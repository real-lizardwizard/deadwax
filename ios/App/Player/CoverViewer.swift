import DeadwaxCore
import ImageIO
import SwiftUI
import UIKit

extension View {
    /// Now Playing's cover, opening the cover viewer at a tap (notes/ios.md "The cover, full screen") - the tap and
    /// VoiceOver's button, nothing more: the cover is put into `viewing`, Now Playing's own, which it presents from its
    /// root (`coverViewer`), so the viewer outlives this cover - Lyrics taking its place as the next song comes, or as
    /// deadwax comes back - until it is closed. Only a tap: the cover's room holds Now Playing's grip as a high-priority
    /// drag, so a drag is the grip's from its first dragStartDistance and the tap fires at lift only when none began.
    /// Only a cover shown opens - drawn by Now Playing, or kept - never the grey square of one loading or that failed
    /// (CoverZoom.opens). For VoiceOver the cover is a button, "Cover of Dummy - show full screen".
    func opensCoverFullScreen(_ track: QueueTrack, into viewing: Binding<ViewedCover?>) -> some View {
        modifier(CoverOpens(track: track, viewing: viewing))
    }

    /// The cover viewer, over Now Playing while `viewing` holds a cover - put on Now Playing's root, beside its sheets,
    /// never on the cover; `onDismiss` once it is gone (the EQ sheet a shared file waited for).
    func coverViewer(_ viewing: Binding<ViewedCover?>, onDismiss: @escaping () -> Void) -> some View {
        appCover(item: viewing, onDismiss: onDismiss) { (cover: ViewedCover) in
            CoverViewer(cover: cover) { CoverViewing.put(nil, into: viewing) }
                .macSheet()
        }
    }
}

/// The cover viewer's one opening: the cover shown, from the song it was tapped on. Held at Now Playing's root, so
/// neither a song change nor Lyrics taking the cover's place changes it or closes it.
struct ViewedCover: Identifiable, Equatable {
    let id = UUID()
    let coverID: String
    let album: String
    let artist: String
}

/// The viewer put up or taken down with no slide: it fades itself in and out.
enum CoverViewing {
    @MainActor static func put(_ cover: ViewedCover?, into viewing: Binding<ViewedCover?>) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { viewing.wrappedValue = cover }
    }
}

private struct CoverOpens: ViewModifier {
    let track: QueueTrack
    @Binding var viewing: ViewedCover?
    @Environment(ServerModel.self) private var server

    func body(content: Content) -> some View {
        content
            .contentShape(Corners.artShape)
            .onTapGesture { open(saying: false) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CoverViewerWords.open(album: track.album))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(saying: true) }
            .accessibilityHidden(track.coverArt?.isEmpty ?? true)
    }

    /// The viewer, on this cover - if a picture of it is shown (CoverZoom.opens); VoiceOver hears why not.
    private func open(saying: Bool) {
        guard viewing == nil else { return }
        let id = track.coverArt ?? ""
        let drawn = server.client.map { CoverViewer.drawn(client: $0, coverID: id) != nil } ?? false
        let kept = !id.isEmpty && KeptCovers.shared.url(for: id) != nil
        guard CoverZoom.opens(coverID: id, drawn: drawn, kept: kept) else {
            if saying { UIAccessibility.post(notification: .announcement, argument: CoverViewerWords.notYet) }
            return
        }
        CoverViewing.put(ViewedCover(coverID: id, album: track.album, artist: track.artist), into: $viewing)
    }
}

/// The cover, full screen: fitted on the page's black, the status bar hidden; pinch or double-tap to zoom, a drag to
/// pan while zoomed, and closed by a drag down at rest, the close button, or VoiceOver's escape (CoverZoomer has the
/// gestures). It shows the cover Now Playing has drawn at once - the largest the cover cache holds, else the one kept
/// with a downloaded album - and the full size, asked of deadwax with no size, over it as it lands. A full size past
/// CoverZoom.fullMostBytes (30 MB) is called off as it arrives, and the cover drawn stays.
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
                placeholder
                    .opacity(shown ? 1 : 0)
                    .offset(y: dragged)
                    .allowsHitTesting(false)
            }
            CoverCloseButton(action: close)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

    /// While nothing is drawn: the spinner, then the empty square if nothing came. Under the cover's fade and following
    /// a drag down, it takes no touch - every one goes to the zoom beneath, so a drag down on it still closes - and the
    /// square is no element of its own: the zoom beneath is the cover, named for it, already.
    @ViewBuilder private var placeholder: some View {
        if asked {
            Corners.artShape
                .fill(Palette.coverEmpty)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 8)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(LibraryWords.loading)
        }
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
        return Self.drawn(client: client, coverID: cover.coverID)
    }

    /// The largest size of a cover the cover cache holds - Now Playing's 1024 first - or nil, drawn nowhere.
    @MainActor static func drawn(client: DeadwaxClient, coverID: String) -> UIImage? {
        for size in CoverSize.steps.reversed() {
            if let image = CoverCache.shared.cached(client: client, id: coverID, size: size) { return image }
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

/// The viewer's ✕, a 44-point target. Its square grows with the text size as the glyph does (`side`, scaled from 36
/// points), and the viewer holds both at the first accessibility size, so the glyph never outgrows its square nor the
/// square the corner. (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") On the phone
/// a bare white glyph, no face (it was a grey card's square), faded while held; on the Mac a round key (CoverCloseKey).
private struct CoverCloseButton: View {
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typeface.symbol(.body).weight(.semibold))
                .foregroundStyle(DWPalette.text)
                .frame(width: side, height: side)
        }
        .buttonStyle(CoverCloseKey())
        .accessibilityLabel(CoverViewerWords.close)
        // (the Mac app, slice 2) Escape closes the viewer; nothing on the iPhone
        .escapeCloses()
    }
}

/// (R18) The ✕'s face: on the Mac a round key - a circle raised in the look's button colours (`.btn`'s face, sheen,
/// edge and drop: the player's own key colours are App/Mac's, which this shared file can't name), pressed in while held,
/// the pointer taking the circle as a Mac's control takes its face; on the phone none - the glyph alone, faded while held
/// as a flat button is (DWPalette.off), in a finger's 44 round it.
private struct CoverCloseKey: ButtonStyle {
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if Platform.mac {
            configuration.label
                .background {
                    DWRaised(shape: Circle(), face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen,
                             edge: DWPalette.buttonEdge, drop: DWPalette.buttonDrop, pressed: configuration.isPressed)
                }
                .contentShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
        } else {
            configuration.label
                .opacity(configuration.isPressed ? DWPalette.off : 1)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// The full-size cover last opened, kept as the bytes deadwax sent (not the decoded picture's tens of MB), so opening
/// the same cover again doesn't ask for it again - only up to CoverZoom.keptMostBytes (10 MB): a larger file is let go
/// as the viewer closes and asked again next time. One at a time, by server, session and cover; let go when iOS says
/// memory is short.
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

    /// Kept for opening it again - a file past 10 MB not, and the one kept before it let go too.
    func keep(_ bytes: Data, for key: String) {
        last = CoverZoom.keeps(bytes: bytes.count) ? (key, bytes) : nil
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
