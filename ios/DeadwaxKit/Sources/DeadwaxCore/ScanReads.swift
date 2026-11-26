import Foundation

/// How one read of the library's scan ended (LibraryScanModel's `Read`).
public enum ScanRead: Sendable, Equatable {
    /// It landed: fresh, or the one in hand still the answer.
    case landed
    /// It failed - the scan says why.
    case failed
    /// A newer read took over, or it was cancelled: nothing changed.
    case dropped
}

/// The reads of one library scan, by ticket (R12's review - notes/ios.md "The redesign, slice R12: Needs a look", its
/// "After review"): LibraryScanModel's, so only the newest read lands - and whoever waits on the newest is told how it
/// ended.
///
/// In queue mode Edit album reads Needs a look's own scan (one read, one ETag), and on the Mac Edit an album's editor
/// reads its folder list's. A read of the page's begun while the editor's was out - ⌘R, at R12's review - took over from
/// it: the editor's came back `.dropped`, its look-up did nothing, and the editor waited on it for good (Apply off, the
/// steps dimmed, no Look again - and `reopen()` asks again only for a first read cut off, and only as the page comes
/// back). A look-up carries its read to an answer instead (`answer`): one a newer read took over waits for that one's
/// end, and one that came to nothing is asked again. Everything here runs on the main actor, as the scan's models do.
@MainActor
public final class ScanReads {
    /// The newest read's ticket.
    public private(set) var newest = 0
    /// The newest read is still out.
    public private(set) var out = false
    /// How the newest read that ended, ended.
    private var last: ScanRead?
    private var waiting: [CheckedContinuation<ScanRead, Never>] = []

    public init() {}

    /// A read begun: its ticket - the newest now.
    public func begin() -> Int {
        newest += 1
        out = true
        return newest
    }

    /// `ticket` is the newest read's: its answer is the one that lands.
    public func isNewest(_ ticket: Int) -> Bool { ticket == newest }

    /// `ticket`'s read ended `end`. The newest's: over, and everyone waiting on it told - `end`. One a newer read took
    /// over: nothing changed - `.dropped`.
    @discardableResult
    public func ended(_ ticket: Int, _ end: ScanRead) -> ScanRead {
        guard ticket == newest else { return .dropped }
        out = false
        last = end
        let told = waiting
        waiting.removeAll()
        for wait in told { wait.resume(returning: end) }
        return end
    }

    /// How the newest read begun after `ticket` ended - waited for while it is out (an even newer one taking over is
    /// waited for in turn) - or nil, when none began after it.
    public func end(after ticket: Int) async -> ScanRead? {
        guard newest > ticket else { return nil }
        guard out else { return last }
        return await withCheckedContinuation { (wait: CheckedContinuation<ScanRead, Never>) -> Void in
            waiting.append(wait)
        }
    }

    /// A look-up's read carried to an answer (EditAlbumModel.lookUp, through LibraryScanModel.readShared): `read`, given
    /// its ticket, its own end - or, a newer read having taken over from it, that one's end, waited for. Asked again,
    /// once, when what it waited on came to nothing (a read cancelled with its page, or this one cancelled while the
    /// newest). Never past `cancelled()`: a look-up called off with its own page (the Mac's page left while it read)
    /// stays `.dropped`, and the page asks again as it comes back (EditAlbumModel.reopen).
    public func answer(cancelled: @MainActor () -> Bool, read: @MainActor (Int) async -> ScanRead) async -> ScanRead {
        var tries = 0
        while true {
            let ticket = begin()
            let own = await read(ticket)
            guard own == .dropped, !cancelled() else { return own }
            if let newer = await end(after: ticket), newer != .dropped || cancelled() {
                return newer
            }
            tries += 1
            guard tries < Self.tries else { return .dropped }
        }
    }

    /// A look-up's reads at most: its own, and once more when what it waited on came to nothing.
    public static let tries = 2
}
