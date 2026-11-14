import Testing
@testable import DeadwaxCore

/// Phase 4 slice 1's review (notes/ios.md "Phase 4, slice 1, after its review"): the albums a queue names never let go
/// of by the store (PlayedAlbums' `keeping`, the phone's own - the fixture's runs hold the web's store with none), the
/// phone's `forget`, the queue's album ids, and a row's offline start.
@Suite struct PlaylistReviewTests {
    typealias Named = PlaylistVectors.Named

    /// A playlist's albums, as PlayerModel remembers them: `n` stubs, the first to play first.
    private static func playlist(_ n: Int) -> [Named] {
        (0..<n).map { Named(id: "q\($0)", tag: "stub") }
    }

    private static func ids(_ albums: [Named]) -> Set<String> { Set(albums.map(\.id)) }

    @Test func albumPagesShownNeverLetGoOfAThirtyAlbumPlaylist() {
        // the review's first case: the 35th distinct album page shown dropped the playlist's last album
        let queue = Self.playlist(30)
        var phone = PlayedAlbums<Named>()
        var web = PlayedAlbums<Named>()
        phone.rememberQueue(queue, keeping: Self.ids(queue))
        web.rememberQueue(queue)
        for page in 0..<40 {
            phone.also(Named(id: "page\(page)", tag: "page"), keeping: Self.ids(queue))
            web.also(Named(id: "page\(page)", tag: "page"))
            if page < 34 { #expect(web.get("q29") != nil, "page \(page)") }
        }
        for album in queue { #expect(phone.get(album.id)?.tag == "stub", "\(album.id)") }
        // the web's store, as the web has it, lets the last to play go once 64 are held (this is why `keeping` exists)
        #expect(web.get("q29") == nil)
        #expect(web.count == 64)
        // the pages beyond the queue's are let go, oldest first: the store stays within its bound
        #expect(phone.count == 64)
        #expect(phone.get("page39") != nil)
        #expect(phone.get("page0") == nil)
    }

    @Test func everyPageShownKeepsASixtyFourAlbumPlaylistWhole() {
        // the review's second case: with 64 albums in the queue, every page shown dropped one
        let queue = Self.playlist(64)
        var phone = PlayedAlbums<Named>()
        var web = PlayedAlbums<Named>()
        phone.rememberQueue(queue, keeping: Self.ids(queue))
        web.rememberQueue(queue)
        phone.also(Named(id: "page0", tag: "page"), keeping: Self.ids(queue))
        web.also(Named(id: "page0", tag: "page"))
        #expect(web.get("q63") == nil)
        for page in 1..<10 { phone.also(Named(id: "page\(page)", tag: "page"), keeping: Self.ids(queue)) }
        for album in queue { #expect(phone.get(album.id)?.tag == "stub", "\(album.id)") }
        // the page just shown is kept too (it's the newest), and only it: 64 and one
        #expect(phone.get("page9")?.tag == "page")
        #expect(phone.get("page8") == nil)
        #expect(phone.count == 65)
    }

    @Test func aQueuePastTheBoundKeepsEveryAlbumItNames() {
        let queue = Self.playlist(70)
        var phone = PlayedAlbums<Named>()
        phone.rememberQueue(queue, keeping: Self.ids(queue))
        #expect(phone.count == 70)
        for album in queue { #expect(phone.get(album.id) != nil, "\(album.id)") }
        // the web's keeps the first 64 to play
        var web = PlayedAlbums<Named>()
        web.rememberQueue(queue)
        #expect(web.count == 64)
        #expect(web.get("q63") != nil)
        #expect(web.get("q64") == nil)
    }

    @Test func playNextKeepsTheQueuesAlbumsAndTheOneAdded() {
        var store = PlayedAlbums<Named>(kept: 1, queueKept: 1)
        store.rememberQueue([Named(id: "a"), Named(id: "b")], keeping: ["a", "b"])
        #expect(Set(store.ids) == ["a", "b"])
        // over the bound, and everything else kept: the album just put isn't let go either
        store.also(Named(id: "c", tag: "added"), keeping: ["a", "b"])
        #expect(Set(store.ids) == ["a", "b", "c"])
        #expect(store.get("c")?.tag == "added")
        // the queue moved on (it names none of them): back within the bound, the newest kept
        store.also(Named(id: "d"), keeping: [])
        #expect(store.ids == ["d"])
        // a kept album in the middle: the others let go oldest first around it
        var middle = PlayedAlbums<Named>(kept: 2, queueKept: 2)
        for id in ["x1", "x2", "x3"] { middle.remember(Named(id: id)) }
        #expect(middle.ids == ["x2", "x3"])
        middle.also(Named(id: "x4"), keeping: ["x2"])
        #expect(middle.ids == ["x2", "x4"])
        // remember keeps what it's told too, and its own album
        middle.remember(Named(id: "x5"), keeping: ["x2"])
        #expect(middle.ids == ["x2", "x5"])
        middle.remember(Named(id: "x6"))
        #expect(middle.ids == ["x5", "x6"])
        // remember with everything else kept: its own album isn't let go either
        var small = PlayedAlbums<Named>(kept: 1, queueKept: 1)
        small.rememberQueue([Named(id: "a"), Named(id: "b")], keeping: ["a", "b"])
        small.remember(Named(id: "c", tag: "played"), keeping: ["a", "b"])
        #expect(Set(small.ids) == ["a", "b", "c"])
        #expect(small.get("c")?.tag == "played")
    }

    @Test func keepingNothingIsTheWebsStore() {
        // the same operations with `keeping` empty and with it left out answer alike - what the fixture holds
        var left = PlayedAlbums<Named>(kept: 3, queueKept: 5)
        var empty = PlayedAlbums<Named>(kept: 3, queueKept: 5)
        let steps: [(String, [String])] = [("remember", ["a"]), ("queue", ["b", "c", "d", "e", "f", "g"]),
                                           ("also", ["h"]), ("also", ["b"]), ("remember", ["i"]), ("queue", [])]
        for (op, ids) in steps {
            let albums = ids.map { Named(id: $0) }
            switch op {
            case "remember":
                left.remember(albums[0])
                empty.remember(albums[0], keeping: [])
            case "queue":
                left.rememberQueue(albums)
                empty.rememberQueue(albums, keeping: [])
            default:
                left.also(albums[0])
                empty.also(albums[0], keeping: [])
            }
            #expect(left.ids == empty.ids, "\(op) \(ids)")
        }
    }

    @Test func anAlbumGoneIsForgottenAtOnce() {
        var store = PlayedAlbums<Named>()
        for id in ["a", "b", "c"] { store.remember(Named(id: id, tag: "first")) }
        store.forget("b")
        #expect(store.get("b") == nil)
        #expect(store.ids == ["a", "c"])
        #expect(store.count == 2)
        // one not held: nothing changes
        store.forget("z")
        store.forget("")
        #expect(store.ids == ["a", "c"])
        // put again, it's the newest, as a new answer
        store.also(Named(id: "b", tag: "again"))
        #expect(store.ids == ["a", "c", "b"])
        #expect(store.get("b")?.tag == "again")
        // a queue's album forgotten leaves the rest of the queue held
        var queue = PlayedAlbums<Named>()
        queue.rememberQueue(Self.playlist(20))
        queue.forget("q5")
        #expect(queue.count == 19)
        #expect(queue.get("q5") == nil)
        #expect(queue.get("q19") != nil)
    }

    @Test func theQueueNamesEachAlbumOnce() {
        let track = { (id: String, album: String?) -> QueueTrack in
            QueueTrack(id: id, title: id, artist: "", album: "", albumId: album)
        }
        #expect(QueueAlbums.named([]).isEmpty)
        let tracks = [track("s1", "al-a"), track("s2", nil), track("s3", ""), track("s4", "al-b"), track("s5", "al-a")]
        #expect(QueueAlbums.named(tracks) == ["al-a", "al-b"])
    }

    @Test func aRowTappedOfflineStartsAtItsPlaceAmongTheSongsHere() {
        // a song listed twice is two rows: its place is counted, never looked up by id
        let songs = ["a", "b", "a", "c", "d"].map { Song(id: $0) }
        let here: Set<String> = ["a", "c"]
        let isHere = { (id: String) -> Bool in here.contains(id) }
        let playable = songs.filter { isHere($0.id) }.map(\.id)
        #expect(playable == ["a", "a", "c"])
        #expect(PlaylistPlay.offlineStart(row: 0, songs: songs, here: isHere) == 0)
        #expect(PlaylistPlay.offlineStart(row: 2, songs: songs, here: isHere) == 1)
        #expect(PlaylistPlay.offlineStart(row: 3, songs: songs, here: isHere) == 2)
        // rows not on this phone start nothing
        #expect(PlaylistPlay.offlineStart(row: 1, songs: songs, here: isHere) == nil)
        #expect(PlaylistPlay.offlineStart(row: 4, songs: songs, here: isHere) == nil)
        // nor rows that aren't there
        #expect(PlaylistPlay.offlineStart(row: 5, songs: songs, here: isHere) == nil)
        #expect(PlaylistPlay.offlineStart(row: -1, songs: songs, here: isHere) == nil)
        #expect(PlaylistPlay.offlineStart(row: 0, songs: [], here: isHere) == nil)
        // with every song here, a row's start is the row
        for row in songs.indices {
            #expect(PlaylistPlay.offlineStart(row: row, songs: songs, here: { (_: String) -> Bool in true }) == row)
        }
    }
}
