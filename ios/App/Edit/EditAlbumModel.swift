import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// What Edit album is opened for (notes/ios-specs/phase8-managing.md 1): an album page's album, by Navidrome's id and
/// what the page knew of it - its folders found from the id bridge, else the scan - or one folder of the library,
/// picked in Choose the folder. One opening each: a second Edit album is a new one.
struct AlbumEditRequest: Identifiable, Equatable {
    enum Target: Equatable {
        case album(AlbumEdit.Subject)
        case folder(String)
    }

    let id = UUID()
    let target: Target
}

/// Edit album's state (phase8-managing.md 3.1, 3.2, 3.7; the web's app/EditPanel.tsx): which folder the album is - the
/// bridge's and the scan's answers through AlbumEdit.folders, or the folder picked - the album held once it is known,
/// its Release (RetagModel), what Needs a look says of it and the two marks, and everything after a write: the folder
/// read again, the album page beneath asked again now and once Navidrome has scanned, and - when the release changed -
/// the album's new id in Navidrome looked for, the page beneath moved to it. Every rule is Core's; this asks and keeps.
///
/// It needs deadwax: opened out of reach it asks nothing (the sheet says so); gone out of reach, what is drawn stays and
/// every write is off; back, everything is asked again before a write comes back on. Nothing is kept on disk.
///
/// An apply can hold its answer for minutes, and deadwax carries on when the phone goes: it is held with a background
/// task for the seconds iOS gives, and one whose answer never came is said as maybe finished, the folder read again
/// (RetagFlow.whereAfter: where the scan now lists it) - never the same Apply on the old preview. What comes after a
/// write outlives the sheet (it ends within about 45 s): an album page left open beneath still follows the album.
@MainActor
@Observable
final class EditAlbumModel {
    private(set) var target: AlbumEditRequest.Target
    let scan = LibraryScanModel()
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
    /// deadwax in reach (Reachability).
    private(set) var online: Bool
    /// It's fine as it is / Ask about it again on its way, and what went wrong.
    private(set) var marking = false
    private(set) var markFailure: String?
    /// The cover drawn in the header and Compare covers - its mtime, so a cover replaced is asked again.
    var coverKey: String { album.map { "\($0.path)|\($0.artMtime)" } ?? "" }

    @ObservationIgnored var client: DeadwaxClient?
    @ObservationIgnored let admin: Bool
    @ObservationIgnored weak var navigation: AppNavigation?
    @ObservationIgnored private var lookups = 0
    @ObservationIgnored private var follows = 0
    @ObservationIgnored private var settles = 0
    /// Where the last apply left the folder: where it said it moved it (`known`), or - one that never answered - where
    /// its preview meant to; the next read finds the album there if the scan lists it (RetagFlow.whereAfter).
    @ObservationIgnored private var after: (path: String, known: Bool)?
    @ObservationIgnored private var opened = false

    init(request: AlbumEditRequest, client: DeadwaxClient?, admin: Bool, online: Bool) {
        target = request.target
        self.client = client
        self.admin = admin
        self.online = online
        if case .folder = request.target { asked = true }
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
            problem: scan.answer?.problem, error: scan.failure, albums: scan.albums.count, loaded: scan.loaded,
            asked: asked, folders: folders, holding: album != nil, listed: listed,
            release: bridge?.releaseMbid ?? subject?.musicBrainzId))
    }

    /// Typed work, or a write under way: the sheet isn't swiped away, and Close asks first.
    var holdsWork: Bool { retag?.unsaved == true || retag?.flow.applying == true || marking }

    /// An apply is under way.
    var applying: Bool { retag?.flow.applying == true }

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
        var landed = false
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.askBridge()
                return false
            }
            group.addTask { await self.scan.read(client: self.client, admin: self.admin) }
            for await read in group where read { landed = true }
        }
        if landed { settle() }
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
    /// known and listed.
    private func settle() {
        guard let answer = scan.answer else { return }
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
    }

    private func hold(_ found: ScanAlbum) {
        album = found
        let release = RetagModel(album: found, online: online, admin: admin, client: client)
        retag = release
        release.start()
    }

    /// A folder picked - from the Folder menu (another of the album's folders) or from Choose the folder (any of the
    /// library's, the album's folder from now on).
    func choose(_ path: String, fromScan: Bool) {
        guard let found = scan.answer?.album(at: path) else { return }
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
            return
        }
        retag?.cameBack()
        // everything asked again before a write comes back on - or, never asked, asked now
        opened = true
        await lookUp()
    }

    /// The app back in front with the folder still to be read (an apply ended while the phone was locked).
    func becameActive() async {
        guard online, retag?.flow.needsRead == true, !scan.reading else { return }
        await lookUp()
    }

    // MARK: Apply

    /// Apply (MetadataEditor's `apply`, EditPanel's `releaseApplied`): the preview's very body sent, the server working
    /// the plan out again; held with a background task while iOS allows; then the folder read again and the album
    /// followed - and, the release changed, its new id looked for.
    func apply() async {
        guard let retag, let client, let before = album, let body = retag.beginApply() else { return }
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
        switch (outcome, result) {
        case (.refused, _):
            return
        case (.applied, .success(let response)):
            after = (response.pathAfter(before.path, preview: preview), true)
        default:
            // never answered: where the scan lists it next - moved, or still where it was
            after = preview?.targetPath.map { ($0, false) }
            AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()
        }
        await lookUp()
        wrote(before: before)
    }

    /// The cover alone, written - the folder read again, the page beneath asked again.
    func saveCoverOnly() async {
        guard let retag, let before = album else { return }
        guard await retag.saveCoverOnly(path: before.path) else { return }
        await lookUp()
        wrote(before: before)
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
        guard let client, online, !marking else { return }
        marking = true
        markFailure = nil
        do {
            try await send(client)
            // an ignore changes no file - only the review row: the folder read again, so the list follows
            await lookUp()
        } catch {
            markFailure = EditWords.said(error, failed: failed, admin: admin)
        }
        marking = false
    }

    // MARK: after a write

    /// The id the album page beneath has now (a move changes it).
    private var pageId: String? { subject?.id }

    /// After a write (EditPanel's `afterWrite`): the page beneath asked again now and once Navidrome has scanned
    /// (AlbumEdit.settleMs) and - when the album's release changed - its new id looked for until Navidrome has it.
    private func wrote(before: ScanAlbum) {
        guard let id = pageId else { return }
        navigation?.albumWritten(id)
        settles += 1
        let ticket = settles
        Task {
            try? await Task.sleep(for: .milliseconds(AlbumEdit.settleMs))
            guard ticket == self.settles, let now = self.pageId else { return }
            self.navigation?.albumWritten(now)
        }
        if let release = AlbumEdit.followRelease(before: before.releaseMbid, after: album?.releaseMbid) {
            lookForMove(from: id, release: release)
        }
    }

    /// The album's new id in Navidrome, looked for by its new release at AlbumEdit.followLooksMs - only a newer look
    /// calls it off. Found: the page beneath moved to it, said once.
    private func lookForMove(from id: String, release: String) {
        follows += 1
        let ticket = follows
        Task {
            for delay in AlbumEdit.followLooksMs {
                try? await Task.sleep(for: .milliseconds(delay))
                guard ticket == self.follows, let client = self.client else { return }
                guard let found = try? await client.storeAlbum(releaseMbid: release) else { continue }
                guard ticket == self.follows else { return }
                // the page's own id is no answer: Navidrome can still list the album at the folder the rename left
                guard let to = AlbumEdit.followsTo(pageId: id, found: found.navidromeId) else { continue }
                self.moved(from: id, to: to)
                return
            }
        }
    }

    private func moved(from id: String, to: String) {
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
