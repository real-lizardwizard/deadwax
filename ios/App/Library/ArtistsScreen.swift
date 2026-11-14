import DeadwaxCore
import SwiftUI

/// One Artists screen (Phase 4, slice 4 - phase4-library.md 2.6, 3.1; the web's LibrarySection.tsx ArtistSection): every
/// artist of a list - Your artists (with a library of your own: the artists of your albums, counting yours), All artists
/// (the collection's), or Artists without a library of your own - in the order chosen (Name, Most albums), under Name's
/// letters, Find in place, the index down the edge for a long list. A row is the artist's round picture, their name and
/// how many albums of theirs ("2 albums in the collection" on All artists with a library of your own, the count alone
/// inside your own list), and opens their page - nothing here plays but the pull. Rows, as the web's (its Shelf's
/// `list`): the Albums page's tiles or rows is the albums'. Every rule and word is Core's (ArtistShelf, YourArtists,
/// ArtistWords, Find); ArtistsModel makes what is drawn once per list, order and Find.
///
/// Two ways it is drawn, as AlbumsScreen is. As the Library's Artists page (`page`), under the switch: the person's scope
/// (Your artists, or Artists), the switch's Find, bar and ••• (the order is the •••'s, question 26), and a pull that
/// shuffles (3.5), never refreshes. Pushed on the tab's path (All music's All artists, AppRoute.artists): its own title,
/// Find and order, and pull to refresh.
///
/// The list is asked as the screen shows and each time it shows again (the page the switch shows, the app back in front
/// on it, a page over it gone) - as the web's - and Your artists' albums with it (LibraryModel's, kept and shared); drawn
/// meanwhile from what is in hand. A failure with a list in hand leaves the list and says so at the top; with none,
/// why, and Try again - Your artists' albums failing among them (ArtistsWaiting). Choosing an order or typing into Find goes back to the top; tapping the Library tab again scrolls
/// the page shown to its top.
///
/// While deadwax can't be reached (3.1's rule) nothing is asked: the list in hand draws, an artist with nothing on this
/// phone dimmed (it opens nothing); with no list in hand, the artists of the albums on this phone stand in, under
/// ArtistWords.offlineList. A pushed list's pull asks whether deadwax is back.
struct ArtistsScreen: View {
    /// The Library's Artists page: what the switch hands it.
    struct Page {
        /// Find's words - the switch's field, this page's own text in it.
        let typed: Binding<String>
        /// The page the switch shows.
        let current: Bool
        let pulling: PullShuffling
    }

    /// The list's scope pushed; nil for the Library's page, whose scope is the person's (LibraryModel.scope).
    let scope: AlbumScope?
    let page: Page?

    /// An artists list pushed (All music's All artists).
    init(scope: AlbumScope) {
        self.scope = scope
        page = nil
    }

    /// The Library's Artists page.
    init(page: Page) {
        scope = nil
        self.page = page
    }

    @Environment(ArtistsModel.self) private var artists
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(\.scenePhase) private var scenePhase
    /// What is typed into a pushed screen's Find - the screen's own: leaving it clears it.
    @State private var ownTyped = ""
    /// On screen (not covered by a page pushed over it).
    @State private var shown = false

    private static let edge: CGFloat = 16

    /// What the screen's ask is keyed on: a new person, deadwax back, the page shown again, your albums' generation.
    private struct AskKey: Equatable {
        let person: Int
        let online: Bool
        let current: Bool
        let generation: Int
    }

    private var shownScope: AlbumScope { scope ?? library.scope }
    /// The list is Your artists: a library of your own, and its scope.
    private var yours: Bool { server.access.hasLibrary && shownScope == .yours }
    private var typed: String { page?.typed.wrappedValue ?? ownTyped }
    private var current: Bool { page?.current ?? true }

    var body: some View {
        let personal = server.access.hasLibrary
        Group {
            if let page {
                shelf(personal: personal, page: page)
            } else {
                shelf(personal: personal, page: nil)
                    .navigationTitle(ArtistWords.title(shownScope, personal: personal))
                    .searchable(text: $ownTyped, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: Text(ArtistWords.findPlaceholder))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ArtistOrderMenu()
                        }
                    }
                    .refreshable { await pulled() }
            }
        }
        .task(id: AskKey(person: server.person, online: reachability.online, current: current,
                         generation: yours ? library.generations[.yours] ?? 0 : 0)) {
            // shown (and shown again): asked afresh - nothing while deadwax can't be reached
            guard reachability.online, current else { return }
            await ask()
        }
        .onChange(of: scenePhase) { _, phase in
            // the app back in front is the screen shown again (the web's): asked afresh
            guard phase == .active, shown, current, reachability.online else { return }
            Task { await ask() }
        }
        .onAppear {
            shown = true
            if yours, reachability.online { library.refreshIfOld(.yours) }
        }
        .onDisappear { shown = false }
    }

    /// The artists asked - and, for Your artists, your albums with them (the web's Promise.all of the two).
    private func ask() async {
        let artists = self.artists
        guard yours else {
            await artists.ask()
            return
        }
        let library = self.library
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await artists.ask() }
            group.addTask { await library.load(.yours) }
        }
    }

    /// A pushed list's pull: asked again now - or, while deadwax can't be reached, whether it is back.
    private func pulled() async {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        await ask()
    }

    /// The list drawn: Your artists or the collection's, from what is in hand - or, offline with none, the artists of
    /// the albums on this phone.
    private func drawn(online: Bool) -> DrawnArtists? {
        if artists.list != nil {
            if !yours { return artists.drawnAll(typed: typed) }
            if let mine = artists.drawnYours(library.shelves[.yours], typed: typed) { return mine }
        }
        return online ? nil : artists.drawnHere(downloads.downloadedAlbums, typed: typed)
    }

    /// The artists with something of theirs on this phone (an album naming them as album artist with a song here) -
    /// read only while deadwax can't be reached, so a download coming in doesn't redraw the list online.
    private func artistsHere() -> Set<String> {
        var here = Set<String>()
        for album in downloads.downloadedAlbums {
            guard let id = album.artistId, downloads.album(id: album.id).hasSongsHere else { continue }
            here.insert(id)
        }
        return here
    }

    @ViewBuilder
    private func shelf(personal: Bool, page: Page?) -> some View {
        let online = reachability.online
        let drawn = self.drawn(online: online)
        let entries = drawn?.view.index ?? []

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                        .overlay(alignment: .bottom) {
                            // the pull's graphic, in the room the pull opens above the first row (3.5)
                            if let page {
                                PullShuffleGraphic(state: page.pulling.state, can: page.pulling.can)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    content(drawn, personal: personal, online: online)
                }
                .padding(.leading, Self.edge)
                .padding(.trailing, entries.isEmpty ? Self.edge : ShelfIndexStrip.width(years: false) + 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(entries.isEmpty ? .automatic : .hidden)
            .pullsToShuffle(page?.pulling)
            .overlay(alignment: .trailing) {
                if !entries.isEmpty {
                    ShelfIndexStrip(entries: entries, years: false) { (group: Int) -> Void in
                        jump(proxy, to: .group(group))
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .onChange(of: typed) { _, _ in jump(proxy, to: .top) }
            .onChange(of: artists.order) { _, _ in jump(proxy, to: .top) }
            .onChange(of: navigation.libraryScrollToTop) { _, _ in
                // the Library tab tapped at its root: the page shown goes to its top
                guard shown, page?.current == true else { return }
                jump(proxy, to: .top, animated: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ drawn: DrawnArtists?, personal: Bool, online: Bool) -> some View {
        if let drawn {
            if drawn.standIn {
                Text(ArtistWords.offlineList)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else if !drawn.artists.isEmpty, !drawn.view.countText.isEmpty {
                Text(drawn.view.countText)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            if online, let failure = artists.failure {
                RefreshProblemNote(failure: failure) { Task { await ask() } }
                    .padding(.vertical, 8)
            }
            if drawn.artists.isEmpty {
                if drawn.standIn {
                    EmptyView()
                } else if yours {
                    EmptyLibraryNote(lead: ArtistWords.noArtistsOfYours)
                } else {
                    ShelfNote(ArtistWords.noArtists)
                }
            } else if drawn.view.found.isEmpty {
                ShelfNote(ArtistWords.noMatch(typed))
            } else {
                rows(drawn, personal: personal, online: online)
            }
        } else if let failure = ArtistsWaiting.failure(artists: artists.failure, yourAlbums: library.failures[.yours],
                                                       yours: yours) {
            // nothing to draw and an ask failed - the artists', or (Your artists) your albums': a first sign-in's
            // failed album index would otherwise leave the spinner for ever, the pull shuffling
            VStack(alignment: .leading, spacing: 10) {
                ErrorNote(failure, retry: true)
                Button(LibraryWords.tryAgain) {
                    if reachability.online { Task { await ask() } } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
            .padding(.top, 8)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .accessibilityLabel(LibraryWords.loading)
        }
    }

    @ViewBuilder
    private func rows(_ drawn: DrawnArtists, personal: Bool, online: Bool) -> some View {
        let place = ArtistWords.countPlace(shownScope, personal: personal)
        let here: Set<String>? = online ? nil : artistsHere()
        ForEach(drawn.groups) { (group: DrawnArtistGroup) in
            if let label = group.label {
                LibraryHeader(label: label)
                    .id(ShelfAnchor.group(group.id))
            } else {
                Color.clear
                    .frame(height: 0)
                    .id(ShelfAnchor.group(group.id))
            }
            ForEach(group.artists) { (artist: Artist) in
                ArtistRow(artist: artist, line: ArtistWords.albumCountLine(artist.albumCount, place: place),
                          dimmed: here.map { (ids: Set<String>) -> Bool in !ids.contains(artist.id) } ?? false)
            }
        }
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

/// One artist's row (LibraryViews.tsx ArtistRow): their round picture at the rows' size, their name and how many albums
/// of theirs, and the chevron - their page pushed on the tab's path. Read as one: "Portishead, 2 albums". Dimmed, and
/// opening nothing, while deadwax can't be reached and nothing of theirs is on this phone.
struct ArtistRow: View {
    let artist: Artist
    let line: String
    var dimmed = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: AppRoute.artist(ArtistRoute(artist))) {
                HStack(spacing: 12) {
                    ArtistPicture(id: artist.coverArt, side: LibraryRow.cover, pixels: CoverSize.row)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name ?? "")
                            .foregroundStyle(.primary)
                        if !line.isEmpty {
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .opacity(dimmed ? Palette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([artist.name ?? "", line].filter { (part: String) -> Bool in !part.isEmpty }
                .joined(separator: ", "))
            .accessibilityValue(dimmed ? DownloadWords.notOnPhone : "")
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }
}

/// An artist's picture, round: Navidrome's artist image (the `artist.*` deadwax writes) at exactly `pixels`
/// (LibraryCover), or - for an artist with none - the person mark on the empty cover's circle.
struct ArtistPicture: View {
    let id: String?
    let side: CGFloat
    let pixels: Int

    var body: some View {
        Group {
            if let id {
                LibraryCover(id: id, pixels: pixels)
            } else {
                ZStack {
                    Palette.coverEmpty
                    Image(systemName: "person.fill")
                        .font(.system(size: side * 0.42, weight: .regular))
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The artist order (ARTIST_ORDERS, the web's labels), saved per device - a pushed list's bar's, as LibrarySortMenu is
/// the albums'. On the Library's page it is the •••'s (question 26).
struct ArtistOrderMenu: View {
    @Environment(ArtistsModel.self) private var artists

    var body: some View {
        @Bindable var artists = artists
        Menu {
            Picker(ArtistWords.sortLabel, selection: $artists.order) {
                ForEach(ArtistOrder.allCases, id: \.self) { (order: ArtistOrder) in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(ArtistWords.sortLabel, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel(ArtistWords.sortLabel)
        .accessibilityValue(artists.order.label)
    }
}
