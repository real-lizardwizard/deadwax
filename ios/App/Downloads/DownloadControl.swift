import DeadwaxCore
import SwiftUI

// The download's marks (notes/ios-specs/phase2-downloads.md 1.2-1.4): one slot, one meaning - filled for here, dotted for
// waiting, the ring for on its way, amber for didn't - wherever a song or an album shows its state; the control in the
// album page's bar; the menus' items; and the Requests board's bar for You > Downloads.

/// The ring (1.3): a quiet track and an accent arc filling from twelve o'clock, round-capped - always determinate, so
/// nothing turns and there is nothing for Reduce Motion to stop; the fraction moves over a quarter second (not at all
/// with Reduce Motion). On the album's control only, Apple Music's stop square in its centre: the one ring a tap acts on.
/// SwiftUI's circular ProgressView is a spinner on iOS whatever its value, so the ring is drawn.
struct DownloadRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 1.5
    /// The control's stop square.
    var stop = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Palette.quiet.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: shown)
            if stop {
                GeometryReader { space in
                    let side = min(space.size.width, space.size.height) / 3
                    RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                        .fill(Palette.accent)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// The one slot a state's mark is drawn in (1.2): an SF Symbol, or the ring in exactly the frame that symbol would
/// take at the font given - so a mark changing from the dotted circle to the ring to the filled one moves nothing
/// beside it, and grows with the text size as the symbols do. Quiet, amber for didn't (the control's own arrow is the
/// accent). Hidden from VoiceOver: what holds it says the state in words.
struct DownloadMark: View {
    let mark: DownloadWords.Mark
    /// The ring's fraction, while downloading.
    var fraction: Double = 0
    var font: Font = .caption
    var lineWidth: CGFloat = 1.5
    /// The control's ring (its stop square) and arrow (the accent).
    var control = false

    var body: some View {
        Group {
            if mark == .ring {
                // the symbol's own frame, unseen, holds the ring's place at this font
                Image(systemName: DownloadWords.Mark.control.rawValue)
                    .hidden()
                    .overlay { DownloadRing(fraction: fraction, lineWidth: lineWidth, stop: control) }
            } else {
                Image(systemName: mark.rawValue)
                    .foregroundStyle(colour)
            }
        }
        .font(font)
        .accessibilityHidden(true)
    }

    private var colour: Color {
        switch mark {
        case .failed: return Palette.amberIcon
        case .control: return Palette.accent
        case .checked: return Palette.held
        default: return Palette.quiet
        }
    }
}

extension DownloadWords.Mark {
    /// A fraction to draw for a mark, from the album's state (the ring's, while downloading).
    static func fraction(_ album: AlbumDownload) -> Double {
        if case .downloading(_, _, let fraction) = album { return fraction }
        return 0
    }

    static func fraction(_ song: SongDownload) -> Double {
        if case .fetching(let fraction) = song { return fraction }
        return 0
    }
}

/// The Requests board's bar (1.4, app.css .app-bar): 6 points tall on the theme's track, a hairline edge and its inset
/// shade, the purple fill - amber, and full, over the storage limit.
struct DownloadBar: View {
    let fraction: Double
    var amber = false

    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = min(max(fraction, 0), 1)
        GeometryReader { space in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.barTrack)
                    // the track's inset shade (--dw-shadow-inset-track)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                Group {
                    if amber {
                        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Palette.amberIcon)
                    } else {
                        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Palette.barFill)
                    }
                }
                .frame(width: max(0, (space.size.width - 2) * shown))
                .padding(1)
                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: shown)
            }
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Palette.barEdge, lineWidth: 0.5))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The album page's download control, in the bar beside its ••• (3.1), drawn from the album's state: the accent arrow
/// downloads at once - every song not on the phone, as the album; it adds, never takes away. Every other state opens a
/// menu from the control itself whose title says in words what the mark only shows (and, for a wait a setting causes,
/// where the setting is), with Remove Download - so a tap meant for the ••• beside it never throws a download away.
/// Dimmed until the album's songs are in. VoiceOver: "Download", its value the album's line ("Downloading, 40 percent"
/// while fetching); the Large Content Viewer, as the bar's own items have.
struct AlbumDownloadControl: View {
    /// The album with its songs - nil while they aren't in (the control dimmed).
    let album: Album?
    /// The album is gone from the collection: there is nothing to fetch, only Remove Download.
    let gone: Bool
    /// The page asked for a download from here (its end is announced while the page is on top).
    let asked: () -> Void

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let songs = album?.song ?? []
        let state = downloads.album(songs)
        let arrow = !gone && {
            switch state {
            case .none, .partial: return true
            default: return false
            }
        }()
        Group {
            if arrow {
                Button {
                    guard let album else { return }
                    downloads.download(album: album)
                    asked()
                } label: {
                    DownloadMark(mark: .control, font: .body, lineWidth: 2, control: true)
                }
            } else {
                Menu {
                    Section(title(state, songs: songs)) {
                        ForEach(items(state, songs: songs), id: \.self) { choice in
                            Button(choice.label, systemImage: choice.symbol, role: choice.isDestructive ? .destructive : nil) {
                                act(choice, songs: songs)
                            }
                        }
                    }
                } label: {
                    DownloadMark(mark: DownloadWords.mark(state, control: true) ?? .control,
                                 fraction: DownloadWords.Mark.fraction(state), font: .body, lineWidth: 2, control: true)
                }
                .menuOrder(.fixed)
            }
        }
        .disabled(album == nil || !downloads.isOpen || (gone && state == .none))
        .accessibilityLabel(DownloadWords.controlLabel)
        .accessibilityValue(DownloadWords.controlValue(state) ?? "")
        .accessibilityAddTraits(isFetching(state) ? .updatesFrequently : [])
        .accessibilityShowsLargeContentViewer {
            Label(DownloadWords.controlLabel, systemImage: largeSymbol(state))
        }
    }

    /// The Large Content Viewer's symbol: the mark, the plain arrow standing in for the ring.
    private func largeSymbol(_ state: AlbumDownload) -> String {
        let mark = DownloadWords.mark(state, control: true) ?? .control
        return mark == .ring ? DownloadWords.Mark.control.rawValue : mark.rawValue
    }

    private func isFetching(_ state: AlbumDownload) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    /// The menu's title: the album's line, and a second line - the setting a wait is for, the first reason a song
    /// didn't download, or the size once downloaded.
    private func title(_ state: AlbumDownload, songs: [Song]) -> String {
        var first: String?
        if case .failed(_, let failure) = state, let song = songs.first(where: { isFailed(downloads.state($0.id)) }) {
            first = DownloadWords.failure(failure, songID: song.id, server: server.address,
                                          admin: server.access.seesDetail).text
        }
        // (slice 3) every song of it a downloaded playlist keeps: no Remove Download here - the title says whose it is
        if case .downloaded = state, let album, let name = downloads.keepingPlaylist(songs, album: album.id) {
            return "\(PlaylistDownloadWords.downloadedWith(name))\n\(Bytes.words(downloads.here(songs).bytes))"
        }
        if case .downloaded = state, let album, downloads.libraryMark(album: album.id) == .withLibrary {
            return AutoDownloadWords.controlMenuTitle(downloads.libraryScope, bytesHere: downloads.here(songs).bytes)
        }
        return DownloadWords.controlMenuTitle(state, limit: downloads.storageLimit,
                                              bytesHere: downloads.here(songs).bytes, firstFailure: first)
    }

    /// The menu's items (2.5): a failed album's Download is "Download Again".
    private func items(_ state: AlbumDownload, songs: [Song]) -> [DownloadChoice] {
        let choices = downloads.choices(songs: songs, gone: gone)
        guard case .failed = state else { return choices }
        return choices.map { $0 == .download ? .downloadAgain : $0 }
    }

    private func act(_ choice: DownloadChoice, songs: [Song]) {
        guard let album else { return }
        switch choice {
        case .download, .downloadAgain:
            downloads.download(album: album)
            asked()
        case .remove:
            downloads.remove(album: album.id)
            player.say(DownloadWords.removed(album.name ?? ""))
        }
    }

    private func isFailed(_ state: SongDownload) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

/// A ••• menu's download section (3.4, 4.1): the items of 2.5 for one song or several, each with its symbol, carried
/// out in the tap through DownloadModel. A failed song's section is headed with why it didn't download. A download
/// never starts the music, so nothing here is on the gesture rule's allowlist. Nothing at all while this phone's
/// downloads can't be used (the store couldn't be read).
struct DownloadMenuSection: View {
    /// One song (a row's •••, Now Playing's) or an album's songs (the bar's •••).
    let songs: [Song]
    /// Several songs are an album, asked for as one (planned whole) - else each song its own.
    var album: Album?
    /// The album is gone from the collection: no Download.
    var gone = false
    /// Removed: what the notice names ("Removed from this phone: Dummy").
    let name: String
    /// Said after a Download - Now Playing's ("Downloading: Roads"); the album page says nothing.
    var downloaded: ((Song) -> String)?

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if downloads.isOpen, !songs.isEmpty {
            // one song's own items - but a song of an album gone from the collection is offered no Download
            let choices = songs.count == 1 && album == nil && !gone
                ? downloads.choices(song: songs[0].id) : downloads.choices(songs: songs, gone: gone, alone: album == nil)
            Section {
                ForEach(choices, id: \.self) { choice in
                    Button(choice.label, systemImage: choice.symbol, role: choice.isDestructive ? .destructive : nil) {
                        act(choice)
                    }
                }
            } header: {
                if songs.count == 1, case .failed(let failure) = downloads.state(songs[0].id) {
                    Text(DownloadWords.failure(failure, songID: songs[0].id, server: server.address,
                                               admin: server.access.seesDetail).text)
                } else if let name = downloads.keepingPlaylist(songs, album: album?.id) {
                    // (slice 3) kept by a downloaded playlist: why there is no Remove Download
                    Text(PlaylistDownloadWords.downloadedWith(name))
                }
            }
        }
    }

    private func act(_ choice: DownloadChoice) {
        switch choice {
        case .download, .downloadAgain:
            if let album {
                downloads.download(album: album)
            } else if songs.count == 1 {
                if choice == .downloadAgain { downloads.tryAgain(songs[0].id) } else { downloads.download(songs[0]) }
            } else {
                downloads.download(songs: songs)
            }
            if songs.count == 1, let words = downloaded?(songs[0]) { player.say(words) }
        case .remove:
            if let album { downloads.remove(album: album.id) } else { downloads.remove(songs: songs.map(\.id)) }
            player.say(DownloadWords.removed(name))
        }
    }
}

// MARK: a playlist's (Phase 4, slice 3)

/// A playlist page's download control, in the bar beside its ••• - the album's (AlbumDownloadControl), for the playlist
/// as one (phase4-library.md 2.5): the accent arrow downloads it at once - kept on this phone, its songs fetched, kept in
/// step as it changes; once downloaded, a menu from the control itself, titled with the playlist's line, with Download
/// Again (its songs that didn't download) and Remove Download (its songs downloaded any other way stay). Dimmed until
/// the playlist's songs are in, and for one gone. None at all for a smart playlist not downloaded (slice 3's review,
/// James: "No Download for them") - its hero says why. VoiceOver: "Download", its value the playlist's line.
struct PlaylistDownloadControl: View {
    /// The playlist with its songs - nil while they aren't in (the control dimmed).
    let answer: PlaylistWithSongs?
    let id: String
    let gone: Bool

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        let state = downloads.playlistState(id)
        Group {
            if let state {
                Menu {
                    PlaylistDownloadMenuSection(answer: answer, id: id, titled: true)
                } label: {
                    DownloadMark(mark: DownloadWords.mark(state, control: true) ?? .control,
                                 fraction: DownloadWords.Mark.fraction(state), font: .body, lineWidth: 2, control: true)
                }
                .menuOrder(.fixed)
            } else if !downloads.playlistIsSmart(id, answer: answer) {
                Button {
                    guard let answer else { return }
                    downloads.download(playlist: answer)
                } label: {
                    DownloadMark(mark: .control, font: .body, lineWidth: 2, control: true)
                }
                .disabled(answer == nil || gone)
            }
        }
        .disabled(!downloads.isOpen)
        .accessibilityLabel(DownloadWords.controlLabel)
        .accessibilityValue(state.flatMap { (shown: AlbumDownload) -> String? in DownloadWords.controlValue(shown) } ?? "")
        .accessibilityAddTraits(isFetching(state) ? .updatesFrequently : [])
        .accessibilityShowsLargeContentViewer {
            Label(DownloadWords.controlLabel, systemImage: DownloadWords.Mark.control.rawValue)
        }
    }

    private func isFetching(_ state: AlbumDownload?) -> Bool {
        if case .downloading? = state { return true }
        return false
    }
}

/// A playlist's download items (PlaylistDownloads.choices) - its control's menu (`titled`: the playlist's line over
/// them) and its bar •••'s second section, carried out in the tap through DownloadModel. A download never starts the
/// music, so nothing here is on the gesture rule's allowlist. Nothing while this phone's downloads can't be used, nor -
/// for Download - before the songs are in, nor for a smart playlist (its choices: none until it is downloaded).
struct PlaylistDownloadMenuSection: View {
    let answer: PlaylistWithSongs?
    let id: String
    /// The control's menu: headed with the playlist's line.
    var titled = false

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player

    init(answer: PlaylistWithSongs?, id: String? = nil, titled: Bool = false) {
        self.answer = answer
        self.id = id ?? answer?.playlist.id ?? ""
        self.titled = titled
    }

    var body: some View {
        if downloads.isOpen, !id.isEmpty {
            let state = downloads.playlistState(id)
            let smart = downloads.playlistIsSmart(id, answer: answer)
            let choices = PlaylistDownloads.choices(state, smart: smart).filter { (choice: DownloadChoice) -> Bool in
                choice != .download || answer != nil
            }
            if !choices.isEmpty {
                Section {
                    ForEach(choices, id: \.self) { choice in
                        Button(choice.label, systemImage: choice.symbol, role: choice.isDestructive ? .destructive : nil) {
                            act(choice)
                        }
                    }
                } header: {
                    if titled, let state { Text(title(state, smart: smart)) }
                }
            }
        }
    }

    /// The control's menu title: the playlist's line, and a second - the setting a wait is for, the first reason a song
    /// didn't download, or the size once downloaded (a smart one's own line over it).
    private func title(_ state: AlbumDownload, smart: Bool) -> String {
        guard let entry = downloads.playlists.entry(id) else { return "" }
        var first: String?
        if case .failed(_, let failure) = state,
           let song = entry.songIDs.first(where: { (songID: String) -> Bool in isFailed(downloads.state(songID)) }) {
            first = DownloadWords.failure(failure, songID: song, server: server.address,
                                          admin: server.access.seesDetail).text
        }
        let bytes = downloads.playlistHere(entry).bytes
        if case .downloaded = state, let line = PlaylistDownloadWords.heroLine(state, smart: smart) {
            return "\(line)\n\(Bytes.words(bytes))"
        }
        return DownloadWords.controlMenuTitle(state, limit: downloads.storageLimit, bytesHere: bytes, firstFailure: first)
    }

    private func act(_ choice: DownloadChoice) {
        let name = answer?.playlist.name ?? downloads.playlists.entry(id)?.name ?? ""
        switch choice {
        case .download:
            guard let answer else { return }
            downloads.download(playlist: answer)
        case .downloadAgain:
            downloads.tryAgain(playlist: id)
        case .remove:
            downloads.remove(playlist: id)
            player.say(DownloadWords.removed(name.isEmpty ? PlayerWords.untitled : name))
        }
    }

    private func isFailed(_ state: SongDownload) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
