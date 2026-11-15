import DeadwaxCore
import SwiftUI
import UIKit

/// The app's tabs (D1), Library, Search (Phase 5), Requests (Phase 6) and You, each its own NavigationStack. Tapping the
/// tab shown again pops it to its root (and, at its root, scrolls its list to the top - AppNavigation.select). With
/// something queued the mini player sits above the tab bar, and a notice (D11) above it; Now Playing opens over
/// everything.
///
/// The tab bar is the app's own since the squared look (14 Nov, James: "maybe square off the slider and the bar at the
/// bottom and the now playing bar as well"): iOS's can't be reshaped - on iOS 26 and later it floats, a capsule of
/// glass - so it is hidden on every tab's stack, and AppTabBar is drawn over the TabView's foot instead: squared, full
/// width, flush to the screen's bottom edge, a hairline along its top, as the web's .app-tabbar. The TabView stays, for
/// each tab's own state; a tap goes through AppNavigation.select, as iOS's bar's did. The bar stays down when the
/// keyboard comes up (it is under it, as iOS's was), and nothing makes room for it then; the mini player rides the
/// keyboard as before.
///
/// Requests' badge is the count of downloads on their way (RequestsView.arriving), drawn on its button in AppTabBar -
/// none at 0 and none while deadwax can't be reached; what the app is looking at, as far as downloads go
/// (RequestsWatch.watching - the scene, the tab, its pages, Now Playing over it, the sign-in over the app), is handed to
/// RequestsModel, whose poll it paces.
struct MainTabs: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(\.scenePhase) private var scenePhase
    /// The tab bar's height as drawn, above the bottom safe area (the home indicator's), at the text size in use.
    @State private var barHeight: CGFloat = 0
    /// The keyboard is up, over the bar: the pages and the player make no room for the bar meanwhile.
    @State private var keyboardUp = false

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: Binding(get: { navigation.tab }, set: { (tab: AppTab) -> Void in navigation.select(tab) })) {
            ForEach(AppTab.allCases, id: \.self) { (tab: AppTab) in
                stack(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .environment(\.tabBarRoom, keyboardUp ? 0 : barHeight)
        .overlay(alignment: .bottom) {
            AppTabBar()
                .onGeometryChange(for: CGFloat.self) { (bar: GeometryProxy) -> CGFloat in
                    bar.size.height
                } action: { (height: CGFloat) -> Void in
                    barHeight = height
                }
                // under the keyboard, as iOS's bar was - never riding up on it
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
            (_: Notification) -> Void in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
            (_: Notification) -> Void in
            keyboardUp = false
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
        // the tabs gone (the sign-in or the launch screen instead, or iOS taking them from under Now Playing's
        // full-screen cover) watch nothing; back, they watch what shows - even when that's what they watched before
        // they went, which onChange alone never says (slice 1's review, finding 1)
        .onAppear { requests.watch(watching) }
        .onDisappear { requests.watch(.hidden) }
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

    /// A tab's stack, its root the tab's own page. (Phase 5) Search between Library and You, the web's order
    /// (phase5-search.md question 1); (Phase 6) Requests between Search and You, the web's order less Home
    /// (phase6-get-requests.md question 1). The Library draws its own top - the switch - with the offline banner under
    /// it.
    @ViewBuilder private func stack(_ tab: AppTab) -> some View {
        let paths = Bindable(navigation)
        switch tab {
        case .library:
            TabStack(path: paths.library, ownTop: true) { LibraryView() }
        case .search:
            TabStack(path: paths.search) { SearchScreen() }
        case .requests:
            TabStack(path: paths.requests) { RequestsScreen() }
        case .you:
            TabStack(path: paths.you) { YouView() }
        }
    }
}

/// The app's tab bar (the squared look; the web's .app-tabbar, app.css): the tabs side by side, each its symbol over its
/// words - the one shown in the accent, the others --dw-tab-inactive - on --dw-tab-bar, full width, flush to the bottom
/// edge (its fill runs under the home indicator), a hairline of --dw-border along its top. A tap is AppNavigation's
/// select: another tab shown, or the tab shown back at its root and then its top.
///
/// VoiceOver reads it as a tab bar, each tab a button with its words, the one shown selected. Its words grow with the
/// text size up to the largest of the standard sizes, as far as a bar can and leave the page its room; at the
/// accessibility sizes they hold there, and a long press shows the tab's symbol and words large (the Large Content
/// Viewer), as iOS's own tab bar does.
///
/// (Phase 6) Requests' button carries its badge, the count of downloads on their way (RequestsModel.badgeCount, 0
/// while deadwax can't be reached), and is read with it: "Requests, 2 arriving" (RequestWords.badgeLabel).
struct AppTabBar: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(\.displayScale) private var displayScale

    /// --dw-tab-pad: above the tabs.
    private static let pad: CGFloat = 4
    /// --app-tab-side: either side of them.
    private static let side: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { (tab: AppTab) in
                AppTabButton(tab: tab, shown: navigation.tab == tab, badge: badge(tab), spoken: spoken(tab)) {
                    navigation.select(tab)
                }
            }
        }
        .padding(.top, Self.pad)
        .padding(.horizontal, Self.side)
        .frame(maxWidth: .infinity)
        .background {
            Palette.tabBar
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Palette.border
                .frame(height: 1 / max(displayScale, 1))
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// The count over a tab's symbol: Requests' "2", "99+" - none at 0, and none on the other tabs.
    private func badge(_ tab: AppTab) -> String {
        tab == .requests ? RequestWords.badgeText(requests.badgeCount) : ""
    }

    /// What VoiceOver reads for a tab: its words, Requests' with its count ("Requests, 2 arriving").
    private func spoken(_ tab: AppTab) -> String {
        tab == .requests ? RequestWords.badgeLabel(tab.title, requests.badgeCount) : tab.title
    }
}

/// One tab of the bar: its symbol over its words, a button the bar's height - and Requests' count over its symbol's top
/// right corner, as the web's .app-tab-badge.
private struct AppTabButton: View {
    let tab: AppTab
    let shown: Bool
    /// The count over the symbol ("2", "99+"), none when empty.
    let badge: String
    /// What VoiceOver reads: the tab's words, with Requests' count.
    let spoken: String
    let action: () -> Void

    /// --dw-tab-item: a tab's height.
    private static let height: CGFloat = 49
    /// --app-tab-gap: between the symbol and the words.
    private static let gap: CGFloat = 3

    /// The symbol's box (--app-tab-icon, 24), one height for every tab's whatever its symbol, growing with the words.
    @ScaledMetric(relativeTo: .title2) private var symbolBox: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: Self.gap) {
                Image(systemName: tab.symbol)
                    .symbolVariant(.fill)
                    .font(.title2)
                    .frame(height: symbolBox)
                    .overlay(alignment: .top) {
                        if !badge.isEmpty { TabBadge(count: badge) }
                    }
                Text(tab.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(shown ? Palette.accent : Palette.tabInactive)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(spoken, systemImage: tab.symbol)
        }
    }
}

/// Requests' count over its symbol's top right corner (app.css .app-tab-badge): STYLE.md's purple badge laid over the
/// bar's own colour, so it is opaque and no stroke of the symbol shows through it - --dw-badge-purple-bg over
/// --dw-tab-bar, a --dw-hairline (1) of --dw-badge-purple-border, --dw-accent-text words in the tab's size, bold
/// (--dw-weight-bold), a control's corners. Its left edge 2 right of the symbol's centre and its top 5 above the
/// symbol's box: the web's 14 and -5 on its 24 icon. It grows with the words; VoiceOver reads it in the button's label,
/// not on its own.
private struct TabBadge: View {
    let count: String

    /// --app-tab-badge: its height, and its narrowest.
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 16
    /// --app-tab-badge-pad: either side of the count.
    private static let pad: CGFloat = 4
    /// --app-tab-badge-left 14 on --app-tab-icon 24: its left edge this far right of the symbol's centre.
    private static let right: CGFloat = 2
    /// --app-tab-badge-top -5: its top this far above the symbol's.
    private static let up: CGFloat = 5

    var body: some View {
        Text(count)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, Self.pad)
            .frame(minWidth: size, minHeight: size)
            .background(Palette.badgeFill, in: Corners.controlShape)
            .background(Palette.tabBar, in: Corners.controlShape)
            .overlay(Corners.controlShape.strokeBorder(Palette.badgeEdge, lineWidth: 1))
            .alignmentGuide(HorizontalAlignment.center) { (box: ViewDimensions) -> CGFloat in box[.leading] - Self.right }
            .alignmentGuide(VerticalAlignment.top) { (box: ViewDimensions) -> CGFloat in box[.top] + Self.up }
            .accessibilityHidden(true)
    }
}

/// A tab's NavigationStack with the player drawn over its bottom edge, above the tab bar - and every page in it, its
/// root and each one pushed (appRoutes), given room at its foot for the player's height and the bar's
/// (`clearsPlayer()`), so a list scrolled to its end has its last row above the mini player and the bar.
///
/// The room is given to the pages, not the stack: a `safeAreaInset` on the NavigationStack itself (as this was until
/// fix/player-inset) draws the player in the right place but never reaches the lists inside - on James's iOS 27.2 a
/// list's last row stayed under the mini player, You's Debug among them (FB23732628, notes/ios.md "The mini player
/// over the last row"). The player is an overlay here, so it adds to no safe area, and the only room a page gets is
/// its own: never twice on an iOS where the stack's inset did reach. Since the squared look iOS's tab bar is hidden
/// on the stack and on each page (the app draws its own, MainTabs), so the stack's safe area at its foot is the home
/// indicator's (or the keyboard's): the player sits `tabBarRoom` above it, and the pages' room counts the bar too.
private struct TabStack<Root: View>: View {
    @Binding var path: [AppRoute]
    /// The root draws its own top, with the offline banner under it (the Library's switch): not drawn here.
    var ownTop = false
    @ViewBuilder var root: Root

    @Environment(PlayerModel.self) private var player
    /// The tab bar's height while it shows (0 while the keyboard is over it).
    @Environment(\.tabBarRoom) private var tabBarRoom
    /// The player's height as last drawn (the notice, the mini player and their padding), at the text size in use.
    @State private var playerHeight: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            root
                .clearsPlayer()
                .showsOfflineBanner(!ownTop)
                .toolbar(.hidden, for: .tabBar)
                .appRoutes()
        }
        .toolbar(.hidden, for: .tabBar)
        .environment(\.playerClearance, (PlayerInset.shown(player) ? playerHeight : 0) + tabBarRoom)
        .overlay(alignment: .bottom) {
            PlayerInset { playerHeight = $0 }
                .padding(.bottom, tabBarRoom)
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
    /// The room a tab's pages leave at their foot for the player and the tab bar over them (TabStack): the player's
    /// height while it's drawn, and the bar's while the keyboard isn't over it.
    @Entry var playerClearance: CGFloat = 0
    /// The app's tab bar's height above the home indicator (MainTabs) - 0 while the keyboard is up, over it.
    @Entry var tabBarRoom: CGFloat = 0
}

extension View {
    /// A tab's page given room at its foot for the player and the tab bar drawn over it: what a `safeAreaInset` of
    /// their height on the page itself gives - a list's or a scroll view's content ends above them, and an overlay on it
    /// (the Library's letter index) stays clear - with nothing there to see or tap. For every page a tab's stack shows:
    /// its root (TabStack) and each pushed one (appRoutes).
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
