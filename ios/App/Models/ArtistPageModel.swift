import DeadwaxCore
import Foundation
import Observation

/// One artist page's state (Phase 4, slice 4 - phase4-library.md 2.6; the web's ArtistPage.tsx, which question 4 built
/// without its MusicBrainz parts until its discography came on 15 Nov): the artist's answer (`GET /artists/{id}`: who
/// they are and the albums Navidrome has of theirs),
/// and each of those albums' songs, asked as the page opens so Play and Shuffle have them in hand at the tap (the gesture
/// rule) - Core's ArtistAlbumAsks: `ArtistPage.atOnce` at a time in the page's order, the newest round's answers only,
/// an album that won't come left out and said so under the buttons, Try again asking those again.
///
/// The answer kept for the artist (ArtistsModel, the last `ArtistPage.kept`) draws at once, and deadwax is asked behind
/// it; a failure keeps it drawn. Only the newest answer draws: each ask takes the next number. The albums' asks are
/// unstructured tasks, so a page covered by an album's page keeps asking; they land on the page only while it exists.
/// While deadwax can't be reached nothing is asked (the page draws what it has, and asks once deadwax is back).
///
/// And (15 Nov, the albums you don't have) their albums on MusicBrainz, once who they are there is known
/// (ArtistJoin.mbid): asked and kept by a MusicBrainz artist's page's own model, so the session's answers, Studio only and
/// a row's id bridge are that page's - `theirAlbums`.
@MainActor
@Observable
final class ArtistPageModel {
    let route: ArtistRoute

    /// The artist's answer, with their albums (no songs); nil until it comes, and when they are gone.
    private(set) var answer: ArtistWithAlbums?
    /// Their albums on MusicBrainz - nil while who they are there isn't known, and for an artist it doesn't know.
    private(set) var discography: MBArtistModel?
    /// The artist's load failed (a 404 among them: AlbumGone.isGone, said as ErrorWords.artistGone).
    private(set) var failure: (any Error)?
    /// Navidrome answered `{}`: the artist isn't there.
    private(set) var empty = false
    /// Their albums' songs, as they come (Core's rule).
    private(set) var asks = ArtistAlbumAsks<Album>()

    /// Who and which artist the answers in hand are for: another resets everything.
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var artistAsks = 0
    /// deadwax's own answer is in hand this page's life (not only the kept one).
    @ObservationIgnored private var fresh = false
    /// One more for each other who-and-which: an album's answer asked for before lands nowhere after.
    @ObservationIgnored private var generation = 0
    /// Who they are on MusicBrainz and the page's rows, as last made, with what they were made from (the web's useMemo
    /// over artistRows): the page is drawn again as each album's songs land and as the name scrolls into the bar, and the
    /// id's fallback reads every folder in the library. `owned` is SearchModel's `ownedVersion`.
    @ObservationIgnored private var mbidMade: (answer: ArtistWithAlbums?, owned: Int, mbid: String?)?
    @ObservationIgnored private var rowsMade: (albums: [Album], groups: [ReleaseGroup]?, owned: Int, rows: [ArtistJoin.Row])?

    init(route: ArtistRoute) {
        self.route = route
    }

    // MARK: what the page draws

    /// The name and picture: the answer's once it has come, else what opened the page.
    var name: String { answer?.name ?? route.preview?.name ?? "" }
    var coverArt: String? { answer.map(\.coverArt) ?? route.preview?.coverArt }
    /// The artist is gone - `{}` or a 404: the page draws what opened it and ErrorWords.artistGone alone.
    var gone: Bool { AlbumGone.isGone(empty: empty, failure: failure) }
    /// Who they are on MusicBrainz (ArtistJoin.mbid), for the answer in hand and `/library/owned` as of `version`.
    func mbid(index: OwnedIndex?, version: Int) -> String? {
        if let made = mbidMade, made.owned == version, made.answer == answer { return made.mbid }
        let found = ArtistJoin.mbid(answer, index: index)
        mbidMade = (answer, version, found)
        return found
    }

    /// The page's rows (ArtistJoin.rows): your albums, and MusicBrainz's `groups` among them once drawn.
    func rows(albums: [Album], groups: [ReleaseGroup]?, index: OwnedIndex?, version: Int) -> [ArtistJoin.Row] {
        if let made = rowsMade, made.owned == version, made.groups == groups, made.albums == albums { return made.rows }
        let rows = ArtistJoin.rows(albums: albums, groups: groups, index: index)
        rowsMade = (albums, groups, version, rows)
        return rows
    }

    /// What Navidrome has said of their albums, for the line under the buttons (playsLine's `library`).
    var library: ArtistPage.Library {
        if answer != nil { return .done }
        return failure != nil || empty ? .failed : .asking
    }

    // MARK: asking

    /// The page's task: the kept answer drawn at once and its albums' songs asked, the artist asked of deadwax (once a
    /// page's life - again after a failure, and on a pull: `again`), and the songs of any other albums its answer names.
    /// `key` is who and which artist.
    func load(key: String, client: DeadwaxClient?, online: Bool, artists: ArtistsModel, again: Bool = false) async {
        if key != self.key {
            self.key = key
            answer = nil
            failure = nil
            empty = false
            generation += 1
            asks = ArtistAlbumAsks<Album>()
            fresh = false
            discography?.standDown()
            discography = nil
        }
        if answer == nil, let kept = artists.keptArtist(route.id) { answer = kept }
        guard online, let client else { return }
        // the albums in hand (a kept answer, or the page opened offline from one and deadwax back) asked at once, as the
        // web's are from its kept rows - not only once deadwax's answer comes, up to its 8 s, with the line saying none
        // of theirs are here meanwhile. The asks are keyed on the albums, so the answer naming the same asks no more.
        if answer != nil { askAlbums(client) }
        if again { fresh = false }
        if !fresh {
            artistAsks += 1
            let asked = artistAsks
            do {
                let found = try await client.artist(id: route.id)
                guard asked == artistAsks else { return }
                failure = nil
                if let found {
                    answer = found
                    empty = false
                    fresh = true
                    artists.keep(found)
                } else {
                    answer = nil
                    empty = true
                    artists.forget(route.id)
                }
            } catch {
                guard asked == artistAsks, !APIFailure.isCancellation(error) else { return }
                let gone = AlbumGone.isGone(empty: false, failure: error)
                // a kept answer stays drawn through a failure - not through the artist being gone
                if answer == nil || gone {
                    if gone { artists.forget(route.id) }
                    answer = nil
                    failure = error
                }
            }
        }
        askAlbums(client)
    }

    /// Their albums' songs asked for - those not in hand, when the albums are other than before.
    private func askAlbums(_ client: DeadwaxClient) {
        let order = ArtistPage.playOrder(ArtistPage.rows(answer?.album ?? []))
        send(asks.want(order), client: client)
    }

    /// Their albums on MusicBrainz, for who they are there now (`mbid`, ArtistJoin.mbid - nil lets them go): the session's
    /// at once when it has them, else asked once - never while deadwax can't be reached, nor while an ask is out, and
    /// after a failure only with `retry` (Try again, a pull, deadwax back). The ask is an unstructured task, so it carries
    /// on while the page is covered, as the albums' songs do.
    func theirAlbums(mbid: String?, client: DeadwaxClient?, online: Bool, retry: Bool = false) {
        guard let mbid else {
            discography?.standDown()
            discography = nil
            return
        }
        if discography?.route.mbid != mbid {
            discography?.standDown()
            discography = MBArtistModel(route: MBArtistRoute(mbid: mbid, name: name))
        }
        guard online, let client, let discography, !discography.asking, discography.shown == nil else { return }
        let failed = discography.trouble != nil
        if failed && !retry { return }
        // past the session's answer only after a failure: a first ask (the page opened offline, deadwax back) takes it
        Task { await discography.browse(client: client, online: true, again: failed) }
    }

    /// (Phase 8, slice 5) Who they are on MusicBrainz - their name now - for the artist tools (Move albums to {name}…,
    /// and the folder Artist images writes to): asked through the MusicBrainz page's own model, so its kept answer is
    /// that page's, and only for someone who manages (ArtistView). Nil until known; a failure leaves it nil.
    var facts: MBArtistFacts? { discography?.facts }

    func theirFacts(client: DeadwaxClient?, online: Bool) async {
        await discography?.loadFacts(client: client, online: online)
    }

    /// Try again under the buttons: the albums that didn't come asked for again.
    func again(client: DeadwaxClient?) {
        guard let client else { return }
        send(asks.again(), client: client)
    }

    /// Each ask made, its answer (or failure) taken by the rule - which hands back the next to make.
    private func send(_ list: [ArtistAlbumAsks<Album>.Ask], client: DeadwaxClient) {
        let generation = self.generation
        for ask in list {
            Task { [weak self] in
                let found: Album?
                do {
                    found = try await client.album(id: ask.id)
                } catch {
                    found = nil
                }
                guard let self, generation == self.generation else { return }
                let next: [ArtistAlbumAsks<Album>.Ask]
                // an album Navidrome no longer has (`{}`, the client's nil) is one that didn't come - the web takes the
                // empty answer as in hand, and then says it plays an album it has nothing of
                if let found {
                    next = self.asks.answered(ask, with: found)
                } else {
                    next = self.asks.failed(ask)
                }
                self.send(next, client: client)
            }
        }
    }
}
