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
@MainActor
@Observable
final class PlaylistsModel {
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
    }
}

/// One playlist page's state (phase4-library.md 2.2; PlaylistPage.tsx): the answer - kept for it, or deadwax's - and
/// what became of the last ask. Asked as the page shows (again each time it shows after not showing: a NavigationStack
/// runs the page's task again on the way back), only the newest answer drawn. A refresh that fails keeps what is drawn
/// and says so; a 404 is gone, the kept answer let go; nothing drawn and the first ask failing: why, and Try again.
/// While deadwax can't be reached nothing is asked: the kept answer draws, its songs on this phone play.
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

    @ObservationIgnored private var asks = 0
    @ObservationIgnored private var key: String?

    init(route: PlaylistRoute) {
        self.route = route
    }

    /// What the hero shows: the answer's summary, else the row's that opened the page.
    var playlist: Playlist? { answer?.playlist ?? route.preview }
    /// The songs drawn - none once gone.
    var songs: [Song] { gone ? [] : answer?.songs ?? [] }
    var name: String { playlist?.name ?? "" }
    var hidden: Int { gone ? 0 : answer?.hidden ?? 0 }

    /// The page's task: the kept answer drawn at once, then deadwax asked (while it can be reached). `key` is who and
    /// which playlist: another drops what is in hand first.
    func load(key: String, client: DeadwaxClient?, playlists: PlaylistsModel) async {
        if key != self.key {
            self.key = key
            answer = nil
            gone = false
            failure = nil
        }
        if answer == nil, let kept = playlists.kept(route.id) { answer = kept }
        guard let client, online else { return }
        asks += 1
        let asked = asks
        // who asked: a sign-out meanwhile (PlaylistsModel.reset) drops the answer, kept and drawn alike
        let generation = playlists.generation
        do {
            let found = try await client.playlist(id: route.id)
            guard asked == asks, playlists.keep(found, asked: generation) else { return }
            answer = found
            gone = false
            failure = nil
        } catch {
            guard asked == asks, generation == playlists.generation, !APIFailure.isCancellation(error) else { return }
            if ErrorWords.kind(of: error) == .notFound {
                playlists.forget(route.id)
                gone = true
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
}
