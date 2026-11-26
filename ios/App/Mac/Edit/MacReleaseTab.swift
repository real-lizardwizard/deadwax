import DeadwaxCore
import SwiftUI

/// The Mac's Edit album, its Release tab (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album,
/// the folder list and Release"; Main.dc.html): the phone's Release and Choose a release on one tab - Pressing (the
/// MusicBrainz search, Find releases and the pressings found, best first, one picked filling the fields), Fields,
/// Cover (the folder's and the pressing's, Replace cover.jpg, Compare full size… in a sheet) and What Apply does, its
/// every change shown under it on asking. Two columns from an editor of 620, one under it; Needs a look's issues and
/// marks over them, as the web's Release tab has them.
///
/// Every rule is the phone's (RetagModel, EditAlbumModel): the same fields set the same way, the same search, the same
/// preview - and Apply, in the foot (MacEditFooter), sends the preview's body for the server to plan again. Return in
/// a field applies nothing: in the search it searches, elsewhere it does nothing; Tab follows the order drawn.
struct MacReleaseTab: View {
    let model: EditAlbumModel
    let retag: RetagModel
    let twoColumns: Bool
    /// Compare full size…: the comparison opened over the page (MacEditWindow's sheet).
    let compare: () -> Void

    @Environment(ServerModel.self) private var server
    @FocusState private var focused: Field?
    @State private var showingChanges = false

    private enum Field: Hashable {
        case search, artist, album, year, originalYear, edition
    }

    /// The fields in the order the tab draws them: Tab's.
    private static let order: [Field] = [.search, .artist, .album, .year, .originalYear, .edition]

    var body: some View {
        let plan = retag.currentPlan
        VStack(alignment: .leading, spacing: 18) {
            needsALook
            if twoColumns {
                HStack(alignment: .top, spacing: 14) {
                    pressingBox
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 18) {
                        fieldsBox
                        coverBox
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                pressingBox
                fieldsBox
                coverBox
            }
            applyBox(plan)
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(DWPalette.text)
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
    }

    // MARK: Needs a look

    /// The issues the album still has and what was marked fine - It's fine as it is and Ask about it again with Look
    /// after the library too (AlbumEdit.marksFine), as the phone's root has them.
    @ViewBuilder private var needsALook: some View {
        let album = retag.album
        let outstanding = MetadataQueue.outstanding(album)
        let fine = MetadataQueue.markedFine(album)
        let types = model.scan.answer?.issueTypes ?? [:]
        let marks = AlbumEdit.marksFine(server.access.permissions)
        if !outstanding.isEmpty || !fine.isEmpty {
            MacGroupBox(legend: EditWords.needsALook) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(outstanding, id: \.self) { (code: String) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MetadataQueue.label(code, types))
                                .fontWeight(.semibold)
                                .foregroundStyle(DWPalette.amberText)
                            let hint = MetadataQueue.hint(code, types)
                            if !hint.isEmpty {
                                Text(hint)
                                    .font(Typeface.Mac.text(.small))
                                    .foregroundStyle(DWPalette.t2)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                    if !fine.isEmpty {
                        Text(RetagWords.markedFine(fine.map { MetadataQueue.label($0, types) }))
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if marks {
                        HStack(spacing: 8) {
                            if !outstanding.isEmpty {
                                Button(model.marking ? RetagWords.markingFine : RetagWords.fine) {
                                    Task { await model.markFine() }
                                }
                                .buttonStyle(DWButtonStyle(size: .small))
                                .disabled(!model.online || model.marking || model.writing)
                            }
                            if !fine.isEmpty {
                                Button(RetagWords.askAgain) {
                                    Task { await model.askAgain() }
                                }
                                .buttonStyle(DWButtonStyle(size: .small))
                                .disabled(!model.online || model.marking || model.writing)
                            }
                        }
                    }
                    if let failure = model.markFailure {
                        ErrorNote(text: failure)
                    }
                }
            }
        }
    }

    // MARK: Pressing

    private var pressingBox: some View {
        MacGroupBox(legend: EditAlbumPage.Words.pressing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    well(TextField(EditAlbumPage.Words.musicBrainzSearch,
                                   text: Binding(get: { retag.typed }, set: { retag.typed = $0 }),
                                   prompt: Text(retag.searchPrompt).foregroundStyle(DWPalette.t3)),
                         .search, mono: true)
                        .onSubmit { findReleases() }
                    Button(EditAlbumPage.Words.findReleases) { findReleases() }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(!retag.flow.online || retag.flow.applying)
                }
                searchState
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(retag.candidates) { (candidate: RetagCandidate) in
                        pressingRow(candidate)
                    }
                }
            }
        }
    }

    /// Find releases (and Return in the search): MusicBrainz searched - nothing written.
    private func findReleases() {
        guard retag.flow.online, !retag.flow.applying else { return }
        Task { await retag.search() }
    }

    @ViewBuilder private var searchState: some View {
        if retag.flow.searching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(RetagWords.searching).foregroundStyle(DWPalette.t2)
            }
            .accessibilityElement(children: .combine)
        } else if let error = retag.searchError {
            Text(error)
                .foregroundStyle(DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
        } else if retag.searched && retag.candidates.isEmpty {
            Text(RetagWords.noReleases).foregroundStyle(DWPalette.t2)
        } else if !retag.searched {
            Text(RetagWords.notSearched).foregroundStyle(DWPalette.t2)
        }
        if !retag.candidates.isEmpty, !retag.album.releaseMbid.isEmpty, !retag.foundCurrent {
            Text(RetagWords.currentMissing)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A pressing found (the drawing's `.item`): its title and Current, its facts in the readout face, its track count -
    /// amber when it isn't the folder's - and a spinner while its tracklist loads; the one chosen in the selection's
    /// colours. One element for VoiceOver (EditWords.releaseRow).
    private func pressingRow(_ candidate: RetagCandidate) -> some View {
        let release = candidate.release
        let current = Retag.isCurrent(release, retag.album.releaseMbid)
        let differs = Retag.countDiffers(release, album: retag.album)
        let chosen = retag.selectedId == candidate.id
        let loading = retag.loadingId == candidate.id
        return Button {
            retag.pick(candidate)
        } label: {
            // the track count on the title's baseline, the spinner centred on its words
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(release.title ?? "")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if current {
                            DWChip(words: RetagWords.current, tone: .marked)
                        }
                    }
                    let detail = Retag.detail(release)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Typeface.Mac.mono(.label))
                            .foregroundStyle(DWPalette.t2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if loading {
                    ProgressView().controlSize(.small)
                        .centredOnWords(CGFloat(Typeface.Mac.Size.base.rawValue))
                }
                Text(Retag.trackWords(release))
                    .font(Typeface.Mac.mono(.label))
                    .foregroundStyle(differs ? DWPalette.amberText : DWPalette.t3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if chosen {
                    DWCorners.boxShape.fill(DWPalette.selbg)
                }
            }
            .overlay(DWCorners.boxShape.strokeBorder(chosen ? DWPalette.selbd : DWPalette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(retag.flow.applying || !retag.flow.online)
        .help(EditWords.releaseRow(release, current: current))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EditWords.releaseRow(release, current: current))
        .accessibilityValue(loading ? EditWords.loadingTracklist : differs ? EditWords.countDiffers(retag.album) : "")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Fields

    private var fieldsBox: some View {
        MacGroupBox(legend: EditWords.fields) {
            VStack(alignment: .leading, spacing: 6) {
                DWFieldRow(label: EditWords.artist) {
                    field(EditWords.artist, \.artist, .artist)
                }
                DWFieldRow(label: EditWords.album) {
                    field(EditWords.album, \.album, .album)
                }
                // Year and Original year on one row, each said by its own name - the label centred on its well, as
                // DWFieldRow lays every field
                HStack(spacing: 8) {
                    DWFieldRow(label: EditWords.year) {
                        field(EditWords.year, \.year, .year, prompt: EditWords.year, mono: true)
                    }
                    Text(EditWords.originalYear)
                        .font(Typeface.Look.text(.fieldLabel))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    field(EditWords.originalYear, \.originalYear, .originalYear,
                          prompt: RetagWords.originalPlaceholder(retag.fields.year), mono: true)
                        .accessibilityLabel(EditWords.originalYear)
                }
                DWFieldRow(label: EditWords.edition) {
                    field(EditWords.edition, \.editionLabel, .edition, prompt: RetagWords.editionPlaceholder(retag.plan))
                }
                Text(RetagWords.fieldsHint)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, CGFloat(DWLook.here.labelWidth) + 8)
                    .padding(.top, 4)
            }
            .disabled(retag.flow.applying)
        }
    }

    private func field(_ label: String, _ key: WritableKeyPath<RetagFields, String>, _ which: Field,
                       prompt: String? = nil, mono: Bool = false) -> some View {
        well(TextField(label, text: Binding(get: { retag.fields[keyPath: key] }, set: { retag.set(key, $0) }),
                       prompt: prompt.map { Text($0).foregroundStyle(DWPalette.t3) }),
             which, mono: mono)
    }

    /// A field on the look's well (MacRequestsPage's): its focus, Tab's order, a click on the well putting the cursor in.
    private func well<Input: View>(_ input: Input, _ which: Field, mono: Bool = false) -> some View {
        faced(input.textFieldStyle(.plain), mono: mono)
            .foregroundStyle(DWPalette.fieldText)
            .autocorrectionDisabled()
            .focused($focused, equals: which)
            .tabs($focused, in: Self.order)
            .focusEffectDisabled()
            // .in: padding 0 8px
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: focused == which)
                    .contentShape(DWTarget(face: DWCorners.buttonShape))
                    .onTapGesture { focused = which }
            }
    }

    /// A field's face: the readout's for the search and the years (digits), the look's field face for words.
    @ViewBuilder private func faced<Input: View>(_ input: Input, mono: Bool) -> some View {
        if mono {
            input.font(Typeface.Mac.mono(.label))
        } else {
            input.font(Typeface.Look.text(.field))
        }
    }

    // MARK: Cover

    private var coverBox: some View {
        let existing = retag.plan?.art.existing
        let album = retag.album
        return MacGroupBox(legend: EditWords.cover) {
            HStack(alignment: .top, spacing: 10) {
                cover(EditAlbumPage.Words.inTheFolder) {
                    FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 200)
                }
                cover(EditAlbumPage.Words.thisPressing) {
                    if let release = retag.coverRelease {
                        ArchiveCover(addresses: ArchiveCoverID.addresses(release: release, group: groupOf(release)),
                                     size: ArchiveCoverSize.row)
                    } else {
                        Rectangle().fill(DWPalette.well)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Toggle(isOn: Binding(get: { retag.fetchArt }, set: { retag.setFetchArt($0) })) {
                        Text(RetagWords.coverToggle(existing: existing))
                    }
                    .disabled(retag.flow.applying)
                    Text(RetagWords.coverHint(existing: existing, size: retag.plan?.art.size))
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                    if retag.coverRelease != nil {
                        Button(EditAlbumPage.Words.compareFullSize, action: compare)
                            .buttonStyle(DWButtonStyle(size: .small))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func cover<Picture: View>(_ caption: String, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(spacing: 4) {
            picture()
                .frame(width: 64, height: 64)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
                .accessibilityHidden(true)
            Text(caption)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t3)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The pressing's release group, as the list found it - the Archive's fallback for its cover.
    private func groupOf(_ release: String) -> String {
        if let selected = retag.selected, selected.id == release { return selected.groupMbid ?? "" }
        return retag.candidates.first { $0.id == release }?.groupMbid ?? ""
    }

    // MARK: What Apply does

    private func applyBox(_ plan: RetagPlan?) -> some View {
        MacGroupBox(legend: EditWords.whatApplyDoes) {
            VStack(alignment: .leading, spacing: 8) {
                if retag.flow.planning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
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

    /// The preview in the web's words: its problems, the move or merge and the pause before the rename, nothing to
    /// change - or how many files would change, and Show every change listing each file's tags old to new.
    @ViewBuilder private func preview(_ plan: RetagPlan) -> some View {
        ForEach(plan.problems, id: \.self) { (problem: String) in
            Text(RetagWords.problem(problem)).foregroundStyle(DWPalette.amberText)
        }
        if plan.moves {
            VStack(alignment: .leading, spacing: 2) {
                Text(RetagWords.moveLabel(plan))
                    .font(Typeface.Mac.text(.small).weight(.semibold))
                    .foregroundStyle(DWPalette.t2)
                Text(plan.albumPath)
                    .font(Typeface.Mac.mono(.label))
                    .foregroundStyle(DWPalette.t2)
                Text("→ \(plan.targetPath ?? "")")
                    .font(Typeface.Mac.mono(.label))
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
        if let wait = RetagWords.renameWait(plan) {
            Text(wait).font(Typeface.Mac.text(.small)).foregroundStyle(DWPalette.t2)
        }
        if let merging = RetagWords.merge(plan) {
            Text(merging).font(Typeface.Mac.text(.small))
        }
        if plan.empty {
            Text(RetagWords.nothingToChange).foregroundStyle(DWPalette.t2)
        } else if retag.applyError == nil {
            HStack(spacing: 8) {
                Text(RetagWords.changeSummary(plan))
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if plan.changedFileCount > 0 {
                    Button(showingChanges ? EditAlbumPage.Words.hideChanges : EditAlbumPage.Words.showChanges) {
                        showingChanges.toggle()
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            if showingChanges, plan.changedFileCount > 0 {
                changes(plan)
            }
        }
    }

    /// Every file's changes, in the server's order, in a well in the readout face: each tag, what it was, what it will
    /// be.
    private func changes(_ plan: RetagPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(plan.changedFiles.enumerated()), id: \.offset) { (_, file: RetagFileChange) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .foregroundStyle(DWPalette.t2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(file.changes, id: \.self) { (change: TagChange) in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(change.tag)
                                .foregroundStyle(DWPalette.t2)
                                .frame(width: 150, alignment: .leading)
                            Text(change.from.isEmpty ? "—" : change.from)
                                .foregroundStyle(DWPalette.t3)
                            Text("→")
                                .foregroundStyle(DWPalette.t3)
                                .accessibilityHidden(true)
                            Text(change.to)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(change.tag): \(change.from.isEmpty ? "—" : change.from), \(change.to)")
                    }
                }
            }
        }
        .font(Typeface.Mac.mono(.label))
        .textSelection(.enabled)
        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DWWell(focused: false) }
    }
}
