import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, the editor's header (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit
/// album, the folder list and Release"; Main.dc.html): the cover at 72, the album at 20 and bold, its artist and
/// edition, its formats, tracks and size in the readout face, its path under them (its whole in its help, and it can
/// be selected) - and, beside the words from an editor of 560 (under them below that), the chip saying whether the
/// folder is matched to MusicBrainz and Open album, the album's page, when the editor was opened from it. With several
/// folders found for the album, the Folder menu under it all, as the sheet's root has it.
///
/// (R12 - notes/ios.md "The redesign, slice R12: Needs a look") `bar`, its host's: queue mode's ‹, "1 of 3" and Skip ›
/// under the chip, at the column's trailing edge beside the words (NeedsALook.dc.html), at its leading edge under them.
struct MacEditHeader<Bar: View>: View {
    let model: EditAlbumModel
    let album: ScanAlbum
    /// The chip and Open album beside the words (EditAlbumPage.Layout.headerBeside), else under them.
    let beside: Bool
    /// (R12) Queue mode's bar, or nothing.
    let bar: Bar

    init(model: EditAlbumModel, album: ScanAlbum, beside: Bool, @ViewBuilder bar: () -> Bar) {
        self.model = model
        self.album = album
        self.beside = beside
        self.bar = bar()
    }

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let layout = beside ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        VStack(alignment: .leading, spacing: 8) {
            layout {
                HStack(alignment: .top, spacing: 14) {
                    FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 240)
                        .frame(width: 72, height: 72)
                        .clipShape(DWCorners.chipShape)
                        .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                        .accessibilityHidden(true)
                    words
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            if let folders = model.folders, folders.paths.count > 1 {
                folderMenu(folders.paths)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.album.isEmpty ? album.path : album.album)
                    .font(Typeface.Mac.text(.h2).weight(.bold))
                    .foregroundStyle(DWPalette.text)
                let byline = EditWords.byline(album)
                if !byline.isEmpty {
                    Text(byline)
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.t2)
                }
                Text(facts)
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t3)
                    .padding(.top, 3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(album.path)
                .font(Typeface.Mac.mono(.label))
                .foregroundStyle(DWPalette.t3)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(album.path)
        }
    }

    /// Its formats and tracks, and its size on disk.
    private var facts: String {
        [EditWords.facts(album), album.totalSize > 0 ? Sources.size(album.totalSize) : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var trailing: some View {
        let matched = EditAlbumPage.matched(album)
        return VStack(alignment: beside ? .trailing : .leading, spacing: 8) {
            DWChip(words: matched ? EditAlbumPage.Words.matchedMusicBrainz : EditAlbumPage.Words.notMatched,
                   tone: matched ? .good : .plain)
            if let subject = model.subject {
                Button(EditAlbumPage.Words.openAlbum) {
                    navigation.openAlbum(AlbumRoute(id: subject.id, name: subject.name, artist: subject.artist,
                                                    musicBrainzId: subject.musicBrainzId))
                }
                .buttonStyle(DWButtonStyle(size: .small))
            }
            bar
        }
        .fixedSize()
    }

    /// The Folder menu (the look's pop-up): another of the album's folders - off while a write runs.
    private func folderMenu(_ paths: [String]) -> some View {
        HStack(spacing: 8) {
            Text(EditWords.folder)
                .font(Typeface.Look.text(.fieldLabel))
                .foregroundStyle(DWPalette.t2)
                .accessibilityHidden(true)
            DWPopUp(words: album.path, size: .small) {
                ForEach(paths, id: \.self) { (path: String) in
                    Button(path) { model.choose(path, fromScan: false) }
                }
            }
            .accessibilityLabel(EditWords.folder)
            .accessibilityValue(album.path)
            .disabled(model.writing)
        }
    }
}
