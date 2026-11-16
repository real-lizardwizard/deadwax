import DeadwaxCore
import SwiftUI

/// Edit album's Delete album (notes/ios-specs/phase8-managing.md 3.6; the web's DeleteAlbumDialog, its Delete tab): what
/// deleting the folder takes - read live as the page opens, so it counts what the scan ignores (a rip log, a cue sheet:
/// named, as they might be the only copy) - and whose libraries it is in, then the warning and **Delete permanently**,
/// off until the summary is in hand, which asks once more in the phone's own action sheet: "Delete Dummy?" / "There is
/// no undo.", Cancel the default. Deleted, the sheet closes, the album page beneath goes back when nothing of the album
/// is left in Navidrome, and the Library's lists are asked again (EditAlbumModel.delete). A delete that never answered
/// is said as maybe finished until the folder's next read says. Every word is Core's (DeleteWords).
struct DeletePage: View {
    let model: EditAlbumModel
    let album: ScanAlbum

    @State private var asking = false

    var body: some View {
        let delete = model.deletion
        List {
            if delete.mayHaveFinished {
                Section {
                    MayHaveFinished(reading: model.scan.reading)
                }
            }
            // the library couldn't be read again (after a write, a gap): nothing is deleted until a read lands
            if model.retag?.flow.readFailed == true || (delete.mayHaveFinished && model.scan.failure != nil) {
                Section {
                    ReadAgainFailed(model: model)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.album.isEmpty ? album.path : album.album)
                        .font(Typeface.headline)
                    let byline = EditWords.byline(album)
                    if !byline.isEmpty {
                        Text(byline)
                            .font(Typeface.subheadline)
                            .foregroundStyle(Palette.quiet)
                    }
                    Text(album.path)
                        .font(Typeface.mono(.caption))
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            } header: {
                Text(DeleteWords.title)
                    .font(Typeface.footnote)
            }
            Section {
                if delete.reading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(DeleteWords.checking)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let summary = delete.summary {
                    Text(DeleteWords.counts(summary))
                    if let others = DeleteWords.others(summary) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(others.lead)
                                .foregroundStyle(Palette.amber)
                            Text(others.names)
                                .font(Typeface.footnote)
                                .foregroundStyle(Palette.quiet)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                    if let holders = DeleteWords.holders(summary) {
                        Text(holders)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let failure = delete.readFailure {
                    ErrorNote(text: failure)
                    Button(EditWords.lookAgain) {
                        Task { await model.readDeletion() }
                    }
                    .disabled(!model.online || delete.reading)
                }
            }
            Section {
                Text(DeleteWords.warning)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    asking = true
                } label: {
                    HStack(spacing: 10) {
                        if delete.deleting { ProgressView() }
                        Text(delete.deleting ? DeleteWords.deleting : DeleteWords.confirm)
                    }
                }
                .disabled(!model.canDelete)
                if let failure = delete.failure {
                    ErrorNote(text: failure)
                }
            }
        }
        .navigationTitle(DeleteWords.page)
        .navigationBarTitleDisplayMode(.inline)
        // the phone's own question: Cancel is the default, Delete the destructive one
        .confirmationDialog(DeleteWords.question(album.album), isPresented: $asking, titleVisibility: .visible) {
            Button(DeleteWords.delete, role: .destructive) {
                Task { await model.delete() }
            }
            Button(DeleteWords.cancel, role: .cancel) {}
        } message: {
            Text(DeleteWords.noUndo)
        }
        // read live each time the page opens (and for the folder the album is followed to, and back in reach) - a
        // summary from before describes the folder as it was
        .task(id: "\(album.path)|\(model.online)") { await model.readDeletion() }
    }
}
