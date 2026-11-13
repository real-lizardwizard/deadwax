import AVFAudio
import DeadwaxAudio
import DeadwaxCore
import DeadwaxTurntable
import Foundation
import Observation
import QuartzCore
import UIKit
import os

// The turntable's deck on the phone (notes/ios-specs/turntable.md 2.1, 2.6, 3.3-3.5, 4.4-4.6, 6.2): Core's DeckRules
// and TurntablePress over the player, the deck engine (DeadwaxAudio), its windows, the `deck.position` queue, the
// clock's timers and display link, and the session's notifications. Made once, beside PlayerModel, for the app's run:
// Now Playing is a full-screen cover whose view goes away as it closes, and the web's deck outlives its sheet's close
// (it is told it isn't showing, so a coast still hands the song back). Its rules are made at the first turntable and
// let go when the look switches to the cover (the web's Turntable unmounting); its engine is kept, stopped and its
// voice reset, so the EQ's host stays the one EQModel was given.

/// The song's engine as the turntable reads it (3.4, 2.6): its position and its last start, read off the main thread
/// by the `deck.position` queue - nothing that changes it.
protocol DeckEngineReading: AnyObject {
    func position() -> EnginePosition?
    func debug() -> EngineDebug
}

extension PlaybackEngine: DeckEngineReading {}

/// The `deck.position` queue (2.6): from a resume the deck asked for, the song's engine read at 120 Hz on a queue of
/// its own, its newest reading kept behind an unfair lock for the frame - which never waits on the engine's queue,
/// busiest exactly then (the resume opening the file, decoding, starting the output). A reading older than 50 ms
/// counts as none. At the run's end it reads the engine's last start, the handover's actual `E` (3.5), and when that
/// read began: the main thread takes it as the let-go's once it has seen the start before then (HandoverTiming).
final class DeckPositionFeed: @unchecked Sendable {
    struct Reading {
        var seconds: Double
        /// host seconds of the read's end
        var at: Double
    }

    static let fresh = 0.05
    static let hz = 120.0

    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let made = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        made.initialize(to: os_unfair_lock())
        return made
    }()
    private let queue = DispatchQueue(label: "deadwax.deck.position", qos: .utility)
    private var reading: Reading?
    private var until = 0.0
    private var looping = false
    private var worst = 0.0
    private var started: Double?
    /// when the read of `started` began
    private var startedReadAt = -Double.infinity

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    private func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body()
    }

    /// Read `engine` for `seconds` more.
    func run(_ engine: DeckEngineReading, for seconds: Double) {
        let end = CACurrentMediaTime() + seconds
        let start: Bool = locked { () -> Bool in
            until = Swift.max(until, end)
            if looping { return false }
            looping = true
            worst = 0
            started = nil
            startedReadAt = -Double.infinity
            return true
        }
        guard start else { return }
        queue.async { [weak self] in self?.loop(engine) }
    }

    private func loop(_ engine: DeckEngineReading) {
        while true {
            let began = CACurrentMediaTime()
            let stop: Bool = locked { () -> Bool in
                if began < until { return false }
                looping = false
                return true
            }
            if stop { break }
            let read = engine.position()
            let ended = CACurrentMediaTime()
            locked { () -> Void in
                if let read { reading = Reading(seconds: read.seconds, at: ended) }
                worst = Swift.max(worst, ended - began)
            }
            let rest = 1 / Self.hz - (ended - began)
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
        }
        let readAt = CACurrentMediaTime()
        let last = engine.debug().lastStartSeconds
        locked { () -> Void in
            started = last
            startedReadAt = readAt
        }
    }

    /// The newest reading, when fresh.
    func latest(now: Double) -> Reading? {
        locked { () -> Reading? in
            guard let reading, now - reading.at <= Self.fresh else { return nil }
            return reading
        }
    }

    /// The longest the engine took to answer during the last run, and its last start as read at that run's end and
    /// when that read began (nil and -infinity while one runs).
    var facts: (worst: Double, started: Double?, readAt: Double) { locked { (worst, started, startedReadAt) } }
}

/// DeckRules' and TurntablePress's world (3.3, 3.4): the Core protocols - written for Linux too, so no actor - over the
/// DeckController, which is the main actor's. Every call comes on the main thread: the rules' and the press's calls are
/// made from the main thread's touches, timers, frames and answers.
final class DeckWorld: DeckHost, DeckClock, PressHost {
    weak var controller: DeckController?

    private func on<T: Sendable>(_ fallback: T, _ body: @MainActor (DeckController) -> T) -> T {
        MainActor.assumeIsolated { () -> T in
            guard let controller else { return fallback }
            return body(controller)
        }
    }

    // DeckHost
    func song() -> DeckSong? { on(nil) { (c: DeckController) -> DeckSong? in c.deckSong() } }
    func playing() -> Bool { on(false) { (c: DeckController) -> Bool in c.player.isPlaying } }
    func position() -> Double { on(0) { (c: DeckController) -> Double in c.songPosition() } }
    func onPosition(_ listener: @escaping (Double) -> Void) -> () -> Void {
        let id = MainActor.assumeIsolated { () -> Int in controller?.listen(listener) ?? 0 }
        return { [weak self] in
            MainActor.assumeIsolated { () -> Void in self?.controller?.unlisten(id) }
        }
    }
    func hold() { on(()) { (c: DeckController) -> Void in c.holdSong() } }
    func resume() { on(()) { (c: DeckController) -> Void in c.resumeSong() } }
    func turnFace(_ degrees: Double) { on(()) { (c: DeckController) -> Void in c.turnFace(degrees) } }
    func show(_ at: Double?, scrubbing: Bool) { on(()) { (c: DeckController) -> Void in c.show(at, scrubbing: scrubbing) } }
    func grabbed() { on(()) { (c: DeckController) -> Void in c.press?.grabbed() } }
    func soundReady() -> Bool { on(false) { (c: DeckController) -> Bool in TurntableScreen.soundReady(c.engineState) } }
    func voiceMade() -> Bool { on(false) { (c: DeckController) -> Bool in c.voiceMade } }
    func window(_ song: DeckSong, from: Double, seconds: Double, answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void) {
        MainActor.assumeIsolated { () -> Void in controller?.window(song, from: from, seconds: seconds, answer: answer) }
    }
    func post(_ message: DeckPost) { on(()) { (c: DeckController) -> Void in c.post(message) } }
    func sleepAudio() { on(()) { (c: DeckController) -> Void in c.evaluate() } }
    func closeAudio() { on(()) { (c: DeckController) -> Void in c.closeAudio() } }

    // DeckClock
    func now() -> Double { CACurrentMediaTime() * 1_000 }
    func stamp(_ ms: Double) -> Double { ms / 1_000 }
    func after(_ ms: Double, _ run: @escaping () -> Void) -> Int {
        MainActor.assumeIsolated { () -> Int in controller?.after(ms, run) ?? 0 }
    }
    func cancel(_ id: Int) { on(()) { (c: DeckController) -> Void in c.cancelTimer(id) } }
    func frame(_ run: @escaping (Double) -> Void) -> Int {
        MainActor.assumeIsolated { () -> Int in controller?.frame(run) ?? 0 }
    }
    func cancelFrame(_ id: Int) { on(()) { (c: DeckController) -> Void in c.cancelFrame(id) } }

    // PressHost (playing() and now() are DeckHost's and DeckClock's)
    func length() -> Double { on(0) { (c: DeckController) -> Double in c.player.duration } }
    func track() -> String { on("") { (c: DeckController) -> String in c.player.current?.track.id ?? "" } }
    func seek(_ seconds: Double) { on(()) { (c: DeckController) -> Void in c.player.seek(to: seconds) } }
    func toggle() { on(()) { (c: DeckController) -> Void in c.player.toggle() } }
    func wake() { on(()) { (c: DeckController) -> Void in c.wake() } }
    func box() -> StageBox { on(StageBox(left: 0, top: 0, width: 0, height: 0)) { (c: DeckController) -> StageBox in c.box } }
    func drawnAt() -> Double { on(0) { (c: DeckController) -> Double in c.player.shownPosition } }
    func shown() -> Double { on(0) { (c: DeckController) -> Double in c.shownTime } }
    func flac() -> Bool { on(false) { (c: DeckController) -> Bool in c.deckSong()?.flac ?? false } }
    func noAudio() -> Bool { on(false) { (c: DeckController) -> Bool in TurntableScreen.noAudio(c.engineState) } }
}

/// CADisplayLink's target, so the link doesn't hold the controller.
private final class DeckFrameTarget: NSObject {
    weak var controller: DeckController?
    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { () -> Void in controller?.tick(link) }
    }
}

@MainActor
@Observable
final class DeckController {
    // MARK: what the screen reads

    /// The time line in the scrubber's row (2.1, 2.9) - set only when its words change.
    private(set) var timeLine = ""
    /// The silent line over the plinth's foot (2.8) - from the song's first silent turn until it changes.
    private(set) var silentLine: String?
    /// The arm's value for VoiceOver.
    private(set) var armValue = ""
    /// You > Playback's two settings (6.1), kept on this phone under the web's keys - read at launch, written on change.
    var opensAs: TurntableSettings.Look {
        didSet { UserDefaults.standard.set(TurntableSettings.stored(opensAs), forKey: TurntableSettings.opensAsKey) }
    }
    var windDown: Bool {
        didSet {
            UserDefaults.standard.set(TurntableSettings.stored(windDown: windDown), forKey: TurntableSettings.windDownKey)
            rules?.setWindDown(windDown)
        }
    }

    // MARK: kept

    @ObservationIgnored let player: PlayerModel
    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let files: SongFiles
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private weak var eq: EQModel?
    @ObservationIgnored private let world = DeckWorld()
    @ObservationIgnored private(set) var rules: DeckRules<PlatformMaths>?
    @ObservationIgnored private(set) var press: TurntablePress<PlatformMaths>?
    @ObservationIgnored private var engine: DeckEngine?
    @ObservationIgnored private let windows = DeckWindows()
    @ObservationIgnored private let feed = DeckPositionFeed()
    @ObservationIgnored private let trig = TurntableTrig(PlatformMaths())
    @ObservationIgnored private weak var view: TurntableDeckUIView?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // the screen
    @ObservationIgnored private var open = false
    @ObservationIgnored private var turntableShown = false
    /// the scene is in front: read as the deck is made, followed by the app's notifications after
    @ObservationIgnored private var active = false
    @ObservationIgnored private var showing = false
    @ObservationIgnored private(set) var box = StageBox(left: 0, top: 0, width: 0, height: 0)
    @ObservationIgnored private var deckAngle = 0.0
    @ObservationIgnored private var deckShown: (at: Double, scrubbing: Bool)?
    @ObservationIgnored private(set) var shownTime = 0.0
    @ObservationIgnored private var contrast = UIAccessibility.isDarkerSystemColorsEnabled
    @ObservationIgnored private var reduced = UIAccessibility.isReduceMotionEnabled
    @ObservationIgnored private var cover: CGImage?
    @ObservationIgnored private var coverFor: String?
    @ObservationIgnored private var art: CGImage?
    @ObservationIgnored private var artFor: String?
    @ObservationIgnored private var artFailed: Set<String> = []
    /// the discs' CD art fetched this run, the newest last - a few only, each a decoded picture of the face's size
    @ObservationIgnored private var artKept: [String: CGImage] = [:]
    @ObservationIgnored private var artOrder: [String] = []
    private static let artKeptMost = 8

    // the player as last seen
    @ObservationIgnored private var songID = ""
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var lastPosition = -1.0
    @ObservationIgnored private var pausedAt: Double?
    @ObservationIgnored private var listeners: [Int: (Double) -> Void] = [:]
    @ObservationIgnored private var nextListener = 1
    @ObservationIgnored private var delivered = 0.0

    // the clock
    @ObservationIgnored private var timers: [Int: DispatchSourceTimer] = [:]
    @ObservationIgnored private var nextTimer = 1
    @ObservationIgnored private var frames: [Int: (Double) -> Void] = [:]
    @ObservationIgnored private var nextFrame = 1
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let frameTarget = DeckFrameTarget()
    @ObservationIgnored private var ticker: Timer?
    /// how late the timer running now fired - the led resume's lateness, when it is the one that asks it
    @ObservationIgnored private var firingLate: Double?

    // the engine
    /// a start that threw: the record silent until a route change, the deck made again, an interruption's end, or a
    /// press 2 s after it (DeckStartFailure)
    @ObservationIgnored private var failure = DeckStartFailure()
    @ObservationIgnored private var airPlay = false
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var routeKey = ""
    @ObservationIgnored private var lastLoud = -Double.infinity
    @ObservationIgnored private var lastSoundPost = -Double.infinity

    // Debug's facts (6.2)
    @ObservationIgnored private var from: DeckPhoneFacts.From?
    @ObservationIgnored private var windowMade: (took: Double, seconds: Double, rate: Double)?
    @ObservationIgnored private var handover: DeckPhoneFacts.Handover?
    /// the let-go's kind, position and route, the engine's starts seen by then, and when it was - for the actual `E`
    @ObservationIgnored private var handoverKind: (local: Bool, position: Double, route: String, starts: Int, at: Double)?
    /// the song's engine's starts, counted from its phase as the player says it here - never asked of its queue
    @ObservationIgnored private var engineStarts = HandoverStarts()
    @ObservationIgnored private var localStarts: [String: [Double]] = [:]
    @ObservationIgnored private var streamStarts: [String: [(position: Double, seconds: Double)]] = [:]
    @ObservationIgnored private var touchCount = (samples: 0.0, events: 0.0)
    @ObservationIgnored private var touchSince: Double?
    @ObservationIgnored private var touches: (samples: Double, events: Double)?
    @ObservationIgnored private var slow: (count: Int, worst: Double)?
    @ObservationIgnored private var sound = DeckReport.DeckHealth()

    /// A sound this recent (the voice's report of one, or a message that makes one) is the record sounding (4.6).
    static let soundingFor = 0.15
    /// How often the run rule and the voice's reports are looked at while there is a deck, frames or none.
    static let tickSeconds = 0.1
    /// How long the `deck.position` queue reads after the deck's resume: HANDOVER_MAX_S and a second (3.5).
    static let feedSeconds = DeckConstants.handoverMaxS + 1
    /// The last five starts of each kind, per route (3.5).
    static let startsKept = 5
    /// deck.ts DEEPEST_GAIN_SAID.
    static let deepestGainSaid = 1e-6

    init(player: PlayerModel, server: ServerModel, files: SongFiles, reachability: Reachability, eq: EQModel) {
        self.player = player
        self.server = server
        self.files = files
        self.reachability = reachability
        self.eq = eq
        opensAs = TurntableSettings.opensAs(UserDefaults.standard.string(forKey: TurntableSettings.opensAsKey))
        windDown = TurntableSettings.windDown(UserDefaults.standard.string(forKey: TurntableSettings.windDownKey))
        world.controller = self
        frameTarget.controller = self
        observe()
        watchPlayer()
    }

    // MARK: Now Playing's calls

    /// Now Playing is up: the turntable shows on it, or the cover (or the lyrics) does - which lets the deck go, as the
    /// web's Turntable unmounts (destroy, deck.ts:1377: a song the hand took from playing plays on).
    func screen(turntable: Bool) {
        open = true
        turntableShown = turntable
        if turntable { make() } else { destroy() }
        applyShowing()
    }

    /// Now Playing went away: the deck isn't showing, but lives on - a coast or a run back to speed still ends by
    /// handing the song back (2.1). A disc that had no CD art is asked again at the next opening, as the web's is.
    func closed() {
        open = false
        artFailed.removeAll()
        applyShowing()
    }

    /// The plinth's view, laid out at `layout` (its own coordinates are the press's box).
    func attach(_ view: TurntableDeckUIView, layout: TurntableLayout) {
        self.view = view
        box = StageBox(left: 0, top: 0, width: layout.width, height: layout.height)
        view.setCover(cover)
        view.setArt(art)
        redraw()
    }

    func detach(_ view: TurntableDeckUIView) {
        if self.view === view { self.view = nil }
    }

    /// The transport's Play/Pause with the turntable showing (NowPlaying.tsx's toggle, :282): a pause winds the record
    /// down, a play during a coast or a wind-down starts from where the record is.
    func toggle() {
        TurntablePress<PlatformMaths>.toggle(rules, world)
    }

    /// A gesture the record's sound may start from (the web's wakeDeckAudio): a failed start tried again when it is old
    /// enough, and the run rule looked at again now.
    func wake() {
        retryFailedStart()
        evaluate()
    }

    /// A press after a failed start (4.6): forgotten when the failure is DeckStartFailure.retryGap old, so the engine is
    /// started again as the run rule says - or by the press that needs it - and the rules ask for a window again.
    private func retryFailedStart() {
        guard engine != nil, failure.pressed(at: CACurrentMediaTime()) else { return }
        audioChanged()
    }

    // MARK: VoiceOver (2.10)

    var recordLabel: String { TurntableWords.record(playing: player.isPlaying) }
    var armAdjusts: Bool { player.duration > 0 }

    /// The record's activation: its tap - a click with no press before it, as VoiceOver's on the web's button: the
    /// pause winds down, the play starts from where a coast is (onRecordClick's rule, which NowPlaying's toggle is).
    func recordActivated() {
        toggle()
    }

    /// The arm's step: 5 s, the web's arrow keys (onArmKey, keyTarget) - the scrubber's step.
    func armAdjusted(increment: Bool) {
        _ = press?.armKey(increment ? "ArrowUp" : "ArrowDown")
    }

    // MARK: touches (the views turn touches into the press's calls, 3.1) - times in ms of the host clock

    func touchDown(_ kind: TurntableDrag.Kind, pointer: Int, x: Double, y: Double, time: Double) {
        guard let press else { return }
        if kind == .record { retryFailedStart() }
        switch kind {
        case .record: press.recordDown(pointer: pointer, x: x, y: y, time: time)
        case .arm: press.armDown(pointer: pointer, x: x, y: y)
        }
        if kind == .record, press.drag?.pointer == pointer, rules?.live() == true {
            touchSince = CACurrentMediaTime()
            touchCount = (0, 0)
        }
        updateLink()
        redraw()
    }

    func touchMoved(pointer: Int, samples: [(time: Double, x: Double, y: Double)]) {
        guard let press, !samples.isEmpty else { return }
        if touchSince != nil, press.drag?.pointer == pointer {
            touchCount.samples += Double(samples.count)
            touchCount.events += 1
        }
        press.moved(pointer: pointer, samples: samples)
        redraw()
    }

    func touchEnded(pointer: Int, how: DeckLetGo, time: Double?) {
        guard let press else { return }
        if let since = touchSince, press.drag?.pointer == pointer {
            let seconds = CACurrentMediaTime() - since
            if seconds > 0.2, touchCount.samples > 0 { touches = (touchCount.samples / seconds, touchCount.events / seconds) }
            touchSince = nil
        }
        press.ended(pointer: pointer, how: how, time: time)
        updateLink()
        redraw()
    }

    // MARK: Debug (6.2)

    /// Debug's Turntable section: the web's rows where the phone has the fact, and the phone's own. The report stands
    /// while the deck lives, shown or not - the web's (deck.ts publishes null only at its destroy) - so You > Debug,
    /// under Now Playing's cover, still reads what the turntable last did.
    func debugRows() -> [InfoRow] {
        collect()
        var facts = DeckPhoneFacts(report: report())
        facts.from = from
        if let status = engine?.status() {
            let underHand = (status.largestSounding ?? 0) > 0
            facts.clock = (status.lead, underHand ? status.largestSounding : status.target, underHand)
            facts.dropped = status.dropped
        }
        facts.handover = handover
        let read = feed.facts
        if read.worst > 0 { facts.positionRead = read.worst }
        facts.windowMade = windowMade
        facts.touches = touches
        facts.slowStarts = slow
        return TurntableDebugRows.phoneRows(facts)
    }

    private func report() -> DeckReport? {
        guard let rules else { return nil }
        let session = AVAudioSession.sharedInstance()
        return TurntableDebugRows.phoneReport(engine: engineState, window: rules.reportWindow, loading: rules.loading,
                                              refused: rules.refusedWhy, failed: rules.failedWhy, fetched: rules.fetchedBytes,
                                              lastFetchAt: rules.lastFetchedAt, ioBuffer: session.ioBufferDuration,
                                              outputLatency: session.outputLatency, health: rules.health(sound))
    }

    // MARK: the deck

    var engineState: DeckEngineState {
        DeckEngineState(prepared: engine != nil, failure: failure.words, airPlay: airPlay, interrupted: interrupted)
    }

    var voiceMade: Bool { engine != nil && failure.words == nil }

    private func make() {
        guard rules == nil else { return }
        // made again: a start that failed before is tried again
        failure.forget()
        if engine == nil { makeEngine() }
        active = UIApplication.shared.applicationState == .active
        airPlay = AudioSessionController.onAirPlay()
        routeKey = Self.routeNow()
        songID = player.current?.track.id ?? ""
        wasPlaying = player.isPlaying
        let made = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: reduced)
        made.handoverLead = { [weak self] (song: DeckSong, x: Double) -> Double in
            MainActor.assumeIsolated { () -> Double in self?.handoverLead(song, x) ?? 0 }
        }
        made.changed = { [weak self] in
            MainActor.assumeIsolated { () -> Void in self?.updateSilent() }
        }
        made.setWindDown(windDown)
        rules = made
        let hand = TurntablePress(deck: made, host: world, maths: PlatformMaths())
        hand.dragChanged = { [weak self] (_: TurntableDrag?) -> Void in
            MainActor.assumeIsolated { () -> Void in
                // the drag moves the time line and the arm; a silent turn may have begun the silent line
                self?.showChanged()
                self?.updateSilent()
            }
        }
        press = hand
        deckShown = nil
        deckAngle = 0
        loadPictures()
        startTicking()
        showChanged()
    }

    private func destroy() {
        guard let rules else { return }
        // the rules' destroy plays on a song the hand took, and closes the deck's audio
        self.rules = nil
        press = nil
        rules.destroy()
        deckShown = nil
        silentLine = nil
        touchSince = nil
        cancelAllTimers()
        frames.removeAll()
        updateLink()
        stopTicking()
        windows.cancel()
        showChanged()
    }

    private func applyShowing() {
        let now = open && turntableShown && active
        if now != showing {
            showing = now
            // the sound's health counted afresh each time it shows, as the web's (deck.ts:1448)
            if now { sound = DeckReport.DeckHealth() }
            rules?.setShowing(now)
        }
        if now && rules != nil { startTicking() }
        updateLink()
        evaluate()
    }

    private func makeEngine() {
        let made = DeckEngine()
        made.ioBuffer = { AudioSessionController.ioBuffer() }
        made.latency = { AudioSessionController.latency() }
        // the session is the app's (4.6): made active at every start, as pressing Play would - never its category changed
        made.activate = { try AudioSessionController.activateShared() }
        made.windowDropped = { [weak self] in
            DispatchQueue.main.async { self?.rules?.windowDropped() }
        }
        eq?.attachDeck(made)
        engine = made
        failure.forget()
    }

    /// closeDeckAudio (deck.ts:1397): the engine stopped and its voice let go, windows and all.
    func closeAudio() {
        guard let engine else { return }
        if engine.isRunning { stopEngine() }
        engine.stop()
        engine.reset()
    }

    /// The deck engine's run rule (4.6, TurntableScreen.engineWant), looked at on every change and every tick.
    func evaluate() {
        guard let engine else { return }
        let now = CACurrentMediaTime()
        let end = Swift.max(lastLoud, lastSoundPost)
        let sounding = now - end < Self.soundingFor
        let want: DeckEngineWant = rules == nil ? .off : TurntableScreen.engineWant(
            showing: showing, songPlaying: player.isPlaying, sounding: sounding,
            quietFor: end.isFinite && !sounding ? now - end : nil,
            pausedFor: pausedAt.map { (at: Double) -> Double in now - at }, active: active, engine: engineState)
        switch want {
        case .running:
            // the engine's own configuration change stops it with no word to us: a stopped engine that should run is
            // started again here, at the next tick (4.6)
            if !engine.isRunning { startEngine(forPress: false) }
        case .resting, .off:
            if engine.isRunning { stopEngine() }
        }
    }

    /// The deck engine started - never while the app isn't active (a tick's drive as the app leaves would start an
    /// output in the background, where the run rule has it off), on AirPlay, during an interruption, or after a start
    /// that failed (until DeckStartFailure forgets it: no post or frame retries a failed start).
    private func startEngine(forPress: Bool) {
        guard let engine, active, !airPlay, !interrupted, failure.words == nil else { return }
        let began = CACurrentMediaTime()
        do {
            // the app's session made active first, by the engine's `activate` (makeEngine)
            try engine.start()
            failure.started()
        } catch {
            failure.failed(error.localizedDescription, at: CACurrentMediaTime())
        }
        let took = CACurrentMediaTime() - began
        if rules != nil { startTicking() }
        if forPress && failure.words == nil && took > DeckConstants.takeBackS {
            slow = ((slow?.count ?? 0) + 1, Swift.max(slow?.worst ?? 0, took - DeckConstants.takeBackS))
        }
        audioChanged()
    }

    private func stopEngine() {
        guard let engine else { return }
        engine.stop()
        collect()
        audioChanged()
        // the lock screen goes by the app's running output (notes/ios.md, "The pause the lock screen didn't see"): the
        // deck's output stopping after the song's is told as the pause was (4.6, check 21)
        if !player.isPlaying { NowPlayingController.republishPaused(elapsed: player.position) }
    }

    /// The deck's rules told the audio changed - after the call that changed it has returned, as the web's statechange
    /// comes (a start inside a post would otherwise call back into the rules mid-method).
    private func audioChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.rules?.audioChanged()
            self?.updateSilent()
        }
    }

    // MARK: DeckHost, as DeckWorld hands it over

    func deckSong() -> DeckSong? {
        guard let track = player.current?.track else { return nil }
        return DeckSong(id: track.id, length: player.duration, suffix: track.suffix, contentType: track.contentType)
    }

    /// The song's position (3.4): the `deck.position` queue's reading while it is fresh (a handover), else the player's.
    func songPosition() -> Double {
        feed.latest(now: CACurrentMediaTime())?.seconds ?? player.position
    }

    func listen(_ listener: @escaping (Double) -> Void) -> Int {
        let id = nextListener
        nextListener += 1
        listeners[id] = listener
        return id
    }

    func unlisten(_ id: Int) {
        listeners[id] = nil
    }

    /// holdSong (Turntable.tsx:199): the player's pause, the only move of the song outside a tap or a release.
    func holdSong() {
        if player.isPlaying { player.pause() }
    }

    /// resumeSong (:202) - and the `deck.position` queue started, the handover's judge reading from it (2.6, 3.5).
    func resumeSong() {
        if let late = firingLate, handover != nil, handover?.timerLate == nil { handover?.timerLate = late }
        if !player.isPlaying { player.resume() }
        if let engine = player.engineForDeck { feed.run(engine, for: Self.feedSeconds) }
        if rules != nil { startTicking() }
    }

    func turnFace(_ degrees: Double) {
        deckAngle = degrees
        redraw()
    }

    /// The deck's show (Turntable.tsx:226): to a fiftieth of a second, so the time line and the arm redraw only when
    /// what they show changes.
    func show(_ at: Double?, scrubbing: Bool) {
        let next = at.map { (at: Double) -> (at: Double, scrubbing: Bool) in ((at * 50).rounded() / 50, scrubbing) }
        if next?.at == deckShown?.at && next?.scrubbing == deckShown?.scrubbing { return }
        deckShown = next
        showChanged()
    }

    /// The window (4.4, 4.5): from the download, else the stream cache's whole copy, else deadwax's `/scrub` - none
    /// offline - at the rate the deck engine runs at (the session's before its first start) and the entry's level.
    func window(_ song: DeckSong, from start: Double, seconds: Double,
                answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void) {
        guard let entry = player.current, entry.track.id == song.id else { return }
        let rate = TurntableScreen.windowRate(engineRate: engine?.rate ?? 0,
                                              engineStarted: (engine?.status().starts ?? 0) > 0,
                                              sessionRate: AVAudioSession.sharedInstance().sampleRate)
        let factor = player.levelDecisions.decided(entry.key)?.multiplier
        let fileRate = Double(entry.track.sampleRate)
        let made = { [weak self] (result: Result<DeckWindow, DeckWindowError>) -> Void in
            if case .success(let window) = result {
                self?.windowMade = (window.madeIn, window.end - window.start, fileRate > 0 ? fileRate : window.rate)
            }
            answer(result)
        }
        if let url = local(entry) {
            self.from = files.downloads.url(for: song.id) != nil ? .download : .cache
            windows.make(file: url, from: start, seconds: seconds, outputRate: rate, factor: factor, answer: made)
        } else if reachability.online, let client = server.client {
            self.from = .server
            windows.make(scrub: client, songID: song.id, from: start, seconds: seconds, outputRate: rate, factor: factor,
                         answer: made)
        } else {
            self.from = .offline
            DispatchQueue.main.async { answer(.failure(.offline)) }
        }
    }

    /// The song's file on the phone, whole: the download, else the stream cache's complete copy - the order the engine
    /// opens a track from (PlayerModel+Engine).
    private func local(_ entry: QueueEntry) -> URL? {
        if let url = files.downloads.url(for: entry.track.id) { return url }
        return files.wholeCopy(of: player.song(for: entry) ?? Song(track: entry.track))
    }

    func post(_ message: DeckPost) {
        guard let engine else { return }
        switch message {
        case .take, .hand, .drive:
            lastSoundPost = CACurrentMediaTime()
            // the press that needs the engine starts it (4.6): nothing timed is posted to a stopped one
            if !engine.isRunning { startEngine(forPress: true) }
        case .window, .fade, .stop:
            break
        }
        _ = engine.post(message)
    }

    /// (3.5) `E - D` for a let-go of a playing record: the song's start predicted from this route's last five of its
    /// kind (local: a download or the cache's whole copy; streamed, growing with the position), less the voice's delay.
    private func handoverLead(_ song: DeckSong, _ x: Double) -> Double {
        let route = routeKey
        let isLocal = player.current.map { (entry: QueueEntry) -> Bool in local(entry) != nil } ?? false
        let predicted = isLocal
            ? HandoverTiming.predictedLocal(localStarts[route] ?? [])
            : HandoverTiming.predictedStream(streamStarts[route] ?? [], at: x)
        let l = engine?.status().lead ?? 2 * AudioSessionController.ioBuffer()
        let d = HandoverTiming.voiceDelay(clockLead: l, latency: AudioSessionController.latency())
        let lead = HandoverTiming.lead(predicted: predicted, voiceDelay: d)
        handover = DeckPhoneFacts.Handover(lead: lead, predicted: predicted)
        // the starts seen so far: this let-go's is the next one. Not the engine's last start asked of it here - that
        // waits on its queue, on the main thread, mid-gesture (2.6); the deck.position queue reads it after the resume
        handoverKind = (isLocal, x, route, engineStarts.count, CACurrentMediaTime())
        return lead
    }

    /// The handover's actual `E`, once the `deck.position` queue's run has read the engine's last start: Debug's, and
    /// kept for the next prediction of its kind on this route.
    private func noteStart() {
        guard let kind = handoverKind else { return }
        let facts = feed.facts
        guard let started = HandoverTiming.actualStart(startsAtLetGo: kind.starts, starts: engineStarts,
                                                       read: facts.started, readAt: facts.readAt) else {
            // no resume came of it (a cancel, the song changed), or the song never started within the run: let go
            if CACurrentMediaTime() - kind.at > 2 * Self.feedSeconds { handoverKind = nil }
            return
        }
        handoverKind = nil
        handover?.took = started
        if kind.local {
            localStarts[kind.route] = Array(((localStarts[kind.route] ?? []) + [started]).suffix(Self.startsKept))
        } else {
            let kept = (streamStarts[kind.route] ?? []) + [(position: kind.position, seconds: started)]
            streamStarts[kind.route] = Array(kept.suffix(Self.startsKept))
        }
    }

    private func updateSilent() {
        let turned = !songID.isEmpty && press?.turnedSilent == songID
        let line = TurntableScreen.silentLine(turnedSilent: turned, flac: deckSong()?.flac ?? false, engine: engineState,
                                              error: player.errorLine)
        if line != silentLine { silentLine = line }
    }

    // MARK: the clock (DeckClock)

    /// A main-queue DispatchSourceTimer, `.strict` and no leeway (3.5): the led resume's moment is one of these.
    func after(_ ms: Double, _ run: @escaping () -> Void) -> Int {
        let id = nextTimer
        nextTimer += 1
        let wait = Swift.max(ms, 0) / 1_000
        let due = CACurrentMediaTime() + wait
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + wait, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { () -> Void in
                guard let self, let fired = self.timers.removeValue(forKey: id) else { return }
                fired.cancel()
                self.firingLate = Swift.max(0, CACurrentMediaTime() - due)
                run()
                self.firingLate = nil
                self.updateLink()
            }
        }
        timers[id] = timer
        timer.resume()
        return id
    }

    func cancelTimer(_ id: Int) {
        timers.removeValue(forKey: id)?.cancel()
    }

    private func cancelAllTimers() {
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
    }

    func frame(_ run: @escaping (Double) -> Void) -> Int {
        let id = nextFrame
        nextFrame += 1
        frames[id] = run
        updateLink()
        return id
    }

    func cancelFrame(_ id: Int) {
        frames[id] = nil
        updateLink()
    }

    /// The display link runs only when the web's loop would (2.6): asked, shown, the scene active - and under Reduce
    /// Motion only for a held record.
    private func updateLink() {
        let held = rules?.taken() == true || press?.drag != nil
        let run = TurntableScreen.framesRun(asked: !frames.isEmpty, showing: showing, active: active, reduced: reduced,
                                            held: held)
        if run && link == nil {
            let made = CADisplayLink(target: frameTarget, selector: #selector(DeckFrameTarget.tick(_:)))
            made.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            made.add(to: .main, forMode: .common)
            link = made
        }
        link?.isPaused = !run
    }

    /// A frame: the voice's reports in, the handover's reading to the rules' listeners, then each frame asked for, with
    /// the frame's time - the last vsync's, requestAnimationFrame's meaning.
    func tick(_ link: CADisplayLink) {
        collect()
        deliverReading()
        runFrames(link.timestamp * 1_000)
    }

    /// Frames asked for that won't be drawn now (Reduce Motion turned on mid-motion): run once with now's time, as a
    /// requestAnimationFrame already asked still comes - so the rules' loop sees it should stop.
    private func flushFrames() {
        runFrames(CACurrentMediaTime() * 1_000)
    }

    private func runFrames(_ time: Double) {
        let due = frames.keys.sorted().compactMap { (id: Int) -> ((Double) -> Void)? in frames[id] }
        frames.removeAll()
        for run in due { run(time) }
        updateLink()
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let made = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] (_: Timer) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.tickRule() }
        }
        RunLoop.main.add(made, forMode: .common)
        ticker = made
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tickRule() {
        collect()
        deliverReading()
        noteStart()
        evaluate()
        // nothing to look at while the deck is hidden, its engine resting, no timer of its own waiting and no handover's
        // start to note: the tick stops until it shows, its engine starts, or the deck resumes the song
        let running = engine?.isRunning ?? false
        if !showing && !running && timers.isEmpty && handoverKind == nil { stopTicking() }
    }

    /// The voice's reports (the web's port.onmessage, deck.ts heard()): to the rules, and counted for the Limiter row.
    private func collect() {
        guard let engine else { return }
        let heard = engine.reports()
        guard !heard.isEmpty else { return }
        let now = CACurrentMediaTime()
        for said in heard {
            rules?.heard(said)
            if said.gain > 0 { lastLoud = now }
            if said.held > 0 {
                sound.peaksHeld = (sound.peaksHeld ?? 0) + said.peaks
                sound.samplesHeld += said.held
            }
            if said.lowest < 1 {
                // floored, as the web's DEEPEST_GAIN_SAID: -20 log10 of 0 is infinite
                let deepest = -20 * log10(Swift.max(said.lowest, Self.deepestGainSaid))
                if deepest > sound.deepestHoldDb { sound.deepestHoldDb = deepest }
            }
        }
    }

    /// A fresh reading of the song's engine (2.6), handed to the rules' listeners once per new reading.
    private func deliverReading() {
        guard let reading = feed.latest(now: CACurrentMediaTime()), reading.at > delivered else { return }
        delivered = reading.at
        for listener in listeners.values { listener(reading.seconds) }
    }

    // MARK: the player, watched

    private func watchPlayer() {
        withObservationTracking {
            _ = player.current?.track.id
            _ = player.isPlaying
            _ = player.position
            _ = player.shownPosition
            _ = player.duration
            _ = player.errorLine
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.playerChanged()
                self.watchPlayer()
            }
        }
    }

    private func playerChanged() {
        // the engine's phase, watched through isPlaying: a start counted each time it says it plays again
        engineStarts.phase(playing: player.engineState.phase == .playing, at: CACurrentMediaTime())
        let id = player.current?.track.id ?? ""
        if id != songID {
            songID = id
            press?.songChanged(id)
            rules?.songChanged(id)
            loadPictures()
        }
        let playing = player.isPlaying
        if playing != wasPlaying {
            wasPlaying = playing
            pausedAt = playing ? nil : CACurrentMediaTime()
            // the song plays: whatever interrupted the sound is over
            if playing { interruptionOver() }
            rules?.playingChanged(playing)
        }
        if player.position != lastPosition {
            lastPosition = player.position
            // the player's own reports (twice a second); a handover's come from the position queue, a frame at a time
            if rules != nil, feed.latest(now: CACurrentMediaTime()) == nil {
                for listener in listeners.values { listener(player.position) }
            }
        }
        guard rules != nil else { return }
        showChanged()
        updateSilent()
        evaluate()
    }

    // MARK: the drawing

    /// What the time line and the arm show (Turntable.tsx:226-233, :420): the deck's show unless the arm is held, else
    /// the drag's preview.
    private func showChanged() {
        let drag = press?.drag
        let previewing: TurntablePreview?
        if let deckShown, drag?.kind != .arm {
            previewing = .deck(at: deckShown.at, scrubbing: deckShown.scrubbing)
        } else {
            previewing = TurntableGeometry.preview(drag)
        }
        let length = player.duration
        shownTime = TurntableGeometry.shownTime(previewing, player.shownPosition, length)
        let line = TurntableWords.timeLine(shownTime, length, TurntableGeometry.previewWords(previewing))
        if line != timeLine { timeLine = line }
        let value = TurntableWords.armValue(shownTime, length)
        if value != armValue { armValue = value }
        updateLink()
        redraw()
    }

    /// The layers written, with no animation: the face (the deck's angle and the hand's turn, Turntable.tsx:426), the
    /// arm, the handle.
    private func redraw() {
        guard let view else { return }
        var look = TurntableLook()
        look.angle = deckAngle + (press?.handTurn ?? 0)
        let length = player.duration
        look.arm = trig.armAngle(shownTime, length)
        look.needle = trig.needleAt(shownTime, length)
        look.lifted = press?.drag?.kind == .arm
        look.contrast = contrast
        view.draw(look)
    }

    /// A disc's CD art kept for its next showing, the oldest let go past `artKeptMost` (question 11: in memory, as
    /// fetched this run - and so a picture replaced by hand shows once its disc has been let go, or the app has started
    /// again).
    private func keep(_ picture: CGImage, as key: String) {
        artKept[key] = picture
        artOrder.removeAll { (each: String) -> Bool in each == key }
        artOrder.append(key)
        while artOrder.count > Self.artKeptMost { artKept[artOrder.removeFirst()] = nil }
    }

    /// The label's cover and the disc's CD art (2.3): the cover from the app's cache, the art from deadwax's disc_art
    /// route - the last `artKeptMost` discs kept, a disc that had none asked again at the next opening (the web's rule).
    private func loadPictures() {
        guard rules != nil, let entry = player.current else { return }
        let track = entry.track
        if coverFor != track.coverArt {
            coverFor = track.coverArt
            setCover(nil)
            if let id = track.coverArt, let client = server.client {
                let across = (box.width > 0 ? box.width : 320) * 2 * TurntableGeometry.record.r / TurntableGeometry.stage.width
                let size = CoverSize.step(for: Int(across * TurntableFace.labelShare * Double(UIScreen.main.scale)))
                Task { @MainActor [weak self] in
                    let got = await CoverCache.shared.load(client: client, id: id, size: size)
                    guard let self, self.coverFor == id else { return }
                    self.setCover(got?.cgImage)
                }
            }
        }
        guard let album = track.albumId, !album.isEmpty else {
            setArt(nil, for: nil)
            return
        }
        let songs = player.song(for: entry).map { (song: Song) -> [(id: String, discNumber: Double?)] in
            [(id: song.id, discNumber: song.discNumber.map { (disc: Int) -> Double in Double(disc) })]
        }
        let disc = TurntableGeometry.playingDisc(songs, track.id)
        let key = "\(album)|\(disc)"
        if artFor == key { return }
        if let kept = artKept[key] {
            setArt(kept, for: key)
            return
        }
        setArt(nil, for: key)
        guard !artFailed.contains(key), reachability.online, let client = server.client else { return }
        Task { @MainActor [weak self] in
            let data = try? await client.discArt(albumID: album, disc: disc)
            let decoded = data.flatMap { (bytes: Data) -> UIImage? in UIImage(data: bytes) }
            let image = await decoded?.byPreparingForDisplay() ?? decoded
            guard let self, self.artFor == key else { return }
            if let picture = image?.cgImage {
                self.keep(picture, as: key)
                self.setArt(picture, for: key)
            } else {
                self.artFailed.insert(key)
            }
        }
    }

    private func setCover(_ image: CGImage?) {
        cover = image
        view?.setCover(image)
    }

    private func setArt(_ image: CGImage?, for key: String?) {
        artFor = key
        art = image
        view?.setArt(image)
    }

    // MARK: the session and the system (4.6)

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { [weak self] (note: Notification) -> Void in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            MainActor.assumeIsolated { () -> Void in
                guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                // the app was suspended, not interrupted: told late, as it runs again, with no "ended" to follow
                if type == .began, reason == Self.appWasSuspended { return }
                self?.interruption(began: type == .began)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.routeChanged() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.mediaReset() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.activeChanged(true) }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.activeChanged(false) }
        })
        observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in self?.reducedChanged() }
        })
        observers.append(center.addObserver(forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] (_: Notification) -> Void in
            MainActor.assumeIsolated { () -> Void in
                self?.contrast = UIAccessibility.isDarkerSystemColorsEnabled
                self?.redraw()
            }
        })
    }

    /// AVAudioSessionInterruptionReasonAppWasSuspended's number. Deprecated in iOS 16 ("no longer present"), so
    /// compared by its number rather than its name, which would warn: a "began" for a suspension is no interruption.
    nonisolated static let appWasSuspended: UInt = 1

    /// A call, Siri, an alarm (3.1, 4.6): a taken press let go as a cancel that rests, the engine stopped, no sound
    /// until it ends; counted.
    private func interruption(began: Bool) {
        if began {
            guard !interrupted else { return }
            interrupted = true
            sound.interruptions += 1
            rules?.interrupted()
            press?.cancelFollowed()
            if let engine, engine.isRunning { stopEngine() }
            audioChanged()
            evaluate()
        } else {
            interruptionOver()
        }
    }

    /// The interruption over, as far as the deck can tell (4.6): its "ended" came - which Apple doesn't promise - or the
    /// song plays again, or the app came back to the front. Without the last two, one "began" with no "ended" left the
    /// record silent for the rest of the run, every press a silent scrub.
    private func interruptionOver() {
        guard interrupted else { return }
        interrupted = false
        // a start that failed during it is tried again
        failure.forget()
        audioChanged()
        evaluate()
    }

    /// Earbuds in or out, Bluetooth, a car (4.6): the voice stopped and the engine with it, `L` from its floor, a window
    /// at the old rate dropped (DeckEngine says so through windowDropped), AirPlay looked at again - the engine started
    /// again when the run rule says. Only a change of the outputs counts: the notification comes for a category set
    /// too, which moves nothing.
    private func routeChanged() {
        let now = Self.routeNow()
        guard now != routeKey else { return }
        routeKey = now
        airPlay = AudioSessionController.onAirPlay()
        // a new output may start where the old one refused
        failure.forget()
        engine?.routeChanged()
        audioChanged()
        evaluate()
    }

    /// Every AVAudio object gone (4.6): the deck engine made again from nothing, its voice with it.
    private func mediaReset() {
        guard let old = engine else { return }
        old.stop()
        engine = nil
        makeEngine()
        rules?.windowDropped()
        audioChanged()
        evaluate()
    }

    /// The app leaving the front (4.6): the engine stopped at once and the deck hidden (setShowing(false)). A touch UIKit
    /// cancels is the press's cancel, from the touch view.
    private func activeChanged(_ now: Bool) {
        if now { interruptionOver() }
        guard now != active else { return }
        active = now
        applyShowing()
    }

    private func reducedChanged() {
        reduced = UIAccessibility.isReduceMotionEnabled
        rules?.reducedChanged(reduced)
        if reduced { flushFrames() }
        updateLink()
    }

    private static func routeNow() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { (port: AVAudioSessionPortDescription) -> String in "\(port.portType.rawValue):\(port.uid)" }
            .joined(separator: "|")
    }
}
