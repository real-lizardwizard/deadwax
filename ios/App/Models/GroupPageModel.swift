import DeadwaxCore
import Foundation
import Observation

/// The album you don't have's answers (Phase 5, slice 2 - phase5-search.md 3.6; the web's ReleaseGroupPage.tsx `load`):
/// every pressing of one MusicBrainz album with its tracklist (`/search_musicbrainz/release_group`), asked as the page
/// opens - or taken from the session's kept lists (Core's KeptPressings: twenty complete answers, so Back and an album
/// opened again ask nothing) - and the pressing chosen. Only the newest ask's answer lands; a list MusicBrainz broke
/// off part way (`problem`) is its trouble, never the album's pressings. While deadwax can't be reached nothing is
/// asked; the page asks once it is back.
///
/// (Slice 3) The kept lists are Search's evidence too - a pressing you hold whose kept tracklist has a song holds the
/// song (`keptReleases`, SongEvidence.pressings) - and a list Search fetched to open a song's album is kept here
/// (`keep`), so the page it opens asks nothing (the web's one pressingLists).
@MainActor
@Observable
final class GroupPageModel {
    /// What went wrong: MusicBrainz away or a list broken off (Pressings.trouble), another failure (its words, a 404
    /// "This album can't be found."), or an address that isn't an album's (no Try again).
    enum Trouble {
        case unavailable
        case failed(any Error)
        case notAnAlbum

        /// Whether Try again is drawn under it - an address that isn't an album's never will be one.
        var asksAgain: Bool {
            if case .notAnAlbum = self { return false }
            return true
        }
    }

    let route: GroupRoute

    /// The album's pressings, nil until they come.
    private(set) var answer: ReleaseGroupAnswer?
    private(set) var trouble: Trouble?
    /// The pressing chosen in the picker - nil: the page's default.
    var picked: String?

    /// The session's pressing lists, every page's.
    private static var kept = KeptPressings()

    /// Every album's pressings kept, by its id - Search's evidence of a song on a pressing you hold.
    static var keptReleases: [String: [PageRelease]] { kept.releases }

    /// Whether an album's pressings are kept (`kept(id)`).
    static func isKept(_ id: String) -> Bool { kept.kept(id) != nil }

    /// A complete list Search fetched, kept as the page's own (a list broken off is never kept).
    static func keep(_ id: String, _ answer: ReleaseGroupAnswer) {
        guard (answer.problem ?? "").isEmpty else { return }
        kept.keep(id, answer)
    }
    @ObservationIgnored private var asks = 0

    init(route: GroupRoute) {
        self.route = route
        if let held = Self.kept.kept(route.id) { answer = held }
    }

    /// The page's task, Try again, and deadwax back: the kept list drawn at once, else asked.
    func load(client: DeadwaxClient?, online: Bool) async {
        guard MBID.isOne(route.id) else {
            answer = nil
            trouble = .notAnAlbum
            return
        }
        if let held = Self.kept.kept(route.id) {
            answer = held
            trouble = nil
            return
        }
        guard online, let client else { return }
        asks += 1
        let asked = asks
        answer = nil
        trouble = nil
        do {
            let found = try await client.releaseGroup(mbid: route.id)
            guard asked == asks else { return }
            if !(found.problem ?? "").isEmpty {
                trouble = .unavailable
                return
            }
            Self.kept.keep(route.id, found)
            answer = found
        } catch {
            guard asked == asks, !APIFailure.isCancellation(error) else { return }
            // MusicBrainz away (the route's 503) is said as the page says it; anything else in a listener's words
            trouble = (error as? APIFailure)?.status == 503 ? .unavailable : .failed(error)
        }
    }

    /// Whether the page is still to be asked: nothing in hand and nothing wrong.
    var waiting: Bool { answer == nil && trouble == nil }
}
