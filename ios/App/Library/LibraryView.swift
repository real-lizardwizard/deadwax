import DeadwaxCore
import SwiftUI

/// The Library tab's root (D2; since Phase 4 slice 3b the switch - phase4-library.md 2.8, 3.1). James: "I like just
/// opening library to your albums", with a switch at the top - Albums | Playlists (Artists and Songs join in slices 4
/// and 5) - "and I would also like to be able to swipe left and right between them, and maybe a way to rearrange the
/// order". So the bar holds the switch (a segmented control, the pages in the order kept on this phone, LibraryPages),
/// the page's own buttons and the Library's ••• (LibraryMenu: Shuffle, Downloaded or the way back to the albums, All
/// music, Refresh, Edit order); Find under it; and under them the pages side by side, a swipe moving between them as
/// the switch does - each following the other. The Library opens on the first page of the order, and on it again for a
/// new person; after that, on the one last shown. Pulling a page down shuffles your library (2.8's PullShuffle; 3.5's
/// graphic) - never refreshes: the Library refreshes itself as it shows, and the •••'s Refresh asks now.
///
/// The Albums page is the Albums list of the person's scope - "Your albums" with a library of your own, "Albums" with
/// logins off and for the break-glass admin - or, when a check finds deadwax has no Navidrome that answers, the Navidrome
/// gate in the switch's place (NavidromeGate). While deadwax can't be reached (phase2-downloads.md 5.4) the Albums page
/// is Downloaded - what is on this phone - and the gate isn't consulted; its check runs again when deadwax answers. The
/// page never swaps under a finger: Core's LibraryRoot changes it only while it isn't on screen (another tab, a page
/// pushed over it, the app in the background), and the app opening starts on the list it should - so the first look
/// waits for the phone's path to be known, a moment at launch.
///
/// As the tab comes into view - picked, the app back in front on it, a new person - its lists are asked again if over a
/// minute old, your library is asked for its New marks (App.tsx's libraryShown), and the Shuffle's first page is asked
/// ahead when it should be (ShuffleModel), whichever page of the tab is on top: the root stays in the tab's stack under
/// its pages, so it hears the tab and the scene change.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(Reachability.self) private var reachability
    @Environment(ShuffleModel.self) private var shuffles
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownOnce = false
    /// Which list the Albums page is (Core's rule, kept here: changed only off screen).
    @State private var rootRule = LibraryRoot()
    @State private var rootList: LibraryRootList?
    /// The pages' order, as this phone keeps it (LibraryPages: read with care).
    @AppStorage(LibraryPages.storageKey) private var savedOrder = ""
    /// The page shown - nil until the Library first draws, when it is the first of the order. The settled page (slice
    /// 3b's review): a swipe changes it only once the pager is at rest, so the switch, the bar, Find and the pulls never
    /// change under a finger, and a half swipe let go changes nothing.
    @State private var page: LibraryPage?
    /// The page at the pager's centre as it scrolls (its scrollPosition) - `page` follows it once at rest.
    @State private var scrolled: LibraryPage?
    /// The pager is moving: a finger on it, or settling (iOS 18's scroll phase; never on iOS 17, where `page` follows
    /// `scrolled` at once - at the swipe's halfway, the centre anchor's).
    @State private var paging = false
    /// Each page's own words in Find.
    @State private var findAlbums = ""
    @State private var findPlaylists = ""
    /// Each page's pull.
    @State private var albumsPull = ShufflePull()
    @State private var playlistsPull = ShufflePull()
    @State private var editingOrder = false
    /// New playlist's sheet (the Playlists page's +), while it is up.
    @State private var newPlaylist: PlaylistsPage.NewSheet?

    init() {}

    var body: some View {
        root
            .onAppear {
                look()
                if page == nil { show(LibraryPages.first(order)) }
                guard !shownOnce else { return }
                shownOnce = true
                if reachability.online { shown() }
            }
            .task {
                // the path is known within moments of the start; should the monitor never say, the root is drawn anyway
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if rootList == nil { look(known: true) }
            }
            .onChange(of: navigation.tab) { _, tab in
                look()
                if tab == .library, reachability.online { shown() }
            }
            .onChange(of: scenePhase) { _, phase in
                look()
                if phase == .active, navigation.tab == .library, reachability.online { shown() }
            }
            .onChange(of: navigation.library.count) { _, _ in look() }
            .onChange(of: reachability.pathKnown) { _, _ in look() }
            .onChange(of: reachability.online) { _, online in
                look()
                // back: Navidrome asked again - a check that failed while deadwax was away says nothing of it
                if online { shown() }
            }
            .onChange(of: server.person) { _, _ in
                // a new person opens on the first page, Find empty
                show(LibraryPages.first(order))
                findAlbums = ""
                findPlaylists = ""
                shown()
            }
            .onChange(of: library.scope) { _, scope in
                // who the person is came in (or changed): the Shuffle of their scope
                if reachability.online { shuffles.shown(scope) }
            }
            .onChange(of: server.signInOver == nil) { _, gone in
                // signed in again over the app, as the same person: what failed while signed out is asked again
                if gone { library.signedInAgain() }
            }
    }

    /// The Library came into view: its lists, your library's New marks, and the Shuffle's first page.
    private func shown() {
        library.libraryShown()
        shuffles.shown(library.scope)
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
            pager(albums: .downloaded)
        case .albums:
            switch gate {
            case .open:
                pager(albums: .scope(library.scope))
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

    // MARK: the switch (slice 3b)

    /// The pages in the order kept.
    private var order: [LibraryPage] { LibraryPages.read(savedOrder) }

    /// The page shown.
    private var shownPage: LibraryPage { page ?? LibraryPages.first(order) }

    /// What the Shuffle can do now (ShuffleCan): play the first page in hand, shuffle the downloads, or why not. The
    /// songs on this phone are read only while deadwax can't be reached (slice 3b's review), so a download coming in
    /// doesn't redraw the pager online - and they are the very list the shuffle plays, so a pull never arms with
    /// nothing to play.
    private var shuffleCan: ShuffleCan {
        let online = reachability.online
        return ShuffleCan.of(online: online, ready: shuffles.ready, empty: shuffles.empty,
                             failed: shuffles.failure, songsHere: online ? 0 : downloads.songsHere.count)
    }

    /// The page shown set, the pager moved to it with it (the switch's tap, the first draw, a new person).
    private func show(_ chosen: LibraryPage) {
        page = chosen
        scrolled = chosen
    }

    /// The pager at rest (iOS 18): the page is the one at its centre.
    private func settled() {
        if let scrolled, scrolled != page { page = scrolled }
    }

    /// The pages side by side under the switch, a swipe between them; Find, the bar and the ••• the switch's.
    private func pager(albums: AlbumList) -> some View {
        let order = self.order
        let can = shuffleCan
        let shownPage = self.shownPage
        let online = reachability.online
        return ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // identified by the page itself, not its `id` string: scrollPosition(id:) matches the views' ids against
                // its binding's type, LibraryPage
                ForEach(order, id: \.self) { (each: LibraryPage) in
                    pageView(each, albums: albums, can: can, current: each == shownPage)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // the page at the centre, not the leading edge: a sliver of the next one isn't it
        .scrollPosition(id: $scrolled, anchor: .center)
        // the pager's own indicator only: the pages' lists keep theirs (the environment would carry it to them)
        .scrollIndicators(.hidden, axes: .horizontal)
        .pagerPhase(moving: $paging, settled: settled)
        .onChange(of: scrolled) { (_: LibraryPage?, now: LibraryPage?) -> Void in
            // at rest - iOS 17 always, iOS 18 a move no finger made (a layout's) - the page follows at once
            guard !paging, let now, now != page else { return }
            page = now
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: shownPage == .albums ? $findAlbums : $findPlaylists,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(shownPage == .albums ? LibraryWords.findPlaceholder : LibrarySwitchWords.findPlaylists))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            ToolbarItem(placement: .principal) {
                switcher(order)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                switch shownPage {
                case .albums:
                    LibrarySortMenu()
                    LibraryLayoutSwitch()
                case .playlists:
                    Button {
                        newPlaylist = PlaylistsPage.NewSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!online)
                    .accessibilityLabel(PlaylistWords.newPlaylist)
                }
                more(albums: albums, can: can)
            }
        }
        .sheet(isPresented: $editingOrder) {
            EditOrderSheet(saved: $savedOrder)
        }
    }

    @ViewBuilder
    private func pageView(_ each: LibraryPage, albums: AlbumList, can: ShuffleCan, current: Bool) -> some View {
        let pulls = current && onScreen
        switch each {
        case .albums:
            ZStack {
                AlbumsScreen(list: albums, page: AlbumsScreen.Page(typed: $findAlbums, current: current, pulls: pulls,
                                                                   pull: albumsPull, shuffle: can, start: shuffleNow))
                    // another scope (or Downloaded) is another list: its own place in it
                    .id(albums)
            }
        case .playlists:
            PlaylistsPage(typed: $findPlaylists, current: current,
                          pulling: PullShuffling(state: playlistsPull, can: can, on: pulls, start: shuffleNow),
                          newSheet: $newPlaylist)
        }
    }

    /// The switch: the pages in the order kept, its tap moving the page (at once under Reduce Motion).
    private func switcher(_ order: [LibraryPage]) -> some View {
        Picker(LibrarySwitchWords.switchLabel, selection: Binding(get: { shownPage }, set: { (chosen: LibraryPage) in
            if reduceMotion {
                show(chosen)
            } else {
                withAnimation(.snappy) { show(chosen) }
            }
        })) {
            ForEach(order) { (each: LibraryPage) in
                Text(each.title).tag(each)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityLabel(LibrarySwitchWords.switchLabel)
    }

    /// The Library's ••• (LibraryMenu, Core's): its sections, each item's words and whether it can be used now.
    private func more(albums: AlbumList, can: ShuffleCan) -> some View {
        let personal = server.access.hasLibrary
        let sections = LibraryMenu.sections(shuffle: can, albumsPage: albums == .downloaded ? .downloaded : .albums,
                                            scope: library.scope, personal: personal, online: reachability.online)
        return Menu {
            ForEach(sections.indices, id: \.self) { (section: Int) in
                Section {
                    ForEach(sections[section].indices, id: \.self) { (index: Int) in
                        menuItem(sections[section][index], personal: personal)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(LibrarySwitchWords.more)
    }

    @ViewBuilder
    private func menuItem(_ item: LibraryMenuItem, personal: Bool) -> some View {
        let words = item.words(personal: personal)
        switch item {
        case .shuffle:
            Button(action: shuffleNow) { Label(words, systemImage: "shuffle") }
                .disabled(!item.enabled)
        case .downloaded:
            Button { navigation.open(.downloaded) } label: { Label(words, systemImage: DownloadWords.downloadSymbol) }
        case .albums(let scope):
            Button { navigation.open(.albums(scope)) } label: { Label(words, systemImage: "square.stack") }
        case .allMusic:
            Button { navigation.open(.albums(.store)) } label: { Label(words, systemImage: "square.stack.3d.up") }
        case .refresh:
            Button(action: refresh) { Label(words, systemImage: "arrow.clockwise") }
        case .editOrder:
            Button { editingOrder = true } label: { Label(words, systemImage: "line.3.horizontal") }
        }
    }

    // MARK: doing

    /// The Shuffle - the •••'s tap, a pull's release - started here, in that call, nothing awaited first: the first page
    /// in hand played as a library's shuffle at the songs level (2.8), or, while deadwax can't be reached, every song on
    /// this phone shuffled as a playlist's Shuffle is (question 22). Nothing when neither can.
    private func shuffleNow() {
        switch shuffleCan {
        case .ready:
            guard let taken = shuffles.take(level: PlaylistPlay.songsLevel(player.normalization)) else { return }
            player.play(shuffled: taken)
        case .downloads:
            // the list the readiness counted; should it have emptied since (a removal), said, as the pull would
            let here = downloads.songsHere
            guard !here.isEmpty else {
                player.say(PullShuffleWords.nothingHere)
                return
            }
            player.play(playlist: here, at: nil, shuffle: true)
        case .gettingReady, .failed, .nothingHere, .none:
            break
        }
    }

    /// The •••'s Refresh: your albums and the playlists asked now, whatever their age - or, while deadwax can't be
    /// reached, whether it is back (a probe at once).
    private func refresh() {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        let scope = library.scope
        Task { await library.refresh(scope) }
        Task { await playlists.ask(fresh: true) }
        shuffles.shown(scope)
    }
}

/// Edit order (3.5): the pages as rows, each with its drag handle - a List held in edit mode, no deletions - kept as
/// each move is made; the footer says the Library opens on the first.
private struct EditOrderSheet: View {
    @Binding var saved: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let order = LibraryPages.read(saved)
        NavigationStack {
            List {
                Section {
                    ForEach(order) { (page: LibraryPage) in
                        Text(page.title)
                    }
                    .onMove { (from: IndexSet, to: Int) -> Void in
                        saved = LibraryPages.saved(LibraryPages.moved(order, from: from, to: to))
                    }
                } footer: {
                    Text(LibrarySwitchWords.orderFooter)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(LibrarySwitchWords.orderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LibrarySwitchWords.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                    .buttonStyle(PrimaryFace())
                    .disabled(library.checkingNavidrome)
                    .accessibilityLabel(NavidromeGate.tryAgain)
                }
                if closed.setUp, let address = server.address, let url = NavidromeGate.setUpURL(address) {
                    Button(NavidromeGate.setUp) { openURL(url) }
                        .buttonStyle(PrimaryFace())
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

private extension View {
    /// (slice 3b's review) The pager's scroll phase, iOS 18's: `moving` while a finger is on it or it settles, and
    /// `settled` called as it comes to rest. iOS 17 has no phase: neither is touched, and the page follows the centre
    /// at once.
    @ViewBuilder
    func pagerPhase(moving: Binding<Bool>, settled: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { (_: ScrollPhase, now: ScrollPhase) -> Void in
                moving.wrappedValue = now != .idle
                if now == .idle { settled() }
            }
        } else {
            self
        }
    }
}
