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
///
/// And (Last.fm, slice A1 - deadwax-plans/lastfm.md 3.1-3.3, notes/ios.md "Last.fm, slice A1") their Last.fm answer:
/// the session's kept one (ArtistsModel, beside their own) drawn at once, else asked once their own answer is in hand,
/// under the page and artist and who they are (`askLastfm`); what lies below Play waiting for it `LastfmPage.waitMs` at
/// most (`arrival`), Top Songs going where Core's LastfmPage.placeOf puts it; and its rows met with the albums' songs
/// (`topRows`). A top song you don't have opens its album through `opener`.
///
/// And (Last.fm, slice A2 - lastfm.md 3.3) the albums' Most played order: the albums by plays the visit orders by, judged
/// once as the albums are first drawn - the arrival's LastfmVisit, Core's, driven event by event (the session's answer
/// drawn at once, the ask that can't be made, a pull, an answer landing, the wait over, a choice) - and the list made
/// of them (`albumsShown`), with whether the menu offers Most played read the same way (`albumsOffered`). (A2's
/// review) Each answer is kept part by part over the one before (LastfmArtist.keeping): a later ask's part that
/// couldn't be had never takes away one drawn.
///
/// And (Last.fm, slice A4 - lastfm.md 3.9) About at the page's foot (`about`, AboutModel): asked once their answer is
/// in hand and who they are settled - MusicBrainz's facts in for an id (`factsFor`), as the web's page waits for them.
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

    /// (Last.fm, slice A1) Last.fm's answer for the artist - the session's kept one at once, then deadwax's; nil before
    /// either.
    private(set) var lastfm: LastfmArtist?
    /// What lies below Play waiting for it, where Top Songs went, and (A2) the albums the visit orders by - for one page
    /// and artist (`page`, the view's taskKey).
    private(set) var arrival: LastfmArrival?
    /// A top song you don't have, opening its album.
    let opener = TopSongOpener()
    /// Who the answer in hand (or a failure the session keeps) was asked about (LastfmPage.Ask.key): asked again only
    /// for someone else, or with `again`.
    @ObservationIgnored private var lastfmAsked: String?
    @ObservationIgnored private var lastfmAsks = 0
    /// The page and artist whose wait has begun (their own answer in hand).
    @ObservationIgnored private var waitBegun: String?
    /// Top Songs' rows as last made, with what they were made from (the page is drawn again as each album lands).
    @ObservationIgnored private var topMade: (top: [LastfmTrack], albums: [Album]?, unknown: Bool, rows: [TopSongs.Row])?
    /// Why Last.fm's answer didn't come, with nothing of it drawn - for the Top Songs page's own ask (TopSongsScreen).
    private(set) var lastfmFailure: (any Error)?
    /// The page and artist whose hero has drawn Last.fm's line (LastfmPage.drawsLine): its height kept for the page's
    /// life, so Play never moves (`LastfmPage.shown`'s `reserved` - the review of A1).
    @ObservationIgnored private var lineKeptFor: String?
    /// (A2) The Albums list as last made (the page is drawn again as each album's songs land).
    @ObservationIgnored private var playsMade = AlbumPlays.Made()

    /// (Last.fm, slice A4 - notes/ios.md "Last.fm, slice A4") About at the page's foot: its answers for the page.
    let about = AboutModel()
    /// Who MusicBrainz has said they are (their facts answered, or failed) - by the id asked: About waits for it, as
    /// deadwax's Wikipedia side makes the same lookup (AboutBlock.artist's `factsSettled`).
    private(set) var factsFor: String?

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

    /// Their albums: the answer's - or, while deadwax can't be reached, the answer in hand, else the albums on this phone
    /// naming them (ArtistOffline.albums).
    func albums(online: Bool, downloads: DownloadModel) -> [Album] {
        if online || answer != nil { return answer?.album ?? [] }
        let downloaded = downloads.downloadedAlbums.compactMap { (album: IndexAlbum) -> Album? in
            downloads.keptAlbum(album.id)
        }
        return ArtistOffline.albums(answer: nil, artistId: route.id, downloaded: downloaded)
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
        let mbid = discography?.route.mbid
        await discography?.loadFacts(client: client, online: online)
        // (A4) settled for who they are now - a task let go for another id settles nothing
        if !Task.isCancelled { factsFor = mbid }
    }

    /// (A4) Whether MusicBrainz has said who `mbid` is - answered or failed - on this page.
    func factsSettled(for mbid: String?) -> Bool { mbid != nil && factsFor == mbid }

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

    // MARK: Last.fm (slice A1)

    /// The arrival for the page and artist `page`: the model's once begun - else what it begins as, so the first frame
    /// draws as the begun page will (`kept`, the session's answer for the artist: with one there is no wait).
    func arrival(page: String, state: LastfmState, online: Bool, kept: LastfmPage.Kept.Entry?) -> LastfmPage.Arrival {
        if let arrival, arrival.page == page { return arrival.visit.arrival }
        return Self.firstArrival(state: state, online: online, kept: kept)
    }

    private static func firstArrival(state: LastfmState, online: Bool,
                                     kept: LastfmPage.Kept.Entry?) -> LastfmPage.Arrival {
        LastfmPage.Arrival(state: state, online: online, kept: kept.map { LastfmPage.present($0.held.answer) })
    }

    /// A page and artist begun (once): the session's answer drawn, the arrival as its first frame drew it.
    private func beginLastfm(page: String, state: LastfmState, online: Bool, artists: ArtistsModel) {
        guard arrival?.page != page else { return }
        let kept = artists.keptLastfm(route.id)
        // (A2) a visit begun: with nothing to wait for (the session's answer), the albums drawn now, by it
        let first = Self.firstArrival(state: state, online: online, kept: kept)
        arrival = LastfmArrival(page: page, visit: LastfmVisit(arrival: first, answer: kept?.held.answer))
        lastfm = kept?.held.answer
        lastfmAsked = kept?.asked
        lastfmAsks += 1
        lastfmFailure = nil
        waitBegun = nil
        topMade = nil
        opener.forget()
        playsMade = AlbumPlays.Made()
    }

    /// Whether the page has drawn the hero's Last.fm line (`keepLine`) - the hero keeps its height from then on.
    func lineKept(page: String) -> Bool { lineKeptFor == page }

    /// The hero's line drawn for the page as things are now (the same rule the page draws by): kept for its life.
    private func keepLine(page: String, state: LastfmState, online: Bool) {
        if LastfmPage.drawsLine(state: LastfmPage.state(me: state, answer: lastfm), online: online, answer: lastfm) {
            lineKeptFor = page
        }
    }

    /// Last.fm's answer for who they are now - `ask` nil while nothing says (their answer isn't in hand: `inHand`).
    /// Never while /me says Last.fm isn't on or deadwax can't be reached: the page waits no more. Asked again only for
    /// someone else, or with `again` (a pull) - the answer in hand drawn meanwhile. Their own answer in hand starts the
    /// wait. The ask is an unstructured task, as the albums' songs are: a page covered by another keeps asking, and only
    /// the newest answer for the page lands; one that fails keeps what is drawn (the session keeps the failure a minute
    /// only while nothing is).
    ///
    /// `retryFailed` (the Top Songs page's own): a failure the session keeps, with nothing drawn, is asked again at once
    /// rather than waited out - that page has nothing else to show.
    func askLastfm(page: String, ask: LastfmPage.Ask?, inHand: Bool, state: LastfmState, client: DeadwaxClient?,
                   online: Bool, artists: ArtistsModel, again: Bool = false, retryFailed: Bool = false) {
        beginLastfm(page: page, state: state, online: online, artists: artists)
        keepLine(page: page, state: state, online: online)
        guard state == .on, online, let client else {
            arrival?.visit.unasked(lastfm)
            return
        }
        if inHand { wait(page: page) }
        let pulled = again
        let again = again || (retryFailed && lastfm == nil)
        guard let ask, again || ask.key != lastfmAsked else { return }
        // (A2) a pull: the albums' order judged again by the answer it brings
        arrival?.visit.asking(pulled: pulled)
        lastfmAsks += 1
        let asked = lastfmAsks
        let id = route.id
        if again { lastfmFailure = nil }
        Task { [weak self] in
            let found: LastfmArtist?
            var failure: (any Error)?
            do {
                found = try await client.lastfmArtist(mbid: ask.mbid, name: ask.name)
            } catch {
                if APIFailure.isCancellation(error) { return }
                found = nil
                failure = error
            }
            guard let self, asked == self.lastfmAsks, self.arrival?.page == page else { return }
            if let found {
                // (A2's review) kept part by part over the one in hand: a part this ask couldn't have keeps the last
                let kept = found.keeping(self.lastfm)
                self.lastfm = kept
                self.lastfmAsked = ask.key
                self.lastfmFailure = nil
                artists.keepLastfm(id, kept, asked: ask.key)
            } else if self.lastfm == nil {
                self.lastfmFailure = failure
                artists.keepLastfm(id, nil, asked: ask.key)
            }
            self.keepLine(page: page, state: state, online: true)
            // placed, then (A2) the albums drawn now if they weren't: by this answer - once drawn, nothing moves them
            self.arrival?.visit.answered(self.lastfm)
        }
    }

    /// Their own answer in hand: what lies below Play waits `LastfmPage.waitMs` more at most.
    private func wait(page: String) {
        guard waitBegun != page, arrival?.visit.arrival.holding == true else { return }
        waitBegun = page
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(LastfmPage.waitMs) * 1_000_000)
            guard let self, self.arrival?.page == page else { return }
            // released, and (A2) the albums drawn by what is in hand - an answer after this leaves them newest first
            self.arrival?.visit.waited(self.lastfm)
        }
    }

    /// Top Songs' rows (TopSongs.rows): the answer's songs met with the page's albums' songs (`mine`, the page's rows of
    /// its albums) - once every album's songs have come or failed; while deadwax can't be reached, with what is in hand
    /// of them (the page's, or this phone's). Before then each row waits; an album of theirs whose songs aren't in hand
    /// (TopSongs.library) makes a song no album in hand has `.unknown`, never "Not in your library". Made once for what
    /// they are made from: the page is drawn again as each album lands.
    func topRows(_ mine: [ArtistPage.Row], online: Bool, downloads: DownloadModel) -> [TopSongs.Row] {
        let order = ArtistPage.playOrder(mine)
        let library = online && answer == nil ? nil
            : TopSongs.library(order: order, asks: asks, online: online) { (id: String) -> Album? in
                downloads.keptAlbum(id)
            }
        let top = lastfm?.topSongs ?? []
        let albums = library?.albums
        let unknown = library?.unknown ?? false
        if let made = topMade, made.top == top, made.albums == albums, made.unknown == unknown { return made.rows }
        let rows = TopSongs.rows(top, albums: albums, unknown: unknown)
        topMade = (top, albums, unknown, rows)
        return rows
    }

    // MARK: Last.fm (slice A2 - notes/ios.md "Last.fm, slice A2")

    /// The albums the visit to the page `page` orders by: the model's, once begun - else what it begins with (`kept`,
    /// the session's answer: with one the albums draw at once, by it).
    func visitAlbums(page: String, kept: LastfmPage.Kept.Entry?) -> [LastfmAlbum]? {
        if let arrival, arrival.page == page { return arrival.visit.albums.albums }
        return AlbumPlays.counted(kept?.held.answer)
    }

    /// (A2's review) Whether the menu offers Most played - read as the order drawn is (`visitAlbums`): the visit's,
    /// once begun (its albums, or the answer in hand's - AlbumPlays.Visit.offers), else the session's answer's. So the
    /// menu is never hidden while the rows are in Most played order.
    func albumsOffered(page: String, kept: LastfmPage.Kept.Entry?) -> Bool {
        if let arrival, arrival.page == page { return arrival.visit.albums.offers(lastfm) }
        return AlbumPlays.offered(kept?.held.answer)
    }

    /// The Albums list as drawn (AlbumPlays.shown): `chosen` the menu's order, the rows Studio only leaves - Most played
    /// only with albums the visit orders by.
    func albumsShown(_ rows: [ArtistJoin.Row], chosen: AlbumOrder, page: String, kept: LastfmPage.Kept.Entry?,
                     albums: [Album]) -> AlbumPlays.Shown {
        playsMade.shown(rows, chosen: chosen, visit: visitAlbums(page: page, kept: kept), albums: albums)
    }

    /// Most played chosen in the menu: the rows ordered by the answer in hand, at once - the person asked them to move.
    func choseMostPlayed() {
        arrival?.visit.chose(lastfm)
    }
}

/// An artist page's Last.fm arrival (LastfmPage.Arrival) and (A2) its albums' visit, for the page and artist it began
/// for.
struct LastfmArrival {
    let page: String
    /// (A2's review) The arrival and the albums' order judged with it, as Core drives them (LastfmVisit).
    var visit: LastfmVisit
}
