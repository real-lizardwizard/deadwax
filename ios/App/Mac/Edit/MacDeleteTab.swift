import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its Delete tab (the redesign, slice R11 - notes/ios.md "The redesign, slice R11: Tags,
/// Artwork, Lyrics and Delete"; Main.dc.html): the "Delete this album?" box - the album's cover at 48, its name, its
/// byline and its folder; what goes, in a well in the readout face ("10 tracks · 290 MB", then "and 40 other files:"
/// over their names, ", …" past the twelve the summary names - read live as the tab opens, so it counts what the scan
/// ignores: a rip log, a cue sheet, named, as they might be the only copy); who holds it, the whole sentence (R11's
/// review: the foot's line is short); and the warning in the red words. Delete permanently is the foot's red button
/// (DeleteButton, MacEditFooter): off until the summary is in hand, it asks once more in the Mac's own question -
/// "There is no undo.", Cancel the default - and only the question's Delete deletes, with every guard the server has.
///
/// Every rule is the phone's (EditAlbumModel.deletion, readDeletion, delete): the summary is read for the folder shown,
/// again for the folder it is followed to and back in reach; a delete that never answered is said as maybe finished
/// until the folder's next read says.
struct MacDeleteTab: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    var body: some View {
        let delete = model.deletion
        MacGroupBox(legend: DeleteWords.title) {
            VStack(alignment: .leading, spacing: 12) {
                if delete.mayHaveFinished {
                    MayHaveFinished(reading: model.scan.reading)
                }
                // the library couldn't be read again: nothing is deleted until a read lands, said rather than leaving
                // Delete off with no reason
                if model.readBlocking != nil || (delete.mayHaveFinished && model.scan.failure != nil) {
                    HStack(spacing: 8) {
                        ReadAgainFailed(model: model)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
                HStack(alignment: .top, spacing: 12) {
                    FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 120)
                        .frame(width: 48, height: 48)
                        .clipShape(DWCorners.chipShape)
                        .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.album.isEmpty ? album.path : album.album)
                            .fontWeight(.semibold)
                            .foregroundStyle(DWPalette.head)
                        let byline = EditWords.byline(album)
                        if !byline.isEmpty {
                            Text(byline)
                                .foregroundStyle(DWPalette.t2)
                        }
                        Text(album.path)
                            .font(Typeface.Mac.mono(.label))
                            .foregroundStyle(DWPalette.t3)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
                if delete.reading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(DeleteWords.checking).foregroundStyle(DWPalette.t2)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let summary = delete.summary {
                    // what goes: its tracks and their size, then (R11's review) what else is in there in deadwax's
                    // words - "and 40 other files:" in the caution's colour over the names, the summary naming twelve
                    // at most and counting every one
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DeleteWords.counts(summary))
                            .foregroundStyle(DWPalette.text)
                        if let others = DeleteWords.others(summary) {
                            Text(others.lead)
                                .foregroundStyle(DWPalette.amberText)
                            Text(others.names)
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                    .font(Typeface.Mac.mono(.small))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { DWWell(focused: false) }
                    .accessibilityElement(children: .combine)
                    // (R11's review) who holds it, the whole sentence - what deleting does to them - in the caution's
                    // words; the foot keeps it short
                    if let holders = DeleteWords.holders(summary) {
                        Text(holders)
                            .foregroundStyle(DWPalette.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let failure = delete.readFailure {
                    ErrorNote(text: failure)
                    Button(EditWords.lookAgain) {
                        Task { await model.readDeletion() }
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!model.online || delete.reading)
                }
                // .red: the red words, under the well
                Text(DeleteWords.warning)
                    .foregroundStyle(DWPalette.redChipText)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = delete.failure {
                    ErrorNote(text: failure)
                }
            }
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(DWPalette.text)
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
        // read live each time the tab shows (and for the folder the album is followed to, and back in reach) - a
        // summary from before describes the folder as it was
        .task(id: "\(album.path)|\(model.online)") { await model.readDeletion() }
    }
}
