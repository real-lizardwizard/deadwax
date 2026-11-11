import DeadwaxCore
import SwiftUI

/// The app's root: the launch's gates in screens.md 1's order - the Server address (no address yet), can't-reach
/// (/me failed with no 401, D10), the sign-in (a 401), then the app (MainTabs). A session ended mid-use brings the
/// sign-in OVER the app: the tabs stay under it, and the music plays on.
struct RootView: View {
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            gate
            if server.launch == .ready, let over = server.signInOver {
                SignInView(reason: over.reason, reasonWhy: over.why)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: server.signInOver)
        .task { await server.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                server.becameActive()
                player.becameActive()
            case .background:
                player.movedToBackground()
            default:
                break
            }
        }
        .onChange(of: server.signInOver) { _, over in
            // the sign-in comes over everything: Now Playing closes under it (the web's leaveFullScreen)
            if over != nil { navigation.nowPlayingShown = false }
        }
    }

    @ViewBuilder private var gate: some View {
        switch server.launch {
        case .needsAddress:
            NavigationStack { ServerAddressView() }
        case .checking:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(AlbumPageLines.loading)
        case .unreachable(let failure):
            UnreachableView(failure: failure)
        case .signedOut(let reason, let why):
            SignInView(reason: reason, reasonWhy: why)
        case .ready:
            MainTabs()
                .accessibilityHidden(server.signInOver != nil)
                .allowsHitTesting(server.signInOver == nil)
        }
    }
}
