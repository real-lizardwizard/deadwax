import DeadwaxCore
import SwiftUI

/// The Library tab's root (D2): the Albums screen of the person's scope - "Your albums" with a library of your own
/// (and, above them, All music's one row, All albums), "Albums" with logins off and for the break-glass admin - or,
/// when a check finds deadwax has no Navidrome that answers, the Navidrome gate in its place (NavidromeGate).
///
/// As the tab comes into view - picked, the app back in front on it, a new person - its lists are asked again if
/// over a minute old and your library is asked for its New marks (App.tsx's libraryShown), whichever page of the
/// tab is on top: the root stays in the tab's stack under its pages, so it hears the tab and the scene change.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var shownOnce = false

    init() {}

    var body: some View {
        root
            .onAppear {
                guard !shownOnce else { return }
                shownOnce = true
                library.libraryShown()
            }
            .onChange(of: navigation.tab) { _, tab in
                if tab == .library { library.libraryShown() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, navigation.tab == .library { library.libraryShown() }
            }
            .onChange(of: server.person) { _, _ in
                library.libraryShown()
            }
            .onChange(of: server.signInOver == nil) { _, gone in
                // signed in again over the app, as the same person: what failed while signed out is asked again
                if gone { library.signedInAgain() }
            }
    }

    @ViewBuilder private var root: some View {
        switch NavidromeGate.shownOnPhone(library.navidrome, access: server.access) {
        case .open:
            AlbumsScreen(scope: library.scope, root: true)
                // another scope is another screen: its own Find and its own place in the list
                .id(library.scope)
        case .connecting:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(NavidromeGate.connecting)
        case .closed(let closed):
            NavidromeGateView(closed: closed)
        }
    }
}

/// The Navidrome gate drawn (app/NeedsNavidrome.tsx): why the Library has no albums to show, in the words Core's
/// NavidromeGate gives this reader, Try again (asks Navidrome again - also on a pull) and, for an admin, Set up
/// Navidrome - deadwax's own app opened in Safari, whose Server settings set it up (D8). Navidrome's own words, for
/// whoever runs deadwax, can be selected to copy.
struct NavidromeGateView: View {
    let closed: NavidromeGate.Closed

    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(closed.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(closed.lines, id: \.self) { line in
                    Text(line)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if closed.tryAgain {
                    Button {
                        Task { await library.checkNavidrome() }
                    } label: {
                        if library.checkingNavidrome {
                            ProgressView()
                        } else {
                            Text(NavidromeGate.tryAgain)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.checkingNavidrome)
                    .accessibilityLabel(NavidromeGate.tryAgain)
                }
                if closed.setUp, let address = server.address, let url = NavidromeGate.setUpURL(address) {
                    Button(NavidromeGate.setUp) { openURL(url) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Library")
        .refreshable { await library.checkNavidrome() }
    }
}
