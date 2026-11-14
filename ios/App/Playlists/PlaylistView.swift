import DeadwaxCore
import SwiftUI

/// One playlist's page (Phase 4, phase4-library.md 3.3; the web's app/PlaylistPage.tsx), laid out as an album's page:
/// Navidrome's 2x2 mosaic, the name, whose it is, why there is no Edit (when there is none), its description, the count
/// and length, Play and Shuffle; the songs not listed just now; the songs, each with its own cover; the footer. The bar's
/// ••• is the whole playlist's Play Next and Play Last.
///
/// PLAYING is PlayerModel.play(playlist:) with the songs in hand - from Play, Shuffle and a row's tap, in the tap,
/// nothing awaited first (the gesture rule): each song with its own album, at the songs level, the albums its songs are
/// on remembered first (PlaylistPlay: stubs, an album held whole kept as it is). A row's ••• is the song's own Play
/// Next and Play Last and its download items; the bar's has no download items until a playlist downloads as one
/// (slice 3, question 7).
///
/// ASKED as it opens (PlaylistPageModel) - drawn at once from the answer kept for it (PlaylistsModel), else the hero
/// from the row that opened it - and again each time it shows, the app coming back to the front included; a refresh that fails keeps what is drawn and says so;
/// a 404 says it has gone; nothing drawn and the first ask failing: why, and Try again. While deadwax can't be reached
/// nothing is asked: what is in hand draws, the songs not on this phone dimmed, Play and Shuffle taking those that are.
/// Edit, Delete and Add are slice 2's; Download a playlist slice 3's.
struct PlaylistView: View {
    let route: PlaylistRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PlaylistPageModel
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false

    init(route: PlaylistRoute) {
        self.route = route
        _model = State(initialValue: PlaylistPageModel(route: route))
    }

    /// Who and which playlist.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    var body: some View {
        let online = reachability.online
        let songs = model.songs
        List {
            PlaylistHero(model: model, playable: !playable.isEmpty,
                         play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                .listRowSeparator(.hidden)
                .onAppear { setTitleInBar(false) }
                .onDisappear { setTitleInBar(true) }

            if model.hidden > 0 {
                QuietLine(text: PlaylistRules.hiddenWords(model.hidden))
                    .listRowSeparator(.hidden)
            }

            if model.gone {
                ErrorNote(text: PlaylistWords.playlistGone)
                    .listRowSeparator(.hidden)
            } else if model.answer == nil {
                if let failure = model.failure {
                    OpenFailedNote(failure: failure) {
                        Task { await model.retry(client: server.client, playlists: playlists) }
                    }
                    .listRowSeparator(.hidden)
                } else if !online {
                    QuietLine(text: PlaylistWords.offlinePage)
                        .listRowSeparator(.hidden)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(PlaylistWords.loading)
                        .listRowSeparator(.hidden)
                }
            } else {
                if online, let failure = model.failure {
                    RefreshFailedNote(failure: failure)
                        .listRowSeparator(.hidden)
                }
                if songs.isEmpty {
                    QuietLine(text: PlaylistWords.playlistEmptyNow)
                        .listRowSeparator(.hidden)
                } else {
                    rows(songs, offline: !online)
                    Text(PlaylistRules.songsLine(songs.count, seconds: PlaylistRules.total(songs)))
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .listRowSeparator(.hidden, edges: .bottom)
                }
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
                QueueMenu(request: playlistMenu) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(PlaylistWords.moreForPlaylist)
            }
        }
        .task(id: taskKey) {
            model.online = reachability.online
            await model.load(key: taskKey, client: server.client, playlists: playlists)
        }
        .task { await downloads.followProgress() }
        .refreshable {
            guard reachability.online else {
                reachability.tryNow()
                return
            }
            await model.load(key: taskKey, client: server.client, playlists: playlists)
        }
        .onChange(of: reachability.online) { _, online in
            model.online = online
            // back: the playlist asked of deadwax now
            guard online else { return }
            Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
        }
        .onChange(of: scenePhase) { _, phase in
            // the app back in front is the page shown again (the web's): the playlist asked again
            guard phase == .active, reachability.online else { return }
            Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
        }
    }

    /// The songs: Navidrome's own, as they are - a song twice is two rows. `offline`: a song not on this phone is dimmed.
    @ViewBuilder private func rows(_ songs: [Song], offline: Bool) -> some View {
        let heard = player.current?.track
        // the slot on every row where any song has a state, on none where none does
        let slot = songs.contains { downloads.state($0.id) != .none }
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            let state = downloads.state(song.id)
            PlaylistSongRow(song: song, current: PlayingBars.marks(song, heard: heard), playing: player.isPlaying,
                            play: { play(row: index) },
                            menu: QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil),
                            download: state, slot: slot, dimmed: offline && !state.isHere,
                            actions: downloads.isOpen ? downloads.choices(song: song.id) : []) { choice in
                act(choice, on: song)
            }
        }
    }

    /// The bar's •••: the whole playlist, as songs - nil (the ••• dimmed) until its songs are in, and once gone.
    private var playlistMenu: QueueMenuRequest? {
        guard !model.gone, let pick = PlaylistPlay.pick(name: model.name, songs: model.songs) else { return nil }
        return QueueMenuRequest(pick: pick, album: nil, offersDownload: false)
    }

    /// What Play and Shuffle take: the songs - offline, those on this phone, in the playlist's order.
    private var playable: [Song] {
        guard !reachability.online else { return model.songs }
        return OfflineAlbum.playable(model.songs, here: downloads.isHere)
    }

    /// Play, Shuffle: the songs, from `index` (nil with Shuffle: any song first). In the tap - nothing awaited before
    /// the player is called.
    private func play(at index: Int?, shuffle: Bool = false) {
        let songs = playable
        guard !songs.isEmpty else { return }
        player.play(playlist: songs, at: index, shuffle: shuffle)
    }

    /// A row's tap: the playlist from that row - offline, from its place among the songs on this phone (a song twice
    /// is two rows, so its place is counted, not looked up by id).
    private func play(row: Int) {
        let songs = model.songs
        guard songs.indices.contains(row) else { return }
        if reachability.online {
            play(at: row)
            return
        }
        guard let start = PlaylistPlay.offlineStart(row: row, songs: songs, here: downloads.isHere) else { return }
        play(at: start)
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

    private func setTitleInBar(_ shown: Bool) {
        guard titleInBar != shown else { return }
        withAnimation(.easeInOut(duration: 0.2)) { titleInBar = shown }
    }
}

/// The top of a playlist's page (PlaylistPage.tsx's hero): the mosaic at the hero's size - or the playlist mark - the
/// name (two lines, a step smaller over 60 letters), whose it is, why there is no Edit, the description, the count and
/// length, and Play and Shuffle, live once there are songs to play. Drawn at once from the row that opened the page.
private struct PlaylistHero: View {
    let model: PlaylistPageModel
    let playable: Bool
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        let playlist = model.playlist
        let songs = model.songs
        VStack(spacing: 0) {
            PlaylistCover(id: playlist?.coverArt, side: AlbumHero.coverSide, pixels: CoverSize.hero, corner: 10)
                .frame(maxWidth: AlbumHero.coverSide)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)

            Text(model.name)
                .font(Format.isLongTitle(model.name) ? .title3.bold() : .title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            if let playlist {
                Text(PlaylistRules.ownerLine(playlist))
                    .font(.title3)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 2)
            }

            // why there is no Edit (somebody else's, a file's, too many songs) - known once the songs are in
            if let answer = model.answer, !model.gone,
               let words = PlaylistRules.readOnlyWords(answer.playlist, songs: answer.songs.count) {
                Text(words)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let comment = playlist?.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // the count holds its line while the songs come, so nothing below moves as it fills
            let line = model.answer != nil && !model.gone
                ? PlaylistRules.songsLine(songs.count, seconds: PlaylistRules.total(songs)) : ""
            Text(line.isEmpty ? " " : line)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .padding(.top, 6)
                .accessibilityHidden(line.isEmpty)

            PlayButtons(enabled: playable && !model.gone, play: play, shuffle: shuffle)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One song of a playlist (PlaylistPage.tsx's track row): the song's own cover, with the playing bars over it for the
/// song the player has (still while paused); its title; its artist and album; the download slot (as an album's rows:
/// on every row where any song has a state); its time; its ••• ("More for Roads"). A tap plays the playlist from it.
/// VoiceOver reads it as one: "Roads, Portishead · Dummy, Downloaded, 5:04" - "playing" or "paused" for the song the
/// player has - with the song's download items as its actions.
private struct PlaylistSongRow: View {
    let song: Song
    let current: Bool
    let playing: Bool
    let play: () -> Void
    let menu: QueueMenuRequest
    var download: SongDownload = .none
    var slot = false
    var dimmed = false
    var actions: [DownloadChoice] = []
    var act: (DownloadChoice) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The cover's side: as the Library's rows.
    private static let cover: CGFloat = LibraryRow.cover

    var body: some View {
        let line = PlaylistRules.songLine(song)
        HStack(spacing: 4) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ZStack {
                        LibraryCover(id: song.coverArt, pixels: CoverSize.row)
                            .frame(width: Self.cover, height: Self.cover)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if current {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.black.opacity(0.45))
                                .frame(width: Self.cover, height: Self.cover)
                            Image(systemName: "waveform")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title ?? "")
                            .foregroundStyle(current ? Palette.accent : Color.primary)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if !line.isEmpty {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    if slot { stateSlot }
                    Text(Format.trackTime(song.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .opacity(dimmed ? Palette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(line))
            .accessibilityActions {
                ForEach(actions, id: \.self) { choice in
                    Button(choice.label) { act(choice) }
                }
            }

            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
        }
    }

    /// The row as VoiceOver reads it: the title, playing or paused, the line, the download state, the time.
    private func spoken(_ line: String) -> String {
        var parts = [song.title ?? ""]
        if current { parts.append(PlayingBars.label(paused: !playing)) }
        if !line.isEmpty { parts.append(line) }
        let state: String? = dimmed ? DownloadWords.notOnPhone : DownloadWords.songLine(download)
        if let state { parts.append(state) }
        let time = Format.trackTime(song.duration)
        if !time.isEmpty { parts.append(time) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The one slot, as an album row's: the song's mark, or the room for one held.
    @ViewBuilder private var stateSlot: some View {
        ZStack {
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: .caption)
            } else {
                DownloadMark(mark: .downloaded, font: .caption).hidden()
            }
        }
        .accessibilityHidden(true)
    }
}

/// A page's quiet line: a state in words, not a failure.
private struct QuietLine: View {
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

/// "Couldn't open this playlist. <why>" and Try again - nothing in hand and the first ask failed.
private struct OpenFailedNote: View {
    let failure: any Error
    let retry: () -> Void

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: true)
        VStack(alignment: .leading, spacing: 8) {
            ErrorNote(text: PlaylistWords.openFailed(line.said), detail: line.detail)
            Button(PlaylistWords.tryAgain, action: retry)
        }
        .padding(.vertical, 4)
    }
}

/// "Couldn't update this playlist - showing it as it was. <why>" - a refresh that failed, what was drawn kept.
private struct RefreshFailedNote: View {
    let failure: any Error

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: false)
        ErrorNote(text: PlaylistWords.refreshFailed(line.said), detail: line.detail)
            .padding(.vertical, 4)
    }
}
