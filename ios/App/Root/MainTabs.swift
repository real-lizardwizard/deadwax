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
            NavigationStack(path: $navigation.library) {
                LibraryView()
                    .appRoutes()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { PlayerInset() }
            .tabItem { Label("Library", systemImage: "square.stack") }
            .tag(AppTab.library)

            NavigationStack(path: $navigation.you) {
                YouView()
                    .appRoutes()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { PlayerInset() }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(AppTab.you)
        }
        .fullScreenCover(isPresented: $navigation.nowPlayingShown) {
            NowPlayingView()
        }
        .onChange(of: player.hasQueue) { _, queued in
            if !queued { navigation.nowPlayingShown = false }
        }
    }
}

/// What sits above the tab bar: the notice (for its 5 s) over the mini player (with something queued).
private struct PlayerInset: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if player.hasQueue || player.notice != nil {
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
            .animation(.default, value: player.notice)
        }
    }
}
