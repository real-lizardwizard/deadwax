import DeadwaxCore
import SwiftUI
import UIKit

/// A cover, by Navidrome's cover id and the size it is drawn at (points; asked at the nearest of CoverSize.steps for
/// the screen's scale): through deadwax's cover route, kept in memory, an empty square while it loads and when there
/// is none. Square; the caller gives it its frame. Hidden from VoiceOver - the row says what it is.
///
/// The cache is the cover's one owner: the view draws what the cache holds, and keeps the image a load gave it only
/// while it is on screen (a lazy grid keeps the state of tiles scrolled past, so a tile holding its own copy would keep
/// every cover ever shown). Only the newest load draws: one for a cover the view no longer shows - a quick Next and
/// Previous, the album page's cover id changing as the album answers - is dropped. A new session (signed in again)
/// asks again for a cover that failed under the old one.
struct CoverImage: View {
    let id: String?
    let size: CGFloat

    @Environment(ServerModel.self) private var server
    @Environment(\.displayScale) private var scale
    /// What a load gave this view, under the key it was asked by; let go when the view goes.
    @State private var loaded: Loaded?

    private struct Loaded {
        let key: String
        let image: UIImage
    }

    init(id: String?, size: CGFloat) {
        self.id = id
        self.size = size
    }

    private var step: Int { CoverSize.step(for: Int((size * scale).rounded(.up))) }

    /// The server, the session (by its hash: a sign-in again asks again), the cover and the size.
    private var key: String {
        "\(server.address?.key ?? "")|\(server.client?.session?.hashValue ?? 0)|\(id ?? "")|\(step)"
    }

    var body: some View {
        let key = self.key
        let image = loaded?.key == key ? loaded?.image : cached
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            guard let id, let client = server.client,
                  CoverCache.shared.cached(client: client, id: id, size: step) == nil else { return }
            let got = await CoverCache.shared.load(client: client, id: id, size: step)
            // a load for a cover this view has left (its key changed, or it went) draws nothing
            guard !Task.isCancelled, let got else { return }
            loaded = Loaded(key: key, image: got)
        }
        .onDisappear { loaded = nil }
    }

    /// The cover as the cache holds it now.
    private var cached: UIImage? {
        guard let id, let client = server.client else { return nil }
        return CoverCache.shared.cached(client: client, id: id, size: step)
    }
}

/// Covers kept in memory by server, cover id and size: one fetch per cover at a time, a failure not asked again for
/// a minute under the same session (a sign-in again, or the app coming back to the front, asks again at once).
/// Held to `costLimit` bytes of decoded pixels (a 400 px tile is 640 KB, so about 150 of them), the least recently
/// used let go first; a fetch every view waiting on it has left - a tile scrolled past - is called off, so a fast
/// scroll through a big library doesn't queue covers nobody will see in front of the ones on screen. Each cover is
/// decoded as it arrives, off the main thread (`byPreparingForDisplay`), not at its first draw on it.
@MainActor
final class CoverCache {
    static let shared = CoverCache()

    /// The decoded covers kept, in bytes.
    static let costLimit = 96 * 1024 * 1024

    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: (task: Task<UIImage?, Never>, waiting: Int)] = [:]
    private var failedAt: [String: Date] = [:]
    private static let againAfter: TimeInterval = 60

    init() {
        images.totalCostLimit = Self.costLimit
    }

    private static func cost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return max(cg.bytesPerRow * cg.height, 1)
    }

    private static func key(_ client: DeadwaxClient, _ id: String, _ size: Int) -> String {
        "\(client.server.key)|\(id)|\(size)"
    }

    func cached(client: DeadwaxClient, id: String, size: Int) -> UIImage? {
        images.object(forKey: Self.key(client, id, size) as NSString)
    }

    /// The cover, fetched once however many views wait for it - nil when there is none, it failed, or the view left
    /// (its task cancelled) before it came.
    func load(client: DeadwaxClient, id: String, size: Int) async -> UIImage? {
        let key = Self.key(client, id, size)
        if let image = images.object(forKey: key as NSString) { return image }
        let flight = Self.flightKey(key, client)
        if let at = failedAt[flight], Date().timeIntervalSince(at) < Self.againAfter { return nil }
        let task: Task<UIImage?, Never>
        if let asking = loading[flight] {
            task = asking.task
            loading[flight] = (task, asking.waiting + 1)
        } else {
            task = Task<UIImage?, Never> { [weak self] in
                let data = try? await client.cover(coverID: id, size: size)
                // UIImage(data:) only reads the header; the pixels are decoded here, off the main thread
                let raw = data.flatMap(UIImage.init(data:))
                let image = await raw?.byPreparingForDisplay() ?? raw
                self?.landed(key, flight, image, called: Task.isCancelled)
                return image
            }
            loading[flight] = (task, 1)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.left(flight, task) }
        }
    }

    /// The app came back to the front (a WireGuard tunnel up again, say): covers that failed are asked again the next
    /// time a view shows them.
    func forgetFailures() {
        failedAt = [:]
    }

    /// A fetch, and its failure, are the session's: one under a session that has ended (a 401 while the sign-in was
    /// up) says nothing of the next, and a view signed in again doesn't wait on it. By the session's hash, so no
    /// cookie is kept in the key.
    private static func flightKey(_ key: String, _ client: DeadwaxClient) -> String {
        "\(key)|\(client.session?.hashValue ?? 0)"
    }

    /// A fetch done: kept, or - unless it was called off - a failure not asked again for a minute. One called off is
    /// out of `loading` already (`left`), and a new fetch of the same cover may be there now.
    private func landed(_ key: String, _ flight: String, _ image: UIImage?, called off: Bool) {
        if !off { loading[flight] = nil }
        if let image {
            images.setObject(image, forKey: key as NSString, cost: Self.cost(image))
            failedAt[flight] = nil
        } else if !off {
            failedAt[flight] = Date()
        }
    }

    /// A view waiting on `task` left: the fetch called off once nobody waits for it.
    private func left(_ flight: String, _ task: Task<UIImage?, Never>) {
        guard let asking = loading[flight], asking.task == task else { return }
        if asking.waiting > 1 {
            loading[flight] = (task, asking.waiting - 1)
        } else {
            loading[flight] = nil
            task.cancel()
        }
    }
}
