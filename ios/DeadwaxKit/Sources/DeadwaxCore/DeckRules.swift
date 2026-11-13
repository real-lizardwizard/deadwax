// The deck's rules (notes/ios-specs/turntable.md 3.3-3.5): ui/src/player/deck.ts's Deck class, ported method for
// method - the same state, the same order of effects, each method carrying the web's line. Its world comes in through
// `DeckHost` (the web's DeckHost, deck.ts:217, with soundReady and window as the spec's 3.3 has them) and `DeckClock`
// (now, the stamp, and the timers and frames the web asks of setTimeout and requestAnimationFrame). What the web reads
// of its module's audio (voiceReady, the voice made, sleeping and closing it) comes through the host too; the deck's
// own clock timer and readings (keepClock, readClock, deck.ts:2156-2193) are not here - the phone's clock is its voice
// host's (3.2). Held to the web by DeckRulesTests, which replays rules/*.json - the real Deck's every input and effect.

/// The song as the deck sees it (deck.ts:195).
public struct DeckSong: Equatable, Sendable {
    public var id: String
    public var length: Double
    public var flac: Bool
    public var kind: String
    public init(id: String, length: Double, flac: Bool, kind: String) {
        self.id = id
        self.length = length
        self.flac = flac
        self.kind = kind
    }
}

/// A window of the song, decoded (3.3): its channels (1 or 2), the stretch of the song it was cut from (`start` and
/// `end`, seconds, as the maker said them), the rate its channels are at, where it came from, its size, and how long it
/// took to make.
///
/// The phone's window maker (slice 2, DeckWindows.swift) gives its channels as `pcm` - memory of its own, which the
/// voice reads by pointer on the audio thread - and `channels` empty; a test's hand-made window gives `channels`. The
/// deck reads its size through `frames` and `channelCount`, which answer for either.
public struct DeckWindow: Sendable {
    public enum Source: Sendable { case file, server }
    public var channels: [[Float]]
    public var pcm: DeckPCM?
    public var start: Double
    public var end: Double
    public var rate: Double
    public var source: Source
    public var bytes: Int
    public var madeIn: Double
    public init(channels: [[Float]], start: Double, end: Double, rate: Double, source: Source, bytes: Int, madeIn: Double) {
        self.channels = channels
        self.start = start
        self.end = end
        self.rate = rate
        self.source = source
        self.bytes = bytes
        self.madeIn = madeIn
    }

    public init(pcm: DeckPCM, start: Double, end: Double, rate: Double, source: Source, bytes: Int, madeIn: Double) {
        self.init(channels: [], start: start, end: end, rate: rate, source: source, bytes: bytes, madeIn: madeIn)
        self.pcm = pcm
    }

    /// Its length, in frames at `rate`.
    public var frames: Int { pcm?.frames ?? channels.first?.count ?? 0 }
    /// How many channels: 1 or 2 from the maker.
    public var channelCount: Int { pcm?.channelCount ?? channels.count }
}

/// A window's channels as the phone's maker makes them (turntable.md 4.3, 4.4): Float32s in memory of their own,
/// `channelCount` runs of `capacity`, of which the first `frames` are the window's. Made and filled off the audio
/// thread; the voice is handed pointers into it, so whoever posts the window keeps this alive until the voice has let
/// go of it (the deck engine's return ring) - and frees it off the audio thread, where its last reference goes.
public final class DeckPCM: @unchecked Sendable {
    public let channelCount: Int
    public let capacity: Int
    /// how many of each channel's `capacity` are the window's - set by the maker as it finishes, before it is posted
    public private(set) var frames: Int
    private let base: UnsafeMutablePointer<Float>

    /// `channelCount` channels of `capacity` frames, every one 0.
    public init(channelCount: Int, capacity: Int) {
        precondition(channelCount >= 1 && capacity >= 0)
        self.channelCount = channelCount
        self.capacity = capacity
        frames = capacity
        base = .allocate(capacity: max(1, channelCount * capacity))
        base.initialize(repeating: 0, count: max(1, channelCount * capacity))
    }

    deinit { base.deallocate() }

    /// Channel `c`'s first sample.
    public func channel(_ c: Int) -> UnsafeMutablePointer<Float> { base + min(max(c, 0), channelCount - 1) * capacity }

    /// The window is the first `count` of each channel (at most `capacity`).
    public func keep(_ count: Int) { frames = min(max(count, 0), capacity) }

    /// Its bytes in memory.
    public var bytes: Int { channelCount * capacity * MemoryLayout<Float>.stride }

    /// The voice's view of it, from song second `start` at `rate`: at most two channels' pointers.
    public func voiceWindow(start: Double, rate: Double) -> VoiceWindow {
        VoiceWindow(first: UnsafePointer(channel(0)), second: channelCount > 1 ? UnsafePointer(channel(1)) : nil,
                    length: frames, start: start, rate: rate)
    }

    /// A copy of `channels` (a test's hand-made window).
    public convenience init(_ channels: [[Float]]) {
        let length = channels.map(\.count).min() ?? 0
        self.init(channelCount: max(1, channels.count), capacity: length)
        for (c, samples) in channels.enumerated() {
            samples.withUnsafeBufferPointer { (from: UnsafeBufferPointer<Float>) -> Void in
                if let address = from.baseAddress, length > 0 { channel(c).update(from: address, count: length) }
            }
        }
    }
}

/// Why a window couldn't be had (3.3): the web's 415 and 416, and the phone's own.
public enum DeckWindowError: Error, Equatable, Sendable {
    /// deadwax's 415: the song can't be a window - for good (its detail, or none)
    case notFlac(String?)
    /// deadwax's 416
    case pastTheEnd
    /// (new) no window: this phone is offline and the song isn't all on it
    case offline
    /// (new) the phone couldn't make the window's PCM - in its own words
    case undecodable(String)
    /// (new) more channels than the voice plays (it plays 1 or 2)
    case channels(Int)
    /// anything else: tried again after RETRY_MS
    case failed(String)
}

/// A message to the voice (deckVoice.ts's VoiceMessage), as the deck posts it.
public enum DeckPost: Sendable {
    case window(DeckWindow)
    case take(at: Double, rate: Double, time: Double, until: Double)
    case drive(at: Double, rate: Double, accel: Double?, time: Double, until: Double)
    case hand(at: Double, time: Double)
    case fade(seconds: Double)
    case stop
}

/// What a release asks Turntable to do, in the release's own handler (deck.ts:239).
public struct DeckReleased: Equatable, Sendable {
    public var seek: Double?
    public var play: Bool
    public init(seek: Double?, play: Bool) {
        self.seek = seek
        self.play = play
    }
}

/// What the deck asks of the turntable and the player (deck.ts:217-237, 3.3, 3.4).
public protocol DeckHost: AnyObject {
    func song() -> DeckSong?
    func playing() -> Bool
    /// the song's position as the player has it, seconds
    func position() -> Double
    /// told the position as the player reports it; returns the way to stop
    func onPosition(_ listener: @escaping (Double) -> Void) -> () -> Void
    func hold()
    func resume()
    /// the face's angle, degrees
    func turnFace(_ degrees: Double)
    /// the time line and the arm: a time (`scrubbing` while a hand or a flick moves it), or nil for the song's own
    func show(_ at: Double?, scrubbing: Bool)
    /// the press took the record: the click after it is not a tap
    func grabbed()
    /// the deck engine prepared and allowed, its voice made (the web's voiceReady(), deck.ts:1240 - not "running")
    func soundReady() -> Bool
    /// a voice made to put a window in (the web's `audio.voice?.ready` with a context not closed, deck.ts:2289, :2386)
    func voiceMade() -> Bool
    /// `seconds` of the song from `from`, decoded; answered once, on the main queue
    func window(_ song: DeckSong, from: Double, seconds: Double, answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void)
    /// a message for the voice
    func post(_ message: DeckPost)
    /// the turntable hidden: the deck engine may rest (the web's sleepDeckAudio, deck.ts:1466)
    func sleepAudio()
    /// the deck gone (closeDeckAudio, deck.ts:1397)
    func closeAudio()
}

/// The deck's time (3.2): the page's milliseconds, the voice's seconds for one of them, and its timers and frames.
public protocol DeckClock: AnyObject {
    /// now, ms
    func now() -> Double
    /// page time `ms` as the voice's clock has it, seconds
    func stamp(_ ms: Double) -> Double
    /// `run` after `ms`; its id (never 0)
    func after(_ ms: Double, _ run: @escaping () -> Void) -> Int
    func cancel(_ id: Int)
    /// `run` at the next frame, with the frame's time (ms); its id (never 0)
    func frame(_ run: @escaping (Double) -> Void) -> Int
    func cancelFrame(_ id: Int)
}

/// The web's constants (deck.ts:111-190), as it has them.
public enum DeckConstants {
    public static let holdMs = 250.0
    public static let takeBackS = DeckVoice.handDelayS - 0.02
    public static let windowS = 40.0
    public static let windowBackS = 4.0
    public static let windowGridS = 2.0
    public static let refreshAheadS = 6.0
    public static let refreshMinMs = 3000.0
    public static let retryMs = 10_000.0
    public static let driveForS = 0.12
    public static let handoverMaxS = 3.0
    public static let handoverFadeS = 0.04
    public static let slowFrameMs = 34.0
    public static let resumeInGestureS = 0.05
    public static let pauseSettleMs = 300.0
    public static let songChangeSettleMs = 300.0
    public static let heardFreshMs = 120.0
    public static let healthReportMs = 250.0
    public static let soughtElsewhereS = 0.75

    /// The margins for windows of `span` seconds (deck.ts:254).
    public static func windowMargins(_ span: Double) -> (back: Double, ahead: Double) {
        let scale = JSMath.max(0, JSMath.min(1, span / windowS))
        return (windowBackS * scale, refreshAheadS * scale)
    }
}

/// Where a plan goes, its lowest point and its highest (deck.ts:1271).
func planReach<M: DeckMaths>(_ plan: Plan, _ plans: PlatterPlans<M>) -> (low: Double, high: Double) {
    var low = Double.infinity, high = -Double.infinity
    for phase in plan.phases {
        for x in [plans.phaseAt(phase, 0).x, plans.phaseAt(phase, phase.duration).x] {
            low = JSMath.min(low, x)
            high = JSMath.max(high, x)
        }
    }
    return low.isFinite ? (low, high) : (plan.x, plan.x)
}

public final class DeckRules<M: DeckMaths> {
    enum Role { case coast, handover, winddown, spin }

    /// deck.ts:262
    final class PlanMotion {
        let role: Role
        let plan: Plan
        let since: Double
        let from: Double
        let x0: Double
        var sounding: Bool
        var sought: Double
        var quiet: Bool
        /// (3.5) the song resumed before its end, by the lead - its judge running from the resume
        var resumed = false
        init(role: Role, plan: Plan, since: Double, from: Double, x0: Double, sounding: Bool, sought: Double, quiet: Bool) {
            self.role = role
            self.plan = plan
            self.since = since
            self.from = from
            self.x0 = x0
            self.sounding = sounding
            self.sought = sought
            self.quiet = quiet
        }
    }

    /// deck.ts:278
    enum Motion {
        case still
        case turning(since: Double, from: Double)
        case hand
        case plan(PlanMotion)
    }

    struct Early {
        var time: Double
        var turned: Double
        var offset: Double
    }

    /// deck.ts:284
    final class Press {
        var taken = false
        var anchor = 0.0
        var at = 0.0
        var intent: Intent = .pause
        var samples: [HandSample]
        var since: Double
        var early: [Early] = []
        enum Intent { case play, pause }
        init(time: Double) {
            samples = [HandSample(time: time, turned: 0)]
            since = time
        }
    }

    struct Heard {
        var pos: Double
        var rate: Double
        var gain: Double
        var at: Double
    }

    struct WindowHad {
        var song: String
        var start: Double
        var end: Double
        var bytes: Int
        var decodedAt: Double
    }

    struct Pending {
        enum Stage { case fetch, held }
        var song: String
        var from: Double
        var to: Double
        var stage: Stage
    }

    struct Decoded {
        var song: String
        var window: DeckWindow
    }

    let host: DeckHost
    let clock: DeckClock
    let plans: PlatterPlans<M>

    var motion: Motion = .still
    var angle = 0.0
    var press: Press?
    var stilled = false
    var holdTimer: Int?
    var planTimer: Int?
    var settleTimer: Int?
    var resumeTimer: Int?
    var handoverTimer: Int?
    /// (3.5) the resume a lead asks before the plan's end
    var ledTimer: Int?
    var handoverOff: (() -> Void)?
    var raf = 0
    var showing = false
    var reduced: Bool
    var windDown = true
    var wasPlaying = false
    var positionOff: (() -> Void)?

    var window: WindowHad?
    var pending: Pending?
    var decodedWindow: Decoded?
    var requestTicket = 0
    var span: (song: String, seconds: Double)?
    var refreshedAt = -Double.infinity
    var refused: (song: String, why: String)?
    var wanted: String?
    var failed: (song: String, why: String, until: Double)?
    var fetched = 0
    var since: Double
    var lastFetchAt = 0.0
    var heard: Heard?
    var stampedTo = -Double.infinity
    var letGo: (at: Double, since: Double, motor: Double)?
    var backMs: Double?
    var motorMs: Double?
    var notBack = 0
    var heldFrame = 0.0
    var frames = 0
    var slowFrames = 0
    var worstFrameMs = 0.0
    var handoverJudge: ((Double) -> Void)?
    var songId: String
    var speed = 1.0

    /// (3.4) the resume the deck itself asked for, until the next playingChanged: a play that is its own
    public private(set) var resumeAsked = false
    /// (3.5) how much earlier than the plan's end the song is resumed, seconds - E less D, read at each let-go of a
    /// playing record. 0 is the web's, exactly
    public var handoverLead: (DeckSong, Double) -> Double = { _, _ in 0 }
    /// told whenever the web's Deck reports (Debug's, slice 3)
    public var changed: (() -> Void)?

    public init(host: DeckHost, clock: DeckClock, maths: M, reduced: Bool) {
        // deck.ts:1360
        self.host = host
        self.clock = clock
        plans = PlatterPlans(maths)
        since = clock.now()
        songId = host.song()?.id ?? ""
        wasPlaying = host.playing()
        self.reduced = reduced
        motion = wasPlaying ? .turning(since: clock.now(), from: 0) : .still
    }

    var now: Double { clock.now() }

    func clearTimer(_ id: Int?) {
        if let id { clock.cancel(id) }
    }

    /// deck.ts:1377 - gone: every timer, the frame loop, the listeners; a song the hand took from playing plays on.
    public func destroy() {
        let resume = meantToPlay() || resumeTimer != nil
        dropPress()
        endHandover()
        clearTimer(planTimer)
        clearTimer(settleTimer)
        clearTimer(resumeTimer)
        resumeTimer = nil
        clearLed()
        if raf != 0 { clock.cancelFrame(raf) }
        raf = 0
        positionOff?()
        positionOff = nil
        requestTicket += 1
        decodedWindow = nil
        post(.stop)
        motion = .still
        host.closeAudio()
        changed?()
        if resume && host.song() != nil && !host.playing() { host.resume() }
    }

    // ----- what Turntable tells it

    /// deck.ts:1420
    public func live() -> Bool {
        if case .plan(let motion) = motion, motion.role == .coast || motion.role == .handover, host.soundReady() { return true }
        return sounding(recordAt())
    }

    /// (3.1, 4.6) An audio interruption began (a call, Siri): a taken press is to rest when its touch is cancelled - its
    /// intent made a pause first, so the cancel doesn't ask the song to play into the call.
    public func interrupted() {
        press?.intent = .pause
    }

    /// deck.ts:1426
    public func taken() -> Bool {
        press?.taken ?? false
    }

    /// deck.ts:1431
    public func anchor() -> Double {
        press?.anchor ?? host.position()
    }

    /// deck.ts:1437
    public func setShowing(_ showing: Bool) {
        if showing == self.showing { return }
        self.showing = showing
        if showing {
            since = now
            fetched = 0
            frames = 0
            slowFrames = 0
            worstFrameMs = 0
            notBack = 0
            backMs = nil
            motorMs = nil
            lastFetchAt = 0
            positionOff = host.onPosition { [weak self] seconds in self?.onPosition(seconds) }
            keepHere()
            loop()
        } else {
            positionOff?()
            positionOff = nil
            if raf != 0 { clock.cancelFrame(raf) }
            raf = 0
            if pending?.stage == .fetch {
                requestTicket += 1
                pending = nil
            }
            host.sleepAudio()
        }
        report()
    }

    /// deck.ts:1474
    public func setWindDown(_ on: Bool) {
        windDown = on
    }

    /// deck.ts:1485
    public func speedChanged(_ speed: Double) {
        if !(speed > 0) || speed == self.speed { return }
        if case .turning = motion { motion = .turning(since: now, from: angleNow()) }
        var spinningUp = false
        if case .plan(let plan) = motion, plan.role == .spin, plan.plan.target > 0 { spinningUp = true }
        let v = spinningUp ? speedNow() : 0
        self.speed = speed
        if spinningUp { spin(plans.motor(0, v, 0, speed)) }
        loop()
    }

    /// deck.ts:1499
    public func playingChanged(_ playing: Bool) {
        let asked = resumeAsked
        resumeAsked = false
        if playing == wasPlaying { return }
        wasPlaying = playing
        clearTimer(settleTimer)
        settleTimer = nil
        if playing {
            if press?.taken == true { return }
            if case .turning = motion { return }
            if case .plan(let motion) = motion, motion.role == .handover {
                //? (3.4) the deck's own resume, asked early by the lead: the plan runs on to its end
                if asked { return }
                //? played before the coast got back to speed: the coast is over - its sound fades
                clearTimer(planTimer)
                planTimer = nil
                clearLed()
                self.motion = .turning(since: now, from: angleNow())
                if motion.sounding { post(.fade(seconds: DeckConstants.handoverFadeS)) }
                host.show(nil, scrubbing: false)
                loop()
                return
            }
            if case .plan(let motion) = motion {
                if motion.sounding { post(.stop) }
                host.show(nil, scrubbing: false)
            }
            spin(plans.motor(0, speedNow(), 0, speed))
            keepHere()
            return
        }
        if press?.taken == true { return }
        guard case .turning = motion else { return }
        settleTimer = clock.after(DeckConstants.pauseSettleMs) { [weak self] in
            guard let self else { return }
            self.settleTimer = nil
            if case .turning = self.motion, !self.host.playing(), self.press?.taken != true { self.spin(self.plans.coast(0, self.speed, 0)) }
        }
    }

    /// deck.ts:1541
    public func songChanged(_ id: String) {
        if id == songId { return }
        songId = id
        let resume = meantToPlay() || resumeTimer != nil
        clearTimer(resumeTimer)
        resumeTimer = nil
        dropPress()
        stilled = false
        endHandover()
        clearTimer(planTimer)
        planTimer = nil
        clearLed()
        post(.stop)
        window = nil
        decodedWindow = nil
        requestTicket += 1
        pending = nil
        failed = nil
        wanted = nil
        let angle = angleNow()
        self.angle = angle
        motion = host.playing() ? .turning(since: now, from: angle) : .still
        host.show(nil, scrubbing: false)
        if resume && !id.isEmpty {
            resumeTimer = clock.after(DeckConstants.songChangeSettleMs) { [weak self] in
                guard let self else { return }
                self.resumeTimer = nil
                if self.songId == id && !self.host.playing() && self.press?.taken != true { self.host.resume() }
            }
        }
        keepHere()
        loop()
        report()
    }

    /// deck.ts:1575 - a press on the live record: taken only past a tap's slop (takeOver) or after HOLD_MS.
    public func pressed(_ time: Double) {
        dropPress()
        letGo = nil
        press = Press(time: time)
        holdTimer = clock.after(DeckConstants.holdMs) { [weak self] in
            guard let self else { return }
            self.holdTimer = nil
            if let press = self.press, !press.taken {
                _ = self.takeOver()
                self.host.grabbed()
            }
        }
    }

    /// deck.ts:1603 - a press the deck doesn't take: the record stops under the finger.
    public func holdStill(_ held: Bool) {
        if held == stilled { return }
        if held {
            angle = angleNow()
            stilled = true
            host.turnFace(angle)
            if case .plan(let motion) = motion, motion.role != .spin {
                clearTimer(planTimer)
                clearLed()
                quieten(motion)
                planEnded(motion)
            }
            keep(recordAt())
            return
        }
        stilled = false
        switch motion {
        case .turning:
            motion = .turning(since: now, from: angle)
        case .plan(let plan) where plan.role == .spin:
            clearTimer(planTimer)
            planTimer = nil
            motion = host.playing() ? .turning(since: now, from: angle) : .still
        default:
            break
        }
        loop()
    }

    /// deck.ts:1635 - the hand inside the slop, not taken yet: kept for a quick grab.
    public func touched(_ time: Double, turned: Double, offset: Double) {
        guard let press, !press.taken else { return }
        let last = press.early.last
        if time < (last?.time ?? press.since) { return }
        if let last, time == last.time { press.early.removeLast() }
        press.early.append(Early(time: time, turned: turned, offset: offset))
    }

    /// deck.ts:1668 - the record taken; returns where the hand's turn counts from.
    @discardableResult
    public func takeOver(_ time: Double? = nil, quick: Bool = false) -> Double {
        let time = time ?? now
        guard let press else { return host.position() }
        if press.taken { return press.anchor }
        clearTimer(holdTimer)
        holdTimer = nil
        clearTimer(settleTimer)
        settleTimer = nil
        let motion = self.motion
        let since = quick && press.since < time ? press.since : time
        var moments: [Early]
        if since < time {
            moments = [Early(time: since, turned: 0, offset: 0)] + press.early.filter { $0.time > since && $0.time <= time }
        } else {
            moments = [Early(time: time, turned: 0, offset: 0)]
        }
        let lastMoment = moments[moments.count - 1]
        if lastMoment.time < time { moments.append(Early(time: time, turned: lastMoment.turned, offset: lastMoment.offset)) }
        let reach = now - DeckConstants.takeBackS * 1000
        var first = moments.firstIndex { $0.time >= reach } ?? -1
        if first < 0 { first = moments.count - 1 }
        let from = moments[first]
        let angle = quick ? angleNow() - (lastMoment.turned * 180) / Double.pi : angleAt(since)
        let at: Double, rate: Double, taking: Bool
        if case .plan(let plan) = motion, plan.role != .spin {
            clearTimer(planTimer)
            planTimer = nil
            clearLed()
            endHandover()
            let v = plans.planAt(plan.plan, (from.time - plan.since) / 1000).v
            at = planHasRecord(plan) ? recordAt(from.time) : recordAt(since) + from.offset
            press.intent = plan.role == .handover ? .play : .pause
            rate = plan.quiet ? 0 : Platter.voiceRate(v)
            taking = !plan.sounding
        } else {
            let playing = host.playing()
            let pendingResume = resumeTimer != nil
            clearTimer(resumeTimer)
            resumeTimer = nil
            let position = host.position()
            at = playing ? JSMath.max(0, position - (speed * JSMath.max(0, time - from.time)) / 1000) : position + from.offset
            if playing { host.hold() }
            press.intent = playing || pendingResume ? .play : .pause
            rate = playing ? speed : 0
            taking = true
        }
        let anchor = at - from.offset
        if taking && sounding(at) { take(at, rate, from.time) }
        press.taken = true
        press.anchor = anchor
        press.at = at
        if since < time {
            press.samples = [HandSample(time: since, turned: 0)] + moments.dropFirst().map { HandSample(time: $0.time, turned: $0.turned) }
        }
        self.angle = angle
        self.motion = .hand
        post(.hand(at: at, time: stamp(from.time)))
        var i = first + 1
        while i < moments.count {
            let moment = moments[i]
            if moment.time >= time { break }
            press.at = anchor + moment.offset
            post(.hand(at: press.at, time: stamp(moment.time)))
            i += 1
        }
        keep(press.at)
        loop()
        return anchor
    }

    /// deck.ts:1756 - the hand moved: a knot of the path the voice plays.
    public func hand(_ time: Double, turned: Double, at: Double) {
        guard let press, press.taken else { return }
        if let last = press.samples.last {
            if time < last.time { return }
            if time == last.time { press.samples.removeLast() }
        }
        press.samples.append(HandSample(time: time, turned: turned))
        while press.samples.count > 2 && time - press.samples[0].time > 4 * Platter.velocityWindowMs { press.samples.removeFirst() }
        press.at = at
        post(.hand(at: at, time: stamp(time)))
        if !covers(at, 0) { keep(at) }
        loop()
    }

    /// deck.ts:1778 - let go ('up') or the system took the touch (`cancel`).
    public func release(_ time: Double, cancel: Bool) -> DeckReleased {
        let press = self.press
        clearTimer(holdTimer)
        holdTimer = nil
        self.press = nil
        guard let press, press.taken else { return DeckReleased(seek: nil, play: false) }
        report()
        let song = host.song()
        let length = song?.length ?? 0
        if cancel {
            post(.stop)
            if press.intent == .play {
                host.resume()
                spin(plans.motor(0, 0, 0, speed))
            } else {
                motion = .still
            }
            host.show(nil, scrubbing: false)
            return DeckReleased(seek: nil, play: false)
        }
        let speed = Platter.releaseSpeed(press.samples, time)
        let last = press.samples[press.samples.count - 1].time
        let since = time - last <= Platter.releaseTailMs ? JSMath.min(time, last) : time
        if press.intent == .play {
            let plan = plans.motor(press.at, speed, length, self.speed)
            let lead = song.map { handoverLead($0, plan.x) } ?? 0
            if lead > 0 {
                return releaseLed(press, plan, lead, since)
            }
            if reduced || plan.duration <= DeckConstants.resumeInGestureS {
                post(.stop)
                motion = .turning(since: now, from: angleNow())
                host.show(nil, scrubbing: false)
                loop()
                letGo = (plan.x, now, 0)
                return DeckReleased(seek: plan.x, play: true)
            }
            letGo = (plan.x, now, plan.duration * 1000)
            startPlan(plan, .handover, press.at, sounding(press.at), since)
            keepPath(plan)
            return DeckReleased(seek: plan.x, play: false)
        }
        let plan = plans.coast(press.at, speed, length)
        if reduced || plan.duration == 0 {
            post(.stop)
            motion = .still
            host.show(nil, scrubbing: false)
            return DeckReleased(seek: plan.x, play: false)
        }
        startPlan(plan, .coast, press.at, sounding(press.at), since)
        keepPath(plan)
        return DeckReleased(seek: plan.x, play: false)
    }

    /// (3.5) a let-go of a playing record with a lead: the song resumed `lead` seconds before the plan's end - by a
    /// timer when that is still ahead, at once (sought to where the record will be when it is heard) when it isn't -
    /// and under Reduce Motion a take at the plan's end, the song sought ahead of it by the lead. The judge runs from
    /// the resume, at the target the song was sought to. Never in a web trace (their lead is 0).
    func releaseLed(_ press: Press, _ plan: Plan, _ lead: Double, _ since: Double) -> DeckReleased {
        if reduced {
            post(.stop)
            let sounds = sounding(plan.x)
            if sounds {
                //? the take holds the song's speed until the judge hears the song (HANDOVER_MAX_S at most): the
                //? handover below is the judge alone, so a take's own DRIVE_FOR_S would leave the voice slowing to
                //? still for the lead less 0.12 s before the song is heard
                let stamped = stamp(now)
                post(.take(at: plan.x, rate: Platter.voiceRate(speed), time: stamped, until: stamped + DeckConstants.handoverMaxS))
            }
            motion = .turning(since: now, from: angleNow())
            host.show(nil, scrubbing: false)
            loop()
            let target = HandoverTiming.reducedTarget(planX: plan.x, speed: speed, lead: lead)
            letGo = (target, now, 0)
            handOver(target, sounds, now, judgeOnly: true)
            return DeckReleased(seek: target, play: true)
        }
        letGo = (plan.x, now, plan.duration * 1000)
        startPlan(plan, .handover, press.at, sounding(press.at), since)
        keepPath(plan)
        guard case .plan(let started) = motion else { return DeckReleased(seek: plan.x, play: false) }
        let endMs = since + plan.duration * 1000
        let resumeAt = endMs - lead * 1000
        if resumeAt > now {
            ledTimer = clock.after(resumeAt - now) { [weak self] in
                guard let self else { return }
                self.ledTimer = nil
                guard case .plan(let current) = self.motion, current === started else { return }
                started.resumed = true
                self.handOver(plan.x, started.sounding && !started.quiet, self.now, judgeOnly: true)
                self.resumeAsked = true
                self.host.resume()
            }
            return DeckReleased(seek: plan.x, play: false)
        }
        let target = HandoverTiming.lateTarget(plan, plans, sinceMs: since, resumeMs: now, lead: lead, speed: speed)
        started.sought = target
        started.resumed = true
        handOver(target, started.sounding && !started.quiet, now, judgeOnly: true)
        resumeAsked = true
        return DeckReleased(seek: target, play: true)
    }

    /// deck.ts:1844 - a pause asked for on the turntable: the wind-down; returns where it stops, or nil.
    public func pausing() -> Double? {
        clearTimer(settleTimer)
        settleTimer = nil
        clearTimer(resumeTimer)
        resumeTimer = nil
        wasPlaying = false
        if press?.taken == true { return nil }
        let song = host.song()
        let at = host.position()
        if reduced {
            angle = angleNow()
            motion = .still
            return nil
        }
        let plan = plans.coast(at, speed, song?.length ?? 0)
        if plan.duration == 0 {
            angle = angleNow()
            motion = .still
            return nil
        }
        let sounding = windDown && self.sounding(at) && covers(at, plan.x - at)
        if sounding { take(at, speed) }
        startPlan(plan, .winddown, at, sounding)
        return sounding ? plan.x : nil
    }

    /// deck.ts:1877 - a play asked for on the turntable: where the record is now, for a coast, a run back or a wind-down.
    public func resuming() -> Double? {
        clearTimer(resumeTimer)
        resumeTimer = nil
        guard case .plan(let motion) = motion, !motion.quiet, motion.role != .spin else { return nil }
        if motion.role == .winddown && !motion.sounding { return nil }
        let x = heardNow() ?? plans.planAt(motion.plan, (now - motion.since) / 1000).x
        motion.sought = x
        return x
    }

    /// deck.ts:1893 - the arm was taken.
    public func armTaken() {
        if case .plan(let motion) = motion, motion.role != .spin { quieten(motion) }
    }

    /// The voice's report (deck.ts:2422).
    public func heard(_ heard: VoiceHeard) {
        self.heard = Heard(pos: heard.pos, rate: heard.rate, gain: heard.gain, at: now)
    }

    /// The deck engine changed - made, prepared, rested, its voice made (deck.ts:2432, the web's onAudio).
    public func audioChanged() {
        handWindow()
        keepHere()
        report()
    }

    /// (new) The voice's window is gone - the deck engine made the voice again at a new output rate (a route change,
    /// 4.6) - so the window is asked for again, where the record is. The web's context never changes its rate.
    public func windowDropped() {
        window = nil
        decodedWindow = nil
        requestTicket += 1
        pending = nil
        keepHere()
        report()
    }

    /// Reduce Motion turned on or off (deck.ts:2443).
    public func reducedChanged(_ reduced: Bool) {
        self.reduced = reduced
        loop()
    }

    // ----- the platter

    /// deck.ts:1904
    func recordAt(_ time: Double? = nil) -> Double {
        if case .plan(let motion) = motion, planHasRecord(motion) { return plans.planAt(motion.plan, ((time ?? now) - motion.since) / 1000).x }
        return host.position()
    }

    /// deck.ts:1912
    func planHasRecord(_ motion: PlanMotion) -> Bool {
        motion.role != .spin && !motion.quiet && (motion.sounding || motion.role != .winddown)
    }

    /// deck.ts:1918
    func meantToPlay() -> Bool {
        if let press, press.taken, press.intent == .play { return true }
        if case .plan(let motion) = motion, motion.role == .handover { return true }
        return false
    }

    /// deck.ts:1923
    func speedNow() -> Double {
        switch motion {
        case .turning: return speed
        case .plan(let motion): return plans.planAt(motion.plan, (now - motion.since) / 1000).v
        default: return 0
        }
    }

    func angleNow() -> Double {
        angleAt(now)
    }

    /// deck.ts:1935
    func angleAt(_ time: Double) -> Double {
        if reduced || stilled { return angle }
        switch motion {
        case .turning(let since, let from): return from + (Platter.degreesPerSecond * speed * (time - since)) / 1000
        case .plan(let motion): return motion.from + Platter.degreesFor(plans.planAt(motion.plan, (time - motion.since) / 1000).x - motion.x0)
        default: return angle
        }
    }

    /// deck.ts:1943 - a visual movement only.
    func spin(_ plan: Plan) {
        if reduced {
            motion = plan.target > 0 ? .turning(since: now, from: angle) : .still
            return
        }
        startPlan(plan, .spin, plan.phases.isEmpty ? 0 : plans.planAt(plan, 0).x, false)
    }

    /// deck.ts:1955
    func startPlan(_ plan: Plan, _ role: Role, _ x0: Double, _ sounding: Bool, _ since: Double? = nil) {
        let since = since ?? now
        let from = angleNow()
        clearTimer(planTimer)
        //? (3.4) a resume asked for an earlier plan is not this one's
        resumeAsked = false
        let sought = role == .winddown && !sounding ? x0 : plan.x
        let motion = PlanMotion(role: role, plan: plan, since: since, from: from, x0: x0, sounding: sounding, sought: sought, quiet: false)
        self.motion = .plan(motion)
        if sounding { drive(motion, since) }
        planTimer = clock.after(JSMath.max(0, plan.duration * 1000 - (now - since))) { [weak self] in self?.planEnded(motion) }
        loop()
    }

    /// deck.ts:1972
    func drive(_ motion: PlanMotion, _ time: Double) {
        let t = (time - motion.since) / 1000
        let (x, v) = plans.planAt(motion.plan, t)
        let accel = t < motion.plan.duration
            ? plans.acceleration(v, motion.role == .handover || (motion.role == .spin && motion.plan.target > 0), motion.plan.target) : 0
        let stamped = stamp(time)
        post(.drive(at: x, rate: Platter.voiceRate(v), accel: Platter.voiceRate(accel), time: stamped, until: stamped + DeckConstants.driveForS))
    }

    /// deck.ts:1980
    func planEnded(_ motion: PlanMotion) {
        planTimer = nil
        guard case .plan(let current) = self.motion, current === motion else { return }
        let angle = angleNow()
        if motion.role == .handover {
            self.motion = .turning(since: now, from: angle)
            host.show(nil, scrubbing: false)
            if motion.resumed {
                //? (3.5) resumed early by the lead: the voice holds the song's speed from here, and asks no second resume
                if motion.sounding && !motion.quiet {
                    //? silent at the resume, its window come since: the judge from here, at what the song was sought to
                    if handoverJudge == nil { handOver(motion.sought, true, now, judgeOnly: true) }
                    let stamped = stamp(motion.since + motion.plan.duration * 1000)
                    post(.drive(at: motion.plan.x, rate: Platter.voiceRate(speed), accel: nil, time: stamped, until: stamped + DeckConstants.handoverMaxS))
                }
            } else {
                handOver(motion.plan.x, motion.sounding && !motion.quiet, motion.since + motion.plan.duration * 1000)
                resumeAsked = true
                host.resume()
            }
            clearTimer(settleTimer)
            settleTimer = clock.after(DeckConstants.handoverMaxS * 1000) { [weak self] in
                guard let self else { return }
                self.settleTimer = nil
                if case .turning = self.motion, !self.host.playing(), self.press?.taken != true { self.spin(self.plans.coast(0, self.speed, 0)) }
            }
        } else if motion.role == .spin && motion.plan.target > 0 {
            self.motion = host.playing() ? .turning(since: now, from: angle) : .still
            self.angle = angle
        } else {
            self.angle = angle
            self.motion = .still
            if motion.sounding { post(.stop) }
            host.show(nil, scrubbing: false)
        }
        loop()
    }

    /// deck.ts:2014 - the record's sound holds the song's speed from `at` until the song plays past it, then fades.
    /// `judgeOnly` (3.5, a lead): the judge from the resume - its drive was the plan's, still running.
    func handOver(_ at: Double, _ sounding: Bool, _ time: Double, judgeOnly: Bool = false) {
        endHandover()
        if !sounding { return }
        if !judgeOnly {
            let stamped = stamp(time)
            post(.drive(at: at, rate: Platter.voiceRate(speed), accel: nil, time: stamped, until: stamped + DeckConstants.handoverMaxS))
        }
        let done = { [weak self] in
            guard let self else { return }
            self.endHandover()
            //? (3.5) heard before the plan's end: the web's own case of a play before the coast got back to speed
            if case .plan(let motion) = self.motion, motion.role == .handover {
                self.clearTimer(self.planTimer)
                self.planTimer = nil
                self.motion = .turning(since: self.now, from: self.angleNow())
                self.host.show(nil, scrubbing: false)
                self.loop()
            }
            self.post(.fade(seconds: DeckConstants.handoverFadeS))
        }
        let judge = { [weak self] (seconds: Double) in
            guard let self else { return }
            if Swift.abs(seconds - at) > DeckConstants.soughtElsewhereS || (self.host.playing() && seconds > at + 0.02) { done() }
        }
        handoverJudge = judge
        handoverOff = host.onPosition(judge)
        handoverTimer = clock.after(DeckConstants.handoverMaxS * 1000, done)
    }

    func clearLed() {
        clearTimer(ledTimer)
        ledTimer = nil
    }

    /// deck.ts:2038
    func endHandover() {
        handoverOff?()
        handoverOff = nil
        handoverJudge = nil
        clearTimer(handoverTimer)
        handoverTimer = nil
    }

    /// deck.ts:2048
    func quieten(_ motion: PlanMotion) {
        motion.quiet = true
        if motion.sounding {
            motion.sounding = false
            post(.stop)
        }
        host.show(nil, scrubbing: false)
    }

    /// deck.ts:2058
    func dropPress() {
        clearTimer(holdTimer)
        holdTimer = nil
        press = nil
    }

    /// deck.ts:2065
    func loop() {
        if raf != 0 || !showing { return }
        if !moving() {
            host.turnFace(angleNow())
            return
        }
        raf = clock.frame { [weak self] time in self?.onFrame(time) }
    }

    /// deck.ts:2074
    func moving() -> Bool {
        if press?.taken == true { return true }
        if reduced || stilled { return false }
        switch motion {
        case .turning, .plan: return true
        default: return false
        }
    }

    /// deck.ts:2080
    func onFrame(_ time: Double) {
        raf = 0
        if !showing { return }
        host.turnFace(angleNow())
        let press = self.press
        let motion = self.motion
        if handoverJudge != nil || letGo != nil {
            let seconds = host.position()
            handoverJudge?(seconds)
            noteBack(seconds)
        }
        if press?.taken == true {
            if heldFrame != 0 {
                let gap = time - heldFrame
                frames += 1
                if gap > DeckConstants.slowFrameMs { slowFrames += 1 }
                if gap > worstFrameMs { worstFrameMs = gap }
            }
            heldFrame = time
        } else {
            heldFrame = 0
        }
        if let press, press.taken {
            host.show(heardNow() ?? press.at, scrubbing: true)
        } else if case .plan(let motion) = motion {
            let t = (time - motion.since) / 1000
            let x = plans.planAt(motion.plan, t).x
            if motion.sounding && time > stampedTo { drive(motion, time) }
            if !motion.quiet && (motion.role == .coast || motion.role == .handover) && !covers(x, 0) { keep(x) }
            if !motion.quiet {
                if motion.role == .coast || motion.role == .handover { host.show(heardNow() ?? x, scrubbing: true) }
                else if motion.role == .winddown && motion.sounding { host.show(heardNow() ?? x, scrubbing: false) }
            }
            if t >= motion.plan.duration { planEnded(motion) }
        }
        if moving() { raf = clock.frame { [weak self] time in self?.onFrame(time) } }
    }

    // ----- the record's sound

    /// deck.ts:2126
    func heardNow() -> Double? {
        guard let heard, !(heard.gain < 0.5) else { return nil }
        let age = now - heard.at
        if age > DeckConstants.heardFreshMs { return nil }
        return heard.pos + (heard.rate * age) / 1000
    }

    func post(_ message: DeckPost) {
        host.post(message)
    }

    /// deck.ts:2145
    func take(_ at: Double, _ rate: Double, _ time: Double? = nil) {
        let stamped = stamp(time ?? now)
        post(.take(at: at, rate: rate, time: stamped, until: stamped + DeckConstants.driveForS))
    }

    /// deck.ts:2197 - page time as the voice's clock has it.
    func stamp(_ time: Double) -> Double {
        if time > stampedTo { stampedTo = time }
        return clock.stamp(time)
    }

    /// deck.ts:2206
    func sounding(_ at: Double) -> Bool {
        host.soundReady() && covers(at, 0)
    }

    /// deck.ts:2211
    func covers(_ at: Double, _ ahead: Double) -> Bool {
        guard let song = host.song(), let window, window.song == song.id else { return false }
        return at >= window.start && at + JSMath.max(0, ahead) <= window.end
    }

    /// deck.ts:2219
    func noteBack(_ seconds: Double) {
        guard let letGo else { return }
        let waited = now - letGo.since
        if host.playing() && seconds > letGo.at + 0.02
            && Swift.abs(seconds - letGo.at) < DeckConstants.soughtElsewhereS + (speed * waited) / 1000 {
            backMs = waited
            motorMs = letGo.motor
        } else if waited > letGo.motor + DeckConstants.handoverMaxS * 1000 {
            notBack += 1
        } else {
            return
        }
        self.letGo = nil
        report()
    }

    /// deck.ts:2234
    func onPosition(_ seconds: Double) {
        noteBack(seconds)
        if case .plan(let motion) = motion, motion.role != .spin, !motion.quiet, (host.song()?.length ?? 0) > 0,
           Swift.abs(seconds - motion.sought) > DeckConstants.soughtElsewhereS {
            quieten(motion)
        }
        if host.playing() && press == nil { keep(seconds) }
    }

    /// deck.ts:2246
    func keepHere() {
        if let press, press.taken { keep(press.at) }
        else if case .plan(let motion) = motion, motion.role != .spin, !motion.quiet {
            keep(plans.planAt(motion.plan, (now - motion.since) / 1000).x)
        } else {
            keep()
        }
    }

    /// deck.ts:2257
    func keepPath(_ plan: Plan) {
        let (low, high) = planReach(plan, plans)
        if !covers(low, high - low) { keep(low, high - low) }
    }

    /// deck.ts:2272 - the window kept ready where the record is.
    func keep(_ at: Double? = nil, _ span: Double? = nil) {
        guard showing, let song = host.song() else { return }
        var busy = press != nil || stilled || wanted == song.id
        if case .plan(let motion) = motion, motion.role != .spin { busy = true }
        let `where` = at ?? host.position()
        let unmet = !covers(`where`, 0)
        if !host.playing() && !busy && !unmet { return }
        if !song.flac {
            if refused?.song != song.id {
                refused = (song.id, "it isn't a FLAC file (it is \(song.kind.isEmpty ? "something else" : song.kind))")
                report()
            }
            return
        }
        if refused?.song == song.id { return }
        if !host.voiceMade() {
            if stilled { wanted = song.id }
            return
        }
        wanted = nil
        if let failed, failed.song == song.id, now < failed.until { return }
        let margins = DeckConstants.windowMargins(self.span?.song == song.id ? self.span!.seconds : DeckConstants.windowS)
        let refreshing = span == nil && host.playing() && !busy
        let room = song.length > 0 ? JSMath.max(0, song.length - `where` - 0.5) : Double.infinity
        let need = JSMath.max(0, span ?? (refreshing ? JSMath.min(margins.ahead * JSMath.max(1, speed), room) : 0))
        if covers(`where`, need) { return }
        if let pending, pending.song == song.id, `where` >= pending.from, `where` + need <= pending.to { return }
        let from = JSMath.max(0, ((`where` - margins.back) / DeckConstants.windowGridS).rounded(.down) * DeckConstants.windowGridS)
        if refreshing && covers(`where`, 0) {
            if from <= window!.start || now - refreshedAt < DeckConstants.refreshMinMs { return }
            refreshedAt = now
        }
        fetchWindow(song, from)
    }

    /// deck.ts:2311 (and decode, :2353) - one window on its way at a time, answered decoded by the host.
    func fetchWindow(_ song: DeckSong, _ from: Double) {
        let id = song.id
        requestTicket += 1
        let ticket = requestTicket
        decodedWindow = nil
        pending = Pending(song: id, from: from, to: from + DeckConstants.windowS, stage: .fetch)
        report()
        host.window(song, from: from, seconds: DeckConstants.windowS) { [weak self] result in
            guard let self, ticket == self.requestTicket else { return }
            switch result {
            case .success(let got):
                let start = got.start, end = got.end
                self.fetched += got.bytes
                self.lastFetchAt = self.now - self.since
                let short = end < from + DeckConstants.windowS - 0.01 && !(song.length > 0 && end >= song.length - 0.5)
                self.span = (id, short ? end - start : DeckConstants.windowS)
                self.pending = Pending(song: id, from: start, to: end, stage: .held)
                if let now = self.host.song(), now.id == id {
                    self.decodedWindow = Decoded(song: id, window: got)
                    self.handWindow()
                }
            case .failure(let error):
                self.pending = nil
                switch error {
                case .notFlac(let detail):
                    self.refused = (id, detail ?? "deadwax can't make it a window")
                case .pastTheEnd:
                    self.failed = (id, "deadwax said that is past the end of the song", self.now + DeckConstants.retryMs)
                case .offline:
                    self.failed = (id, "no window - this phone is offline and the song isn't all on it yet", self.now + DeckConstants.retryMs)
                case .undecodable(let words):
                    self.refused = (id, "this phone couldn't make its window - \(words.isEmpty ? "it gave no reason" : words)")
                case .channels(let count):
                    self.refused = (id, "it has \(count) channels")
                case .failed(let words):
                    self.failed = (id, "deadwax didn't send it - \(words)", self.now + DeckConstants.retryMs)
                }
            }
            self.report()
        }
    }

    /// deck.ts:2386
    func handWindow() {
        guard let decoded = decodedWindow, host.voiceMade() else { return }
        decodedWindow = nil
        if pending?.song == decoded.song { pending = nil }
        let got = decoded.window
        let length = got.frames
        post(.window(got))
        window = WindowHad(song: decoded.song, start: got.start, end: got.start + Double(length) / got.rate, bytes: got.bytes, decodedAt: got.rate)
        if let press, press.taken, heardNow() == nil, sounding(press.at) {
            let time = press.samples.last?.time ?? now
            take(press.at, 0, time)
            post(.hand(at: press.at, time: stamp(time)))
        } else if case .plan(let motion) = motion, !motion.sounding, !motion.quiet, motion.role == .coast || motion.role == .handover {
            let (x, v) = plans.planAt(motion.plan, (now - motion.since) / 1000)
            if sounding(x) {
                take(x, Platter.voiceRate(v))
                motion.sounding = true
            }
        }
        report()
    }

    func report() {
        changed?()
    }

    // ----- for Debug (slice 3)

    /// Why this song has no record's sound for good, or for now; whether a window is on its way.
    public var refusedWhy: String? { refused.flatMap { $0.song == host.song()?.id ? $0.why : nil } }
    public var failedWhy: String? { failed.flatMap { $0.song == host.song()?.id ? $0.why : nil } }
    public var loading: Bool { pending != nil }

    /// The report's window, for this song only (deck.ts report(), :2463-2469).
    public var reportWindow: DeckReport.Window? {
        guard let window, let song = host.song(), window.song == song.id else { return nil }
        return DeckReport.Window(start: window.start, end: window.end, kind: song.kind.isEmpty ? "FLAC" : song.kind,
                                 decodedAt: window.decodedAt, bytes: Double(window.bytes))
    }

    /// `/scrub`'s bytes since the turntable showed, and the last window's place (deck.ts report(), :2473-2474).
    public var fetchedBytes: Double { Double(fetched) }
    public var lastFetchedAt: Double { lastFetchAt }

    /// The report's health (deck.ts health(), :2450): the voice's part as the host counted it, the deck's own frames
    /// and hand-backs over it.
    public func health(_ sound: DeckReport.DeckHealth) -> DeckReport.DeckHealth {
        var health = sound
        health.frames = Double(frames)
        health.slowFrames = Double(slowFrames)
        health.worstFrameMs = worstFrameMs
        health.backMs = backMs
        health.motorMs = motorMs
        health.notBack = Double(notBack)
        return health
    }
}

/// The handover's arithmetic on the phone (3.5): the voice's delay as heard, the song's predicted start, the lead,
/// and where the song is sought for a resume that can't be early. Pure; HandoverPlanTests holds it.
public enum HandoverTiming {
    /// `D`: a knot stamped t is heard at t + D - HAND_DELAY_S, the limiter's lookahead, the clock's lead `l` and the
    /// deck engine's latency (outputLatency + ioBufferDuration).
    public static func voiceDelay(clockLead l: Double, latency: Double) -> Double {
        DeckVoice.handDelayS + DeckVoice.lookaheadS + l + latency
    }

    /// Before any start is known: 0.3 s (notes/ios.md's 0.2-0.4 s), and a stream's 0.3 s + position / 300.
    public static let firstGuessS = 0.3

    /// `E` for a local song: the median of the last five starts of its kind on this route.
    public static func predictedLocal(_ starts: [Double]) -> Double {
        let last = Array(starts.suffix(5)).sorted()
        if last.isEmpty { return firstGuessS }
        let middle = last.count / 2
        return last.count % 2 == 1 ? last[middle] : (last[middle - 1] + last[middle]) / 2
    }

    /// `E` for a streamed song at `position`: a + b x position fitted to its last five (position, start) pairs by least
    /// squares, b at least 0; one pair, or all at one position, its mean.
    public static func predictedStream(_ starts: [(position: Double, seconds: Double)], at position: Double) -> Double {
        let last = Array(starts.suffix(5))
        if last.isEmpty { return firstGuessS + position / 300 }
        let n = Double(last.count)
        let mx = last.reduce(0) { $0 + $1.position } / n
        let my = last.reduce(0) { $0 + $1.seconds } / n
        var sxx = 0.0, sxy = 0.0
        for pair in last {
            sxx += (pair.position - mx) * (pair.position - mx)
            sxy += (pair.position - mx) * (pair.seconds - my)
        }
        let b = sxx > 0 ? Swift.max(0, sxy / sxx) : 0
        let a = my - b * mx
        return a + b * position
    }

    /// The lead DeckRules takes: E less D, never below 0.
    public static func lead(predicted e: Double, voiceDelay d: Double) -> Double {
        Swift.max(0, e - d)
    }

    /// A song that can't start in time - a predicted E over HANDOVER_MAX_S less the plan's length - is not held across.
    public static func holdsAcross(predicted e: Double, planSeconds: Double) -> Bool {
        e <= DeckConstants.handoverMaxS - planSeconds
    }

    /// Too late for the timer: resumed at `resumeMs`, the song is sought to where the record will be when it is heard -
    /// the plan's position at resume + lead, carried on past the plan's end at the player's speed.
    public static func lateTarget<M: DeckMaths>(_ plan: Plan, _ plans: PlatterPlans<M>, sinceMs: Double, resumeMs: Double, lead: Double,
                                                speed: Double) -> Double {
        let t = (resumeMs - sinceMs) / 1000 + lead
        if t <= plan.duration { return plans.planAt(plan, t).x }
        return plan.x + speed * (t - plan.duration)
    }

    /// Reduce Motion: the take at the plan's end at the player's speed, and the song sought to where that take will be
    /// when the song is heard.
    public static func reducedTarget(planX: Double, speed: Double, lead: Double) -> Double {
        planX + speed * lead
    }
}
