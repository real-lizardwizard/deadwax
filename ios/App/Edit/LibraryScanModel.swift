import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// The library's scan as Edit album and Choose the folder read it (notes/ios-specs/phase8-managing.md 3.1): every
/// album folder deadwax's scan lists, without its tracks (`GET /library/albums?tracks=false`), held in memory by the
/// page that asked it with its ETag - so asking again is a 304 when nothing changed. (Speed A, fix 3) And kept on disk
/// with its ETag, per server and session (Core's ScanKept), so a page's first read - the first Edit of a launch - asks
/// with it too; the copy on disk is drawn only once deadwax's 304 says it is still the scan, so managing still shows
/// nothing stale as live. Only the newest read lands; a read that fails keeps what is in hand and says why
/// (EditWords.said, the library's own words for whoever runs deadwax); a read cancelled is neither, and changes nothing.
@MainActor
@Observable
final class LibraryScanModel {
    /// How a read ended (Core's ScanRead): it landed, it failed (said in `failure`), or a newer read took over or it was
    /// cancelled - nothing changed.
    typealias Read = ScanRead

    /// The scan in hand - nil until one lands.
    private(set) var answer: ScanAnswer?
    /// A read is on its way.
    private(set) var reading = false
    /// The last read failed: why, and whether whoever asked may see deadwax's own words - nil once one lands. Kept as
    /// the error, so each place that draws it says it its own way (`failure(saying:)` - slice 6's review).
    private(set) var failed: (error: any Error, admin: Bool)?
    @ObservationIgnored private var etag: String?
    /// (R12's review) The reads by ticket - the newest's answer is the one that lands, and a read shared with another
    /// reader is carried to an answer (`readShared`).
    private let reads = ScanReads()

    /// The scan has answered at least once.
    var loaded: Bool { answer != nil }
    /// (Slice 7's review) A read has ended, answered or failed - the web's `loaded` (useLibrary sets it as each read
    /// ends), which its ladders mean: a failed first read is Try again, not the spinner for good.
    var ended: Bool { answer != nil || failed != nil }
    var albums: [ScanAlbum] { answer?.albums ?? [] }

    /// The last read's failure in the editor's words (EditWords.said over READ_FAILED's "Couldn't read the library.").
    var failure: String? { failure(saying: EditWords.readFailed) }

    /// The last read's failure, `what` saying what didn't work when deadwax gave no words of its own - Needs a look's
    /// READ_FAILED for its first read, CHECK_FAILED for one again over the list on screen (slice 6).
    func failure(saying what: String) -> String? {
        failed.map { EditWords.said($0.error, failed: what, admin: $0.admin) }
    }

    /// The scan read again.
    @discardableResult
    func read(client: DeadwaxClient?, admin: Bool) async -> Read {
        guard let client else { return .dropped }
        return await fetch(client, admin: admin, ticket: reads.begin())
    }

    /// (R12's review - notes/ios.md "The redesign, slice R12: Needs a look", "After review") The scan read again for a
    /// reader that shares it - Edit album's look-up, over Needs a look's scan in queue mode or the Mac's folder list's:
    /// carried to an answer (ScanReads.answer). A read of the other reader's that takes over from this one (Needs a
    /// look's ⌘R) is waited for and its end is this one's, so the look-up never waits on a read that came to nothing;
    /// one called off with its task (the page left) is dropped, as `read`'s is.
    func readShared(client: DeadwaxClient?, admin: Bool) async -> Read {
        guard let client else { return .dropped }
        return await reads.answer(cancelled: { Task.isCancelled }) { (ticket: Int) -> Read in
            await self.fetch(client, admin: admin, ticket: ticket)
        }
    }

    /// The read `ticket` is: only the newest lands, and its end is told to whoever waits on it (ScanReads.ended).
    ///
    /// (Speed A, fix 3) A page's first read sends the ETag of the scan kept on disk for this server and session
    /// (ScanKept), so an unchanged library is a 304 - and only then is the kept copy the scan in hand, with the 304's
    /// headers. A fresh answer is kept on disk in its place. A kept copy deadwax vouched for that can't be read is passed
    /// over: the scan is asked again without its ETag, and that answer replaces it.
    private func fetch(_ client: DeadwaxClient, admin: Bool, ticket: Int) async -> Read {
        reading = true
        do {
            let first = answer == nil
            let disk = first ? await Self.kept(client) : nil
            var got = try await client.libraryScanKeeping(ifNoneMatch: first ? disk?.etag : etag)
            // a 304 to the kept copy's ETag: the copy is the scan - unless it can't be read, then asked again without it
            var copy: (answer: ScanAnswer, etag: String)?
            if first, let disk, case .unchanged(let unchanged) = got {
                if let scan = await Self.decoded(disk, unchanged) {
                    copy = (scan, disk.etag)
                } else {
                    got = try await client.libraryScanKeeping(ifNoneMatch: nil)
                }
            }
            guard reads.isNewest(ticket) else { return .dropped }
            if let copy {
                answer = copy.answer
                etag = copy.etag
            }
            if case .fresh(let fresh, let tag, let body) = got {
                answer = fresh
                etag = tag
                Self.keep(client, etag: tag, body: body)
            }
            failed = nil
            reading = false
            return reads.ended(ticket, .landed)
        } catch {
            guard reads.isNewest(ticket) else { return .dropped }
            reading = false
            // a cancellation (the page gone) is neither a failure nor an answer: what was there stays
            guard !APIFailure.isCancellation(error) else { return reads.ended(ticket, .dropped) }
            failed = (error, admin)
            return reads.ended(ticket, .failed)
        }
    }

    /// (Speed A) The scan kept on disk for the client's server and session, read off the main actor - nil for none.
    private static func kept(_ client: DeadwaxClient) async -> ScanKept? {
        let server = client.server.key
        let session = client.session
        return await Task.detached(priority: .userInitiated) { () -> ScanKept? in
            ScanFiles.inCaches()?.read(server: server, session: session)
        }.value
    }

    /// (Speed A) The kept copy read as the scan, with the 304's headers - decoded off the main actor, as a fresh answer is.
    private static func decoded(_ disk: ScanKept, _ unchanged: HTTPResponse) async -> ScanAnswer? {
        await Task.detached(priority: .userInitiated) { () -> ScanAnswer? in disk.answer(unchanged) }.value
    }

    /// (Speed A) A fresh scan kept on disk as its server's, for the session that read it - written off the main actor.
    private static func keep(_ client: DeadwaxClient, etag: String?, body: Data) {
        guard let etag, !etag.isEmpty else { return }
        let record = ScanKept(server: client.server.key, session: client.session, etag: etag, body: body)
        Task.detached(priority: .utility) { ScanFiles.inCaches()?.write(record) }
    }

    /// (Phase 8, slice 7) Library care's Rescan (`POST /library/rescan?tracks=false`): the cache dropped and every file
    /// read again - its answer the scan in hand and its ETag kept, as a read's, and only the newest landing. What came of
    /// it, for CareRuns: a refusal (a 4xx) and one that never answered (it may have finished) are kept in `failed` as a
    /// read's failure is; a cancellation, or a newer read, changes nothing.
    func rescan(client: DeadwaxClient?, admin: Bool) async -> CareRuns.Rescanned {
        guard let client else { return .dropped }
        let ticket = reads.begin()
        reading = true
        do {
            let (fresh, tag) = try await client.rescan()
            guard reads.isNewest(ticket) else { return .dropped }
            answer = fresh
            etag = tag
            failed = nil
            reading = false
            reads.ended(ticket, .landed)
            return .landed(albums: fresh.albums.count)
        } catch {
            guard reads.isNewest(ticket) else { return .dropped }
            reading = false
            guard !APIFailure.isCancellation(error) else {
                reads.ended(ticket, .dropped)
                return .dropped
            }
            failed = (error, admin)
            reads.ended(ticket, .failed)
            return RetagFlow.outcome(of: error) == .refused ? .refused : .unanswered
        }
    }
}

/// A folder's cover as deadwax's library has it (`/library/art?album=`), kept in memory by the server, the folder, its
/// art's mtime and the size drawn - a cover replaced has a new mtime, so it is asked again - and never on disk. One
/// fetch however many views wait; a folder with none (a 404) is nothing, for a minute.
@MainActor
final class FolderCoverCache {
    static let shared = FolderCoverCache()

    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    private var failedAt: [String: Date] = [:]

    private init() {
        images.totalCostLimit = 24 * 1024 * 1024
    }

    static func key(_ client: DeadwaxClient, path: String, mtime: Double, pixels: Int) -> String {
        "\(client.server.key)|\(path)|\(mtime)|\(pixels)"
    }

    func cached(_ key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    /// The cover drawn at `pixels` on its longer side (0: as it is) - nil for none, or a failure within the minute.
    func load(client: DeadwaxClient, path: String, mtime: Double, pixels: Int) async -> UIImage? {
        let key = Self.key(client, path: path, mtime: mtime, pixels: pixels)
        if let image = cached(key) { return image }
        if let at = failedAt[key], Date().timeIntervalSince(at) < CoverCache.againAfter { return nil }
        let task: Task<UIImage?, Never>
        if let asking = loading[key] {
            task = asking
        } else {
            task = Task<UIImage?, Never> {
                let data = try? await client.libraryArt(path: path)
                guard let raw = data.flatMap({ UIImage(data: $0) }) else { return nil }
                if pixels > 0 {
                    let side = CGFloat(pixels)
                    let scale = side / max(raw.size.width, raw.size.height, 1)
                    let size = CGSize(width: raw.size.width * min(scale, 1), height: raw.size.height * min(scale, 1))
                    return await raw.byPreparingThumbnail(ofSize: size) ?? raw
                }
                return await raw.byPreparingForDisplay() ?? raw
            }
            loading[key] = task
        }
        let image = await task.value
        loading[key] = nil
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            images.setObject(image, forKey: key as NSString, cost: max(cost, 1))
            failedAt[key] = nil
        } else {
            failedAt[key] = Date()
        }
        return image
    }
}

/// A folder's cover, square (FolderCoverCache): the empty square while it loads and for a folder with none. Hidden
/// from VoiceOver - the row or the header says what it is.
struct FolderCover: View {
    let path: String
    /// The scan's `art_mtime`: a new cover is a new mtime.
    let mtime: Double
    /// The scan says the folder has a cover: none is asked for when it hasn't.
    let hasArt: Bool
    /// Its longer side in pixels (0: as it is, for the full screen).
    let pixels: Int

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        let key = server.client.map { FolderCoverCache.key($0, path: path, mtime: mtime, pixels: pixels) } ?? ""
        let shown = image ?? (key.isEmpty ? nil : FolderCoverCache.shared.cached(key))
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            image = nil
            guard hasArt, let client = server.client else { return }
            let got = await FolderCoverCache.shared.load(client: client, path: path, mtime: mtime, pixels: pixels)
            guard !Task.isCancelled else { return }
            image = got
        }
    }
}
