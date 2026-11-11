import DeadwaxCore
import SwiftUI
import UIKit

/// A cover, by Navidrome's cover id and the size it is drawn at (points; asked at the nearest of CoverSize.steps for
/// the screen's scale): through deadwax's cover route, kept in memory, an empty square while it loads and when there
/// is none. Square; the caller gives it its frame. Hidden from VoiceOver - the row says what it is.
struct CoverImage: View {
    let id: String?
    let size: CGFloat

    @Environment(ServerModel.self) private var server
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    init(id: String?, size: CGFloat) {
        self.id = id
        self.size = size
    }

    private var step: Int { CoverSize.step(for: Int((size * scale).rounded(.up))) }

    var body: some View {
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
        .task(id: "\(server.address?.key ?? "")|\(id ?? "")|\(step)") {
            guard let id, let client = server.client else {
                image = nil
                return
            }
            image = CoverCache.shared.cached(client: client, id: id, size: step)
            if image == nil { image = await CoverCache.shared.load(client: client, id: id, size: step) }
        }
    }
}

/// Covers kept in memory by server, cover id and size: one fetch per cover at a time, a failure not asked again for
/// a minute. Held to `costLimit` bytes of decoded pixels (a 400 px tile is 640 KB, so about 150 of them), the least
/// recently used let go first; a fetch every view waiting on it has left - a tile scrolled past - is called off, so
/// a fast scroll through a big library doesn't queue covers nobody will see in front of the ones on screen.
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
        if let at = failedAt[key], Date().timeIntervalSince(at) < Self.againAfter { return nil }
        let task: Task<UIImage?, Never>
        if let asking = loading[key] {
            task = asking.task
            loading[key] = (task, asking.waiting + 1)
        } else {
            task = Task<UIImage?, Never> { [weak self] in
                let data = try? await client.cover(coverID: id, size: size)
                let image = data.flatMap(UIImage.init(data:))
                self?.landed(key, image, called: Task.isCancelled)
                return image
            }
            loading[key] = (task, 1)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.left(key, task) }
        }
    }

    /// A fetch done: kept, or - unless it was called off - a failure not asked again for a minute. One called off is
    /// out of `loading` already (`left`), and a new fetch of the same cover may be there now.
    private func landed(_ key: String, _ image: UIImage?, called off: Bool) {
        if !off { loading[key] = nil }
        if let image {
            images.setObject(image, forKey: key as NSString, cost: Self.cost(image))
            failedAt[key] = nil
        } else if !off {
            failedAt[key] = Date()
        }
    }

    /// A view waiting on `task` left: the fetch called off once nobody waits for it.
    private func left(_ key: String, _ task: Task<UIImage?, Never>) {
        guard let asking = loading[key], asking.task == task else { return }
        if asking.waiting > 1 {
            loading[key] = (task, asking.waiting - 1)
        } else {
            loading[key] = nil
            task.cancel()
        }
    }
}
