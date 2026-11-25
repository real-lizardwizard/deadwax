import DeadwaxCore
import SwiftUI

/// Playlists on the Mac (the redesign, slice R5 - Playlists.dc.html; notes/ios.md "The redesign, slice R5: an album,
/// Playlists, a playlist"): the Library's Playlists page at its root, under the page's toolbar, as a column list - drawn
/// by LibraryView's `desk` in the phone page's place.
///
/// - The toolbar (.bar): New playlist… (the accent's), the groove, Play and Shuffle - the playlist selected, once its
///   songs are in hand - and Find in playlists at its end, 230 wide. The drawing's Download, Rename… and Delete… are a
///   playlist's own: its right-click's Download items, its page's Edit.
/// - The list (MacColumnList): Playlist (its cover and name), Songs, Length, Whose (Yours, its owner's name, From a
///   file), Changed (today, yesterday, 3 days ago... - read against a `now` taken again at a day's change), On this Mac
///   (a chip once downloaded, its line while it downloads). (R5's review) The columns are Core's, narrower than drawn
///   (MacAlbumFacts.playlistColumns): Playlist keeps 160 at least, and on a page too narrow for that beside the rest -
///   a 1280 window beside the side panel's column - Whose and Changed are left out. Yours first, then those shared
///   with you, then those from files - each in Navidrome's order (PlaylistRules.groups). A click selects, a double-click
///   or Return opens the playlist's page; a right-click is its page's •••'s items (PlaylistRightClick). The drawing's
///   rows are 40 tall with a 28 cover - (the Mac's Row Size) View > Row Size's Medium; Small (30 with 20) is the
///   default, and Large 52 with 40. Playlist's least grows with the cover (MacAlbumFacts.playlistLeast(_:)), so its
///   name keeps its room.
/// - Play and Shuffle play the playlist selected once its songs are in hand: asked once the selection has rested (200
///   ms), as its page asks them (PlaylistPageModel), Play and Shuffle dimmed until they come - the tap calls the player
///   with them, nothing awaited (PlayerModel.play(playlist:)). (R5's review) Only a playlist listed: the selection lets
///   go as soon as its row isn't shown (Find, or a list with no rows to draw at all), here at the page, not only in
///   the list.
/// - The list is PlaylistsModel's, asked afresh each time the page shows (the app back in front included), as the
///   phone's is. While deadwax can't be reached a playlist with nothing of it to play here is dimmed and opens nothing.
/// - The status bar: how many playlists are listed (those Find finds), how many yours and shared with you - nothing
///   while none is.
struct MacPlaylistsPage: View {
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    /// (The Mac's Row Size) The rows' size: the cover's, the list's own row, and Playlist's least beside the columns.
    @Environment(\.macRowSize) private var rowSize
    /// Find's words.
    @State private var typed = ""
    /// The row selected, by playlist id.
    @State private var selected: String?
    /// The selected playlist's songs, asked once the selection rests: Play's and Shuffle's.
    @State private var chosen: PlaylistPageModel?
    /// New playlist's sheet, while it is up.
    @State private var newSheet: PlaylistsPage.NewSheet?
    /// The playlist just made, opened once its sheet has gone.
    @State private var made: PlaylistRoute?
    @State private var shown = false
    /// The day Changed is read against: taken again at a day's change.
    @State private var now = ArtistTotals.now()

    /// How long the selection rests before its playlist is asked for: 200 ms.
    private static let rest: UInt64 = 200_000_000

    /// The columns (Playlists.dc.html's .cols) a list `width` wide draws - Core's (MacAlbumFacts.playlistColumns):
    /// Playlist takes what the others leave, 160 at least.
    static func columns(_ shown: [MacAlbumFacts.PlaylistColumn]) -> [MacListColumn] {
        shown.map { (column: MacAlbumFacts.PlaylistColumn) -> MacListColumn in
            MacListColumn(title: MacAlbumFacts.playlistTitle(column, device: Platform.device),
                          width: MacAlbumFacts.playlistWidth(column))
        }
    }

    private struct ChosenKey: Equatable {
        let person: Int
        let selected: String?
        let online: Bool
    }

    var body: some View {
        let online = reachability.online
        let rows = self.rows
        MacPage {
            tools
        } content: {
            content(rows, online: online)
        }
        // (R5's review) what is listed: Find's, the downloaded shelf offline - nothing while none is
        .macStatus(MacStatusItems.Items(leading: MacAlbumFacts.playlistsStatus(rows)))
        // (R5's review) the selection is only ever a playlist shown: let go here, at the page, when its row isn't - a
        // list with no rows isn't drawn, so MacColumnList's own keeping never runs
        .onChange(of: rows.map(\.id), initial: true) { (_: [String], ids: [String]) -> Void in
            let kept = MacTable.kept(selected, in: ids)
            if kept != selected { selected = kept }
        }
        .appSheet(item: $newSheet, onDismiss: openMade) { (sheet: PlaylistsPage.NewSheet) in
            NavigationStack {
                List {
                    NewPlaylistFields(escapes: true) { (name: String) in
                        try await make(name, from: sheet)
                    } cancel: {
                        if newSheet == sheet { newSheet = nil }
                    }
                }
                .navigationTitle(PlaylistWords.newPlaylistTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
            .macSheet()
        }
        .task(id: "\(server.person)|\(online)") {
            // the page shown (and shown again): asked afresh - nothing while deadwax can't be reached
            guard online else { return }
            await playlists.ask(fresh: true)
        }
        .task(id: ChosenKey(person: server.person, selected: selected, online: online)) {
            if selected != nil {
                try? await Task.sleep(nanoseconds: Self.rest)
                guard !Task.isCancelled else { return }
            }
            await choose(selectedPlaylist(self.rows))
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, reachability.online else { return }
            Task { await playlists.ask(fresh: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear {
            shown = true
            now = ArtistTotals.now()
        }
        .onDisappear { shown = false }
    }

    // MARK: the toolbar

    @ViewBuilder private var tools: some View {
        let songs = playable
        Button(PlaylistWords.newPlaylistRow) { newSheet = PlaylistsPage.NewSheet() }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(!reachability.online)
        MacGroove()
        Button(action: play) {
            HStack(spacing: 6) {
                SharpSymbol(.play)
                Text(PlaylistWords.play)
            }
        }
        .buttonStyle(DWButtonStyle())
        .disabled(songs.isEmpty)
        Button(ShuffleWords.shuffle, action: shuffle)
            .buttonStyle(DWButtonStyle())
            .disabled(songs.isEmpty)
        Spacer(minLength: 0)
        DWField(prompt: LibrarySwitchWords.findPlaylists, text: $typed)
            .frame(width: 230)
    }

    // MARK: the list

    /// The playlists listed: those Find finds, yours first, then shared with you, then from files - offline with no list
    /// in hand, those downloaded to this Mac.
    private var rows: [Playlist] {
        let list = playlists.list ?? (reachability.online ? [] : PlaylistDownloads.shelf(downloads.playlists.kept))
        let groups = PlaylistRules.groups(PlaylistRules.found(list, typed: typed))
        return groups.yours + groups.shared + groups.files
    }

    private func selectedPlaylist(_ rows: [Playlist]) -> Playlist? {
        guard let selected else { return nil }
        return rows.first { (playlist: Playlist) -> Bool in playlist.id == selected }
    }

    @ViewBuilder private func content(_ rows: [Playlist], online: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if online, playlists.list != nil, let failure = playlists.failure {
                failed(failure, retry: false)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
            }
            if playlists.list == nil, online {
                Group {
                    if let failure = playlists.failure {
                        failed(failure, retry: true)
                    } else {
                        ProgressView()
                            .accessibilityLabel(PlaylistWords.loading)
                    }
                }
                .padding(22)
            } else if rows.isEmpty {
                Text(empty(online: online))
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(22)
            } else {
                // (R5's review) the columns that fit the page: Whose and Changed left out beside the side panel
                GeometryReader { (room: GeometryProxy) in
                    let shown = MacAlbumFacts.playlistColumns(width: Double(room.size.width), size: rowSize)
                    MacColumnList(columns: Self.columns(shown), rows: rows, selected: $selected,
                                  open: { (playlist: Playlist) -> Void in open(playlist) },
                                  menu: { (playlist: Playlist) -> PlaylistRightClick in
                                      PlaylistRightClick(route: PlaylistRoute(playlist))
                                  }
                    ) { (playlist: Playlist, column: Int) in
                        if shown.indices.contains(column) { cell(playlist, shown[column]) }
                    }
                }
            }
        }
    }

    /// "Couldn't list your playlists. <why>" (the phone page's note, its words Core's) - and Try again with no list to
    /// show.
    private func failed(_ failure: any Error, retry: Bool) -> some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: retry)
        return VStack(alignment: .leading, spacing: 8) {
            ErrorNote(text: PlaylistWords.listFailed(line.said), detail: line.detail)
            if retry {
                Button(PlaylistWords.tryAgain) { Task { await playlists.ask(fresh: true) } }
                    .buttonStyle(DWButtonStyle())
            }
        }
    }

    /// What an empty list says: none yet, none Find finds, or none downloaded while deadwax can't be reached.
    private func empty(online: Bool) -> String {
        if Find.finding(typed) { return LibrarySwitchWords.noPlaylistMatch(typed) }
        if !online && playlists.list == nil { return PlaylistWords.offlineList }
        return "\(PlaylistWords.playlistsEmpty) \(PlaylistWords.playlistsEmptyHow)"
    }

    /// While deadwax can't be reached, a playlist with nothing of it to play here: dimmed, opening nothing.
    private func dimmed(_ playlist: Playlist) -> Bool {
        !reachability.online && !playlists.playsOffline(playlist.id, here: downloads.isHere)
            && !downloads.playlistPlaysOffline(playlist.id)
    }

    @ViewBuilder private func cell(_ playlist: Playlist, _ column: MacAlbumFacts.PlaylistColumn) -> some View {
        Group {
            switch column {
            case .playlist:
                HStack(spacing: 8) {
                    PlaylistCover(id: playlist.coverArt, side: CGFloat(rowSize.cover), pixels: CoverSize.row)
                        .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                        .clipShape(DWCorners.chipShape)
                        .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text(playlist.name)
                }
            case .songs:
                Text(ArtistTotals.number(playlist.songCount))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            case .length:
                Text(MacAlbumFacts.length(playlist.duration))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            case .whose:
                Text(MacAlbumFacts.whose(playlist))
                    .foregroundStyle(DWPalette.t2)
            case .changed:
                Text(MacAlbumFacts.changed(playlist, now: now))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
            case .onDevice:
                if let state = downloads.playlistState(playlist.id) {
                    if case .downloaded = state {
                        DWChip(words: MacAlbumFacts.Words.onDevice(Platform.device))
                    } else if let line = DownloadWords.albumLine(state, device: Platform.device) {
                        Text(line)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t3)
                    }
                }
            }
        }
        .opacity(dimmed(playlist) ? DWPalette.off : 1)
    }

    // MARK: doing

    /// A playlist opened (a double-click, Return): its page - not one with nothing to play while deadwax can't be reached.
    private func open(_ playlist: Playlist) {
        guard !dimmed(playlist) else { return }
        navigation.open(.playlist(PlaylistRoute(playlist)))
    }

    /// The selected playlist asked for, as its page asks it - its songs Play's and Shuffle's once they come.
    private func choose(_ playlist: Playlist?) async {
        guard let playlist else {
            chosen = nil
            return
        }
        let model: PlaylistPageModel
        if let chosen, chosen.route.id == playlist.id {
            model = chosen
        } else {
            model = PlaylistPageModel(route: PlaylistRoute(playlist))
        }
        model.online = reachability.online
        // a downloaded playlist drawn from this Mac, and the downloads kept in step by what it is answered, as its page
        let downloads = downloads
        model.stored = { (id: String) -> PlaylistWithSongs? in downloads.keptPlaylist(id) }
        let id = playlist.id
        model.heard = { (answer: PlaylistWithSongs?) -> Void in
            if let answer { downloads.playlistAnswered(answer) } else { downloads.playlistGone(id) }
        }
        chosen = model
        await model.load(key: "\(server.person)|\(id)", client: server.client, playlists: playlists)
    }

    /// What Play and Shuffle take: the selected playlist's songs, once in hand - offline, those on this Mac. (R5's
    /// review) Only for the playlist selected now (never the one asked before it), and only while its row is listed.
    private var playable: [Song] {
        guard let chosen, let selected, chosen.route.id == selected, !chosen.gone,
              rows.contains(where: { (playlist: Playlist) -> Bool in playlist.id == selected }) else { return [] }
        guard !reachability.online else { return chosen.songs }
        return OfflineAlbum.playable(chosen.songs, here: downloads.isHere)
    }

    /// Play: the selected playlist from its first song, in the tap - the songs already in hand, nothing awaited.
    private func play() {
        let songs = playable
        guard !songs.isEmpty else { return }
        player.play(playlist: songs, at: 0, shuffle: false)
    }

    /// Shuffle: the selected playlist's songs, every one once in a random order - in the tap.
    private func shuffle() {
        let songs = playable
        guard !songs.isEmpty else { return }
        player.play(playlist: songs, at: nil, shuffle: true)
    }

    /// New playlist's Create, from `sheet`: an empty playlist, made as the person signed in - its page opened once the
    /// sheet has gone (the phone's rule, PlaylistEdit.made), else said.
    private func make(_ name: String, from sheet: PlaylistsPage.NewSheet) async throws {
        let new: PlaylistWithSongs
        do {
            new = try await playlists.create(name: name, songIDs: [], picker: false)
        } catch is PlaylistsModel.Superseded {
            return
        }
        let route = PlaylistRoute(new.playlist)
        switch PlaylistEdit.made(sentFrom: sheet, up: newSheet, shown: shown) {
        case .closeThenOpen:
            made = route
            newSheet = nil
        case .open:
            navigation.open(.playlist(route))
        case .say:
            player.say(PlaylistWords.made(new.playlist.name))
        }
    }

    private func openMade() {
        guard let route = made else { return }
        made = nil
        if shown {
            navigation.open(.playlist(route))
        } else {
            player.say(PlaylistWords.made(route.preview?.name ?? ""))
        }
    }
}
