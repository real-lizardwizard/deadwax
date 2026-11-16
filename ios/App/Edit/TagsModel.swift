import DeadwaxCore
import Observation
import SwiftUI

/// Edit album's Tags (notes/ios-specs/phase8-managing.md 3.4; the web's EditPanel TagsList, TrackInspector and
/// components/TrackTagEditor.tsx) for one folder: its files as read from the disk just now (`/library/tracks`), the
/// tracks selected, and the editor - which files it edits, what was typed over each field, the preview and what the
/// last apply did. Every rule is Core's - TagEdit (the fields, shared values, edits, problems, notes), TagEditWords and
/// TrackInspector (every word), RetagFlow (which preview lands, when one goes, when Apply is on - the Release page's
/// own rules, a tag edit's preview and apply being the same plan/execute pair) - this keeps the answers, makes the
/// requests and hands the pages what the rules say. EditAlbumModel holds it, one for each folder it holds, and
/// carries out Apply.
///
/// Its files are read the first time Tags opens, and again whenever the scan reads the folder again (after a write, a
/// gap, Look again) - the preview describes the files as they were last read, so a write or a gap waits for that read
/// before Apply comes back (RetagFlow.needsRead). Only the newest read lands.
@MainActor
@Observable
final class TagsModel {
    /// The folder, as the scan last read it.
    private(set) var album: ScanAlbum
    /// Every audio file in the folder, in running order - nil until the first read lands.
    private(set) var files: [AlbumFile]?
    private(set) var reading = false
    /// The last read failed: in the phone's words, with Look again.
    private(set) var readFailure: String?
    /// The tracks selected in Select.
    var selection: Set<String> = []
    /// The files the editor edits, in running order - fixed when it opened.
    private(set) var editing: [String] = []
    /// What was typed over each field - only the fields touched (TagEdit.edits sends nothing else).
    private(set) var draft: [String: String] = [:]
    /// The preview in hand (RetagFlow says whether it describes what Apply would send now).
    private(set) var plan: TagEditPlan?
    private(set) var previewError: String?
    /// What the last apply did ("Saved 3 files."), and what it couldn't do.
    private(set) var applied: String?
    private(set) var applyError: String?
    private(set) var flow: RetagFlow

    @ObservationIgnored var client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var reads = 0
    @ObservationIgnored private var started = false

    init(album: ScanAlbum, online: Bool, admin: Bool, client: DeadwaxClient?) {
        self.album = album
        self.flow = RetagFlow(online: online)
        self.admin = admin
        self.client = client
    }

    // MARK: what the pages read

    /// The folder's files by name.
    func file(_ name: String) -> AlbumFile? { files?.first { $0.filename == name } }

    /// The files the editor edits, as last read - fewer than `editing` when one has gone since.
    var editingFiles: [AlbumFile] { editing.compactMap(file) }

    /// Every file the editor edits has been read: the fields can show what they say (the web's `ready`).
    var ready: Bool { !editing.isEmpty && editingFiles.count == editing.count }

    /// A track number in the list: the disc first on a set.
    func label(_ file: AlbumFile) -> String {
        TagEdit.trackLabel(position: file.position, disc: file.disc, discs: album.discCount)
    }

    /// The list's sections: one per disc on a set (by the file's own disc number, a file with none on disc 1), one
    /// in all otherwise - in the server's running order.
    var discs: [(disc: Int?, files: [AlbumFile])] {
        let all = files ?? []
        guard album.discCount > 1 else { return [(nil, all)] }
        var order: [Int] = []
        var byDisc: [Int: [AlbumFile]] = [:]
        for file in all {
            let disc = file.disc ?? 1
            if byDisc[disc] == nil { order.append(disc) }
            byDisc[disc, default: []].append(file)
        }
        return order.map { ($0, byDisc[$0] ?? []) }
    }

    /// What one field holds across the files edited.
    func shared(_ key: String) -> TagEdit.Shared { TagEdit.shared(editingFiles, key) }

    /// What a field shows: what was typed over it, else what the files share.
    func value(_ key: String) -> String { draft[key] ?? shared(key).value }

    /// Each field typed over that can't take what was typed, and why.
    var problems: [String: String] {
        draft.reduce(into: [:]) { found, entry in
            if let problem = TagEdit.problem(entry.key, entry.value) { found[entry.key] = problem }
        }
    }

    /// The line under a field (TagEdit.note), or nil.
    func note(_ key: String) -> String? { TagEdit.note(key, shared(key), draft: draft[key], problem: problems[key]) }

    /// What Apply sends - and the preview, the same body.
    var body: TagEditBody { TagEditBody(albumPath: album.path, edits: TagEdit.edits(filenames: editing, draft: draft)) }

    /// The preview, only while it describes what Apply would send now.
    var currentPlan: TagEditPlan? { flow.current ? plan : nil }

    var canApply: Bool { ready && flow.canApply(plan, problems: problems.count) }

    /// Typed work Close would throw away.
    var unsaved: Bool { !draft.isEmpty }

    var single: Bool { editing.count == 1 }

    // MARK: reading the files

    /// Tags opened: the files read, once.
    func start() {
        guard !started else { return }
        started = true
        Task { await readFiles() }
    }

    /// The folder's files read from the disk now - only the newest read lands; a cancelled one changes nothing.
    func readFiles() async {
        guard let client else { return }
        reads += 1
        let ticket = reads
        reading = true
        do {
            let found = try await client.albumFiles(folder: album.path)
            guard ticket == reads else { return }
            reading = false
            files = found
            readFailure = nil
            // a file edited that has gone since (a release applied renames them): the editor's selection with it
            selection = selection.filter { name in found.contains { $0.filename == name } }
            flow.read()
            schedulePreview()
        } catch {
            guard ticket == reads else { return }
            reading = false
            guard !APIFailure.isCancellation(error) else { return }
            readFailure = EditWords.said(error, failed: TagEditWords.readFailed, admin: admin)
            flow.couldNotRead()
        }
    }

    /// The folder as the scan read it again: followed (a move changes its path), and - once Tags has opened - its
    /// files read again.
    func albumRead(_ fresh: ScanAlbum) {
        album = fresh
        // never opened: nothing previewed to wait for - the files are read when Tags opens
        guard started else {
            flow.read()
            return
        }
        Task { await readFiles() }
    }

    /// Another part of Edit album wrote to the folder (Release's apply - RetagFlow.folderChanged): no
    /// preview in flight lands, and Apply waits for the files to be read again.
    func folderChanged() {
        guard started else { return }
        previewTask?.cancel()
        flow.folderChanged()
    }

    // MARK: the editor

    /// Edit tags opened for `filenames`: a new set of files starts from what they say - the same set keeps what was
    /// typed.
    func edit(_ filenames: [String]) {
        guard filenames != editing else { return }
        editing = filenames
        draft = [:]
        plan = nil
        previewError = nil
        applied = nil
        applyError = nil
        changed()
    }

    /// Typing over a field.
    func set(_ key: String, _ value: String) {
        guard draft[key] != value else { return }
        // the message describes a write that has happened: changed, it no longer describes what Apply would do
        applied = nil
        draft[key] = value
        changed()
    }

    /// Undo: the field put back to what the files say.
    func revert(_ key: String) {
        guard draft[key] != nil else { return }
        applied = nil
        draft[key] = nil
        changed()
    }

    // MARK: the preview

    private func changed() {
        flow.changed()
        schedulePreview()
    }

    /// The preview of what Apply would send, once the typing stops - none while nothing is typed over or a field is
    /// plainly wrong (the server would only refuse it, and the field already says why: TrackTagEditor's effect).
    private func schedulePreview() {
        previewTask?.cancel()
        let edit = flow.edits
        let body = self.body
        if body.edits.isEmpty || !problems.isEmpty {
            if flow.answered(edit) {
                plan = nil
                previewError = nil
            }
            return
        }
        // out of reach, a write under way or the files to be read again: what ends it previews again
        guard flow.due(edit) else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Retag.previewDebounceMs))
            guard let self, !Task.isCancelled, self.flow.due(edit), let client = self.client else { return }
            do {
                let next = try await client.tagsPreview(body)
                if self.flow.answered(edit) {
                    self.plan = next
                    self.previewError = nil
                }
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                if self.flow.failed(edit) {
                    self.plan = nil
                    self.previewError = EditWords.said(error, failed: TagEditWords.previewFailed, admin: self.admin)
                }
            }
        }
    }

    // MARK: Apply

    /// Apply pressed: the body to send - nil when Apply isn't on.
    func beginApply() -> TagEditBody? {
        guard ready, flow.beginApply(plan, problems: problems.count) else { return nil }
        applied = nil
        applyError = nil
        return body
    }

    /// The apply is over: what came of it said (TrackTagEditor's `apply`), the flow told. Saved with nothing failed,
    /// the fields go back to what the files now say - the phone's own: the web leaves what was typed in them.
    func applyEnded(_ result: Result<TagEditResponse, any Error>) -> RetagFlow.Outcome {
        let outcome: RetagFlow.Outcome
        switch result {
        case .success(let response):
            outcome = .applied
            let said = TagEditWords.saved(response.results, filenames: editing)
            if said.failed {
                applyError = said.text
            } else {
                applied = said.text
                draft = [:]
            }
            plan = nil
        case .failure(let error):
            outcome = RetagFlow.outcome(of: error)
            applyError = EditWords.writeFailure(error, failed: TagEditWords.applyFailed, admin: admin)
        }
        flow.applyEnded(outcome)
        if outcome == .refused { schedulePreview() }
        return outcome
    }

    // MARK: reach

    func wentAway() {
        flow.wentAway()
        previewTask?.cancel()
    }

    /// Back in reach: nothing offered until the files are read again (EditAlbumModel reads the folder, and albumRead
    /// reads them).
    func cameBack() {
        flow.cameBack()
    }

    /// The folder couldn't be read again: the wait for it ends, said with Look again.
    func couldNotRead() {
        flow.couldNotRead()
    }
}
