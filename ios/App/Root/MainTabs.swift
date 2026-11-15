import DeadwaxCore
import SwiftUI

/// The app's tabs (D1), Library, Search (Phase 5), Requests (Phase 6) and You, each its own NavigationStack. Tapping the
/// tab shown again pops it to its root (and, at its root, scrolls its list to the top - AppNavigation.select). With
/// something queued the mini player sits above the tab bar, and a notice (D11) above it; Now Playing opens over
/// everything.
///
/// Requests' badge is the count of downloads on their way (RequestsView.arriving), none at 0 and none while deadwax
/// can't be reached; what the app is looking at, as far as downloads go (RequestsWatch.watching - the scene, the tab,
/// its pages, Now Playing over it, the sign-in over the app), is handed to RequestsModel, whose poll it paces.
struct MainTabs: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: Binding(get: { navigation.tab }, set: { navigation.select($0) })) {
            TabStack(path: $navigation.library) { LibraryView() }
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(AppTab.library)

            // (Phase 5) between Library and You, the web's order (phase5-search.md question 1)
            TabStack(path: $navigation.search) { SearchScreen() }
                .tabItem { Label(SearchWords.title, systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            // (Phase 6) between Search and You, the web's order less Home (phase6-get-requests.md question 1)
            TabStack(path: $navigation.requests) { RequestsScreen() }
                .tabItem {
                    Label(RequestWords.tab, systemImage: "square.and.arrow.down")
                        .accessibilityLabel(RequestWords.badgeLabel(RequestWords.tab, requests.badgeCount))
                }
                .badge(badge)
                .tag(AppTab.requests)

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
        // Add to a playlist from a page's ••• (Phase 4, slice 2) - Now Playing's opens over Now Playing
        .sheet(item: $navigation.playlistPick) { (request: PlaylistPickRequest) in
            PlaylistPicker(request: request)
        }
        .onChange(of: player.hasQueue) { _, queued in
            if !queued { navigation.nowPlayingShown = false }
        }
        .onChange(of: watching, initial: true) { _, now in requests.watch(now) }
        .onDisappear { requests.watch(.hidden) }
    }

    /// Requests' badge: "2", "99+" - none at 0 (the count is 0 while deadwax can't be reached).
    private var badge: Text? {
        let words = RequestWords.badgeText(requests.badgeCount)
        return words.isEmpty ? nil : Text(words)
    }

    /// What the app is looking at, as far as downloads go: nothing in the background or under the sign-in; a tab at
    /// its root with Now Playing not over it.
    private var watching: Watching {
        let tab: String
        switch navigation.tab {
        case .requests: tab = "requests"
        case .library: tab = "library"
        case .search: tab = "search"
        case .you: tab = "you"
        }
        return RequestsWatch.watching(shown: scenePhase != .background && server.signInOver == nil, tab: tab,
                                      depth: navigation.shownStack.count, sheetOpen: navigation.nowPlayingShown)
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
