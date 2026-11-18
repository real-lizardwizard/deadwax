import DeadwaxCore
import SwiftUI
import UIKit

/// Tags (notes/ios-specs/phase8-managing.md 3.4; the web's EditPanel TagsList): the folder's files as read from the disk
/// just now, a section per disc on a set, each row its number and title (its artist when it isn't the album's). A tap
/// pushes the track's page; **Select** turns on multi-select, and the bottom bar's button edits the tracks selected -
/// or every track with none (the web's words). Another set of tracks while typed work waits for its Apply asks
/// "Discard changes?" first, as Close does. Not the web's Shift-click runs (`tickTracks`): Select is the phone's way.
struct TagsListView: View {
    let model: EditAlbumModel
    let tags: TagsModel
    @Binding var path: [EditPage]

    @State private var editMode: EditMode = .inactive
    @State private var discarding: [String]?

    var body: some View {
        @Bindable var tags = tags
        let selecting = editMode.isEditing
        List(selection: selecting ? $tags.selection : nil) {
            TagsReadState(model: model, tags: tags)
            let discs = tags.discs
            ForEach(Array(discs.enumerated()), id: \.offset) { (at: Int, disc: (disc: Int?, files: [AlbumFile])) in
                Section {
                    ForEach(disc.files, id: \.filename) { (file: AlbumFile) in
                        if selecting {
                            TagTrackRow(tags: tags, file: file)
                        } else {
                            NavigationLink(value: EditPage.track(file.filename)) {
                                TagTrackRow(tags: tags, file: file)
                            }
                        }
                    }
                } header: {
                    if let number = disc.disc {
                        Text(TagEditWords.disc(number))
                            .font(Typeface.footnote)
                    }
                } footer: {
                    if at == discs.count - 1, let files = tags.files, !files.isEmpty {
                        Text(tags.selection.isEmpty ? TagEditWords.selectNote
                             : TagEditWords.selected(tags.selection.count, of: files.count))
                            .font(Typeface.footnote)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(AlbumEdit.Part.tags.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(selecting ? AlbumInfoWords.done : TagEditWords.select) {
                    withAnimation {
                        editMode = selecting ? .inactive : .active
                        if !editMode.isEditing { tags.selection = [] }
                    }
                }
                .disabled(tags.files?.isEmpty != false)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if selecting, let files = tags.files {
                    let all = !files.isEmpty && tags.selection.count == files.count
                    Button(all ? TagEditWords.deselectAll : TagEditWords.selectAll) {
                        tags.selection = all ? [] : Set(files.map(\.filename))
                    }
                    Spacer()
                }
                Button(TagEditWords.editTracks(tags.selection.count)) {
                    open(targets)
                }
                .font(Typeface.headline)
                .disabled(targets.isEmpty || model.writing)
            }
        }
        .confirmationDialog(EditWords.discardTitle, isPresented: Binding(get: { discarding != nil },
                                                                          set: { if !$0 { discarding = nil } }),
                            titleVisibility: .visible) {
            Button(EditWords.discard, role: .destructive) {
                if let names = discarding { push(names) }
            }
            Button(EditWords.keepEditing, role: .cancel) {}
                .returnCancels()
        }
        .task(id: ObjectIdentifier(tags)) { tags.start() }
    }

    /// The tracks Edit tags edits: those selected, in running order - every track with none selected.
    private var targets: [String] {
        let names = (tags.files ?? []).map(\.filename)
        return tags.selection.isEmpty ? names : names.filter { tags.selection.contains($0) }
    }

    private func open(_ names: [String]) {
        if names != tags.editing && tags.unsaved {
            discarding = names
        } else {
            push(names)
        }
    }

    private func push(_ names: [String]) {
        tags.edit(names)
        path.append(.editTags)
    }
}

/// The files read, or reading, or not read - over the Tags list and a track's page: "Reading the files…" while the
/// first read is on its way; the read's failure in the phone's words with Look again (the scan read again, and with it
/// the files) - the files' own read's, or (review, 16 Nov) the scan's, when the read a write or a gap waits for
/// couldn't be made there.
struct TagsReadState: View {
    let model: EditAlbumModel
    let tags: TagsModel

    var body: some View {
        if tags.files == nil, tags.reading {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(TagEditWords.readingFiles).foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            }
        }
        if let failure = tags.readFailure ?? (tags.flow.readFailed ? model.scan.failure ?? EditWords.readFailed : nil) {
            Section {
                ErrorNote(text: failure)
                Button(EditWords.lookAgain) {
                    Task {
                        await model.lookUp()
                        await tags.readFiles()
                    }
                }
                .disabled(!model.online || tags.reading || model.scan.reading)
            }
        }
    }
}

/// A track in Tags: "3 · Title", its artist under it when it isn't the album's, read by VoiceOver as one.
struct TagTrackRow: View {
    let tags: TagsModel
    let file: AlbumFile

    var body: some View {
        let label = tags.label(file)
        let title = file.title ?? file.filename
        let artist = TagEditWords.artist(file, album: tags.album)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Typeface.mono(.footnote))
                .foregroundStyle(Palette.quiet)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let artist {
                    Text(artist)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TagEditWords.trackRow(label: label, title: title, artist: artist))
    }
}

/// A track's page (the web's TrackInspector): its title and where it sits, Edit this track…, every field the web's
/// inspector shows under its group - the ones the file has; the disc of a file with no disc tag dimmed and saying why -
/// the pictures inside it (each a row, its facts once it has loaded; a tap shows it full screen), and every tag under
/// its container's own name.
struct TrackPageView: View {
    let model: EditAlbumModel
    let tags: TagsModel
    let filename: String
    @Binding var path: [EditPage]

    @State private var full: FullCover?
    @State private var discarding = false

    var body: some View {
        List {
            TagsReadState(model: model, tags: tags)
            if let file = tags.file(filename) {
                head(file)
                ForEach(TrackInspector.groups(file)) { (section: TrackInspector.Section) in
                    InspectorSection(section: section)
                }
                pictures(file)
                raw(file)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
                .macSheet()
        }
        .confirmationDialog(EditWords.discardTitle, isPresented: $discarding, titleVisibility: .visible) {
            Button(EditWords.discard, role: .destructive) { push() }
            Button(EditWords.keepEditing, role: .cancel) {}
                .returnCancels()
        }
        .task(id: ObjectIdentifier(tags)) { tags.start() }
    }

    /// The bar's title: the file's title, else its name.
    private var title: String {
        guard let file = tags.file(filename), let title = file.title else { return filename }
        return title
    }

    private func head(_ file: AlbumFile) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(TrackInspector.title(file).isEmpty ? file.filename : TrackInspector.title(file))
                    .font(Typeface.headline)
                if TrackInspector.untitled(file) {
                    Text(TrackInspector.noTitle)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                Text(TrackInspector.place(file, discs: tags.album.discCount))
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.quiet)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button(TrackInspector.editThis) {
                if [filename] != tags.editing && tags.unsaved {
                    discarding = true
                } else {
                    push()
                }
            }
            .disabled(model.writing)
        }
    }

    private func push() {
        tags.edit([filename])
        path.append(.editTags)
    }

    @ViewBuilder private func pictures(_ file: AlbumFile) -> some View {
        Section {
            if file.pictures.isEmpty {
                Text(TrackInspector.noPictures)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // by place, not by the server's index: an index read loosely (missing, malformed) is 0, and two pictures
            // with one id would be drawn as one
            ForEach(Array(file.pictures.enumerated()), id: \.offset) {
                (entry: (offset: Int, element: EmbeddedPicture)) in
                let picture = entry.element
                Button {
                    full = FullCover(source: .picture(path: tags.album.path, file: file.filename, index: picture.index))
                } label: {
                    PictureRow(path: tags.album.path, file: file.filename, picture: picture)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(TrackInspector.pictures)
                .font(Typeface.footnote)
        }
    }

    @ViewBuilder private func raw(_ file: AlbumFile) -> some View {
        Section {
            ForEach(Array((file.raw ?? []).enumerated()), id: \.offset) { (_, pair: [String]) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.first ?? "")
                        .font(Typeface.mono(.footnote))
                        .foregroundStyle(Palette.quiet)
                    Text(pair.dropFirst().first ?? "")
                        .textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            Text(file.filename)
                .font(Typeface.mono(.footnote))
                .foregroundStyle(Palette.quiet)
                .textSelection(.enabled)
        } header: {
            Text(TrackInspector.rawTitle(file))
                .font(Typeface.footnote)
        }
    }
}

/// One group of a track's page (Tags, Audio, MusicBrainz, File): the fields the file has, a default dimmed and its
/// reason under the group - nothing drawn for a group the file has none of (the web draws a dash for each field).
struct InspectorSection: View {
    let section: TrackInspector.Section

    var body: some View {
        let shown = section.fields.filter { !$0.value.isEmpty }
        if !shown.isEmpty {
            Section {
                ForEach(shown) { (field: TrackInspector.Field) in
                    InspectorRow(field: field)
                }
            } header: {
                Text(section.group.rawValue)
                    .font(Typeface.footnote)
            } footer: {
                if let why = shown.compactMap(\.inferred).first {
                    Text(why)
                        .font(Typeface.footnote)
                }
            }
        }
    }
}

/// One field: its label, its value (in the data face for a number or an id), dimmed when it is a default.
struct InspectorRow: View {
    let field: TrackInspector.Field

    var body: some View {
        let face: Font = field.mono ? Typeface.mono(.body) : Typeface.body
        let colour: Color = field.inferred == nil ? Color.primary : Palette.quiet
        LabeledContent {
            Text(field.value)
                .font(face)
                .foregroundStyle(colour)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(field.label)
        }
        .accessibilityHint(field.inferred ?? "")
    }
}

/// One picture inside a file: a thumbnail, its label, and its facts - its pixel size once it has loaded, its bytes, its
/// format (TrackInspector.pictureFacts). Read by VoiceOver as one, saying a tap shows it.
struct PictureRow: View {
    let path: String
    let file: String
    let picture: EmbeddedPicture

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Palette.coverEmpty
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Corners.artShape)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(picture.label)
                Text(TrackInspector.pictureFacts(picture, pixels: image.map {
                    TrackInspector.pixels(width: Int($0.size.width * $0.scale), height: Int($0.size.height * $0.scale))
                }))
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                if !picture.description.isEmpty {
                    Text(picture.description)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(TrackInspector.pictureLabel(picture))
        .accessibilityAddTraits(.isButton)
        .task(id: "\(path)|\(file)|\(picture.index)") {
            guard let client = server.client,
                  let data = try? await client.trackPicture(path: path, file: file, index: picture.index) else { return }
            image = UIImage(data: data)
        }
    }
}

/// Edit tags (the web's TrackTagEditor): the eleven fields in four sections (the phone's own grouping, the web's order
/// in each), each starting at what the files share, the web's line under it and Undo once it is typed over; what would
/// change - asked `Retag.previewDebounceMs` after the typing stops, only the fields typed over sent - and Apply, on only
/// for a preview of what the page shows now that changes something with no problem (RetagFlow.canApply). Nothing is
/// written until Apply, and no file is renamed.
struct EditTagsView: View {
    let model: EditAlbumModel
    let tags: TagsModel

    @FocusState private var focused: String?

    var body: some View {
        Form {
            if tags.flow.mayHaveFinished {
                Section {
                    MayHaveFinished(reading: tags.reading || model.scan.reading)
                }
            }
            TagsReadState(model: model, tags: tags)
            if tags.refreshing {
                // saved: the fields come back once the files are read again (TagsModel.refreshing) - never what they
                // said before under "Saved"; a read that failed is said above, with Look again
                Section {
                    if let applied = tags.applied {
                        Text(applied)
                            .foregroundStyle(Palette.held)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if tags.readFailure == nil, !tags.flow.readFailed {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(TagEditWords.readingFiles).foregroundStyle(Palette.quiet)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if tags.ready {
                editingSection
                ForEach(TagEdit.sections, id: \.title) { (section: (title: String, keys: [String])) in
                    Section {
                        ForEach(section.keys, id: \.self) { (key: String) in
                            if let field = TagEdit.field(key) { fieldRow(field) }
                        }
                    } header: {
                        Text(section.title)
                            .font(Typeface.footnote)
                    } footer: {
                        if section.title == TagEdit.sections.last?.title {
                            Text(TagEditWords.hint(single: tags.single))
                                .font(Typeface.footnote)
                        }
                    }
                    .disabled(tags.flow.applying)
                }
                previewSection
                applySection
            } else if tags.files != nil, !tags.reading, tags.readFailure == nil {
                // a file edited has gone since it was chosen (a release applied renames them): back to the list
                Section {
                    Text(TagEditWords.readFailed).foregroundStyle(Palette.quiet)
                }
            }
        }
        .navigationTitle(TagEditWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AlbumInfoWords.done) { focused = nil }
            }
        }
    }

    /// What is being edited: one track's title, or the tracks, listed under "Editing these 12 tracks".
    @ViewBuilder private var editingSection: some View {
        let heading = TagEditWords.heading(filenames: tags.editing, files: tags.editingFiles)
        Section {
            if tags.single {
                Text(heading.isEmpty ? tags.editing.first ?? "" : heading)
                    .font(Typeface.headline)
                    .accessibilityAddTraits(.isHeader)
            } else {
                DisclosureGroup(TagEditWords.editingThese(tags.editing.count)) {
                    ForEach(tags.editingFiles, id: \.filename) { (file: AlbumFile) in
                        TagTrackRow(tags: tags, file: file)
                    }
                }
            }
        } header: {
            Text(tags.album.album.isEmpty ? tags.album.path : tags.album.album)
                .font(Typeface.footnote)
        }
    }

    private func fieldRow(_ field: TagEdit.Field) -> some View {
        let shared = tags.shared(field.key)
        let edited = tags.draft[field.key] != nil
        let problem = tags.problems[field.key]
        let note = tags.note(field.key)
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                TextField(field.label, text: Binding(get: { tags.value(field.key) }, set: { tags.set(field.key, $0) }),
                          prompt: Text(TagEdit.placeholder(field.key, shared, edited: edited)))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(field.numeric || field.short ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(field.short ? .never : .words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: field.key)
            } label: {
                Text(field.label)
            }
            if note != nil || edited {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let note {
                        Text(note)
                            .font(Typeface.footnote)
                            .foregroundStyle(problem != nil ? Palette.amber : Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if edited {
                        Button(TagEditWords.undo) { tags.revert(field.key) }
                            .font(Typeface.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                            .accessibilityHint(TagEditWords.undoHint)
                    }
                }
            }
        }
        .accessibilityValue(note ?? "")
    }

    /// What would change (the web's preview column): the last apply's words while no preview is in hand, the reason
    /// none is asked, the wait, the plan's problems, nothing to change - or each file that would change, its tags from
    /// what they say to what they'd say.
    private var previewSection: some View {
        let plan = tags.currentPlan
        let problems = tags.problems.count
        let planning = tags.flow.planning && !tags.body.edits.isEmpty && problems == 0
        return Section {
            if let applied = tags.applied, plan == nil {
                Text(applied)
                    .foregroundStyle(Palette.held)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tags.body.edits.isEmpty && tags.applied == nil {
                Text(TagEditWords.changeAField).foregroundStyle(Palette.quiet)
            }
            if problems > 0 {
                Text(TagEditWords.fixFirst(problems)).foregroundStyle(Palette.amber)
            }
            if planning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(TagEditWords.working).foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            }
            if !planning, let plan {
                ForEach(TagEditWords.problems(plan, filenames: tags.editing), id: \.self) { (problem: String) in
                    Text(problem).foregroundStyle(Palette.amber)
                }
                if plan.empty && plan.problems.isEmpty {
                    Text(TagEditWords.nothingToChange(single: tags.single)).foregroundStyle(Palette.quiet)
                }
                ForEach(plan.changed, id: \.filename) { (file: TagEditFile) in
                    TagFileChanges(file: file)
                }
            } else if !planning, let error = tags.previewError {
                ErrorNote(text: error)
            }
        } header: {
            Text(TagEditWords.whatWouldChange)
                .font(Typeface.footnote)
        }
    }

    private var applySection: some View {
        Section {
            if let error = tags.applyError {
                ErrorNote(text: error)
            } else if let plan = tags.currentPlan, !plan.empty, tags.applied == nil {
                Text(TagEditWords.wouldChange(plan)).foregroundStyle(Palette.quiet)
            }
            Button {
                focused = nil
                Task { await model.applyTags() }
            } label: {
                HStack(spacing: 10) {
                    if tags.flow.applying { ProgressView() }
                    Text(tags.flow.applying ? TagEditWords.saving : TagEditWords.apply)
                        .font(Typeface.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!tags.canApply || model.writing || model.marking)
        }
    }
}

/// One file's changes in the preview: its name, then each tag - the form's label, what it says now ("—" for nothing),
/// what it would say ("removed" for nothing).
struct TagFileChanges: View {
    let file: TagEditFile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.filename)
                .font(Typeface.mono(.footnote))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(file.changes, id: \.tag) { (change: TagChange) in
                let from = change.from.isEmpty ? TagEditWords.none : change.from
                let to = change.to.isEmpty ? TagEditWords.removed : change.to
                VStack(alignment: .leading, spacing: 1) {
                    Text(TagEdit.label(change.tag))
                        .font(Typeface.footnote.weight(.semibold))
                        .foregroundStyle(Palette.quiet)
                    Text(from)
                        .foregroundStyle(Palette.quiet)
                        .strikethrough(!change.from.isEmpty)
                    Text(to)
                        .foregroundStyle(change.to.isEmpty ? Palette.quiet : Color.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TagEdit.label(change.tag)): \(from), \(to)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
