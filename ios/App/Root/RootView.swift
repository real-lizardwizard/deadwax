import DeadwaxCore
import SwiftUI

/// The app's root: the launch's gates in screens.md 1's order - the Server address (no address yet), can't-reach
/// (/me failed with no 401, D10), the sign-in (a 401), then the app (MainTabs). A session ended mid-use brings the
/// sign-in OVER the app: the tabs stay under it, and the music plays on.
struct RootView: View {
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(AppNavigation.self) private var navigation
    @Environment(CareRunModel.self) private var care
    @Environment(ServerSettingsModel.self) private var serverSettings
    @Environment(EventLogModel.self) private var eventLog
    @Environment(PeopleModel.self) private var people
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
            // (Phase 8, slice 7) a Library care run stops after the album out as the app goes, its screen let sleep - and
            // (slice 8) a Re-time run the same
            care.scene(phase)
            serverSettings.scene(phase)
            // (slice 9) the event log's stream called off as the app goes, rejoined from the last line on return
            eventLog.scene(phase)
            // (slice 11) People read again as the app comes back with it up - the unlock may have run out meanwhile
            people.scene(phase)
            switch phase {
            case .active:
                CoverCache.shared.forgetFailures()
                server.becameActive()
                player.becameActive()
                eq.becameActive()
            case .background:
                player.movedToBackground()
                eq.movedToBackground()
            default:
                break
            }
        }
        .onChange(of: server.signInOver) { _, over in
            // the sign-in comes over everything: Now Playing closes under it (the web's leaveFullScreen)
            if over != nil { navigation.nowPlayingShown = false }
            // (Phase 8, slice 8) gone: a Server settings page showing asks again what failed under it - told once
            // here, as the root, a group page and Set up Navidrome's sheet may all be up at once
            if over == nil { serverSettings.sessionBack() }
            // (slice 9) come: the event log's stream called off (it would only be refused); gone: asked again
            eventLog.recheck()
            // (slice 11) come: People's passwords emptied and its sheet put away (it would stand over the sign-in);
            // gone: People read again
            people.signInChanged()
        }
        .onChange(of: server.client?.session) { _, _ in
            // (slice 10's review) the session moved - Change password's re-key: the event log's stream asked again under
            // the new one, a halt for the old one's 401 let go
            eventLog.sessionMoved()
            // (slice 11) People's unlock was the old session's: read again under the new one
            people.sessionMoved()
        }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            // (slice 11) Now Playing over People (a full-screen cover, its pages left shown under it): every password
            // typed there emptied; gone again, People read again
            people.nowPlaying(shown)
        }
        .onOpenURL { (url: URL) -> Void in shared(url) }
    }

    /// A file shared to deadwax (eq.md 3.9: "deadwax" in the share sheet for a .txt) - read off the main thread, then
    /// shown in the EQ's import preview over whatever is on top, For set to the output now.
    private func shared(_ url: URL) {
        guard url.isFileURL else { return }
        let navigation = self.navigation
        Task.detached(priority: .userInitiated) { () async -> Void in
            let item = EQImportReading.file(url, forKey: nil)
            await MainActor.run { navigation.share(item) }
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
