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
/// The amber is laid over the bar's own material, so a list scrolling up under the strip never shows through it (a 14%
/// fill alone would), with the badge's amber hairline at its foot. One line, two at the larger text sizes, capped at
/// accessibility2: a pinned strip must leave the page room.
struct OfflineBanner: View {
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale
    /// Opened to its second line.
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            if let banner = DownloadWords.banner(reachability.reach) {
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
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.amber)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(banner.line)
            .accessibilityValue(open ? DownloadWords.showingMore : DownloadWords.showsMore)

            if open {
                Text(banner.more)
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                if reachability.reach == .unreachable {
                    Button(reachability.probing ? DownloadWords.trying : DownloadWords.tryAgain) {
                        reachability.tryNow()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.amber)
                    .buttonStyle(.borderless)
                    .disabled(reachability.probing)
                    .opacity(reachability.probing ? Palette.off : 1)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // the bar's own material under the amber's tint, as the New mark lays its tint over a solid
            Rectangle().fill(.bar)
                .overlay(Rectangle().fill(Palette.amberFill))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.amberEdge)
                .frame(height: 1 / max(scale, 1))
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension View {
    /// The offline banner pinned at the top of this page, under its navigation bar - on the page's own content, never on
    /// the NavigationStack (an inset there doesn't reach the pages inside it: the mini player's lesson, FB23732628).
    /// For every page a tab's stack shows, beside `clearsPlayer()`: its root (TabStack) and each pushed one (appRoutes).
    func showsOfflineBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { OfflineBanner() }
    }
}
