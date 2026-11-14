import DeadwaxCore
import Foundation
import Observation

/// The Library's Shuffle's first page, asked ahead (Phase 4, slice 3b - phase4-library.md 2.7, 2.8; the web's
/// app/ShuffleSongs.tsx): Core's ShuffleAhead kept here, its asks made of deadwax as the person signed in
/// (`GET /navidrome/shuffle`), so the ••• Shuffle's tap and the pull's release play songs already in hand - nothing is
/// awaited in either. The rest of the order is brought in as it plays by the player's feed (PlayerModel, Core's
/// ShuffleFeedRun).
///
/// Since slice 5 there are two (Core's ShuffleAheads): the Library's (`.library` - your library with one of your own,
/// else the collection) and All songs' (`.allSongs` - the collection's, at the head of All music's All songs with a
/// library of your own), each asked ahead as its list shows, neither letting the other's page go.
///
/// `shown` as a list comes into view (LibraryView: the app opening on it, the tab picked, the app back in front, a new
/// person; SongsScreen: All songs shown) asks when ShuffleAhead says to - no page yet, the last ask failed, or it was
/// made more than 10 minutes ago. `take` is the tap's: the page, and the next order asked at once, naming the one
/// played. A failure is said in the web's words (ShuffleWords.unready: the 413's own). A new person lets every ask go
/// (`reset`); an answer for an ask no longer the newest is dropped by ShuffleAhead itself.
@MainActor
@Observable
final class ShuffleModel {
    /// What the two ShuffleAheads hold: whether a tap would play, why it can't.
    private(set) var aheads = ShuffleAheads()

    private let server: ServerModel

    init(server: ServerModel) {
        self.server = server
    }

    /// A tap of `which` would play a page in hand.
    func ready(_ which: ShuffleOf) -> Bool { aheads[which].ready }
    /// `which`'s scope has no songs at all.
    func empty(_ which: ShuffleOf) -> Bool { aheads[which].empty }
    /// Why `which`'s last ask failed, in the web's words.
    func failure(_ which: ShuffleOf) -> String? { aheads[which].failure }

    /// `which`'s list came into view, the Library's scope `scope`: its first page asked, when ShuffleAhead says to.
    func shown(_ which: ShuffleOf, _ scope: AlbumScope) {
        guard let ask = aheads.shown(which, library: scope, now: Self.now()) else { return }
        send(which, ask)
    }

    /// The tap (the •••'s Shuffle, the pull's release, All songs' Shuffle): `which`'s page in hand, every song at
    /// `level`, as a library's shuffle - and the next tap's order asked now. Nil when there is none: the tap does
    /// nothing.
    func take(_ which: ShuffleOf, level: Level?) -> ShuffleAhead.Taken? {
        guard let taken = aheads.take(which, level: level, now: Self.now()) else { return nil }
        send(which, taken.next)
        return taken
    }

    /// A new person: nothing asked before lands.
    func reset() {
        aheads.reset()
    }

    private func send(_ which: ShuffleOf, _ ask: ShuffleAhead.Ask) {
        guard let client = server.client else {
            aheads.failed(which, ask, words: ShuffleWords.unready)
            return
        }
        // an unstructured task: the list left before the answer doesn't call off the one ask the tap will play
        Task { [weak self] in
            do {
                let answer = try await client.shuffleStart(scope: ask.scope, playing: ask.playing)
                self?.aheads.answered(which, ask, answer)
            } catch {
                let failure = error as? APIFailure
                self?.aheads.failed(which, ask, words: ShuffleWords.unready(status: failure?.status,
                                                                             detail: failure?.answer?.detail))
            }
        }
    }

    /// Seconds, by the wall clock: "more than 10 minutes since the last ask" is the songs added meanwhile (the route's
    /// SHUFFLE_LIST_TTL_S), which go on being added while the phone sleeps.
    private static func now() -> Double { Date().timeIntervalSince1970 }
}
