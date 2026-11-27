import Foundation

/// (Speed A, fix 4 - notes/ios.md "Speed A: what's asked again") When a list a screen shows is asked again as it shows:
/// the album index's own rule (AlbumIndexState.refreshIfOld), for a list kept outside it - the Library's artists. Asked
/// when none has landed, or the one in hand landed over `freshMs` ago - and never while one asked under the same writes
/// is on its way, as the index waits for the ask of its own generation. The index's generation moves with a write; here
/// a write deadwax was told of (the count the app keeps - an Edit's apply, a delete, a re-file, a Get) asks at once, and
/// a list asked within `AlbumEdit.settleMs` of the writes moving may be from before Navidrome scanned them, so it is asked
/// again at each show until one asked after that has landed - each show asked afresh, as before, for those seconds. A
/// last ask that failed asks again too. A pull, or the Library's Refresh, asks regardless: this is only the screen showing.
public enum ListFreshness {
    /// The album index's minute.
    public static let freshMs: Int64 = AlbumIndexState.freshMs

    /// A list landed: when, in milliseconds on the asker's clock; how many writes deadwax had been told of when it was
    /// asked; and whether it was asked long enough after they last moved for Navidrome to have scanned them (`settled`).
    public struct Landed: Equatable, Sendable {
        public let at: Int64
        public let writes: Int
        public let settled: Bool

        public init(at: Int64, writes: Int, settled: Bool) {
            self.at = at
            self.writes = writes
            self.settled = settled
        }
    }

    /// Whether a list asked at `askedAt` was asked at least `AlbumEdit.settleMs` after the writes last moved
    /// (`writesMovedAt`, nil when they haven't since the person signed in).
    public static func settled(askedAt: Int64, writesMovedAt: Int64?) -> Bool {
        guard let writesMovedAt else { return true }
        return askedAt - writesMovedAt >= Int64(AlbumEdit.settleMs)
    }

    /// Whether the screen showing now asks the list again: `landed` the list in hand (nil for none), `writes` the writes
    /// told of now, `failed` whether the newest ask failed, `onItsWay` the writes the ask on its way was asked under (nil
    /// for none).
    public static func asks(landed: Landed?, writes: Int, failed: Bool, onItsWay: Int?, now: Int64) -> Bool {
        if let onItsWay, onItsWay == writes { return false }
        guard let landed, !failed, landed.writes == writes, landed.settled else { return true }
        return now - landed.at > freshMs
    }
}
