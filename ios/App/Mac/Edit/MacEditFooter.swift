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
///
/// (R12 - notes/ios.md "The redesign, slice R12: Needs a look"; NeedsALook.dc.html) In queue mode, It's fine as it is at
/// its left on every tab - the album's own issues marked fine, exactly those it shows (EditAlbumModel.markFine), with
/// Edit albums and Look after the library, as the phone offers it (NeedsLookPage.offersFine) - and under Release its line
/// says Apply moves on: once a release was applied, the purple button is Next album ›, a step through the host's gate
/// and question as the bar's Skip › is (NeedsLookPage.movesOn - the web's Apply becoming Next album); the last album
/// keeps Apply.
///
/// (R12's review) Queue mode's foot is laid out to fit (`queued`): its line, It's fine and the tab's actions on one line
/// when the whole of each fits, else the line over the two, else each on a line of its own - so nothing is cut, down to
/// the narrowest editor (378, the side panel open at 1280). A mark refused is said in it, over them, on every tab.
struct MacEditFooter: View {
    let model: EditAlbumModel
    let album: ScanAlbum
    let part: AlbumEdit.Part
    /// (R12) Queue mode, the host's - nil from anywhere but Needs a look.
    var queue: MacEditQueue? = nil

    @Environment(ServerModel.self) private var server

    var body: some View {
        Group {
            if queue != nil {
                queued
            } else {
                HStack(spacing: 8) {
                    Text(note)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(note)
                    Spacer(minLength: 8)
                    actions
                }
                .frame(height: 48)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(MacPalette.statusFace)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
        .accessibilityElement(children: .contain)
    }

    /// The tab's own actions, at the foot's right.
    @ViewBuilder private var actions: some View {
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

    /// (R12's review) Queue mode's foot, the first of three ways that fits its width (ViewThatFits): the line whole
    /// beside It's fine and the actions; the line over It's fine and the actions; the line, It's fine and the actions
    /// each a line of their own - worked out with the bundled faces' widths (tests/test_ios_needs_look_look.py) so the
    /// last fits the narrowest editor with every tab's widest words ("Apply to all 1,234 tracks"). The line wraps, never
    /// cut; its whole on the pointer and to VoiceOver too. A mark refused (`markFailure`) is said over them, on whichever
    /// tab is open - and for a person who has no Release tab, where the tab's own would have said it.
    private var queued: some View {
        VStack(alignment: .leading, spacing: MacEditFootLook.gap) {
            if let failure = model.markFailure {
                Text(failure)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.redChipText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    fine
                    line
                        .fixedSize()
                    Spacer(minLength: 8)
                    actions
                }
                VStack(alignment: .leading, spacing: MacEditFootLook.gap) {
                    wrapped
                    HStack(spacing: 8) {
                        fine
                        Spacer(minLength: 8)
                        actions
                    }
                }
                VStack(alignment: .leading, spacing: MacEditFootLook.gap) {
                    wrapped
                    fine
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        actions
                    }
                }
            }
        }
        .padding(.vertical, MacEditFootLook.side)
        .frame(minHeight: 48)
    }

    /// The tab's line, in queue mode: Apply moving on under Release, else the tab's own.
    private var line: some View {
        Text(note)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t3)
            .help(note)
    }

    /// The line over the foot's buttons: wrapping at the foot's width - measured as nothing wide (`idealWidth: 0`), so
    /// the way chosen is the one whose buttons fit.
    private var wrapped: some View {
        line
            .fixedSize(horizontal: false, vertical: true)
            .frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    /// The tab's line - under Delete, who holds the album, short, once the summary says ("In a library: Ann's" - the
    /// drawing's "Nobody else has this album in their library."): the whole sentence is the tab's own row (R11's review).
    private var note: String {
        if part == .release, queue?.nav.on == true { return NeedsLookPage.movesOnLine }
        return part == .delete ? EditAlbumPage.deleteFoot(model.deletion.summary) : EditAlbumPage.Words.foot(part)
    }

    /// (R12) It's fine as it is, in queue mode: the album's outstanding issues marked fine - (R12's review) with Edit
    /// albums and Look after the library, exactly as the phone offers it (NeedsLookPage.offersFine), while it has some
    /// (the Release tab's Needs a look box shows them, and Ask about it again).
    @ViewBuilder private var fine: some View {
        if NeedsLookPage.offersFine(server.access.permissions), !MetadataQueue.outstanding(album).isEmpty {
            Button(model.marking ? RetagWords.markingFine : RetagWords.fine) {
                Task { await model.markFine() }
            }
            .buttonStyle(DWButtonStyle())
            .disabled(!model.online || model.marking || model.writing)
            .fixedSize()
        }
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
        if let queue, NeedsLookPage.movesOn(queue.nav, applied: retag.applied != nil) {
            // (R12) applied, in queue mode: the purple button moves on - through the host's gate and question
            Button {
                queue.take(1)
            } label: {
                Text(NeedsLookWords.nextAlbum)
                    .frame(minWidth: 72)
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .accessibilityLabel(NeedsLookWords.nextAlbumSpoken)
            .disabled(!model.canStep)
        } else {
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

/// (R12's review) Queue mode's foot on the Mac: the room over and under its lines (11, so one line of 26-tall buttons is
/// the foot's 48) and between them (6).
enum MacEditFootLook {
    static let side: CGFloat = 11
    static let gap: CGFloat = 6
}
