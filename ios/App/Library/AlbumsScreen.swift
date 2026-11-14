import DeadwaxCore
import SwiftUI

/// One Albums screen (app/LibrarySection.tsx AlbumSection, D2): every album of a list - yours, the store's, or what is
/// on this phone (Downloaded, phase2-downloads.md 5.1) - in the order chosen, under its headers, as tiles or rows; Find
/// in place; the index down the edge; the New marks, and each album's download mark. What it draws is Core's: the body
/// by AlbumListBody, the order, headers, Find, count and index by Shelf.view (through LibraryModel.drawn, made once per
/// list, sort and Find), the words LibraryWords' and DownloadWords'.
///
/// Two ways it is drawn (Phase 4, slice 3b - phase4-library.md 2.8, 3.1). As the Library's Albums page (`page`), under
/// the switch: the albums alone from the top, their count and then the albums - no rows above them (James: "I like
/// just opening library to your albums") - with the switch's Find, bar and •••, and a pull that shuffles (3.5), never
/// refreshes. Pushed on the tab's path (All albums, Downloaded - AppRoute.albums, .downloaded): its own title, Find,
/// sort and layout, and pull to refresh.
///
/// A scope's list is the model's, shared by every screen of the scope and kept on disk; this screen asks for it as it
/// shows and again whenever its generation moves (an Add or a Remove, the starred count, older than a minute). A list
/// asked again swaps in where the old one was - never emptied, the scroll kept. Downloaded is never asked of deadwax: it
/// is DownloadModel's albums, its Recently added the moment each arrived; at its top, the first ask's card (question
/// 17) and Downloaded playlists. Choosing a sort or typing into Find goes back to the top. Tapping the Library tab again
/// scrolls the page shown to its top; the pushed lists are pages of the tab's own, so the tab's tap pops them with
/// whatever album is over them. Nothing here plays but the pull (the gesture rule): a tile opens its album.
///
/// While deadwax can't be reached (5.4) the Albums page is Downloaded, named at its top, with "Only downloaded albums play
/// until deadwax is back."; an album with nothing on this phone is dimmed and opens nothing, a list that couldn't be
/// asked again says nothing of it (the banner says it once for every page), and a pushed list's pull asks whether
/// deadwax is back.
struct AlbumsScreen: View {
    /// The Library's Albums page (slice 3b): what the switch hands it.
    struct Page {
        /// Find's words - the switch's field, this page's own text in it.
        let typed: Binding<String>
        /// The page the switch shows: the tab's tap scrolls it to its top.
        let current: Bool
        /// It pulls to shuffle: the page shown, on screen.
        let pulls: Bool
        let pull: ShufflePull
        let shuffle: ShuffleCan
        /// The shuffle, started in the lift that releases the pull.
        let start: () -> Void
    }

    let list: AlbumList
    /// nil: a screen pushed on the tab's path.
    let page: Page?

    /// A scope's albums, pushed (All music's All albums, the way back to your albums).
    init(scope: AlbumScope) {
        self.init(list: .scope(scope))
    }

    init(list: AlbumList, page: Page? = nil) {
        self.list = list
        self.page = page
    }

    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    /// What is typed into a pushed screen's Find - the screen's own: leaving it clears it.
    @State private var ownTyped = ""
    /// On screen (not covered by a page pushed over it).
    @State private var shown = false

    /// The tiles' gap, and the screen's side margins.
    private static let gap: CGFloat = 14
    private static let edge: CGFloat = 16

    /// What the screen's ask is keyed on: a new person or a new generation is a new look.
    private struct LoadKey: Equatable {
        let person: Int
        let generation: Int
    }

    /// The scope asked of deadwax - nil for Downloaded.
    private var scope: AlbumScope? {
        if case .scope(let scope) = list { return scope }
        return nil
    }

    /// Find's words: the switch's for the page, the screen's own pushed.
    private var typed: String { page?.typed.wrappedValue ?? ownTyped }

    /// Showing: on screen, and - as a page - the one the switch shows.
    private var showing: Bool { shown && (page?.current ?? true) }

    var body: some View {
        let personal = server.access.hasLibrary
        Group {
            if let page {
                shelf(personal: personal, page: page)
            } else {
                shelf(personal: personal, page: nil)
                    .navigationTitle(title(personal: personal))
                    .searchable(text: $ownTyped, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: Text(LibraryWords.findPlaceholder))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            LibrarySortMenu()
                            LibraryLayoutSwitch()
                        }
                    }
                    .refreshable { await pulled() }
            }
        }
        .task(id: LoadKey(person: server.person, generation: scope.map { library.generations[$0] ?? 0 } ?? 0)) {
            guard let scope else { return }
            await library.load(scope)
        }
        // a ring moves only while it shows: the root stays in the tab's stack under its pages
        .task(id: showing) {
            guard showing else { return }
            await downloads.followProgress()
        }
        .onAppear {
            shown = true
            if let scope, reachability.online { library.refreshIfOld(scope) }
        }
        .onDisappear { shown = false }
    }

    @ViewBuilder
    private func shelf(personal: Bool, page: Page?) -> some View {
        let online = reachability.online
        let drawn = self.drawn
        let failure = scope.flatMap { library.failures[$0] }
        let finding = Find.finding(typed)
        let entries = drawn?.view.index ?? []
        let years = ShelfIndex.kind(library.sort) == .decades

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                        .overlay(alignment: .bottom) {
                            // the pull's graphic, in the room the pull opens above the first row (3.5)
                            if let page {
                                PullShuffleGraphic(state: page.pull, can: page.shuffle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    // Downloaded's own top (slice 3: its downloaded playlists; 3b: the first ask's card)
                    if list == .downloaded && !finding {
                        downloadedTop(page: page, online: online)
                    }
                    if let drawn, !drawn.view.countText.isEmpty, !(list == .downloaded && drawn.albums.isEmpty) {
                        Text(drawn.view.countText)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                    if online, drawn != nil, let failure, let scope {
                        RefreshProblemNote(failure: failure) { Task { await library.load(scope) } }
                    }
                    if drawn?.truncated == true {
                        Text(LibraryWords.truncated)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content(drawn, failure: failure, personal: personal, online: online)
                }
                .padding(.leading, Self.edge)
                .padding(.trailing, entries.isEmpty ? Self.edge : ShelfIndexStrip.width(years: years) + 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(entries.isEmpty ? .automatic : .hidden)
            .pullsToShuffle(page.map { (page: Page) -> PullShuffling in
                PullShuffling(state: page.pull, can: page.shuffle, on: page.pulls, start: page.start)
            })
            .overlay(alignment: .trailing) {
                if !entries.isEmpty {
                    ShelfIndexStrip(entries: entries, years: years) { group in
                        jump(proxy, to: .group(group))
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .onChange(of: typed) { _, _ in jump(proxy, to: .top) }
            .onChange(of: library.sort) { _, _ in jump(proxy, to: .top) }
            .onChange(of: navigation.libraryScrollToTop) { _, _ in
                // the Library tab tapped at its root: the page shown goes to its top
                guard shown, page?.current == true else { return }
                jump(proxy, to: .top, animated: true)
            }
        }
    }

    /// The list drawn: a scope's from the model's kept list, Downloaded from the albums on this phone.
    private var drawn: DrawnShelf? {
        switch list {
        case .scope(let scope): return library.drawn(scope, typed: typed)
        case .downloaded: return library.drawnDownloaded(downloads.downloadedAlbums, typed: typed)
        }
    }

    private func title(personal: Bool) -> String {
        switch list {
        case .scope(let scope): return LibraryWords.title(scope, personal: personal)
        case .downloaded: return DownloadWords.downloadedTitle
        }
    }

    /// A pushed list's pull: asked again now - or, while deadwax can't be reached, whether it is back (a probe at once).
    private func pulled() async {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        guard let scope else { return }
        await library.refresh(scope)
    }

    // MARK: Downloaded's top (5.2, 5.4; slice 3b)

    @ViewBuilder
    private func downloadedTop(page: Page?, online: Bool) -> some View {
        // the playlists its screen lists (the shelf: those whose answer can be read), never an unreadable row's
        let downloadedPlaylists = PlaylistDownloads.shelf(downloads.playlists.kept).count
        let offlinePage = page != nil && !online
        VStack(alignment: .leading, spacing: 0) {
            if page != nil {
                // the Albums page while deadwax can't be reached is Downloaded: named here, the switch holding the bar
                Text(DownloadWords.downloadedTitle)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 6)
            }
            // the first ask (phase3-autodownload.md 3.2; question 17): no longer over the albums - here, once deadwax
            // answered with albums of the Library's to download
            if online, library.albums(library.scope)?.albums.isEmpty == false {
                FirstAskCard()
            }
            // (slice 3) the playlists downloaded to this phone, under Downloaded
            if downloadedPlaylists > 0 {
                PlaceRow(symbol: "music.note.list", label: PlaylistDownloadWords.place,
                         count: downloadedPlaylists, counted: PlaylistDownloadWords.count,
                         route: .downloadedPlaylists, divider: !offlinePage)
            }
            if offlinePage {
                Text(DownloadWords.onlyDownloadedPlay)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                Divider()
            }
        }
    }

    // MARK: the body (AlbumListBody)

    @ViewBuilder
    private func content(_ drawn: DrawnShelf?, failure: APIFailure?, personal: Bool, online: Bool) -> some View {
        if list == .downloaded, drawn?.albums.isEmpty != false {
            // (slice 3) an empty playlist downloaded has no album: its row above says what is here
            if downloads.playlists.kept.isEmpty { NothingDownloadedNote() }
        } else {
            switch AlbumListBody.of(scope ?? .store, list: drawn?.albums, failed: failure != nil,
                                    found: drawn?.view.found.count ?? 0, typed: typed) {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .accessibilityLabel(LibraryWords.loading)
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    if let failure { ErrorNote(failure, retry: true) }
                    Button(LibraryWords.tryAgain) {
                        if online, let scope { Task { await library.load(scope) } } else { reachability.tryNow() }
                    }
                    .disabled(reachability.probing)
                }
                .padding(.top, 8)
            case .emptyLibrary:
                EmptyLibraryNote()
            case .noAlbums:
                ShelfNote(LibraryWords.noAlbums)
            case .noMatch(let words):
                ShelfNote(words)
            case .albums:
                if let drawn { albums(drawn, personal: personal, online: online) }
            }
        }
    }

    @ViewBuilder
    private func albums(_ drawn: DrawnShelf, personal: Bool, online: Bool) -> some View {
        let marks = library.marks
        let lines = list == .downloaded
        switch library.layout {
        case .grid:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.gap, alignment: .top),
                                GridItem(.flexible(), spacing: Self.gap, alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(drawn.groups) { group in
                    Section {
                        ForEach(group.albums) { album in
                            let download = downloads.album(id: album.id)
                            LibraryTile(album: album, isNew: personal && marks.isNew(album), download: download,
                                        line: lines ? line(album, download) : nil,
                                        dimmed: !online && !download.hasSongsHere) { open(album) }
                        }
                    } header: {
                        header(group)
                    }
                }
            }
        case .list:
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(drawn.groups) { group in
                    Section {
                        ForEach(group.albums) { album in
                            let download = downloads.album(id: album.id)
                            LibraryRow(album: album, isNew: personal && marks.isNew(album), download: download,
                                       line: lines ? line(album, download) : nil,
                                       dimmed: !online && !download.hasSongsHere) { open(album) }
                            Divider().padding(.leading, LibraryRow.textInset)
                        }
                    } header: {
                        header(group)
                    }
                }
            }
        }
    }

    /// Downloaded's third line (5.1): "12 songs", "3 of 12 songs", "Downloading", "Waiting", "Didn't download".
    private func line(_ album: IndexAlbum, _ download: AlbumDownload) -> String {
        let count = album.songCount ?? downloads.songIDs(album: album.id)?.count ?? 0
        return DownloadWords.tileLine(download, songCount: count) ?? ""
    }

    /// A group's header, in the flow (never pinned: Shelf.tsx) - what the index scrolls to.
    @ViewBuilder
    private func header(_ group: DrawnGroup) -> some View {
        if let label = group.label {
            LibraryHeader(label: label)
                .id(ShelfAnchor.group(group.id))
        }
    }

    // MARK: doing

    /// A tile's tap: its album's page, the New mark gone (MyLibraryState.opened - deadwax told).
    private func open(_ album: IndexAlbum) {
        library.opened(album)
        navigation.open(.album(AlbumRoute(album)))
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: ShelfAnchor, animated: Bool = false) {
        if animated {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(anchor, anchor: .top) }
        }
    }
}

/// What a screen scrolls to: its top, or a group's header by its place among the groups.
enum ShelfAnchor: Hashable {
    case top
    case group(Int)
}

/// The Albums screens' order (ALBUM_SORTS, the web's labels), one choice for both scopes, saved per device.
struct LibrarySortMenu: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        Menu {
            Picker(LibraryWords.sortLabel, selection: $library.sort) {
                ForEach(AlbumSort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(LibraryWords.sortLabel, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel(LibraryWords.sortLabel)
        .accessibilityValue(library.sort.label)
    }
}

/// Tiles or rows, per device (the phone's own: the web has only tiles).
struct LibraryLayoutSwitch: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Button {
            library.layout = library.layout == .grid ? .list : .grid
        } label: {
            Label(library.layout.switchLabel, systemImage: library.layout.switchSymbol)
        }
    }
}

/// The first ask (phase3-autodownload.md 3.2, open question 1): a card at the top of the Library's Downloaded (Phase 4,
/// slice 3b, question 17 - it was over the root's albums until the switch), once per phone, not a dialog at launch - the
/// app opens to music. Its title, its line with the storage limit, Turn On (the
/// accent) and Not Now; either answer puts it away for good (AutoDownload.askedKey). Not shown while downloads can't be
/// used, or with the switch already on. The setting is in You > Downloads either way.
struct FirstAskCard: View {
    @Environment(DownloadModel.self) private var downloads
    @AppStorage(AutoDownload.askedKey) private var asked = false

    var body: some View {
        if !asked, downloads.isOpen, !downloads.follower.on {
            let scope = downloads.libraryScope
            VStack(alignment: .leading, spacing: 10) {
                Text(AutoDownloadWords.askTitle(scope))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(AutoDownloadWords.askLine(scope, limit: downloads.storageLimit))
                    .font(.subheadline)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons }
                    VStack(alignment: .leading, spacing: 10) { buttons }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.toggledFill))
            .accessibilityElement(children: .contain)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(AutoDownloadWords.turnOn) {
            asked = true
            downloads.follower.on = true
        }
        .buttonStyle(PrimaryFace())
        Button(AutoDownloadWords.notNow) { asked = true }
            .buttonStyle(SecondaryPill())
    }
}

/// One group of places (app/LibraryHome.tsx's groups): a header and its rows - since slice 3b only the Navidrome gate's
/// On this phone, the switch and its ••• holding the rest.
struct PlaceGroup<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }
}

/// A place's row: the accent mark, its name, a count (albums, quiet), the chevron and the divider - a page pushed on
/// the tab's path (AppRoute), so the tab's tap pops it like any page.
struct PlaceRow: View {
    let symbol: String
    let label: String
    var count: Int?
    /// The count, spoken - albums, unless the place holds something else (slice 3's playlists).
    var counted: (Int) -> String = { (n: Int) -> String in Find.countText(n, one: "album", many: "albums") }
    let route: AppRoute
    var divider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: route) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(label)
                    Spacer(minLength: 8)
                    if let count {
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(Palette.quiet)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(count.map(counted) ?? "")
            if divider { Divider() }
        }
    }
}

/// Downloaded with nothing on it (5.1): what is empty and how to fill it, left aligned in the list's flow under the
/// title, as Your albums' empty note is.
private struct NothingDownloadedNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DownloadWords.nothingYet)
            Text(DownloadWords.nothingYetHow)
                .foregroundStyle(Palette.quiet)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }
}

/// The way to the store's albums - All music's row, and an empty library's See All music: the store's Albums screen
/// pushed on the tab's path (AppRoute.albums), so the tab's tap pops it like any page.
private struct StoreAlbumsLink<Content: View>: View {
    @ViewBuilder let label: () -> Content

    var body: some View {
        NavigationLink(value: AppRoute.albums(.store)) {
            label()
        }
    }
}

/// Your library empty (EmptyLibrary): what is empty, how to fill it, and See All music.
private struct EmptyLibraryNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LibraryWords.emptyLibrary)
            Text(LibraryWords.emptyLibraryHow)
                .foregroundStyle(Palette.quiet)
            StoreAlbumsLink {
                Text(LibraryWords.seeAllMusic)
            }
            .buttonStyle(.bordered)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }
}

/// A list that couldn't be asked again, drawn as it was (COULDNT_REFRESH), with the error and Try again.
private struct RefreshProblemNote: View {
    let failure: APIFailure
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LibraryWords.couldntRefresh)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            ErrorNote(failure, retry: true)
            Button(LibraryWords.tryAgain, action: retry)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One line in place of the albums ("No albums yet.", "No albums match “…”.").
private struct ShelfNote: View {
    let words: String

    init(_ words: String) {
        self.words = words
    }

    var body: some View {
        Text(words)
            .foregroundStyle(Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
}
