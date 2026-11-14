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
/// - Every artist Navidrome has (`GET /deadwax/navidrome/artists`), asked as an Artists screen shows and again each time
///   it shows - as the web's, which keeps no list from one look to the next - the newest answer only. A failure keeps
///   the list in hand (the screen says it couldn't be asked again); kept in memory only, so the app opening asks again.
/// - What each screen draws of it: the collection's list, Your artists (Core's YourArtists over your albums, counting
///   yours - with a library of your own), or, while deadwax can't be reached and no list is in hand, the artists of the
///   albums on this phone (ArtistOffline.artists). Each list's ArtistShelf made once, its order once per order, and
///   what Find keeps once per what is typed.
/// - The artist order, per device, under the web's own key (ArtistOrder.storageKey).
/// - The last `ArtistPage.kept` artists' answers (ARTISTS_KEPT): an artist page opened again draws at once, and while
///   deadwax can't be reached, from what was in hand.
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

    /// `GET /artists`: the list asked again - drawn in place of the one in hand when it lands (when it differs); a
    /// failure keeps the one in hand and says why.
    func ask() async {
        guard let client = server.client else { return }
        asks += 1
        let asked = asks
        let epoch = self.epoch
        failure = nil
        do {
            let artists = try await client.artists()
            guard asked == asks, epoch == self.epoch else { return }
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

    // MARK: a new person

    /// The person changed: nothing of theirs kept, and nothing asked before lands after.
    func reset() {
        epoch += 1
        asks += 1
        list = nil
        failure = nil
        serial = 0
        shelves = [:]
        sorted = [:]
        drawnCache = [:]
        kept = [:]
        keptOrder = []
    }
}
