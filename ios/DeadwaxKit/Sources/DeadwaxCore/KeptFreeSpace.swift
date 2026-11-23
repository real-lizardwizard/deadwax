import Foundation

/// The planner's free space, kept a while (23 Nov, notes/ios.md "A slow start, and the watchdog"): the volume's
/// "important usage" capacity takes the system a while to work out, and the planner asks at every plan - several a second
/// while songs land, on the main thread. A reading answers for `keptFor` seconds on the uptime clock, less the bytes
/// downloaded since it was read (more, the bytes removed); then it is read again. A reading from the future - another
/// boot's clock - is read again at once.
public struct KeptFreeSpace: Sendable, Equatable {
    /// How long a reading answers.
    public static let keptFor: Double = 30

    /// The free bytes read.
    public let bytes: Int64
    /// When, on the uptime clock (seconds).
    public let at: Double
    /// The bytes downloaded here when it was read.
    public let used: Int64

    public init(bytes: Int64, at: Double, used: Int64) {
        self.bytes = bytes
        self.at = at
        self.used = used
    }

    /// The free space now, from this reading - nil once it is too old to answer (or from the future): read it again.
    public func estimate(now: Double, used now_: Int64) -> Int64? {
        guard now.isFinite, at.isFinite, now >= at, now - at < Self.keptFor else { return nil }
        let (grown, overflow) = now_.subtractingReportingOverflow(used)
        guard !overflow else { return nil }
        let (left, under) = bytes.subtractingReportingOverflow(grown)
        guard !under else { return nil }
        return max(left, 0)
    }
}
