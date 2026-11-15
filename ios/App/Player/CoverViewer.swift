import DeadwaxCore
import ImageIO
import SwiftUI
import UIKit

extension View {
    /// Now Playing's cover, opening the cover viewer at a tap (notes/ios.md "The cover, full screen"). Only a tap: the
    /// drag Now Playing closes by is the cover's parent's, and a tap's gesture gives way to it as the finger moves. For
    /// VoiceOver the cover becomes a button, "Cover of Dummy - show full screen". A song with no cover opens nothing.
    func opensCoverFullScreen(_ track: QueueTrack) -> some View {
        modifier(CoverOpens(track: track))
    }
}

/// The cover viewer's one opening: the cover shown, from the song it was tapped on - a song change behind it changes
/// nothing in it.
struct ViewedCover: Identifiable, Equatable {
    let id = UUID()
    let coverID: String
    let album: String
    let artist: String
}

private struct CoverOpens: ViewModifier {
    let track: QueueTrack
    @State private var viewing: ViewedCover?

    func body(content: Content) -> some View {
        content
            .contentShape(Corners.artShape)
            .onTapGesture { open() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CoverViewerWords.open(album: track.album))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityHidden(track.coverArt == nil)
            .fullScreenCover(item: $viewing) { (cover: ViewedCover) in
                CoverViewer(cover: cover) { put(nil) }
            }
    }

    private func open() {
        guard let id = track.coverArt, !id.isEmpty, viewing == nil else { return }
        put(ViewedCover(coverID: id, album: track.album, artist: track.artist))
    }

    /// Up or down with no slide: the viewer fades itself in and out.
    private func put(_ cover: ViewedCover?) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { viewing = cover }
    }
}

/// The cover, full screen: fitted on the page's black, the status bar hidden; pinch or double-tap to zoom, a drag to
/// pan while zoomed, and closed by a drag down at rest, the close button, or VoiceOver's escape (CoverZoomer has the
/// gestures). It shows the cover Now Playing has drawn at once - the largest the cover cache holds, else the one kept
/// with a downloaded album - and the full size, asked of deadwax with no size, over it as it lands.
struct CoverViewer: View {
    let cover: ViewedCover
    let done: () -> Void

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @State private var drawn: UIImage?
    @State private var full: UIImage?
    /// The full size's ask has ended (it came, or it couldn't): with nothing drawn, the empty square.
    @State private var asked = false
    /// How far down a finger holds the cover.
    @State private var dragged: CGFloat = 0
    /// In: faded in once it opens, out as it closes.
    @State private var shown = false
    @State private var closing = false

    private static let fade = Animation.easeOut(duration: 0.2)

    /// The full size once it is in (and isn't smaller), else what was drawn.
    private var image: UIImage? {
        guard let full else { return drawn }
        guard let drawn else { return full }
        return CoverZoom.showsFull(drawnPixels: Self.pixels(drawn), fullPixels: Self.pixels(full)) ? full : drawn
    }

    var body: some View {
        let ground = shown ? CoverZoom.groundOpacity(dragged: Double(dragged)) : 0
        ZStack {
            Palette.page
                .opacity(ground)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            CoverZoomer(image: image, label: CoverViewerWords.image(album: cover.album, artist: cover.artist),
                        onDrag: held, onClose: close)
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
            if image == nil {
                if asked {
                    Corners.artShape
                        .fill(Palette.coverEmpty)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.horizontal, 8)
                        .accessibilityLabel(CoverViewerWords.image(album: cover.album, artist: cover.artist))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel(LibraryWords.loading)
                }
            }
            closeButton
                .opacity(shown ? ground : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.horizontal, 12)
        }
        .statusBarHidden(true)
        .presentationBackground(.clear)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .onAppear {
            drawn = drawnCover()
            withAnimation(Self.fade) { shown = true }
        }
        .task { await load() }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(Typeface.symbol(.body).weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .background(Palette.card, in: Corners.controlShape)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CoverViewerWords.close)
    }

    /// A finger holding the cover down - followed as it goes, eased back as it springs back.
    private func held(_ down: CGFloat, settling: Bool) {
        if settling {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragged = down }
        } else {
            dragged = down
        }
    }

    /// Faded out, then gone.
    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(Self.fade) {
            shown = false
        } completion: {
            done()
        }
    }

    // MARK: the pictures

    /// What Now Playing has drawn: the largest size of this cover the cover cache holds.
    private func drawnCover() -> UIImage? {
        guard let client = server.client else { return nil }
        for size in CoverSize.steps.reversed() {
            if let image = CoverCache.shared.cached(client: client, id: cover.coverID, size: size) { return image }
        }
        return nil
    }

    /// Nothing drawn: the cover kept with a downloaded album, from the phone. Then the full size, while deadwax can be
    /// reached - the last one kept, or asked for.
    private func load() async {
        defer { asked = true }
        if drawn == nil { drawn = drawnCover() }
        if drawn == nil, let kept = KeptCovers.shared.url(for: cover.coverID) {
            drawn = await Task.detached(priority: .userInitiated) { CoverCache.thumbnail(kept, size: CoverSize.hero) }.value
        }
        guard reachability.online, let client = server.client else { return }
        let key = FullCovers.key(client, cover.coverID)
        var bytes = FullCovers.shared.bytes(for: key)
        if bytes == nil {
            bytes = try? await client.fullCover(coverID: cover.coverID)
            guard !Task.isCancelled else { return }
            if let bytes { FullCovers.shared.keep(bytes, for: key) }
        }
        guard let bytes else { return }
        let decoded = await Task.detached(priority: .userInitiated) { FullCovers.decode(bytes) }.value
        guard !Task.isCancelled, let decoded else { return }
        full = decoded
    }

    private static func pixels(_ image: UIImage) -> Double {
        Double(image.size.width * image.scale) * Double(image.size.height * image.scale)
    }
}

/// The full-size cover last opened, kept as the bytes deadwax sent (a few MB, not the decoded picture's tens), so
/// opening the same cover again doesn't ask for it again. One at a time, by server, session and cover; let go when
/// iOS says memory is short.
@MainActor
final class FullCovers {
    static let shared = FullCovers()

    private var last: (key: String, bytes: Data)?
    private var warning: NSObjectProtocol?

    private init() {
        warning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                         object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FullCovers.shared.last = nil }
        }
    }

    static func key(_ client: DeadwaxClient, _ coverID: String) -> String {
        "\(client.server.key)|\(client.session?.hashValue ?? 0)|\(coverID)"
    }

    func bytes(for key: String) -> Data? {
        last?.key == key ? last?.bytes : nil
    }

    func keep(_ bytes: Data, for key: String) {
        last = (key, bytes)
    }

    /// The picture decoded off the main thread, no larger than CoverZoom.decodeSize along its longer side, turned the
    /// way its file says.
    nonisolated static func decode(_ bytes: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: CoverZoom.decodeSize(longest: max(width, height))]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
