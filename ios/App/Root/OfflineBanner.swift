import DeadwaxCore
import SwiftUI

/// The offline banner (notes/ios-specs/phase2-downloads.md 7.2): a slim amber strip at the top of each page, just under
/// its navigation bar (and the Library's Find field), pinned there as the page scrolls, for as long as deadwax can't
/// be reached - "Offline - showing what's on this phone" with no network at all, "Can't reach deadwax - showing what's
/// on this phone" when the network is there and deadwax doesn't answer.
///
/// It says how things are and stays, so it lives at the top: the bottom is the notice's and the mini player's, which
/// say what just happened - apart, they never stack or cover the last row. A tap opens it to its second line (and,
/// for deadwax not answering, Try again - "Trying…" while the 3 s probe is out) and closes it again. It slides down in
/// and up out (opacity alone with Reduce Motion); VoiceOver hears it come and hears "Back online" as it goes, from
/// Reachability, once - every page draws its own banner.
///
/// (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") No material: a DWPalette ground,
/// solid, so a list scrolling up under the strip never shows through it - the phone's page black, flat, its words amber
/// over the amber's hairline at its foot (`.chip.amber`'s edge); the Mac's window ground with the amber chip's tint over
/// it (`.chip.amber`'s fill - the Mac keeps its faces) and the same hairline. One line, two at the larger text sizes,
/// capped at accessibility2: a pinned strip must leave the page room. It is a safe-area inset at the page's top, never
/// laid over the page, so it covers no control; Try again's finger's target (44, round its 36) stays inside the strip's
/// own room under it (BannerLook.foot).
struct OfflineBanner: View {
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opened to its second line.
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            if let banner = DownloadWords.banner(reachability.reach, device: Platform.device) {
                strip(banner)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .default, value: reachability.reach)
        .onChange(of: reachability.reach) { _, reach in
            if reach == .online { open = false }
        }
    }

    private func strip(_ banner: (line: String, symbol: String, more: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: banner.symbol)
                        .accessibilityHidden(true)
                    Text(banner.line)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(Typeface.symbol(.caption2).weight(.bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(SheetLook.small.weight(.semibold))
                .foregroundStyle(DWPalette.amberText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(banner.line)
            .accessibilityValue(open ? DownloadWords.showingMore : DownloadWords.showsMore)

            if open {
                Text(banner.more)
                    .font(SheetLook.small)
                    .foregroundStyle(DWPalette.amberText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                if reachability.reach == .unreachable {
                    // (R18) the look's button - flat accent words on the phone, the Mac's `.btn` - not the system's
                    Button(reachability.probing ? DownloadWords.trying : DownloadWords.tryAgain) {
                        reachability.tryNow()
                    }
                    .buttonStyle(DWButtonStyle())
                    .disabled(reachability.probing)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, BannerLook.side)
        .padding(.vertical, BannerLook.foot)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BannerGround() }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// (R18) The offline banner's and Edit album's out-of-reach line's measures: 16 in from the sides (the page's), and 6
/// above and below their words - room enough under Try again for a finger's 44 round its 36 (DWTarget's reach, 4).
enum BannerLook {
    static let side: CGFloat = 16
    static let foot: CGFloat = 6
}

/// (R18) What the offline banner and Edit album's out-of-reach line are drawn on: a solid DWPalette ground (the phone's
/// page black; the Mac's window ground under the amber chip's tint) and the amber's hairline at their foot - no material.
struct BannerGround: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if Platform.mac {
                Rectangle().fill(DWPalette.bg)
                    .overlay(Rectangle().fill(DWPalette.amberFill))
            } else {
                Rectangle().fill(DWPalette.page)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DWPalette.amberEdge)
                .frame(height: 1 / max(scale, 1))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// The offline banner pinned at the top of this page, under its navigation bar - on the page's own content, never on
    /// the NavigationStack (an inset there doesn't reach the pages inside it: the mini player's lesson, FB23732628).
    /// For every page a tab's stack shows, beside `clearsPlayer()`: its root (TabStack) and each pushed one (appRoutes) -
    /// but the Library's root, whose own top (the switch, the squared look) has the banner under it, not over it: there
    /// TabStack passes `false`, and LibraryView draws it.
    func showsOfflineBanner(_ shown: Bool = true) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if shown { OfflineBanner() }
        }
    }
}
