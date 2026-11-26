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
    /// (R9) The sign-in's one screen was up when the launch went to `.checking`: its own Check, so it stays up.
    @State private var signInUp = false
    /// (R9's review) Why it was up - a 401's words - kept through its own Check, so the line stays where it was.
    @State private var keptReason: String?
    @State private var keptWhy: String?

    var body: some View {
        ZStack {
            gate
            if server.launch == .ready, let over = server.signInOver {
                signIn(reason: over.reason, why: over.why)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: server.signInOver)
        // (the Mac app, slice 3) the window this is drawn in is the app's own: the one scene Platform shapes
        .shapesWindow()
        // (the Mac redesign, R1's review) and named for the launch screen up in place of the app - Sign in after a
        // sign-out - as the desktop frame names it for its page. Nothing on the iPhone
        .namesWindow(gateName)
        .task { await server.start() }
        // (R9) the one screen up, and kept up through its own Check; the app, or the can't-reach screen, puts it away
        .onChange(of: server.launch, initial: true) { (_: ServerModel.Launch, launch: ServerModel.Launch) -> Void in
            switch launch {
            case .signedOut(let reason, let why):
                signInUp = true
                keptReason = reason
                keptWhy = why
            case .needsAddress:
                signInUp = true
                keptReason = nil
                keptWhy = nil
            case .checking: break
            case .unreachable, .ready:
                signInUp = false
                keptReason = nil
                keptWhy = nil
            }
        }
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
        // (the Mac app, slice 6) File > Import EQ File… (⌘O)'s Open panel, and a file dropped on the window: each the way
        // a shared file comes - read as one is, its preview over whatever is up. Nothing on the iPhone
        .eqOpenPanel(Binding<Bool>(get: { navigation.eqFileChoosing }, set: { (up: Bool) -> Void in
            navigation.eqFileChoosing = up
        })) { (url: URL) -> Void in shared(url) }
        .eqFileDrop { (item: EQImportItem) -> Void in navigation.share(item) }
    }

    /// A file shared to deadwax (eq.md 3.9: "deadwax" in the share sheet for a .txt) - read off the main thread, then
    /// shown in the EQ's import preview over whatever is on top, For set to the output now. (The Mac app, slice 6) And
    /// on the Mac: Finder's Open With, a file dropped on the Dock's icon (both `.onOpenURL`, as a share), and the file
    /// chosen in File > Import EQ File…'s Open panel.
    private func shared(_ url: URL) {
        guard url.isFileURL else { return }
        let navigation = self.navigation
        Task.detached(priority: .userInitiated) { () async -> Void in
            let item = EQImportReading.file(url, forKey: nil)
            await MainActor.run { navigation.share(item) }
        }
    }

    /// (The Mac redesign) The window's name while a launch screen stands in place of the app: Sign in, or deadwax for
    /// the others (the address, can't reach, checking); none with the app up - the desktop frame names it for its page,
    /// a sign-in over the app included.
    private var gateName: String? {
        switch server.launch {
        case .ready: return nil
        case .signedOut: return SignInWords.signIn
        case .needsAddress, .checking, .unreachable: return SignInWords.title
        }
    }

    /// (The redesign, slice R9) The sign-in's one screen is up: no address yet (or Change address pressed), a sign-in
    /// asked for - and through the screen's own Check, the launch's `.checking` while it asks (`signInUp`), so what is
    /// typed stays. The launch's own checking (a saved address) is the spinner, as before.
    private var showsSignIn: Bool {
        switch server.launch {
        case .needsAddress, .signedOut: return true
        case .checking: return signInUp
        case .unreachable, .ready: return false
        }
    }

    /// Why the sign-in shows: a 401's words (`.signedOut`) - (R9's review) kept through the screen's own Check, so the
    /// line doesn't go while it asks and come back - none while the address is still to check.
    private var signInReason: (reason: String?, why: String?) {
        switch server.launch {
        case .signedOut(let reason, let why): return (reason, why)
        case .checking: return signInUp ? (keptReason, keptWhy) : (nil, nil)
        case .needsAddress, .unreachable, .ready: return (nil, nil)
        }
    }

    @ViewBuilder private var gate: some View {
        if showsSignIn {
            signIn(reason: signInReason.reason, why: signInReason.why)
        } else {
            switch server.launch {
            case .needsAddress, .signedOut:
                // drawn above, as the one screen (showsSignIn)
                EmptyView()
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel(AlbumPageLines.loading)
            case .unreachable(let failure):
                UnreachableView(failure: failure)
            case .ready:
                app
                    .accessibilityHidden(server.signInOver != nil)
                    .allowsHitTesting(server.signInOver == nil)
            }
        }
    }

    /// (R9) The sign-in, where deadwax is and who you are, today's calls in today's order (Check, then Sign in): on the
    /// iPhone one screen (SignInView, iSignIn), on the Mac one dialog (MacSignIn, SignIn.dc.html) - the same calls.
    @ViewBuilder private func signIn(reason: String?, why: String?) -> some View {
        if Platform.mac {
            MacSignIn(reason: reason, reasonWhy: why)
        } else {
            SignInView(reason: reason, reasonWhy: why)
        }
    }

    /// The app: the tabs on the iPhone; (the Mac app, slice 3) on the Mac always the desktop frame - the sidebar, the
    /// page, the side panels and the player bar (MacFrame.drawsDesktop, the Mac app's plan decision 3).
    @ViewBuilder private var app: some View {
        if MacFrame.drawsDesktop(Platform.device) {
            DesktopFrame()
        } else {
            MainTabs()
        }
    }
}
