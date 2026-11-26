import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its foot (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the
/// folder list and Release"; Main.dc.html): 48 tall under the tab, what the tab's action does at its left - and, under
/// Release, Revert (the typed work put back as the folder has it) and Apply, the purple one, saying what it waits for
/// while it runs. Apply is the sheet's own (EditAlbumModel.apply): the preview's body sent, the server working the plan
/// out again - never a plan sent back.
///
/// (R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") Each tab's own actions, as the
/// drawing's `foots`: under Tags, Revert (every field typed over put back as the files say) and Apply to N tracks - the
/// tracks ticked, all of them with none (EditAlbumModel.applyTags: the fields sent, the server planning again); under
/// Delete, who holds the album at its left, short (EditAlbumPage.deleteFoot - the tab says it whole) and Delete
/// permanently, the red one,
/// through the device's own question with every guard (DeleteButton); under Artwork and Lyrics, their line alone - their
/// Gets are the tab's.
struct MacEditFooter: View {
    let model: EditAlbumModel
    let album: ScanAlbum
    let part: AlbumEdit.Part

    var body: some View {
        HStack(spacing: 8) {
            Text(note)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(note)
            Spacer(minLength: 8)
            switch part {
            case .release:
                if let retag = model.retag {
                    release(retag)
                }
            case .tags:
                if let tags = model.tags {
                    self.tags(tags)
                }
            case .delete:
                DeleteButton(model: model, album: album)
                    .buttonStyle(DWButtonStyle(kind: .danger))
            case .artwork, .lyrics:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(MacPalette.statusFace)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
        .accessibilityElement(children: .contain)
    }

    /// The tab's line - under Delete, who holds the album, short, once the summary says ("In a library: Ann's" - the
    /// drawing's "Nobody else has this album in their library."): the whole sentence is the tab's own row (R11's review).
    private var note: String {
        part == .delete ? EditAlbumPage.deleteFoot(model.deletion.summary) : EditAlbumPage.Words.foot(part)
    }

    @ViewBuilder private func release(_ retag: RetagModel) -> some View {
        let plan = retag.currentPlan
        if retag.flow.applying {
            // (R10's review) one line beside the foot's words and its buttons: by the sum, "Applying, waiting for
            // Navidrome" is cut at an editor under about 560 (the smallest page's 379, 1280 with the panel open) - its
            // whole words on the pointer, and to VoiceOver as they are
            let applying = RetagWords.applying(plan ?? retag.plan)
            ProgressView().controlSize(.small)
            Text(applying)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .help(applying)
        }
        Button(EditAlbumPage.Words.revert) {
            model.revertRelease()
        }
        .buttonStyle(DWButtonStyle())
        .disabled(!model.canRevertRelease)
        Button {
            Task { await model.apply() }
        } label: {
            Text(RetagWords.apply)
                .frame(minWidth: 72)
        }
        .buttonStyle(DWButtonStyle(kind: .pri))
        .disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)
    }

    /// (R11) Tags' Revert - every field typed over put back as the files say (TagsModel.revert, field by field) - and
    /// Apply to N tracks, saying what it writes to; "Saving…" while it runs.
    @ViewBuilder private func tags(_ tags: TagsModel) -> some View {
        let names = (tags.files ?? []).map { (file: AlbumFile) -> String in file.filename }
        Button(EditAlbumPage.Words.revert) {
            for key in tags.draft.keys.sorted() { tags.revert(key) }
        }
        .buttonStyle(DWButtonStyle())
        .disabled(!tags.unsaved || tags.flow.applying)
        Button {
            Task { await model.applyTags() }
        } label: {
            HStack(spacing: 8) {
                if tags.flow.applying { ProgressView().controlSize(.small) }
                Text(tags.flow.applying ? TagEditWords.saving
                     : EditAlbumPage.Words.applyTo(ticked: EditAlbumPage.ticked(names, tags.selection), of: names.count))
                    .lineLimit(1)
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(DWButtonStyle(kind: .pri))
        .disabled(!tags.canApply || model.writing || model.marking)
    }
}
