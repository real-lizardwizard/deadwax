import Foundation

/// Now Playing's scrubber - the web app's ui/src/lib/scrub.ts, ported line for line: where a point on the bar is in
/// the song, what a key (VoiceOver's adjust) seeks to, a drag that seeks only when let go (cancelled, nowhere; the
/// song changing under it, dropped), what the bar shows meanwhile, the seek on its way that the bar holds to until it
/// lands - and the readout of where a seek really landed. Held to what the TypeScript answers: Tests/DeadwaxCoreTests/
/// Fixtures/screens/scrub.json (ui/test/scrub.sim.cjs's checks by name, seeded drags and seek readings, sweeps),
/// written by ios/scripts/export-screen-vectors.cjs. scrub.ts is one of the web's engine files: it is read here,
/// never changed.
///
/// Times are seconds, `now` and `since` milliseconds. The numbers go through JavaScript's Math.max and Math.min
/// (`JSNumber`), so NaN and -0 come out as the web's do.
public enum Scrub {
    /// What an arrow key (VoiceOver's swipe up and down) moves by.
    public static let keyStep = 5.0
    /// What Page Up and Page Down move by - no iOS gesture has it.
    public static let pageStep = 30.0
    /// How long the bar holds to a seek's target before taking the song's position again, landed or not.
    public static let pendingMaxMs = 20_000.0
    /// The clock this near the song's length counts as at its end.
    public static let endSlack = 0.35
    /// A seek that landed this near where it was asked landed there.
    public static let landedWithin = 1.5

    /// A position as Now Playing's clocks write it (scrub.ts clock).
    public static func clock(_ seconds: Double) -> String { Format.clock(seconds) }

    static func clamp(_ seconds: Double, _ length: Double) -> Double {
        JSNumber.max(0, JSNumber.min(seconds, length))
    }

    /// Where a point on the bar is in the song: `x` against the bar's `left` and `width` - 0 with no length or no
    /// width yet.
    public static func timeAt(x: Double, left: Double, width: Double, length: Double) -> Double {
        guard length > 0, width > 0 else { return 0 }
        return clamp(((x - left) / width) * length, length)
    }

    /// What a key seeks to from `from`, or nil for a key that isn't the bar's (and with no length yet): the arrows a
    /// step, Page Up and Down a page, Home the start, End the end. Keys by the web's names ("ArrowRight", ...).
    public static func keyTarget(_ key: String, from: Double, length: Double) -> Double? {
        guard length > 0 else { return nil }
        let at = clamp(from, length)
        switch key {
        case "ArrowRight", "ArrowUp": return clamp(at + keyStep, length)
        case "ArrowLeft", "ArrowDown": return clamp(at - keyStep, length)
        case "PageUp": return clamp(at + pageStep, length)
        case "PageDown": return clamp(at - pageStep, length)
        case "Home": return 0
        case "End": return length
        default: return nil
        }
    }

    /// VoiceOver's adjust: up (increment) a step forward, down a step back - the arrows' targets.
    public static func adjusted(increment: Bool, from: Double, length: Double) -> Double? {
        keyTarget(increment ? "ArrowUp" : "ArrowDown", from: from, length: length)
    }

    /// A finger on the bar: which one, the song it went down on, and where it is now.
    public struct Drag: Sendable, Equatable {
        public let pointer: Int
        public let track: String
        public let time: Double

        public init(pointer: Int, track: String, time: Double) {
            self.pointer = pointer
            self.track = track
            self.time = time
        }
    }

    /// Put down: it is where the finger is.
    public static func dragStart(pointer: Int, track: String, time: Double) -> Drag {
        Drag(pointer: pointer, track: track, time: time)
    }

    /// Moved: it follows - only the finger that started it; a move to where it is already is the same drag.
    public static func dragMove(_ drag: Drag?, pointer: Int, time: Double) -> Drag? {
        guard let drag, drag.pointer == pointer else { return drag }
        return drag.time == time ? drag : Drag(pointer: drag.pointer, track: drag.track, time: time)
    }

    /// How a finger left the bar: lifted, or the system took the touch.
    public enum Release: String, Sendable { case up, cancel }

    /// Let go: seeks where the last move put it - a cancel seeks nowhere - and lets go. Another finger changes nothing.
    public static func dragEnd(_ drag: Drag?, pointer: Int, how: Release) -> (drag: Drag?, seek: Double?) {
        guard let drag, drag.pointer == pointer else { return (drag, nil) }
        return (nil, how == .up ? drag.time : nil)
    }

    /// The song changed under the finger: the drag is let go of. The same song: it stays.
    public static func dragFor(_ drag: Drag?, track: String) -> Drag? {
        guard let drag else { return nil }
        return WebText.same(drag.track, track) ? drag : nil
    }

    /// What the bar shows: the finger while there is a drag, else the song's position - never past the end, nor
    /// before the start; with no length yet, the position as it is (never below 0).
    public static func shownTime(_ drag: Drag?, position: Double, length: Double) -> Double {
        let at = drag?.time ?? position
        return length > 0 ? clamp(at, length) : JSNumber.max(0, JSNumber.truthy(at) ? at : 0)
    }

    /// A seek on its way: where to, and when it was asked (ms).
    public struct PendingSeek: Sendable, Equatable {
        public let target: Double
        public let since: Double

        public init(target: Double, since: Double) {
            self.target = target
            self.since = since
        }
    }

    /// The position the bar is given: a seek's target while it is on its way (for `pendingMaxMs` at most - one that
    /// never landed lets go), else the song's position. So the thumb never snaps back.
    public static func reportedPosition(_ pending: PendingSeek?, position: Double, now: Double) -> Double {
        guard let pending, now - pending.since < pendingMaxMs else { return position }
        return pending.target
    }

    // MARK: where a seek really landed (Debug's readout)

    /// The latest seek, and what is known of where it landed (scrub.ts SeekReading).
    public struct SeekReading: Sendable, Equatable {
        public struct ClockEnd: Sendable, Equatable {
            /// when the clock first reached the song's end (ms)
            public let at: Double
            /// what it read then
            public let position: Double
        }

        public let asked: Double
        /// the song's length when the seek was asked for - what its end is judged against
        public let length: Double
        public let track: String
        /// the element's clock at 'seeked'; nil until then
        public var said: Double?
        /// no later 'seeked' can be this seek's: another seek took its place, the song changed or failed
        public var closed: Bool
        /// still the latest seek in a song still playing, so its end can speak for it
        public var judging: Bool
        public var clockEnd: ClockEnd?
        /// seconds: + it really landed later in the song than asked, - earlier, 0 where asked; nil unjudged
        public var off: Double?
    }

    /// What happens to a seek after it is asked for (scrub.ts SeekEvent).
    public enum SeekEvent: Sendable, Equatable {
        case asked(asked: Double, length: Double, track: String)
        case seeked(position: Double)
        /// a seek the listener didn't make with the bar ("previous" restarting, a failed song resumed)
        case otherSeek
        case songChange
        /// the song failed: a seek on its way never lands, and the end is no longer this seek's
        case failed
        /// paused, other than by the song ending
        case paused
        case clock(position: Double, at: Double)
        case ended(position: Double, at: Double, rate: Double)
    }

    /// The reading after an event (seekStep).
    public static func seekStep(_ reading: SeekReading?, _ event: SeekEvent) -> SeekReading? {
        if case .asked(let asked, let length, let track) = event {
            return SeekReading(asked: asked, length: length, track: track, said: nil, closed: false, judging: length > 0,
                               clockEnd: nil, off: nil)
        }
        guard var reading else { return nil }
        switch event {
        case .asked:
            return reading
        case .seeked(let position):
            if reading.said == nil && !reading.closed { reading.said = position }
            return reading
        case .otherSeek, .songChange, .failed:
            if reading.judging || !reading.closed {
                reading.judging = false
                reading.closed = true
            }
            return reading
        case .paused:
            reading.judging = false
            return reading
        case .clock(let position, let at):
            guard reading.judging, reading.said != nil, reading.clockEnd == nil else { return reading }
            if position >= reading.length - endSlack { reading.clockEnd = .init(at: at, position: position) }
            return reading
        case .ended(let position, let at, let rate):
            guard reading.judging, reading.said != nil else { return reading }
            let short = JSNumber.max(0, reading.length - position)
            let on = reading.clockEnd.map {
                JSNumber.max(0, ((at - $0.at) / 1000) * (JSNumber.truthy(rate) ? rate : 1) - (reading.length - $0.position))
            } ?? 0
            let off = WebText.round((short - on) * 10) / 10
            reading.judging = false
            reading.off = abs(off) < landedWithin ? 0 : off
            return reading
        }
    }

    /// The readout's words (describeSeek).
    public static func describeSeek(_ reading: SeekReading?) -> String {
        guard let reading else { return "No seek yet" }
        let asked = "Last seek: asked \(clock(reading.asked))"
        guard let said = reading.said else { return reading.closed ? "\(asked), interrupted" : "\(asked), seeking…" }
        let saidLine = "\(asked), the player said \(clock(said))"
        guard let off = reading.off else { return saidLine }
        if off == 0 { return "\(saidLine) · the song ended on time, so it landed there" }
        let by = JSNumber.string(WebText.round(abs(off)))
        let really = clock(WebText.round(reading.asked + off))
        return off > 0
            ? "\(saidLine) · the song ran out \(by) s before its clock did, so it really landed at about \(really)"
            : "\(saidLine) · the song played on \(by) s after its clock ended, so it really landed at about \(really)"
    }
}
