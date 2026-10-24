import Foundation

/// Where in a song to start: an exact frame, counted at the rate the engine heard it at - or
/// seconds, when the song's rate isn't known yet (a seek or the lock screen's scrubber before the
/// song has been heard, a song not decoded yet). The source turns it into a frame at the file's own
/// rate, once that rate is sure, so a seek to 60 s is 60 s into a 192 kHz file as into a 44.1 kHz
/// one, and going on from where a song was (a pause, a new route, a call) is the exact sample.
///
/// Pure, so it is tested on Linux; the engine (DeadwaxAudio) only uses it.
public enum StartPoint: Sendable, Equatable {
    /// `frame` frames in, counted at `rate` (the file's own rate, as the engine heard it).
    case frame(Int64, rate: Double)
    /// `seconds` in, at whatever rate the file turns out to have.
    case seconds(Double)

    /// A song's beginning.
    public static let beginning = StartPoint.frame(0, rate: 0)

    /// The frame at `rate` - exact when it was counted at that rate (or `rate` is unknown, 0).
    public func frame(at rate: Double) -> Int64 {
        switch self {
        case .frame(let frame, let counted):
            if counted == rate || counted <= 0 || rate <= 0 { return max(frame, 0) }
            return max(Int64((Double(frame) / counted * rate).rounded()), 0)
        case .seconds(let seconds):
            guard rate > 0, seconds.isFinite, seconds > 0 else { return 0 }
            return Int64((seconds * rate).rounded(.down))
        }
    }

    /// How far in, in seconds.
    public var seconds: Double {
        switch self {
        case .frame(let frame, let rate): return rate > 0 ? Double(max(frame, 0)) / rate : 0
        case .seconds(let seconds): return seconds.isFinite ? max(seconds, 0) : 0
        }
    }
}
