import DeadwaxCore
import SwiftUI

/// Albums on the Mac (the redesign, slice R2 - Albums.dc.html; notes/ios.md "The redesign, slice R2: Albums and
/// Artists, and the Library's top"): a scope's albums - Your albums at the Library's root, the collection's from the
/// sidebar's All music - under the page's toolbar, as a column list or as tiles (LibraryModel.layout, kept on this Mac).
///
/// - The toolbar (.bar): Play, Shuffle, the groove, Sort and its pop-up (LibraryModel.sort, shared with the phone's
///   page), Grid | List, and Find in albums at its end, 230 wide.
/// - The list (MacColumnList): Album (its 20 pt cover, its title, the New mark and - the album playing - the accent's
///   ▶), Artist (with the album's download mark, as the rows before R2 had it), Year and Songs - the album index's own
///   facts, nothing asked for them. A click selects, a double-click or Return opens the album's page; a right-click is
///   the album page's •••'s items (AlbumRightClick), as the tiles' is.
/// - A selection is the list's alone (R2's review): Grid shows none, so choosing Grid lets it go - nothing unseen is
///   Info's, the status bar's or Play's.
/// - Play plays the album selected once its songs are in hand: they are asked once the selection has rested (200 ms -
///   ↑ and ↓ passing rows ask for none of them), as its page asks (AlbumModel), and Play is dimmed until they come - the
///   tap calls the player with them, nothing awaited. The album's levels wanted as they come (PlayerModel.albumShown)
///   are let go as the selection leaves it (albumLeft), as its page's are when it goes.
/// - Shuffle is the scope's Library Shuffle (ShuffleModel - the collection's All songs' with a library of your own),
///   its first page asked ahead as the page shows.
/// - The status bar: how many albums and songs are listed, and "1 selected"; the selection is Info's (MacSelection).
/// - While deadwax can't be reached, an album with nothing on this Mac is dimmed and opens nothing, as the phone's.
///
/// Left out, as the build plan's R2 says nothing can draw them yet: the Format column and the library's size (the album
/// index carries neither), and "Navidrome up to date".
struct MacAlbumsPage: View {
    let scope: AlbumScope

    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(Reachability.self) private var reachability
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(ShuffleModel.self) private var shuffles
    /// Find's words - the page's own.
    @State private var typed = ""
    /// The row selected, by album id - in List alone.
    @State private var selected: String?
    /// The selected album's answer, asked once the selection rests: Play's songs.
    @State private var chosen: AlbumModel?

    /// How long the selection rests before its album is asked for: 200 ms.
    private static let rest: UInt64 = 200_000_000

    /// The columns: Album takes what the others leave (Albums.dc.html's widths).
    private static let columns = [
        MacListColumn(title: LibraryColumnWords.album, width: .flexible),
        MacListColumn(title: LibraryColumnWords.artist, width: .fixed(150)),
        MacListColumn(title: LibraryColumnWords.year, width: .fixed(54)),
        MacListColumn(title: LibraryColumnWords.songs, width: .fixed(58)),
    ]

    /// What the album list is asked again on: who is signed in, and the scope's generation.
    private struct LoadKey: Equatable {
        let person: Int
        let generation: Int
    }

    /// What the selected album is asked on: who, which album, and deadwax in reach.
    private struct ChosenKey: Equatable {
        let person: Int
        let selected: String?
        let online: Bool
    }

    var body: some View {
        let rows = self.rows
        // (R2's review) the album playing, read once for every row: the player's song's album
        let playing = player.current?.track.albumId
        MacPage {
            tools
        } content: {
            if library.layout == .list {
                MacColumnList(columns: Self.columns, rows: rows, selected: $selected,
                              open: { (album: IndexAlbum) -> Void in open(album) },
                              menu: { (album: IndexAlbum) -> AlbumRightClick in AlbumRightClick(route: AlbumRoute(album)) }
                ) { (album: IndexAlbum, column: Int) in
                    cell(album, column, playing: playing)
                }
            } else {
                tiles(rows)
            }
        }
        .macStatus(MacStatusItems.Items(leading: status(rows)))
        .macSelects(selectedAlbum(rows).map { (album: IndexAlbum) -> MacSelection.Subject in .album(AlbumRoute(album)) })
        .task(id: LoadKey(person: server.person, generation: library.generations[scope] ?? 0)) {
            await library.load(scope)
        }
        .task(id: ChosenKey(person: server.person, selected: selected, online: reachability.online)) {
            // (R2's review) asked once the selection has rested: ↑ and ↓ passing rows ask for none of them
            if selected != nil {
                try? await Task.sleep(nanoseconds: Self.rest)
                guard !Task.isCancelled else { return }
            }
            await choose(selectedAlbum(self.rows))
        }
        .onChange(of: library.layout) { (_: LibraryLayout, now: LibraryLayout) -> Void in
            // (R2's review) Grid shows no selection: none is kept unseen for Info, the status bar or Play
            if now != .list { selected = nil }
        }
        .onAppear {
            if reachability.online {
                library.refreshIfOld(scope)
                shuffles.shown(shuffleOf, library.scope)
            }
            // shown again (a page over it gone): the selected album's levels wanted again, as its page's are
            if let album = chosen?.album { player.albumShown(album) }
        }
        .onDisappear {
            if let chosen { player.albumLeft(id: chosen.route.id) }
        }
    }

    // MARK: the toolbar

    @ViewBuilder private var tools: some View {
        @Bindable var library = library
        let songs = playable
        Button(action: play) {
            HStack(spacing: 6) {
                SharpSymbol(.play)
                Text(PlaylistWords.play)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri))
        .disabled(songs.isEmpty)
        .help(songs.isEmpty ? LibraryColumnWords.playHelp(list: library.layout == .list, selected: selected != nil,
                                                           artist: false) : "")
        Button(ShuffleWords.shuffle, action: shuffle)
            .buttonStyle(DWButtonStyle())
            .disabled(!shuffleCan.starts)
        MacGroove()
        Text(LibraryColumnWords.sort)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t2)
            .accessibilityHidden(true)
        DWPopUp(words: library.sort.label) {
            Picker(LibraryWords.sortLabel, selection: $library.sort) {
                ForEach(AlbumSort.allCases, id: \.self) { (sort: AlbumSort) in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.inline)
        }
        .accessibilityLabel(LibraryWords.sortLabel)
        .accessibilityValue(library.sort.label)
        DWSegmented(options: LibraryLayout.allCases,
                    words: { (layout: LibraryLayout) -> String in
                        layout == .grid ? LibrarySwitchWords.grid : LibrarySwitchWords.list
                    },
                    chosen: $library.layout, spoken: LibraryColumnWords.layout, large: true)
        Spacer(minLength: 0)
        DWField(prompt: LibraryWords.findPlaceholder, text: $typed)
            .frame(width: 230)
    }

    // MARK: the list

    /// The albums listed: the scope's, in the sort chosen, found by Find's words - the groups' runs one after another.
    private var rows: [IndexAlbum] {
        library.drawn(scope, typed: typed)?.groups.flatMap { (group: DrawnGroup) -> [IndexAlbum] in group.albums } ?? []
    }

    /// The album selected - in List alone: Grid shows none (R2's review).
    private func selectedAlbum(_ rows: [IndexAlbum]) -> IndexAlbum? {
        guard library.layout == .list, let selected else { return nil }
        return rows.first { (album: IndexAlbum) -> Bool in album.id == selected }
    }

    /// While deadwax can't be reached, an album with nothing on this Mac: dimmed, opening nothing.
    private func notHere(_ download: AlbumDownload) -> Bool {
        !reachability.online && !download.hasSongsHere
    }

    @ViewBuilder
    private func cell(_ album: IndexAlbum, _ column: Int, playing: String?) -> some View {
        let download = downloads.album(id: album.id)
        Group {
            switch column {
            case 0:
                HStack(spacing: 8) {
                    LibraryCover(id: album.coverArt, pixels: CoverSize.row)
                        .frame(width: 20, height: 20)
                        .clipShape(DWCorners.chipShape)
                        .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text(album.name ?? "")
                    // (R2's review) the album playing (Albums.dc.html's a.playing): the accent's ▶, read from the
                    // player, never a play
                    if playing == album.id {
                        SharpSymbol(.play)
                            .foregroundStyle(DWPalette.acc)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(LibraryColumnWords.playing)
                    }
                    if server.access.hasLibrary && library.marks.isNew(album) { LibraryNewMark() }
                }
            case 1:
                HStack(spacing: 4) {
                    Text(album.artist ?? "")
                    // the download mark at the artist's end, as the rows before R2 had it
                    if let mark = DownloadWords.mark(download) {
                        DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download),
                                     font: Typeface.symbol(.caption2))
                            .fixedSize()
                    }
                }
                .foregroundStyle(DWPalette.t2)
            case 2:
                Text(album.year.map { (year: Int) -> String in String(year) } ?? "")
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            default:
                Text(ArtistTotals.number(album.songCount))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .opacity(notHere(download) ? DWPalette.off : 1)
    }

    /// Grid: the albums' tiles, as the Mac drew them before R2 (MacFrame.tileMin wide at least) - a click opens one.
    private func tiles(_ rows: [IndexAlbum]) -> some View {
        let personal = server.access.hasLibrary
        let marks = library.marks
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(MacFrame.tileMin)), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(rows) { (album: IndexAlbum) in
                    let download = downloads.album(id: album.id)
                    LibraryTile(album: album, isNew: personal && marks.isNew(album), download: download,
                                dimmed: notHere(download)) { open(album) }
                }
            }
            .padding(16)
        }
    }

    /// The status bar's facts: the albums listed and their songs, and the selection.
    private func status(_ rows: [IndexAlbum]) -> [String] {
        let songs = rows.reduce(0) { (sum: Int, album: IndexAlbum) -> Int in sum + max(album.songCount ?? 0, 0) }
        var items = [ArtistTotals.albums(rows.count), ArtistTotals.songs(songs)]
        if selectedAlbum(rows) != nil { items.append(ArtistTotals.oneSelected) }
        return items
    }

    // MARK: doing

    /// An album opened (a double-click, Return, a tile's click): its page, the New mark gone - not one with nothing on
    /// this Mac while deadwax can't be reached.
    private func open(_ album: IndexAlbum) {
        guard !notHere(downloads.album(id: album.id)) else { return }
        library.opened(album)
        navigation.open(.album(AlbumRoute(album)))
    }

    /// The selected album asked for, as its page asks - its songs Play's once they come; none with nothing selected.
    /// The album the selection leaves is let go (`leave`) - and one whose answer came only after the selection had
    /// left it (its albumShown late) is let go then.
    private func choose(_ album: IndexAlbum?) async {
        guard let album else {
            leave()
            return
        }
        let model: AlbumModel
        if let chosen, chosen.route.id == album.id {
            model = chosen
        } else {
            leave()
            model = AlbumModel(route: AlbumRoute(album))
        }
        model.online = reachability.online
        chosen = model
        await model.load(key: "\(server.person)|\(album.id)", client: server.client, personal: false, player: player,
                         downloads: downloads)
        if chosen !== model { player.albumLeft(id: album.id) }
    }

    /// (R2's review) The album the selection left: its levels no longer wanted for it (PlayerModel.albumLeft), each
    /// albumShown its answer made paired, as its page's leaving pairs its own.
    private func leave() {
        guard let chosen else { return }
        player.albumLeft(id: chosen.route.id)
        self.chosen = nil
    }

    /// What Play takes: the selected album's songs, once in hand - offline, those on this Mac. Nothing in Grid, where
    /// nothing is selected (R2's review).
    private var playable: [Song] {
        guard library.layout == .list, let chosen, chosen.route.id == selected else { return [] }
        guard !reachability.online || chosen.goneButHere else { return chosen.songs }
        return OfflineAlbum.playable(chosen.songs, here: downloads.isHere)
    }

    /// Play: the selected album from its first song, in the tap - the songs already in hand, nothing awaited.
    private func play() {
        let songs = playable
        guard let album = chosen?.album, !songs.isEmpty else { return }
        player.play(songs: songs, album: album, at: nil)
    }

    /// Whose Shuffle: the Library's, or the collection's (All songs') for the collection's albums with a library of
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
