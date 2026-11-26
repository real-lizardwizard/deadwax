import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its foot (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the
/// folder list and Release"; Main.dc.html): 48 tall under the tab, what the tab's action does at its left - and, under
/// Release, Revert (the typed work put back as the folder has it) and Apply, the purple one, saying what it waits for
/// while it runs. Apply is the sheet's own (EditAlbumModel.apply): the preview's body sent, the server working the plan
/// out again - never a plan sent back. Under a part still today's page (Tags, Artwork, Lyrics, Delete), its Open…,
/// over the page (R11 gives each tab its own actions here: Tags' Revert and Apply, Delete's Delete permanently).
struct MacEditFooter: View {
    let model: EditAlbumModel
    let part: AlbumEdit.Part
    /// Open…: the part's page, over this one.
    let open: (AlbumEdit.Part) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(note)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if part == .release {
                if let retag = model.retag {
                    release(retag)
                }
            } else {
                Button(EditAlbumPage.Words.openPart(part)) { open(part) }
                    .buttonStyle(DWButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(MacPalette.statusFace)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
        .accessibilityElement(children: .contain)
    }

    private var note: String {
        part == .release ? EditAlbumPage.Words.releaseFoot : EditAlbumPage.Words.partFoot
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
}
