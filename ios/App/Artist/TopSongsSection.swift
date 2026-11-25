import DeadwaxCore
import SwiftUI

/// Top Songs on an artist's page (Last.fm, slice A1 - deadwax-plans/lastfm.md 3.2; notes/ios.md "Last.fm, slice A1"):
/// the heading with See All at its end (more than five: the Top Songs page, all ten), the first five rows
/// (TopSongRow), and "From Last.fm" under them, opening the artist's page on Last.fm beside the app. The same on the
/// iPhone and the Mac at the readable width.
struct TopSongsSection: View {
    /// Every row of the answer's (TopSongs.rows - ten at most): the page shows the first five, and a tap plays from
    /// all of them.
    let rows: [TopSongs.Row]
    let route: ArtistRoute
    let name: String
    let mbid: String?
    let credit: String?
    let opener: TopSongOpener

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(LastfmWords.topSongs)
                    .font(Typeface.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if rows.count > TopSongs.shown {
                    Button(LastfmWords.seeAll) {
                        navigation.open(.topSongs(route))
                    }
                    .font(Typeface.footnote)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 4)
            ForEach(rows.prefix(TopSongs.shown)) { (row: TopSongs.Row) in
                TopSongRow(row: row, all: rows, name: name, mbid: mbid, opener: opener)
            }
            LastfmCredit(lastfmPage: credit)
        }
    }
}

/// "From Last.fm" (footnote): the artist's page on Last.fm, opened beside the app - in the system's browser, so the
/// player plays on - and read as a link. With no page that is Last.fm's (LastfmLink), the words alone.
struct LastfmCredit: View {
    let lastfmPage: String?

    var body: some View {
        Group {
            if let page = LastfmLink.url(lastfmPage) {
                Link(LastfmWords.credit, destination: page)
            } else {
                Text(LastfmWords.credit)
                    .foregroundStyle(Palette.quiet)
            }
        }
        .font(Typeface.footnote)
        .padding(.top, 10)
    }
}

/// One top song: its cover at the rows' size, its title and its line, and - for one you have - its ••• (QueueMenu's
/// song items; on the Mac a right-click gives the same).
///
/// - A SONG YOU HAVE: the album's cover, the library song's own title, "{album} · {year}". A tap plays every top song
///   you have that plays now, in Last.fm's order, from this one (TopSongs.play, PlayerModel.play(playlist:at:)) - in
///   the tap, nothing awaited. While deadwax can't be reached one not on this phone is dimmed and plays nothing. Swiped
///   right it adds the song to the queue, as a song row does (AddToQueueSwipe.swift).
/// - A SONG YOU DON'T HAVE: a blank cover with the note, Last.fm's title, "Not in your library" - or, for the visit,
///   why its album didn't open. A tap spins the row while MusicBrainz is asked (TopSongOpener), and opens the album you
///   don't have. No •••. Offline it does nothing.
/// - WAITING (the albums' songs not all in): Last.fm's title over a blank line, the same height, doing nothing.
/// - MAYBE YOURS (`.unknown` - an album of theirs whose songs aren't in hand: one that didn't load, or offline one not
///   on this device): drawn as a waiting row, dimmed, doing nothing.
struct TopSongRow: View {
    let row: TopSongs.Row
    let all: [TopSongs.Row]
    let name: String
    let mbid: String?
    let opener: TopSongOpener

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            switch row.kind {
            case .have(let song, let album):
                have(song, album)
            case .missing:
                missing
            case .waiting:
                face(line: " ", busy: false) { LibraryCover(id: nil, pixels: CoverSize.row) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.title)
            case .unknown:
                // an album of theirs whose songs aren't in hand may have it: never "Not in your library" - dimmed
                face(line: " ", busy: false) { LibraryCover(id: nil, pixels: CoverSize.row) }
                    .opacity(Palette.off)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.title)
            }
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }

    // MARK: a song you have

    private func have(_ song: Song, _ album: Album) -> some View {
        let menu = QueueMenuRequest(pick: QueuePick.song(song, of: album), album: album)
        let playable = reachability.online || downloads.isHere(song.id)
        return HStack(spacing: 4) {
            Button {
                play()
            } label: {
                face(line: row.line, busy: false) { LibraryCover(id: album.coverArt, pixels: CoverSize.row) }
                    .opacity(playable ? 1 : Palette.off)
            }
            .buttonStyle(.plain)
            .disabled(!playable)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(row.line))
            .accessibilityValue(playable ? "" : DownloadWords.notOnDevice(Platform.device))
            .addToQueueAction(menu)
            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AlbumPageLines.moreForSong(row.title))
        }
        // the page's stack's own padding: the purple runs out to the screen's edge
        .addsToQueue(menu, in: .stack(inset: 16))
        // (the Mac app) the row's ••• on a right-click; nothing on the iPhone
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    /// The tap: the top songs you have that play now, from this one - nothing awaited first (the gesture rule).
    private func play() {
        let online = reachability.online
        guard let plan = TopSongs.play(all, from: row.rank, playable: { (song: Song) -> Bool in
            online || downloads.isHere(song.id)
        }) else { return }
        player.play(playlist: plan.songs, at: plan.at)
    }

    // MARK: a song you don't have

    private var missing: some View {
        let busy = opener.opening == TopSongOpener.key(row.top)
        let line = opener.trouble(row.top) ?? row.line
        return Button {
            opener.open(row.top, mbid: mbid, name: name, client: server.client, online: reachability.online,
                        admin: server.access.seesDetail, navigation: navigation)
        } label: {
            face(line: line, busy: busy) { NoteCover() }
        }
        .buttonStyle(.plain)
        .disabled(!reachability.online || busy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(busy ? SearchWords.loading : "")
    }

    // MARK: the row's face

    /// The cover, the title over its line, and - while its album is asked for - the spinner at its end.
    private func face<Cover: View>(line: String, busy: Bool, @ViewBuilder cover: () -> Cover) -> some View {
        HStack(spacing: 12) {
            cover()
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(Corners.artShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(line.isEmpty ? " " : line)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView()
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// What VoiceOver hears: the title and its line.
    private func spoken(_ line: String) -> String {
        [row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }
}

/// A song you don't have's cover: blank, with the note.
private struct NoteCover: View {
    var body: some View {
        ZStack {
            Palette.coverEmpty
            Image(systemName: "music.note")
                .font(Typeface.symbol(size: LibraryRow.cover * 0.4, weight: .regular))
                .foregroundStyle(Palette.quiet)
        }
    }
}
