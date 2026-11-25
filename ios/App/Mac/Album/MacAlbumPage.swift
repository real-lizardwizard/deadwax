import DeadwaxCore
import SwiftUI

/// An album's page on the Mac (the redesign, slice R5 - Album.dc.html; notes/ios.md "The redesign, slice R5: an album,
/// Playlists, a playlist"), drawn in AlbumView's place by MacAlbum.page(for:): AlbumView keeps the page's model and
/// every load, wait, level warmed and let go, New mark seen and announcement, and hands this its actions (AlbumDesk) -
/// so the Mac draws and does nothing the phone's page doesn't.
///
/// - The toolbar (.bar): Play (the accent's), Shuffle, the groove, Add to Queue, Add to a playlist…, Download, then
///   Edit at its end for whoever may edit the album. Every one an existing call: Play and Shuffle AlbumView's own,
///   Add to Queue and Add to a playlist… the right-click's (QueueMenuItems), Download the album's control's
///   (AlbumDownloadMenu), Edit the •••'s Edit album. It fits every page down to the one beside the side panel's column;
///   should it ever not (a long download state in the pop-up), it folds: Play, Shuffle and the album's ••• (the
///   right-click's items, Edit album among them). The drawing's ‹ Albums is the window's own back; Play next and
///   Play last are the one Add to Queue (James, 16 Nov - the right-click offers that alone); Other pressings and Pin are
///   left out (the app has no pressings to offer, and no pin on the Mac yet).
/// - The hero: the cover (132), the title (.h1), the artist in the accent - a link to their page - the meta line, when
///   it was last played and how often ("Played yesterday · 12 times", MacAlbumFacts - Albums' Info says the same,
///   check 555), the chips (whose it is, and on this Mac), the mine block's Add or Remove, and the quiet lines. A
///   right-click on it is the album's ••• (as a tile's).
/// - The songs (MacColumnList): #, Title, Plays, Length, •••. A click selects, a double-click or Return plays the album
///   from the song; a right-click and the row's ••• are the song's own items. The song playing has the accent's ▶ in
///   its #. (R5's review) A disc's heading row above its first song wherever the phone's page draws one - more than one
///   disc, or a disc with a title - carrying its title (MacAlbumFacts.songLines); # is the song's own track number. A
///   nil play count is a blank, never 0. While deadwax can't be reached (or the album is gone), a song not on this Mac
///   is dimmed. The box is as tall as its rows, scrolling inside once there isn't room.
/// - Properties (.group): Released, Added, Format, Size (every disc's, or none), and Album info's Folder or Folders -
///   whenever Album info would show it (AlbumInfo.server, for whoever may see folders): the id bridge's answer, asked
///   here when the page's model hasn't it (with logins off, or break-glass, the model asks it for nobody's library).
/// - The status bar: the songs, their length and their size.
/// - "Yesterday" is the calendar's, read against a `now` taken again at a day's change.
struct MacAlbumPage: View {
    let desk: AlbumDesk

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    /// The song row selected, by its place and id.
    @State private var selected: String?
    /// The day "Played yesterday" is read against: taken again at a day's change (midnight crossed).
    @State private var now = ArtistTotals.now()
    /// (R5's review) The id bridge's answer for Properties' folder, asked here when the page's model asked none.
    @State private var bridged: StoreAlbum?

    /// The columns (Album.dc.html's .cols): Title takes what the others leave.
    static let columns = [
        MacListColumn(title: MacAlbumFacts.Words.number, width: .fixed(46)),
        MacListColumn(title: MacAlbumFacts.Words.title, width: .flexible),
        MacListColumn(title: MacAlbumFacts.Words.plays, width: .fixed(70)),
        MacListColumn(title: MacAlbumFacts.Words.length, width: .fixed(66)),
        MacListColumn(title: MacAlbumFacts.Words.more, width: .fixed(44)),
    ]

    /// The drawing's numbers: the page 20 down and 22 in, the cover 132 and 18 from the words, the songs' box 18 under
    /// the hero, Properties 22 under the box with its columns 28 apart and their labels 70 and 60 wide.
    private enum Drawn {
        static let top: CGFloat = 20
        static let side: CGFloat = 22
        static let cover: CGFloat = 132
        static let coverGap: CGFloat = 18
        static let boxAbove: CGFloat = 18
        static let propertiesAbove: CGFloat = 22
        static let propertiesGap: CGFloat = 28
        static let leftLabel: CGFloat = 70
        static let rightLabel: CGFloat = 60
        static let bottom: CGFloat = 16
    }

    /// One song of the list: its place on the album, the song.
    struct Line: Identifiable {
        let index: Int
        let song: Song

        var id: String { MacAlbumFacts.lineID(index, song) }
    }

    /// What the folder ask waits on: who, which album, deadwax in reach, the model's own answer.
    private struct BridgeKey: Equatable {
        let person: Int
        let album: String
        let online: Bool
        let modelHasIt: Bool
    }

    /// The toolbar as drawn, or folded.
    private enum Fit {
        case full, folded
    }

    var body: some View {
        let model = desk.model
        MacPage {
            ViewThatFits(in: .horizontal) {
                tools(.full)
                tools(.folded)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if let album = model.album {
                    songs(album)
                        .padding(.top, Drawn.boxAbove)
                        .layoutPriority(1)
                    properties(album)
                } else {
                    waiting
                        .padding(.top, Drawn.boxAbove)
                }
            }
            .padding(EdgeInsets(top: Drawn.top, leading: Drawn.side, bottom: Drawn.bottom, trailing: Drawn.side))
        }
        .macStatus(MacStatusItems.Items(leading: MacAlbumFacts.status(model.songs)))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear { now = ArtistTotals.now() }
        .task(id: BridgeKey(person: server.person, album: model.route.id, online: reachability.online,
                            modelHasIt: model.store != nil)) {
            await bridge()
        }
    }

    /// (R5's review) Properties' folder as Album info has it: the id bridge's answer - the model's, or asked here (the
    /// call Album info asks, AlbumInfoAsk's) for whoever may see folders while the model has none. Nothing asked for
    /// anyone else, or while deadwax can't be reached.
    private func bridge() async {
        let model = desk.model
        guard model.store == nil, server.access.isAdmin, reachability.online, let client = server.client else { return }
        let answer = try? await client.storeAlbum(navidromeID: model.route.id)
        guard !Task.isCancelled else { return }
        bridged = answer
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
            .disabled(desk.playable.isEmpty)
            Button(ShuffleWords.shuffle, action: desk.shuffle)
                .buttonStyle(DWButtonStyle())
                .disabled(desk.playable.isEmpty)
            switch fit {
            case .full:
                MacGroove()
                Button(AddToQueue.words) { addToQueue() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(queuePick == nil)
                Button(PlaylistWords.addToAPlaylistRow) { addToPlaylist() }
                    .buttonStyle(DWButtonStyle())
                    .disabled(!playlistable)
                download
                Spacer(minLength: 0)
                if Managing.albumEdit(server.access.permissions).shown {
                    Button(PlaylistWords.edit) { desk.edit?() }
                        .buttonStyle(DWButtonStyle())
                        .disabled(desk.edit == nil)
                        .accessibilityLabel(EditWords.menuItem)
                }
            case .folded:
                Spacer(minLength: 0)
                // the album's ••• - the right-click's items, Download and Edit album among them
                QueueMenu(request: desk.menu) {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(DWButtonStyle())
                .fixedSize()
                .accessibilityLabel(AlbumPageLines.moreForAlbum)
            }
        }
    }

    /// Add to Queue's songs, as the right-click has them (AddToQueue.pick) - nil, the button dimmed, without.
    private var queuePick: QueuePick<Song>? {
        guard let request = desk.menu else { return nil }
        return AddToQueue.pick(request.pick, online: reachability.online, gone: request.gone, here: downloads.isHere)
    }

    /// Add to Queue: the album after what is queued - the right-click's call.
    private func addToQueue() {
        guard let pick = queuePick else { return }
        player.addToQueue(pick, album: desk.menu?.album)
    }

    /// Add to a playlist… is offered as the right-click offers it: deadwax in reach, the album in the collection.
    private var playlistable: Bool {
        guard let request = desk.menu else { return false }
        return reachability.online && !request.gone && !request.pick.tracks.isEmpty
    }

    /// Add to a playlist…: the picker, with the album's songs - the right-click's call.
    private func addToPlaylist() {
        guard playlistable, let request = desk.menu else { return }
        navigation.playlistPick = PlaylistPickRequest(PlaylistPick(request.pick))
    }

    /// Download: the album's control in words. With nothing of it here (or a part), a click downloads it at once, as
    /// the control's arrow; otherwise a pop-up headed with the download's state, its items the control's own.
    @ViewBuilder private var download: some View {
        let album = desk.model.album
        let songs = desk.model.songs
        let state = desk.download
        let gone = desk.model.goneButHere
        Group {
            if !gone && Self.arrow(state) {
                Button(DownloadWords.controlLabel) {
                    guard let album else { return }
                    downloads.download(album: album)
                    desk.asked()
                }
                .buttonStyle(DWButtonStyle())
            } else {
                DWPopUp(words: DownloadWords.controlLabel) {
                    Section(AlbumDownloadMenu.title(state, songs: songs, album: album, downloads: downloads, server: server)) {
                        ForEach(AlbumDownloadMenu.items(state, songs: songs, gone: gone, downloads: downloads),
                                id: \.self) { (choice: DownloadChoice) in
                            Button(choice.label, systemImage: choice.symbol, role: choice.isDestructive ? .destructive : nil) {
                                act(choice)
                            }
                        }
                    }
                }
            }
        }
        .disabled(album == nil || !downloads.isOpen || (gone && state == .none))
        .accessibilityValue(DownloadWords.controlValue(state, device: Platform.device) ?? "")
    }

    /// The control's arrow states: nothing here, or a part.
    private static func arrow(_ state: AlbumDownload) -> Bool {
        switch state {
        case .none, .partial: return true
        default: return false
        }
    }

    /// A Download pop-up's item, as the control carries it out.
    private func act(_ choice: DownloadChoice) {
        guard let album = desk.model.album else { return }
        switch choice {
        case .download, .downloadAgain:
            downloads.download(album: album)
            desk.asked()
        case .remove:
            downloads.remove(album: album.id)
            player.say(DownloadWords.removed(album.name ?? "", device: Platform.device))
        }
    }

    // MARK: the hero

    private var hero: some View {
        let model = desk.model
        // a right-click on it: the album's own •••, as a tile's
        let menu = desk.menu
        return HStack(alignment: .top, spacing: Drawn.coverGap) {
            CoverImage(id: model.coverArt, size: Drawn.cover)
                .frame(width: Drawn.cover, height: Drawn.cover)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.name)
                    .font(Typeface.Mac.text(.h1).weight(.bold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if !model.artist.isEmpty {
                    artistLine
                        .padding(.top, 4)
                }
                if !model.meta.isEmpty {
                    Text(model.meta)
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                if let album = model.album, let played = MacAlbumFacts.played(album, now: now) {
                    Text(played)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                chips
                    .padding(.top, 10)
                mine
                lines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    /// The artist: a link to their page in the accent (AlbumHero's rule), the accent unlinked while it may still become
    /// one, the second colour once the album named nobody to go to.
    @ViewBuilder private var artistLine: some View {
        let model = desk.model
        let words = Text(model.artist)
            .font(Typeface.Mac.text(.h3))
            .lineLimit(1)
        switch model.artistLink {
        case .link(let id):
            Button {
                navigation.open(.artist(ArtistRoute(id: id, preview: Artist(id: id, name: model.artist))))
            } label: {
                words.foregroundStyle(DWPalette.acc)
            }
            .buttonStyle(.plain)
        case .pending:
            words.foregroundStyle(DWPalette.acc)
        case .plain:
            words.foregroundStyle(DWPalette.t2)
        }
    }

    /// Whose it is (its place held while that's still to come) and how much of it is on this Mac.
    private var chips: some View {
        let model = desk.model
        return HStack(spacing: 6) {
            DWChip(words: model.mine.badge, tone: model.mine.yours == true ? .good : .plain)
                .opacity(model.badgeShown ? 1 : 0)
                .accessibilityHidden(!model.badgeShown)
            if let words = Self.downloadChip(desk.download) {
                DWChip(words: words, tone: Self.downloadTone(desk.download))
            }
        }
    }

    /// The download's chip: "On this Mac" once it is all here, else the album's line ("Downloading - 4 of 12") -
    /// nothing for none.
    private static func downloadChip(_ download: AlbumDownload) -> String? {
        if case .downloaded = download { return MacAlbumFacts.Words.onDevice(Platform.device) }
        return DownloadWords.albumLine(download, device: Platform.device)
    }

    private static func downloadTone(_ download: AlbumDownload) -> DWChip.Tone {
        switch download {
        case .failed: return .caution
        default: return .plain
        }
    }

    /// The mine block's Add to my library or Remove from my library, its line and a refusal - as the phone's page
    /// offers them (logins on, with a library of your own).
    @ViewBuilder private var mine: some View {
        let model = desk.model
        if model.mineBlockShown {
            VStack(alignment: .leading, spacing: 6) {
                if let note = mineLine, !note.isEmpty {
                    Text(note)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityFocused(desk.noteFocused)
                }
                if let action = model.mine.action {
                    Button(Whose.button(action, busy: model.busy)) {
                        if !model.busy { desk.change(action) }
                    }
                    .buttonStyle(DWButtonStyle(kind: action == .add ? .pri : .normal))
                    .opacity(model.busy ? DWPalette.off : 1)
                }
                if let refused = model.refused {
                    ErrorNote(refused)
                }
            }
            .padding(.top, 10)
        }
    }

    /// Whose line - with its download going from this Mac too, while Remove would take it (MineBlock's rule).
    private var mineLine: String? {
        let mine = desk.model.mine
        guard desk.goesToo, mine.action == .remove else { return mine.note }
        return [mine.note, AutoDownloadWords.goesToo(Platform.device)].compactMap { $0 }
            .filter { (line: String) -> Bool in !line.isEmpty }.joined(separator: " ")
    }

    /// The phone page's quiet lines: the album gone from the collection with songs of it here, and what your library
    /// says of it.
    @ViewBuilder private var lines: some View {
        let model = desk.model
        let said = [model.goneButHere ? desk.note : nil, desk.libraryLine].compactMap { $0 }
        ForEach(said, id: \.self) { (line: String) in
            Text(line)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    /// No album to draw yet: its wait, its failure (Try again), or why nothing was asked.
    @ViewBuilder private var waiting: some View {
        let model = desk.model
        if model.empty {
            ErrorNote(text: ErrorWords.albumGone)
        } else if let failure = model.failure {
            let retry = !model.gone
            VStack(alignment: .leading, spacing: 8) {
                ErrorNote(failure, gone: ErrorWords.albumGone, retry: retry)
                if retry {
                    Button(LibraryWords.tryAgain, action: desk.refresh)
                        .buttonStyle(DWButtonStyle())
                }
            }
        } else if let note = desk.note {
            Text(note)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
        } else {
            ProgressView()
                .accessibilityLabel(AlbumPageLines.loading)
        }
    }

    // MARK: the songs

    private func songs(_ album: Album) -> some View {
        let songs = desk.model.songs
        let rows = songs.enumerated().map { (index: Int, song: Song) -> Line in Line(index: index, song: song) }
        // (R5's review) a disc's heading row above its first song, as the phone's page draws its headings
        let drawn = MacAlbumFacts.songLines(songs, headings: desk.model.headings)
        let headings = drawn.count - rows.count
        let heard = player.current?.track
        // the box as tall as its rows, its headings and its edge while there is room, scrolling within it once there
        // isn't - never asked to be shorter than three rows unless it is shorter still
        let tall = CGFloat(MacLook.headerHeight + MacLook.rowHeight * Double(rows.count)
                           + MacLook.groupRowHeight * Double(headings)) + 2
        let least = min(CGFloat(MacLook.headerHeight + MacLook.rowHeight * 3), tall)
        return MacColumnList(columns: Self.columns, rows: rows, lines: drawn, selected: $selected,
                             open: { (line: Line) -> Void in open(line) },
                             menu: { (line: Line) -> SongRightClick in SongRightClick(menu: desk.row(line.song, album)) }
        ) { (line: Line, column: Int) in
            cell(line, column, album: album, heard: heard)
        }
        .frame(minHeight: least, maxHeight: tall)
        .clipShape(DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.frame, lineWidth: 1))
    }

    /// A song not on this Mac while deadwax can't be reached (or the album is gone): dimmed, playing nothing.
    private func dimmed(_ song: Song) -> Bool {
        desk.offline && !downloads.state(song.id).isHere
    }

    @ViewBuilder
    private func cell(_ line: Line, _ column: Int, album: Album, heard: QueueTrack?) -> some View {
        let song = line.song
        Group {
            switch column {
            case 0:
                if PlayingBars.marks(song, heard: heard) {
                    // the song playing: the accent's ▶ in its number's place, read from the player, never a play
                    SharpSymbol(.play)
                        .foregroundStyle(DWPalette.acc)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(LibraryColumnWords.playing)
                } else {
                    // the song's own track number - its disc is the heading row above it
                    Text(AlbumPageLines.number(song))
                        .font(Typeface.Mac.mono(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            case 1:
                HStack(spacing: 6) {
                    Text(song.title ?? "")
                    if let artist = AlbumPageLines.artistShown(song, albumArtist: album.artist) {
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
                Text(MacAlbumFacts.plays(song.playCount))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t3)
            case 3:
                Text(Format.trackTime(song.duration))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            default:
                QueueMenu(request: desk.row(song, album)) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(DWPalette.t3)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
            }
        }
        .opacity(dimmed(song) ? DWPalette.off : 1)
    }

    /// A song opened - a double-click, Return, VoiceOver's action: the album from it, as a row's tap on the phone.
    private func open(_ line: Line) {
        guard !dimmed(line.song) else { return }
        desk.playFrom(line.song)
    }

    // MARK: Properties

    @ViewBuilder private func properties(_ album: Album) -> some View {
        // Album info's own row, by its rule - "Folder" or "Folders" - from the model's bridge answer or this page's
        let folder = AlbumInfo.server(store: desk.model.store ?? bridged, folders: server.access.isAdmin).first
        let facts = MacAlbumFacts.properties(album, songs: desk.model.songs, folder: folder)
        let left: Set<String> = [MacAlbumFacts.Words.released, MacAlbumFacts.Words.added]
        if !facts.isEmpty {
            MacGroupBox(legend: MacAlbumFacts.Words.properties, ground: DWPalette.bg) {
                HStack(alignment: .top, spacing: Drawn.propertiesGap) {
                    factColumn(facts.filter { (fact: MacAlbumFacts.Fact) -> Bool in left.contains(fact.label) },
                               label: Drawn.leftLabel)
                    factColumn(facts.filter { (fact: MacAlbumFacts.Fact) -> Bool in !left.contains(fact.label) },
                               label: Drawn.rightLabel)
                }
            }
            .padding(.top, Drawn.propertiesAbove)
        }
    }

    private func factColumn(_ facts: [MacAlbumFacts.Fact], label: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(facts) { (fact: MacAlbumFacts.Fact) in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(fact.label)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .frame(width: label, alignment: .leading)
                    Text(fact.value)
                        .font(Typeface.Mac.mono(.label))
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A song row's right-click (MacColumnList's `menu`): the song's own ••• items, as its ••• offers them.
struct SongRightClick: ViewModifier {
    let menu: QueueMenuRequest

    func body(content: Content) -> some View {
        content.macContextMenu { QueueMenuItems(request: menu) }
    }
}
