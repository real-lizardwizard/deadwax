import Foundation

// The EQ screen's rules (notes/ios-specs/eq.md 3.2, 3.3, 3.5, 3.12, 3.13; 8, question 30), pure so they are tested on
// Linux and the views only draw: which output a page shows and when it may switch, a change while Off turning the EQ
// on, the short setting, Other outputs' order, the line under the curve, a slider's drag, and Info's and Debug's rows.

// MARK: - which output a page shows (3.2)

/// An EQ page and the output it shows (3.2; 8, question 30). The EQ page opened from You or Now Playing's ••• is "the
/// output now", and follows the route - but only that page, only while it is on top, and never under a finger. A
/// page opened from Other outputs stays on its output, and **every page pushed from an EQ page is bound to the output
/// it was opened for** (the presets, Rename and Save as Preset - and slice 4's picker and profile, slice 5's filter
/// editor): "Use for James's AirPods Pro" must do what it says, whatever connects while you read.
public struct EQPage: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// the EQ page of the output now, opened from You or Now Playing's •••: it follows the route
        case followsRoute
        /// one output's EQ page, opened from Other outputs (or slice 5's import's For): it stays on it
        case output
        /// a page pushed from an EQ page: bound to the output it was opened for
        case pushed
    }

    public let kind: Kind
    /// the output it shows (`EQOutputs` key)
    public private(set) var output: String
    /// the output now, as last heard
    public private(set) var route: String?
    /// shown, with nothing pushed or presented over it
    public private(set) var onTop = true
    /// fingers down on its controls (a slider, a stepper's hold, slice 5's handles)
    public private(set) var held = 0

    init(kind: Kind, output: String, route: String?) {
        self.kind = kind
        self.output = output
        self.route = route
    }

    /// The EQ page of the output now (You's row, Now Playing's •••).
    public static func now(route: String) -> EQPage { EQPage(kind: .followsRoute, output: route, route: route) }

    /// One output's EQ page (Other outputs).
    public static func of(_ key: String, route: String?) -> EQPage { EQPage(kind: .output, output: key, route: route) }

    /// A page pushed for `key` - from the EQ page showing it.
    public static func pushed(_ key: String, route: String?) -> EQPage { EQPage(kind: .pushed, output: key, route: route) }

    /// The page may switch to the route now: only the EQ page that follows it, only on top, and never under a finger.
    public var maySwitch: Bool { kind == .followsRoute && onTop && held == 0 }

    /// Its output is the one playing: changes made here are heard.
    public var connected: Bool { route == output }

    /// The route changed (nil: a route with no output, which leaves the last one standing). True when the page
    /// switched to it - for the header's crossfade and VoiceOver's "EQ for …".
    @discardableResult
    public mutating func heard(route new: String?) -> Bool {
        guard let new else { return false }
        route = new
        return follow()
    }

    /// Shown again (Back, or its tab chosen again): it switches now if the route moved while it was covered.
    @discardableResult
    public mutating func shown() -> Bool {
        onTop = true
        return follow()
    }

    /// Covered: a page pushed over it, an alert or a dialog up, another tab chosen.
    public mutating func covered() { onTop = false }

    /// A finger down on one of its controls.
    public mutating func hold() { held += 1 }

    /// That finger up: it switches now if the route moved under it.
    @discardableResult
    public mutating func release() -> Bool {
        held = max(held - 1, 0)
        return follow()
    }

    private mutating func follow() -> Bool {
        guard maySwitch, let route, route != output else { return false }
        output = route
        return true
    }
}

// MARK: - changes (3.2, 3.6, 3.12)

/// What a change to one output's sound depends on: the bank is made from these alone (`EQSettings.bank`), so two
/// settings with the same sound for an output make the same bank for it at any rate.
public struct EQSound: Equatable, Sendable {
    public var on: Bool
    public var correction: [EQFilter]
    public var offsets: EQPreampParts
    public var gains: [Double]
    public var preamp: EQPreampSetting
}

extension EQSettings {
    /// An output's setting - or, never met, the one it starts with: Off (3.12).
    public func setting(for output: EQOutput) -> EQOutputSetting {
        self.output(output.key) ?? EQSettings.newOutput(output, seen: "")
    }

    /// What an output's bank is made from (nil for one never met: Off).
    public func sound(_ key: String) -> EQSound? {
        guard let s = output(key) else { return nil }
        return EQSound(on: s.on, correction: s.correction?.filters ?? [], offsets: s.correction?.preamp ?? .zero,
                       gains: gains(s.tone), preamp: s.preamp)
    }

    /// The route met (3.12): a new output starts Off; one met before has its iOS name, kind and UID brought up to date
    /// and when it was last the output (`seen`, ISO 8601) - yours from Rename kept. True when it was new.
    @discardableResult
    public mutating func met(_ o: EQOutput, at seen: String) -> Bool {
        if let i = outputs.firstIndex(where: { $0.key == o.key }) {
            outputs[i].seen = seen
            outputs[i].name = o.name
            outputs[i].type = o.port
            outputs[i].uid = o.uid
            return false
        }
        outputs.append(EQSettings.newOutput(o, seen: seen))
        return true
    }

    /// A change to an output's sound (3.2): made - an output never met is given its setting first - and, when it
    /// changed anything (or `always`, a choice made: a preset chosen is the EQ turned on, as Apple Music's is), the EQ
    /// turned on if it was Off: "nobody edits an EQ they don't want to hear, and a change you can't hear is a trap" (8,
    /// question 9). True when it turned the EQ on - for VoiceOver's "EQ on".
    @discardableResult
    public mutating func change(_ o: EQOutput, always: Bool = false, _ body: (inout EQOutputSetting) -> Void) -> Bool {
        if output(o.key) == nil { outputs.append(EQSettings.newOutput(o, seen: "")) }
        let i = outputs.firstIndex { $0.key == o.key }!
        let before = outputs[i]
        body(&outputs[i])
        guard always || outputs[i] != before, !outputs[i].on else { return false }
        outputs[i].on = true
        return true
    }

    /// A preset chosen, or yours (3.6) - the EQ on with it. True when it turned the EQ on.
    @discardableResult
    public mutating func choose(_ tone: EQTone, for o: EQOutput) -> Bool {
        change(o, always: true) { $0.tone = tone }
    }

    /// One slider moved (3.5): its band at `gain`, to the step and inside the range, and the tone Custom from then on,
    /// keeping where the others are. Nothing at all when the band is already there. True when it turned the EQ on.
    @discardableResult
    public mutating func setBand(_ band: Int, to gain: Double, for o: EQOutput) -> Bool {
        var gains = gains(setting(for: o).tone)
        guard gains.indices.contains(band) else { return false }
        let snapped = EQGraphic.snapped(gain)
        guard gains[band] != snapped else { return false }
        gains[band] = snapped
        return change(o) { $0.tone = .custom(gains) }
    }

    /// The switch itself.
    public mutating func setOn(_ on: Bool, for o: EQOutput) {
        if output(o.key) == nil { outputs.append(EQSettings.newOutput(o, seen: "")) }
        if let i = outputs.firstIndex(where: { $0.key == o.key }) { outputs[i].on = on }
    }

    /// Rename (3.2): yours, trimmed - or, empty, the name iOS gives it back.
    public mutating func rename(_ key: String, to typed: String) {
        guard let i = outputs.firstIndex(where: { $0.key == key }) else { return }
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        outputs[i].renamed = name.isEmpty || name == outputs[i].name ? nil : name
    }

    /// Forget (3.12): its setting deleted; met again, it starts Off. Never the speaker, which is always there.
    public mutating func forget(_ key: String) {
        guard key != EQOutputs.speaker.key else { return }
        outputs.removeAll { $0.key == key }
    }

    /// Save as Preset (3.6): the output's sliders kept under a name of yours, and the output's tone that preset from
    /// now on (the same gains, so the sound doesn't change). The name's problem, if it has one.
    public mutating func savePreset(_ typed: String, id: String, from o: EQOutput) -> EQNameProblem? {
        switch presetName(typed) {
        case .failure(let problem):
            return problem
        case .success(let name):
            let gains = gains(setting(for: o).tone)
            presets.append(EQYourPreset(id: id, name: name, gains: gains))
            if output(o.key) == nil { outputs.append(EQSettings.newOutput(o, seen: "")) }
            if let i = outputs.firstIndex(where: { $0.key == o.key }) { outputs[i].tone = .yours(id) }
            return nil
        }
    }

    /// Rename Preset (3.6): the same rules, the preset's own name aside.
    public mutating func renamePreset(_ id: String, to typed: String) -> EQNameProblem? {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return nil }
        switch presetName(typed, renaming: id) {
        case .failure(let problem): return problem
        case .success(let name):
            presets[i].name = name
            return nil
        }
    }
}

extension EQOutputSetting {
    /// The output it is, as the screen draws it: its key as kept, its symbol and kind from its port and name.
    public var output: EQOutput {
        let symbol = EQOutputs.output(EQRoutePort(port: type, portType: "", name: name, uid: uid)).symbol
        return EQOutput(key: key, port: type, portType: "", uid: uid, name: shownName, symbol: symbol)
    }
}

// MARK: - what the screens say

/// The line under the curve (3.3), and the colour it is drawn in.
public struct EQLine: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case quiet, amber, danger }

    public var text: String
    public var tone: Tone

    public init(_ text: String, _ tone: Tone = .quiet) {
        self.text = text
        self.tone = tone
    }
}

/// What the unit does now, in Core's words - the engine's state for Info's Debug row (3.1).
public enum EQPlaying: Equatable, Sendable {
    case passing
    /// sections a channel (the largest list), at the unit's rate, with the preamp it plays at
    case filtering(sections: Int, rate: Double, preamp: Double)
    case crossfading
}

public enum EQScreenRules {
    /// Other outputs (3.12): every output the phone has met but the one the page shows, the most recent first - and
    /// the speaker, always there, met or not (last, when it never was). Ties by name.
    public static func others(_ settings: EQSettings, shown: String) -> [EQOutputSetting] {
        var list = settings.outputs.filter { $0.key != shown }
        let speaker = EQOutputs.speaker.key
        if shown != speaker && !list.contains(where: { $0.key == speaker }) {
            list.append(EQSettings.newOutput(EQOutputs.speaker, seen: ""))
        }
        return list.sorted { (a: EQOutputSetting, b: EQOutputSetting) -> Bool in
            if a.seen != b.seen { return a.seen > b.seen }
            if a.shownName != b.shownName { return a.shownName < b.shownName }
            return a.key < b.key
        }
    }

    /// Other outputs is shown only on the page of the output that is connected (3.2).
    public static func showsOthers(_ page: EQPage) -> Bool { page.connected }

    /// "Forget This Output" (3.2): only on the page of an output that isn't connected, has been met, and isn't the
    /// speaker.
    public static func forgets(_ page: EQPage, met: Bool) -> Bool {
        !page.connected && met && page.output != EQOutputs.speaker.key
    }

    /// Other outputs' Forget (3.12): never the speaker.
    public static func forgets(_ key: String) -> Bool { key != EQOutputs.speaker.key }

    /// The output a page bound to `key` draws and changes (3.2): as kept (iOS's name as it was last met, yours from
    /// Rename), else the route's own while it is the output now, the speaker (always there), or as the page last drew
    /// it - one just forgotten keeps its name while it goes. **Never another output**: whatever has connected or been
    /// forgotten meanwhile, a page bound to the AirPods reads and writes the AirPods (the review: the first build fell
    /// back to the output now, so a page whose output had been forgotten would have changed the one playing). An output
    /// none of those knows (Debug's Started with, for one forgotten since) is named by its key.
    public static func output(_ key: String, route: EQOutput, in settings: EQSettings, lastDrawn: EQOutput?) -> EQOutput {
        if let kept = settings.output(key) { return kept.output }
        if key == route.key { return route }
        if key == EQOutputs.speaker.key { return EQOutputs.speaker }
        if let lastDrawn, lastDrawn.key == key { return lastDrawn }
        return EQOutput(key: key, port: .other, portType: "", uid: "", name: key, symbol: "speaker.wave.2")
    }

    /// You's row and Now Playing's subtitle (3.1): the output now's name and its short setting.
    public static func now(_ settings: EQSettings, route: EQOutput) -> (name: String, short: String) {
        let setting = settings.setting(for: route)
        return (setting.output.name, EQWords.shortSetting(setting, in: settings))
    }

    /// The line at the top of a page pushed for an output that isn't connected (3.2) - none on the EQ page itself,
    /// which says "Not connected" its own way (3.3, state 7).
    public static func goneLine(_ page: EQPage, name: String) -> String? {
        page.kind == .pushed && !page.connected ? EQWords.Screen.outputGone(name) : nil
    }

    /// The line under the curve (3.3): the unit not made (state 11, in danger's colour) before anything; Off; on and
    /// flat (the identity bank: no sections at this rate and the level exactly 1); a preamp set by hand, enough or not
    /// (amber); else the automatic preamp - or, at 0, the curve only cuts (it never boosts, 3.2), said plainly as Flat
    /// is, with no preamp (back-home 15a). `top` is the curve's top over the ears before the preamp (only read for a
    /// preamp by hand).
    public static func line(on: Bool, identity: Bool, preamp: EQPreampSetting, played: Double, top: Double,
                            unitNotMade: Bool) -> EQLine {
        if unitNotMade { return EQLine(EQWords.Screen.unitNotMade, .danger) }
        guard on else { return EQLine(EQWords.Screen.off) }
        if identity { return EQLine(EQWords.Screen.flat) }
        switch preamp {
        case .hand(let dB):
            return EQLine(EQWords.Screen.hand(dB, top: top), top + dB > 1e-9 ? .amber : .quiet)
        case .automatic:
            return EQLine(played == 0 ? EQWords.Screen.cutsOnly : EQWords.Screen.automatic(played))
        }
    }

    /// Info's Sound row (3.1): "Bass Boost on James's AirPods Pro, preamp -6.4 dB" - none while Off (8, question 8).
    public static func infoSound(_ setting: EQOutputSetting, in settings: EQSettings, preamp: Double) -> String? {
        EQWords.Info.sound(short: EQWords.shortSetting(setting, in: settings), output: setting.output.name,
                           preamp: preamp, on: setting.on)
    }

    /// Info's Debug row (3.1): what the unit does with the sound now - none before it has started.
    public static func infoDebug(_ playing: EQPlaying?) -> String? {
        switch playing {
        case .none: nil
        case .passing: EQWords.Info.passing
        case .filtering(let sections, let rate, let preamp): EQWords.Info.filtering(filters: sections, rate: rate, preamp: preamp)
        case .crossfading: EQWords.Info.changing
        }
    }

    /// Debug's EQ rows in 3.13's order: Output and Key, the unit's own rows (Unit, Render block, At this rate,
    /// Changes, Started with, Over full scale, Render - as the engine says them) with the Curve after Unit's, At this
    /// rate and Started with in the settings' words where they have them, Start took after Started with,
    /// and Kept last. A row with no value is left out.
    public static func debugRows(unit: [(label: String, value: String)], output: String?, key: String?, curve: String?,
                                 atRate: String?, startedWith: String?, start: String?,
                                 kept: String?) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let output { rows.append(("Output", output)) }
        if let key { rows.append(("Key", key)) }
        var curveIn = false
        for row in unit {
            switch row.label {
            case "At this rate":
                if let curve, !curveIn {
                    rows.append(("Curve", curve))
                    curveIn = true
                }
                rows.append((row.label, atRate ?? row.value))
            case "Started with":
                rows.append((row.label, startedWith ?? row.value))
                if let start { rows.append((EQWords.Debug.startTookLabel, start)) }
            default:
                rows.append(row)
            }
        }
        if let curve, !curveIn { rows.append(("Curve", curve)) }
        if let kept { rows.append(("Kept", kept)) }
        return rows
    }

    /// Debug's Curve row (3.13) for an output's setting at a rate: its filters for both ears and each, its tone bands
    /// that play, its top and where, and the preamp - "Off" while it is.
    public static func debugCurve(_ setting: EQOutputSetting, in settings: EQSettings, rate: Double) -> String {
        guard setting.on else { return EQWords.Debug.curveOff }
        let bank = settings.bank(setting, rate: rate, version: 0)
        let filters = setting.correction?.filters ?? []
        func played(_ channel: EQChannel) -> Int {
            filters.filter { $0.channel == channel && $0.design(rate: rate).outcome == .plays }.count
        }
        let bands = EQGraphic.sections(gains: settings.gains(setting.tone), rate: rate).count
        let offsets = setting.correction?.preamp ?? .zero
        let top = EQResponse.top([EQResponse.Ear(sections: bank.left, offset: offsets.left),
                                  EQResponse.Ear(sections: bank.right, offset: offsets.right)], rate: rate)
        let automatic = setting.preamp == .automatic
        return EQWords.Debug.curve(both: played(.all), left: played(.left), right: played(.right), bands: bands,
                                   top: top.db, at: top.at, preamp: bank.preamp, automatic: automatic)
    }

    /// Debug's At this rate (3.13), with what the setting leaves out above the rate's top: "48 kHz: 20 sections a
    /// channel; 1 left out (above 23.5 kHz)".
    public static func debugAtRate(_ setting: EQOutputSetting, in settings: EQSettings, rate: Double,
                                   sections: Int) -> String {
        guard setting.on else { return EQWords.Debug.atRate(rate, sections: sections, leftOut: 0) }
        let filters = setting.correction?.filters ?? []
        let bands = settings.gains(setting.tone).enumerated().map { EQGraphic.filter(band: $0.offset, gain: $0.element) }
        let above = (filters + bands).filter { $0.design(rate: rate).outcome == .above }.count
        return EQWords.Debug.atRate(rate, sections: sections, leftOut: above)
    }
}

// MARK: - the sliders (3.5, 3.14, 3.15)

/// A slider's drag and its steps (3.5): it takes hold wherever the knob is - a touch never makes it jump - and follows
/// the finger's movement, 24 dB over the track's 200 pt, rounded to 0.5 dB; it moves nothing until the finger has
/// gone 6 pt up or down; a light tick as it crosses into 0 dB. VoiceOver's swipe moves it 1 dB.
public enum EQSliderRules {
    /// the track's height (pt): the knob's centre travels it, +12 dB at its top
    public static let track: Double = 200
    /// how far up or down a finger goes before the knob follows it (pt)
    public static let engage: Double = 6
    /// VoiceOver's step (dB)
    public static let spoken: Double = 1

    static var span: Double { EQGraphic.range.upperBound - EQGraphic.range.lowerBound }

    /// The value a drag gives: where it took hold, moved by the finger (`dy` down, in pt), to the step and inside the
    /// range.
    public static func value(from start: Double, dy: Double, track: Double = track) -> Double {
        EQGraphic.snapped(start - dy / track * span)
    }

    /// A drag moves the knob once it has gone `engage` up or down; sideways moves nothing.
    public static func engaged(dy: Double) -> Bool { abs(dy) >= engage }

    /// The tick (3.5): the value crossing into 0 dB.
    public static func ticks(from old: Double, to new: Double) -> Bool { new == 0 && old != 0 }

    /// The knob's place on the track: 0 at its top (+12 dB) to 1 at its foot (-12 dB).
    public static func place(_ gain: Double) -> Double {
        (EQGraphic.range.upperBound - min(max(gain, EQGraphic.range.lowerBound), EQGraphic.range.upperBound)) / span
    }

    /// VoiceOver's swipe up or down (3.14): `step` dB, inside the range - 1 for a slider, 0.5 for a stepper row.
    public static func adjusted(_ gain: Double, up: Bool, step: Double = spoken) -> Double {
        min(max(gain + (up ? step : -step), EQGraphic.range.lowerBound), EQGraphic.range.upperBound)
    }
}

/// One finger's drag on a slider (3.5): the value it took hold at, and - once the finger has gone `engage` up or down -
/// the point it engaged at, kept for the rest of the drag. The knob follows the finger's movement from there, so
/// taking hold never makes it jump, and nor does the finger passing back over where it came down (the review: the
/// first build took the engaging side from the finger's side of that point at every move, so crossing it moved the knob
/// 12 pt - 1.44 dB - at once).
public struct EQSliderDrag: Equatable, Sendable {
    /// the band's value when the finger came down
    public let start: Double
    /// where the drag engaged (pt from where it came down, down positive) - nil until it has
    public private(set) var engagedAt: Double?

    public init(start: Double) {
        self.start = start
    }

    public var engaged: Bool { engagedAt != nil }

    /// The value for the finger's movement so far (`dy` pt, down positive), to the step and inside the range - nil
    /// while it hasn't gone `engage` up or down yet.
    public mutating func value(dy: Double, track: Double = EQSliderRules.track) -> Double? {
        if engagedAt == nil {
            guard EQSliderRules.engaged(dy: dy) else { return nil }
            engagedAt = dy > 0 ? EQSliderRules.engage : -EQSliderRules.engage
        }
        return EQSliderRules.value(from: start, dy: dy - (engagedAt ?? 0), track: track)
    }
}
