import DeadwaxCore
import SwiftUI
import UIKit

/// Edit album's Release (notes/ios-specs/phase8-managing.md 3.3; the web's MetadataEditor, split over pages): the
/// pressing chosen (pushing Choose a release), the fields, the cover, What Apply does - the preview, drawn in the web's
/// words, its changes a row pushing Changes - and Apply. Apply is on only for a preview of what the page shows now that
/// changes something, with nothing loading and deadwax in reach (RetagFlow.canApply); while it runs it says what it waits
/// for (RetagWords.applying), and after, what it did - the folder read again and the album followed by EditAlbumModel.
/// Every word is Core's.
///
/// (R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release") On the phone Release is the
/// root's own now, under its strip (iEdit.dc.html): its four cards (ReleaseCards) and its foot (ReleaseFoot - Revert and
/// Apply). (R11) The page R10 kept for Artwork's pointer to push is gone: Artwork's Go to Release shows the Release tab.
///
/// Release's cards on the phone (iEdit.dc.html, flat as R1c draws the phone): Release - the pressing chosen, Change…
/// pushing Choose a release; Fields - Artist, Album, Year beside Original, Edition, each on the look's well; Cover - the
/// folder's and the pressing's, Replace cover.jpg's switch, Compare pushing Compare covers; What Apply does - the
/// preview, its summary pushing Changes. The waits the root says over its strip are said there (R11: the page by
/// itself that said them here too is gone).
struct ReleaseCards: View {
    let model: EditAlbumModel
    let retag: RetagModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case artist, album, year, originalYear, edition
    }

    /// (The Mac app, slice 7) The fields in the order the page draws them: Tab's on the Mac.
    private static let order: [Field] = [.artist, .album, .year, .originalYear, .edition]

    var body: some View {
        let plan = retag.currentPlan
        VStack(alignment: .leading, spacing: 0) {
            // the folder couldn't be read again after a write or a gap: the wait ends here, said, with Look again - on
            // the root its own line says it, where the library's read failed
            if retag.flow.readFailed {
                if model.scan.failure == nil {
                    PhoneCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ReadAgainFailed(model: model)
                        }
                        .buttonStyle(DWButtonStyle(size: .small))
                    }
                }
            }
            pressingSection
            fieldsSection
            coverSection
            applySection(plan)
        }
        .font(Typeface.Phone.text(.row))
        .foregroundStyle(DWPalette.text)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AlbumInfoWords.done) { focused = nil }
            }
        }
    }

    // MARK: the pressing

    private var pressingSection: some View {
        PhoneGroup(legend: EditWords.release) {
            PhoneCard {
                VStack(alignment: .leading, spacing: 8) {
                    stacking(spacing: 10) {
                        pressingWords
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NavigationLink(value: EditPage.chooseRelease) {
                            buttonWords(retag.selectedId == nil ? EditWords.chooseRelease : EditAlbumPage.Words.change)
                        }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(retag.flow.applying)
                    }
                    if let error = retag.searchError {
                        Text(error)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The pressing chosen, in iEdit's words: its title and Current, its facts in the readout face - one element for
    /// VoiceOver (EditWords.releaseRow), its tracklist loading said as its value.
    @ViewBuilder private var pressingWords: some View {
        if let shown = chosen {
            let release = shown.release
            let current = Retag.isCurrent(release, retag.album.releaseMbid)
            let differs = Retag.countDiffers(release, album: retag.album)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(release.title ?? "")
                        .fontWeight(.semibold)
                    if current {
                        DWChip(words: RetagWords.current, tone: .marked)
                    }
                    if retag.loadingId == shown.id {
                        ProgressView()
                    }
                }
                Text([Retag.detail(release), Retag.trackWords(release)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(differs ? DWPalette.amberText : DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EditWords.releaseRow(release, current: current))
            .accessibilityValue(retag.loadingId == shown.id ? EditWords.loadingTracklist
                                : differs ? EditWords.countDiffers(retag.album) : "")
        } else {
            Text(EditWords.releaseValue(retag.album, pressing: nil))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The pressing chosen, as the list found it (with its tracklist once loaded).
    private var chosen: RetagCandidate? {
        guard let id = retag.selectedId else { return nil }
        if let selected = retag.selected, selected.id == id { return selected }
        return retag.candidates.first { $0.id == id }
    }

    // MARK: the fields

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhoneGroup(legend: EditWords.fields) {
                fieldRow(EditWords.artist, field(EditWords.artist, \.artist, .artist))
                fieldRow(EditWords.album, field(EditWords.album, \.album, .album))
                yearRow(field(EditWords.year, \.year, .year, prompt: EditWords.year, digits: true),
                        field(EditWords.originalYear, \.originalYear, .originalYear,
                              prompt: RetagWords.originalPlaceholder(retag.fields.year), digits: true))
                fieldRow(EditWords.edition, field(EditWords.edition, \.editionLabel, .edition,
                                                  prompt: RetagWords.editionPlaceholder(retag.plan)))
            }
            Text(RetagWords.fieldsHint)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(retag.flow.applying)
    }

    /// A field on the look's well (DWWellField): its own focus, then Tab's, as every field of the editor's. (R10's
    /// review) The years in the readout face, as iEdit draws them (`.in.mono`) - ReleaseYearFace, set inside the well's
    /// own face, so it wins; its size the field's 16, so iOS never zooms to it.
    private func field(_ label: String, _ key: WritableKeyPath<RetagFields, String>, _ name: Field,
                       prompt: String? = nil, digits: Bool = false) -> some View {
        TextField(label, text: Binding(get: { retag.fields[keyPath: key] }, set: { retag.set(key, $0) }),
                  prompt: prompt.map { Text($0).foregroundStyle(DWPalette.t3) })
            .keyboardType(digits ? .numberPad : .default)
            .textInputAutocapitalization(digits ? .never : .words)
            .autocorrectionDisabled()
            .focused($focused, equals: name)
            .tabs($focused, in: Self.order)
            .modifier(ReleaseYearFace(digits: digits))
            .modifier(DWWellField(focus: $focused, field: name))
    }

    /// (R10's review) A field's row, as DWFieldRow's phone half draws it - its label at the left in white, 88 at least,
    /// the field beside it, the row 44 tall at least on its hairline - but stacked, the label over the field, at the
    /// accessibility sizes, as the Year row stacks: the look's DWFieldRow keeps one line at every size, so these rows
    /// are Release's own.
    private func fieldRow(_ label: String, _ field: some View) -> some View {
        row {
            fieldLabel(label)
                .frame(minWidth: CGFloat(DWLook.here.labelWidth), alignment: .leading)
            field
                .accessibilityLabel(label)
        }
    }

    /// iEdit's Year row: Year and Original on one row, a field's row with two labels - each field said by its own name
    /// (one label would name both) - stacked at the accessibility sizes.
    private func yearRow(_ year: some View, _ original: some View) -> some View {
        row {
            fieldLabel(EditWords.year)
                .frame(minWidth: CGFloat(DWLook.here.labelWidth), alignment: .leading)
            year
                .accessibilityLabel(EditWords.year)
            fieldLabel(EditAlbumPage.Words.original)
            original
                .accessibilityLabel(EditWords.originalYear)
        }
    }

    /// A row of the Fields card (`.field`): side by side, stacked at the accessibility sizes; 44 tall at least, on the
    /// group's hairline (PhoneGroup clips the last one's, as `.field:last-child` draws none).
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }

    private func fieldLabel(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Look.text(.fieldLabel))
            .foregroundStyle(DWPalette.rowText)
            .accessibilityHidden(true)
    }

    // MARK: the cover

    private var coverSection: some View {
        let existing = retag.plan?.art.existing
        let album = retag.album
        return PhoneGroup(legend: EditWords.cover) {
            PhoneCard {
                VStack(alignment: .leading, spacing: 8) {
                    stacking(spacing: 10) {
                        HStack(spacing: 10) {
                            FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 160)
                                .frame(width: 48, height: 48)
                                .clipShape(Corners.artShape)
                            if let release = retag.coverRelease {
                                ArchiveCover(addresses: ArchiveCoverID.addresses(release: release,
                                                                                 group: chosen?.groupMbid ?? ""),
                                             size: ArchiveCoverSize.row)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Corners.artShape)
                            }
                        }
                        .accessibilityHidden(true)
                        Toggle(isOn: Binding(get: { retag.fetchArt }, set: { retag.setFetchArt($0) })) {
                            Text(RetagWords.coverToggle(existing: existing))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .toggleStyle(.phoneSwitch)
                        .disabled(retag.flow.applying)
                        if retag.coverRelease != nil {
                            NavigationLink(value: EditPage.compareCovers) {
                                buttonWords(EditAlbumPage.Words.compare)
                            }
                            .buttonStyle(DWButtonStyle(size: .small))
                            .accessibilityLabel(EditWords.compareCovers)
                        }
                    }
                    Text(RetagWords.coverHint(existing: existing, size: retag.plan?.art.size))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: what Apply does

    @ViewBuilder private func applySection(_ plan: RetagPlan?) -> some View {
        PhoneGroup(legend: EditWords.whatApplyDoes) {
            PhoneCard {
                VStack(alignment: .leading, spacing: 8) {
                    if retag.flow.planning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(RetagWords.planningLabel(loadingRelease: retag.flow.loadingRelease))
                                .foregroundStyle(DWPalette.t2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    // what the last apply reported, kept on screen while the preview is redone under it
                    ForEach(retag.appliedProblems, id: \.self) { (problem: String) in
                        Text(RetagWords.problem(problem)).foregroundStyle(DWPalette.amberText)
                    }
                    if let plan, !retag.flow.planning {
                        preview(plan)
                    } else if let error = retag.previewError, !retag.flow.planning {
                        ErrorNote(text: error)
                    }
                    if let applied = retag.applied {
                        Text(applied)
                            .foregroundStyle(DWPalette.greenText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = retag.applyError {
                        ErrorNote(text: error)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, CGFloat(PhoneLook.cardPadding))
    }

    /// The preview in the web's words (MetadataEditor's): its problems, the folder's move or merge, the pause before the
    /// rename, nothing to change - or how many files would change, a row pushing each file's changes.
    @ViewBuilder private func preview(_ plan: RetagPlan) -> some View {
        ForEach(plan.problems, id: \.self) { (problem: String) in
            Text(RetagWords.problem(problem)).foregroundStyle(DWPalette.amberText)
        }
        if plan.moves {
            VStack(alignment: .leading, spacing: 3) {
                Text(RetagWords.moveLabel(plan))
                    .font(Typeface.Phone.text(.small).weight(.semibold))
                    .foregroundStyle(DWPalette.t2)
                Text(plan.albumPath)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t2)
                Text("→ \(plan.targetPath ?? "")")
                    .font(Typeface.Phone.mono(.extraSmall))
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
        if let wait = RetagWords.renameWait(plan) {
            Text(wait).font(Typeface.Phone.text(.small)).foregroundStyle(DWPalette.t2)
        }
        if let merging = RetagWords.merge(plan) {
            Text(merging).font(Typeface.Phone.text(.small))
        }
        if plan.empty {
            Text(RetagWords.nothingToChange).foregroundStyle(DWPalette.t2)
        } else if retag.applyError == nil {
            if plan.changedFileCount > 0 {
                NavigationLink(value: EditPage.changes) {
                    HStack(spacing: CGFloat(PhoneLook.goGap)) {
                        Text(RetagWords.changeSummary(plan))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PhoneChevron()
                    }
                    // (R10's review) every change, a finger's 44 tall at least however short its words
                    .frame(minHeight: CGFloat(DWLook.here.target))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(RetagWords.changeSummary(plan))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: the cards' parts

    /// A card's row: side by side, the trailing parts stacked under at the accessibility sizes.
    private func stacking<Content: View>(spacing: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        return layout { content() }
    }

    /// A button's words: three lines at the accessibility sizes, one otherwise.
    private func buttonWords(_ words: String) -> some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}

/// (R10's review) A year field's face on the phone: the readout's (`.in.mono`) at the field's 16, set inside
/// DWWellField's own face so it wins there; a field of words keeps the well's.
private struct ReleaseYearFace: ViewModifier {
    let digits: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if digits {
            content.font(Typeface.Look.mono(.field))
        } else {
            content
        }
    }
}

/// Release's foot on the phone (iEdit's .foot2): Revert - the typed work put back as the folder has it - and Apply,
/// the purple one, growing. Apply sends the preview's very body (EditAlbumModel.apply): the server works the plan out
/// again from it, never a plan sent back. While it runs it says what it waits for, the sheet's Close off and its swipe
/// held (EditAlbumSheet).
struct ReleaseFoot: View {
    let model: EditAlbumModel
    let retag: RetagModel
    /// (R12 - notes/ios.md "The redesign, slice R12: Needs a look") Queue mode's bar, the sheet's: once a release was
    /// applied and an album follows, the purple button is Next album, a step through the sheet's `take` as Skip › is
    /// (NeedsLookPage.movesOn - the web's Apply becoming Next album); the last album keeps Apply.
    var queue: EditQueueBar? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let plan = retag.currentPlan
        Button {
            model.revertRelease()
        } label: {
            words(EditAlbumPage.Words.revert)
        }
        .buttonStyle(DWButtonStyle(size: .large))
        .disabled(!model.canRevertRelease)
        if let queue, NeedsLookPage.movesOn(queue.nav, applied: retag.applied != nil) {
            Button {
                queue.take(1)
            } label: {
                words(NeedsLookWords.nextAlbum)
            }
            .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
            .accessibilityLabel(NeedsLookWords.nextAlbumSpoken)
            .disabled(!model.canStep)
        } else {
            Button {
                Task { await model.apply() }
            } label: {
                HStack(spacing: 10) {
                    if retag.flow.applying { ProgressView() }
                    words(retag.flow.applying ? RetagWords.applying(plan ?? retag.plan) : RetagWords.apply)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
            .disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)
        }
    }

    private func words(_ said: String) -> some View {
        Text(said)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}

/// A pressing as Choose a release and Release draw it: its title and artist, its year and description, its track count
/// (amber when it isn't the folder's - the web's `mismatch`), "Current" when the folder is tagged with it, a spinner
/// while its tracklist loads. VoiceOver reads it as one (EditWords.releaseRow).
struct RetagPressingRow: View {
    let candidate: RetagCandidate
    let album: ScanAlbum
    let loading: Bool

    var body: some View {
        let release = candidate.release
        let current = Retag.isCurrent(release, album.releaseMbid)
        let differs = Retag.countDiffers(release, album: album)
        HStack(alignment: .top, spacing: 12) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: release.id, group: candidate.groupMbid ?? ""),
                         size: ArchiveCoverSize.row)
                .frame(width: 44, height: 44)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(release.title ?? "")
                        .font(Typeface.body.weight(.semibold))
                    if current {
                        Text(RetagWords.current)
                            .font(Typeface.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Palette.badgeFill, in: Corners.controlShape)
                            .foregroundStyle(Palette.accentText)
                    }
                }
                let artist = Credits.name(release.artistCredit)
                if !artist.isEmpty {
                    Text(artist).font(Typeface.subheadline).foregroundStyle(Palette.quiet)
                }
                let detail = Retag.detail(release)
                if !detail.isEmpty {
                    Text(detail).font(Typeface.footnote).foregroundStyle(Palette.quiet)
                }
                Text(Retag.trackWords(release))
                    .font(Typeface.footnote)
                    .foregroundStyle(differs ? Palette.amber : Palette.quiet)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if loading {
                ProgressView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EditWords.releaseRow(release, current: current))
        .accessibilityValue(loading ? EditWords.loadingTracklist : differs ? EditWords.countDiffers(album) : "")
    }
}

/// Choose a release (phase8-managing.md 3.3): MusicBrainz's pressings for the album, best first - a flat list, as the
/// web's ("an edition IS a release"). The search field, blank, searches the fielded query (its placeholder the plain
/// one); submitted, what was typed. A tap loads the pressing's tracklist, fills the fields and goes back.
///
/// (R20 - notes/ios.md "The panel review, R20: the known holdouts (2026-11-26)") No List: the page's black, each pressing
/// R10's RetagPressingRow as it was on a row's hairline, the chosen one marked by the accent's tick (no grey fill) and
/// said selected. iOS's search field stays at the top: a field is where you type, and it keeps its well. A tap still
/// only chooses - it fills the fields, and Apply on Release's foot is what writes.
struct ChooseReleaseView: View {
    let retag: RetagModel
    @Binding var path: [EditPage]

    var body: some View {
        @Bindable var retag = retag
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if retag.flow.searching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(RetagWords.searching)
                            .font(Typeface.Phone.text(.row))
                            .foregroundStyle(DWPalette.t2)
                    }
                    .releaseListRow()
                    .accessibilityElement(children: .combine)
                } else if let error = retag.searchError {
                    Text(error)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                        .releaseListRow()
                } else if retag.searched && retag.candidates.isEmpty {
                    Text(RetagWords.noReleases)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.t2)
                        .releaseListRow()
                } else if !retag.searched {
                    Text(RetagWords.notSearched)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.t2)
                        .releaseListRow()
                }
                if !retag.candidates.isEmpty, !retag.album.releaseMbid.isEmpty, !retag.foundCurrent {
                    Text(RetagWords.currentMissing)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .releaseListRow()
                }
                ForEach(retag.candidates) { (candidate: RetagCandidate) in
                    let chosen = retag.selectedId == candidate.id
                    Button {
                        retag.pick(candidate)
                        if path.last == .chooseRelease { path.removeLast() }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            RetagPressingRow(candidate: candidate, album: retag.album, loading: retag.loadingId == candidate.id)
                            if chosen {
                                Image(systemName: "checkmark")
                                    .font(Typeface.Phone.text(.row).weight(.semibold))
                                    .foregroundStyle(DWPalette.acc)
                                    .accessibilityHidden(true)
                            }
                        }
                        .releaseListRow()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(retag.flow.applying || !retag.flow.online)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.groupAbove))
        }
        .background(DWPalette.page)
        .navigationTitle(EditWords.chooseRelease)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $retag.typed, placement: .navigationBarDrawer(displayMode: .always), prompt: retag.searchPrompt)
        .onSubmit(of: .search) {
            Task { await retag.search() }
        }
        .pullToRefresh {
            await retag.search()
        }
    }
}

/// Changes (phase8-managing.md 3.3): each file the preview would change, its tags old to new - the web's preview list,
/// in the server's order. (R20) No List: on the page's black, each file's name in the readout face as its heading, its
/// changes under it on their hairlines - the tag, the old value struck through, the new one in white.
struct ChangesView: View {
    let plan: RetagPlan

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(plan.changedFiles.enumerated()), id: \.offset) { (_, file: RetagFileChange) in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.filename)
                            .font(Typeface.Phone.mono(.small))
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, CGFloat(PhoneLook.groupAbove))
                            .padding(.bottom, ReleaseListLook.headingBelow)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(file.changes, id: \.self) { (change: TagChange) in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.tag)
                                    .font(Typeface.Phone.text(.small).weight(.semibold))
                                    .foregroundStyle(DWPalette.t2)
                                Text(change.from.isEmpty ? "—" : change.from)
                                    .font(Typeface.Phone.text(.row))
                                    .foregroundStyle(DWPalette.t2)
                                    .strikethrough(!change.from.isEmpty)
                                Text(change.to)
                                    .font(Typeface.Phone.text(.row))
                                    .foregroundStyle(DWPalette.text)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .releaseListRow()
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(change.tag): \(change.from.isEmpty ? "—" : change.from), \(change.to)")
                        }
                    }
                }
            }
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.groupAbove))
        }
        .background(DWPalette.page)
        .navigationTitle(EditWords.changes)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Compare covers (phase8-managing.md 3.3; the web's ArtViewer from the editor): the folder's cover beside the
/// pressing's - the one chosen, else the one the folder is tagged with - through deadwax's relay of the Cover Art
/// Archive, never the Archive directly. A tap on either opens it full screen. Replace cover only (Save cover only, with
/// none there) writes the pressing's cover into the folder and changes nothing else - on only once its cover has come.
///
/// (R20) No List: the two covers side by side on the page's black, a cover not there drawn as its square's hairline with
/// why inside (no grey fill); Replace cover only the purple, the page's width, what it did and its note under it.
struct CompareCoversView: View {
    let model: EditAlbumModel
    let retag: RetagModel
    let album: ScanAlbum

    @Environment(ServerModel.self) private var server
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var incoming: UIImage?
    @State private var looked = false
    @State private var full: FullCover?

    var body: some View {
        let release = retag.coverRelease
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    side(label: RetagWords.compareCurrent) {
                        if album.art.isEmpty {
                            missing(RetagWords.compareNoCover)
                        } else {
                            Button {
                                full = FullCover(source: .folder(album.path, album.artMtime))
                            } label: {
                                FolderCover(path: album.path, mtime: album.artMtime, hasArt: true, pixels: 600)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(RetagWords.compareCurrent) - \(EditWords.coverFullScreen)")
                        }
                    }
                    side(label: retag.selectedId != nil ? RetagWords.compareFromThis : RetagWords.compareFromTagged) {
                        if let incoming, let release {
                            Button {
                                full = FullCover(source: .release(release))
                            } label: {
                                Image(uiImage: incoming)
                                    .resizable()
                                    .scaledToFit()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(retag.selectedId != nil ? RetagWords.compareFromThis : RetagWords.compareFromTagged) - \(EditWords.coverFullScreen)")
                        } else if release == nil {
                            missing(RetagWords.comparePick)
                        } else if looked {
                            missing(RetagWords.compareArchiveNone)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { Rectangle().strokeBorder(DWPalette.line, lineWidth: 1) }
                        }
                    }
                }
                .padding(.top, CGFloat(PhoneLook.groupAbove))
                if release != nil {
                    VStack(alignment: .leading, spacing: ReleaseListLook.footGap) {
                        Button {
                            Task { await model.saveCoverOnly() }
                        } label: {
                            HStack(spacing: 10) {
                                if retag.savingCover { ProgressView() }
                                Text(retag.savingCover ? EditWords.savingCover : RetagWords.coverOnly(hasArt: !album.art.isEmpty))
                                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                        // only once the pressing's cover has come (what it saves is what was looked at), no write under
                        // way, and the folder read since the last gap or write (RetagFlow.canSaveCover)
                        .disabled(incoming == nil || !retag.flow.canSaveCover || model.tagsApplying || model.getting
                                  || model.deleting)
                        if let result = retag.coverResult {
                            Text(result)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(RetagWords.coverOnlyHint(hasArt: !album.art.isEmpty))
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, CGFloat(PhoneLook.groupAbove))
                }
            }
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.groupAbove))
        }
        .background(DWPalette.page)
        .navigationTitle(EditWords.compareCovers.replacingOccurrences(of: "…", with: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: release ?? "") {
            incoming = nil
            looked = false
            guard let release, let client = server.client else { return }
            let got = await CoverCache.shared.loadArchive(client: client, cover: ArchiveCoverID(.release, release),
                                                          size: ArchiveCoverSize.compare)
            guard !Task.isCancelled else { return }
            incoming = got
            looked = true
        }
        .appCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
                .macSheet()
        }
    }

    private func side<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typeface.Phone.text(.small).weight(.semibold))
                .foregroundStyle(DWPalette.t2)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// A cover that isn't there: its square's hairline, why inside it.
    private func missing(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay { Rectangle().strokeBorder(DWPalette.line, lineWidth: 1) }
    }
}

/// (R20) Choose a release's and Changes' rows: 10 above and below, the page's width, on a row's hairline (`.dw.ph .row`).
private enum ReleaseListLook {
    static let rowRoom: CGFloat = 10
    /// Under a file's name in Changes, over its first row.
    static let headingBelow: CGFloat = 6
    /// Between Replace cover only, what it did and its note.
    static let footGap: CGFloat = 10
}

private extension View {
    func releaseListRow() -> some View {
        padding(.vertical, ReleaseListLook.rowRoom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
    }
}

/// A cover opened full screen from Compare covers: the folder's as it is, or the pressing's from the relay at its
/// largest - and (slice 2) a picture inside a track, from a track's page; (slice 3) a CD art picture beside the tracks,
/// from Artwork.
struct FullCover: Identifiable {
    enum Source {
        case folder(String, Double)
        case release(String)
        case picture(path: String, file: String, index: Int)
        case discArt(path: String, file: String)
    }

    let id = UUID()
    let source: Source
}

/// The cover, full screen (EditWords.coverFullScreen): on black, fitted, Close at the top - and a tap anywhere closes it.
/// (R20) The black is the page's (DWPalette.page), Close the look's button - flat accent words on the phone, the Mac's
/// button on the Mac, where Artwork and Tags open it too.
struct FullCoverView: View {
    let cover: FullCover

    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    /// A picture fetched for itself (not a cover) that couldn't be.
    @State private var failed = false

    /// What VoiceOver says of it: a CD art picture by its name, anything else as the cover.
    private var label: String {
        if case .discArt(_, let file) = cover.source { return file }
        return EditWords.coverFullScreen
    }

    var body: some View {
        ZStack {
            DWPalette.page.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(label)
            } else if failed {
                Text(EditWords.pictureFailed)
                    .font(Typeface.Look.text(.field))
                    .foregroundStyle(DWPalette.text)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                HoldoutWords(EditWords.close)
            }
            .buttonStyle(DWButtonStyle())
            .escapeCloses()
            .padding()
        }
        .task {
            guard let client = server.client else { return }
            switch cover.source {
            case .folder(let path, let mtime):
                image = await FolderCoverCache.shared.load(client: client, path: path, mtime: mtime, pixels: 0)
            case .release(let mbid):
                image = await CoverCache.shared.loadArchive(client: client, cover: ArchiveCoverID(.release, mbid),
                                                            size: ArchiveCoverSize.hero)
            case .picture(let path, let file, let index):
                let data = try? await client.trackPicture(path: path, file: file, index: index)
                image = data.flatMap { UIImage(data: $0) }
                failed = image == nil
            case .discArt(let path, let file):
                let data = try? await client.libraryDiscArt(path: path, file: file)
                image = data.flatMap { UIImage(data: $0) }
                failed = image == nil
            }
        }
    }
}
