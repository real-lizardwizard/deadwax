import DeadwaxCore
import SwiftUI

/// The phone's album and playlist pages as iAlbum.dc.html and iPlaylist.dc.html draw them (the redesign, slice R5 -
/// notes/ios.md "The redesign, slice R5: an album, Playlists, a playlist"): every number the drawings' own inline
/// style (`drawn:`) or dw.css's phone rules (`dw.ph:`), held to them by tests/test_ios_album_look.py. Square, as the
/// phone is (binding 5): no corner, no shadow.
enum AlbumPageLook {
    /// The hero: the cover centred, 6 under the bar, the words 16 in from either side.
    static let albumCover: CGFloat = 204        // drawn: iAlbum .cover width
    static let playlistCover: CGFloat = 150     // drawn: iPlaylist .cover width
    static let heroTop: CGFloat = 6             // drawn: iAlbum hero padding-top
    static let heroSide: CGFloat = 16           // drawn: iAlbum hero padding-left
    /// The title 16 under the cover (a playlist's 14), the artist 2 under it, the meta line 6, the chips 10 and 6 apart.
    static let titleAbove: CGFloat = 16         // drawn: iAlbum title margin-top
    static let playlistTitleAbove: CGFloat = 14 // drawn: iPlaylist title margin-top
    static let artistAbove: CGFloat = 2         // drawn: iAlbum artist margin-top
    static let metaAbove: CGFloat = 6           // drawn: iAlbum meta margin-top
    static let chipsAbove: CGFloat = 10         // drawn: iAlbum chips margin-top
    static let chipGap: CGFloat = 6             // drawn: iAlbum chips gap
    /// Play and Shuffle: 12 apart, 16 above and 14 below - 16 in, the hero's own side (the drawing's pair padding-left).
    static let playGap: CGFloat = 12            // drawn: iAlbum play pair gap
    static let playAbove: CGFloat = 16          // drawn: iAlbum play pair padding-top
    static let playBelow: CGFloat = 14          // drawn: iAlbum play pair padding-bottom
    /// A song's row: its number from 16 in, the title at 56 - the drawing's number is a 46-wide box (dw.css's
    /// border-box) holding its own 16 of padding, so 30 for the number and the title's 10 of padding after it (R5's
    /// review: it sat at 62) - its time 4 from the •••, the ••• 16 from the right. The number's width and gap are
    /// TrackRow's to scale with the text size.
    static let numberWidth: CGFloat = 30        // drawn: iAlbum .row number width 46, less its padding-left 16
    static let numberGap: CGFloat = 10          // drawn: iAlbum .row title's padding-left (dw.css .row > div 0 10px)
    static let rowSide: CGFloat = 16            // drawn: iAlbum .row number padding-left
    static let timeTrail: CGFloat = 4           // drawn: iAlbum .row time padding-right
    static let moreTrail: CGFloat = 16          // drawn: iAlbum .row ••• padding-right
}

/// The top of an album page (screens.md 4, AlbumPage.tsx's hero): the cover (asked at 1024), the title (two lines,
/// a step smaller over 60 letters), the artist (plain text until Phase 4's slice 4, the link to their page since), the meta line,
/// the badge - its place held, unseen, until whose it is is known - the album's download line under it (Phase 2), and
/// Play and Shuffle, live once the songs are in (offline: once a song of it is on this phone). Drawn at once from what
/// opened the page, then filled as the album answers.
///
/// (R5, iAlbum.dc.html) The cover 204, square and flat; the title 22 bold; the artist at 20 in the accent (`acc`); the
/// meta line in the third colour; the badge a chip - green "In your library", plain "In the collection"; Play and
/// Shuffle the shared buttons, large (48) and side by side (AlbumPlayPair).
struct AlbumHero: View {
    let model: AlbumModel
    /// The album's download (phase2-downloads.md 3.2): its line under the badge, nothing at all for none.
    let download: AlbumDownload
    /// Play and Shuffle have something to play: the songs, or offline the songs on this phone.
    let playable: Bool
    let play: () -> Void
    let shuffle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppNavigation.self) private var navigation

    /// The cover's side before R5 - the pages that haven't been redrawn yet (the album you don't have) keep it.
    static let coverSide: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            CoverImage(id: model.coverArt, size: AlbumPageLook.albumCover)
                .frame(width: AlbumPageLook.albumCover, height: AlbumPageLook.albumCover)
                .clipShape(Rectangle())
                .padding(.top, AlbumPageLook.heroTop)

            Text(model.name)
                .font(model.longTitle ? Typeface.title3.bold() : Typeface.title2.bold())
                .foregroundStyle(DWPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, AlbumPageLook.titleAbove)
                .accessibilityAddTraits(.isHeader)

            if !model.artist.isEmpty {
                artistLine
                    .padding(.top, AlbumPageLook.artistAbove)
            }

            // the meta line holds its line while it is empty, so nothing below moves as it fills
            Text(model.meta.isEmpty ? " " : model.meta)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t3)
                .multilineTextAlignment(.center)
                .padding(.top, AlbumPageLook.metaAbove)
                .accessibilityHidden(model.meta.isEmpty)

            // the badge's place held, unseen, until whose it is is known
            HStack(spacing: AlbumPageLook.chipGap) {
                DWChip(words: model.mine.badge, tone: model.mine.yours == true ? .good : .plain)
            }
            .opacity(model.badgeShown ? 1 : 0)
            .accessibilityHidden(!model.badgeShown)
            .padding(.top, AlbumPageLook.chipsAbove)

            // its own line, so the badge never slides as the count moves; none at all for an album never downloaded
            if let line = DownloadWords.albumLine(download, device: Platform.device) {
                DownloadLine(download: download, line: line)
                    .padding(.top, AlbumPageLook.metaAbove)
                    .transition(.opacity)
            }

            AlbumPlayPair(enabled: playable, play: play, shuffle: shuffle)
        }
        .padding(.horizontal, AlbumPageLook.heroSide)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .default, value: DownloadWords.albumLine(download, device: Platform.device) != nil)
    }

    /// (Phase 4, slice 4) The artist (ArtistLink, AlbumPage.tsx's): a link to their page in the accent when the album
    /// names an artist and their name; drawn the same, but not tappable, while the album hasn't answered and it might
    /// still become one - so it never flashes from grey to the accent; quiet once the album has answered naming no
    /// artist to go to.
    @ViewBuilder private var artistLine: some View {
        let words = Text(model.artist)
            .font(Typeface.title3)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        switch model.artistLink {
        case .link(let id):
            // a button, not a NavigationLink: in the page's List a link would take the whole hero's row
            Button {
                navigation.open(.artist(ArtistRoute(id: id, preview: Artist(id: id, name: model.artist))))
            } label: {
                words
                    .foregroundStyle(DWPalette.acc)
                    // 44 pt to a finger, as the web's link reaches past its line
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -8)
        case .pending:
            words.foregroundStyle(DWPalette.acc)
        case .plain:
            words.foregroundStyle(DWPalette.t2)
        }
    }
}

/// The hero's download line (3.2): the album's line in the "In the collection" style - caption, semibold, quiet, no box
/// - its mark in front (amber, and amber words, for didn't); centred, wrapping at the largest sizes. Not a button: the
/// control in the bar is. VoiceOver reads it after the badge, the words alone.
struct DownloadLine: View {
    let download: AlbumDownload
    let line: String

    var body: some View {
        let failed: Bool = {
            if case .failed = download { return true }
            return false
        }()
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let mark = DownloadWords.mark(download) {
                // a symbol's own baseline (the ring keeps the hidden symbol's) sits it on the words' line
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: Typeface.symbol(.caption))
            }
            Text(line)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typeface.caption.weight(.semibold))
        .foregroundStyle(failed ? Palette.amber : Palette.quiet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }
}

/// (R5, iAlbum.dc.html and iPlaylist.dc.html) An album's and a playlist's - (R6) and an artist's - Play and Shuffle:
/// the shared buttons, large (48 at least) and filling - Play the phone's purple with its sharp glyph, Shuffle the plain
/// face - 12 apart, side by side, one above the other when the words won't fit beside each other (the largest text
/// sizes), each word taking up to three lines there. Both dimmed until there is something to play; each is the page's
/// own call, in the tap.
struct AlbumPlayPair: View {
    let enabled: Bool
    let play: () -> Void
    let shuffle: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AlbumPageLook.playGap) { buttons }
            VStack(spacing: AlbumPageLook.playGap) { buttons }
        }
        .disabled(!enabled)
        .padding(.top, AlbumPageLook.playAbove)
        .padding(.bottom, AlbumPageLook.playBelow)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: play) {
            HStack(spacing: 6) {
                SharpSymbol(.play)
                    .accessibilityHidden(true)
                words(PlaylistWords.play)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
        .accessibilityLabel(PlaylistWords.play)

        Button(action: shuffle) {
            HStack(spacing: 6) {
                Image(systemName: "shuffle")
                    .accessibilityHidden(true)
                words(PlaylistWords.shuffle)
            }
        }
        .buttonStyle(DWButtonStyle(size: .large, fills: true))
        .accessibilityLabel(PlaylistWords.shuffle)
    }

    /// A button's words: one line, three at the accessibility sizes (DWButtonStyle's one line the outer limit).
    private func words(_ text: String) -> some View {
        Text(text)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
