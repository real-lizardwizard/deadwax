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
/// a minute.
@MainActor
final class CoverCache {
    static let shared = CoverCache()

    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    private var failedAt: [String: Date] = [:]
    private static let againAfter: TimeInterval = 60

    init() {
        images.countLimit = 400
    }

    private static func key(_ client: DeadwaxClient, _ id: String, _ size: Int) -> String {
        "\(client.server.key)|\(id)|\(size)"
    }

    func cached(client: DeadwaxClient, id: String, size: Int) -> UIImage? {
        images.object(forKey: Self.key(client, id, size) as NSString)
    }

    func load(client: DeadwaxClient, id: String, size: Int) async -> UIImage? {
        let key = Self.key(client, id, size)
        if let image = images.object(forKey: key as NSString) { return image }
        if let at = failedAt[key], Date().timeIntervalSince(at) < Self.againAfter { return nil }
        if let task = loading[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = try? await client.cover(coverID: id, size: size) else { return nil }
            return UIImage(data: data)
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            images.setObject(image, forKey: key as NSString)
            failedAt[key] = nil
        } else {
            failedAt[key] = Date()
        }
        return image
    }
}
