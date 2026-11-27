import DeadwaxCore
import Foundation
import Observation

/// One header's run of artists, as a screen draws it: its place among the groups (what the index jumps to), its words,
/// and its artists in order.
struct DrawnArtistGroup: Identifiable {
    let id: Int
    let label: String?
    let artists: [Artist]
}

/// Everything one Artists screen draws for an order and what is typed into Find (Core's ArtistShelf.view, its places
/// turned into artists) - made once per list, order and Find, never in a view's body.
struct DrawnArtists {
    /// every artist of the list, in Navidrome's order
    let artists: [Artist]
    let view: ShelfView
    let groups: [DrawnArtistGroup]
    /// The phone's own stand-in (ArtistOffline.artists): no list in hand while deadwax can't be reached.
    let standIn: Bool
}

/// The Library's artists (Phase 4, slice 4 - phase4-library.md 2.6; the web's LibrarySection.tsx ArtistSection), one per
/// person:
///
/// - Every artist Navidrome has (`GET /deadwax/navidrome/artists`), asked as an Artists screen shows - (Speed A, fix 4)
///   again only once the list in hand is over a minute old or a write was told of, the album index's rule (`askIfOld`);
///   a pull and the Library's Refresh ask at once (`ask`) - the newest answer only. A failure keeps the list in hand
///   (the screen says it couldn't be asked again); kept in memory only, so the app opening asks again.
/// - What each screen draws of it: the collection's list, Your artists (Core's YourArtists over your albums, counting
///   yours - with a library of your own), or, while deadwax can't be reached and no list is in hand, the artists of the
///   albums on this phone (ArtistOffline.artists). Each list's ArtistShelf made once, its order once per order, and
///   what Find keeps once per what is typed.
/// - The artist order, per device, under the web's own key (ArtistOrder.storageKey).
/// - The last `ArtistPage.kept` artists' answers (ARTISTS_KEPT): an artist page opened again draws at once, and while
///   deadwax can't be reached, from what was in hand.
/// - (Last.fm, slice A1) Their Last.fm answers beside them (LastfmPage.Kept), and the artist pages showing, for Top Songs.
/// - (Last.fm, slice A2) The albums' order on an artist's page, per device (AlbumOrder.storageKey), and the list as
///   Similar Artists meets it (SimilarArtists.Library, made once per list).
///
/// `reset()` - a new person - drops everything in memory, and nothing asked before it lands after it.
@MainActor
@Observable
final class ArtistsModel {
    /// Every artist, as Navidrome last listed them - nil before one answer has come.
    private(set) var list: [Artist]?
    /// The last ask failed (nil once one begins again, or it answers).
    private(set) var failure: (any Error)?
    /// One more each time a different list lands.
    private(set) var serial = 0
    /// The order, kept per device (the web's `deadwax-player-artist-order`, read with ArtistOrder(saved:)).
    var order: ArtistOrder = ArtistOrder(saved: UserDefaults.standard.string(forKey: ArtistOrder.storageKey)) {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: ArtistOrder.storageKey) }
    }

    private let server: ServerModel

    /// Only the newest answer counts (latestOnly).
    @ObservationIgnored private var asks = 0
    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    /// (Speed A, fix 4) The list in hand: when it landed (Monotonic ms), under how many writes and whether settled - nil
    /// before one has; the writes the screens last told of, and when they last moved; and the writes the ask on its way
    /// was asked under (nil for none).
    @ObservationIgnored private var landed: ListFreshness.Landed?
    @ObservationIgnored private var told = 0
    @ObservationIgnored private var toldMoved: Int64?
    @ObservationIgnored private var asking: Int?
    /// Each kind of list's shelf, the order made of it and what was last drawn - and what each was made from.
    @ObservationIgnored private var shelves: [Kind: (stamp: Stamp, shelf: ArtistShelf)] = [:]
    @ObservationIgnored private var sorted: [Kind: (stamp: Stamp, order: ArtistOrder, places: [Int])] = [:]
    @ObservationIgnored private var drawnCache: [Kind: (stamp: Stamp, order: ArtistOrder, typed: String, drawn: DrawnArtists)] = [:]
    /// The artists' answers kept, the most recently kept last.
    @ObservationIgnored private var kept: [String: ArtistWithAlbums] = [:]
    @ObservationIgnored private var keptOrder: [String] = []

    /// The lists a screen draws.
    private enum Kind: Hashable {
        case all, yours, here
    }

    /// What a list was made from: the collection's answer, your albums' answer, the albums on this phone.
    private struct Stamp: Equatable {
        let serial: Int
        let yours: Int
        let here: [IndexAlbum]
    }

    init(server: ServerModel) {
        self.server = server
    }

    // MARK: asking

    /// (Speed A, fix 4 - notes/ios.md "Speed A: what's asked again") As an Artists screen shows, or the app comes back
    /// to the front on one: the list asked again only when none is in hand or the one in hand is over a minute old, and
    /// nothing asked under the same writes is on its way - the album index's own rule (Core's ListFreshness,
    /// AlbumIndexState.freshMs). `writes`, every write deadwax was told of (KeptAlbumAnswers.stamp's), asks at once when
    /// it moved since the list in hand was asked, as the index's generation does - and at each show until a list asked
    /// AlbumEdit.settleMs after they moved has landed, Navidrome's scan of them being seconds behind; so does a last ask
    /// that failed. A pull, and the Library's Refresh, still ask at once (`ask`).
    func askIfOld(writes: Int) async {
        if writes != told {
            told = writes
            toldMoved = Int64(Self.now)
        }
        guard ListFreshness.asks(landed: landed, writes: writes, failed: failure != nil, onItsWay: asking,
                                 now: Int64(Self.now)) else { return }
        await ask()
    }

    /// `GET /artists`: the list asked again - drawn in place of the one in hand when it lands (when it differs); a
    /// failure keeps the one in hand and says why.
    func ask() async {
        guard let client = server.client else { return }
        asks += 1
        let asked = asks
        let epoch = self.epoch
        failure = nil
        let writes = told
        let settled = ListFreshness.settled(askedAt: Int64(Self.now), writesMovedAt: toldMoved)
        asking = writes
        defer { if asked == asks { asking = nil } }
        do {
            let artists = try await client.artists()
            guard asked == asks, epoch == self.epoch else { return }
            // (Speed A) the list in hand stands as of now, changed or not
            landed = ListFreshness.Landed(at: Int64(Self.now), writes: writes, settled: settled)
            if artists != list {
                list = artists
                serial += 1
            }
        } catch {
            guard asked == asks, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
            failure = error
        }
    }

    // MARK: what a screen draws

    /// The collection's list as drawn - nil before an answer.
    func drawnAll(typed: String) -> DrawnArtists? {
        guard let list else { return nil }
        let stamp = Stamp(serial: serial, yours: 0, here: [])
        return drawn(.all, stamp: stamp, typed: typed, standIn: false) { list }
    }

    /// Your artists as drawn (YourArtists: the collection's artists your albums name, counting yours) - nil before
    /// both answers are in hand.
    func drawnYours(_ albums: KeptShelf?, typed: String) -> DrawnArtists? {
        guard let list, let albums else { return nil }
        let stamp = Stamp(serial: serial, yours: albums.serial, here: [])
        return drawn(.yours, stamp: stamp, typed: typed, standIn: false) {
            YourArtists.of(list, albums: albums.shelf.albums)
        }
    }

    /// The artists of the albums on this phone - the stand-in while deadwax can't be reached and no list is in hand.
    func drawnHere(_ downloaded: [IndexAlbum], typed: String) -> DrawnArtists {
        let stamp = Stamp(serial: 0, yours: 0, here: downloaded)
        return drawn(.here, stamp: stamp, typed: typed, standIn: true) { ArtistOffline.artists(downloaded) }
    }

    private func drawn(_ kind: Kind, stamp: Stamp, typed: String, standIn: Bool,
                       artists: () -> [Artist]) -> DrawnArtists {
        let order = self.order
        if let cached = drawnCache[kind], cached.stamp == stamp, cached.order == order, cached.typed == typed {
            return cached.drawn
        }
        let shelf: ArtistShelf
        if let held = shelves[kind], held.stamp == stamp {
            shelf = held.shelf
        } else {
            shelf = ArtistShelf(artists())
            shelves[kind] = (stamp, shelf)
        }
        let places: [Int]
        if let held = sorted[kind], held.stamp == stamp, held.order == order {
            places = held.places
        } else {
            places = shelf.sorted(order)
            sorted[kind] = (stamp, order, places)
        }
        let view = shelf.view(order, typed: typed, sorted: places)
        let every = shelf.artists
        let groups = view.groups.enumerated().map { (at: Int, group: ShelfGroup) -> DrawnArtistGroup in
            DrawnArtistGroup(id: at, label: group.label, artists: group.items.map { (place: Int) -> Artist in every[place] })
        }
        let drawn = DrawnArtists(artists: every, view: view, groups: groups, standIn: standIn)
        drawnCache[kind] = (stamp, order, typed, drawn)
        return drawn
    }

    // MARK: the artists' answers

    /// The answer kept for an artist, if one is.
    func keptArtist(_ id: String) -> ArtistWithAlbums? { kept[id] }

    /// An artist page's answer kept - the oldest let go past `ArtistPage.kept`.
    func keep(_ answer: ArtistWithAlbums) {
        kept[answer.id] = answer
        keptOrder.removeAll { (id: String) -> Bool in id == answer.id }
        keptOrder.append(answer.id)
        while keptOrder.count > ArtistPage.kept {
            kept[keptOrder.removeFirst()] = nil
        }
    }

    /// An artist Navidrome no longer has: their kept answer let go.
    func forget(_ id: String) {
        kept[id] = nil
        keptOrder.removeAll { (kept: String) -> Bool in kept == id }
    }

    // MARK: Last.fm (slice A1 - notes/ios.md "Last.fm, slice A1")

    /// Each artist's Last.fm answer kept for the session, beside their own answer (LastfmPage.Kept: the last 64, an
    /// answer not had whole a minute) - an artist page opened again draws Top Songs at once, in place.
    @ObservationIgnored private var lastfm = LastfmPage.Kept()
    /// The artist pages showing, by artist id - their Top Songs page draws the very rows the page has.
    @ObservationIgnored private var pages: [String: ShownArtistPage] = [:]

    func keptLastfm(_ id: String) -> LastfmPage.Kept.Entry? { lastfm.entry(id, now: Self.now) }

    /// An artist's Last.fm answer kept - nil for an ask that failed (kept a minute).
    func keepLastfm(_ id: String, _ answer: LastfmArtist?, asked: String) {
        lastfm.keep(id, answer, asked: asked, now: Self.now)
    }

    /// The clock the kept answers are timed by, in ms: one that only goes forward and counts the phone asleep
    /// (Monotonic, as SearchModel's kept answers are timed) - never the wall clock, which can be set back.
    private static var now: Double { Monotonic.seconds() * 1000 }

    /// An artist page showing: its model is the one their Top Songs page reads.
    func showing(_ page: ArtistPageModel) {
        pages[page.route.id] = ShownArtistPage(page)
    }

    /// The artist page showing for the artist, if one still is.
    func page(_ id: String) -> ArtistPageModel? { pages[id]?.page }

    // MARK: Last.fm (slice A2 - notes/ios.md "Last.fm, slice A2")

    /// (A2) The albums' order on an artist's page, kept per device (`deadwax-artist-album-order`, read with
    /// AlbumOrder(saved:): anything but `played` is newest first).
    var albumOrder: AlbumOrder = AlbumOrder(saved: UserDefaults.standard.string(forKey: AlbumOrder.storageKey)) {
        didSet { UserDefaults.standard.set(albumOrder.rawValue, forKey: AlbumOrder.storageKey) }
    }

    /// (A2) The library's artists as Similar Artists meets them, made once per list - nil while no list is in hand.
    @ObservationIgnored private var similarMade: (serial: Int, library: SimilarArtists.Library)?

    func similarLibrary() -> SimilarArtists.Library? {
        guard let list else { return nil }
        if let made = similarMade, made.serial == serial { return made.library }
        let library = SimilarArtists.Library(list)
        similarMade = (serial, library)
        return library
    }

    /// (A2) Whether the library's artists have answered (or failed) - Similar Artists' tiles wait for one or the other.
    var listKnown: Bool { list != nil || failure != nil }

    // MARK: who an artist is, chosen (Phase 8, slice 5)

    /// Who an artist page's artist is on MusicBrainz, chosen with Which artist is this? - by the page's artist id, for
    /// this visit (the web's `kept.chosen`): used only while nothing else says who they are, never written anywhere.
    private(set) var chosen: [String: MBArtistMatch] = [:]

    func choose(_ id: String, _ match: MBArtistMatch) {
        chosen[id] = match
    }

    // MARK: a new person

    /// The person changed: nothing of theirs kept, and nothing asked before lands after.
    func reset() {
        epoch += 1
        asks += 1
        list = nil
        failure = nil
        landed = nil
        told = 0
        toldMoved = nil
        asking = nil
        serial = 0
        shelves = [:]
        sorted = [:]
        drawnCache = [:]
        kept = [:]
        keptOrder = []
        chosen = [:]
        lastfm = LastfmPage.Kept()
        pages = [:]
        similarMade = nil
    }
}

/// An artist page's model, held no longer than its page holds it.
private final class ShownArtistPage {
    weak var page: ArtistPageModel?

    init(_ page: ArtistPageModel) {
        self.page = page
    }
}
