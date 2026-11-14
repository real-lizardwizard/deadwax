import DeadwaxCore
import Foundation
import Observation

/// A MusicBrainz artist's page's answers (Phase 5, slice 3 - question 9; the web's ArtistPage.tsx for an artist known
/// by MusicBrainz, its `browse` and its facts): who they are (`/search_musicbrainz/artist`, the line under the name) and
/// their albums (`/search_musicbrainz/discography`, `types=album`, the studio ones alone with Studio only - on unless
/// turned off, for each artist), asked as the page opens. The session keeps each answer for `MBArtistPage.kept` artists,
/// so Back to the page draws it at once and asks nothing; a re-browse (Studio only toggled, Try again) keeps the last
/// answer on screen until the new one lands - and a failure keeps it only when it answered the same question. A list
/// MusicBrainz broke off part way (`problem`) is its trouble, never their albums. While deadwax can't be reached nothing
/// is asked; the page asks once it is back.
///
/// A row (`MBArtistPage.Row`) held with releases the library holds asks the id bridge for Navidrome's album (the row
/// busy), else - or Navidrome not having it - opens the album you don't have; its answer opens only on the page it was
/// tapped on (`standDown()` lets it go).
@MainActor
@Observable
final class MBArtistModel {
    /// Why their albums aren't drawn: MusicBrainz away or a list broken off (`MBArtistPage.away`), or another failure
    /// (its words, through ErrorWords).
    enum Trouble {
        case unavailable
        case failed(any Error)
    }

    /// One answer of their albums, as the session keeps it.
    struct Albums: Equatable {
        let groups: [ReleaseGroup]
        let truncated: Bool
    }

    let route: MBArtistRoute

    /// Who they are - nil until it comes, and left nil when it fails (the line under the name left out).
    private(set) var facts: MBArtistFacts?
    /// Their albums as drawn, and the question they answer (`"mbid|studio"`).
    private(set) var albums: Albums?
    private(set) var albumsKey: String?
    /// Their albums are being asked.
    private(set) var asking = false
    private(set) var trouble: Trouble?
    /// Studio only - on unless turned off on this artist's page.
    private(set) var studioOnly: Bool
    /// The row asking the id bridge (its key) - nil when none is.
    private(set) var opening: String?

    /// The session's: facts and albums by artist, and Studio only as each page left it - `MBArtistPage.kept` artists.
    private static var keptFacts: [String: MBArtistFacts] = [:]
    private static var keptAlbums: [String: Albums] = [:]
    private static var keptStudio: [String: Bool] = [:]
    private static var order: [String] = []

    @ObservationIgnored private var asks = 0
    @ObservationIgnored private var factsAsks = 0
    @ObservationIgnored private var bridging: Task<Void, Never>?

    init(route: MBArtistRoute) {
        self.route = route
        let mbid = route.mbid
        studioOnly = Self.keptStudio[mbid] ?? true
        facts = Self.keptFacts[mbid]
        let key = Self.key(mbid, studioOnly)
        if let held = Self.keptAlbums[key] {
            albums = held
            albumsKey = key
        }
    }

    static func key(_ mbid: String, _ studio: Bool) -> String { "\(mbid)|\(studio)" }

    /// The question their albums answer now.
    var key: String { Self.key(route.mbid, studioOnly) }

    /// Their albums for the question asked now - nil while they aren't in hand.
    var shown: Albums? { albumsKey == key ? albums : nil }

    /// The page's task, deadwax back: who they are, and their albums - the session's at once, else asked.
    func load(client: DeadwaxClient?, online: Bool) async {
        async let who: Void = loadFacts(client: client, online: online)
        async let theirs: Void = browse(client: client, online: online)
        _ = await (who, theirs)
    }

    /// Who they are: kept, else asked - a failure leaves the line out, quietly (About, where the web says so, is
    /// Phase 7's).
    private func loadFacts(client: DeadwaxClient?, online: Bool) async {
        let mbid = route.mbid
        if let held = Self.keptFacts[mbid] {
            facts = held
            return
        }
        guard MBID.isOne(mbid), online, let client else { return }
        factsAsks += 1
        let asked = factsAsks
        guard let found = try? await client.artistFacts(mbid: mbid), asked == factsAsks else { return }
        Self.keep(mbid) { Self.keptFacts[mbid] = found }
        facts = found
    }

    /// Their albums (the web's `browse`): the session's when it has them (unless `again`, Try again), else asked.
    func browse(client: DeadwaxClient?, online: Bool, again: Bool = false) async {
        let mbid = route.mbid
        let key = self.key
        let studio = studioOnly
        if !again, let held = Self.keptAlbums[key] {
            asks += 1
            albums = held
            albumsKey = key
            asking = false
            trouble = nil
            return
        }
        guard MBID.isOne(mbid) else {
            // no MusicBrainz id to ask by: nothing of theirs to list
            albums = Albums(groups: [], truncated: false)
            albumsKey = key
            return
        }
        guard online, let client else { return }
        asks += 1
        let asked = asks
        asking = true
        trouble = nil
        do {
            let found = try await client.discography(mbid: mbid, studioOnly: studio)
            guard asked == asks else { return }
            asking = false
            if found.brokenOff {
                failed(key, .unavailable)
                return
            }
            let answer = Albums(groups: found.releaseGroups, truncated: found.truncated)
            Self.keep(mbid) { Self.keptAlbums[key] = answer }
            albums = answer
            albumsKey = key
        } catch {
            guard asked == asks, !APIFailure.isCancellation(error) else { return }
            asking = false
            // MusicBrainz away (the route's 503) is said as the page says it; anything else in a listener's words
            failed(key, (error as? APIFailure)?.status == 503 ? .unavailable : .failed(error))
        }
    }

    /// A failure keeps what was on screen only when it answered this same question.
    private func failed(_ key: String, _ why: Trouble) {
        if albumsKey != key {
            albums = nil
            albumsKey = nil
        }
        trouble = why
    }

    /// Studio only turned on or off: kept for this artist, and their albums asked again (the last answer drawn
    /// meanwhile).
    func toggleStudio(client: DeadwaxClient?, online: Bool) {
        studioOnly.toggle()
        let mbid = route.mbid
        let studio = studioOnly
        Self.keep(mbid) { Self.keptStudio[mbid] = studio }
        Task { await browse(client: client, online: online) }
    }

    /// The session keeps `mbid`'s answer as the newest - the oldest artist let go past `MBArtistPage.kept`.
    private static func keep(_ mbid: String, _ change: () -> Void) {
        change()
        order.removeAll { $0 == mbid }
        order.append(mbid)
        while order.count > MBArtistPage.kept {
            let gone = order.removeFirst()
            keptFacts[gone] = nil
            keptStudio[gone] = nil
            for studio in [true, false] { keptAlbums[key(gone, studio)] = nil }
        }
    }

    // MARK: a row's tap

    /// A row (`openRow`): held, with releases the library holds, Navidrome's album for one of them from the id bridge
    /// (the row busy) - else, or Navidrome not having it or not answering, the album you don't have. The answer opens
    /// only on the page it was tapped on: the same tab, its pages as they were, Now Playing not over it.
    func open(_ row: MBArtistPage.Row, client: DeadwaxClient?, online: Bool, navigation: AppNavigation) {
        bridging?.cancel()
        guard MBArtistPage.asksBridge(row), online, let client else {
            opening = nil
            navigation.open(.group(GroupRoute(row.group)))
            return
        }
        opening = row.key
        let tab = navigation.tab
        let pages = navigation.shownStack
        let name = route.name
        bridging = Task { [weak self] in
            let found = try? await client.navidromeAlbum(releases: row.releases)
            guard !Task.isCancelled, let self, self.opening == row.key else { return }
            self.opening = nil
            guard navigation.tab == tab, navigation.shownStack == pages, !navigation.nowPlayingShown else { return }
            if let id = found {
                navigation.open(.album(AlbumRoute(id: id, name: row.title, artist: name.isEmpty ? nil : name)))
            } else {
                navigation.open(.group(GroupRoute(row.group)))
            }
        }
    }

    /// The page stopped showing (another tab, a page pushed over it, Now Playing): a row's ask let go.
    func standDown() {
        bridging?.cancel()
        bridging = nil
        opening = nil
    }
}
