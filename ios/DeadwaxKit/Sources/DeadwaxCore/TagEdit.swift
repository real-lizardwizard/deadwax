import Foundation

/// Editing tags by hand (Phase 8, slice 2 - notes/ios-specs/phase8-managing.md 3.4): ui/src/lib/tagEdit.ts's fields,
/// what a selection holds in each, what to send, what a value can't be and the line under a field, with
/// lib/albumEdit.ts's `trackLabel` - held to the web's own answers by Fixtures/edit/edit-parts-vectors.json.
///
/// The failure it guards against is a silent one: a mass edit that sent the form's value back for a field nobody
/// touched would overwrite every track's own with whatever the form happened to show. So only EDITED fields are sent,
/// and a field whose files disagree starts empty and keeps each one's own until it is typed over.
public enum TagEdit {
    /// One field the editor offers: mutagen's easy-interface name (src/track_tags.py EDITABLE_TAGS), its label, and
    /// whether it is a short one (numbers and dates) and a number (the number pad).
    public struct Field: Sendable, Equatable, Hashable {
        public let key: String
        public let label: String
        public let short: Bool
        public let numeric: Bool

        public init(key: String, label: String, short: Bool = false, numeric: Bool = false) {
            self.key = key
            self.label = label
            self.short = short
            self.numeric = numeric
        }
    }

    /// `EDIT_FIELDS`, in the web's order - which is EDITABLE_TAGS' order on the server.
    public static let fields: [Field] = [
        Field(key: "title", label: "Title"),
        Field(key: "artist", label: "Artist"),
        Field(key: "album", label: "Album"),
        Field(key: "albumartist", label: "Album artist"),
        Field(key: "tracknumber", label: "Track", short: true, numeric: true),
        Field(key: "discnumber", label: "Disc", short: true, numeric: true),
        Field(key: "discsubtitle", label: "Disc title"),
        Field(key: "date", label: "Year", short: true),
        Field(key: "originaldate", label: "Original year", short: true),
        Field(key: "genre", label: "Genre"),
        Field(key: "composer", label: "Composer"),
    ]

    public static func field(_ key: String) -> Field? { fields.first { $0.key == key } }

    /// The preview's name for a tag: the form's own label, so the two read as one thing (TrackTagEditor's `LABELS`).
    public static func label(_ key: String) -> String { field(key)?.label ?? key }

    /// The phone's grouping of the eleven fields into a Form's four sections (the spec's own; the web lays them out
    /// in one grid), each in the web's order.
    public static let sections: [(title: String, keys: [String])] = [
        ("Track", ["title", "artist", "tracknumber"]),
        ("Album", ["album", "albumartist", "discnumber", "discsubtitle"]),
        ("Dates", ["date", "originaldate"]),
        ("More", ["genre", "composer"]),
    ]

    /// What one field holds across the files being edited (`SharedValue`).
    public struct Shared: Sendable, Equatable {
        /// The value every file agrees on, or "" when they disagree - or all go without.
        public let value: String
        /// The files disagree, so the field starts empty and an untouched field keeps each one's own.
        public let mixed: Bool

        public init(value: String, mixed: Bool) {
            self.value = value
            self.mixed = mixed
        }
    }

    /// `sharedValue(files, key)`: a file without the tag counts as "", and the values are told apart as JavaScript's
    /// Set does (by UTF-16 unit).
    public static func shared(_ files: [AlbumFile], _ key: String) -> Shared {
        let values = WebText.unique(files.map { $0.tags?[key] ?? "" })
        if values.count > 1 { return Shared(value: "", mixed: true) }
        return Shared(value: values.first ?? "", mixed: false)
    }

    /// `buildEdits(filenames, draft)`: every edited field, trimmed, for every file being edited - none at all with
    /// nothing edited. An edited field that is empty goes as "" and removes the tag (the server reads "" and null
    /// alike, src/track_tags.py), which the preview spells out before anything is written.
    public static func edits(filenames: [String], draft: [String: String]) -> [TagEditBody.Edit] {
        if draft.isEmpty { return [] }
        let tags = draft.mapValues { WebText.trim($0) }
        return filenames.map { TagEditBody.Edit(filename: $0, tags: tags) }
    }

    /// `tagProblem(key, value)`: why a value can't go in a field, or nil - an empty one is fine (it removes the tag).
    /// Mirrors src/track_tags.py `validate_tag`, so a mistake shows under the field as it is typed; the server's check
    /// is the one that counts.
    public static func problem(_ key: String, _ value: String) -> String? {
        let text = WebText.trim(value)
        if text.isEmpty { return nil }
        if text.utf16.count > 1000 { return "Longer than 1000 characters" }
        if text.utf16.contains(where: { $0 <= 0x1F || $0 == 0x7F }) { return "One line only" }
        if (key == "tracknumber" || key == "discnumber") && !isNumber(text) {
            return "Has to be a number, like 3 or 3/12"
        }
        if (key == "date" || key == "originaldate") && !isDate(text) {
            return "Has to be a year or a date, like 2022 or 2022-07-29"
        }
        return nil
    }

    /// `/^\d{1,4}(\/\d{1,4})?$/` - JavaScript's `\d` is the ASCII digits alone.
    static func isNumber(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        return parts.allSatisfy { (1...4).contains($0.utf16.count) && $0.utf16.allSatisfy(isDigit) }
    }

    /// `/^\d{4}(-\d{2}(-\d{2})?)?$/`.
    static func isDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return false }
        let widths = [4, 2, 2]
        return parts.enumerated().allSatisfy { at, part in
            part.utf16.count == widths[at] && part.utf16.allSatisfy(isDigit)
        }
    }

    static func isDigit(_ unit: UInt16) -> Bool { (0x30...0x39).contains(unit) }

    /// `removesTag(shared, draft)`: edited to nothing - but only from tracks that have one to remove. `draft` is what
    /// was typed over the field, nil while it is left alone.
    public static func removes(_ shared: Shared, draft: String?) -> Bool {
        guard let draft else { return false }
        return WebText.trim(draft).isEmpty && (shared.mixed || !shared.value.isEmpty)
    }

    /// `fieldPlaceholder(key, shared, edited)`: "Several values" over files that disagree while it is left alone; a
    /// disc number defaults to 1, so an untagged one says so rather than looking blank; "Not set" otherwise.
    public static func placeholder(_ key: String, _ shared: Shared, edited: Bool) -> String {
        shared.mixed && !edited ? "Several values" : key == "discnumber" ? "1" : "Not set"
    }

    /// `fieldNote(key, shared, draft, problem)`: the line under a field - its problem as typed first; then that
    /// emptying it removes the tag; that the files disagree and, left alone, each keeps its own; or that a disc number
    /// never tagged reads as disc 1. Nil for none.
    public static func note(_ key: String, _ shared: Shared, draft: String?, problem: String?) -> String? {
        let edited = draft != nil
        if let problem { return problem }
        if removes(shared, draft: draft) { return "Will be removed" }
        if shared.mixed && !edited { return "Differs between tracks - left alone, each keeps its own" }
        if key == "discnumber" && !edited && shared.value.isEmpty { return "Not tagged - reads as disc 1" }
        return nil
    }

    /// lib/albumEdit.ts `trackLabel`: a track's number in the list - the disc first on a set ("2-04"), the number
    /// alone otherwise, a dot for a file with no number.
    public static func trackLabel(position: Int?, disc: Int?, discs: Int) -> String {
        guard let position else { return "·" }
        if discs <= 1 { return String(position) }
        let number = String(position)
        return "\(disc ?? 1)-\(String(repeating: "0", count: max(0, 2 - number.utf16.count)))\(number)"
    }
}

/// What the Tags pages say (Phase 8, slice 2): components/TrackTagEditor.tsx's words and app/EditPanel.tsx TagsList's,
/// as the web writes them - read out of their sources into Fixtures/edit/edit-parts-vectors.json and held there.
public enum TagEditWords {
    public static let title = "Edit tags"
    public static let tags = "Tags"
    public static let readingFiles = "Reading the files…"
    public static let previewFailed = "Couldn't work out the changes."
    public static let applyFailed = "Couldn't save the tags."
    public static let readFailed = "Couldn't read the files."
    public static let whatWouldChange = "What would change"
    public static let changeAField = "Change a field to see what would be written."
    public static let working = "Working out the changes…"
    public static let saving = "Saving…"
    public static let apply = "Apply"
    public static let undo = "Undo"
    public static let undoHint = "Put back what the files say"
    public static let removed = "removed"
    public static let none = "—"
    public static let selectAll = "Select every track"
    public static let deselectAll = "Deselect every track"
    /// The list's line with nothing selected - the web's words for a phone's sheet.
    public static let selectNote = "Select tracks to edit only those. Tap a track's name to see everything in its file."
    /// The bar's button that turns multi-select on (the web's verb since 2.0.8: "Select", never "Tick").
    public static let select = "Select"

    /// What VoiceOver hears of a track's row: its number, its title (its file's name without one), its artist when
    /// it differs from the album's.
    public static func trackRow(label: String, title: String, artist: String?) -> String {
        [label == "·" ? "" : "Track \(label)", title, artist ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// A row's artist, shown only when it isn't the album's (the list's "3 · Title" line with its artist when it
    /// differs - phase8-managing.md 3.4).
    public static func artist(_ file: AlbumFile, album: ScanAlbum) -> String? {
        let artist = WebText.trim(file.tags?["artist"] ?? "")
        guard !artist.isEmpty, !WebText.same(artist, WebText.trim(album.artist)) else { return nil }
        return artist
    }

    /// A disc's section on a set.
    public static func disc(_ number: Int?) -> String { "Disc \(number ?? 1)" }

    /// The bottom toolbar's button: "Edit 3 tracks…", or "Edit all tracks…" with none selected.
    public static func editTracks(_ selected: Int) -> String {
        selected > 0 ? "Edit \(selected) track\(selected == 1 ? "" : "s")…" : "Edit all tracks…"
    }

    /// "3 of 12 selected".
    public static func selected(_ count: Int, of total: Int) -> String { "\(count) of \(total) selected" }

    /// "Fix the marked field first." / "fields".
    public static func fixFirst(_ count: Int) -> String { "Fix the marked field\(count == 1 ? "" : "s") first." }

    /// The preview with nothing to write.
    public static func nothingToChange(single: Bool) -> String {
        "Nothing to change - \(single ? "the track already says" : "every track already says") that."
    }

    /// "2 of 12 files would change".
    public static func wouldChange(_ plan: TagEditPlan) -> String {
        "\(plan.changedFileCount) of \(RetagWords.files(plan.fileCount)) would change"
    }

    /// What the editor is editing: one track's title (its file's name without one), else "12 tracks".
    public static func heading(filenames: [String], files: [AlbumFile]) -> String {
        if filenames.count == 1 { return files.first?.tags?["title"] ?? filenames.first ?? "one track" }
        return "\(filenames.count) tracks"
    }

    /// "Editing these 12 tracks".
    public static func editingThese(_ count: Int) -> String { "Editing these \(count) tracks" }

    /// The line under the fields - the web's, with its Release *tab* the phone's Release *page*.
    public static func hint(single: Bool) -> String {
        "Only the fields you change are written\(single ? "" : ", to every track above")."
            + (single ? "" : " A field showing several values keeps each track’s own unless you type over it.")
            + " Empty a field to remove that tag. No file is renamed and the folder stays where it is - the Release"
            + " page moves an album's folder to where its tags say it belongs."
    }

    /// After an apply: "Saved 3 files." and each problem the writer named as a sentence (one that starts with a file's
    /// name keeps it as it is on disk) - `failed` when any file wasn't written, said as the web says an error.
    public static func saved(_ results: TagEditResults, filenames: [String]) -> (text: String, failed: Bool) {
        let said = (["Saved \(RetagWords.files(results.written))."]
                    + results.problems.map { ErrorWords.asSentence($0, keeping: filenames) }).joined(separator: " ")
        return (said, results.failed > 0)
    }

    /// The preview's problems as sentences, a file's name kept as it is on disk.
    public static func problems(_ plan: TagEditPlan, filenames: [String]) -> [String] {
        plan.problems.map { ErrorWords.asSentence($0, keeping: filenames) }
    }

    /// Apply may be pressed (the web's button's `disabled`, turned round): a current plan that changes something with
    /// no problem, nothing on its way, and no field wrong as typed.
    public static func canApply(plan: TagEditPlan?, planning: Bool, applying: Bool, problems: Int) -> Bool {
        guard let plan else { return false }
        return !plan.empty && plan.problems.isEmpty && !planning && !applying && problems == 0
    }
}

extension EditWords {
    /// A picture full screen that couldn't be fetched (a track's own, a disc's) - the phone's own words: the web's
    /// viewer leaves its image broken.
    public static let pictureFailed = "Couldn't load this picture."
}

/// What the Tags preview and apply are sent (`TagEditRequest`, src/routes/library.py): the folder, and each file with
/// the tags typed over - a tag left out is not touched; "" removes it.
public struct TagEditBody: Encodable, Sendable, Equatable {
    public struct Edit: Encodable, Sendable, Equatable {
        public let filename: String
        public let tags: [String: String]

        public init(filename: String, tags: [String: String]) {
            self.filename = filename
            self.tags = tags
        }

        enum CodingKeys: String, CodingKey { case filename, tags }
    }

    public let albumPath: String
    public let edits: [Edit]

    public init(albumPath: String, edits: [Edit]) {
        self.albumPath = albumPath
        self.edits = edits
    }

    enum CodingKeys: String, CodingKey {
        case edits
        case albumPath = "album_path"
    }
}

/// One file of a tag edit's preview (`TagEditFile`): its name and only the tags that would really change - in the
/// form's order (the web lists them in the order the fields were typed into; the server's dictionary is that order,
/// which a phone's encoder doesn't keep).
public struct TagEditFile: Sendable, Equatable, Decodable {
    public let filename: String
    public let changes: [TagChange]

    public init(filename: String, changes: [TagChange]) {
        self.filename = filename
        self.changes = changes
    }

    enum CodingKeys: String, CodingKey { case filename, changes }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        filename = try fields.decode(String.self, forKey: .filename)
        let changed = fields.looseField([String: TagChange.Value].self, .changes) ?? [:]
        changes = changed.keys.sorted(by: Self.inFormOrder)
            .map { TagChange(tag: $0, from: changed[$0]!.from, to: changed[$0]!.to) }
    }

    /// The form's order, a tag it doesn't offer after them by name.
    static func inFormOrder(_ a: String, _ b: String) -> Bool {
        let at = TagEdit.fields.firstIndex { $0.key == a } ?? Int.max
        let bt = TagEdit.fields.firstIndex { $0.key == b } ?? Int.max
        return at != bt ? at < bt : a < b
    }
}

/// What a tag edit would do (`TagEditPlan`) - written by the same planner the apply recomputes, never sent back.
public struct TagEditPlan: Sendable, Equatable, Decodable {
    public let albumPath: String
    /// Nil when the folder couldn't be read at all; `problems` says why.
    public let source: String?
    public let files: [TagEditFile]
    public let fileCount: Int
    public let changedFileCount: Int
    /// Anything wrong with the request - any of them and Apply refuses the whole batch.
    public let problems: [String]
    /// Nothing would change.
    public let empty: Bool

    public init(albumPath: String, source: String?, files: [TagEditFile], fileCount: Int, changedFileCount: Int,
                problems: [String], empty: Bool) {
        self.albumPath = albumPath
        self.source = source
        self.files = files
        self.fileCount = fileCount
        self.changedFileCount = changedFileCount
        self.problems = problems
        self.empty = empty
    }

    enum CodingKeys: String, CodingKey {
        case source, files, problems, empty
        case albumPath = "album_path"
        case fileCount = "file_count"
        case changedFileCount = "changed_file_count"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        albumPath = fields.looseField(String.self, .albumPath) ?? ""
        source = fields.looseField(String.self, .source)
        files = fields.looseList(TagEditFile.self, .files) ?? []
        fileCount = fields.looseField(Int.self, .fileCount) ?? 0
        changedFileCount = fields.looseField(Int.self, .changedFileCount) ?? 0
        problems = fields.looseList(String.self, .problems) ?? []
        empty = fields.looseField(Bool.self, .empty) ?? true
    }

    /// The files with something to change - the only ones the preview lists.
    public var changed: [TagEditFile] { files.filter { !$0.changes.isEmpty } }
}

/// What an apply did (`TagEditResults`): how many files were written, how many weren't, and every problem - a tag a
/// file's format couldn't hold named rather than dropped in silence.
public struct TagEditResults: Sendable, Equatable, Decodable {
    public let written: Int
    public let failed: Int
    public let problems: [String]

    public init(written: Int, failed: Int, problems: [String]) {
        self.written = written
        self.failed = failed
        self.problems = problems
    }

    enum CodingKeys: String, CodingKey { case written, failed, problems }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        written = fields.looseField(Int.self, .written) ?? 0
        failed = fields.looseField(Int.self, .failed) ?? 0
        problems = fields.looseList(String.self, .problems) ?? []
    }
}

/// `POST /library/tags/apply`'s answer: the plan worked out again, and what was written.
public struct TagEditResponse: Sendable, Equatable, Decodable {
    public let plan: TagEditPlan
    public let results: TagEditResults

    public init(plan: TagEditPlan, results: TagEditResults) {
        self.plan = plan
        self.results = results
    }

    enum CodingKeys: String, CodingKey { case plan, results }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        plan = try fields.decode(TagEditPlan.self, forKey: .plan)
        results = try fields.decode(TagEditResults.self, forKey: .results)
    }
}
