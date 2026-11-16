import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// What Edit album is opened for (notes/ios-specs/phase8-managing.md 1): an album page's album, by Navidrome's id and
/// what the page knew of it - its folders found from the id bridge, else the scan - or one folder of the library,
/// picked in Choose the folder. One opening each: a second Edit album is a new one.
///
/// (Phase 8, slice 6) Opened from Needs a look, it carries the page's session (`queue`): the editor is in queue mode,
/// its folder the session's current album, stepping through the rest in the same sheet.
struct AlbumEditRequest: Identifiable, Equatable {
    enum Target: Equatable {
        case album(AlbumEdit.Subject)
        case folder(String)
    }

    let id = UUID()
    let target: Target
    /// Needs a look's page, when the editor was opened from it - nil from anywhere else.
    var queue: NeedsLookModel?

    init(target: Target, queue: NeedsLookModel? = nil) {
        self.target = target
        self.queue = queue
    }

    /// One opening each: the same request is the same opening.
    static func == (one: AlbumEditRequest, other: AlbumEditRequest) -> Bool { one.id == other.id }
}

/// Edit album's state (phase8-managing.md 3.1, 3.2, 3.7; the web's app/EditPanel.tsx): which folder the album is - the
/// bridge's and the scan's answers through AlbumEdit.folders, or the folder picked - the album held once it is known,
/// its Release (RetagModel), its Tags (TagsModel), its Gets (slice 3: Get cover, Get CD art, Get lyrics), Delete album
/// (slice 4: the summary, Delete permanently, the sheet closing and the page going back), what Needs a look says of it
/// and the two marks, and everything after a write: the folder
/// read again, the album page beneath asked again now and once Navidrome has scanned, and - when the release changed -
/// the album's new id in Navidrome looked for, the page beneath moved to it. Every rule is Core's; this asks and keeps.
///
/// It needs deadwax: opened out of reach it asks nothing (the sheet says so); gone out of reach, what is drawn stays and
/// every write is off; back, everything is asked again before a write comes back on. Nothing is kept on disk.
///
/// An apply can hold its answer for minutes, and deadwax carries on when the phone goes: it is held with a background
/// task for the seconds iOS gives, and one whose answer never came (or came as a 5xx) is said as maybe finished, the
/// folder read again (RetagFlow.whereAfter: where the scan now lists it) - never the same Apply on the old preview. While
/// a write runs, nothing a read brings drops the album held or its Release. What comes after a write outlives the sheet
/// (it ends within about 45 s): an album page left open beneath still follows the album - but never past a sign-out, or
/// into the next person's pages (`session`, AppNavigation's when the sheet opened).
///
/// (Phase 8, slice 6) In queue mode (opened from Needs a look) the scan is the page's - one read, one ETag - and every
/// write tells the page what became of the album (NeedsLookModel.heard: its row followed and marked); a delete leaves
/// the sheet up saying so, the queue going on from there (the web's "Next album" after a delete), where anywhere else it
/// closes. Every write, here or not, asks Needs a look's count again (AppNavigation.managed).
@MainActor
@Observable
final class EditAlbumModel {
    private(set) var target: AlbumEditRequest.Target
    let scan: LibraryScanModel
    /// Needs a look's page, in queue mode.
    @ObservationIgnored private(set) weak var queue: NeedsLookModel?
    /// (slice 6) The folder a delete took, in queue mode: the sheet says so (AlbumEdit.status), and stays.
    private(set) var deletedPath: String?
    /// The id bridge's answer - nil before it answers, and when it couldn't.
    private(set) var bridge: AlbumEdit.Bridge?
    /// The bridge has answered or failed (a folder opening asks none).
    private(set) var asked = false
    /// A folder picked in Choose the folder, for this opening: the album's folder from now on.
    private(set) var chosen: String?
    /// The album being edited - the scan's folder, once its folder is known.
    private(set) var album: ScanAlbum?
    /// Its Release.
    private(set) var retag: RetagModel?
    /// Its Tags (slice 2): the files, the selection, the tag editor.
    private(set) var tags: TagsModel?
    /// deadwax in reach (Reachability).
    private(set) var online: Bool
    /// It's fine as it is / Ask about it again on its way, and what went wrong.
    private(set) var marking = false
    private(set) var markFailure: String?
    /// Get cover, Get CD art and Get lyrics (slice 3): each one's last run, kept with the folder it ran for.
    private(set) var runs: [GetResults.Kind: GetRun] = [:]
    /// A Get whose answer never came (or came as a 5xx): said as maybe finished until the folder's next read lands.
    private(set) var unansweredGet: GetResults.Kind?
    /// Delete album (slice 4): the folder's summary, read live as its page opens, Delete permanently and how it ended.
    private(set) var deletion = DeleteFlow()
    /// The folder is gone - Delete permanently answered, or a delete that never answered isn't in the next read: the
    /// sheet closes.
    private(set) var deleted = false
    /// The cover drawn in the header and Compare covers - its mtime, so a cover replaced is asked again.
    var coverKey: String { album.map { "\($0.path)|\($0.artMtime)" } ?? "" }

    @ObservationIgnored var client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    @ObservationIgnored private(set) weak var navigation: AppNavigation?
    /// The Library's lists, asked again once a folder is deleted.
    @ObservationIgnored private weak var library: LibraryModel?
    /// A delete whose answer never came (or came as a 5xx): the folder it was for, and whether it was all the album had
    /// - settled by the next read that lands (gone from the scan: it went).
    @ObservationIgnored private var unansweredDelete: (before: ScanAlbum, all: Bool)?
    /// AppNavigation's session when the sheet opened: once it moves on (a sign-out, another person), nothing after a
    /// write asks deadwax again or touches the pages.
    @ObservationIgnored private var session: Int?
    @ObservationIgnored private var lookups = 0
    @ObservationIgnored private var follows = 0
    @ObservationIgnored private var settles = 0
    /// Where the last apply left the folder: where it said it moved it (`known`), or - one that never answered - where
    /// its preview meant to; the next read finds the album there if the scan lists it (RetagFlow.whereAfter).
    @ObservationIgnored private var after: (path: String, known: Bool)?
    @ObservationIgnored private var opened = false

    /// `target` the folder or album to open - in queue mode, the session's current folder; `scan` the page's, then.
    init(request: AlbumEditRequest, target: AlbumEditRequest.Target? = nil, scan: LibraryScanModel? = nil,
         client: DeadwaxClient?, admin: Bool, online: Bool) {
        let target = target ?? request.target
        self.target = target
        self.scan = scan ?? LibraryScanModel()
        queue = request.queue
        self.client = client
        self.admin = admin
        self.online = online
        if case .folder = target { asked = true }
    }

    /// The app's navigation - and the person the sheet opened for, with it - and the Library's lists.
    func attach(_ navigation: AppNavigation, library: LibraryModel) {
        self.navigation = navigation
        self.library = library
        session = navigation.session
    }

    /// Still the person the sheet opened for (AppNavigation.reset moves the session on).
    private var samePerson: Bool {
        guard let navigation, let session else { return false }
        return navigation.session == session
    }

    // MARK: what the sheet reads

    /// The album page's album the editor was opened for, if it was.
    var subject: AlbumEdit.Subject? {
        if case .album(let subject) = target { return subject }
        return nil
    }

    /// The folders the album is (AlbumEdit.folders), once the bridge and the scan have answered.
    var folders: AlbumEdit.Folders? {
        guard asked, scan.loaded else { return nil }
        if let chosen { return AlbumEdit.folderOnly(chosen) }
        switch target {
        case .folder(let path): return AlbumEdit.folderOnly(path)
        case .album(let subject): return AlbumEdit.folders(bridge, scan.albums, subject)
        }
    }

    /// Several folders by name alone, none picked: the Folder menu is all the sheet shows.
    var choosing: Bool { album == nil && folders.map(AlbumEdit.needsChoice) == true }

    /// What the sheet says in place of the album (AlbumEdit.status) - nil while it has one, or folders to choose from.
    var status: AlbumEdit.Status? {
        let folders = self.folders
        let listed = folders.map { $0.paths.count == 1 && scan.answer?.album(at: $0.paths[0]) != nil } ?? false
        return AlbumEdit.status(AlbumEdit.StatusFacts(
            deleted: deletedPath,
            problem: scan.answer?.problem, error: scan.failure, albums: scan.albums.count, loaded: scan.loaded,
            asked: asked, folders: folders, holding: album != nil, listed: listed,
            release: bridge?.releaseMbid ?? subject?.musicBrainzId))
    }

    /// Typed work, or a write under way: the sheet isn't swiped away, and Close asks first.
    var holdsWork: Bool { retag?.unsaved == true || tags?.unsaved == true || writing || marking }

    /// An apply is under way - a release's, (slice 2) a tag edit's, (slice 3) a Get or (slice 4) a delete: Close is off.
    var applying: Bool { retag?.flow.applying == true || tagsApplying || getting || deleting }

    /// Delete permanently is under way: no other write starts.
    var deleting: Bool { deletion.deleting }

    /// A tag edit's Apply is under way: no other write starts.
    var tagsApplying: Bool { tags?.flow.applying == true }

    /// A Get is under way: no other write starts - nor another Get.
    var getting: Bool { runs.values.contains { $0.state == .working } }

    /// This folder's last run of `kind` - another folder's is never shown.
    func run(_ kind: GetResults.Kind) -> GetRun? {
        guard let run = runs[kind], run.path == album?.path else { return nil }
        return run
    }

    /// A Get may be pressed: in reach, an album held, no write or mark under way, and the folder read since the last
    /// write or gap (the Release's wait for it, RetagFlow.needsRead) - what it offers is what the folder holds now.
    var canGet: Bool {
        online && album != nil && !writing && !marking && !scan.reading && retag?.flow.needsRead != true
    }

    /// An apply or the cover alone is under way: the album held and its Release stay, whatever a read brings.
    var writing: Bool { applying || retag?.flow.savingCover == true }

    /// (slice 6) Queue mode's ‹, Skip and Next album may be pressed: in reach (a step notes the album left looked at,
    /// and opens the next from deadwax), and no write or mark under way - as Close is off while one runs. Typed work
    /// asks first, as Close does (the sheet's).
    var canStep: Bool { online && !writing && !marking }

    /// The read a write or a gap waits for couldn't be made - the Release's or Tags' (RetagFlow.readFailed) - in the
    /// phone's words (review, 16 Nov): what holds Delete and the Gets off, said with Look again wherever they are.
    /// Tags' own read of the files first, else the scan's failure.
    var readBlocking: String? {
        if tags?.flow.readFailed == true, let said = tags?.readFailure { return said }
        guard retag?.flow.readFailed == true || tags?.flow.readFailed == true else { return nil }
        return scan.failure ?? EditWords.readFailed
    }

    // MARK: opening, and looking again

    /// The sheet opened: the bridge and the scan, at once - once.
    func open() async {
        guard !opened else { return }
        opened = true
        guard online else { return }
        await lookUp()
    }

    /// Look again (and back in reach): the bridge and the scan asked afresh; the album held followed to the fresh scan
    /// - or let go, its folder gone, to be found again from what the scan says.
    func lookUp() async {
        // only a read that landed moves anything: the scan in hand from before says nothing of what a write did
        var read = LibraryScanModel.Read.dropped
        await withTaskGroup(of: LibraryScanModel.Read?.self) { group in
            group.addTask {
                await self.askBridge()
                return nil
            }
            group.addTask { await self.scan.read(client: self.client, admin: self.admin) }
            for await ended in group {
                if let ended { read = ended }
            }
        }
        switch read {
        case .landed:
            unansweredGet = nil
            // a delete that never answered: the scan says whether it went
            if let pending = unansweredDelete, let answer = scan.answer,
               let went = DeleteFlow.went(answer, path: pending.before.path) {
                unansweredDelete = nil
                deletion.settled(gone: went)
                if went {
                    if samePerson { gone(pending.before, all: pending.all) }
                    return
                }
                settle()
                await readDeletion()
                return
            }
            settle()
        case .failed:
            // the read a write or a gap waits for: the wait ends, said with Look again (the sheet draws scan.failure)
            retag?.couldNotRead()
            tags?.couldNotRead()
        case .dropped:
            break
        }
    }

    private func askBridge() async {
        guard case .album(let subject) = target else {
            asked = true
            return
        }
        lookups += 1
        let ticket = lookups
        guard let client else {
            asked = true
            return
        }
        do {
            let found = try await client.storeAlbum(navidromeID: subject.id)
            guard ticket == lookups else { return }
            bridge = AlbumEdit.Bridge(found)
        } catch {
            // the bridge not answering leaves the scan to find it, by the release Navidrome said
            guard ticket == lookups else { return }
        }
        asked = true
    }

    /// After a read: the album held followed to the scan (or let go, its folder gone), else taken once its folder is
    /// known and listed. Never while a write runs: its end reads the folder again and decides (the apply's answer, the
    /// follow) - an album let go mid-apply would bring Close back, and the apply's end would land on a dropped model.
    private func settle() {
        guard !writing, let answer = scan.answer else { return }
        if let held = album {
            let path: String
            if let after, after.known, answer.album(at: after.path) != nil {
                path = after.path
            } else {
                path = RetagFlow.whereAfter(answer, was: held.path, target: after?.path)
            }
            after = nil
            if let fresh = answer.album(at: path) {
                follow(fresh, from: held.path)
                return
            }
            // the folder is gone from the scan: let go, found again below from what the scan says
            album = nil
            retag = nil
            tags = nil
        }
        guard let folders, let first = folders.paths.first, !AlbumEdit.needsChoice(folders),
              let found = answer.album(at: first) else { return }
        hold(found)
    }

    /// The album, followed to where the scan now lists it - a chosen folder with it.
    private func follow(_ fresh: ScanAlbum, from oldPath: String) {
        album = fresh
        if fresh.path != oldPath, chosen == oldPath { chosen = fresh.path }
        retag?.albumRead(fresh)
        tags?.albumRead(fresh)
    }

    private func hold(_ found: ScanAlbum) {
        album = found
        let release = RetagModel(album: found, online: online, admin: admin, client: client)
        retag = release
        release.start()
        // its files are read the first time Tags opens
        tags = TagsModel(album: found, online: online, admin: admin, client: client)
    }

    /// A folder picked - from the Folder menu (another of the album's folders) or from Choose the folder (any of the
    /// library's, the album's folder from now on).
    func choose(_ path: String, fromScan: Bool) {
        guard !writing, let found = scan.answer?.album(at: path) else { return }
        if fromScan { chosen = path }
        guard album?.path != path else { return }
        hold(found)
    }

    // MARK: in and out of reach

    func reach(_ now: Bool) async {
        guard now != online else { return }
        online = now
        guard now else {
            retag?.wentAway()
            tags?.wentAway()
            return
        }
        retag?.cameBack()
        tags?.cameBack()
        // everything asked again before a write comes back on - or, never asked, asked now
        opened = true
        await lookUp()
    }

    /// The app back in front with the folder still to be read (an apply ended while the phone was locked).
    func becameActive() async {
        guard online, retag?.flow.needsRead == true || tags?.flow.needsRead == true, !scan.reading else { return }
        await lookUp()
    }

    // MARK: Apply

    /// Apply (MetadataEditor's `apply`, EditPanel's `releaseApplied`): the preview's very body sent, the server working
    /// the plan out again; held with a background task while iOS allows; then the folder read again and the album
    /// followed - and, the release changed, its new id looked for. Signed out meanwhile, nothing more: the next person's
    /// pages are none of this apply's business.
    func apply() async {
        guard !tagsApplying, !getting, !deleting, let retag, let client, let before = album,
              let body = retag.beginApply() else { return }
        let preview = retag.plan
        let hold = BackgroundHold(named: "Edit album: Apply")
        defer { hold.end() }
        let result: Result<RetagResponse, any Error>
        do {
            result = .success(try await client.retagApply(body))
        } catch {
            result = .failure(error)
        }
        let outcome = retag.applyEnded(result)
        // Tags' preview describes the files as they were: it waits for the read too
        if outcome != .refused { tags?.folderChanged() }
        guard samePerson else { return }
        switch (outcome, result) {
        case (.refused, _):
            break
        case (.applied, .success(let response)):
            // where the apply itself said it left the folder - its own plan's target, worked out again, not the
            // preview's; one that moved it without saying where: the preview's, if the scan lists it
            if let path = response.pathAfter(before.path) {
                after = (path, true)
            } else {
                after = preview?.targetPath.map { ($0, false) }
            }
        default:
            // never answered, or a 5xx: where the scan lists it next - moved, or still where it was
            after = preview?.targetPath.map { ($0, false) }
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
        }
        // a refusal wrote nothing: read only when a gap meanwhile asked for it
        guard retag.flow.needsRead else { return }
        await lookUp()
        if outcome != .refused { wrote(before: before) }
    }

    /// The cover alone (RetagModel.saveCoverOnly): written - or maybe written, no answer or a 5xx, said as an apply's -
    /// the folder read again and the page beneath asked again; refused, nothing more.
    func saveCoverOnly() async {
        guard !tagsApplying, !getting, !deleting, let retag, let before = album,
              let outcome = await retag.saveCoverOnly(path: before.path) else { return }
        guard samePerson else { return }
        if outcome == .unanswered {
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
        }
        guard retag.flow.needsRead else { return }
        await lookUp()
        if outcome != .refused { wrote(before: before) }
    }

    /// Tags' Apply (TrackTagEditor's `apply`): the preview's very body sent, the plan worked out again on the server;
    /// held with a background task while iOS allows; then the folder read again (its files with it) and the album page
    /// beneath asked again. One that never answered, or answered a 5xx, is said as maybe finished and read again - never
    /// the same Apply on the old preview. Never while the Release is writing; signed out meanwhile, nothing more.
    func applyTags() async {
        guard let tags, let client, let before = album, !(retag?.flow.applying == true),
              retag?.flow.savingCover != true, !getting, !deleting, !marking, let body = tags.beginApply() else { return }
        let hold = BackgroundHold(named: "Edit album: Edit tags")
        defer { hold.end() }
        let result: Result<TagEditResponse, any Error>
        do {
            result = .success(try await client.tagsApply(body, bytes: tags.editingFiles.reduce(0) { $0 + $1.size }))
        } catch {
            result = .failure(error)
        }
        let outcome = tags.applyEnded(result)
        // the Release's preview describes the files as they were: it waits for the read too
        if outcome != .refused { retag?.folderChanged() }
        guard samePerson else { return }
        switch outcome {
        case .unanswered:
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
        case .applied:
            if let said = tags.applied ?? tags.applyError {
                AccessibilityNotification.Announcement(said).post()
            }
        case .refused:
            break
        }
        // a refusal wrote nothing: read only when a gap meanwhile asked for it
        guard tags.flow.needsRead else { return }
        await lookUp()
        if outcome != .refused { wrote(before: before) }
    }

    // MARK: Get cover, Get CD art, Get lyrics

    /// One of the album's Gets (LibraryParts.tsx's buttons - none replacing anything), held with a background task while
    /// iOS allows. A 404 is a fact (nothing for this release: Look again) and a refusal wrote nothing, both said under
    /// the button and nothing read. An answer - or none, or a 5xx, said as maybe finished - may have changed the folder:
    /// the Release's and Tags' previews wait for its next read (folderChanged), the folder is read again, and the album
    /// page beneath asked again. Signed out meanwhile, nothing more.
    func get(_ kind: GetResults.Kind) async {
        guard canGet, let client, let before = album else { return }
        let path = before.path
        var run = GetRun(kind: kind, path: path)
        runs[kind] = run
        let hold = BackgroundHold(named: "Edit album: \(GetResults.label(kind, nil, trackCount: 0))")
        defer { hold.end() }
        do {
            switch kind {
            case .cover:
                _ = try await client.getCover(path: path)
                run.done()
            case .disc:
                _ = try await client.getDiscArt(before)
                run.done()
            case .lyrics:
                run.done(try await client.getLyrics(before))
            }
        } catch {
            // a refusal or a 404 wrote nothing; no answer, a 5xx - or the phone calling it off - may have
            run.failed(error, admin: admin)
        }
        runs[kind] = run
        // the other parts' previews describe the folder as it was: they wait for the read too
        if run.wrote {
            retag?.folderChanged()
            tags?.folderChanged()
        }
        guard samePerson else { return }
        if run.state == .unanswered {
            unansweredGet = kind
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
        } else if let said = run.said {
            AccessibilityNotification.Announcement(said).post()
        }
        guard run.wrote else { return }
        await lookUp()
        wrote(before: before)
    }

    // MARK: Delete album (slice 4)

    /// Delete permanently may be pressed: in reach, an album held, no write or mark under way, the folder read since the
    /// last write or gap, and this folder's summary in hand (DeleteAlbumDialog's `disabled={loading || deleting ||
    /// !summary}`).
    var canDelete: Bool {
        guard online, let album, !writing, !marking, !scan.reading, retag?.flow.needsRead != true,
              tags?.flow.needsRead != true else { return false }
        return deletion.canDelete(album.path)
    }

    /// What deleting the folder held takes (DeleteAlbumDialog's read as it opens, and Look again): read live, only the
    /// newest landing; a read the page called off (it left) says nothing, and a failed one leaves nothing to delete by.
    func readDeletion() async {
        guard let client, online, !deleting, let album else { return }
        let ticket = deletion.beginRead(album.path)
        do {
            let summary = try await client.deletionSummary(path: album.path)
            deletion.read(ticket, summary)
        } catch {
            if APIFailure.isCancellation(error) {
                deletion.readCancelled(ticket)
            } else {
                deletion.readFailed(ticket, said: EditWords.said(error, failed: DeleteWords.readFailed, admin: admin))
            }
        }
    }

    /// Delete permanently, confirmed (DeleteAlbumDialog's `remove`, EditPanel's `albumDeleted`): the folder and
    /// everything in it, held with a background task while iOS allows. Gone: `gone`. Refused (a 4xx): said under the
    /// button, nothing deleted. No answer, or a 5xx (the folder can go before deadwax's index is told): said as maybe
    /// finished, the other parts' previews waiting, the folder read again - gone from the scan, it went; still there, it
    /// didn't, said, and its summary read again. Signed out meanwhile, nothing more.
    ///
    /// `path` and `summary` are the folder and the summary the question was asked over (review, 16 Nov): the delete
    /// starts only while the page holds that folder and that summary is still the one in hand (DeleteFlow.beginDelete).
    func delete(path: String, summary: DeletionSummary) async {
        guard canDelete, let client, let before = album,
              deletion.beginDelete(path, over: summary, holding: before.path) else { return }
        // decided now, from the folders as they are - as the web's dialog is given it: once the folder is gone the
        // scan can't say what the album had
        let all = AlbumEdit.deletesAll(folders, tracks: before.trackCount, subject)
        let hold = BackgroundHold(named: "Edit album: \(DeleteWords.page)")
        defer { hold.end() }
        let outcome: RetagFlow.Outcome
        var said: String?
        do {
            _ = try await client.deleteAlbum(path: before.path)
            outcome = .applied
        } catch {
            outcome = RetagFlow.outcome(of: error)
            said = EditWords.writeFailure(error, failed: DeleteWords.failed, admin: admin)
        }
        deletion.deleteEnded(outcome, said: said)
        guard samePerson else { return }
        switch outcome {
        case .applied:
            gone(before, all: all)
        case .refused:
            if let said { AccessibilityNotification.Announcement(said).post() }
        case .unanswered:
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
            retag?.folderChanged()
            tags?.folderChanged()
            unansweredDelete = (before, all)
            await lookUp()
        }
    }

    /// The folder is gone (EditPanel's `albumDeleted`, App.tsx's 'deleted'): said, the sheet closes (`deleted`), the
    /// Library's lists asked again now and once Navidrome has scanned (AlbumEdit.settleMs) - and the album page beneath,
    /// with nothing of the album left in Navidrome (`all`), goes back while it is what shows; a folder of several, the
    /// page is asked again now and once Navidrome has scanned instead. A folder opened from Choose the folder has no page.
    ///
    /// (slice 6) In queue mode the sheet stays, saying "Deleted …" where the album was, and Needs a look's row says
    /// Deleted: the queue goes on from here (EditPanel's `albumDeleted` for a folder request, its Next album).
    private func gone(_ before: ScanAlbum, all: Bool) {
        AccessibilityNotification.Announcement(DeleteWords.deleted(before.path)).post()
        if queue != nil {
            deletedPath = before.path
            album = nil
            retag = nil
            tags = nil
        }
        deleted = true
        told(from: before.path, deleted: true)
        library?.albumDeleted()
        Task {
            try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))
            guard self.samePerson else { return }
            self.library?.albumDeleted()
        }
        guard let id = pageId else { return }
        if all {
            navigation?.leaveAlbum(id)
        } else {
            wrote(before: before)
        }
    }

    // MARK: Needs a look's marks

    /// It's fine as it is: exactly the issues shown marked fine (QueueRequest's note).
    func markFine() async {
        guard let album else { return }
        await mark(failed: EditWords.markFineFailed) { client in
            _ = try await client.markFine(path: album.path, issues: MetadataQueue.outstanding(album))
        }
    }

    /// Ask about it again: every mark on the folder taken away.
    func askAgain() async {
        guard let album else { return }
        await mark(failed: EditWords.askAgainFailed) { client in
            _ = try await client.askAgain(path: album.path)
        }
    }

    private func mark(failed: String, _ send: (DeadwaxClient) async throws -> Void) async {
        guard let client, online, !marking, !deleting, let from = album?.path else { return }
        marking = true
        markFailure = nil
        do {
            try await send(client)
            // an ignore changes no file - only the review row: the folder read again, so the list follows
            await lookUp()
            // (slice 6) Needs a look's row says Marked fine (or nothing, asked about again), and its count follows
            told(from: from)
        } catch {
            markFailure = EditWords.said(error, failed: failed, admin: admin)
        }
        marking = false
    }

    // MARK: after a write

    /// (slice 6) A write to the folder that was at `from` landed, or may have, and the folder has been read again: Needs
    /// a look's count asked again, and - in queue mode - its row told what became of the album (the album as this read
    /// has it, nil when it isn't listed; or deleted). The web's `toFolder`.
    private func told(from: String, deleted: Bool = false) {
        guard samePerson else { return }
        navigation?.managed()
        queue?.heard(NeedsLook.FolderChange(from: from, album: deleted ? nil : album, deleted: deleted))
    }

    /// The id the album page beneath has now (a move changes it).
    private var pageId: String? { subject?.id }

    /// After a write (EditPanel's `afterWrite`): the page beneath asked again now and once Navidrome has scanned
    /// (AlbumEdit.settleMs) and - when the album's release changed - its new id looked for until Navidrome has it.
    /// (slice 6) Needs a look's count asked again, and - in queue mode - the page told what became of the album.
    private func wrote(before: ScanAlbum) {
        guard samePerson else { return }
        told(from: before.path)
        guard let id = pageId else { return }
        navigation?.albumWritten(id)
        settles += 1
        let ticket = settles
        Task {
            try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))
            guard ticket == self.settles, self.samePerson, let now = self.pageId else { return }
            self.navigation?.albumWritten(now)
        }
        if let release = AlbumEdit.followRelease(before: before.releaseMbid, after: album?.releaseMbid) {
            lookForMove(from: id, release: release)
        }
    }

    /// The album's new id in Navidrome, looked for by its new release at AlbumEdit.followLooksMs - only a newer look,
    /// or a sign-out (the session moved on), calls it off. Found: the page beneath moved to it, said once.
    private func lookForMove(from id: String, release: String) {
        follows += 1
        let ticket = follows
        Task {
            for delay in AlbumEdit.followLooksMs {
                try? await Task.sleep(for: .milliseconds(delay))
                guard ticket == self.follows, self.samePerson, let client = self.client else { return }
                guard let found = try? await client.storeAlbum(releaseMbid: release) else { continue }
                guard ticket == self.follows, self.samePerson else { return }
                // the page's own id is no answer: Navidrome can still list the album at the folder the rename left
                guard let to = AlbumEdit.followsTo(pageId: id, found: found.navidromeId) else { continue }
                self.moved(from: id, to: to)
                return
            }
        }
    }

    private func moved(from id: String, to: String) {
        guard samePerson else { return }
        if case .album(let subject) = target {
            target = .album(AlbumEdit.Subject(id: to, name: subject.name, artist: subject.artist,
                                              songCount: subject.songCount, musicBrainzId: album?.releaseMbid))
        }
        navigation?.albumMoved(from: id, to: to)
        AccessibilityNotification.Announcement(EditWords.followed).post()
    }
}

/// A background task held while an apply waits for its answer (UIApplication's: the seconds iOS gives an app sent to
/// the background) - ended once, by the apply or by iOS running out of time.
@MainActor
final class BackgroundHold {
    private var task: UIBackgroundTaskIdentifier = .invalid

    init(named name: String) {
        task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
