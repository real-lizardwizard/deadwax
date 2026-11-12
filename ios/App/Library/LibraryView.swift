import DeadwaxCore
import SwiftUI

/// The Library tab's root (D2): the Albums screen of the person's scope - "Your albums" with a library of your own
/// (and, above them, All music's one row, All albums), "Albums" with logins off and for the break-glass admin - or,
/// when a check finds deadwax has no Navidrome that answers, the Navidrome gate in its place (NavidromeGate).
///
/// While deadwax can't be reached (phase2-downloads.md 5.4) the root is Downloaded - what is on this phone - and the
/// gate isn't consulted; its check runs again when deadwax answers. The root never swaps under a finger: Core's
/// LibraryRoot changes it only while it isn't on screen (another tab, a page pushed over it, the app in the
/// background), and the app opening starts on the list it should - so the first look waits for the phone's path to be
/// known, a moment at launch.
///
/// As the tab comes into view - picked, the app back in front on it, a new person - its lists are asked again if
/// over a minute old and your library is asked for its New marks (App.tsx's libraryShown), whichever page of the
/// tab is on top: the root stays in the tab's stack under its pages, so it hears the tab and the scene change.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(Reachability.self) private var reachability
    @Environment(\.scenePhase) private var scenePhase
    @State private var shownOnce = false
    /// Which list the root is (Core's rule, kept here: changed only off screen).
    @State private var rootRule = LibraryRoot()
    @State private var rootList: LibraryRootList?

    init() {}

    var body: some View {
        root
            .onAppear {
                look()
                guard !shownOnce else { return }
                shownOnce = true
                if reachability.online { library.libraryShown() }
            }
            .task {
                // the path is known within moments of the start; should the monitor never say, the root is drawn anyway
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if rootList == nil { look(known: true) }
            }
            .onChange(of: navigation.tab) { _, tab in
                look()
                if tab == .library, reachability.online { library.libraryShown() }
            }
            .onChange(of: scenePhase) { _, phase in
                look()
                if phase == .active, navigation.tab == .library, reachability.online { library.libraryShown() }
            }
            .onChange(of: navigation.library.count) { _, _ in look() }
            .onChange(of: reachability.pathKnown) { _, _ in look() }
            .onChange(of: reachability.online) { _, online in
                look()
                // back: Navidrome asked again - a check that failed while deadwax was away says nothing of it
                if online { library.libraryShown() }
            }
            .onChange(of: server.person) { _, _ in
                library.libraryShown()
            }
            .onChange(of: server.signInOver == nil) { _, gone in
                // signed in again over the app, as the same person: what failed while signed out is asked again
                if gone { library.signedInAgain() }
            }
    }

    /// The root on screen: its tab chosen, nothing pushed over it, the app not in the background.
    private var onScreen: Bool {
        navigation.tab == .library && navigation.library.isEmpty && scenePhase != .background
    }

    /// The root's list looked at again (LibraryRoot.look): taken as it should be off screen, kept as it is on screen.
    private func look(known: Bool = false) {
        guard reachability.pathKnown || known else { return }
        var rule = rootRule
        let list = rule.look(online: reachability.online, onScreen: onScreen && rootList != nil)
        if rule != rootRule { rootRule = rule }
        if rootList != list { rootList = list }
    }

    @ViewBuilder private var root: some View {
        switch rootList {
        case nil:
            // the moment before the phone's path is known: nothing drawn rather than the wrong list
            Color.clear
                .navigationTitle("Library")
        case .downloaded:
            AlbumsScreen(list: .downloaded, root: true)
                .id("downloaded")
        case .albums:
            switch gate {
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

    /// The gate, consulted only while deadwax answers (5.4) - and not on a check that failed because deadwax itself
    /// didn't answer: that one is asked again as deadwax comes back, and the albums kept on disk draw meanwhile.
    private var gate: NavidromeGate.Shown {
        guard NavidromeGate.consulted(reachability.reach), library.navidrome?.offline != true else { return .open }
        return NavidromeGate.shownOnPhone(library.navidrome, access: server.access)
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
    @Environment(DownloadModel.self) private var downloads
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
                if NavidromeGate.showsDownloaded(.closed(closed), anythingHere: downloads.anythingHere) {
                    // Navidrome down is no reason to hide what plays from this phone (5.4)
                    PlaceGroup(title: DownloadWords.onThisPhone) {
                        PlaceRow(symbol: DownloadWords.downloadSymbol, label: DownloadWords.downloadedTitle,
                                 count: downloads.albumCount, route: .downloaded)
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Library")
        .refreshable { await library.checkNavidrome() }
    }
}
