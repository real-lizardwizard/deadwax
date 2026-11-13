/// The play speed and its fader - the web's ui/src/lib/playSpeed.ts, ported line for line (notes/ios-specs/
/// turntable.md 5.1): the speeds the player takes, in hundredths, the fader's octave scale and its 1x detent, its keys,
/// its place on the plinth and a finger on it. `PlaySpeed` holds what needs no transcendental function;
/// `PlaySpeedScale` the scale's log and pow, over a `DeckMaths` (Fixtures/deck/turntable.json, PlaySpeedTests). The
/// words it makes are TurntableWords'.

public enum PlaySpeed {
    /// The slowest and fastest the player plays (playSpeed.ts:24-25), and the song's own speed (:27).
    public static let min = 0.25
    public static let max = 2.0
    public static let normal = 1.0
    /// A drag within this of 1x lands on 1x exactly - the fader's detent (:29).
    public static let detentWidth = 0.02
    /// What an arrow key moves it by, and Page Up and Page Down (:31-32).
    public static let step = 0.01
    public static let page = 0.1

    /// The speed in hundredths (:35).
    public static func roundSpeed(_ speed: Double) -> Double {
        JSMath.round(speed * 100) / 100
    }

    /// Whether a value is a speed the player takes (:40).
    public static func isSpeed(_ value: Double) -> Bool {
        value.isFinite && value >= min && value <= max
    }

    /// Any number as a speed: held to the range, in hundredths - 1x for one that isn't a number (:45).
    public static func clampSpeed(_ speed: Double) -> Double {
        if !speed.isFinite { return normal }
        return roundSpeed(JSMath.max(min, JSMath.min(max, speed)))
    }

    /// The detent: a speed within SPEED_DETENT of 1x is 1x (:51).
    public static func detent(_ speed: Double) -> Double {
        Swift.abs(speed - normal) <= detentWidth + 1e-9 ? normal : speed
    }

    /// What a key does to the speed, nil for a key that isn't the fader's (:83).
    public static func speedKey(_ key: String, _ speed: Double) -> Double? {
        switch key {
        case "ArrowUp", "ArrowRight": return clampSpeed(speed + step)
        case "ArrowDown", "ArrowLeft": return clampSpeed(speed - step)
        case "PageUp": return clampSpeed(speed + page)
        case "PageDown": return clampSpeed(speed - page)
        case "Home": return min
        case "End": return max
        default: return nil
        }
    }

    // ----- the fader on the plinth (playSpeed.ts:104-153)

    /// The fader, in the plinth's units (:113): its line, top and bottom of its travel, the gap from the record, its
    /// slot, its knob and the mark at 1x.
    public static let fader = (x: 359.0, top: 150.0, bottom: 318.0, clear: 1.0, slot: 6.0, slotRadius: 2.0)
    public static let knob = (width: 20.0, height: 12.0, radius: 3.0, grip: 1.5, gripInset: 3.0)
    public static let mark = (overhang: 2.0, thick: 2.0)
    /// The readout under it (:123).
    public static let readout = (x: 344.0, y: 349.0)
    /// Where the fader's target may start: the record's rim (:127).
    public static let faderFrom = TurntableGeometry.record.x + TurntableGeometry.record.r + fader.clear

    /// The fader's touch target across the plinth, in its units, for a plinth `stage` points wide: a `hit` wide, at
    /// most `cap` of the stage, never over the record (:137).
    public static func faderTarget(_ stage: Double, hit: Double = 44, cap: Double = 0.14) -> (left: Double, right: Double) {
        let width = JSMath.min((hit / JSMath.max(stage, 1e-9)) * TurntableGeometry.stage.width, cap * TurntableGeometry.stage.width)
        let left = JSMath.max(faderFrom, fader.x - width / 2)
        return (left, left + width)
    }

    /// How far the knob travels on screen for a stage `height` tall (:151).
    public static func faderTravel(_ height: Double) -> Double {
        ((fader.bottom - fader.top) / TurntableGeometry.stage.height) * JSMath.max(0, height)
    }

    /// A finger on the fader (:157): where it went down, and once past the slop where the drag is measured from.
    public struct FaderDrag: Equatable, Sendable {
        public var pointer: Int
        public var y0: Double
        public var from: (y: Double, share: Double)?
        public static func == (a: FaderDrag, b: FaderDrag) -> Bool {
            a.pointer == b.pointer && a.y0 == b.y0 && a.from?.y == b.from?.y && a.from?.share == b.from?.share
        }
    }

    public static func faderStart(_ pointer: Int, _ y: Double) -> FaderDrag {
        FaderDrag(pointer: pointer, y0: y, from: nil)
    }

    /// The tick at 1x (5.1, question 17's A - the phone's, the web has no way to give one): one light impact as a drag
    /// crosses INTO the detent - the speed it moved to exactly 1x, from any other. The arrows' steps and the readout's
    /// tap give none.
    public static func ticks(from: Double, to: Double) -> Bool {
        to == normal && from != normal
    }

    /// The finger let go: the drag is over - unless it is another pointer's (:190).
    public static func faderEnd(_ drag: FaderDrag?, _ pointer: Int) -> FaderDrag? {
        guard let drag else { return nil }
        return drag.pointer == pointer ? nil : drag
    }
}

/// The fader's octave scale, over a `DeckMaths`.
public struct PlaySpeedScale<M: DeckMaths> {
    public let maths: M
    public init(_ maths: M) { self.maths = maths }

    /// How far up the fader a speed is, 0 to 1, by octaves (:56).
    public func faderShare(_ speed: Double) -> Double {
        let held = JSMath.max(PlaySpeed.min, JSMath.min(PlaySpeed.max, speed.isFinite ? speed : PlaySpeed.normal))
        return maths.log(held / PlaySpeed.min) / maths.log(PlaySpeed.max / PlaySpeed.min)
    }

    /// The speed at a share of the fader's travel, in hundredths, through the detent (:62).
    public func speedAt(_ share: Double) -> Double {
        let at = JSMath.max(0, JSMath.min(1, share.isFinite ? share : 0))
        return PlaySpeed.detent(PlaySpeed.clampSpeed(PlaySpeed.min * maths.pow(PlaySpeed.max / PlaySpeed.min, at)))
    }

    /// The knob's centre for a speed, as a CSS share of the stage's height (:146).
    public func knobTop(_ speed: Double) -> String {
        let fader = PlaySpeed.fader
        return TurntableGeometry.pct((fader.bottom - faderShare(speed) * (fader.bottom - fader.top)) / TurntableGeometry.stage.height)
    }

    /// The fader's drag moved (:177): nothing until past the slop, then the speed the finger's travel puts it at -
    /// `same` where the web hands the very drag back (anything but the move that passes the slop).
    public func faderMove(_ drag: PlaySpeed.FaderDrag?, _ pointer: Int, _ y: Double, _ travel: Double, _ speed: Double)
        -> (drag: PlaySpeed.FaderDrag?, speed: Double?, same: Bool) {
        guard let drag, drag.pointer == pointer, travel > 0 else { return (drag, nil, true) }
        var held = drag
        //? the web hands the very drag back once it has its `from`; a new one the move that sets it
        let same = held.from != nil
        if held.from == nil {
            let moved = y - held.y0
            if Swift.abs(moved) < TurntableGeometry.tapSlop { return (drag, nil, true) }
            held.from = (held.y0 + JSMath.sign(moved) * TurntableGeometry.tapSlop, faderShare(speed))
        }
        let from = held.from!
        return (held, speedAt(from.share + (from.y - y) / travel), same)
    }
}

// ----- kept on the phone, and the pace measured (persisted.ts:302-311; playSpeed.ts:236-257)

extension PlaySpeed {
    /// The device's speed, under the web's key (persisted.ts STORAGE_KEYS.playerSpeed): '0.25' to '2' as text.
    public static let storageKey = "deadwax-player-speed"

    /// The kept speed as the web reads it (readPlayerSpeed, :302): nothing or blank is 1x, a number that is a speed
    /// is that speed in hundredths, anything else 1x. The phone writes only what `stored` makes, so JavaScript's
    /// other number forms (hex and the like) are not read.
    public static func read(_ saved: String?) -> Double {
        guard let saved else { return normal }
        let text = WebText.trim(saved)
        if text.isEmpty { return normal }
        let decimal = text.unicodeScalars.allSatisfy { (c: Unicode.Scalar) -> Bool in
            ("0"..."9").contains(c) || c == "." || c == "e" || c == "E" || c == "+" || c == "-"
        }
        guard decimal, let speed = Double(text), isSpeed(speed) else { return normal }
        return roundSpeed(speed)
    }

    /// The speed as the web writes it (writePlayerSpeed, :309): `String(speed)`.
    public static func stored(_ speed: Double) -> String {
        JSNumber.string(speed)
    }

    /// How much playing the measured pace is taken over, in seconds of the clock, and how much it needs before it
    /// says anything (PACE_WINDOW_S, PACE_MIN_S).
    public static let paceWindowS = 8.0
    public static let paceMinS = 2.0

    /// One step of playing: seconds of song, over seconds of the clock (PaceSample).
    public struct PaceSample: Equatable, Sendable {
        public var media: Double
        public var wall: Double
        public init(media: Double, wall: Double) {
            self.media = media
            self.wall = wall
        }
    }

    /// The window with a step added, its oldest steps let go past PACE_WINDOW_S of the clock (paceStep). The caller
    /// leaves out a step across a seek, a pause or a song change - nothing to measure there.
    public static func paceStep(_ window: [PaceSample], _ sample: PaceSample) -> [PaceSample] {
        if !(sample.wall > 0) || !(sample.media >= 0) { return window }
        var kept = window + [sample]
        var wall = kept.reduce(0) { (sum: Double, step: PaceSample) -> Double in sum + step.wall }
        while kept.count > 1 && wall - kept[0].wall >= paceWindowS { wall -= kept.removeFirst().wall }
        return kept
    }

    /// Seconds of song a second of the clock over the window - nil under PACE_MIN_S of it (paceOf).
    public static func paceOf(_ window: [PaceSample]) -> Double? {
        let wall = window.reduce(0) { (sum: Double, step: PaceSample) -> Double in sum + step.wall }
        if wall < paceMinS { return nil }
        return window.reduce(0) { (sum: Double, step: PaceSample) -> Double in sum + step.media } / wall
    }
}

/// The speed as the player keeps it, and what the engine is told (notes/ios-specs/turntable.md 5.1, 5.2; James's
/// answers, 2026-11-13). PlaybackEngine plays 1x out of the speed's path - the song's own samples - and any other
/// speed through one varispeed; leaving 1x begins the lanes again into it (a short gap), and while a drag crosses 1x
/// the chain plays on at rate 1, so the mark is passed without a gap. A drag let go AT 1x is told `exact`, which
/// takes the lanes out of the chain again (another short gap): from there 1x is the file's own samples, bit for
/// bit. A jump to 1x - the readout's tap, the chip's, a VoiceOver step onto it - is a let-go too.
///
/// `restarts` says the engine may begin its lanes again for this send - leaving 1x, or `exact` - so the player can
/// keep the `.loading` the engine says through it off the screen and the lock screen (SpeedRestartHold).
public struct SpeedControl: Equatable, Sendable {
    public struct Send: Equatable, Sendable {
        public var speed: Double
        public var exact: Bool
        public var restarts: Bool
        public init(speed: Double, exact: Bool, restarts: Bool) {
            self.speed = speed
            self.exact = exact
            self.restarts = restarts
        }
    }

    /// The speed the player plays at, in hundredths, 0.25 to 2.
    public private(set) var speed: Double
    /// The engine may be holding its lanes in the chain at 1x: a drag (or nothing yet told) left it there.
    public private(set) var chained: Bool

    /// The kept speed, at launch: the engine is told it before anything plays, so a lane starts in the chain.
    public init(speed: Double) {
        self.speed = PlaySpeed.clampSpeed(speed)
        chained = self.speed != PlaySpeed.normal
    }

    /// What the engine is told as it is made: the kept speed, or nothing at 1x (the chain is never made).
    public var atStart: Send? {
        speed == PlaySpeed.normal ? nil : Send(speed: speed, exact: false, restarts: false)
    }

    /// The fader mid-drag, at `to` (speedAt's, through its detent): through 1x the chain plays on at rate 1.
    public mutating func dragged(to: Double) -> Send? {
        let next = PlaySpeed.clampSpeed(to)
        if next == speed { return nil }
        let leaving = speed == PlaySpeed.normal
        speed = next
        chained = true
        return Send(speed: next, exact: false, restarts: leaving)
    }

    /// The fader let go, or its touch taken by the system: at 1x after a drag through the chain, exact again.
    public mutating func letGo() -> Send? {
        guard speed == PlaySpeed.normal, chained else { return nil }
        chained = false
        return Send(speed: PlaySpeed.normal, exact: true, restarts: true)
    }

    /// A jump - the readout's tap, the chip's, a VoiceOver step: exact when it lands on 1x.
    public mutating func set(_ to: Double) -> Send? {
        let next = PlaySpeed.clampSpeed(to)
        if next == PlaySpeed.normal {
            guard next != speed || chained else { return nil }
            speed = next
            chained = false
            return Send(speed: next, exact: true, restarts: true)
        }
        if next == speed { return nil }
        let leaving = speed == PlaySpeed.normal
        speed = next
        chained = true
        return Send(speed: next, exact: false, restarts: leaving)
    }
}

/// The lanes begun again for the speed publish `.loading` then `.playing` (PlaybackEngine's `beginAgain`, through
/// `begin`) - a few milliseconds on the phone, during which nothing has stopped for the listener: the transport and the
/// lock screen keep showing the song playing. Asked as a send that `restarts` goes to the engine while the song plays;
/// the engine's next `.loading` of that entry within `seconds` is the restart's. Past `seconds` a loading still going
/// shows, as any other wait does (a song that really is waiting for its bytes).
public struct SpeedRestartHold: Equatable, Sendable {
    public static let seconds = 1.0

    /// The entry playing when the send went, and until when its loading is the restart's.
    public private(set) var entry: Int?
    public private(set) var until = -Double.infinity
    /// The engine says `.loading` and it is the restart's: shown as playing.
    public private(set) var hiding = false

    public init() {}

    /// A send that may begin the lanes again went to the engine while `entry` played.
    public mutating func asked(entry: Int, at now: Double) {
        self.entry = entry
        until = now + Self.seconds
    }

    /// The engine's phase as it comes. Playing ends the hold (the restart is done); any other phase than loading ends
    /// it too (a pause, a failure, the end: never hidden).
    public mutating func phase(loading: Bool, playing: Bool, entry: Int?, at now: Double) {
        if loading, let entry, entry == self.entry, now < until {
            hiding = true
            return
        }
        hiding = false
        if playing || !loading { self.entry = nil }
    }

    /// Time has passed: a loading hidden past the hold shows. True when that changed what shows.
    public mutating func expired(at now: Double) -> Bool {
        guard hiding, now >= until else { return false }
        hiding = false
        entry = nil
        return true
    }
}

/// The lock screen told a new speed during a drag (MPNowPlayingInfoCenter is another process, and a drag is a change a
/// frame): at once, then no more often than every `gap` seconds, the last change of a run always told at the end of its
/// gap - so the lock screen's clock runs at the speed the drag ended on.
public struct SpeedPublishing: Equatable, Sendable {
    public static let gap = 0.25

    public enum When: Equatable, Sendable {
        /// tell it now
        case now
        /// tell it at this time (nothing waits for it yet)
        case at(Double)
        /// one is already waiting, which will tell this change too
        case waiting
    }

    public private(set) var lastAt = -Double.infinity
    public private(set) var waiting = false

    public init() {}

    /// The speed changed at `now`.
    public mutating func changed(at now: Double) -> When {
        if waiting { return .waiting }
        if now - lastAt >= Self.gap { return .now }
        waiting = true
        return .at(lastAt + Self.gap)
    }

    /// The lock screen was told, at `now` - for the speed's sake or any other (a pause, a song).
    public mutating func told(at now: Double) {
        lastAt = now
        waiting = false
    }
}
