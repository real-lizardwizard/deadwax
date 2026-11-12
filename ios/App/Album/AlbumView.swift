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
///
/// Downloads (phase2-downloads.md 3): the control in the bar beside the •••, the hero's line, the rows' marks, the
/// menus' download items and the footer's "on this phone" line - every one drawn from DownloadModel by the album's
/// songs, never from what the page last did, with progress followed while the page shows. An album with songs here
/// opens at once from what the phone kept. While deadwax can't be reached, the songs not here are dimmed, Play and
/// Shuffle take only what is here, and an album with nothing here says so in place of its songs.
struct AlbumView: View {
    let route: AlbumRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @State private var model: AlbumModel
    /// On screen - the page on top of its tab.
    @State private var shown = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    /// A download was asked for from this page and hasn't ended: its end is announced while the page is on top.
    @State private var askedHere = false
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
        let download = downloads.album(model.songs)
        let offline = !reachability.online
        let note = OfflineAlbum.note(online: reachability.online, haveSongs: model.album != nil, gone: model.goneButHere,
                                     anyHere: download.hasSongsHere)
        List {
            AlbumHero(model: model, download: download, playable: !playable.isEmpty,
                      play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                .listRowSeparator(.hidden)
                .onAppear { setTitleInBar(false) }
                .onDisappear { setTitleInBar(true) }

            // the album gone from the collection, with songs of it here: said quietly under the hero - it still plays
            if model.goneButHere, let note {
                QuietNote(text: note)
                    .listRowSeparator(.hidden)
            }

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
            } else if model.album == nil, let note {
                // not on this phone, and deadwax out of reach: a state, not a failure - nothing was asked
                QuietNote(text: note)
                    .listRowSeparator(.hidden)
            } else if model.album == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(AlbumPageLines.loading)
                    .listRowSeparator(.hidden)
            }

            if let album = model.album {
                songs(album, download: download, offline: offline || model.goneButHere)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.footer)
                    let here = downloads.here(model.songs)
                    if let line = DownloadWords.footer(here: here.count, of: model.songs.count, bytes: here.bytes) {
                        Text(line)
                    }
                }
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
            // before the •••, so the two sit together as Apple Music's download button sits beside its •••
            ToolbarItem(placement: .topBarTrailing) {
                AlbumDownloadControl(album: model.album, gone: model.goneButHere) { askedHere = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                QueueMenu(request: albumMenu) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(AlbumPageLines.moreForAlbum)
            }
        }
        .task(id: taskKey) {
            model.online = reachability.online
            await model.load(key: taskKey, client: server.client, personal: server.access.hasLibrary, player: player,
                             downloads: downloads)
        }
        .task { await downloads.followProgress() }
        .refreshable {
            // deadwax out of reach: a pull asks whether it is back (the banner says why nothing changes)
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            await model.refresh(client: server.client, player: player, downloads: downloads)
        }
        .onChange(of: reachability.online) { _, online in
            model.online = online
            // back: what the page drew from the phone, or couldn't draw, is asked of deadwax now
            guard online else { return }
            Task {
                await model.load(key: taskKey, client: server.client, personal: server.access.hasLibrary, player: player,
                                 downloads: downloads)
            }
        }
        .onChange(of: download) { _, now in ended(now) }
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

    /// The songs, a disc heading above the first of each disc when the album shows them. `offline`: a song not on this
    /// phone is dimmed (deadwax out of reach, or the album gone from the collection).
    @ViewBuilder private func songs(_ album: Album, download: AlbumDownload, offline: Bool) -> some View {
        let songs = model.songs
        let headings = model.headings
        let heard = player.current?.track
        // the slot on every row where any song has a state, on none where none does
        let slot = songs.contains { downloads.state($0.id) != .none }
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            if headings.indices.contains(index), let heading = headings[index] {
                DiscHeadingRow(heading: heading)
                    .listRowSeparator(.hidden)
            }
            let state = downloads.state(song.id)
            TrackRow(song: song, albumArtist: album.artist, current: PlayingBars.marks(song, heard: heard),
                     playing: player.isPlaying,
                     play: { play(song: song) },
                     menu: QueueMenuRequest(pick: .song(song, of: album), album: album, gone: model.goneButHere),
                     download: state, slot: slot, dimmed: offline && !state.isHere,
                     actions: !downloads.isOpen ? []
                         : model.goneButHere ? downloads.choices(songs: [song], gone: true)
                         : downloads.choices(song: song.id)) { choice in
                act(choice, on: song)
            }
        }
    }

    /// The bar's •••: the whole album, as an album - nil (the ••• dimmed) until its songs are in.
    private var albumMenu: QueueMenuRequest? {
        guard let album = model.album, let pick = model.albumPick else { return nil }
        return QueueMenuRequest(pick: pick, album: album, gone: model.goneButHere)
    }

    /// What Play and Shuffle take: the album's songs - offline, or with the album gone from the collection, its songs on
    /// this phone, in its order.
    private var playable: [Song] {
        guard !reachability.online || model.goneButHere else { return model.songs }
        return OfflineAlbum.playable(model.songs, here: downloads.isHere)
    }

    /// Play, Shuffle and a row's tap: the album's songs, as the album, from `index` (nil with Shuffle: any song
    /// first). In the tap - nothing awaited before the player is called.
    private func play(at index: Int?, shuffle: Bool = false) {
        let songs = playable
        guard let album = model.album, !songs.isEmpty else { return }
        player.play(songs: songs, album: album, at: index, shuffle: shuffle)
    }

    /// A row's tap: the album from that song (among those that play, offline).
    private func play(song: Song) {
        guard let index = playable.firstIndex(where: { $0.id == song.id }) else { return }
        play(at: index)
    }

    /// A row's VoiceOver action - the song's ••• download items.
    private func act(_ choice: DownloadChoice, on song: Song) {
        switch choice {
        case .download: downloads.download(song)
        case .downloadAgain: downloads.tryAgain(song.id)
        case .remove:
            downloads.remove(song.id)
            player.say(DownloadWords.removed(song.title ?? ""))
        }
    }

    /// A download asked for from this page has ended while the page is on top: VoiceOver hears it ("Downloaded Dummy",
    /// "Dummy: 2 songs didn't download"); nothing more is drawn - the control and the line say it.
    private func ended(_ now: AlbumDownload) {
        guard askedHere else { return }
        switch now {
        case .downloaded:
            askedHere = false
            if shown { Notice.announce(DownloadWords.ended(model.name, failed: 0)) }
        case .failed(let count, _):
            askedHere = false
            if shown { Notice.announce(DownloadWords.ended(model.name, failed: count)) }
        case .none:
            askedHere = false
        default:
            break
        }
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

/// A page's own quiet line (3.7): a state in words, not a failure - "This album isn't on this phone - it plays once
/// deadwax is back."
private struct QuietNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
