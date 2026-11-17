import DeadwaxCore
import SwiftUI
import UIKit

/// Edit album's Release (notes/ios-specs/phase8-managing.md 3.3; the web's MetadataEditor, split over pages): the
/// pressing chosen (pushing Choose a release), the fields, the cover, What Apply does - the preview, drawn in the web's
/// words, its changes a row pushing Changes - and Apply under it. Apply is on only for a preview of what the page shows
/// now that changes something, with nothing loading and deadwax in reach (RetagFlow.canApply); while it runs it says
/// what it waits for (RetagWords.applying), and after, what it did - the folder read again and the album followed by
/// EditAlbumModel. Every word is Core's.
struct ReleasePage: View {
    let model: EditAlbumModel
    let retag: RetagModel

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case artist, album, year, originalYear, edition
    }

    var body: some View {
        let plan = retag.currentPlan
        Form {
            if retag.flow.mayHaveFinished {
                Section {
                    MayHaveFinished(reading: model.scan.reading)
                }
            }
            // the folder couldn't be read again after a write or a gap: the wait ends here, said, with Look again
            if retag.flow.readFailed {
                Section {
                    ReadAgainFailed(model: model)
                }
            }
            pressingSection
            fieldsSection
            coverSection
            applySection(plan)
        }
        .navigationTitle(EditWords.release)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AlbumInfoWords.done) { focused = nil }
            }
        }
    }

    // MARK: the pressing

    private var pressingSection: some View {
        Section {
            NavigationLink(value: EditPage.chooseRelease) {
                if let shown = chosen {
                    RetagPressingRow(candidate: shown, album: retag.album, loading: retag.loadingId == shown.id)
                } else {
                    Text(EditWords.chooseRelease)
                }
            }
            .disabled(retag.flow.applying)
            if let error = retag.searchError {
                Text(error)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(EditWords.release)
                .font(Typeface.footnote)
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
        Section {
            field(EditWords.artist, \.artist, .artist)
            field(EditWords.album, \.album, .album)
            field(EditWords.year, \.year, .year, prompt: EditWords.year, digits: true)
            field(EditWords.originalYear, \.originalYear, .originalYear,
                  prompt: RetagWords.originalPlaceholder(retag.fields.year), digits: true)
            field(EditWords.edition, \.editionLabel, .edition, prompt: RetagWords.editionPlaceholder(retag.plan))
        } header: {
            Text(EditWords.fields)
                .font(Typeface.footnote)
        } footer: {
            Text(RetagWords.fieldsHint)
                .font(Typeface.footnote)
        }
        .disabled(retag.flow.applying)
    }

    private func field(_ label: String, _ key: WritableKeyPath<RetagFields, String>, _ name: Field,
                       prompt: String? = nil, digits: Bool = false) -> some View {
        LabeledContent(label) {
            TextField(label, text: Binding(get: { retag.fields[keyPath: key] }, set: { retag.set(key, $0) }),
                      prompt: prompt.map { Text($0) })
                .multilineTextAlignment(.trailing)
                .keyboardType(digits ? .numberPad : .default)
                .textInputAutocapitalization(digits ? .never : .words)
                .autocorrectionDisabled()
                .focused($focused, equals: name)
        }
    }

    // MARK: the cover

    private var coverSection: some View {
        let existing = retag.plan?.art.existing
        return Section {
            Toggle(isOn: Binding(get: { retag.fetchArt }, set: { retag.setFetchArt($0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(RetagWords.coverToggle(existing: existing))
                    Text(RetagWords.coverHint(existing: existing, size: retag.plan?.art.size))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(retag.flow.applying)
            if retag.coverRelease != nil {
                NavigationLink(value: EditPage.compareCovers) {
                    Text(EditWords.compareCovers)
                }
            }
        } header: {
            Text(EditWords.cover)
                .font(Typeface.footnote)
        }
    }

    // MARK: what Apply does, and Apply

    @ViewBuilder private func applySection(_ plan: RetagPlan?) -> some View {
        Section {
            if retag.flow.planning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(RetagWords.planningLabel(loadingRelease: retag.flow.loadingRelease))
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            }
            // what the last apply reported, kept on screen while the preview is redone under it
            ForEach(retag.appliedProblems, id: \.self) { (problem: String) in
                Text(RetagWords.problem(problem)).foregroundStyle(Palette.amber)
            }
            if let plan, !retag.flow.planning {
                preview(plan)
            } else if let error = retag.previewError, !retag.flow.planning {
                ErrorNote(text: error)
            }
            if let applied = retag.applied {
                Text(applied)
                    .foregroundStyle(Palette.held)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = retag.applyError {
                ErrorNote(text: error)
            }
        } header: {
            Text(EditWords.whatApplyDoes)
                .font(Typeface.footnote)
        }
        Section {
            Button {
                Task { await model.apply() }
            } label: {
                HStack(spacing: 10) {
                    if retag.flow.applying { ProgressView() }
                    Text(retag.flow.applying ? RetagWords.applying(plan ?? retag.plan) : RetagWords.apply)
                        .font(Typeface.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)
        }
    }

    /// The preview in the web's words (MetadataEditor's): its problems, the folder's move or merge, the pause before the
    /// rename, nothing to change - or how many files would change, a row pushing each file's changes.
    @ViewBuilder private func preview(_ plan: RetagPlan) -> some View {
        ForEach(plan.problems, id: \.self) { (problem: String) in
            Text(RetagWords.problem(problem)).foregroundStyle(Palette.amber)
        }
        if plan.moves {
            VStack(alignment: .leading, spacing: 3) {
                Text(RetagWords.moveLabel(plan))
                    .font(Typeface.footnote.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                Text(plan.albumPath)
                    .font(Typeface.mono(.footnote))
                    .foregroundStyle(Palette.quiet)
                Text("→ \(plan.targetPath ?? "")")
                    .font(Typeface.mono(.footnote))
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
        if let wait = RetagWords.renameWait(plan) {
            Text(wait).font(Typeface.footnote).foregroundStyle(Palette.quiet)
        }
        if let merging = RetagWords.merge(plan) {
            Text(merging).font(Typeface.footnote)
        }
        if plan.empty {
            Text(RetagWords.nothingToChange).foregroundStyle(Palette.quiet)
        } else if retag.applyError == nil {
            if plan.changedFileCount > 0 {
                NavigationLink(value: EditPage.changes) {
                    Text(RetagWords.changeSummary(plan))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(RetagWords.changeSummary(plan))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
struct ChooseReleaseView: View {
    let retag: RetagModel
    @Binding var path: [EditPage]

    var body: some View {
        @Bindable var retag = retag
        List {
            if retag.flow.searching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(RetagWords.searching).foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            } else if let error = retag.searchError {
                Text(error)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if retag.searched && retag.candidates.isEmpty {
                Text(RetagWords.noReleases).foregroundStyle(Palette.quiet)
            } else if !retag.searched {
                Text(RetagWords.notSearched).foregroundStyle(Palette.quiet)
            }
            if !retag.candidates.isEmpty, !retag.album.releaseMbid.isEmpty, !retag.foundCurrent {
                Text(RetagWords.currentMissing)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            ForEach(retag.candidates) { (candidate: RetagCandidate) in
                Button {
                    retag.pick(candidate)
                    if path.last == .chooseRelease { path.removeLast() }
                } label: {
                    RetagPressingRow(candidate: candidate, album: retag.album, loading: retag.loadingId == candidate.id)
                }
                .buttonStyle(.plain)
                .disabled(retag.flow.applying || !retag.flow.online)
                .listRowBackground(retag.selectedId == candidate.id ? Palette.toggledFill : nil)
            }
        }
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
/// in the server's order.
struct ChangesView: View {
    let plan: RetagPlan

    var body: some View {
        List {
            ForEach(Array(plan.changedFiles.enumerated()), id: \.offset) { (_, file: RetagFileChange) in
                Section {
                    ForEach(file.changes, id: \.self) { (change: TagChange) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.tag)
                                .font(Typeface.footnote.weight(.semibold))
                                .foregroundStyle(Palette.quiet)
                            Text(change.from.isEmpty ? "—" : change.from)
                                .foregroundStyle(Palette.quiet)
                                .strikethrough(!change.from.isEmpty)
                            Text(change.to)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(change.tag): \(change.from.isEmpty ? "—" : change.from), \(change.to)")
                    }
                } header: {
                    Text(file.filename)
                        .font(Typeface.mono(.footnote))
                        .textCase(nil)
                }
            }
        }
        .navigationTitle(EditWords.changes)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Compare covers (phase8-managing.md 3.3; the web's ArtViewer from the editor): the folder's cover beside the
/// pressing's - the one chosen, else the one the folder is tagged with - through deadwax's relay of the Cover Art
/// Archive, never the Archive directly. A tap on either opens it full screen. Replace cover only (Save cover only, with
/// none there) writes the pressing's cover into the folder and changes nothing else - on only once its cover has come.
struct CompareCoversView: View {
    let model: EditAlbumModel
    let retag: RetagModel
    let album: ScanAlbum

    @Environment(ServerModel.self) private var server
    @State private var incoming: UIImage?
    @State private var looked = false
    @State private var full: FullCover?

    var body: some View {
        let release = retag.coverRelease
        List {
            Section {
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
                            ZStack {
                                Rectangle().fill(Palette.coverEmpty)
                                ProgressView()
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if release != nil {
                Section {
                    Button {
                        Task { await model.saveCoverOnly() }
                    } label: {
                        HStack(spacing: 10) {
                            if retag.savingCover { ProgressView() }
                            Text(retag.savingCover ? EditWords.savingCover : RetagWords.coverOnly(hasArt: !album.art.isEmpty))
                        }
                    }
                    // only once the pressing's cover has come (what it saves is what was looked at), no write under
                    // way, and the folder read since the last gap or write (RetagFlow.canSaveCover)
                    .disabled(incoming == nil || !retag.flow.canSaveCover || model.tagsApplying || model.getting
                              || model.deleting)
                    if let result = retag.coverResult {
                        Text(result)
                            .font(Typeface.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } footer: {
                    Text(RetagWords.coverOnlyHint(hasArt: !album.art.isEmpty))
                        .font(Typeface.footnote)
                }
            }
        }
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
        .fullScreenCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
        }
    }

    private func side<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typeface.footnote.weight(.semibold))
                .foregroundStyle(Palette.quiet)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func missing(_ words: String) -> some View {
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            Text(words)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
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
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(label)
            } else if failed {
                Text(EditWords.pictureFailed)
                    .foregroundStyle(.primary)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .overlay(alignment: .topTrailing) {
            Button(EditWords.close) { dismiss() }
                .font(Typeface.headline)
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
