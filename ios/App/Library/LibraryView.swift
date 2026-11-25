import DeadwaxCore
import SwiftUI

/// The Library tab's root (D2; since Phase 4 slice 3b the switch - phase4-library.md 2.8, 3.1). James: "I like just
/// opening library to your albums", with a switch at the top - Albums | Playlists | Artists (slice 4) | Songs (slice 5,
/// only where the collection is the Library: with a library of your own it is All music's All songs, question 32) -
/// "and I would also like to be able to swipe left and right between them, and maybe a way to rearrange the order". So
/// the top holds the switch (the pages shown in the order kept on this phone, LibraryPages) and the Library's •••
/// (LibraryMenu: Shuffle; the page's own order, and Albums' Show as list or grid - in the ••• since slice 4, question
/// 26, so three pages and more fit - and Playlists' New playlist; Downloaded or the way back to the albums, All
/// music's submenu - All albums, All artists, All songs; Refresh, Edit order); and under them the pages side by side, a
/// swipe moving between them as the switch does - each following the other. The Library opens on the
/// first page of the order, and on it again for a new person; after that, on the one last shown. Pulling a page down
/// shuffles your library (2.8's PullShuffle; 3.5's graphic) - never refreshes: the Library refreshes itself as it
/// shows, and the •••'s Refresh asks now.
///
/// THE TOP (the squared look, 14 Nov - LibraryTop): James, "the search bar is kinda in the way". The navigation bar is
/// hidden on the pager and the Library draws its own top. Since the redesign's slice R2 (notes/ios.md "The redesign,
/// slice R2: Albums and Artists, and the Library's top"; James's answer 1, "Today's behaviour, new look") it is
/// iLibrary's: "Library", Yours | All with a library of your own (All: All music's albums, artists and songs as the
/// pages, where the •••'s All music pushed them), Find's magnifying glass and the •••, square; under it the strip
/// (PhoneStrip) - the pages in the order kept, then Downloaded, pushed - and the offline banner. Each page's meta line
/// is its own: its count, its order (out of the •••), Albums' Grid and List, Playlists' New playlist. Find is shown
/// only once the magnifying glass is tapped: its field under the top for the page shown, focused, the keyboard up; each
/// page keeps its own words while it is open, a swipe or a chip showing the next page's; Cancel hides it and clears
/// every page's words, so a hidden Find never filters a list unseen. A new person closes it too.
///
/// (R2) On the Mac its Albums and Artists at the root are the Mac's own column lists (`desk`, from MacLibrary.root());
/// the iPhone's Library has none.
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
struct LibraryView<Desk: View>: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(Reachability.self) private var reachability
    @Environment(ShuffleModel.self) private var shuffles
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(ArtistsModel.self) private var artists
    @Environment(SongsModel.self) private var songs
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
    /// Find is open (the magnifying glass): its field under the switch, the page shown's words in it.
    @State private var finding = false
    @FocusState private var findFocused: Bool
    /// Each page's own words in Find.
    @State private var findAlbums = ""
    @State private var findPlaylists = ""
    @State private var findArtists = ""
    @State private var findSongs = ""
    /// Each page's pull.
    @State private var albumsPull = ShufflePull()
    @State private var playlistsPull = ShufflePull()
    @State private var artistsPull = ShufflePull()
    @State private var songsPull = ShufflePull()
    @State private var editingOrder = false
    /// New playlist's sheet (the Playlists page's +), while it is up.
    @State private var newPlaylist: PlaylistsPage.NewSheet?
    /// (Phase 8, slice 8) Set up Navidrome's sheet is up: held here, above the gate, so the gate giving way - deadwax
    /// going out of reach opens it, a save mid-way included - never takes the sheet with it.
    @State private var settingUp = false
    @Environment(ServerSettingsModel.self) private var serverSettings
    /// (R2) Yours | All's choice - Yours for a new person, and whenever the switch isn't shown (`side`).
    @State private var chosenSide: LibrarySide = .yours
    /// (R2) The Mac's own page for Albums or Artists at the root, in the scope given - nil on the iPhone.
    private let desk: ((LibraryPage, AlbumScope) -> Desk)?

    /// (R2) The Mac's Library: its Albums and Artists drawn by `desk`.
    init(desk: @escaping (LibraryPage, AlbumScope) -> Desk) {
        self.desk = desk
    }

    var body: some View {
        // a ZStack over the root's switch, so what is attached below stays on one view whichever list is drawn
        ZStack { root }
            // Server settings' Connections page over the Library; it goes when Close says so, or Navidrome answers
            .appSheet(isPresented: $settingUp) {
                SetUpNavidromeSheet()
                    .macSheet()
            }
            .onChange(of: navidromeAnswers) { _, _ in setUpDone() }
            .onChange(of: serverSettings.flow.saving) { _, _ in setUpDone() }
            .onAppear {
                look()
                // (the Mac app, slice 2) the Mac's window opened again: on the page it showed (never set on the iPhone)
                if page == nil { show(navigation.macLibraryPage ?? LibraryPages.first(shownOrder)) }
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
            .onChange(of: page) { (_: LibraryPage?, now: LibraryPage?) -> Void in
                // (the Mac app, slice 2) kept beside the tab for the window closed and opened again - the Mac's alone
                if Platform.mac { navigation.macLibraryPage = now }
            }
            .onChange(of: navigation.macLibraryPage) { (_: LibraryPage?, asked: LibraryPage?) -> Void in
                // (the Mac app, slice 3) a sidebar row's page of the Library, shown - the page the switch has already
                // is let be (it wrote it). Never on the iPhone, where nothing writes it
                if let asked, asked != page { show(LibraryPages.showing(asked, in: shownOrder)) }
            }
            .onChange(of: server.person) { _, _ in
                // a new person opens on the first page of Yours, Find closed and empty - and no Set up Navidrome left up
                chosenSide = .yours
                show(LibraryPages.first(shownOrder))
                finding = false
                settingUp = false
                clearFind()
                shown()
            }
            .onChange(of: library.scope) { _, scope in
                // who the person is came in (or changed): the Shuffle of their scope
                if reachability.online { shuffles.shown(.library, scope) }
            }
            .onChange(of: server.access.hasLibrary) { _, _ in
                // (slice 5) a library of your own came in, or went: Songs shown or not - the page kept while it still is
                show(LibraryPages.showing(page, in: shownOrder))
            }
            .onChange(of: side) { _, _ in
                // (R2) Yours | All: the other side's pages - the page kept where that side has it, else its first
                show(LibraryPages.showing(page, in: shownOrder))
            }
            .onChange(of: server.signInOver == nil) { _, gone in
                // signed in again over the app, as the same person: what failed while signed out is asked again
                if gone { library.signedInAgain() }
            }
    }

    /// The Library came into view: its lists, your library's New marks, and the Shuffle's first page - (R2) on All, the
    /// collection's too.
    private func shown() {
        library.libraryShown()
        shuffles.shown(.library, library.scope)
        if side == .all { shuffles.shown(.allSongs, library.scope) }
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
                .showsOfflineBanner()
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .showsOfflineBanner()
            case .closed(let closed):
                NavidromeGateView(closed: closed) { settingUp = true }
                    .showsOfflineBanner()
            }
        }
    }

    /// The gate, consulted only while deadwax answers (5.4) - and not on a check that failed because deadwax itself
    /// didn't answer: that one is asked again as deadwax comes back, and the albums kept on disk draw meanwhile.
    private var gate: NavidromeGate.Shown {
        guard NavidromeGate.consulted(reachability.reach), library.navidrome?.offline != true else { return .open }
        return NavidromeGate.shownOnPhone(library.navidrome, access: server.access, device: Platform.device)
    }

    /// Navidrome really answers - not the gate merely giving way: deadwax in reach, and the newest check (only the
    /// newest lands - LibraryModel.checkNavidrome) one deadwax answered, finding Navidrome there. The sheet only ever
    /// opens over a closed gate, whose check said otherwise, so this turns true only on a check that landed since.
    private var navidromeAnswers: Bool {
        guard NavidromeGate.consulted(reachability.reach), let checked = library.navidrome else { return false }
        return !checked.offline && checked.status.ok
    }

    /// Set up Navidrome done: the sheet put away once Navidrome answers - never during a save (the sheet can't be
    /// closed then; it goes as the save ends), and never only because deadwax went out of reach.
    private func setUpDone() {
        guard settingUp, navidromeAnswers, !serverSettings.flow.saving else { return }
        settingUp = false
    }

    // MARK: the strip (slice 3b's switch; since R2 the phone's strip)

    /// The pages in the order kept.
    private var order: [LibraryPage] { LibraryPages.read(savedOrder) }

    /// (R2) The top shows Yours | All: with a library of your own, on your albums, where the •••'s All music was - while
    /// deadwax can be reached, or (its review) while All is the side chosen, so deadwax dropping out never turns a
    /// chosen All back into Yours on screen: All's pages stay, drawing what is in hand. Never on the Mac, whose sidebar
    /// has All music's lists.
    private var sides: Bool {
        !Platform.mac && LibraryPages.sides(personal: server.access.hasLibrary, scope: library.scope,
                                            online: reachability.online, chosen: chosenSide)
    }

    /// (R2) The side drawn: the one chosen while Yours | All shows, Yours otherwise.
    private var side: LibrarySide { LibraryPages.side(chosenSide, sides: sides) }

    /// (slice 5, question 32; R2) The pages the strip shows, in the order kept: Songs only without a library of your
    /// own - never beside your own albums - and on All, All music's albums, artists and songs.
    private var shownOrder: [LibraryPage] {
        LibraryPages.shown(order, personal: server.access.hasLibrary, side: side)
    }

    /// The page shown - always one the strip shows.
    private var shownPage: LibraryPage { LibraryPages.showing(page, in: shownOrder) }

    /// (R2) Whose Shuffle the pulls and the •••'s are: the Library's, or on All the collection's (All songs').
    private var shuffleOf: ShuffleOf { side.shuffle }

    /// What the Shuffle can do now (ShuffleCan): play the first page in hand, shuffle the downloads, or why not. The
    /// songs on this phone are read only while deadwax can't be reached (slice 3b's review), so a download coming in
    /// doesn't redraw the pager online - and they are the very list the shuffle plays, so a pull never arms with
    /// nothing to play.
    private var shuffleCan: ShuffleCan {
        let online = reachability.online
        let which = shuffleOf
        return ShuffleCan.of(online: online, ready: shuffles.ready(which), empty: shuffles.empty(which),
                             failed: shuffles.failure(which), songsHere: online ? 0 : downloads.songsHere.count)
    }

    /// The page shown set, the pager moved to it with it (a chip's tap, the first draw, a new person).
    private func show(_ chosen: LibraryPage) {
        page = chosen
        scrolled = chosen
    }

    /// The pager at rest (iOS 18): the page is the one at its centre.
    private func settled() {
        if let scrolled, scrolled != page { page = scrolled }
    }

    /// The pages side by side under the Library's own top (since R2 iLibrary's - "Library", Yours | All, Find, the •••),
    /// the strip of the pages under it, a swipe between them; the navigation bar hidden; the offline banner between the
    /// strip and the pages.
    ///
    /// One above the other in a VStack (15 Nov, James: "on the app the top bar is obstructed by the Dynamic Island"):
    /// the top, the banner, the pager. A VStack is laid out in the safe area whatever its children do, so the top's row
    /// always starts under the status bar and the Dynamic Island, where an inset on the pager - a scroll view, free to
    /// run under the status bar - put it in the island's strip; only the top's own fill reaches up behind the status bar
    /// (LibraryTop). The pages end at the strip's foot rather than scrolling under it.
    ///
    /// (R2) On the Mac, Albums and Artists at the root are the Mac's own pages (MacLibrary's - `desk`), drawn in the
    /// pager's place under their own toolbar; its Playlists and Songs are the phone's, borrowed.
    private func pager(albums: AlbumList) -> some View {
        let order = shownOrder
        let can = shuffleCan
        let shownPage = self.shownPage
        // (R2) All's albums are the collection's - (its review) always, Downloaded being Yours' stand-in alone
        let list = side.albums(albums)
        // (R5) and Playlists, the Mac's own list - whatever the side, playlists being no scope's
        let desk = Platform.mac && (list != .downloaded && (shownPage == .albums || shownPage == .artists)
            || shownPage == .playlists) ? self.desk : nil
        return VStack(spacing: 0) {
            if desk == nil {
                LibraryTop(finding: finding, findLabel: findPrompt(shownPage), openFind: { openFind() }) {
                    findField(shownPage)
                } sides: {
                    sidesControl
                } more: {
                    more(albums: list, can: can)
                }
                strip(order, albums: list)
            }
            // the banner under the top, not over it: TabStack leaves the Library's to it
            OfflineBanner()
            if let desk {
                desk(shownPage, library.scope)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        // identified by the page itself, not its `id` string: scrollPosition(id:) matches the views' ids
                        // against its binding's type, LibraryPage
                        ForEach(order, id: \.self) { (each: LibraryPage) in
                            pageView(each, albums: list, can: can, current: each == shownPage)
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
            }
        }
        // the title the pages pushed over it go back to; the bar itself is the Library's own top
        .navigationTitle("Library")
        .toolbar(.hidden, for: .navigationBar)
        // (the Mac app, slice 2) ⌘R: the •••'s Refresh, while the Library shows; nothing on the iPhone, where the pull
        // shuffles and the ••• has it
        .refreshCommand { refresh() }
        .appSheet(isPresented: $editingOrder) {
            EditOrderSheet(saved: $savedOrder, personal: server.access.hasLibrary)
                .macSheet()
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
        case .artists:
            // (R2) on All, the collection's artists
            ArtistsScreen(page: ArtistsScreen.Page(
                typed: $findArtists, current: current,
                pulling: PullShuffling(state: artistsPull, can: can, on: pulls, start: shuffleNow),
                scope: side.artistsScope))
                .id(side)
        case .songs:
            SongsScreen(page: SongsScreen.Page(
                typed: $findSongs, current: current,
                pulling: PullShuffling(state: songsPull, can: can, on: pulls, start: shuffleNow)))
        }
    }

    /// Each page's own words in Find.
    private func find(_ page: LibraryPage) -> Binding<String> {
        switch page {
        case .albums: return $findAlbums
        case .playlists: return $findPlaylists
        case .artists: return $findArtists
        case .songs: return $findSongs
        }
    }

    private func findPrompt(_ page: LibraryPage) -> String {
        switch page {
        case .albums: return LibraryWords.findPlaceholder
        case .playlists: return LibrarySwitchWords.findPlaylists
        case .artists: return ArtistWords.findPlaceholder
        case .songs: return SongWords.findPlaceholder
        }
    }

    // MARK: Find (the squared look; since R2 in the look's well)

    /// Find's field under the top, for the page shown - its own words, its own prompt - and Cancel. Typing finds as it
    /// did in the bar's drawer; the keyboard's Search puts the keyboard away and leaves the words. (R2) In the look's
    /// field: its well, the accent's edge while it has the cursor, the words in the field's white, Cancel in the accent.
    private func findField(_ page: LibraryPage) -> some View {
        HStack(spacing: CGFloat(PhoneLook.topGap)) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DWPalette.t3)
                    .accessibilityHidden(true)
                TextField(findPrompt(page), text: find(page), prompt: Text(findPrompt(page)).foregroundStyle(DWPalette.t3))
                    .textFieldStyle(.plain)
                    .font(Typeface.Look.text(.field))
                    .foregroundStyle(DWPalette.fieldText)
                    .focused($findFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { findFocused = false }
            }
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: findFocused)
            }
            .task {
                // focused once it is drawn: a focus asked before the field exists is lost
                findFocused = true
            }
            Button(action: closeFind) {
                Text(LibrarySwitchWords.cancelFind)
                    .font(Typeface.Phone.text(.back))
                    .foregroundStyle(DWPalette.acc)
                    .contentShape(DWTarget(face: Rectangle()))
            }
            .buttonStyle(.plain)
        }
    }

    /// The magnifying glass: Find opened, focused, the keyboard up - or, open already, its field focused again.
    private func openFind() {
        if !finding {
            if reduceMotion {
                finding = true
            } else {
                withAnimation(.snappy) { finding = true }
            }
        }
        findFocused = true
    }

    /// Cancel: Find hidden, and every page's words cleared - a hidden Find never filters a list unseen.
    private func closeFind() {
        findFocused = false
        clearFind()
        if reduceMotion {
            finding = false
        } else {
            withAnimation(.snappy) { finding = false }
        }
    }

    private func clearFind() {
        findAlbums = ""
        findPlaylists = ""
        findArtists = ""
        findSongs = ""
    }

    /// (R2) The strip (iLibrary's .chips, PhoneStrip): the pages in the order kept, then Downloaded. A page's chip moves
    /// the pager to it as the switch's tap did - moving as the Library's swipe does, at once under Reduce Motion - and
    /// a swipe settling lights its chip; Downloaded is pushed on the tab's path, as the •••'s Downloaded was - so (its
    /// review) it is a button to VoiceOver, after the tab bar of the pages, never a tab (PhoneStrip's `pushes`).
    private func strip(_ order: [LibraryPage], albums: AlbumList) -> some View {
        let shownPage = self.shownPage
        let items = LibraryStrip.items(order, albumsPage: albums == .downloaded ? .downloaded : .albums)
        return PhoneStrip(options: items.filter { (item: LibraryStripItem) -> Bool in !item.pushes },
                          words: { (item: LibraryStripItem) -> String in item.title },
                          shown: Binding(get: { LibraryStripItem.page(shownPage) },
                                         set: { (item: LibraryStripItem) -> Void in chose(item) }),
                          spoken: LibrarySwitchWords.switchLabel,
                          pushes: items.filter { (item: LibraryStripItem) -> Bool in item.pushes })
    }

    /// A chip tapped: its page shown, the pager moved to it - or Downloaded pushed.
    private func chose(_ item: LibraryStripItem) {
        switch item {
        case .page(let chosen):
            withAnimation(reduceMotion ? nil : .snappy) { show(chosen) }
        case .downloaded:
            navigation.open(.downloaded)
        }
    }

    /// (R2, James's answer 1) Yours | All, with a library of your own: All shows All music's albums, artists and songs
    /// as the pages, in the •••'s All music's place.
    @ViewBuilder private var sidesControl: some View {
        if sides {
            DWSegmented(options: LibrarySide.allCases, words: { (each: LibrarySide) -> String in each.title },
                        chosen: Binding(get: { side }, set: { (chosen: LibrarySide) -> Void in choose(chosen) }),
                        spoken: LibrarySwitchWords.sidesLabel)
        }
    }

    /// A side chosen: its pages drawn (`.onChange(of: side)` keeps the page where it has it), and on All the
    /// collection's Shuffle asked ahead.
    private func choose(_ chosen: LibrarySide) {
        guard chosen != chosenSide else { return }
        chosenSide = chosen
        if chosen == .all, reachability.online { shuffles.shown(.allSongs, library.scope) }
    }

    /// The Library's ••• (Core's LibraryMenu.topSections since R2): the Shuffle, the way back to the albums while the
    /// Albums page is Downloaded, Refresh and Edit order - the rest moved to the meta line, the strip and Yours | All. A
    /// small square button, as the magnifying glass is.
    private func more(albums: AlbumList, can: ShuffleCan) -> some View {
        let personal = server.access.hasLibrary
        let sections = LibraryMenu.topSections(shuffle: can, albumsPage: albums == .downloaded ? .downloaded : .albums,
                                               scope: library.scope)
        return Menu {
            ForEach(sections.indices, id: \.self) { (section: Int) in
                Section {
                    ForEach(sections[section].indices, id: \.self) { (index: Int) in
                        menuItem(sections[section][index], personal: personal)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        // the label takes the button style as a button menu's
        .menuStyle(.button)
        .buttonStyle(DWButtonStyle(size: .small))
        .menuIndicator(.hidden)
        .accessibilityLabel(LibrarySwitchWords.more)
        .accessibilityShowsLargeContentViewer {
            Label(LibrarySwitchWords.more, systemImage: "ellipsis")
        }
    }

    @ViewBuilder
    private func menuItem(_ item: LibraryMenuItem, personal: Bool) -> some View {
        let words = item.words(personal: personal)
        switch item {
        case .shuffle:
            Button(action: shuffleNow) { Label(words, systemImage: "shuffle") }
                .disabled(!item.enabled)
        case .albums(let scope):
            Button { navigation.open(.albums(scope)) } label: { Label(words, systemImage: "square.stack") }
        case .refresh:
            Button(action: refresh) { Label(words, systemImage: "arrow.clockwise") }
        case .editOrder:
            Button { editingOrder = true } label: { Label(words, systemImage: "line.3.horizontal") }
        }
    }

    // MARK: doing

    /// The Shuffle - the •••'s tap, a pull's release - started here, in that call, nothing awaited first: the first page
    /// in hand played as a library's shuffle at the songs level (2.8) - on All (R2) the collection's, All songs' - or,
    /// while deadwax can't be reached, every song on this phone shuffled as a playlist's Shuffle is (question 22).
    /// Nothing when neither can.
    private func shuffleNow() {
        switch shuffleCan {
        case .ready:
            guard let taken = shuffles.take(shuffleOf, level: PlaylistPlay.songsLevel(player.normalization)) else { return }
            player.play(shuffled: taken)
        case .downloads:
            // the list the readiness counted; should it have emptied since (a removal), said, as the pull would
            let here = downloads.songsHere
            guard !here.isEmpty else {
                player.say(PullShuffleWords.nothingHere(Platform.device))
                return
            }
            player.play(playlist: here, at: nil, shuffle: true)
        case .gettingReady, .failed, .nothingHere, .none:
            break
        }
    }

    /// The •••'s Refresh: the side's albums, the playlists and the artists asked now, whatever their age - and (slice
    /// 5) the Songs page's first page, once it has been shown - or, while deadwax can't be reached, whether it is back
    /// (a probe at once).
    private func refresh() {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        let scope = side == .all ? AlbumScope.store : library.scope
        Task { await library.refresh(scope) }
        Task { await playlists.ask(fresh: true) }
        Task { await artists.ask() }
        if !server.access.hasLibrary || side == .all, songs.paging.query != nil { songs.refresh(findSongs) }
        shuffles.shown(shuffleOf, library.scope)
    }
}

extension LibraryView where Desk == EmptyView {
    /// The iPhone's Library, and the Mac's before R2: the pager on every page.
    init() {
        desk = nil
    }
}

/// Edit order (3.5): the pages the switch shows as rows, each with its drag handle - a List held in edit mode, no
/// deletions - kept as each move is made; the footer says the Library opens on the first. (slice 5) With a library of
/// your own, Songs isn't a page of the switch: it isn't listed, and keeps its place in the order kept.
private struct EditOrderSheet: View {
    @Binding var saved: String
    let personal: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let order = LibraryPages.read(saved)
        NavigationStack {
            List {
                Section {
                    ForEach(LibraryPages.shown(order, personal: personal)) { (page: LibraryPage) in
                        Text(page.title)
                    }
                    .onMove { (from: IndexSet, to: Int) -> Void in
                        saved = LibraryPages.saved(LibraryPages.moved(order, personal: personal, from: from, to: to))
                    }
                } footer: {
                    Text(LibrarySwitchWords.orderFooter)
                        .font(Typeface.footnote)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(LibrarySwitchWords.orderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LibrarySwitchWords.done) { dismiss() }
                        .escapeCloses()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The Navidrome gate drawn (app/NeedsNavidrome.tsx): why the Library has no albums to show, in the words Core's
/// NavidromeGate gives this reader, Try again (asks Navidrome again - also on a pull) and, for an admin, Set up
/// Navidrome - since Phase 8, slice 8 the app's own Server settings, its Connections group page in a sheet over the
/// Library (SetUpNavidromeSheet) - held and drawn by LibraryView, above the gate, so the gate giving way never takes
/// it. Saved, the Library asks Navidrome again, and the sheet goes once Navidrome
/// answers. Navidrome's own words, for whoever runs deadwax, can be selected to copy.
struct NavidromeGateView: View {
    let closed: NavidromeGate.Closed
    /// Set up Navidrome pressed: LibraryView's sheet put up.
    let setUp: () -> Void

    @Environment(LibraryModel.self) private var library
    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(closed.title)
                    .font(Typeface.title3.weight(.semibold))
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
                if closed.setUp {
                    Button(NavidromeGate.setUp) { setUp() }
                        .buttonStyle(PrimaryFace())
                }
                if NavidromeGate.showsDownloaded(.closed(closed), anythingHere: downloads.anythingHere) {
                    // Navidrome down is no reason to hide what plays from this phone (5.4)
                    PlaceGroup(title: DownloadWords.onThisDevice(Platform.device)) {
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
        .pullToRefresh { await library.checkNavidrome() }
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
