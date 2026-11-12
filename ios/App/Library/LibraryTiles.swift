import DeadwaxCore
import SwiftUI

/// One album's tile (app/AlbumTile.tsx): the cover, the title, the artist and - with a library of your own - the New
/// mark of an album new in your library until you open it. It opens its album; nothing here plays.
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
            VStack(alignment: .leading, spacing: 6) {
                LibraryCover(id: album.coverArt, pixels: CoverSize.tile)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if isNew { LibraryNewMark().padding(6) }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name ?? "")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    ArtistLine(artist: album.artist ?? "", download: download, font: .footnote)
                    if let line {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(download.isFailed ? Palette.amber : Palette.quiet)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(dimmed ? Palette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(LibraryTile.spoken(album, isNew: isNew, download: download, notHere: dimmed))
    }

    /// What VoiceOver says of a tile or a row, in the order the web's button reads: the title, the artist, its download
    /// ("Downloaded", "Partly downloaded", "Downloading"... - "Not on this phone" while dimmed) and "New in your library".
    static func spoken(_ album: IndexAlbum, isNew: Bool, download: AlbumDownload = .none, notHere: Bool = false) -> String {
        [album.name, album.artist, DownloadWords.tileSpoken(download, notHere: notHere),
         isNew ? LibraryWords.newMarkSpoken : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A tile's or a row's artist line with the album's download mark at its end (5.3): the mark outside the words, fixed,
/// so a long artist truncates before it rather than taking it with it.
private struct ArtistLine: View {
    let artist: String
    let download: AlbumDownload
    let font: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(artist)
                .font(font)
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: .caption2)
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

/// One album's row in the list layout (library.md Open question 3): the cover at the rows' size, the title, the
/// artist under it, and the New mark - the same headers, Find, index and marks as the tiles, the download's too.
struct LibraryRow: View {
    let album: IndexAlbum
    let isNew: Bool
    var download: AlbumDownload = .none
    var line: String?
    var dimmed = false
    let open: () -> Void

    /// The cover's side, and where the text (and the line under a row) begins.
    static let cover: CGFloat = 48
    static let textInset: CGFloat = cover + 12

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                LibraryCover(id: album.coverArt, pixels: CoverSize.row)
                    .frame(width: Self.cover, height: Self.cover)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name ?? "")
                        .foregroundStyle(.primary)
                    ArtistLine(artist: album.artist ?? "", download: download, font: .subheadline)
                    if let line {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(download.isFailed ? Palette.amber : Palette.quiet)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if isNew { LibraryNewMark() }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(dimmed ? Palette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(LibraryTile.spoken(album, isNew: isNew, download: download, notHere: dimmed))
    }
}

/// The New mark: "New", read as "New in your library" (the tile's own label says it, for VoiceOver).
struct LibraryNewMark: View {
    var body: some View {
        Text(LibraryWords.newMark)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                // the card's own colour under the badge's tint: legible whatever the cover behind it
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.accent.opacity(0.18)))
            }
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.accent.opacity(0.55)))
            .accessibilityLabel(LibraryWords.newMarkSpoken)
    }
}

/// A group's header - "A", "#", "October 2026", "1994", "No year" - in the list's flow, never pinned, a heading for
/// VoiceOver.
struct LibraryHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.title3.weight(.semibold))
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
