import DeadwaxCore
import SwiftUI

/// Edit album's Delete album (notes/ios-specs/phase8-managing.md 3.6; the web's DeleteAlbumDialog, its Delete tab): what
/// deleting the folder takes - read live as the page opens, so it counts what the scan ignores (a rip log, a cue sheet:
/// named, as they might be the only copy) - and whose libraries it is in, then the warning and **Delete permanently**
/// (DeleteButton), off until the summary is in hand, which asks once more in the phone's own action sheet. Deleted, the
/// sheet closes, the album page beneath goes back when nothing of the album is left in Navidrome, and the Library's lists
/// are asked again (EditAlbumModel.delete). A delete that never answered is said as maybe finished until the folder's
/// next read says. Every word is Core's (DeleteWords, EditAlbumPage).
///
/// (R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") The root's Delete tab, as
/// iEditDelete.dc.html draws it, flat: the "Delete this album?" group - Tracks; what else is in there in deadwax's words
/// ("and 40 other files:" over their names - R11's review: the drawing's "Also in there" row lost the count); In a
/// library and Folder, each a row - who holds it in their words, and the warning in the red words; Delete permanently is
/// the root's foot (DeleteButton, the red one), through the same question with every guard it had.
struct DeletePage: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    var body: some View {
        let delete = model.deletion
        VStack(alignment: .leading, spacing: 0) {
            if delete.mayHaveFinished {
                PhoneCard {
                    MayHaveFinished(reading: model.scan.reading)
                }
            }
            // the library couldn't be read again (after a write, a gap - the Release's wait or Tags'): nothing is
            // deleted until a read lands, and the page says so rather than leaving Delete off with no reason
            if model.readBlocking != nil || (delete.mayHaveFinished && model.scan.failure != nil) {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ReadAgainFailed(model: model)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            PhoneGroup(legend: DeleteWords.title) {
                if delete.reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(DeleteWords.checking)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .frame(maxWidth: .infinity, minHeight: CGFloat(PhoneLook.kvRow), alignment: .leading)
                    .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                    .accessibilityElement(children: .combine)
                }
                if let summary = delete.summary {
                    PhoneKV(label: EditAlbumPage.Words.tracks, value: EditAlbumPage.deleteTracks(summary), mono: true)
                    // (R11's review) what else goes, in deadwax's words: "and 40 other files:" in the caution's colour
                    // over the names - the summary names twelve at most, and counts every one
                    if let others = DeleteWords.others(summary) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(others.lead)
                                .foregroundStyle(DWPalette.amberText)
                            Text(others.names)
                                .font(Typeface.Phone.mono(.small))
                                .foregroundStyle(DWPalette.t2)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                        .accessibilityElement(children: .combine)
                    }
                    if let held = EditAlbumPage.held(summary) {
                        PhoneKV(label: EditAlbumPage.Words.inALibrary, value: held)
                    }
                }
                PhoneKV(label: EditWords.folder, value: album.path, mono: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                // who holds it, and what deleting does to them - in the caution's words
                if let summary = delete.summary, let holders = DeleteWords.holders(summary) {
                    Text(holders)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.amberText)
                }
                if let failure = delete.readFailure {
                    ErrorNote(text: failure)
                    Button(EditWords.lookAgain) {
                        Task { await model.readDeletion() }
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!model.online || delete.reading)
                }
                // .dw .red: the red words, under the group
                Text(DeleteWords.warning)
                    .foregroundStyle(DWPalette.redChipText)
                if let failure = delete.failure {
                    ErrorNote(text: failure)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
        }
        .font(Typeface.Phone.text(.row))
        .foregroundStyle(DWPalette.text)
        // read live each time the tab shows (and for the folder the album is followed to, and back in reach) - a
        // summary from before describes the folder as it was
        .task(id: "\(album.path)|\(model.online)") { await model.readDeletion() }
    }
}

/// Delete permanently (slice 4's; R11 - the foot's on both devices, the phone's PhoneFoot and the Mac's MacEditFooter,
/// each its own red button style): off until this folder's summary is in hand (EditAlbumModel.canDelete), it asks once
/// more in the device's own question - "Delete Dummy?" / "There is no undo.", Cancel the default - a question tied to the
/// folder and the summary it was asked over, put away if the page is followed to another folder, and refused if either
/// is no longer what the page holds (review, 16 Nov). Nothing is deleted from the button itself: only the question's
/// Delete deletes.
struct DeleteButton: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    /// The question up: the folder and the summary it was asked over.
    @State private var asking: (path: String, summary: DeletionSummary)?

    var body: some View {
        let delete = model.deletion
        // one line: the phone's foot (PhoneFoot) stops its text at xxxLarge, where Delete permanently fills it with
        // room to spare - an accessibility size never reaches it (R11's review)
        Button(role: .destructive) {
            if let summary = delete.summary { asking = (album.path, summary) }
        } label: {
            HStack(spacing: 8) {
                if delete.deleting { ProgressView().controlSize(.small) }
                Text(delete.deleting ? DeleteWords.deleting : DeleteWords.confirm)
            }
        }
        .disabled(!model.canDelete)
        // the device's own question: Cancel is the default, Delete the destructive one
        .confirmationDialog(DeleteWords.question(album.album),
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { asked in
            // the question's own folder and summary, handed in as it was raised - not read back after it has gone
            Button(DeleteWords.delete, role: .destructive) {
                Task { await model.delete(path: asked.path, summary: asked.summary) }
            }
            Button(DeleteWords.cancel, role: .cancel) {}
                .returnCancels()
        } message: { _ in
            Text(DeleteWords.noUndo)
        }
        // followed to another folder while the question is up (a scan moved it): the question was about the other one
        .onChange(of: album.path) { asking = nil }
    }
}
