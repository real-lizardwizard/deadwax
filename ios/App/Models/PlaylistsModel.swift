import DeadwaxCore
import Foundation
import Observation

/// The person's playlists (Phase 4, phase4-library.md 2.1-2.2; the web's app/usePlaylists.ts): the one list, shared by
/// every screen and kept in memory for the app's run, and the last playlist pages' answers (PlaylistRules.kept, 8), so a
/// page drawn again - back to it from an album, or opened again from the list - draws at once while it is asked again.
/// Navidrome's own playlists, asked as the person signed in (deadwax's routes, the session's own cookie); a new person
/// drops everything (`reset`, ServerModel.whenPersonChanges).
///
/// The list is asked with `fresh` as the Playlists screen shows (each time it shows again), else not while an answer
/// under PlaylistRules.freshSeconds old is in hand. Only the newest answer is kept; an answer for a person no longer
/// signed in is dropped. A failure with a list in hand keeps the list (`failure` says why, under the title); with none,
/// the screen says why with Try again. Asked in an unstructured task: a screen left before its answer doesn't call off
/// the one request every screen shares.
///
/// Slice 2: the four writes (`create`, `add`, `edit`, `delete`), each asked of deadwax as the person signed in, in an
/// unstructured task - a sheet or page closed while one is out never calls it off (a write is never called off, as the
/// web's never are). Nothing is changed before deadwax answers. Each that was written is told (`changed`, the web's
/// announcePlaylistChanged): the playlist's kept answer replaced by the one the write gave, or let go when it gave
/// none, the list asked again, and `lastChange` moved on - a page of that playlist asks for it again. One answered
/// after the person changed is thrown as `Superseded`, and nothing of it kept or said.
@MainActor
@Observable
final class PlaylistsModel {
    /// A write's answer came after the person changed (a sign-out, another person): nothing of it is kept, drawn or said.
    struct Superseded: Error {}

    /// A write here changed a playlist: which, and whether its answer came with it (a page drawn from it may offer Edit;
    /// one changed without - an add, a delete - is asked again before it does).
    struct Change: Equatable {
        let serial: Int
        let id: String
        let answered: Bool
    }

    /// The last playlist a write here changed - each page of it watches this.
    private(set) var lastChange: Change?
    /// Navidrome's answer, in its order (by name) - nil until the first comes.
    private(set) var list: [Playlist]?
    /// The last ask failed: the list in hand (if any) is the one before it.
    private(set) var failure: (any Error)?

    private let server: ServerModel
    /// When the list in hand was answered.
    @ObservationIgnored private var answeredAt: Date?
    /// Each ask takes the next number; only the newest one's answer is kept.
    @ObservationIgnored private var asks = 0
    /// Moves on with every `reset` (a new person): an answer asked for under an older one is neither kept nor drawn -
    /// a page's load, run from a task nothing cancels at a sign-out, never keeps one person's playlist under the next.
    @ObservationIgnored private(set) var generation = 0
    /// The pages' answers, by playlist id - oldest first in `keptOrder`.
    @ObservationIgnored private var keptPages: [String: PlaylistWithSongs] = [:]
    @ObservationIgnored private var keptOrder: [String] = []

    init(server: ServerModel) {
        self.server = server
    }

    /// The list asked of deadwax - with `fresh`, whatever is in hand; else only when nothing younger than
    /// PlaylistRules.freshSeconds is. Returns once it has answered (a pull to refresh waits for it).
    func ask(fresh: Bool) async {
        if !fresh, list != nil, let answeredAt, Date().timeIntervalSince(answeredAt) < PlaylistRules.freshSeconds { return }
        guard let client = server.client else { return }
        asks += 1
        let asked = asks
        let person = server.person
        let under = generation
        let task = Task { () -> Result<[Playlist], any Error> in
            do {
                return .success(try await client.playlists())
            } catch {
                return .failure(error)
            }
        }
        let result = await task.value
        guard asked == asks, under == generation, person == server.person else { return }
        switch result {
        case .success(let playlists):
            list = playlists
            failure = nil
            answeredAt = Date()
        case .failure(let error):
            if APIFailure.isCancellation(error) { return }
            failure = error
        }
    }

    /// The page's answer kept for `id`, if any (drawn at once as the page opens).
    func kept(_ id: String) -> PlaylistWithSongs? { keptPages[id] }

    /// A page's answer kept, the newest last, the oldest let go past PlaylistRules.kept (the web's keepPlaylist). The
    /// list isn't changed by it: a row says what the list's own last answer said. `asked`: the generation the answer was
    /// asked under - an older one's is dropped (false).
    @discardableResult
    func keep(_ answer: PlaylistWithSongs, asked: Int) -> Bool {
        guard asked == generation else { return false }
        let id = answer.playlist.id
        keptPages[id] = answer
        keptOrder.removeAll { $0 == id }
        keptOrder.append(id)
        while keptOrder.count > PlaylistRules.kept {
            keptPages.removeValue(forKey: keptOrder.removeFirst())
        }
        return true
    }

    /// A playlist gone (its page's 404): its kept answer let go, and the list asked again when it next shows.
    func forget(_ id: String) {
        keptPages.removeValue(forKey: id)
        keptOrder.removeAll { $0 == id }
        answeredAt = nil
    }

    /// Whether a playlist opens while deadwax can't be reached: its page's answer is in hand with a song of it on this
    /// phone (the list's row is dimmed otherwise, as an album with nothing here is).
    func playsOffline(_ id: String, here: (String) -> Bool) -> Bool {
        keptPages[id]?.songs.contains { here($0.id) } == true
    }

    /// The person changed: nothing of the last one's kept, and an answer still out for them dropped.
    func reset() {
        asks += 1
        generation += 1
        list = nil
        failure = nil
        answeredAt = nil
        keptPages = [:]
        keptOrder = []
        lastChange = nil
    }

    // MARK: the writes (slice 2)

    /// A new playlist of the person's, with `songIDs` (none from the Playlists screen), named `name` as typed - sent
    /// trimmed as the web's form sends it. Answered whole: kept as the new playlist's page.
    func create(name: String, songIDs: [String]) async throws -> PlaylistWithSongs {
        let made = try await write { (client: DeadwaxClient) -> PlaylistWithSongs in
            try await client.createPlaylist(name: name, songIDs: songIDs)
        }
        changed(made.playlist.id, now: made)
        return made
    }

    /// Songs added at a playlist's end. `.ask` with some there already writes nothing - not a change.
    func add(_ songIDs: [String], to id: String, duplicates: PlaylistDuplicates) async throws -> PlaylistAddAnswer {
        let answer = try await write { (client: DeadwaxClient) -> PlaylistAddAnswer in
            try await client.addToPlaylist(id: id, songIDs: songIDs, duplicates: duplicates)
        }
        if answer.done { changed(id, now: nil) }
        return answer
    }

    /// Edit's Done: the playlist as deadwax answered it after the write, kept for its page.
    func edit(_ id: String, _ body: PlaylistEditBody) async throws -> PlaylistWithSongs {
        let saved = try await write { (client: DeadwaxClient) -> PlaylistWithSongs in
            try await client.editPlaylist(id: id, body: body)
        }
        changed(id, now: saved)
        return saved
    }

    /// A playlist deleted, for good: its kept answer let go.
    func delete(_ id: String) async throws {
        try await write { (client: DeadwaxClient) -> Void in try await client.deletePlaylist(id: id) }
        changed(id, now: nil)
    }

    /// A playlist answered gone by a write (a 404): its kept answer let go, the list asked again.
    func gone(_ id: String) {
        forget(id)
        Task { await ask(fresh: true) }
    }

    /// The web's announcePlaylistChanged: the kept answer replaced, or let go; the list asked again; the pages told.
    private func changed(_ id: String, now: PlaylistWithSongs?) {
        if let now {
            keep(now, asked: generation)
        } else {
            keptPages.removeValue(forKey: id)
            keptOrder.removeAll { $0 == id }
        }
        answeredAt = nil
        lastChange = Change(serial: (lastChange?.serial ?? 0) + 1, id: id, answered: now != nil)
        Task { await ask(fresh: true) }
    }

    /// One write, as the person signed in now, in a task nothing calls off: answered for someone else, `Superseded`.
    private func write<Value: Sendable>(_ call: @escaping @Sendable (DeadwaxClient) async throws -> Value) async throws
        -> Value {
        guard let client = server.client else { throw Superseded() }
        let person = server.person
        let under = generation
        let task = Task { () -> Result<Value, any Error> in
            do {
                return .success(try await call(client))
            } catch {
                return .failure(error)
            }
        }
        let result = await task.value
        guard under == generation, person == server.person else { throw Superseded() }
        return try result.get()
    }
}

/// One playlist page's state (phase4-library.md 2.2, 2.4; PlaylistPage.tsx): the answer - kept for it, or deadwax's - and
/// what became of the last ask. Asked as the page shows (again each time it shows after not showing: a NavigationStack
/// runs the page's task again on the way back), only the newest answer drawn. A refresh that fails keeps what is drawn
/// and says so; a 404 is gone, the kept answer let go; nothing drawn and the first ask failing: why, and Try again.
/// While deadwax can't be reached nothing is asked: the kept answer draws, its songs on this phone play.
///
/// EDIT (slice 2) - the person's own, editable, at most 2,000 songs - is offered only once this page's own ask has
/// answered (`fresh`), never from a kept answer or one a write elsewhere has made old. Nothing is asked while it is
/// open, and an answer landing meanwhile is dropped: Done's `base` is the songs as drawn when Edit began, and deadwax
/// refuses it (a 409) if the playlist changed in another app since. Done refused for any other reason leaves Edit open
/// with why, and the next Done sends `tried` - the songs the refused one sent, which Navidrome may have taken before
/// refusing - and leaving Edit after one asks the playlist again. Nothing is drawn as saved before deadwax says it is.
@MainActor
@Observable
final class PlaylistPageModel {
    let route: PlaylistRoute

    /// The playlist and its songs, as last answered; nil until then.
    private(set) var answer: PlaylistWithSongs?
    /// deadwax says it is gone (a 404): the page draws the gone line alone.
    private(set) var gone = false
    /// The last ask failed (not gone).
    private(set) var failure: (any Error)?
    /// deadwax can be reached (the page's Reachability, set as it draws).
    var online = true
    /// The answer drawn is this page's own ask's (or its own Done's): Edit may begin from it.
    private(set) var fresh = false

    /// Edit, open: what it began with and what it holds now - nil while closed.
    private(set) var start: PlaylistEditState?
    var edit: PlaylistEditState?
    /// Done is out.
    private(set) var saving = false
    /// Done was refused (not a 409 or a 404): why, while Edit stays open.
    private(set) var editFailure: (any Error)?
    /// Delete is out.
    private(set) var deleting = false
    /// Delete was refused: why, under its row.
    private(set) var deleteFailure: (any Error)?
    /// The playlist changed in another app while it was being edited (Done's 409): said over the songs as they are now.
    private(set) var note: String?

    @ObservationIgnored private var asks = 0
    @ObservationIgnored private var key: String?
    /// The songs the last Done that FAILED sent (the web's `tried`).
    @ObservationIgnored private var tried: [String]?

    init(route: PlaylistRoute) {
        self.route = route
    }

    /// What the hero shows: the answer's summary, else the row's that opened the page.
    var playlist: Playlist? { answer?.playlist ?? route.preview }
    /// The songs drawn - none once gone.
    var songs: [Song] { gone ? [] : answer?.songs ?? [] }
    var name: String { playlist?.name ?? "" }
    var hidden: Int { gone ? 0 : answer?.hidden ?? 0 }

    /// Edit is open.
    var editing: Bool { edit != nil }
    /// The playlist can be edited here: the person's own, editable, at most 2,000 songs (PlaylistRules.canEdit).
    var editable: Bool {
        guard let answer, !gone else { return false }
        return PlaylistRules.canEdit(answer.playlist, songs: answer.songs.count)
    }
    /// Edit may begin now: editable, this page's own answer drawn, deadwax in reach.
    var canBegin: Bool { editable && fresh && online && !editing }
    /// Edit holds changes Done would send.
    var changed: Bool {
        guard let start, let edit else { return false }
        return PlaylistEdit.changed(start: start, now: edit)
    }
    /// The name is blank: Done waits.
    var needsName: Bool { edit.map(PlaylistEdit.needsName) ?? false }
    /// A write is out.
    var busy: Bool { saving || deleting }

    /// The page's task: the kept answer drawn at once, then deadwax asked (while it can be reached). `key` is who and
    /// which playlist: another drops what is in hand first. Nothing is asked while Edit is open.
    func load(key: String, client: DeadwaxClient?, playlists: PlaylistsModel) async {
        if key != self.key {
            self.key = key
            answer = nil
            gone = false
            failure = nil
            fresh = false
            closeEdit()
            note = nil
        }
        if answer == nil, let kept = playlists.kept(route.id) { answer = kept }
        guard let client, online, !editing else { return }
        asks += 1
        let asked = asks
        // who asked: a sign-out meanwhile (PlaylistsModel.reset) drops the answer, kept and drawn alike
        let generation = playlists.generation
        do {
            let found = try await client.playlist(id: route.id)
            // an answer landing while Edit is open is dropped (the web's): Done's base is the songs Edit began from
            guard asked == asks, !editing, playlists.keep(found, asked: generation) else { return }
            answer = found
            gone = false
            failure = nil
            fresh = true
        } catch {
            guard asked == asks, generation == playlists.generation, !APIFailure.isCancellation(error) else { return }
            if ErrorWords.kind(of: error) == .notFound {
                playlists.forget(route.id)
                gone = true
                closeEdit()
                return
            }
            failure = error
        }
    }

    /// Try again, after a first ask that failed with nothing drawn.
    func retry(client: DeadwaxClient?, playlists: PlaylistsModel) async {
        guard let key else { return }
        failure = nil
        await load(key: key, client: client, playlists: playlists)
    }

    /// A write here changed this playlist (PlaylistsModel.lastChange): one without its answer - an add from the
    /// picker - makes what is drawn old, so Edit waits for the ask; either way the playlist is asked again.
    func changedHere(_ change: PlaylistsModel.Change, client: DeadwaxClient?, playlists: PlaylistsModel) async {
        // (deleted here - gone already - there is nothing to ask)
        guard change.id == route.id, !gone, let key else { return }
        if !change.answered { fresh = false }
        await load(key: key, client: client, playlists: playlists)
    }

    // MARK: Edit

    /// Edit begins from the songs as drawn now.
    func beginEdit() {
        guard canBegin, let answer else { return }
        let began = PlaylistEdit.start(songs: answer.songs, playlist: answer.playlist)
        start = began
        edit = began
        editFailure = nil
        deleteFailure = nil
        note = nil
    }

    /// Edit closed, nothing sent. After a Done that failed, what is drawn may be old: asked again (`true`).
    @discardableResult
    func leaveEdit() -> Bool {
        closeEdit()
        guard tried != nil else { return false }
        tried = nil
        fresh = false
        return true
    }

    private func closeEdit() {
        start = nil
        edit = nil
        editFailure = nil
        deleteFailure = nil
    }

    /// The row at `from` moved to `to`.
    func move(from: Int, to: Int) {
        guard var now = edit, !busy else { return }
        now.rows = PlaylistEdit.move(now.rows, from: from, to: to)
        edit = now
    }

    /// The row at `index` taken out.
    func remove(at index: Int) {
        guard var now = edit, !busy else { return }
        now.rows = PlaylistEdit.remove(now.rows, at: index)
        edit = now
    }

    /// What became of Done.
    enum Done {
        /// Nothing had changed: Edit closed.
        case unchanged
        /// Saved: drawn as deadwax answered it.
        case saved
        /// Changed in another app since Edit began: nothing saved, the playlist asked again - said at the page's top.
        case changedElsewhere
        /// Gone (a 404).
        case gone
        /// Refused: Edit stays open with why.
        case refused
        /// The name is blank, or Done is out already, or the person changed: nothing sent.
        case notSent
    }

    /// Done: the one body Edit's changes make, sent as the person signed in. Drawn only from deadwax's answer.
    func done(playlists: PlaylistsModel) async -> Done {
        guard let start, let edit, !busy else { return .notSent }
        guard let body = PlaylistEdit.body(start: start, now: edit) else {
            leaveEdit()
            return .unchanged
        }
        guard !PlaylistEdit.needsName(edit) else { return .notSent }
        saving = true
        editFailure = nil
        let sent = body.trying(tried)
        do {
            let saved = try await playlists.edit(route.id, sent)
            saving = false
            tried = nil
            answer = saved
            gone = false
            failure = nil
            fresh = true
            closeEdit()
            return .saved
        } catch is PlaylistsModel.Superseded {
            saving = false
            return .notSent
        } catch {
            saving = false
            switch PlaylistEdit.refusal(of: error) {
            case .changedElsewhere:
                tried = nil
                closeEdit()
                fresh = false
                note = PlaylistWords.playlistChanged
                return .changedElsewhere
            case .gone:
                tried = nil
                closeEdit()
                playlists.gone(route.id)
                gone = true
                return .gone
            case .refused:
                tried = body.songIds
                editFailure = error
                return .refused
            }
        }
    }

    /// Delete: the playlist gone from Navidrome for good, as the person signed in - true once deadwax says it is.
    func delete(playlists: PlaylistsModel) async -> Bool {
        guard editing, !busy else { return false }
        deleting = true
        deleteFailure = nil
        do {
            try await playlists.delete(route.id)
            deleting = false
            closeEdit()
            gone = true
            return true
        } catch is PlaylistsModel.Superseded {
            deleting = false
            return false
        } catch {
            deleting = false
            deleteFailure = error
            return false
        }
    }

    /// The note said over the songs (PLAYLIST_CHANGED) put away - Edit begun again, or the page left.
    func clearNote() { note = nil }
}
