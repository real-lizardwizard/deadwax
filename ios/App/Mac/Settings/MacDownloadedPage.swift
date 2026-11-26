import DeadwaxCore
import SwiftUI

/// Downloaded on the Mac (the redesign, slice R9 - Downloaded.dc.html; notes/ios.md "The redesign, slice R9"): what is
/// on this Mac, as a column list under the page's toolbar - the sidebar's Downloaded, and This Mac's Show Downloaded.
///
/// - The toolbar: Albums | Playlists (the drawing's segments; its Songs has no list of its own here, and its Play and
///   Shuffle are an album's page's), Remove all… - Settings > Downloads' own question and call (DownloadModel.removeAll),
///   asked first, said once done - and (R9's review) Find at its end, 230 wide, as the Albums page's: every word typed
///   in an album's name or artist, a playlist's name (MacDownloaded.finds).
/// - (R9's review) Over the albums, the first ask (FirstAskCard, the phone's Downloaded's own: Download your library?),
///   once deadwax has answered with albums of the Library's, while nothing is typed into Find.
/// - The list (MacColumnList, Core's MacDownloaded columns at the drawing's widths): Album (its cover and name), Artist,
///   Songs ("7 of 13" when not all of it is here), Size, and On this Mac - the meter and its line while it downloads,
///   amber while some of it didn't, else the day its last song came (today, yesterday, 4 days ago, 21 Nov - read against
///   a `now` taken again at a day's change). Playlists: Playlist, Songs, Size, On this Mac. Every row and number is
///   DownloadShelf's - the records Settings > Downloads draws - albums that are coming first, then those that didn't
///   come, then those here, largest first. A click selects, a double-click or Return opens the album's (the
///   playlist's) page; a right-click is that page's •••'s items (AlbumRightClick, PlaylistRightClick), Remove Download
///   among them. Its rows as tall as View > Row Size says, the cover with them.
/// - The status bar: the albums, songs and size here, how many are downloading, and the free space (MacDownloaded's).
///
/// Progress moves while the page shows (DownloadModel.followProgress), as on Settings > Downloads.
struct MacDownloadedPage: View {
    var tab: MacDownloaded.Tab = .albums

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryModel.self) private var library
    @Environment(Reachability.self) private var reachability
    /// (The Mac's Row Size) The cover grows with the rows.
    @Environment(\.macRowSize) private var rowSize
    @State private var shown: MacDownloaded.Tab = .albums
    @State private var selected: String?
    /// Find's words - the page's own, let go with a change of tab.
    @State private var typed = ""
    @State private var askingRemoveAll = false
    @State private var free: Int64? = DownloadStore.freeSpace()
    /// The day On this Mac is read against: taken again at a day's change.
    @State private var now = ArtistTotals.now()

    init(tab: MacDownloaded.Tab = .albums) {
        self.tab = tab
        _shown = State(initialValue: tab)
    }

    var body: some View {
        let shelf = DownloadShelf(downloads, server: server)
        let albums = Self.albums(shelf)
        let playlists = Self.playlists(shelf)
        MacPage {
            tools(shelf)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // the phone's Downloaded's first ask, over the albums
                if shown == .albums, !Find.finding(typed), reachability.online,
                   library.albums(library.scope)?.albums.isEmpty == false {
                    FirstAskCard(macRoom: EdgeInsets(top: 16, leading: 22, bottom: 0, trailing: 22))
                }
                content(albums: albums, playlists: playlists)
            }
        }
        .macStatus(status(shelf))
        .onChange(of: shown) { _, _ in
            selected = nil
            typed = ""
        }
        .task { await downloads.followProgress() }
        .task(id: downloads.bytesHere) { free = DownloadStore.freeSpace() ?? free }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear { now = ArtistTotals.now() }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ shelf: DownloadShelf) -> some View {
        DWSegmented(options: MacDownloaded.Tab.allCases,
                    words: { (tab: MacDownloaded.Tab) -> String in MacDownloaded.tabWords(tab) },
                    chosen: $shown, spoken: DownloadWords.downloadedHeader, large: true)
        Spacer(minLength: 8)
        Button(MacDownloaded.removeAll) { askingRemoveAll = true }
            .buttonStyle(DWButtonStyle())
            .disabled(shelf.isEmpty || downloads.storeProblem != nil)
            .confirmationDialog(DownloadWords.removeAllTitle, isPresented: $askingRemoveAll, titleVisibility: .visible) {
                Button(DownloadWords.removeAll, role: .destructive) {
                    downloads.removeAll()
                    player.say(DownloadWords.removedAll)
                }
                Platform.dialogCancel()
            } message: {
                Text(shelf.removeAllMessage(downloads, server: server))
            }
        DWField(prompt: shown == .albums ? LibraryWords.findPlaceholder : LibrarySwitchWords.findPlaylists, text: $typed)
            .frame(width: 230)
    }

    // MARK: the rows

    /// An album's row: what DownloadShelf's sections hold of it, one row however many of them it is in.
    struct AlbumRow: Identifiable {
        enum Standing {
            case going(line: String, fraction: Double?)
            case failed(String)
            case here([Int64?])
        }

        let id: String
        let album: Album?
        var songs = ""
        var bytes: Int64?
        var state: Standing
    }

    struct PlaylistRow: Identifiable {
        let id: String
        let name: String
        let coverArt: String?
        var songs = ""
        var bytes: Int64?
        /// Its line and meter while songs of it are to come.
        var going: (line: String, fraction: Double?)?
    }

    /// The albums: coming first, then those that didn't come, then those here, largest first - each once, its songs and
    /// size those here.
    static func albums(_ shelf: DownloadShelf) -> [AlbumRow] {
        var order: [String] = []
        var rows: [String: AlbumRow] = [:]
        for going in shelf.downloading where rows[going.id] == nil {
            order.append(going.id)
            rows[going.id] = AlbumRow(id: going.id, album: going.album,
                                      state: .going(line: going.line, fraction: going.fraction))
        }
        for failed in shelf.failed where rows[failed.id] == nil {
            order.append(failed.id)
            rows[failed.id] = AlbumRow(id: failed.id, album: failed.album,
                                       state: .failed(DownloadWords.didntDownload(failed.records.count)))
        }
        for here in shelf.downloaded {
            if rows[here.id] == nil {
                order.append(here.id)
                rows[here.id] = AlbumRow(id: here.id, album: here.album, state: .here(here.doneAt))
            }
            rows[here.id]?.songs = MacDownloaded.songs(here: here.songs, of: here.total)
            rows[here.id]?.bytes = here.bytes
        }
        return order.compactMap { (id: String) -> AlbumRow? in rows[id] }
    }

    /// The downloaded playlists: coming first, then those here - each once.
    static func playlists(_ shelf: DownloadShelf) -> [PlaylistRow] {
        var order: [String] = []
        var rows: [String: PlaylistRow] = [:]
        for going in shelf.playlistsGoing where rows[going.id] == nil {
            order.append(going.id)
            rows[going.id] = PlaylistRow(id: going.id, name: going.name, coverArt: going.coverArt,
                                         going: (going.line, going.fraction))
        }
        for here in shelf.playlistsHere {
            if rows[here.id] == nil {
                order.append(here.id)
                rows[here.id] = PlaylistRow(id: here.id, name: here.name, coverArt: here.coverArt)
            }
            rows[here.id]?.songs = MacDownloaded.songs(here: here.songs, of: here.total)
            rows[here.id]?.bytes = here.bytes
        }
        return order.compactMap { (id: String) -> PlaylistRow? in rows[id] }
    }

    private func columns(_ tab: MacDownloaded.Tab) -> [MacListColumn] {
        MacDownloaded.columns(tab).map { (column: MacDownloaded.Column) -> MacListColumn in
            MacListColumn(title: MacDownloaded.title(column, tab: tab, device: Platform.device),
                          width: MacDownloaded.width(column))
        }
    }

    @ViewBuilder private func content(albums all: [AlbumRow], playlists allPlaylists: [PlaylistRow]) -> some View {
        let albums = all.filter { (row: AlbumRow) -> Bool in
            MacDownloaded.finds(typed, name: row.album?.name, artist: row.album?.artist)
        }
        let playlists = allPlaylists.filter { (row: PlaylistRow) -> Bool in MacDownloaded.finds(typed, name: row.name) }
        if let problem = downloads.storeProblem {
            ErrorNote(text: DownloadWords.storeUnreadable(Platform.device), detail: problem)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.amberText)
                .padding(22)
        } else if shown == .albums ? (albums.isEmpty && !all.isEmpty) : (playlists.isEmpty && !allPlaylists.isEmpty) {
            // Find found none of them
            Text(shown == .albums ? Find.noMatchText("albums", typed: typed) : LibrarySwitchWords.noPlaylistMatch(typed))
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(22)
        } else if shown == .albums ? albums.isEmpty : playlists.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(shown == .albums ? DownloadWords.nothingYet : PlaylistDownloadWords.noneYet)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.text)
                Text(shown == .albums ? DownloadWords.nothingYetHow : PlaylistDownloadWords.noneYetHow(Platform.device))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(22)
            .accessibilityElement(children: .combine)
        } else if shown == .albums {
            let tab = MacDownloaded.Tab.albums
            let shownColumns = MacDownloaded.columns(tab)
            MacColumnList(columns: columns(tab), rows: albums, selected: $selected,
                          open: { (row: AlbumRow) -> Void in open(row) },
                          menu: { (row: AlbumRow) -> AlbumRightClick in AlbumRightClick(route: route(row)) }
            ) { (row: AlbumRow, column: Int) in
                if shownColumns.indices.contains(column) { cell(row, shownColumns[column]) }
            }
        } else {
            let tab = MacDownloaded.Tab.playlists
            let shownColumns = MacDownloaded.columns(tab)
            MacColumnList(columns: columns(tab), rows: playlists, selected: $selected,
                          open: { (row: PlaylistRow) -> Void in navigation.open(.playlist(PlaylistRoute(id: row.id))) },
                          menu: { (row: PlaylistRow) -> PlaylistRightClick in
                              PlaylistRightClick(route: PlaylistRoute(id: row.id))
                          }
            ) { (row: PlaylistRow, column: Int) in
                if shownColumns.indices.contains(column) { cell(row, shownColumns[column]) }
            }
        }
    }

    private func route(_ row: AlbumRow) -> AlbumRoute {
        row.album.map { (album: Album) -> AlbumRoute in AlbumRoute(album) } ?? AlbumRoute(id: row.id)
    }

    private func open(_ row: AlbumRow) {
        navigation.open(.album(route(row)))
    }

    @ViewBuilder private func cell(_ row: AlbumRow, _ column: MacDownloaded.Column) -> some View {
        switch column {
        case .name:
            HStack(spacing: 8) {
                CoverImage(id: row.album?.coverArt, size: CGFloat(rowSize.cover))
                    .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(row.album?.name ?? PlayerWords.untitled)
            }
        case .artist:
            Text(row.album?.artist ?? "")
                .foregroundStyle(DWPalette.t2)
        case .songs:
            Text(row.songs)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case .size:
            Text(row.bytes.map { (bytes: Int64) -> String in Bytes.words(bytes) } ?? "")
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case .here:
            switch row.state {
            case .going(let line, let fraction):
                going(line: line, fraction: fraction)
            case .failed(let words):
                Text(words)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.amberText)
            case .here(let doneAt):
                Text(MacDownloaded.when(doneAt, now: now))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
            }
        }
    }

    @ViewBuilder private func cell(_ row: PlaylistRow, _ column: MacDownloaded.Column) -> some View {
        switch column {
        case .name:
            HStack(spacing: 8) {
                PlaylistCover(id: row.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row)
                    .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(row.name)
            }
        case .artist:
            EmptyView()
        case .songs:
            Text(row.songs)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case .size:
            Text(row.bytes.map { (bytes: Int64) -> String in Bytes.words(bytes) } ?? "")
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case .here:
            if let going = row.going {
                self.going(line: going.line, fraction: going.fraction)
            } else {
                DWChip(words: MacAlbumFacts.Words.onDevice(Platform.device))
            }
        }
    }

    /// On this Mac while it downloads: the meter while songs of it fetch, and its line.
    private func going(line: String, fraction: Double?) -> some View {
        HStack(spacing: 8) {
            if let fraction {
                DWMeter(fraction: fraction)
                    .frame(width: 48)
            }
            Text(line)
                .font(Typeface.Mac.text(.label))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
        }
    }

    // MARK: the status bar

    private func status(_ shelf: DownloadShelf) -> MacStatusItems.Items {
        let said: (leading: [String], trailing: [String])
        if shown == .albums {
            said = MacDownloaded.status(albums: shelf.albumsHere, songs: shelf.songsHere, bytes: downloads.bytesHere,
                                        downloading: shelf.downloading.count, free: free, device: Platform.device)
        } else {
            let here = shelf.playlistsHere
            said = MacDownloaded.playlistsStatus(playlists: here.count,
                                                 songs: here.reduce(0) { (sum: Int, row: DownloadShelf.PlaylistLine) -> Int in sum + row.songs },
                                                 bytes: here.reduce(Int64(0)) { (sum: Int64, row: DownloadShelf.PlaylistLine) -> Int64 in sum + row.bytes },
                                                 free: free, device: Platform.device)
        }
        return MacStatusItems.Items(leading: said.leading, trailing: said.trailing)
    }
}
