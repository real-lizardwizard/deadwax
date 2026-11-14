import DeadwaxCore
import Foundation
import Observation

/// The Library's Shuffle's first page, asked ahead (Phase 4, slice 3b - phase4-library.md 2.7, 2.8; the web's
/// app/ShuffleSongs.tsx): Core's ShuffleAhead kept here, its asks made of deadwax as the person signed in
/// (`GET /navidrome/shuffle`), so the ••• Shuffle's tap and the pull's release play songs already in hand - nothing is
/// awaited in either. The rest of the order is brought in as it plays by the player's feed (PlayerModel, Core's
/// ShuffleFeedRun).
///
/// `shown` as the Library comes into view (LibraryView: the app opening on it, the tab picked, the app back in front, a
/// new person) asks when ShuffleAhead says to - no page yet, the last ask failed, or it was made more than 10 minutes
/// ago. `take` is the tap's: the page, and the next order asked at once, naming the one played. A failure is said in
/// the web's words (ShuffleWords.unready: the 413's own). A new person lets every ask go (`reset`); an answer for an
/// ask no longer the newest is dropped by ShuffleAhead itself.
@MainActor
@Observable
final class ShuffleModel {
    /// What ShuffleAhead holds: whether a tap would play, why it can't.
    private(set) var ahead = ShuffleAhead()

    private let server: ServerModel

    init(server: ServerModel) {
        self.server = server
    }

    /// A tap would play a page in hand.
    var ready: Bool { ahead.ready }
    /// The scope has no songs at all.
    var empty: Bool { ahead.empty }
    /// Why the last ask failed, in the web's words.
    var failure: String? { ahead.failure }

    /// The Library came into view, its scope `scope`: the first page asked, when ShuffleAhead says to.
    func shown(_ scope: AlbumScope) {
        guard let ask = ahead.shown(Self.paged(scope), now: Self.now()) else { return }
        send(ask)
    }

    /// The tap (the •••'s Shuffle, the pull's release): the page in hand, every song at `level`, as a library's shuffle -
    /// and the next tap's order asked now. Nil when there is none: the tap does nothing.
    func take(level: Level?) -> ShuffleAhead.Taken? {
        guard let taken = ahead.take(level: level, now: Self.now()) else { return nil }
        send(taken.next)
        return taken
    }

    /// A new person: nothing asked before lands.
    func reset() {
        ahead.reset()
    }

    private func send(_ ask: ShuffleAhead.Ask) {
        guard let client = server.client else {
            ahead.failed(ask, words: ShuffleWords.unready)
            return
        }
        // an unstructured task: the Library left before the answer doesn't call off the one ask the tap will play
        Task { [weak self] in
            do {
                let answer = try await client.shuffleStart(scope: ask.scope, playing: ask.playing)
                self?.ahead.answered(ask, answer)
            } catch {
                let failure = error as? APIFailure
                self?.ahead.failed(ask, words: ShuffleWords.unready(status: failure?.status, detail: failure?.answer?.detail))
            }
        }
    }

    /// The Library's scope as a shuffle's.
    static func paged(_ scope: AlbumScope) -> PagedScope {
        scope == .yours ? .yours : .store
    }

    /// Seconds, by the wall clock: "more than 10 minutes since the last ask" is the songs added meanwhile (the route's
    /// SHUFFLE_LIST_TTL_S), which go on being added while the phone sleeps.
    private static func now() -> Double { Date().timeIntervalSince1970 }
}
