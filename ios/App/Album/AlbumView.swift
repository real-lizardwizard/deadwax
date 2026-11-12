import DeadwaxCore
import SwiftUI

/// An album's page (screens.md 4; the web's ui/src/player/AlbumPage.tsx), by Navidrome's album id - what opened it
/// (the Library's row, Now Playing's Go to the album) drawn at once while the album loads. Top to bottom: the hero
/// (cover, title, artist, meta line, the badge, Play and Shuffle), the mine block (logins on with a library of your
/// own), the songs with their disc headings, the footer; the bar's ••• is the whole album's Play Next and Play Last.
///
/// What it asks as it opens, at once (AlbumModel): the album; the id bridge only with a library of your own (D12);
/// and, as the songs come, the album's levels warmed (PlayerModel.albumShown) - wanted again each time the page is
/// shown, let go when it goes (PlayerModel.albumLeft). While it is on top your library is told it was opened
/// (LibraryModel.opened - its New mark goes), again as /me/library answers. Every rule is Core's; this draws.
///
/// Play queues the songs from the first, Shuffle every song once in a random order, a row's tap from that song - all
/// as the album (Normalization's album level), through PlayerModel.play in the tap, nothing awaited first.
struct AlbumView: View {
    let route: AlbumRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @State private var model: AlbumModel
    /// On screen - the page on top of its tab.
    @State private var shown = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    @AccessibilityFocusState private var noteFocused: Bool

    init(route: AlbumRoute) {
        self.route = route
        _model = State(initialValue: AlbumModel(route: route))
    }

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil) {
        self.init(route: AlbumRoute(id: id, name: name, artist: artist, coverArt: coverArt))
    }

    /// Who and which album: a new person, or a library of their own come or gone, asks everything again.
    private var taskKey: String { "\(server.person)|\(server.access.hasLibrary)|\(route.id)" }

    var body: some View {
        List {
            AlbumHero(model: model, play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                .listRowSeparator(.hidden)
                .onAppear { setTitleInBar(false) }
                .onDisappear { setTitleInBar(true) }

            if model.placeholderShown {
                MinePlaceholder()
                    .listRowSeparator(.hidden)
            } else if model.mineBlockShown {
                MineBlock(mine: model.mine, busy: model.busy, refused: model.refused,
                          act: { action in Task { await model.change(action, client: server.client, library: library) } },
                          noteFocused: $noteFocused)
                    .listRowSeparator(.hidden)
            }

            if model.empty {
                ErrorNote(text: ErrorWords.albumGone)
                    .listRowSeparator(.hidden)
            } else if let failure = model.failure {
                ErrorNote(failure, gone: ErrorWords.albumGone)
                    .listRowSeparator(.hidden)
            } else if model.album == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(AlbumPageLines.loading)
                    .listRowSeparator(.hidden)
            }

            if let album = model.album {
                songs(album)
                Text(model.footer)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .listRowSeparator(.hidden, edges: .bottom)
            }
        }
        .listStyle(.plain)
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(titleInBar ? 1 : 0)
                    .accessibilityHidden(!titleInBar)
            }
            ToolbarItem(placement: .topBarTrailing) {
                QueueMenu(request: albumMenu) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(AlbumPageLines.moreForAlbum)
            }
        }
        .task(id: taskKey) {
            await model.load(key: taskKey, client: server.client, personal: server.access.hasLibrary, player: player)
        }
        .refreshable {
            await model.refresh(client: server.client, player: player)
        }
        .onChange(of: model.answered) { _, _ in told() }
        .onAppear {
            shown = true
            seen()
            // shown again (a page over it gone, its tab back): its levels wanted again - its first showing waits for
            // the album to answer (AlbumModel.load)
            if let album = model.album { player.albumShown(album) }
        }
        .onDisappear {
            shown = false
            player.albumLeft(id: route.id)
        }
        .onChange(of: library.marks) { _, _ in
            // your library answered while the page is on top: one opened before deadwax said what is new is cleared too
            if shown { seen() }
        }
    }

    /// The page on top is seen (App.tsx's seenAlbum for the page on top): its New mark goes, and deadwax is told.
    private func seen() {
        library.opened(id: route.id, musicBrainzId: route.musicBrainzId ?? model.album?.musicBrainzId)
    }

    /// The songs, a disc heading above the first of each disc when the album shows them.
    @ViewBuilder private func songs(_ album: Album) -> some View {
        let songs = model.songs
        let headings = model.headings
        let heard = player.current?.track
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            if headings.indices.contains(index), let heading = headings[index] {
                DiscHeadingRow(heading: heading)
                    .listRowSeparator(.hidden)
            }
            TrackRow(song: song, albumArtist: album.artist, current: PlayingBars.marks(song, heard: heard),
                     playing: player.isPlaying,
                     play: { play(at: index) },
                     menu: QueueMenuRequest(pick: .song(song, of: album), album: album))
        }
    }

    /// The bar's •••: the whole album, as an album - nil (the ••• dimmed) until its songs are in.
    private var albumMenu: QueueMenuRequest? {
        guard let album = model.album, let pick = model.albumPick else { return nil }
        return QueueMenuRequest(pick: pick, album: album)
    }

    /// Play, Shuffle and a row's tap: the album's songs, as the album, from `index` (nil with Shuffle: any song
    /// first). In the tap - nothing awaited before the player is called.
    private func play(at index: Int?, shuffle: Bool = false) {
        guard let album = model.album, !model.songs.isEmpty else { return }
        player.play(songs: model.songs, album: album, at: index, shuffle: shuffle)
    }

    /// An Add or Remove answered: taken - VoiceOver goes to the line that says so (the web's role=status, its focus
    /// handed to the line); refused - the refusal is read out where the button keeps the focus (role=alert).
    private func told() {
        if let refused = model.refused {
            Notice.announce(ErrorWords.of(refused, admin: server.access.seesDetail).said)
        } else if model.mine.note != nil {
            // after the line is drawn: the focus can only go to a view that is there
            Task { @MainActor in
                await Task.yield()
                noteFocused = true
            }
        }
    }

    private func setTitleInBar(_ shown: Bool) {
        guard titleInBar != shown else { return }
        withAnimation(.easeInOut(duration: 0.2)) { titleInBar = shown }
    }
}
