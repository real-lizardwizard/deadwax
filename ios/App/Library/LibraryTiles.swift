import DeadwaxCore
import SwiftUI

/// The Library's lists as the redesign draws them (slice R2 - notes/ios.md "The redesign, slice R2: Albums and Artists,
/// and the Library's top"): iLibrary.dc.html's tiles and iArtists.dc.html's rows, each size from dw.css's phone rules or
/// the drawing itself, as its comment says (tests/test_ios_library_look.py holds each to its source).
enum LibraryLook {
    /// .tiles: two columns 14 apart, rows 16 apart, 12 under the meta line.
    static let tileColumnGap: CGFloat = 14      // dw.ph: .tiles gap 2
    static let tileRowGap: CGFloat = 16         // dw.ph: .tiles gap 1
    static let tilesTop: CGFloat = 12           // dw.ph: .tiles padding-top
    /// .tile > .t: the title 7 under the cover.
    static let tileTitleAbove: CGFloat = 7      // dw.ph: .tile > .t margin-top
    /// A list's tall row: the cover 44, 16 in; its words 10 either side; the chevron 16 from the right.
    static let rowCover: CGFloat = 44           // drawn: iArtists .row .cover width
    static let rowSide: CGFloat = 16            // drawn: iArtists .row padding-left
    static let rowTextSide: CGFloat = 10        // dw.ph: .row > div padding-left
    static let rowTrail: CGFloat = 16           // drawn: iArtists .row chevron padding-right
    /// The list's sides - the meta line's and the strip's 16.
    static let side: CGFloat = 16               // dw.ph: .tiles padding-left
    /// Find's field under the top, 8 above the strip (drawn nowhere in dw.css: the field the top opens is the app's).
    static let findBelow: CGFloat = 8
}

/// One album's tile (app/AlbumTile.tsx; since R2 iLibrary's .tile): the cover, the title (15, semibold, white), the
/// artist (13, the second colour) and - with a library of your own - the New mark of an album new in your library until
/// you open it. It opens its album; nothing here plays.
///
/// Phase 2 (phase2-downloads.md 5.1, 5.3): an album with a download state carries its mark at the end of its artist
/// line - never on the cover, whose top left is the New mark's - outside the artist's words, so a long artist
/// truncates before the mark; on Downloaded, every tile has a third line, the state in words, so the grid's rows keep
/// one height. While deadwax can't be reached, an album with nothing on this phone is dimmed and opens nothing.
struct LibraryTile: View {
    let album: IndexAlbum
    let isNew: Bool
    var download: AlbumDownload = .none
    /// Downloaded's third line ("12 songs", "Downloading", amber "Didn't download") - nil on the other lists.
    var line: String?
    var dimmed = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                LibraryCover(id: album.coverArt, pixels: CoverSize.tile)
                    .clipShape(DWCorners.chipShape)
                    .overlay(alignment: .topLeading) {
                        if isNew { LibraryNewMark().padding(6) }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name ?? "")
                        .font(Typeface.subheadline.weight(.semibold))
                        .foregroundStyle(DWPalette.text)
                    ArtistLine(artist: album.artist ?? "", download: download)
                    if let line {
                        Text(line)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(download.isFailed ? DWPalette.amberText : DWPalette.t2)
                    }
                }
                .lineLimit(1)
                .padding(.top, LibraryLook.tileTitleAbove)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(dimmed ? DWPalette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(LibraryTile.spoken(album, isNew: isNew, download: download, notHere: dimmed))
        // (the Mac app, slice 2) the album page's ••• on a right-click; nothing on the iPhone
        .albumRightClick(AlbumRoute(album))
    }

    /// What VoiceOver says of a tile or a row, in the order the web's button reads: the title, the artist, its download
    /// ("Downloaded", "Partly downloaded", "Downloading"... - "Not on this phone" while dimmed) and "New in your library".
    static func spoken(_ album: IndexAlbum, isNew: Bool, download: AlbumDownload = .none, notHere: Bool = false) -> String {
        [album.name, album.artist, DownloadWords.tileSpoken(download, notHere: notHere, device: Platform.device),
         isNew ? LibraryWords.newMarkSpoken : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A tile's or a row's artist line (.a, .s: 13, the second colour) with the album's download mark at its end (5.3): the
/// mark outside the words, fixed, so a long artist truncates before it rather than taking it with it.
private struct ArtistLine: View {
    let artist: String
    let download: AlbumDownload

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(artist)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: Typeface.symbol(.caption2))
                    .fixedSize()
            }
        }
    }
}

extension AlbumDownload {
    /// Something of it didn't download: its words are amber.
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A list's tall row as the redesign draws it (iArtists.dc.html's .row.tall, slice R2): the cover 44 at 16 in, the
/// name (17, white) and its line (13, the second colour) 10 from either side, what trails it - the chevron, or a song's
/// ••• - and the row's rule under it; 60 tall at least, growing with the text. The rule spans the row within the list's
/// own 16 pt sides (the drawing's runs edge to edge: the lists keep their sides, for the letter index's room).
struct LibraryListRow<Cover: View, Trailing: View>: View {
    let title: String
    let line: String
    var lineColour = DWPalette.t2
    /// (R2's review) How many lines the name and its line may each take: one, as drawn - a playlist's two at the
    /// accessibility sizes, as its row had before R2, so a long name isn't cut.
    var lines = 1
    @ViewBuilder let cover: Cover
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            cover
                .frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                if !line.isEmpty {
                    Text(line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(lineColour)
                }
            }
            .lineLimit(lines)
            .padding(.horizontal, LibraryLook.rowTextSide)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .lookHeight(DWLook.here.tallRowHeight)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
    }
}

/// The row's chevron (the drawing's ›, in the third colour): its page is pushed.
struct LibraryChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(Typeface.symbol(.footnote).weight(.semibold))
            .foregroundStyle(DWPalette.t3)
            .accessibilityHidden(true)
    }
}

/// One album's row in the list layout (library.md Open question 3; since R2 iArtists' tall row): the cover, the title,
/// the artist under it, and the New mark - the same headers, Find, index and marks as the tiles, the download's too.
struct LibraryRow: View {
    let album: IndexAlbum
    let isNew: Bool
    var download: AlbumDownload = .none
    var line: String?
    var dimmed = false
    let open: () -> Void

    /// The cover's side, and where the text (and the line under a row) begins - the rows of the lists R2 doesn't redraw
    /// (a playlist's songs, the playlist picker) still read these.
    static let cover: CGFloat = 48
    static let textInset: CGFloat = cover + 12

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                LibraryCover(id: album.coverArt, pixels: CoverSize.row)
                    .frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)
                    .clipShape(DWCorners.chipShape)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name ?? "")
                        .font(Typeface.body)
                        .foregroundStyle(DWPalette.text)
                    ArtistLine(artist: album.artist ?? "", download: download)
                    if let line {
                        Text(line)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(download.isFailed ? DWPalette.amberText : DWPalette.t2)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, LibraryLook.rowTextSide)
                .frame(maxWidth: .infinity, alignment: .leading)
                if isNew { LibraryNewMark() }
            }
            .lookHeight(DWLook.here.tallRowHeight)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
            .contentShape(Rectangle())
            .opacity(dimmed ? DWPalette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(LibraryTile.spoken(album, isNew: isNew, download: download, notHere: dimmed))
        // (the Mac app, slice 2) the album page's ••• on a right-click; nothing on the iPhone
        .albumRightClick(AlbumRoute(album))
    }
}

/// The New mark: "New", the accent's chip (.chip.purple) on the window's ground - legible whatever the cover behind it -
/// read as "New in your library" (the tile's own label says it, for VoiceOver).
struct LibraryNewMark: View {
    var body: some View {
        DWChip(words: LibraryWords.newMark, tone: .marked)
            .background(DWPalette.bg, in: DWCorners.chipShape)
            .accessibilityLabel(LibraryWords.newMarkSpoken)
    }
}

/// A group's header - "A", "#", "October 2026", "1994", "No year" - in the list's flow, never pinned, a heading for
/// VoiceOver.
struct LibraryHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .font(Typeface.title3.weight(.semibold))
            .foregroundStyle(DWPalette.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A cover asked at exactly the size Core names for where it is drawn (CoverSize.tile for a tile, .row for a row),
/// whatever the screen's scale - as the web's tile asks 400 - so 3,000 tiles share Navidrome's few kept sizes and
/// the memory a cover takes stays a tile's. CoverImage asks the step for its size times the scale, so it is handed
/// the size that comes to just under `pixels` (never over, which would round up to the next step).
struct LibraryCover: View {
    let id: String?
    let pixels: Int

    @Environment(\.displayScale) private var scale

    var body: some View {
        CoverImage(id: id, size: (CGFloat(pixels) - 0.5) / max(scale, 1))
    }
}
