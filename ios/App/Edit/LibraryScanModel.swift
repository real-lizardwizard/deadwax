import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// The library's scan as Edit album and Choose the folder read it (notes/ios-specs/phase8-managing.md 3.1): every
/// album folder deadwax's scan lists, without its tracks (`GET /library/albums?tracks=false`), held in memory by the
/// page that asked it with its ETag - so asking again is a 304 when nothing changed - and never on disk: managing shows
/// nothing stale as live. Only the newest read lands; a read that fails keeps what is in hand and says why
/// (EditWords.said, the library's own words for whoever runs deadwax); a read cancelled is neither, and changes nothing.
@MainActor
@Observable
final class LibraryScanModel {
    /// How a read ended.
    enum Read: Sendable {
        /// It landed: fresh, or the one in hand still the answer.
        case landed
        /// It failed - said in `failure`.
        case failed
        /// A newer read took over, or it was cancelled: nothing changed.
        case dropped
    }

    /// The scan in hand - nil until one lands.
    private(set) var answer: ScanAnswer?
    /// A read is on its way.
    private(set) var reading = false
    /// The last read failed: why, and whether whoever asked may see deadwax's own words - nil once one lands. Kept as
    /// the error, so each place that draws it says it its own way (`failure(saying:)` - slice 6's review).
    private(set) var failed: (error: any Error, admin: Bool)?
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var reads = 0

    /// The scan has answered at least once.
    var loaded: Bool { answer != nil }
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
        reads += 1
        let ticket = reads
        reading = true
        do {
            let got = try await client.libraryScan(ifNoneMatch: answer == nil ? nil : etag)
            guard ticket == reads else { return .dropped }
            if case .fresh(let fresh, let tag) = got {
                answer = fresh
                etag = tag
            }
            failed = nil
            reading = false
            return .landed
        } catch {
            guard ticket == reads else { return .dropped }
            reading = false
            // a cancellation (the page gone) is neither a failure nor an answer: what was there stays
            guard !APIFailure.isCancellation(error) else { return .dropped }
            failed = (error, admin)
            return .failed
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
