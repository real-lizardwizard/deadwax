import DeadwaxCore
import SwiftUI
import UIKit

/// Tags (notes/ios-specs/phase8-managing.md 3.4; the web's EditPanel TagsList): the folder's files as read from the disk
/// just now, a heading per disc on a set, each row its number, its title (its artist when it isn't the album's) and its
/// length. Another set of tracks while typed work waits for its Apply asks "Discard changes?" first, as Close does.
///
/// (R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") The root's Tags tab, as
/// iEditTags.dc.html draws it, flat: a row per track run to the screen's edges, its tick at its start - a tap anywhere
/// on the row ticks it, as the drawing's `<label class="row">` does - and its › pushing the track's page (everything in
/// its file); the line under them; and the root's foot (TagsFoot): Select all, and Edit N tracks… - the tracks ticked,
/// every track with none ticked (EditAlbumPage.tagTargets).
struct TagsListView: View {
    let model: EditAlbumModel
    let tags: TagsModel
    @Binding var path: [EditPage]

    private let side = CGFloat(PhoneLook.bigSide)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagsReadState(model: model, tags: tags)
                .padding(.horizontal, side)
            let discs = tags.discs
            if let files = tags.files, !files.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(discs.enumerated()), id: \.offset) { (_: Int, disc: (disc: Int?, files: [AlbumFile])) in
                        if let number = disc.disc {
                            // .dw.ph .row.grp: 38 tall, its words at its foot, the heading's 15 semibold
                            Text(TagEditWords.disc(number))
                                .font(Typeface.Phone.text(.strip).weight(.semibold))
                                .foregroundStyle(DWPalette.head)
                                .padding(.horizontal, side)
                                .padding(.bottom, 6)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .bottomLeading)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(disc.files, id: \.filename) { (file: AlbumFile) in
                            TagTrackRow(tags: tags, file: file, path: $path)
                        }
                    }
                }
                // iEditTags' `.list`: its hairline over the first row
                .overlay(alignment: .top) { DWRule(colour: DWPalette.rowRule) }
                Text(EditAlbumPage.Words.tagsNote(Platform.device))
                    .font(Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, side)
                    .padding(.vertical, 10)
            }
        }
        // the rows run to the screen's edges, as the strip's hairline does - the root's page is padded by `side`
        .padding(.horizontal, -side)
        // the files are read once Tags shows - again for a model held anew
        .task(id: ObjectIdentifier(tags)) { tags.start() }
    }
}

/// The Tags tab's foot (iEditTags' `.foot2`): Select all - Deselect all once every track is ticked - and Edit N tracks…,
/// the purple one, pushing Edit tags for the tracks ticked, every track with none ticked. Another set of tracks while
/// typed work waits asks "Discard changes?" first. (R11's review) Side by side while both fit the foot, one over the
/// other once they don't: PhoneFoot stops its text at xxxLarge, where "Deselect all" and "Edit 10 tracks…" come to
/// about 350 against the foot's 343 - no accessibility size reaches a foot's words, so they are never cut to fit.
struct TagsFoot: View {
    let model: EditAlbumModel
    let tags: TagsModel
    @Binding var path: [EditPage]

    @State private var discarding: [String]?

    var body: some View {
        let names = (tags.files ?? []).map(\.filename)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CGFloat(PhoneLook.footGap)) {
                selectButton(names)
                editButton(names)
            }
            VStack(spacing: CGFloat(PhoneLook.footGap)) {
                selectButton(names)
                editButton(names)
            }
            .padding(.vertical, CGFloat(PhoneLook.footGap))
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
    }

    /// Select all - Deselect all once every track is ticked (EditAlbumPage.selectAll): VoiceOver hears TagEditWords'
    /// whole words.
    private func selectButton(_ names: [String]) -> some View {
        let all = EditAlbumPage.allTicked(names, tags.selection)
        return Button(all ? EditAlbumPage.Words.deselectAll : EditAlbumPage.Words.selectAll) {
            tags.selection = EditAlbumPage.selectAll(names, tags.selection)
        }
        .buttonStyle(DWButtonStyle(size: .large))
        .accessibilityLabel(all ? TagEditWords.deselectAll : TagEditWords.selectAll)
        .disabled(names.isEmpty)
    }

    /// Edit N tracks…, the purple one - off while a write runs: the editor it pushes would start from files about to
    /// change.
    private func editButton(_ names: [String]) -> some View {
        Button {
            open(EditAlbumPage.tagTargets(names, ticked: tags.selection))
        } label: {
            Text(TagEditWords.editTracks(EditAlbumPage.ticked(names, tags.selection)))
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
        .disabled(names.isEmpty || model.writing)
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

/// The files read, or reading, or not read - over the Tags tab, a track's page and Edit tags: "Reading the files…"
/// while the first read is on its way; the read's failure in the phone's words with Look again (the scan read again, and
/// with it the files) - the files' own read's, or (review, 16 Nov) the scan's, when the read a write or a gap waits for
/// couldn't be made there. (R11) Flat: a card each.
struct TagsReadState: View {
    let model: EditAlbumModel
    let tags: TagsModel

    var body: some View {
        if tags.files == nil, tags.reading {
            PhoneCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(TagEditWords.readingFiles)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.t2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        if let failure = tags.readFailure ?? (tags.flow.readFailed ? model.scan.failure ?? EditWords.readFailed : nil) {
            PhoneCard {
                VStack(alignment: .leading, spacing: 8) {
                    ErrorNote(text: failure)
                    Button(EditWords.lookAgain) {
                        Task {
                            await model.lookUp()
                            await tags.readFiles()
                        }
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!model.online || tags.reading || model.scan.reading)
                }
            }
        }
    }
}

/// A track in Tags (iEditTags' `.row`): its tick, its number, its title (its artist under it when it isn't the album's),
/// its length, and its › - 48 tall at least on the row's hairline. A tap on the row ticks it; the › pushes the track's
/// page. (R11's review) VoiceOver reads the whole row as one toggle - its words "Track 3, Title", its length its value -
/// a double-tap ticking it (its default action) and See a file's every tag… a named action: the › is no element of its
/// own beside it.
struct TagTrackRow: View {
    let tags: TagsModel
    let file: AlbumFile
    @Binding var path: [EditPage]

    private let side = CGFloat(PhoneLook.bigSide)
    /// The title's size (Typeface.Phone's .row, scaled as it is): the tick is centred on its words' line.
    @ScaledMetric(relativeTo: Typeface.Phone.Size.row.scaled.style)
    private var rowWords: CGFloat = Typeface.Phone.Size.row.scaled.points

    var body: some View {
        let label = tags.label(file)
        let title = file.title ?? file.filename
        let artist = TagEditWords.artist(file, album: tags.album)
        let ticked = tags.selection.contains(file.filename)
        HStack(spacing: 0) {
            Button {
                toggle()
            } label: {
                // the number and the length on the title's first text baseline, the tick centred on its words' line
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    DWCheckMark(on: ticked)
                        .padding(.leading, side)
                        .padding(.trailing, 12)
                        .centredOnWords(rowWords)
                    // .mono.s.q, 38 wide
                    Text(label)
                        .font(Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t2)
                        .frame(minWidth: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typeface.Phone.text(.row))
                            .foregroundStyle(DWPalette.head)
                        if let artist {
                            Text(artist)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    Text(TrackInspector.trackTime(file.length))
                        .font(Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t2)
                        .padding(.leading, 10)
                }
                .frame(minHeight: CGFloat(DWLook.here.rowHeight))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // the ›: the track's page - a finger's 44 round it, the row's side after it
            NavigationLink(value: EditPage.track(file.filename)) {
                PhoneChevron()
                    .frame(minWidth: CGFloat(DWLook.here.target), minHeight: CGFloat(DWLook.here.target))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, side - 14)
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
        // one element, the row: a toggle, a double-tap ticking it - the ›'s page its named action
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TagEditWords.trackRow(label: label, title: title, artist: artist))
        .accessibilityValue(TrackInspector.trackTime(file.length))
        .accessibilityAddTraits(ticked ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityAction { toggle() }
        .accessibilityAction(named: EditAlbumPage.Words.seeEveryTag) {
            path.append(.track(file.filename))
        }
    }

    /// The row's tap, and VoiceOver's double-tap: ticked or unticked.
    private func toggle() {
        if tags.selection.contains(file.filename) {
            tags.selection.remove(file.filename)
        } else {
            tags.selection.insert(file.filename)
        }
    }
}

/// A track's page (the web's TrackInspector): its title and where it sits, Edit this track…, every field the web's
/// inspector shows under its group - the ones the file has; the disc of a file with no disc tag dimmed and saying why -
/// the pictures inside it (each a row, its facts once it has loaded; a tap shows it full screen), and every tag under
/// its container's own name. (R11) Flat: each group a PhoneGroup of rows on the page's black.
struct TrackPageView: View {
    let model: EditAlbumModel
    let tags: TagsModel
    let filename: String
    @Binding var path: [EditPage]

    @State private var full: FullCover?
    @State private var discarding = false

    private let side = CGFloat(PhoneLook.bigSide)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, side)
            .padding(.bottom, 24)
        }
        .background(DWPalette.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appCover(item: $full) { (cover: FullCover) in
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
        PhoneCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TrackInspector.title(file).isEmpty ? file.filename : TrackInspector.title(file))
                        .font(Typeface.Phone.text(.row).weight(.semibold))
                        .foregroundStyle(DWPalette.text)
                    if TrackInspector.untitled(file) {
                        Text(TrackInspector.noTitle)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                    }
                    Text(TrackInspector.place(file, discs: tags.album.discCount))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
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
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(model.writing)
            }
        }
    }

    private func push() {
        tags.edit([filename])
        path.append(.editTags)
    }

    @ViewBuilder private func pictures(_ file: AlbumFile) -> some View {
        PhoneGroup(legend: TrackInspector.pictures) {
            if file.pictures.isEmpty {
                Text(TrackInspector.noPictures)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    @ViewBuilder private func raw(_ file: AlbumFile) -> some View {
        PhoneGroup(legend: TrackInspector.rawTitle(file)) {
            ForEach(Array((file.raw ?? []).enumerated()), id: \.offset) { (_, pair: [String]) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.first ?? "")
                        .font(Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t2)
                    Text(pair.dropFirst().first ?? "")
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.text)
                        .textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                .accessibilityElement(children: .combine)
            }
            Text(file.filename)
                .font(Typeface.Phone.mono(.extraSmall))
                .foregroundStyle(DWPalette.t3)
                .textSelection(.enabled)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            PhoneGroup(legend: section.group.rawValue) {
                ForEach(shown) { (field: TrackInspector.Field) in
                    InspectorRow(field: field)
                }
            }
            if let why = shown.compactMap(\.inferred).first {
                Text(why)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }
}

/// One field (`.kv`): its label in white, its value at its end in the second colour (in the readout face for a number
/// or an id), the third when it is a default - 42 tall at least on the group's hairline, its value selectable.
struct InspectorRow: View {
    let field: TrackInspector.Field

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.kvGap)) {
            Text(field.label)
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.kvLabel)
                .frame(minWidth: CGFloat(PhoneLook.kvLabelWidth), alignment: .leading)
            Spacer(minLength: 0)
            Text(field.value)
                .font(field.mono ? Typeface.Phone.mono(.small) : Typeface.Phone.text(.row))
                .foregroundStyle(field.inferred == nil ? DWPalette.t2 : DWPalette.t3)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .frame(minHeight: CGFloat(PhoneLook.kvRow))
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(field.inferred ?? "")
    }
}

/// One picture inside a file: a thumbnail, its label, and its facts - its pixel size once it has loaded, its bytes, its
/// format (TrackInspector.pictureFacts). Read by VoiceOver as one, saying a tap shows it. The thumbnail's empty square is
/// a picture's face (the card's), until the picture comes.
struct PictureRow: View {
    let path: String
    let file: String
    let picture: EmbeddedPicture

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                DWPalette.card
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
                    .font(Typeface.Phone.text(.row))
                    .foregroundStyle(DWPalette.text)
                Text(TrackInspector.pictureFacts(picture, pixels: image.map {
                    TrackInspector.pixels(width: Int($0.size.width * $0.scale), height: Int($0.size.height * $0.scale))
                }))
                .font(Typeface.Phone.mono(.extraSmall))
                .foregroundStyle(DWPalette.t2)
                if !picture.description.isEmpty {
                    Text(picture.description)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
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

/// Edit tags (the web's TrackTagEditor): the eleven fields in four groups (the phone's own grouping, the web's order in
/// each), each starting at what the files share, the web's line under it and Undo once it is typed over; what would
/// change - asked `Retag.previewDebounceMs` after the typing stops, only the fields typed over sent - and Apply, on only
/// for a preview of what the page shows now that changes something with no problem (RetagFlow.canApply). Nothing is
/// written until Apply, and no file is renamed.
///
/// (R11) Flat, as Release's Fields are (iEdit): each field on the look's well (DWWellField) beside its label on the
/// group's hairline, stacked at the accessibility sizes; what would change under them; and Apply in the page's foot
/// (`.phoneFoot`) - over the page's foot, under the keyboard, never riding up on a field.
struct EditTagsView: View {
    let model: EditAlbumModel
    let tags: TagsModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: String?

    private let side = CGFloat(PhoneLook.bigSide)

    /// (The Mac app, slice 7) The fields in the order the page draws them - its sections', in turn: Tab's on the Mac.
    private static let order = TagEdit.sections.flatMap { (section: (title: String, keys: [String])) -> [String] in
        section.keys
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if tags.flow.mayHaveFinished {
                    PhoneCard {
                        MayHaveFinished(reading: tags.reading || model.scan.reading)
                    }
                }
                TagsReadState(model: model, tags: tags)
                if tags.refreshing {
                    // saved: the fields come back once the files are read again (TagsModel.refreshing) - never what
                    // they said before under "Saved"; a read that failed is said above, with Look again
                    PhoneCard {
                        VStack(alignment: .leading, spacing: 8) {
                            if let applied = tags.applied {
                                Text(applied)
                                    .foregroundStyle(DWPalette.greenText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if tags.readFailure == nil, !tags.flow.readFailed {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(TagEditWords.readingFiles).foregroundStyle(DWPalette.t2)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                } else if tags.ready {
                    editingSection
                    ForEach(TagEdit.sections, id: \.title) { (section: (title: String, keys: [String])) in
                        PhoneGroup(legend: section.title) {
                            ForEach(section.keys, id: \.self) { (key: String) in
                                if let field = TagEdit.field(key) { fieldRow(field) }
                            }
                        }
                        .disabled(tags.flow.applying)
                    }
                    Text(TagEditWords.hint(single: tags.single))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    previewSection
                } else if tags.files != nil, !tags.reading, tags.readFailure == nil {
                    // a file edited has gone since it was chosen (a release applied renames them): back to the list
                    PhoneCard {
                        Text(TagEditWords.readFailed).foregroundStyle(DWPalette.t2)
                    }
                }
            }
            .font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .padding(.horizontal, side)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DWPalette.page)
        .navigationTitle(TagEditWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AlbumInfoWords.done) { focused = nil }
            }
        }
        .phoneFoot { applyButton }
    }

    /// What is being edited: one track's title, or the tracks, listed under "Editing these 12 tracks".
    @ViewBuilder private var editingSection: some View {
        let heading = TagEditWords.heading(filenames: tags.editing, files: tags.editingFiles)
        PhoneGroup(legend: tags.album.album.isEmpty ? tags.album.path : tags.album.album) {
            PhoneCard {
                if tags.single {
                    Text(heading.isEmpty ? tags.editing.first ?? "" : heading)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(tags.editingFiles, id: \.filename) { (file: AlbumFile) in
                                let label = tags.label(file)
                                let title = file.title ?? file.filename
                                Text("\(label) · \(title)")
                                    .font(Typeface.Phone.text(.small))
                                    .foregroundStyle(DWPalette.t2)
                                    .accessibilityLabel(TagEditWords.trackRow(label: label, title: title,
                                                                              artist: TagEditWords.artist(file, album: tags.album)))
                            }
                        }
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(TagEditWords.editingThese(tags.editing.count))
                            .foregroundStyle(DWPalette.text)
                    }
                    .tint(DWPalette.acc)
                }
            }
        }
    }

    /// A field's row, as Release's are: its label at the left in white, 88 at least, the field on the look's well beside
    /// it, 44 tall at least on the group's hairline - stacked at the accessibility sizes - and under it the web's line and
    /// Undo once it is typed over.
    private func fieldRow(_ field: TagEdit.Field) -> some View {
        let shared = tags.shared(field.key)
        let edited = tags.draft[field.key] != nil
        let problem = tags.problems[field.key]
        let note = tags.note(field.key)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 0) {
            layout {
                Text(field.label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.rowText)
                    .frame(minWidth: CGFloat(DWLook.here.labelWidth), alignment: .leading)
                    .accessibilityHidden(true)
                TextField(field.label, text: Binding(get: { tags.value(field.key) }, set: { tags.set(field.key, $0) }),
                          prompt: Text(TagEdit.placeholder(field.key, shared, edited: edited)).foregroundStyle(DWPalette.t3))
                    .keyboardType(field.numeric || field.short ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(field.short ? .never : .words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: field.key)
                    .tabs($focused, in: Self.order)
                    .modifier(DWWellField(focus: $focused, field: field.key))
                    .accessibilityLabel(field.label)
                    .accessibilityValue(note ?? "")
            }
            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            if note != nil || edited {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let note {
                        Text(note)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(problem != nil ? DWPalette.amberText : DWPalette.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if edited {
                        Button(TagEditWords.undo) { tags.revert(field.key) }
                            .buttonStyle(DWButtonStyle(size: .small))
                            .accessibilityHint(TagEditWords.undoHint)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }

    /// What would change (the web's preview column): the last apply's words while no preview is in hand, the reason
    /// none is asked, the wait, the plan's problems, nothing to change - or each file that would change, its tags from
    /// what they say to what they'd say; and what Apply's last try came to.
    private var previewSection: some View {
        let plan = tags.currentPlan
        let problems = tags.problems.count
        let planning = tags.flow.planning && !tags.body.edits.isEmpty && problems == 0
        return PhoneGroup(legend: TagEditWords.whatWouldChange) {
            PhoneCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let applied = tags.applied, plan == nil {
                        Text(applied)
                            .foregroundStyle(DWPalette.greenText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if tags.body.edits.isEmpty && tags.applied == nil {
                        Text(TagEditWords.changeAField).foregroundStyle(DWPalette.t2)
                    }
                    if problems > 0 {
                        Text(TagEditWords.fixFirst(problems)).foregroundStyle(DWPalette.amberText)
                    }
                    if planning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(TagEditWords.working).foregroundStyle(DWPalette.t2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !planning, let plan {
                        ForEach(TagEditWords.problems(plan, filenames: tags.editing), id: \.self) { (problem: String) in
                            Text(problem).foregroundStyle(DWPalette.amberText)
                        }
                        if plan.empty && plan.problems.isEmpty {
                            Text(TagEditWords.nothingToChange(single: tags.single)).foregroundStyle(DWPalette.t2)
                        }
                        ForEach(plan.changed, id: \.filename) { (file: TagEditFile) in
                            TagFileChanges(file: file)
                        }
                    } else if !planning, let error = tags.previewError {
                        ErrorNote(text: error)
                    }
                    if let error = tags.applyError {
                        ErrorNote(text: error)
                    } else if let plan = tags.currentPlan, !plan.empty, tags.applied == nil {
                        Text(TagEditWords.wouldChange(plan)).foregroundStyle(DWPalette.t2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Apply, the foot's purple: the tracks' typed fields written - the model's own (EditAlbumModel.applyTags), the
    /// server working the plan out again from the body.
    private var applyButton: some View {
        Button {
            focused = nil
            Task { await model.applyTags() }
        } label: {
            HStack(spacing: 8) {
                if tags.flow.applying { ProgressView().controlSize(.small) }
                // one line: the foot (PhoneFoot) stops its text at xxxLarge, where Apply fills it with room to spare
                Text(tags.flow.applying ? TagEditWords.saving : TagEditWords.apply)
            }
        }
        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
        .disabled(!tags.canApply || model.writing || model.marking)
    }
}

/// One file's changes in the preview: its name, then each tag - the form's label, what it says now ("—" for nothing),
/// what it would say ("removed" for nothing). Both devices': the phone's preview and the Mac's Tags well.
struct TagFileChanges: View {
    let file: TagEditFile
    /// Each device's own small faces: the name's and the change's readout, and the label's.
    let mono: Font
    let words: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.filename)
                .font(mono)
                .foregroundStyle(DWPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(file.changes, id: \.tag) { (change: TagChange) in
                let from = change.from.isEmpty ? TagEditWords.none : change.from
                let to = change.to.isEmpty ? TagEditWords.removed : change.to
                VStack(alignment: .leading, spacing: 1) {
                    Text(TagEdit.label(change.tag))
                        .font(words.weight(.semibold))
                        .foregroundStyle(DWPalette.t2)
                    Text(from)
                        .font(mono)
                        .foregroundStyle(DWPalette.t3)
                        .strikethrough(!change.from.isEmpty)
                    Text(to)
                        .font(mono)
                        .foregroundStyle(change.to.isEmpty ? DWPalette.t3 : DWPalette.text)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TagEdit.label(change.tag)): \(from), \(to)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension TagFileChanges {
    /// The phone's: its readouts in Courier Prime at .xs, the labels at .s.
    init(file: TagEditFile) {
        self.init(file: file, mono: Typeface.Phone.mono(.extraSmall), words: Typeface.Phone.text(.small))
    }
}
