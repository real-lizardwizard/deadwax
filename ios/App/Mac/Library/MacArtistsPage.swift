import DeadwaxCore
import SwiftUI
import UIKit

/// Artists on the Mac (the redesign, slice R2 - Artists.dc.html; notes/ios.md "The redesign, slice R2: Albums and
/// Artists, and the Library's top"): a scope's artists - Your artists at the Library's root, the collection's from the
/// sidebar's All music - under the page's toolbar, as a column list or as tiles (LibraryModel.layout, the Albums
/// page's choice: one Grid | List for the Library on this Mac).
///
/// - The toolbar: Play, Shuffle, the groove, Sort and its pop-up (ArtistsModel.order, shared with the phone's page),
///   Grid | List, and Find in artists at its end.
/// - The list (MacColumnList): Artist (their round 20 pt picture and their name), Albums (Navidrome's count, as the
///   phone's row says it), and Songs, Plays and Last played - each summed from the scope's album index by Core's
///   ArtistTotals (its albums whose album artist is theirs), made once per answer, never in the body; nothing is asked
///   for them. A click selects, a double-click or Return opens their page. Last played's words are read against a
///   `now` set as the page shows and again at each day's change (R2's review), never once per cell.
/// - A selection is the list's alone (R2's review): choosing Grid lets it go.
/// - Play plays every album of theirs once their songs are in hand: asked once the selection has rested (200 ms), as
///   their page asks (ArtistPageModel), Play dimmed until they are settled - the tap calls the player with them,
///   nothing awaited. Only while deadwax can be reached.
/// - Shuffle and the status bar as the Albums page's: how many artists are listed, the index's albums under them (each
///   once - R2's review: the Albums column counts a split album under each of its artists, its Songs and Plays only
///   under the one whose artistId it has), and "1 selected".
///
/// Left out: "Navidrome up to date", which nothing can say yet; and a right-click, which an artist's row never had.
struct MacArtistsPage: View {
    let scope: AlbumScope

    @Environment(ArtistsModel.self) private var artists
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(Reachability.self) private var reachability
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(ShuffleModel.self) private var shuffles
    /// Find's words - the page's own.
    @State private var typed = ""
    /// The row selected, by artist id - in List alone.
    @State private var selected: String?
    /// The selected artist's albums and their songs, asked as they are selected: Play's.
    @State private var chosen: ArtistPageModel?
    /// Each artist's totals over the scope's album index (ArtistTotals), made once per answer.
    @State private var totals: [String: ArtistTotal] = [:]
    /// (R2's review) Now, for Last played's words: read as the page shows and again at each day's change - and a
    /// clock's or a time zone's (UIKit's significant time change) - so a list left open overnight never says "today" of
    /// yesterday's plays.
    @State private var now = ArtistTotals.now()

    /// How long the selection rests before its artist is asked for: 200 ms.
    private static let rest: UInt64 = 200_000_000

    /// The columns: Artist takes what the others leave (Artists.dc.html's widths).
    private static let columns = [
        MacListColumn(title: LibraryColumnWords.artist, width: .flexible),
        MacListColumn(title: LibraryColumnWords.albums, width: .fixed(76)),
        MacListColumn(title: LibraryColumnWords.songs, width: .fixed(76)),
        MacListColumn(title: LibraryColumnWords.plays, width: .fixed(70)),
        MacListColumn(title: LibraryColumnWords.lastPlayed, width: .fixed(124)),
    ]

    /// What the artists are asked again on: who is signed in, deadwax in reach, and the scope's generation.
    private struct AskKey: Equatable {
        let person: Int
        let online: Bool
        let generation: Int
    }

    /// What the selected artist is asked on: who, which artist, and deadwax in reach.
    private struct ChosenKey: Equatable {
        let person: Int
        let selected: String?
        let online: Bool
    }

    /// Their own artists - Your artists - with a library of your own on your scope.
    private var yours: Bool { server.access.hasLibrary && scope == .yours }

    var body: some View {
        let rows = self.rows
        MacPage {
            tools
        } content: {
            if library.layout == .list {
                // no right-click: an artist's row had none before R2, and their page's ••• is its own
                MacColumnList(columns: Self.columns, rows: rows, selected: $selected,
                              open: { (artist: Artist) -> Void in open(artist) },
                              menu: { (_: Artist) -> EmptyModifier in EmptyModifier() }
                ) { (artist: Artist, column: Int) in
                    cell(artist, column, now: now)
                }
            } else {
                tiles(rows)
            }
        }
        .macStatus(MacStatusItems.Items(leading: status(rows)))
        .macSelects(selectedArtist(rows).map { (artist: Artist) -> MacSelection.Subject in .artist(ArtistRoute(artist)) })
        .task(id: AskKey(person: server.person, online: reachability.online,
                         generation: library.generations[scope] ?? 0)) {
            guard reachability.online else { return }
            // the artists, and the scope's albums the totals are summed from (the phone's Your artists asks both too)
            let artists = self.artists
            let library = self.library
            let scope = self.scope
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await artists.ask() }
                group.addTask { await library.load(scope) }
            }
        }
        .task(id: ArtistTotalsKey(scope: scope, serial: library.shelves[scope]?.serial)) {
            totals = ArtistTotals.of(library.albums(scope)?.albums ?? [])
        }
        .task(id: ChosenKey(person: server.person, selected: selected, online: reachability.online)) {
            // (R2's review) asked once the selection has rested: ↑ and ↓ passing rows ask for none of them
            if selected != nil {
                try? await Task.sleep(nanoseconds: Self.rest)
                guard !Task.isCancelled else { return }
            }
            await choose(selectedArtist(self.rows))
        }
        .onChange(of: library.layout) { (_: LibraryLayout, layout: LibraryLayout) -> Void in
            // (R2's review) Grid shows no selection: none is kept unseen for Info, the status bar or Play
            if layout != .list { selected = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear {
            now = ArtistTotals.now()
            if reachability.online { shuffles.shown(shuffleOf, library.scope) }
        }
    }

    // MARK: the toolbar

    @ViewBuilder private var tools: some View {
        @Bindable var artists = artists
        @Bindable var library = library
        Button(action: play) {
            HStack(spacing: 6) {
                SharpSymbol(.play)
                Text(PlaylistWords.play)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri))
        .disabled(!playable)
        .help(playable ? "" : LibraryColumnWords.playHelp(list: library.layout == .list, selected: selected != nil,
                                                          artist: true))
        Button(ShuffleWords.shuffle, action: shuffle)
            .buttonStyle(DWButtonStyle())
            .disabled(!shuffleCan.starts)
        MacGroove()
        Text(LibraryColumnWords.sort)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t2)
            .accessibilityHidden(true)
        DWPopUp(words: artists.order.label) {
            Picker(ArtistWords.sortLabel, selection: $artists.order) {
                ForEach(ArtistOrder.allCases, id: \.self) { (order: ArtistOrder) in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        }
        .accessibilityLabel(ArtistWords.sortLabel)
        .accessibilityValue(artists.order.label)
        DWSegmented(options: LibraryLayout.allCases,
                    words: { (layout: LibraryLayout) -> String in
                        layout == .grid ? LibrarySwitchWords.grid : LibrarySwitchWords.list
                    },
                    chosen: $library.layout, spoken: LibraryColumnWords.layout, large: true)
        Spacer(minLength: 0)
        DWField(prompt: ArtistWords.findPlaceholder, text: $typed)
            .frame(width: 230)
    }

    // MARK: the list

    /// The artists drawn: Your artists or the collection's, in the order chosen, found by Find's words - or, offline
    /// with none in hand, those with albums on this Mac.
    private var drawn: DrawnArtists? {
        if artists.list != nil {
            if !yours { return artists.drawnAll(typed: typed) }
            if let mine = artists.drawnYours(library.shelves[.yours], typed: typed) { return mine }
        }
        return reachability.online ? nil : artists.drawnHere(downloads.downloadedAlbums, typed: typed)
    }

    /// The artists listed - the groups' runs one after another.
    private var rows: [Artist] {
        drawn?.groups.flatMap { (group: DrawnArtistGroup) -> [Artist] in group.artists } ?? []
    }

    /// The artist selected - in List alone: Grid shows none (R2's review).
    private func selectedArtist(_ rows: [Artist]) -> Artist? {
        guard library.layout == .list, let selected else { return nil }
        return rows.first { (artist: Artist) -> Bool in artist.id == selected }
    }

    @ViewBuilder
    private func cell(_ artist: Artist, _ column: Int, now: Int64) -> some View {
        let total = totals[artist.id]
        switch column {
        case 0:
            HStack(spacing: 8) {
                ArtistPicture(id: artist.coverArt, side: 20, pixels: CoverSize.row)
                    .accessibilityHidden(true)
                Text(artist.name ?? "")
            }
        case 1:
            Text(ArtistTotals.number(artist.albumCount))
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case 2:
            Text(total.map { (total: ArtistTotal) -> String in ArtistTotals.number(total.songs) } ?? "")
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case 3:
            Text(ArtistTotals.plays(total?.plays ?? 0))
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        default:
            Text(ArtistTotals.lastPlayedWords(total?.lastPlayed, now: now))
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
        }
    }

    /// Grid: each artist's picture and name, MacFrame.tileMin wide at least - a click opens their page.
    private func tiles(_ rows: [Artist]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(MacFrame.tileMin)), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(rows) { (artist: Artist) in
                    Button {
                        open(artist)
                    } label: {
                        VStack(spacing: 7) {
                            ArtistPicture(id: artist.coverArt, side: CGFloat(MacFrame.tileMin), pixels: CoverSize.tile)
                            Text(artist.name ?? "")
                                .font(Typeface.Mac.text(.base).weight(.semibold))
                                .foregroundStyle(DWPalette.head)
                                .lineLimit(1)
                            Text(ArtistTotals.rowLine(albums: artist.albumCount, songs: totals[artist.id]?.songs))
                                .font(Typeface.Mac.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(artist.name ?? "")
                }
            }
            .padding(16)
        }
    }

    /// The status bar's facts: the artists listed and their albums - (R2's review) the index's albums under them, each
    /// once, never the Albums column summed - and the selection.
    private func status(_ rows: [Artist]) -> [String] {
        let listed = Set(rows.map { (artist: Artist) -> String in artist.id })
        let albums = ArtistTotals.albumCount(of: listed, in: library.albums(scope)?.albums ?? [])
        var items = [ArtistTotals.artists(rows.count), ArtistTotals.albums(albums)]
        if selectedArtist(rows) != nil { items.append(ArtistTotals.oneSelected) }
        return items
    }

    // MARK: doing

    /// An artist opened (a double-click, Return, a tile's click): their page.
    private func open(_ artist: Artist) {
        navigation.open(.artist(ArtistRoute(artist)))
    }

    /// The selected artist asked for, as their page asks - their albums' songs Play's once settled; none with nothing
    /// selected.
    private func choose(_ artist: Artist?) async {
        guard let artist else {
            chosen = nil
            return
        }
        let model: ArtistPageModel
        if let chosen, chosen.route.id == artist.id {
            model = chosen
        } else {
            model = ArtistPageModel(route: ArtistRoute(artist))
        }
        chosen = model
        await model.load(key: "\(server.person)|\(artist.id)", client: server.client, online: reachability.online,
                         artists: artists)
    }

    /// Play can: the selected artist's albums all asked, some with songs in hand, deadwax in reach - never in Grid,
    /// where nothing is selected (R2's review).
    private var playable: Bool {
        guard reachability.online, library.layout == .list, let chosen, chosen.route.id == selected else { return false }
        return chosen.asks.playable
    }

    /// Play: every album of theirs in hand, in their page's order, in the tap - nothing awaited.
    private func play() {
        guard playable, let chosen else { return }
        player.play(artist: chosen.asks.answers, shuffle: false)
    }

    /// Whose Shuffle: the Library's, or the collection's (All songs') for the collection's artists with a library of
    /// your own.
    private var shuffleOf: ShuffleOf { scope == library.scope ? .library : .allSongs }

    private var shuffleCan: ShuffleCan {
        let online = reachability.online
        return ShuffleCan.of(online: online, ready: shuffles.ready(shuffleOf), empty: shuffles.empty(shuffleOf),
                             failed: shuffles.failure(shuffleOf), songsHere: online ? 0 : downloads.songsHere.count)
    }

    /// Shuffle, in the tap: the first page in hand - or, offline, every song on this Mac.
    private func shuffle() {
        switch shuffleCan {
        case .ready:
            guard let taken = shuffles.take(shuffleOf, level: PlaylistPlay.songsLevel(player.normalization)) else { return }
            player.play(shuffled: taken)
        case .downloads:
            let here = downloads.songsHere
            guard !here.isEmpty else { return }
            player.play(playlist: here, at: nil, shuffle: true)
        case .gettingReady, .failed, .nothingHere, .none:
            break
        }
    }
}

/// The Library's root on the Mac (R2): Albums and Artists as the Mac's own pages, in the person's scope - what
/// LibraryView draws in the pager's place for them (MacLibrary.root()). (R5) And Playlists, the Mac's own list.
struct MacLibraryDesk: View {
    let page: LibraryPage
    let scope: AlbumScope

    var body: some View {
        switch page {
        case .artists:
            MacArtistsPage(scope: scope)
        case .playlists:
            MacPlaylistsPage()
        default:
            MacAlbumsPage(scope: scope)
        }
    }
}
