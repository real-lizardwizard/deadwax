import DeadwaxCore
import SwiftUI

/// A playlist's page on the Mac (the redesign, slice R5 - Playlist.dc.html; notes/ios.md "The redesign, slice R5: an
/// album, Playlists, a playlist"), drawn in PlaylistView's place out of Edit by MacAlbum.page(for:): PlaylistView keeps
/// the page's model, every ask and write, Edit and leaving, and hands this its actions (PlaylistDesk).
///
/// - The toolbar (.bar): Play (the accent's), Shuffle, the groove, Add to Queue, Add to a playlist…, Download (the
///   playlist's control in words), and Edit at its end for a playlist that is yours to edit. Every one an existing call:
///   Play and Shuffle PlaylistView's own, Add to Queue and Add to a playlist… the right-click's, Download the playlist
///   control's (PlaylistDownloadMenuSection), Edit PlaylistView's form - the order, the name, the description, sharing
///   and Delete playlist, all saved with Done. Narrower than it fits, it folds: Play, Shuffle, Edit and the playlist's
///   •••. The drawing's ‹ Playlists is the window's own back; Play next is the one Add to Queue; Add songs… is left out
///   (songs are added from their own •••, Add to a playlist…); Edit order, Rename… and Delete… are the one Edit.
/// - The hero: the cover (96), the name (.h1), whose it is and when it last changed ("Yours · changed today",
///   MacAlbumFacts), why there is no Edit, its description, its songs and length, its download.
/// - The songs (MacColumnList): #, Title, Album, Length. A click selects, a double-click or Return plays the playlist
///   from the row; a right-click is the song's own items. While deadwax can't be reached a song not on this Mac is
///   dimmed and plays nothing.
/// - The status bar: the songs, their length, and their size when every song says its own.
struct MacPlaylistPage: View {
    let desk: PlaylistDesk

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var selected: String?
    /// The day "changed today" is read against: taken again at a day's change.
    @State private var now = ArtistTotals.now()

    /// The columns (Playlist.dc.html's .cols): Title takes what the others leave.
    static let columns = [
        MacListColumn(title: MacAlbumFacts.Words.number, width: .fixed(46)),
        MacListColumn(title: MacAlbumFacts.Words.title, width: .flexible),
        MacListColumn(title: MacAlbumFacts.Words.album, width: .fixed(190)),
        MacListColumn(title: MacAlbumFacts.Words.length, width: .fixed(66)),
    ]

    /// The drawing's numbers: the hero 18 down, 22 in and 16 above the list, its cover 96 and 16 from the words, the
    /// chips 10 under the line; the list edge to edge under it, on the frame's rule.
    private enum Drawn {
        static let top: CGFloat = 18
        static let side: CGFloat = 22
        static let below: CGFloat = 16
        static let cover: CGFloat = 96
        static let coverGap: CGFloat = 16
        static let chipsAbove: CGFloat = 10
    }

    /// One row: its place in the playlist (a song twice is two rows), the song.
    struct Line: Identifiable {
        let index: Int
        let song: Song

        var id: String { "\(index)|\(song.id)" }
    }

    private enum Fit {
        case full, folded
    }

    private var id: String { desk.model.route.id }

    var body: some View {
        let model = desk.model
        MacPage {
            ViewThatFits(in: .horizontal) {
                tools(.full)
                tools(.folded)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Drawn.below) {
                    hero
                    notes
                }
                .padding(EdgeInsets(top: Drawn.top, leading: Drawn.side, bottom: Drawn.below, trailing: Drawn.side))
                songs(model)
            }
        }
        .macStatus(MacStatusItems.Items(leading: MacAlbumFacts.status(model.songs)))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear { now = ArtistTotals.now() }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ fit: Fit) -> some View {
        HStack(spacing: 6) {
            Button(action: desk.play) {
                HStack(spacing: 6) {
                    SharpSymbol(.play)
                    Text(PlaylistWords.play)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(desk.playable.isEmpty || desk.model.gone)
            Button(ShuffleWords.shuffle, action: desk.shuffle)
                .buttonStyle(DWButtonStyle())
                .disabled(desk.playable.isEmpty || desk.model.gone)
            if fit == .full {
                MacGroove()
                Button(AddToQueue.words) { addToQueue() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(queuePick == nil)
                Button(PlaylistWords.addToAPlaylistRow) { addToPlaylist() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(!playlistable)
                download
            }
            Spacer(minLength: 0)
            if let edit = desk.edit {
                Button(PlaylistWords.edit, action: edit)
                    .buttonStyle(DWButtonStyle())
                    .disabled(!desk.canEdit)
            }
            if fit == .folded {
                QueueMenu(request: desk.menu) {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(DWButtonStyle())
                .fixedSize()
                .accessibilityLabel(PlaylistWords.moreForPlaylist)
            }
        }
    }

    private var queuePick: QueuePick<Song>? {
        guard let request = desk.menu else { return nil }
        return AddToQueue.pick(request.pick, online: reachability.online, gone: request.gone, here: downloads.isHere)
    }

    /// Add to Queue: the playlist's songs after what is queued, each with its own album - the right-click's call.
    private func addToQueue() {
        guard let pick = queuePick else { return }
        player.addToQueue(pick, album: desk.menu?.album)
    }

    private var playlistable: Bool {
        guard let request = desk.menu else { return false }
        return reachability.online && !request.gone && !request.pick.tracks.isEmpty
    }

    private func addToPlaylist() {
        guard playlistable, let request = desk.menu else { return }
        navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))
    }

    /// Download, the playlist's control in words: not downloaded, a click downloads it (kept on this Mac, kept in step);
    /// downloaded, a pop-up of the control's own items headed with its line. None for a smart playlist not downloaded
    /// (its hero says why).
    @ViewBuilder private var download: some View {
        let answer = desk.model.answer
        if let state = downloads.playlistState(id) {
            DWPopUp(words: DownloadWords.controlLabel) {
                PlaylistDownloadMenuSection(answer: answer, id: id, titled: true)
            }
            .accessibilityValue(DownloadWords.controlValue(state, device: Platform.device) ?? "")
        } else if !downloads.playlistIsSmart(id, answer: answer) {
            Button(DownloadWords.controlLabel) {
                guard let answer else { return }
                downloads.download(playlist: answer)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(answer == nil || desk.model.gone || !downloads.isOpen)
        }
    }

    // MARK: the hero

    private var hero: some View {
        let model = desk.model
        // a right-click on it: the playlist's own •••, as its row's
        let menu = desk.menu
        let playlist = model.playlist
        let songs = model.songs
        let download = model.gone ? nil : downloads.playlistState(id)
        let smart = downloads.playlistIsSmart(id, answer: model.answer)
        return HStack(alignment: .top, spacing: Drawn.coverGap) {
            PlaylistCover(id: playlist?.coverArt, side: Drawn.cover, pixels: CoverSize.hero)
                .frame(width: Drawn.cover, height: Drawn.cover)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(Typeface.Mac.text(.h1).weight(.bold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if let playlist {
                    Text(MacAlbumFacts.playlistLine(playlist, now: now))
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                }
                if let answer = model.answer, !model.gone,
                   let words = PlaylistRules.readOnlyWords(answer.playlist, songs: answer.songs.count) {
                    quiet(words)
                }
                if let comment = playlist?.comment, !comment.isEmpty {
                    Text(comment)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // the drawing's chips: its songs, its length, and on this Mac once all of it is here
                if model.answer != nil, !model.gone {
                    HStack(spacing: 6) {
                        DWChip(words: ArtistTotals.songs(songs.count))
                        let length = MacAlbumFacts.length(PlaylistRules.total(songs))
                        if !length.isEmpty { DWChip(words: length) }
                        if case .downloaded? = download {
                            DWChip(words: MacAlbumFacts.Words.onDevice(Platform.device), tone: .good)
                        }
                    }
                    .padding(.top, Drawn.chipsAbove - 4)
                }
                // its download's line (one under way, one that didn't finish; a smart one's, why there is none)
                if !model.gone, let words = PlaylistDownloadWords.heroLine(download, smart: smart, device: Platform.device) {
                    quiet(words)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    private func quiet(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Changed in another app while it was being edited, and the songs not listed just now: said under the hero.
    @ViewBuilder private var notes: some View {
        let model = desk.model
        if let note = model.note {
            ErrorNote(text: note)
        }
        if model.hidden > 0 {
            quiet(PlaylistRules.hiddenWords(model.hidden))
        }
    }

    /// The songs - or, without them, the page's state as the phone's says it: gone, failed (Try again), offline,
    /// loading, empty.
    @ViewBuilder private func songs(_ model: PlaylistPageModel) -> some View {
        let online = reachability.online
        if model.gone {
            ErrorNote(text: PlaylistWords.playlistGone)
                .padding(.horizontal, Drawn.side)
        } else if model.answer == nil {
            Group {
                if let failure = model.failure {
                    OpenFailedNote(failure: failure, retry: desk.retry)
                } else if !online {
                    Text(PlaylistWords.offlinePage)
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.t2)
                } else {
                    ProgressView()
                        .accessibilityLabel(PlaylistWords.loading)
                }
            }
            .padding(.horizontal, Drawn.side)
        } else {
            if online, let failure = model.failure {
                RefreshFailedNote(failure: failure)
                    .padding(.horizontal, Drawn.side)
                    .padding(.bottom, 8)
            }
            if model.songs.isEmpty {
                Text(PlaylistWords.playlistEmpty)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
                    .padding(.horizontal, Drawn.side)
            } else {
                list(model.songs)
            }
        }
    }

    private func list(_ songs: [Song]) -> some View {
        let lines = songs.enumerated().map { (index: Int, song: Song) -> Line in Line(index: index, song: song) }
        let heard = player.current?.track
        // edge to edge to the page's foot, the frame's rule along its top (.cols' border-top)
        return MacColumnList(columns: Self.columns, rows: lines, selected: $selected,
                             open: { (line: Line) -> Void in open(line) },
                             menu: { (line: Line) -> SongRightClick in SongRightClick(menu: desk.row(line.song)) }
        ) { (line: Line, column: Int) in
            cell(line, column, heard: heard)
        }
        .overlay(alignment: .top) { DWRule(colour: DWPalette.frame) }
    }

    private func dimmed(_ song: Song) -> Bool {
        desk.offline && !downloads.state(song.id).isHere
    }

    @ViewBuilder private func cell(_ line: Line, _ column: Int, heard: QueueTrack?) -> some View {
        let song = line.song
        Group {
            switch column {
            case 0:
                if PlayingBars.marks(song, heard: heard) {
                    SharpSymbol(.play)
                        .foregroundStyle(DWPalette.acc)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(LibraryColumnWords.playing)
                } else {
                    Text(String(line.index + 1))
                        .font(Typeface.Mac.mono(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            case 1:
                HStack(spacing: 6) {
                    Text(song.title ?? "")
                    if let artist = song.artist, !artist.isEmpty {
                        Text(artist)
                            .foregroundStyle(DWPalette.t2)
                    }
                    let state = downloads.state(song.id)
                    if let mark = DownloadWords.mark(state) {
                        DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(state),
                                     font: Typeface.symbol(.caption2))
                            .fixedSize()
                    }
                }
            case 2:
                Text(song.album ?? "")
                    .foregroundStyle(DWPalette.t2)
            default:
                Text(Format.trackTime(song.duration))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .opacity(dimmed(song) ? DWPalette.off : 1)
    }

    /// A row opened - a double-click, Return, VoiceOver's action: the playlist from that row.
    private func open(_ line: Line) {
        guard !dimmed(line.song) else { return }
        desk.playRow(line.index)
    }
}
