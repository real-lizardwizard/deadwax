import DeadwaxCore
import SwiftUI

/// An artist's page (Phase 4, slice 4 - phase4-library.md 2.6; the web's ArtistPage.tsx without its MusicBrainz parts,
/// question 4: no discography, description, facts, pins or managing). Top to bottom: their picture (round, as their row's)
/// and their name; Play and Shuffle, with the line under them (ArtistPage.playsLine) and Try again when some albums'
/// songs didn't come; Albums - their albums in the collection, newest first (ArtistPage.rows), each its cover, title and
/// "1994 · in your library" with the tick for yours (or every one without a library of your own). A row opens its album;
/// nothing here plays but Play and Shuffle.
///
/// Play plays every album of theirs in the page's order, each at its album level, from the first song; Shuffle every song
/// of them once, at the songs level (ArtistPlay.plan) - through PlayerModel.play(artist:) in the tap, with the songs in
/// hand: the page asks for every album's songs as it opens, 4 at a time (ArtistPageModel, Core's ArtistAlbumAsks), and
/// Play and Shuffle are live once every album has answered or failed.
///
/// While deadwax can't be reached (3.1's rule): nothing is asked; their albums are the answer in hand, or the albums on
/// this phone naming them; an album with nothing here is dimmed and opens nothing; Play and Shuffle take only the songs
/// on this phone (ArtistOffline.playable), and the line says only downloaded albums play.
struct ArtistView: View {
    let route: ArtistRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(ArtistsModel.self) private var artists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var model: ArtistPageModel
    /// The hero's name has scrolled away: the bar shows it.
    @State private var nameInBar = false

    /// The picture's side, in points (CoverImage asks the nearest step for the screen's scale: 1024 on an iPhone).
    private static let pictureSide: CGFloat = 200
    private static let edge: CGFloat = 16

    init(route: ArtistRoute) {
        self.route = route
        _model = State(initialValue: ArtistPageModel(route: route))
    }

    /// Who and which artist: a new person asks everything again.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    var body: some View {
        let online = reachability.online
        let personal = server.access.hasLibrary
        let albums = self.albums(online: online)
        let rows = ArtistPage.rows(albums)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero
                    .onAppear { nameInBar = false }
                    .onDisappear { nameInBar = true }
                if model.answer == nil && !online && rows.isEmpty {
                    // nothing of theirs in hand, and deadwax out of reach: a state, not a failure - nothing was asked
                    ShelfNote(DownloadWords.onlyDownloadedPlay)
                } else if model.gone {
                    ErrorNote(text: ErrorWords.artistGone)
                        .padding(.top, 8)
                } else if let failure = model.failure, model.answer == nil, online {
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                        Button(LibraryWords.tryAgain) { reload() }
                    }
                    .padding(.top, 8)
                } else {
                    plays(rows: rows, online: online, personal: personal)
                    albumsList(rows, albums: albums, online: online, personal: personal)
                }
            }
            .padding(.horizontal, Self.edge)
            .padding(.bottom, 24)
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(nameInBar ? 1 : 0)
                    .accessibilityHidden(!nameInBar)
            }
        }
        .task(id: taskKey) {
            await model.load(key: taskKey, client: server.client, online: reachability.online, artists: artists)
        }
        .task { await downloads.followProgress() }
        .refreshable {
            // deadwax out of reach: a pull asks whether it is back (the banner says why nothing changes)
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            await model.load(key: taskKey, client: server.client, online: true, artists: artists, again: true)
            if model.asks.someMissing { model.again(client: server.client) }
        }
        .onChange(of: reachability.online) { _, online in
            // back: what the page couldn't ask is asked of deadwax now - the songs that didn't come with it
            guard online else { return }
            reload()
        }
    }

    /// The artist asked again (Try again, deadwax back) - and the albums whose songs didn't come.
    private func reload() {
        let key = taskKey
        Task {
            await model.load(key: key, client: server.client, online: reachability.online, artists: artists)
            if model.asks.someMissing { model.again(client: server.client) }
        }
    }

    /// Their albums: the answer's - or, while deadwax can't be reached, the answer in hand, else the albums on this phone
    /// naming them (ArtistOffline.albums).
    private func albums(online: Bool) -> [Album] {
        if online || model.answer != nil { return model.answer?.album ?? [] }
        let downloaded = downloads.downloadedAlbums.compactMap { (album: IndexAlbum) -> Album? in
            downloads.keptAlbum(album.id)
        }
        return ArtistOffline.albums(answer: nil, artistId: route.id, downloaded: downloaded)
    }

    // MARK: the hero

    private var hero: some View {
        VStack(spacing: 0) {
            ArtistPicture(id: model.coverArt, side: Self.pictureSide, pixels: CoverSize.hero)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)
            Text(model.name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Play and Shuffle

    /// Play and Shuffle, the line under them (held at its height whatever it says), and Try again when some albums'
    /// songs didn't come.
    @ViewBuilder
    private func plays(rows: [ArtistPage.Row], online: Bool, personal: Bool) -> some View {
        let order = ArtistPage.playOrder(rows)
        let offlineAlbums = online ? [] : offlinePlayable(order)
        let playable = online ? model.asks.playable : !offlineAlbums.isEmpty
        let line = online ? model.asks.line(library: model.library, personal: personal)
            : DownloadWords.onlyDownloadedPlay
        VStack(spacing: 8) {
            PlayButtons(enabled: playable,
                        play: { play(shuffle: false, online: online, offlineAlbums: offlineAlbums) },
                        shuffle: { play(shuffle: true, online: online, offlineAlbums: offlineAlbums) })
            Text(line.isEmpty ? " " : line)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(line.isEmpty)
            if online, model.asks.someMissing {
                Button(LibraryWords.tryAgain) { model.again(client: server.client) }
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    /// What plays offline: each album of theirs in the page's order, its kept answer's songs on this phone only.
    private func offlinePlayable(_ order: [String]) -> [Album] {
        let ready = model.asks.ready
        return ArtistOffline.playable(order, album: { (id: String) -> Album? in ready[id] ?? downloads.keptAlbum(id) },
                                      here: { (id: String) -> Bool in downloads.isHere(id) })
    }

    /// Play or Shuffle, in the tap: the albums in hand (or, offline, the songs on this phone) - nothing awaited first.
    private func play(shuffle: Bool, online: Bool, offlineAlbums: [Album]) {
        let albums = online ? model.asks.answers : offlineAlbums
        player.play(artist: albums, shuffle: shuffle)
    }

    // MARK: their albums

    @ViewBuilder
    private func albumsList(_ rows: [ArtistPage.Row], albums: [Album], online: Bool, personal: Bool) -> some View {
        if !rows.isEmpty {
            Text(ArtistWords.albumsHeading)
                .font(.title3.weight(.semibold))
                .padding(.top, 18)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { (row: ArtistPage.Row) in
                ArtistAlbumRow(row: row, line: ArtistPage.line(row, personal: personal),
                               marked: ArtistPage.marked(row, personal: personal),
                               dimmed: !online && !downloads.album(id: row.albumId).hasSongsHere) {
                    open(row, albums: albums)
                }
            }
        }
        // none: the line under Play and Shuffle says so ("None of their albums are here to play.")
    }

    /// A row's tap: its album's page, what the artist's answer knew of it drawn at once - the artist line their link.
    private func open(_ row: ArtistPage.Row, albums: [Album]) {
        var album = albums.first { (album: Album) -> Bool in album.id == row.albumId }.map { (album: Album) -> AlbumRoute in
            AlbumRoute(album)
        } ?? AlbumRoute(id: row.albumId, name: row.title, coverArt: row.coverArt)
        if album.artist == nil { album.artist = model.name }
        if album.artistId == nil { album.artistId = route.id }
        navigation.open(.album(album))
    }
}

/// One album of the artist's (ArtistPage.tsx's row): its cover at the rows' size, its title, and "1994 · in your
/// library" with the green tick before it for an album marked (ArtistPage.marked). Read as one. Dimmed, and opening
/// nothing, while deadwax can't be reached and nothing of it is on this phone.
private struct ArtistAlbumRow: View {
    let row: ArtistPage.Row
    let line: String
    let marked: Bool
    let dimmed: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    LibraryCover(id: row.coverArt, pixels: CoverSize.row)
                        .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .foregroundStyle(.primary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if marked {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.held)
                                    .accessibilityHidden(true)
                            }
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
            .accessibilityLabel([row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
            .accessibilityValue(dimmed ? DownloadWords.notOnPhone : "")
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }
}
