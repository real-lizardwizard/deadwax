import AVFAudio
import DeadwaxAudio
import DeadwaxCore
import Foundation
import Observation
import SwiftUI
import UIKit

/// The EQ as this phone keeps it (notes/ios-specs/eq.md 3, 4; slice 3): every output's setting and your presets, the
/// route observed, and the banks put in - the one place the screens change the EQ and the engine's start reads it.
/// Made once in DeadwaxApp beside PlayerModel and put in the environment; PlayerModel hands it the engine when it makes
/// one (`attach`).
///
/// - **The settings** are read once at launch (EQStore) and written 0.5 s after the last change - a drag once, at its
///   end - and as the app goes to the back.
/// - **The route** (1.8, 3.12): `routeChangeNotification`, heard on the main queue, makes the output now - recorded as
///   met (a new one starts Off), the host told, a new version published.
/// - **Every change goes through Core's EQStartDesk** (slice 2's review): one version counter for changes, routes and
///   starts, raised before the host's rate is read, so the bank for the rate the unit runs at always lands; and every
///   output's bank made ahead, off the main thread, for the rates it starts at - so the engine's start only looks its
///   curve up (`startHook`).
/// - **Debug's Muffle** (slice 2's test curve) goes through the same door: on, the test curve on its own output; off,
///   the route's own curve. Off at each launch and whenever Debug closes, kept nowhere.
@MainActor
@Observable
final class EQModel {
    /// Every output met and your presets, as kept.
    private(set) var settings: EQSettings
    /// The output now.
    private(set) var route: EQOutput
    /// The route's ports, for Debug's Output row.
    private(set) var ports: [EQRoutePort]
    /// The engine's own words when its unit couldn't be made (3.3, state 11) - nil while it plays, or before there is
    /// an engine.
    private(set) var unitProblem: String?
    /// Debug's Kept row: the file's size, or what was set aside.
    private(set) var bytes = 0
    private(set) var setAside: String?

    /// Debug's "Muffle what plays" (eq.md 5.2, check 0).
    var muffle: Bool {
        get { muffleOn }
        set {
            guard newValue != muffleOn else { return }
            muffleOn = newValue
            publish()
        }
    }

    private var muffleOn = false

    /// Core's book of versions and banks made ahead, shared with the engine's queue.
    nonisolated let desk: EQStartDesk
    @ObservationIgnored private weak var host: EQHost?
    private let store: EQStore
    @ObservationIgnored private var writable: Bool
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    /// Fingers down on an EQ page's controls: the file is written once they're all up.
    @ObservationIgnored private var held = 0
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Waiting for the phone's first unlock, when eq.json couldn't be opened at launch.
    @ObservationIgnored private var unlock: NSObjectProtocol?
    /// Each output's curve as last drawn, and what it was made from.
    @ObservationIgnored private var drawn: [String: (sound: EQSound?, rate: Double, drawing: EQDrawing)] = [:]
    /// Each output as last read from the settings: a page whose output has just been forgotten keeps its name while it
    /// goes.
    @ObservationIgnored private var known: [String: EQOutput] = [:]

    init(store: EQStore = EQStore()) {
        self.store = store
        let loaded = store.load()
        settings = loaded.settings
        setAside = loaded.setAside
        bytes = loaded.bytes
        writable = loaded.writable
        let nowPorts = EQRouteReader.ports()
        ports = nowPorts
        route = EQOutputs.output(nowPorts) ?? EQOutputs.speaker
        desk = EQStartDesk(muffleKey: EQTestCurve.key, muffleBank: { (rate: Double, version: Int) -> EQBank in
            EQTestCurve.bank(on: true, rate: rate, version: version)
        }, clock: { AVAudioTime.seconds(forHostTime: mach_absolute_time()) })
        if settings.met(route, at: Self.now()) { dirty = true }
        _ = desk.take(settings, muffle: false)
        makeAhead()
        if dirty { scheduleSave() }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                          object: AVAudioSession.sharedInstance(),
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }
        if loaded.locked {
            unlock = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.unlocked() }
            }
            // an unlock between the read above and the observer would never be heard: read again now it is there
            unlocked()
        }
    }

    /// The app came to the front: if eq.json couldn't be opened at launch and nothing has said the phone unlocked since
    /// (a suspended app may not hear it), read it now - the phone is unlocked if the app is in front.
    func becameActive() {
        if unlock != nil { unlocked() }
    }

    /// The phone unlocked after a launch that couldn't open eq.json (a background launch since it started): read now,
    /// and the route met again on what was kept. Nothing while it still can't be opened.
    private func unlocked() {
        let loaded = store.load()
        guard !loaded.locked else { return }
        if let unlock { NotificationCenter.default.removeObserver(unlock) }
        unlock = nil
        settings = loaded.settings
        setAside = loaded.setAside
        bytes = loaded.bytes
        writable = loaded.writable
        drawn = [:]
        settings.met(route, at: Self.now())
        changed()
        makeAhead()
    }

    // MARK: the engine

    /// The engine made (PlayerModel.ensureLink): its host is where banks go, and its start puts the output's curve in.
    func attach(_ engine: PlaybackEngine) {
        host = engine.eq
        engine.eqStart = Self.startHook(desk)
        readUnit()
        publish()
    }

    /// The EQ's start (eq.md 1.8), on the engine's queue between prepare and start: the output now, read from the route
    /// there and then - an output EQModel hasn't heard of yet is Off - and its curve at the unit's rate, made ahead, put
    /// in before the first sample. Made outside the main actor, as PlayerModel's `lead` is.
    nonisolated static func startHook(_ desk: EQStartDesk) -> (EQHost, Double, Int) -> Void {
        { (host: EQHost, rate: Double, _: Int) -> Void in
            desk.start(EQRouteReader.output().key, rate: rate, host: Self.taker(host))
        }
    }

    nonisolated static func taker(_ host: EQHost) -> EQTaker {
        EQTaker(setOutput: { host.setOutput($0) }, publish: { host.publish($0) }, rate: { host.rate })
    }

    /// The unit's state, for Debug (read under the host's own lock).
    func status() -> EQUnitStatus? { host?.status() }

    /// What the last start spent putting its curve in (Debug's Start took).
    var lastStart: EQStartTime? { desk.lastStart }

    // MARK: the route (1.8, 3.12)

    private func routeChanged() {
        let nowPorts = EQRouteReader.ports()
        let output = EQOutputs.output(nowPorts) ?? EQOutputs.speaker
        ports = nowPorts
        guard output != route else { return }
        let moved = output.key != route.key
        route = output
        settings.met(output, at: Self.now())
        changed(save: true)
        if moved { makeAhead() }
    }

    /// When an output was last the output now: ISO 8601, to the second (4).
    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    // MARK: what the screens read

    /// An output's setting - or, never met, the one it would start with: Off.
    func setting(_ output: EQOutput) -> EQOutputSetting { settings.setting(for: output) }

    /// The output a key is (Core's EQScreenRules.output): as kept, the route's own, the speaker - or, just forgotten, as
    /// it was last drawn. Never another output's: a page bound to the AirPods changes the AirPods. Each answer is
    /// remembered, the route's included, so a page whose output goes keeps its name while it goes.
    func output(_ key: String) -> EQOutput {
        let output = EQScreenRules.output(key, route: route, in: settings, lastDrawn: known[key])
        known[key] = output
        return output
    }

    /// The rate an output's curve is drawn at: the unit's own while it is the output now, 48 kHz while it isn't
    /// connected (3.3, state 7).
    func rate(_ key: String) -> Double {
        guard key == route.key else { return 48_000 }
        return host?.rate ?? EQRouteReader.rate()
    }

    /// An output's curve (3.4), made again only when its sound or rate has changed.
    func drawing(_ key: String) -> EQDrawing {
        let output = self.output(key)
        let sound = settings.sound(key)
        let rate = rate(key)
        if let kept = drawn[key], kept.sound == sound, kept.rate == rate { return kept.drawing }
        let drawing = EQDrawing.make(setting(output), in: settings, rate: rate)
        drawn[key] = (sound, rate, drawing)
        return drawing
    }

    /// The line under an output's curve (3.3).
    func line(_ key: String) -> EQLine {
        let setting = self.setting(output(key))
        let drawing = self.drawing(key)
        return EQScreenRules.line(on: setting.on, identity: drawing.identity, preamp: setting.preamp,
                                  played: drawing.preamp, top: drawing.top, unitNotMade: unitProblem != nil)
    }

    /// You's row and Now Playing's subtitle: the output now's name and its short setting.
    var now: (name: String, short: String) { EQScreenRules.now(settings, route: route) }

    /// Info's Sound row: "Bass Boost on James's AirPods Pro, preamp -6.4 dB" - none while Off.
    var infoSound: String? {
        EQScreenRules.infoSound(setting(route), in: settings, preamp: drawing(route.key).preamp)
    }

    /// Info's Debug row: what the unit does with the sound now.
    var infoDebug: String? {
        guard let status = host?.status() else { return nil }
        return EQScreenRules.infoDebug(Self.playing(status, preamp: host?.newest?.preamp ?? 0))
    }

    static func playing(_ status: EQUnitStatus, preamp: Double) -> EQPlaying? {
        switch status.mode {
        case .passing: return .passing
        case .filtering:
            guard let rate = status.rate else { return nil }
            return .filtering(sections: status.sections ?? 0, rate: rate, preamp: preamp)
        case .crossfading: return .crossfading
        case .notMade, .stopped, .waiting: return nil
        }
    }

    /// Debug's EQ rows (3.13): the settings' among the unit's.
    func debugRows(_ status: EQUnitStatus?) -> [(label: String, value: String)] {
        let unit = status?.rows.map { (label: $0.label, value: $0.value) }
            ?? [(label: "Unit", value: EQWords.Debug.noEngine)]
        let key = muffleOn ? EQTestCurve.key : route.key
        let setting = self.setting(route)
        let rate = host?.rate ?? EQRouteReader.rate()
        var startedWith: String?
        if let started = status?.started, started.secondsBefore != nil, !started.identity, let k = started.key,
           k != EQTestCurve.key, let seconds = started.secondsBefore {
            startedWith = EQWords.Debug.startedWith(output(k).name, msBefore: seconds * 1_000)
        }
        let kept = setAside.map(EQWords.Debug.setAside)
            ?? EQWords.Debug.kept(outputs: settings.outputs.count, presets: settings.presets.count, bytes: bytes)
        return EQScreenRules.debugRows(
            unit: unit, output: EQWords.Debug.output(ports), key: key,
            curve: muffleOn ? nil : EQScreenRules.debugCurve(setting, in: settings, rate: rate),
            atRate: status?.rate == nil || muffleOn ? nil
                : EQScreenRules.debugAtRate(setting, in: settings, rate: rate, sections: status?.sections ?? 0),
            startedWith: startedWith, start: desk.lastStart?.words, kept: kept)
    }

    // MARK: changes (3.2, 3.5, 3.6, 3.12)

    /// The switch.
    func setOn(_ on: Bool, for output: EQOutput) {
        settings.setOn(on, for: output)
        changed()
    }

    /// A preset chosen, or yours: the EQ on with it.
    func choose(_ tone: EQTone, for output: EQOutput) {
        let turnedOn = settings.choose(tone, for: output)
        changed()
        if turnedOn { Self.say(EQWords.Said.on) }
    }

    /// One slider moved: the tone Custom, the EQ on - and the sound follows it, a bank a value.
    func setBand(_ band: Int, to gain: Double, for output: EQOutput) {
        let before = settings
        let turnedOn = settings.setBand(band, to: gain, for: output)
        guard settings != before else { return }
        changed()
        if turnedOn { Self.say(EQWords.Said.on) }
    }

    /// Rename (3.2): an output never met (the speaker, in Other outputs) is kept first, as it would start - so the name
    /// has somewhere to go - without being counted as met.
    func rename(_ key: String, to name: String) {
        if settings.output(key) == nil { settings.outputs.append(EQSettings.newOutput(output(key), seen: "")) }
        settings.rename(key, to: name)
        changed()
    }

    func forget(_ key: String) {
        settings.forget(key)
        drawn[key] = nil
        changed()
    }

    /// Save as Preset: the name's problem, if it has one.
    func savePreset(_ name: String, from output: EQOutput) -> EQNameProblem? {
        let problem = settings.savePreset(name, id: "p-" + UUID().uuidString.lowercased(), from: output)
        if problem == nil { changed() }
        return problem
    }

    func renamePreset(_ id: String, to name: String) -> EQNameProblem? {
        let problem = settings.renamePreset(id, to: name)
        if problem == nil { changed() }
        return problem
    }

    func deletePreset(_ id: String) {
        settings.deletePreset(id)
        changed()
    }

    // MARK: AutoEq (3.7)

    /// A correction chosen: AutoEq's profile used (the EQ turned on if it was Off - "EQ on"), or None. Crossfaded, as
    /// every change is.
    func use(_ correction: EQCorrection?, for output: EQOutput) {
        let before = settings
        let turnedOn = settings.use(correction, for: output)
        guard settings != before else { return }
        changed()
        if turnedOn { Self.say(EQWords.Said.on) }
    }

    /// Each output's suggestion this launch, once answered: what deadwax's search for its cleaned name offers, and the
    /// answer itself, which the picker opens with. Kept in memory only - asked again at the next launch.
    private(set) var suggestions: [String: (suggestion: EQSuggestion, query: String, answer: AutoEqResults)] = [:]
    /// The outputs whose suggestion is being asked for.
    @ObservationIgnored private var asking: Set<String> = []

    /// An output's suggestion, when it was asked for and answered this launch.
    func suggestion(_ key: String) -> EQSuggestion? { suggestions[key]?.suggestion }

    /// The EQ page shows an output (3.7): its suggestion asked for once a launch - a Bluetooth or USB output with no
    /// correction, not put away with Not now, deadwax in reach. A failure keeps nothing, so the next time the page
    /// shows it is asked again; an answer stands for the launch.
    func askSuggestion(for output: EQOutput, client: DeadwaxClient?, online: Bool) {
        let key = output.key
        let setting = self.setting(output)
        guard online, let client, suggestions[key] == nil, !asking.contains(key),
              EQSuggestionRules.asks(output, setting),
              let query = AutoEqAsk.query(EQSuggestionRules.query(output, setting)) else { return }
        asking.insert(key)
        Task { [weak self] () async -> Void in
            let answer = try? await client.autoEq(search: query)
            guard let self else { return }
            self.asking.remove(key)
            guard let answer else { return }
            self.suggestions[key] = (EQSuggestion.of(query, answer: answer), query, answer)
        }
    }

    /// The picker's start (3.7): the suggestion's query and deadwax's answer to it, when it was a choice - so the field
    /// opens holding the cleaned name, already searched.
    func searched(_ key: String) -> (query: String, answer: AutoEqResults)? {
        guard let kept = suggestions[key], kept.suggestion.searched != nil else { return nil }
        return (kept.query, kept.answer)
    }

    /// The suggestion's row was drawn ("shown"), or put away for good ("Not now") - kept in the file, nothing heard
    /// differently, so no new curve is published.
    func mark(_ suggestion: EQOutputSetting.Suggestion, for output: EQOutput) {
        guard settings.mark(suggestion, for: output) else { return }
        dirty = true
        scheduleSave()
    }

    /// A finger down on an EQ page's control: the file waits for it.
    func hold() { held += 1 }

    func release() {
        held = max(held - 1, 0)
        if held == 0 && dirty { scheduleSave() }
    }

    /// The app went to the back: the settings written now, if anything waits.
    func movedToBackground() {
        if dirty { save() }
    }

    // MARK: publishing and keeping

    private func changed(save: Bool = true) {
        publish()
        dirty = true
        if save { scheduleSave() }
    }

    /// A new version, then the output now's curve at the unit's rate put in (nothing before the engine's first start:
    /// the start puts it in). The route is read again first, so a change never lands on an output that has just gone.
    private func publish() {
        let nowPorts = EQRouteReader.ports()
        let output = EQOutputs.output(nowPorts) ?? EQOutputs.speaker
        if output.key != route.key {
            ports = nowPorts
            route = output
            settings.met(output, at: Self.now())
            dirty = true
        }
        guard let host else {
            _ = desk.take(settings, muffle: muffleOn)
            return
        }
        desk.changed(settings, route: route.key, muffle: muffleOn, host: Self.taker(host))
        readUnit()
    }

    private func readUnit() {
        if case .notMade(let words)? = host?.status().mode { unitProblem = words } else { unitProblem = nil }
    }

    /// Every output's banks still to make, made off the main thread.
    private func makeAhead() {
        let desk = self.desk
        let keys = [route.key] + settings.outputs.map(\.key).filter { $0 != route.key }
        Task.detached(priority: .utility) { desk.makeAhead(keys) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.held == 0 else { return }
            self.save()
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = nil
        dirty = false
        makeAhead()
        guard writable, let written = store.save(settings) else { return }
        bytes = written
    }

    /// VoiceOver hears it (3.14): "EQ on", "EQ for James's AirPods Pro".
    static func say(_ words: String) {
        Notice.announce(words)
    }
}
