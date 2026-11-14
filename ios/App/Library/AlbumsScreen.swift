import DeadwaxCore
import SwiftUI

/// One Albums screen (app/LibrarySection.tsx AlbumSection, D2): every album of a list - yours, the store's, or what is
/// on this phone (Downloaded, phase2-downloads.md 5.1) - in the order chosen, under its headers, as tiles or rows; Find
/// in place; the index down the edge; the New marks, and each album's download mark. What it draws is Core's: the body
/// by AlbumListBody, the order, headers, Find, count and index by Shelf.view (through LibraryModel.drawn, made once per
/// list, sort and Find), the words LibraryWords' and DownloadWords'.
///
/// A scope's list is the model's, shared by every screen of the scope and kept on disk; this screen asks for it as it
/// shows and again whenever its generation moves (an Add or a Remove, the starred count, older than a minute), pull
/// to refresh asks now. A list asked again swaps in where the old one was - never emptied, the scroll kept.
/// Downloaded is never asked of deadwax: it is DownloadModel's albums, its Recently added the moment each arrived.
/// Choosing a sort or typing into Find goes back to the top. Tapping the Library tab again scrolls the root to its
/// top; the other lists are pages of the tab's own (AppRoute.albums, .downloaded), so the tab's tap pops them with
/// whatever album is over them. Nothing here plays (the gesture rule): a tile opens its album.
///
/// While deadwax can't be reached (5.4) an album with nothing on this phone is dimmed and opens nothing, a list that
/// couldn't be asked again says nothing of it (the banner says it once for every page), and a pull asks whether deadwax
/// is back.
struct AlbumsScreen: View {
    let list: AlbumList
    /// The tab's root - the places above its albums (All music, On this phone), and the tab's tap scrolls it to the top.
    let root: Bool

    init(scope: AlbumScope, root: Bool) {
        self.init(list: .scope(scope), root: root)
    }

    init(list: AlbumList, root: Bool) {
        self.list = list
        self.root = root
    }

    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    /// What is typed into Find - the screen's own: leaving it clears it.
    @State private var typed = ""
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

    var body: some View {
        let personal = server.access.hasLibrary
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
                    if root && !finding {
                        places(personal: personal, online: online, hasAlbums: drawn?.albums.isEmpty == false)
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
                // the Library tab tapped at its root: the root list goes to its top
                guard shown, root else { return }
                jump(proxy, to: .top, animated: true)
            }
        }
        .navigationTitle(title(personal: personal))
        .searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always),
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
        .task(id: LoadKey(person: server.person, generation: scope.map { library.generations[$0] ?? 0 } ?? 0)) {
            guard let scope else { return }
            await library.load(scope)
        }
        // a ring moves only while it shows: the root stays in the tab's stack under its pages
        .task(id: shown) {
            guard shown else { return }
            await downloads.followProgress()
        }
        .onAppear {
            shown = true
            if let scope, online { library.refreshIfOld(scope) }
        }
        .onDisappear { shown = false }
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

    /// A pull: the list asked again now - or, while deadwax can't be reached, whether it is back (a probe at once).
    private func pulled() async {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        guard let scope else { return }
        await library.refresh(scope)
    }

    // MARK: the places above the root's albums (5.2, 5.4)

    @ViewBuilder
    private func places(personal: Bool, online: Bool, hasAlbums: Bool) -> some View {
        switch list {
        case .scope(let scope):
            // the first ask (phase3-autodownload.md 3.2): once deadwax answered with albums to download
            if hasAlbums && online {
                FirstAskCard()
            }
            if scope == .yours && personal {
                PlaceGroup(title: LibraryWords.allMusic) {
                    PlaceRow(symbol: "square.stack", label: LibraryWords.allAlbums, route: .albums(.store))
                }
            }
            if !downloads.records.isEmpty {
                PlaceGroup(title: DownloadWords.onThisPhone) {
                    PlaceRow(symbol: DownloadWords.downloadSymbol, label: DownloadWords.downloadedTitle,
                             count: downloads.albumCount, route: .downloaded)
                }
            }
        case .downloaded:
            // the root is Downloaded (deadwax couldn't be reached as it was last shown): the way back to the albums
            VStack(alignment: .leading, spacing: 0) {
                // named as the page it opens is titled: "Your albums", or "Albums" without a library of your own
                PlaceRow(symbol: "square.stack", label: LibraryWords.title(library.scope, personal: personal),
                         route: .albums(library.scope), divider: online)
                if !online {
                    Text(DownloadWords.onlyDownloadedPlay)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                    Divider()
                }
            }
        }
    }

    // MARK: the body (AlbumListBody)

    @ViewBuilder
    private func content(_ drawn: DrawnShelf?, failure: APIFailure?, personal: Bool, online: Bool) -> some View {
        if list == .downloaded, drawn?.albums.isEmpty != false {
            NothingDownloadedNote()
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
private struct LibrarySortMenu: View {
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
private struct LibraryLayoutSwitch: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Button {
            library.layout = library.layout == .grid ? .list : .grid
        } label: {
            Label(library.layout.switchLabel, systemImage: library.layout.switchSymbol)
        }
    }
}

/// One group of the root's places (app/LibraryHome.tsx's groups): All music with a library of your own, On this phone
/// once anything is downloaded, on its way or failed (5.2) - each a header and its rows, so the groups read as one list
/// of places, as Apple Music's Library lists Downloaded among its own.
/// The first ask (phase3-autodownload.md 3.2, open question 1): a card at the top of the Library's root, once per
/// phone, not a dialog at launch - the app opens to music. Its title, its line with the storage limit, Turn On (the
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
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(AutoDownloadWords.turnOn) {
            asked = true
            downloads.follower.on = true
        }
        .buttonStyle(.borderedProminent)
        Button(AutoDownloadWords.notNow) { asked = true }
            .buttonStyle(.bordered)
    }
}

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
            .accessibilityValue(count.map { Find.countText($0, one: "album", many: "albums") } ?? "")
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
