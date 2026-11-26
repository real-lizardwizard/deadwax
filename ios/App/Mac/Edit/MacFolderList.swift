import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its left (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the
/// folder list and Release"; Main.dc.html's `.col`): the library's folders in the Library's order - its own bar (Find
/// folders, and the switch, All or Needs a look) over a list of columns: Album with its cover, Artist (from a page of
/// 1000 - the album's VoiceOver words and the row's help say it under that), Year, and the mark - the issues still to
/// look at, amber, or New for a new import with none, as the queue marks it; each row read cell by cell, as every list
/// but an artist's and an album's. A row picked is the editor's folder once the pick rests (MacEditWindow); the list is
/// off while a write runs, so the folder can't change under it. Every row and fact is the scan's: nothing is asked
/// here but the scan.
///
/// (R10's review) The rows and the status bar's counts are worked out here, from the scan, what was typed and the
/// switch alone - never in the page's body, which an editor's keystroke would otherwise run them again for.
struct MacFolderList: View {
    let scan: LibraryScanModel
    @Binding var typed: String
    @Binding var shown: EditAlbumPage.Shown
    @Binding var selected: String?
    let artistColumn: Bool
    let writing: Bool
    let lookAgain: () -> Void

    @Environment(\.macRowSize) private var rowSize

    /// The columns, in the drawing's order.
    private enum Column {
        case album, artist, year, issues
    }

    var body: some View {
        // the rows shown (EditAlbumPage.folders: what was typed, the switch)
        let rows = EditAlbumPage.folders(scan.albums, typed: typed, shown: shown)
        VStack(spacing: 0) {
            MacToolbar {
                // (R10's review) words that fit the field's 114 points beside the switch; what it finds by its name
                DWField(prompt: EditAlbumPage.Words.findFolders, text: $typed, spoken: EditWords.folderPrompt)
                    .help(EditWords.folderPrompt)
                DWSegmented(options: EditAlbumPage.Shown.allCases,
                            words: { (option: EditAlbumPage.Shown) -> String in option.label },
                            chosen: $shown, spoken: EditAlbumPage.Words.show, large: true)
            }
            content(rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(DWPalette.bg)
        .disabled(writing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(EditAlbumPage.Words.folderList)
        // the status bar: the folders shown, and the scan's waiting in Needs a look - the queue's own count
        .macStatus(MacStatusItems.Items(leading: [EditAlbumPage.Words.folders(rows.count),
                                                  EditAlbumPage.Words.needALook(EditAlbumPage.needingALook(scan.albums))]))
    }

    @ViewBuilder private func content(_ rows: [ScanAlbum]) -> some View {
        if !scan.loaded {
            VStack(alignment: .leading, spacing: 8) {
                if scan.reading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(EditWords.readingLibrary)
                    }
                    .accessibilityElement(children: .combine)
                } else if let failure = scan.failure {
                    ErrorNote(text: failure)
                    Button(EditWords.lookAgain, action: lookAgain)
                        .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .padding(16)
        } else if rows.isEmpty {
            Text(shown == .needsALook && typed.isEmpty ? EditAlbumPage.Words.noneNeedALook : EditAlbumPage.Words.noneMatch)
                .font(Typeface.Mac.text(.base))
                .foregroundStyle(DWPalette.t2)
                .padding(16)
        } else {
            let columns = shownColumns
            MacColumnList(columns: columns.map(column), rows: rows,
                          selected: $selected,
                          open: { (album: ScanAlbum) -> Void in selected = album.id },
                          menu: { (_: ScanAlbum) -> EmptyModifier in EmptyModifier() }
            ) { (album: ScanAlbum, at: Int) in
                if columns.indices.contains(at) { cell(album, columns[at]) }
            }
        }
    }

    private var shownColumns: [Column] {
        artistColumn ? [.album, .artist, .year, .issues] : [.album, .year, .issues]
    }

    private func column(_ column: Column) -> MacListColumn {
        switch column {
        case .album: return MacListColumn(title: EditWords.album, width: .flexible)
        case .artist: return MacListColumn(title: EditWords.artist, width: .fixed(EditAlbumPage.artistWidth))
        case .year: return MacListColumn(title: EditWords.year, width: .fixed(EditAlbumPage.yearWidth))
        case .issues: return MacListColumn(title: "", width: .fixed(EditAlbumPage.countWidth))
        }
    }

    @ViewBuilder private func cell(_ album: ScanAlbum, _ column: Column) -> some View {
        switch column {
        case .album:
            HStack(spacing: 8) {
                FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 80)
                    .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                    .accessibilityHidden(true)
                let title = album.album.isEmpty ? album.path : album.album
                Text(title)
                    .lineLimit(1)
                    // no Artist column under a page of 1000: the album's words say the artist to VoiceOver too
                    .accessibilityLabel(artistColumn || album.artist.isEmpty ? title : "\(title), \(album.artist)")
            }
            .help(EditAlbumPage.Words.folderRow(album))
        case .artist:
            Text(album.artist)
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                // (R10's review) 112 wide: a long name cut, its whole words on the pointer
                .help(album.artist)
        case .year:
            Text(album.year)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .help(album.year)
        case .issues:
            switch EditAlbumPage.mark(album) {
            case .issues(let count):
                DWChip(words: "\(count)", tone: .caution)
                    .accessibilityLabel(EditAlbumPage.Words.issues(count))
            case .new:
                // (R10's review) a new import with nothing wrong: the queue lists it, so the row says why
                DWChip(words: NeedsLook.newWord, tone: .marked)
                    .accessibilityLabel(EditAlbumPage.Words.newlyAdded)
            case nil:
                EmptyView()
            }
        }
    }
}
