import DeadwaxCore
import SwiftUI

/// Top Songs on an artist's page (Last.fm, slice A1 - deadwax-plans/lastfm.md 3.2; notes/ios.md "Last.fm, slice A1"):
/// the heading with See All at its end (more than it shows: the Top Songs page, all ten), its rows (TopSongRow), and
/// "From Last.fm" under them, opening the artist's page on Last.fm beside the app.
///
/// (R6 - notes/ios.md "The redesign, slice R6: an artist") Flat, as iArtist draws a list: the heading a group's
/// (ArtistSectionHead), See All a flat button, each row the tall row on its hairline (ArtistSongFace). The phone's
/// alone since R6: the Mac's artist page (MacArtistPage) draws all ten in a list of its own, with no See All.
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
            ArtistSectionHead(words: LastfmWords.topSongs) {
                if rows.count > TopSongs.shown {
                    Button(LastfmWords.seeAll) {
                        navigation.open(.topSongs(route))
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            ForEach(rows.prefix(TopSongs.shown)) { (row: TopSongs.Row) in
                TopSongRow(row: row, all: rows, name: name, mbid: mbid, opener: opener)
            }
            LastfmCredit(lastfmPage: credit)
        }
    }
}

/// ArtistSectionHead's: .row.grp's words at its foot. Outside the generic view, which can hold no stored static.
private enum ArtistSectionHeadDrawn {
    static let foot: CGFloat = 6     // dw.ph: .row.grp padding-bottom
}

/// (R6) A section's heading on the phone's artist page: iArtist's group row (.row.grp - 38 tall at least, its words at
/// its foot, 15 and semibold in the heading's colour), what trails it at its end (See All, the albums' count) on the
/// words' baseline. A header to VoiceOver. A count at its end (`count`, "16 · 6 yours") is the readout's, in Courier
/// Prime in the third colour, and VoiceOver reads it as `spoken`.
struct ArtistSectionHead<Trailing: View>: View {
    let words: String
    var count: String? = nil
    var spoken: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(words)
                .font(Typeface.subheadline.weight(.semibold))
                .foregroundStyle(DWPalette.head)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .lineLimit(1)
                    .accessibilityLabel(spoken ?? count)
            }
            trailing
        }
        .padding(.bottom, ArtistSectionHeadDrawn.foot)
        .frame(maxWidth: .infinity, minHeight: CGFloat(DWLook.here.groupRowHeight), alignment: .bottomLeading)
    }
}

extension ArtistSectionHead where Trailing == EmptyView {
    /// A heading with a count at its end and nothing else (the albums').
    init(words: String, count: String, spoken: String) {
        self.init(words: words, count: count, spoken: spoken) { EmptyView() }
    }
}

/// "From Last.fm" (the small words): the artist's page on Last.fm, opened beside the app - in the system's browser, so
/// the player plays on - and read as a link, in the accent. With no page that is Last.fm's (LastfmLink), the words
/// alone, in the second colour. (R6) The Mac's artist page passes its own face and space above it; the phone's are
/// the defaults.
struct LastfmCredit: View {
    let lastfmPage: String?
    var font = Typeface.Phone.text(.small)
    var above: CGFloat = 10

    var body: some View {
        Group {
            if let page = LastfmLink.url(lastfmPage) {
                Link(LastfmWords.credit, destination: page)
                    .foregroundStyle(DWPalette.acc)
            } else {
                Text(LastfmWords.credit)
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .font(font)
        .padding(.top, above)
    }
}

/// (R6) A top song's row on the phone's artist page: iArtist's tall row (LibraryListRow's sizes: the cover 44, the
/// title 17 in white over its line 13 in the second colour, 10 from either side, 60 tall at least, growing with the
/// text, 3 lines each at the accessibility sizes), its cover, its title over its line, and the spinner while its album
/// is asked for. The rule under it is the row's (ArtistRowRule), under the ••• too.
struct ArtistSongFace<Cover: View>: View {
    let title: String
    let line: String
    var busy = false
    @ViewBuilder let cover: Cover

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            cover
                .frame(width: CGFloat(LibraryLook.rowCover), height: CGFloat(LibraryLook.rowCover))
                .clipShape(DWCorners.chipShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(line.isEmpty ? " " : line)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            .padding(.horizontal, LibraryLook.rowTextSide)
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView()
                    .accessibilityHidden(true)
            }
        }
        .lookHeight(DWLook.here.tallRowHeight)
        .contentShape(Rectangle())
    }
}

/// The row's hairline: the phone's row rule.
struct ArtistRowRule: View {
    var body: some View {
        DWRule(colour: DWPalette.rowRule)
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
///
/// (R6) One element to VoiceOver, as a song row is (R5's rule): the title and its line; a song you have a button
/// whose action plays, its •••'s Add to Queue and Add to a playlist… its actions.
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

    var body: some View {
        Group {
            switch row.kind {
            case .have(let song, let album):
                have(song, album)
            case .missing:
                missing
            case .waiting:
                face(line: " ", busy: false) { LibraryCover(id: nil, pixels: CoverSize.row) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
            case .unknown:
                // an album of theirs whose songs aren't in hand may have it: never "Not in your library" - dimmed
                face(line: " ", busy: false) { LibraryCover(id: nil, pixels: CoverSize.row) }
                    .opacity(DWPalette.off)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
            }
        }
        .overlay(alignment: .bottom) { ArtistRowRule() }
    }

    // MARK: a song you have

    private func have(_ song: Song, _ album: Album) -> some View {
        let menu = QueueMenuRequest(pick: QueuePick.song(song, of: album), album: album)
        let playable = reachability.online || downloads.isHere(song.id)
        return HStack(spacing: 0) {
            Button {
                play()
            } label: {
                face(line: row.line, busy: false) { LibraryCover(id: album.coverArt, pixels: CoverSize.row) }
                    .opacity(playable ? 1 : DWPalette.off)
            }
            .buttonStyle(.plain)
            .disabled(!playable)
            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(DWPalette.t3)
                    .frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        // one element: its tap plays, the •••'s Add to Queue and Add to a playlist… its actions
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row.line))
        .accessibilityValue(playable ? "" : DownloadWords.notOnDevice(Platform.device))
        .accessibilityAddTraits(playable ? .isButton : [])
        .accessibilityAction {
            if playable { play() }
        }
        .addToQueueAction(menu)
        .addToPlaylistAction(menu)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(busy ? SearchWords.loading : "")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: the row's face

    /// The cover, the title over its line, and - while its album is asked for - the spinner at its end.
    private func face<Cover: View>(line: String, busy: Bool, @ViewBuilder cover: () -> Cover) -> some View {
        ArtistSongFace(title: row.title, line: line, busy: busy, cover: cover)
    }

    /// What VoiceOver hears: the title and its line.
    private func spoken(_ line: String) -> String {
        [row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }
}

/// A song you don't have's cover: blank, with the note.
private struct NoteCover: View {
    var body: some View {
        GeometryReader { (room: GeometryProxy) in
            ZStack {
                Palette.coverEmpty
                Image(systemName: "music.note")
                    .font(Typeface.symbol(size: room.size.width * 0.4, weight: .regular))
                    .foregroundStyle(DWPalette.t2)
            }
        }
    }
}
