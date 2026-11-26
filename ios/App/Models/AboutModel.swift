import DeadwaxCore
import Foundation
import Observation

/// (Last.fm, slice A4 - deadwax-plans/lastfm.md 3.9; notes/ios.md "Last.fm, slice A4") One page's About: the artist
/// page's (ArtistPageModel.about) or the album page's (AlbumModel.about) - the web's app/useDescription.ts, by Core's
/// AboutBlock rules.
///
/// The page hands it its question as it stands (AboutBlock.artist or .album) whenever that, the page or whether deadwax
/// can be reached changes - its `.task(id:)` keyed on the page and the question (`taskKey|` the ids). What it draws
/// (`drawn(for:)`) is the answer to that question only: the session's, at once, or this page's own ask's - and while
/// the question changes, what it drew stays until the new answer replaces it (AboutBlock.Showing). Each ask takes the
/// next number, so only the newest lands.
///
/// The session's answers are every page's, one person's at a time (`session`): a description or none kept by what was
/// asked, an answer that isn't the whole story - or a failure - only `AboutBlock.unsureKeptMs`, and each page's last
/// question remembered, so Back (and a page opened again while its ids settle) draws at once. One question out to
/// deadwax at a time, shared by every page asking it and never called off: a page left before its answer came finds it
/// kept when it is back. Nothing is asked while deadwax can't be reached - an answer kept is drawn, else nothing - and
/// a failure draws nothing, with no words for it (the block is simply absent).
@MainActor
@Observable
final class AboutModel {
    /// What the page draws, for which page (AboutBlock.Showing).
    private(set) var showing = AboutBlock.Showing()
    /// The newest ask's number: an answer to any other draws nothing.
    @ObservationIgnored private var asks = 0
    /// The page's own ask's answer, by what it asked.
    @ObservationIgnored private var own: (key: String, found: AboutBlock.Drawn?)?

    /// The session's answers and the questions out - one person's: another's begins it again.
    private struct Session {
        var person: Int?
        var kept = AboutBlock.Kept()
        var out: [String: Task<AboutBlock.Drawn?, Never>] = [:]
    }

    private static var session = Session()

    /// The block's words for the page `page` - nil for none, or for another page.
    func drawn(for page: String) -> AboutBlock.Drawn? { showing.drawn(for: page) }

    /// The page's question now: what the session keeps for it drawn at once, and - online, with a question settled and
    /// nothing kept for it - asked of deadwax (the one question out for it, if there is one). Its answer lands only if
    /// this is still the newest ask.
    func ask(page: String, person: Int, question: AboutBlock.Question, client: DeadwaxClient?, online: Bool) {
        Self.belong(to: person)
        asks += 1
        let asked = asks
        let now = Self.now()
        showing.update(page: page, question: question, kept: &Self.session.kept, own: own, now: now)
        guard online, let client, let ask = AboutBlock.asks(question, kept: &Self.session.kept, now: now) else { return }
        let out = Self.session.out[ask.key] ?? Self.begin(ask, client: client, person: person)
        Task { [weak self] in
            let found = await out.value
            guard let self, asked == self.asks else { return }
            self.own = (ask.key, found)
            self.showing.update(page: page, question: question, kept: &Self.session.kept, own: self.own, now: Self.now())
        }
    }

    /// The session for `person`: another person's let go.
    private static func belong(to person: Int) {
        if session.person != person { session = Session(person: person) }
    }

    /// The one question out for `ask`: its answer - or none, for a failure - kept when it comes (for the person who
    /// asked: a session begun again since keeps nothing of it), whoever is still waiting.
    private static func begin(_ ask: AboutBlock.Ask, client: DeadwaxClient, person: Int) -> Task<AboutBlock.Drawn?, Never> {
        let key = ask.key
        let question = Task { @MainActor () -> AboutBlock.Drawn? in
            let found: AboutBlock.Drawn?
            let unsure: Bool
            do {
                let answer = try await client.describe(ask)
                found = AboutBlock.of(answer)
                unsure = answer.unavailable
            } catch {
                // no block, and no words for it: kept as none a moment, so Back draws at once and it is asked again soon
                found = nil
                unsure = true
            }
            if session.person == person {
                session.kept.keep(key, found, unsure: unsure, now: now())
                session.out[key] = nil
            }
            return found
        }
        session.out[key] = question
        return question
    }

    /// The session's clock, in ms: the engine's monotonic one, as ArtistsModel's Last.fm answers are timed.
    private static func now() -> Double { Monotonic.seconds() * 1000 }
}
