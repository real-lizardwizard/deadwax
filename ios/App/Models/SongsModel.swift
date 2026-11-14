import DeadwaxCore
import Foundation
import Observation

/// Every song of the collection, a page at a time (Phase 4, slice 5 - phase4-library.md 2.7, 6.5; the web's
/// LibraryViews.tsx SongsView over app/usePaged.ts): Core's SongsPaging kept here, its pages asked of deadwax as the
/// person signed in (`GET /navidrome/search?q=&songCount=100&songOffset=` - search3 with an empty query, which Navidrome
/// answers with everything, in its own order). One list per person, drawn by the Library's Songs page (without a
/// library of your own) or All music's All songs (with one) - never both for one person, so they share it.
///
/// - `show` as Songs shows: the list for what Find holds, asked from its first page when it isn't the list in hand -
///   another query (question 33: Find on Songs asks Navidrome's own search), nothing in hand yet, or what is in hand
///   failed with nothing drawn. The list in hand stays as it is otherwise, its place in it kept: asking page 1 again
///   each time Songs shows would cut a long list back to 100 songs under the reader.
/// - `appeared` as a row appears: how far the reader got kept (Core's SongsReach, outside what is observed, so a row
///   appearing redraws nothing), and - while deadwax can be reached - the next page when the row is near the end of
///   what is drawn (one at a time, none after a failure - Try again asks that one, `retry`).
/// - `resumed` when deadwax is back: the next page, when the reader got near the end while it couldn't be reached -
///   those rows asked nothing as they appeared, and won't appear again until scrolled away and back.
/// - `refresh` (the •••'s Refresh, a pushed list's pull): the first page asked again, the list drawn kept until it lands
///   in its place (SongsPaging's `stale`) - its ask handed back, for a pull to wait on.
///
/// Only the newest ask's answer counts (SongsPaging, latestOnly); a list let go has its ask cancelled. `reset()` - a new
/// person - drops everything, and nothing asked before it lands after it.
@MainActor
@Observable
final class SongsModel {
    /// The list: what is drawn, and where its paging stands.
    private(set) var paging = SongsPaging()
    /// Why the last ask failed - read while `paging.failing`.
    private(set) var failure: (any Error)?
    /// One more each time a first page lands in place of what was drawn: the screen goes back to its top.
    private(set) var landed = 0

    private let server: ServerModel

    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    /// How far down the list drawn the reader got.
    @ObservationIgnored private var reach = SongsReach()
    /// The ask on its way, cancelled when another list takes its place.
    @ObservationIgnored private var asking: Task<Void, Never>?

    init(server: ServerModel) {
        self.server = server
    }

    /// Songs shows, Find holding `typed`: the list for it, when it isn't the one in hand.
    func show(_ typed: String) {
        let query = SongsList.query(typed)
        if paging.query == query, !(paging.items.isEmpty && paging.failing) { return }
        asking?.cancel()
        send(paging.start(query))
    }

    /// The •••'s Refresh, a pushed list's pull: the first page of the list asked again now - the ask handed back, so a
    /// pull's spinner lasts until it lands (nil when there is no deadwax to ask).
    @discardableResult
    func refresh(_ typed: String) -> Task<Void, Never>? {
        asking?.cancel()
        return send(paging.start(SongsList.query(typed)))
    }

    /// The row at `index` appeared: kept as how far the reader got, and - `online` - the next page, when it is near
    /// enough the end and one should be asked.
    func appeared(_ index: Int, online: Bool) {
        reach.appeared(index, in: paging)
        guard online, SongsList.asksMore(at: index, of: paging.items.count), let ask = paging.more() else { return }
        send(ask)
    }

    /// Deadwax is back: the next page, when the reader got near the end of the list while it couldn't be reached.
    func resumed() {
        guard reach.wantsMore(paging), let ask = paging.more() else { return }
        send(ask)
    }

    /// Try again: the page that wouldn't come.
    func retry() {
        guard let ask = paging.retry() else { return }
        send(ask)
    }

    /// A new person: everything let go.
    func reset() {
        epoch += 1
        asking?.cancel()
        asking = nil
        paging.reset()
        reach = SongsReach()
        failure = nil
        landed = 0
    }

    @discardableResult
    private func send(_ ask: SongsPaging.Ask) -> Task<Void, Never>? {
        guard let client = server.client else {
            failure = nil
            paging.failed(ask)
            return nil
        }
        let epoch = self.epoch
        let task = Task { [weak self] in
            do {
                let found = try await client.search(ask.query, songs: ask.count, songOffset: ask.offset)
                guard let self, epoch == self.epoch, self.paging.isNewest(ask) else { return }
                self.failure = nil
                self.paging.answered(ask, found.songs)
                if ask.offset == 0 { self.landed += 1 }
            } catch {
                guard let self, epoch == self.epoch, self.paging.isNewest(ask), !APIFailure.isCancellation(error) else { return }
                self.failure = error
                self.paging.failed(ask)
            }
        }
        asking = task
        return task
    }
}
