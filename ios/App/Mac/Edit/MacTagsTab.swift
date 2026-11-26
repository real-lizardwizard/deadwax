import DeadwaxCore
import SwiftUI
import UIKit

/// The Mac's Edit album, its Tags tab (the redesign, slice R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork,
/// Lyrics and Delete"; Main.dc.html): the phone's Tags and Edit tags on one tab - the folder's tracks in a list, each
/// with its checkbox (the look's DWCheckbox, no words), its number, its title and its length, a heading per disc on a
/// set; under them the line and See a file's every tag… (the row selected, in a sheet); and beside them (under them in
/// one column) the editor for the tracks ticked - every track with none ticked (EditAlbumPage.tagTargets) - its legend
/// saying which ("Edit 3 tracks"), the eleven fields on the look's wells in the drawing's order, each one's line and Undo
/// under it, and what Apply would write in a well. Revert and Apply ("Apply to 3 tracks") are the foot's
/// (MacEditFooter).
///
/// Every rule is the phone's (TagsModel, EditAlbumModel): a tick changes which tracks the editor edits (TagsModel.edit -
/// a new set starts from what its files say), so a tick that would change the set while typed work waits for its Apply
/// asks "Discard changes?" first, as the phone's Edit N tracks… does; the preview is the server's plan of the fields
/// typed over, and Apply (EditAlbumModel.applyTags) sends the fields for the server to plan again - never a plan. A
/// click selects a row; its checkbox ticks it; a double-click (or Return) opens its every tag.
///
/// (R11's review) The sheet's Edit this track… is chosen once the sheet has gone (its onDismiss), so "Discard
/// changes?" shows; the question is held only while it can show. A release applied renaming the files under typed work
/// keeps the ticks, the tracks Apply writes to and the typed work in step (EditAlbumPage.afterRead): the tracks still
/// edited ticked, or - none of them left - said in the editor with Discard.
struct MacTagsTab: View {
    let model: EditAlbumModel
    let tags: TagsModel
    let twoColumns: Bool

    @Environment(\.macRowSize) private var rowSize
    @FocusState private var focused: String?
    /// The row selected: the one See a file's every tag… opens.
    @State private var selected: String?
    /// The ticks waiting on "Discard changes?": the selection they would make - only while the question is up (a sheet
    /// coming up, or the tab's model held anew, clears it: R11's review).
    @State private var discarding: Set<String>?
    /// The file whose every tag is shown, in a sheet.
    @State private var everyTag: EveryTag?
    /// (R11's review) Edit this track…'s pick, waiting for the sheet to have gone: SwiftUI drops a question raised over
    /// a sheet on its way down, so "Discard changes?" is asked from the sheet's onDismiss.
    @State private var picked: Set<String>?

    /// The fields in the order the tab draws them: Tab's.
    private static let order = TagEdit.fields.map { (field: TagEdit.Field) -> String in field.key }

    /// The list's columns (Main.dc.html's `.cols`): the checkbox, #, Title, Length - the checkbox's 34 its 13 box and the
    /// list's 10 each side.
    private static let columns = [
        MacListColumn(title: "", width: .fixed(34)),
        MacListColumn(title: EditAlbumPage.Words.number, width: .fixed(38)),
        MacListColumn(title: EditAlbumPage.Words.title, width: .flexible),
        MacListColumn(title: EditAlbumPage.Words.length, width: .fixed(62)),
    ]

    var body: some View {
        let names = (tags.files ?? []).map { (file: AlbumFile) -> String in file.filename }
        VStack(alignment: .leading, spacing: 18) {
            readState
            if let files = tags.files, !files.isEmpty {
                if twoColumns {
                    HStack(alignment: .top, spacing: 14) {
                        trackBox(files, names: names)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        editorBox(names)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    trackBox(files, names: names)
                    editorBox(names)
                }
            }
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(DWPalette.text)
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
        // the files are read once Tags shows - again for a model held anew
        .task(id: ObjectIdentifier(tags)) { tags.start() }
        // the editor follows the ticks as the files are read (EditAlbumPage.afterRead): with nothing typed, it edits
        // the tracks ticked (every track with none); over typed work a release's renames tick the tracks still edited,
        // so Apply to N tracks says what it writes to - typed work is never put away by a read. Typed work put back
        // (Revert, every Undo) lets the editor follow the ticks again.
        .onChange(of: names, initial: true) { (_: [String], now: [String]) -> Void in
            follow(now)
        }
        .onChange(of: tags.unsaved) { (_: Bool, _: Bool) -> Void in
            follow(fileNames)
        }
        // a question or a pick for another model is no question of this one's
        .onChange(of: ObjectIdentifier(tags)) { (_: ObjectIdentifier, _: ObjectIdentifier) -> Void in
            everyTag = nil
            discarding = nil
            picked = nil
        }
        // a sheet coming up takes the question's place: it is never left waiting to show over something else
        .onChange(of: everyTag?.id) { (_: String?, now: String?) -> Void in
            if now != nil { discarding = nil }
        }
        .confirmationDialog(EditWords.discardTitle, isPresented: Binding(get: { discarding != nil },
                                                                          set: { if !$0 { discarding = nil } }),
                            titleVisibility: .visible) {
            Button(EditWords.discard, role: .destructive) {
                if let next = discarding { choose(next, names: fileNames, discard: true) }
            }
            Button(EditWords.keepEditing, role: .cancel) {}
                .returnCancels()
        }
        // Edit this track…'s pick, once the sheet has gone: "Discard changes?" can be shown then
        .appSheet(item: $everyTag, onDismiss: {
            guard let next = picked else { return }
            picked = nil
            choose(next, names: fileNames)
        }) { (shown: EveryTag) in
            NavigationStack {
                MacTrackTags(model: model, tags: tags, filename: shown.filename) {
                    picked = [shown.filename]
                    everyTag = nil
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AlbumInfoWords.done) { everyTag = nil }
                            .escapeCloses()
                    }
                }
            }
            .macSheet()
        }
    }

    // MARK: the ticks

    /// A track ticked or unticked: the selection it makes, through "Discard changes?" when the editor would edit another
    /// set of tracks over typed work.
    private func tick(_ name: String, names: [String]) {
        var next = tags.selection
        if next.contains(name) {
            next.remove(name)
        } else {
            next.insert(name)
        }
        choose(next, names: names)
    }

    /// The selection made - and the editor set to its tracks (every track with none ticked). Over typed work for another
    /// set it waits on "Discard changes?" (`discard`: answered; EditAlbumPage.asksFirst) - and with a sheet up, for the
    /// sheet to have gone (`picked`, its onDismiss): a question raised over it would never show.
    private func choose(_ next: Set<String>, names: [String], discard: Bool = false) {
        let targets = EditAlbumPage.tagTargets(names, ticked: next)
        if !discard && EditAlbumPage.asksFirst(names, ticked: next, editing: tags.editing, typed: tags.unsaved) {
            if everyTag != nil {
                picked = next
            } else {
                discarding = next
            }
            return
        }
        tags.selection = next
        tags.edit(targets)
    }

    /// The folder's tracks as last read, by name - read when called (a question answered, a sheet gone), never as the
    /// body last drew them.
    private var fileNames: [String] {
        (tags.files ?? []).map { (file: AlbumFile) -> String in file.filename }
    }

    /// The editor after the files are read again, or typed work put back (EditAlbumPage.afterRead): the ticks, the
    /// tracks Apply writes to and the typed work kept in step - stranded typed work is the editor's to say.
    private func follow(_ now: [String]) {
        switch EditAlbumPage.afterRead(now, ticked: tags.selection, editing: tags.editing, typed: tags.unsaved) {
        case .keep, .stranded:
            break
        case .edit(let targets):
            tags.edit(targets)
        case .tick(let held):
            tags.selection = held
        }
    }

    // MARK: the files read

    /// The files reading, or not read - "Reading the files…", the read's failure with Look again (the files' own read's,
    /// or the scan's that a write waits for) - and an apply that never answered.
    @ViewBuilder private var readState: some View {
        let failure = tags.readFailure ?? (tags.flow.readFailed ? model.scan.failure ?? EditWords.readFailed : nil)
        if tags.flow.mayHaveFinished || (tags.files == nil && tags.reading) || failure != nil {
            VStack(alignment: .leading, spacing: 8) {
                if tags.flow.mayHaveFinished {
                    MayHaveFinished(reading: tags.reading || model.scan.reading)
                }
                if tags.files == nil, tags.reading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(TagEditWords.readingFiles).foregroundStyle(DWPalette.t2)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let failure {
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
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: the tracks

    /// The tracks' box: the list as tall as its lines (the editor's page scrolls, never the list), and under it the line
    /// and See a file's every tag….
    private func trackBox(_ files: [AlbumFile], names: [String]) -> some View {
        let rows = files.map { (file: AlbumFile) -> TrackLine in TrackLine(file: file) }
        let drawn = lines
        let headings = drawn.count - rows.count
        let tall = CGFloat(rowSize.boxHeight(rows: rows.count, headings: headings))
        let busy = tags.flow.applying || model.writing
        return VStack(spacing: 0) {
            MacColumnList(columns: Self.columns, rows: rows, lines: headings > 0 ? drawn : nil, controls: [0],
                          voice: { (line: TrackLine) -> MacRowVoice in voice(line.file, names: names, busy: busy) },
                          selected: $selected,
                          open: { (line: TrackLine) -> Void in everyTag = EveryTag(filename: line.file.filename) },
                          menu: { (_: TrackLine) -> EmptyModifier in EmptyModifier() }) { (line: TrackLine, column: Int) in
                cell(line.file, column, names: names, busy: busy)
            }
            // as tall as its lines: the tab's own page scrolls - a list that fits is never a scroll of its own
            .frame(height: tall)
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                Text(EditAlbumPage.Words.tagsNote(Platform.device))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(EditAlbumPage.Words.seeEveryTag) {
                    if let selected { everyTag = EveryTag(filename: selected) }
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(selected == nil)
                .accessibilityHint(EditAlbumPage.Words.everyTagHint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: CGFloat(rowSize.rowHeight))
            .overlay(alignment: .top) { DWRule(colour: DWPalette.rowline) }
        }
        .clipShape(DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.frame, lineWidth: 1))
    }

    /// The list's lines: a heading per disc on a set, each disc's tracks under it.
    private var lines: [MacTable.Line<String>] {
        tags.discs.flatMap { (disc: (disc: Int?, files: [AlbumFile])) -> [MacTable.Line<String>] in
            let heading: [MacTable.Line<String>] = disc.disc.map { (number: Int) -> [MacTable.Line<String>] in
                [.group(TagEditWords.disc(number))]
            } ?? []
            return heading + disc.files.map { (file: AlbumFile) -> MacTable.Line<String> in .row(file.filename) }
        }
    }

    @ViewBuilder private func cell(_ file: AlbumFile, _ column: Int, names: [String], busy: Bool) -> some View {
        switch column {
        case 0:
            DWCheckbox(words: TagEditWords.trackRow(label: tags.label(file), title: file.title ?? file.filename,
                                                    artist: TagEditWords.artist(file, album: tags.album)),
                       on: Binding(get: { tags.selection.contains(file.filename) },
                                   set: { (_: Bool) -> Void in tick(file.filename, names: names) }),
                       showsWords: false)
                .disabled(busy)
        case 1:
            Text(tags.label(file))
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        case 2:
            HStack(spacing: 6) {
                Text(file.title ?? file.filename)
                if let artist = TagEditWords.artist(file, album: tags.album) {
                    Text(artist)
                        .foregroundStyle(DWPalette.t2)
                }
            }
        default:
            Text(TrackInspector.trackTime(file.length))
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(DWPalette.t2)
        }
    }

    /// A row to VoiceOver: one element - its words, its length and whether it is ticked - its actions Select (or
    /// Deselect) and See a file's every tag….
    private func voice(_ file: AlbumFile, names: [String], busy: Bool) -> MacRowVoice {
        let ticked = tags.selection.contains(file.filename)
        let row = TagEditWords.trackRow(label: tags.label(file), title: file.title ?? file.filename,
                                        artist: TagEditWords.artist(file, album: tags.album))
        let toggle = MacRowAction(words: ticked ? EditAlbumPage.Words.deselect : TagEditWords.select) {
            if !busy { tick(file.filename, names: names) }
        }
        let open = MacRowAction(words: EditAlbumPage.Words.seeEveryTag) {
            everyTag = EveryTag(filename: file.filename)
        }
        return MacRowVoice(label: EditAlbumPage.Words.tagRow(row, length: TrackInspector.trackTime(file.length),
                                                             ticked: ticked),
                           actions: [toggle, open])
    }

    // MARK: the editor

    /// The editor's box: its legend the tracks it edits; while the files are read again after a save, what was saved and
    /// the read - never the fields as the files said them before; else the fields, the hint, and what would change.
    @ViewBuilder private func editorBox(_ names: [String]) -> some View {
        let ticked = EditAlbumPage.ticked(names, tags.selection)
        MacGroupBox(legend: EditAlbumPage.Words.editLegend(ticked)) {
            VStack(alignment: .leading, spacing: 6) {
                if tags.refreshing {
                    if let applied = tags.applied {
                        Text(applied)
                            .foregroundStyle(DWPalette.greenText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if tags.readFailure == nil, !tags.flow.readFailed {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(TagEditWords.readingFiles).foregroundStyle(DWPalette.t2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else if tags.ready {
                    fields
                        .disabled(tags.flow.applying)
                    Text(TagEditWords.hint(single: tags.single))
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, CGFloat(DWLook.here.labelWidth) + 8)
                        .padding(.top, 4)
                    preview
                        .padding(.top, 6)
                } else if EditAlbumPage.afterRead(names, ticked: tags.selection, editing: tags.editing,
                                                  typed: tags.unsaved) == .stranded {
                    // (R11's review) a release applied renamed every track the typed work was for: said, never left an
                    // empty box - Discard (or Revert) the one way on, the editor then taking the ticks
                    Text(EditAlbumPage.Words.editedGone)
                        .foregroundStyle(DWPalette.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(EditWords.discard) {
                        tags.edit(EditAlbumPage.tagTargets(names, ticked: tags.selection))
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(tags.flow.applying || model.writing)
                }
            }
        }
    }

    /// The eleven fields in the drawing's order (TagEdit.fields'): Track beside Disc, Year beside Original, each pair
    /// said by its own names.
    private var fields: some View {
        VStack(alignment: .leading, spacing: 6) {
            single("title")
            single("artist")
            single("album")
            single("albumartist")
            pair("tracknumber", "discnumber", second: TagEdit.label("discnumber"))
            single("discsubtitle")
            pair("date", "originaldate", second: EditAlbumPage.Words.original)
            single("genre")
            single("composer")
        }
    }

    @ViewBuilder private func single(_ key: String) -> some View {
        if let field = TagEdit.field(key) {
            VStack(alignment: .leading, spacing: 2) {
                DWFieldRow(label: field.label) {
                    input(field)
                }
                line(field)
            }
        }
    }

    @ViewBuilder private func pair(_ first: String, _ second: String, second words: String) -> some View {
        if let one = TagEdit.field(first), let two = TagEdit.field(second) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    DWFieldRow(label: one.label) {
                        input(one)
                    }
                    Text(words)
                        .font(Typeface.Look.text(.fieldLabel))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    input(two)
                        .accessibilityLabel(two.label)
                }
                line(one)
                line(two)
            }
        }
    }

    /// A field on the look's well: what its files share (its prompt when they differ, or say nothing), what was typed
    /// over it, its line to VoiceOver as its value.
    private func input(_ field: TagEdit.Field) -> some View {
        let shared = tags.shared(field.key)
        let edited = tags.draft[field.key] != nil
        return well(TextField(field.label, text: Binding(get: { tags.value(field.key) },
                                                         set: { (typed: String) -> Void in tags.set(field.key, typed) }),
                              prompt: Text(TagEdit.placeholder(field.key, shared, edited: edited))
                                  .foregroundStyle(DWPalette.t3)),
                    field.key, mono: field.short)
            .accessibilityValue(tags.note(field.key) ?? "")
    }

    /// A field on the look's well (MacReleaseTab's): its focus, Tab's order, a click on the well putting the cursor in.
    private func well<Input: View>(_ input: Input, _ key: String, mono: Bool) -> some View {
        faced(input.textFieldStyle(.plain), mono: mono)
            .foregroundStyle(DWPalette.fieldText)
            .autocorrectionDisabled()
            .focused($focused, equals: key)
            .tabs($focused, in: Self.order)
            .focusEffectDisabled()
            // .in: padding 0 8px
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: focused == key)
                    .contentShape(DWTarget(face: DWCorners.buttonShape))
                    .onTapGesture { focused = key }
            }
    }

    /// A field's face: the readout's for the numbers and the dates, the look's field face for words.
    @ViewBuilder private func faced<Input: View>(_ input: Input, mono: Bool) -> some View {
        if mono {
            input.font(Typeface.Mac.mono(.label))
        } else {
            input.font(Typeface.Look.text(.field))
        }
    }

    /// The web's line under a field - its problem in the caution's colour - and Undo once it is typed over.
    @ViewBuilder private func line(_ field: TagEdit.Field) -> some View {
        let note = tags.note(field.key)
        let edited = tags.draft[field.key] != nil
        if note != nil || edited {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let note {
                    Text("\(field.label): \(note)")
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(tags.problems[field.key] != nil ? DWPalette.amberText : DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if edited {
                    Button(TagEditWords.undo) { tags.revert(field.key) }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .accessibilityLabel("\(TagEditWords.undo), \(field.label)")
                        .accessibilityHint(TagEditWords.undoHint)
                }
            }
            .padding(.leading, CGFloat(DWLook.here.labelWidth) + 8)
        }
    }

    // MARK: what would change

    /// What would change, as the phone's preview says it: the last save's words while no preview is in hand, the reason
    /// none is asked, the wait, the plan's problems, nothing to change - or each file that would change in a well in the
    /// readout face, each tag what it says to what it would say; and what Apply's last try came to.
    private var preview: some View {
        let plan = tags.currentPlan
        let problems = tags.problems.count
        let planning = tags.flow.planning && !tags.body.edits.isEmpty && problems == 0
        return VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
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
                if !plan.changed.isEmpty {
                    changes(plan.changed)
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

    /// Each file's changes in a well (Main.dc.html's): its name, then each tag - its label, what it says ("—" for
    /// nothing), →, what it would say ("removed" for nothing).
    private func changes(_ files: [TagEditFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files, id: \.filename) { (file: TagEditFile) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .foregroundStyle(DWPalette.t2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(file.changes, id: \.tag) { (change: TagChange) in
                        let from = change.from.isEmpty ? TagEditWords.none : change.from
                        let to = change.to.isEmpty ? TagEditWords.removed : change.to
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TagEdit.label(change.tag))
                                .foregroundStyle(DWPalette.t2)
                                .frame(width: 96, alignment: .leading)
                            Text(from)
                                .foregroundStyle(DWPalette.t3)
                            Text("→")
                                .foregroundStyle(DWPalette.t3)
                                .accessibilityHidden(true)
                            Text(to)
                                .foregroundStyle(change.to.isEmpty ? DWPalette.t3 : DWPalette.text)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(TagEdit.label(change.tag)): \(from), \(to)")
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

/// A track of the Tags list, by its file's name.
private struct TrackLine: Identifiable {
    let file: AlbumFile
    var id: String { file.filename }
}

/// The file whose every tag the sheet shows.
private struct EveryTag: Identifiable {
    let filename: String
    var id: String { filename }
}

/// A file's every tag on the Mac (the phone's track page, TrackPageView), in a sheet over the Tags tab: its title and
/// where it sits, Edit this track… (only this file ticked), every field the web's inspector shows under its group - the
/// ones the file has, a default dimmed and its reason under the group - the pictures inside it (each opening full size),
/// and every tag under its container's own name, in a well in the readout face.
struct MacTrackTags: View {
    let model: EditAlbumModel
    let tags: TagsModel
    let filename: String
    /// Edit this track…: only this file ticked - the tab's, through "Discard changes?" over typed work.
    let editThis: () -> Void

    @State private var full: FullCover?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let file = tags.file(filename) {
                    head(file)
                    ForEach(TrackInspector.groups(file)) { (section: TrackInspector.Section) in
                        group(section)
                    }
                    pictures(file)
                    raw(file)
                } else {
                    Text(TagEditWords.readFailed).foregroundStyle(DWPalette.t2)
                }
            }
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.text)
            .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
        }
        .background(DWPalette.panel)
        .navigationTitle(tags.file(filename)?.title ?? filename)
        .appCover(item: $full) { (cover: FullCover) in
            FullCoverView(cover: cover)
                .macSheet()
        }
    }

    private func head(_ file: AlbumFile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(TrackInspector.title(file).isEmpty ? file.filename : TrackInspector.title(file))
                    .font(Typeface.Mac.text(.h3).weight(.semibold))
                    .foregroundStyle(DWPalette.head)
                if TrackInspector.untitled(file) {
                    Text(TrackInspector.noTitle)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
                Text(TrackInspector.place(file, discs: tags.album.discCount))
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button(TrackInspector.editThis, action: editThis)
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(model.writing || tags.flow.applying)
        }
    }

    /// One group (Tags, Audio, MusicBrainz, File): the fields the file has, the label at the left as Fields' are, the
    /// value selectable - in the readout face for a number or an id, the third colour for a default, its reason under.
    @ViewBuilder private func group(_ section: TrackInspector.Section) -> some View {
        let shown = section.fields.filter { (field: TrackInspector.Field) -> Bool in !field.value.isEmpty }
        if !shown.isEmpty {
            MacGroupBox(legend: section.group.rawValue) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shown) { (field: TrackInspector.Field) in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(field.label)
                                .font(Typeface.Look.text(.fieldLabel))
                                .foregroundStyle(DWPalette.t2)
                                .frame(width: CGFloat(DWLook.here.labelWidth), alignment: .trailing)
                            value(field)
                                .foregroundStyle(field.inferred == nil ? DWPalette.text : DWPalette.t3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(field.inferred ?? "")
                    }
                    if let why = shown.compactMap({ (field: TrackInspector.Field) -> String? in field.inferred }).first {
                        Text(why)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, CGFloat(DWLook.here.labelWidth) + 8)
                    }
                }
            }
        }
    }

    /// A field's value: in the readout face for a number or an id, the Mac's words otherwise.
    @ViewBuilder private func value(_ field: TrackInspector.Field) -> some View {
        if field.mono {
            Text(field.value).font(Typeface.Mac.mono(.label))
        } else {
            Text(field.value).font(Typeface.Mac.text(.base))
        }
    }

    private func pictures(_ file: AlbumFile) -> some View {
        MacGroupBox(legend: TrackInspector.pictures) {
            VStack(alignment: .leading, spacing: 8) {
                if file.pictures.isEmpty {
                    Text(TrackInspector.noPictures)
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // by place, not by the server's index: an index read loosely is 0, and two pictures with one id would be
                // drawn as one
                ForEach(Array(file.pictures.enumerated()), id: \.offset) {
                    (entry: (offset: Int, element: EmbeddedPicture)) in
                    let picture = entry.element
                    Button {
                        full = FullCover(source: .picture(path: tags.album.path, file: file.filename, index: picture.index))
                    } label: {
                        MacPictureRow(path: tags.album.path, file: file.filename, picture: picture)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func raw(_ file: AlbumFile) -> some View {
        MacGroupBox(legend: TrackInspector.rawTitle(file)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array((file.raw ?? []).enumerated()), id: \.offset) { (_, pair: [String]) in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pair.first ?? "")
                            .foregroundStyle(DWPalette.t2)
                            .frame(width: 150, alignment: .leading)
                        Text(pair.dropFirst().first ?? "")
                            .foregroundStyle(DWPalette.text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
                Text(file.filename)
                    .foregroundStyle(DWPalette.t3)
                    .padding(.top, 4)
            }
            .font(Typeface.Mac.mono(.label))
            .textSelection(.enabled)
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { DWWell(focused: false) }
        }
    }
}

/// One picture inside a file on the Mac: a thumbnail on a picture's face, its label and its facts (TrackInspector's) -
/// read by VoiceOver as one, saying a click shows it.
private struct MacPictureRow: View {
    let path: String
    let file: String
    let picture: EmbeddedPicture

    @Environment(ServerModel.self) private var server
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                DWPalette.card
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(DWCorners.chipShape)
            .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(picture.label)
                    .foregroundStyle(DWPalette.text)
                Text(TrackInspector.pictureFacts(picture, pixels: image.map { (shown: UIImage) -> String in
                    TrackInspector.pixels(width: Int(shown.size.width * shown.scale), height: Int(shown.size.height * shown.scale))
                }))
                .font(Typeface.Mac.mono(.label))
                .foregroundStyle(DWPalette.t2)
                if !picture.description.isEmpty {
                    Text(picture.description)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
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
