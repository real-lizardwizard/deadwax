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
/// after the person changed is thrown as `Superseded`, and nothing of it kept or said. Add to a playlist's writes - an
/// add, its New playlist… - go one at a time across every opening of the picker (`writes`, Core's PlaylistWrites): a
/// tap while one is out sends nothing, whichever sheet it is in.
@MainActor
@Observable
final class PlaylistsModel {
    /// A write's answer came after the person changed (a sign-out, another person) - or it wasn't sent, another of the
    /// picker's being out: nothing of it is kept, drawn or said.
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
    /// The writes out: the picker's one at a time (its rows wait while `writes.busy`; "Adding…" on `adding(id)`), and
    /// who each was asked as.
    private(set) var writes = PlaylistWrites()

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
        writes.reset()
    }

    // MARK: the writes (slice 2)

    /// A new playlist of the person's, with `songIDs` (none from the Playlists screen), named `name` as typed - sent
    /// trimmed as the web's form sends it. Answered whole: kept as the new playlist's page. The picker's (`picker`) waits
    /// for the picker's write out, and holds the others back while it is out.
    func create(name: String, songIDs: [String], picker: Bool) async throws -> PlaylistWithSongs {
        let made = try await write(picker ? .create : nil) { (client: DeadwaxClient) -> PlaylistWithSongs in
            try await client.createPlaylist(name: name, songIDs: songIDs)
        }
        changed(made.playlist.id, now: made)
        return made
    }

    /// Songs added at a playlist's end - the picker's, one at a time. `.ask` with some there already writes nothing -
    /// not a change.
    func add(_ songIDs: [String], to id: String, duplicates: PlaylistDuplicates) async throws -> PlaylistAddAnswer {
        let answer = try await write(.add(playlist: id, mode: duplicates)) { (client: DeadwaxClient) -> PlaylistAddAnswer in
            try await client.addToPlaylist(id: id, songIDs: songIDs, duplicates: duplicates)
        }
        if answer.done { changed(id, now: nil) }
        return answer
    }

    /// Edit's Done: the playlist as deadwax answered it after the write, kept for its page.
    func edit(_ id: String, _ body: PlaylistEditBody) async throws -> PlaylistWithSongs {
        let saved = try await write(nil) { (client: DeadwaxClient) -> PlaylistWithSongs in
            try await client.editPlaylist(id: id, body: body)
        }
        changed(id, now: saved)
        return saved
    }

    /// A playlist deleted, for good: its kept answer let go.
    func delete(_ id: String) async throws {
        try await write(nil) { (client: DeadwaxClient) -> Void in try await client.deletePlaylist(id: id) }
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

    /// One write, as the person signed in now, in a task nothing calls off - `gate` the picker's, sent only while none
    /// of the picker's is out. Not sent, or answered for someone else: `Superseded`.
    private func write<Value: Sendable>(_ gate: PlaylistWrites.Write?,
                                        _ call: @escaping @Sendable (DeadwaxClient) async throws -> Value) async throws
        -> Value {
        guard let client = server.client, let ticket = writes.begin(gate, person: server.person) else {
            throw Superseded()
        }
        let task = Task { () -> Result<Value, any Error> in
            do {
                return .success(try await call(client))
            } catch {
                return .failure(error)
            }
        }
        let result = await task.value
        guard writes.end(ticket, person: server.person) else { throw Superseded() }
        return try result.get()
    }
}

/// One playlist page's state (phase4-library.md 2.2, 2.4; PlaylistPage.tsx): the answer - kept for it, or deadwax's - and
/// what became of the last ask. Asked as the page shows (again each time it shows after not showing: a NavigationStack
/// runs the page's task again on the way back), only the newest answer drawn. A refresh that fails keeps what is drawn
/// and says so; a 404 is gone, the kept answer let go; nothing drawn and the first ask failing: why, and Try again.
/// While deadwax can't be reached nothing is asked: the kept answer draws, its songs on this phone play.
///
/// EDIT (slice 2) - the person's own, editable, at most 2,000 songs - is Core's PlaylistEditFlow, which this drives: offered
/// only once this page's own ask has answered (`fresh`), never from a kept answer or one a write elsewhere has made old;
/// nothing asked while it is open, an answer landing meanwhile dropped; Done's refusals each leaving what the flow says
/// (a 409 drawn as it is now, a 404 gone, anything else Edit open with why and `tried` kept for the next Done), and a
/// Delete answered 404 gone as a deleted one is. Nothing is drawn as saved before deadwax says it is.
@MainActor
@Observable
final class PlaylistPageModel {
    let route: PlaylistRoute

    /// The playlist and its songs, as last answered; nil until then.
    private(set) var answer: PlaylistWithSongs?
    /// The last ask failed (not gone).
    private(set) var failure: (any Error)?
    /// deadwax can be reached (the page's Reachability, set as it draws).
    var online = true
    /// Edit, and what the page's asks and writes leave of it (Core's).
    private(set) var flow = PlaylistEditFlow()

    @ObservationIgnored private var asks = 0
    @ObservationIgnored private var key: String?

    init(route: PlaylistRoute) {
        self.route = route
    }

    /// What the hero shows: the answer's summary, else the row's that opened the page.
    var playlist: Playlist? { answer?.playlist ?? route.preview }
    /// deadwax says it is gone (a 404), or it was deleted here: the page draws the gone line alone.
    var gone: Bool { flow.gone }
    /// The songs drawn - none once gone.
    var songs: [Song] { gone ? [] : answer?.songs ?? [] }
    var name: String { playlist?.name ?? "" }
    var hidden: Int { gone ? 0 : answer?.hidden ?? 0 }

    /// Edit's changes as they are now - nil while closed (the form's fields write here).
    var edit: PlaylistEditState? {
        get { flow.now }
        set { flow.now = newValue }
    }
    var editing: Bool { flow.editing }
    var fresh: Bool { flow.fresh }
    var saving: Bool { flow.saving }
    var deleting: Bool { flow.deleting }
    var busy: Bool { flow.busy }
    var changed: Bool { flow.changed }
    var needsName: Bool { flow.needsName }
    var editFailure: (any Error)? { flow.failure }
    var deleteFailure: (any Error)? { flow.deleteFailure }
    var note: String? { flow.note }
    /// One more for each Done refused with Edit left open: the page scrolls to why.
    var refusals: Int { flow.refusals }

    /// The playlist can be edited here: the person's own, editable, at most 2,000 songs (PlaylistRules.canEdit).
    var editable: Bool {
        guard let answer, !gone else { return false }
        return PlaylistRules.canEdit(answer.playlist, songs: answer.songs.count)
    }
    /// Edit may begin now: editable, this page's own answer drawn, deadwax in reach.
    var canBegin: Bool { flow.canBegin(editable: editable, online: online) }

    /// The page's task: the kept answer drawn at once, then deadwax asked (while it can be reached). `key` is who and
    /// which playlist: another drops what is in hand first. Nothing is asked while Edit is open.
    func load(key: String, client: DeadwaxClient?, playlists: PlaylistsModel) async {
        if key != self.key {
            self.key = key
            answer = nil
            failure = nil
            flow.reset()
        }
        if answer == nil, let kept = playlists.kept(route.id) { answer = kept }
        guard let client, online, !flow.editing else { return }
        asks += 1
        let asked = asks
        // who asked: a sign-out meanwhile (PlaylistsModel.reset) drops the answer, kept and drawn alike
        let generation = playlists.generation
        do {
            let found = try await client.playlist(id: route.id)
            // an answer landing while Edit is open is dropped (the web's): Done's base is the songs Edit began from
            guard asked == asks, !flow.editing, playlists.keep(found, asked: generation) else { return }
            answer = found
            failure = nil
            flow.answered()
        } catch {
            guard asked == asks, generation == playlists.generation, !APIFailure.isCancellation(error) else { return }
            if ErrorWords.kind(of: error) == .notFound {
                playlists.forget(route.id)
                flow.notFound()
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
        if !change.answered { flow.madeOld() }
        await load(key: key, client: client, playlists: playlists)
    }

    // MARK: Edit

    /// Edit begins from the songs as drawn now.
    func beginEdit() {
        guard let answer else { return }
        flow.begin(songs: answer.songs, playlist: answer.playlist, editable: editable, online: online)
    }

    /// Edit closed, nothing sent. After a Done that failed, what is drawn may be old: asked again (`true`).
    @discardableResult
    func leaveEdit() -> Bool {
        flow.leave()
    }

    /// The row at `from` moved to `to`.
    func move(from: Int, to: Int) {
        flow.move(from: from, to: to)
    }

    /// The row at `index` taken out.
    func remove(at index: Int) {
        flow.remove(at: index)
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

    /// Done: the one body Edit's changes make (with `tried`), sent as the person signed in. Drawn only from deadwax's
    /// answer.
    func done(playlists: PlaylistsModel) async -> Done {
        let body: PlaylistEditBody
        switch flow.done() {
        case .notSent: return .notSent
        case .unchanged: return .unchanged
        case .send(let sent): body = sent
        }
        do {
            let saved = try await playlists.edit(route.id, body)
            answer = saved
            failure = nil
            flow.saved()
            return .saved
        } catch is PlaylistsModel.Superseded {
            flow.notSent()
            return .notSent
        } catch {
            switch flow.refused(error) {
            case .changedElsewhere:
                return .changedElsewhere
            case .gone:
                playlists.gone(route.id)
                return .gone
            case .refused:
                return .refused
            }
        }
    }

    /// What became of Delete.
    enum Deleted {
        /// Deleted: gone from Navidrome, for good.
        case deleted
        /// deadwax said it was gone already (a 404): gone all the same.
        case gone
        /// Refused: why, under the button, Edit open.
        case refused
        /// Not open, or out already, or the person changed: nothing sent.
        case notSent
    }

    /// Delete: the playlist gone from Navidrome for good, as the person signed in.
    func delete(playlists: PlaylistsModel) async -> Deleted {
        guard flow.beginDelete() else { return .notSent }
        do {
            try await playlists.delete(route.id)
            flow.deleted()
            return .deleted
        } catch is PlaylistsModel.Superseded {
            flow.deleteNotSent()
            return .notSent
        } catch {
            guard flow.deleteRefused(error) else { return .refused }
            playlists.gone(route.id)
            return .gone
        }
    }

    /// The note said over the songs (PLAYLIST_CHANGED) put away - Edit begun again, or the page left.
    func clearNote() { flow.clearNote() }
}
