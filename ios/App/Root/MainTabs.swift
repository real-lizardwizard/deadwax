import DeadwaxCore
import SwiftUI

/// The app's two tabs (D1), Library and You, each its own NavigationStack. Tapping the tab shown again pops it to its
/// root (and, at its root, scrolls its list to the top - AppNavigation.select). With something queued the mini
/// player sits above the tab bar, and a notice (D11) above it; Now Playing opens over everything.
struct MainTabs: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: Binding(get: { navigation.tab }, set: { navigation.select($0) })) {
            TabStack(path: $navigation.library) { LibraryView() }
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(AppTab.library)

            TabStack(path: $navigation.you) { YouView() }
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(AppTab.you)
        }
        .fullScreenCover(isPresented: $navigation.nowPlayingShown) {
            NowPlayingView()
        }
        // a file shared to deadwax over the tabs (eq.md 3.9): the EQ as a sheet, the import's preview over it - over
        // Now Playing, Now Playing opens its own
        .sheet(isPresented: $navigation.eqImportSheet) {
            EQSheet()
        }
        .onChange(of: player.hasQueue) { _, queued in
            if !queued { navigation.nowPlayingShown = false }
        }
    }
}

/// A tab's NavigationStack with the player drawn over its bottom edge, above the tab bar - and every page in it, its
/// root and each one pushed (appRoutes), given room at its foot for the player's height (`clearsPlayer()`), so a
/// list scrolled to its end has its last row above the mini player.
///
/// The room is given to the pages, not the stack: a `safeAreaInset` on the NavigationStack itself (as this was until
/// fix/player-inset) draws the player in the right place but never reaches the lists inside - on James's iOS 27.2 a
/// list's last row stayed under the mini player, You's Debug among them (FB23732628, notes/ios.md "The mini player
/// over the last row"). The player is an overlay here, so it adds to no safe area, and the only room a page gets is
/// its own: never twice on an iOS where the stack's inset did reach.
private struct TabStack<Root: View>: View {
    @Binding var path: [AppRoute]
    @ViewBuilder var root: Root

    @Environment(PlayerModel.self) private var player
    /// The player's height as last drawn (the notice, the mini player and their padding), at the text size in use.
    @State private var playerHeight: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            root
                .clearsPlayer()
                .showsOfflineBanner()
                .appRoutes()
        }
        .environment(\.playerClearance, PlayerInset.shown(player) ? playerHeight : 0)
        .overlay(alignment: .bottom) {
            PlayerInset { playerHeight = $0 }
        }
    }
}

/// What sits above the tab bar: the notice (for its 5 s) over the mini player (with something queued). It says its
/// height as drawn, for the pages' room under it.
private struct PlayerInset: View {
    @Environment(PlayerModel.self) private var player

    let measured: (CGFloat) -> Void

    /// Anything to draw: something queued, or a notice.
    static func shown(_ player: PlayerModel) -> Bool { player.hasQueue || player.notice != nil }

    var body: some View {
        if Self.shown(player) {
            VStack(spacing: 8) {
                if let notice = player.notice {
                    Notice(text: notice)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if player.hasQueue {
                    MiniPlayerView()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in measured(height) }
            .animation(.default, value: player.notice)
        }
    }
}

extension EnvironmentValues {
    /// The room a tab's pages leave at their foot for the player over them (TabStack): its height while it's drawn,
    /// else 0.
    @Entry var playerClearance: CGFloat = 0
}

extension View {
    /// A tab's page given room at its foot for the player drawn over it: what a `safeAreaInset` of the player's height
    /// on the page itself gives - a list's or a scroll view's content ends above it, and an overlay on it (the
    /// Library's letter index) stays clear - with nothing there to see or tap. For every page a tab's stack shows: its
    /// root (TabStack) and each pushed one (appRoutes).
    func clearsPlayer() -> some View {
        modifier(PlayerClearance())
    }
}

private struct PlayerClearance: ViewModifier {
    @Environment(\.playerClearance) private var clearance

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: clearance)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
