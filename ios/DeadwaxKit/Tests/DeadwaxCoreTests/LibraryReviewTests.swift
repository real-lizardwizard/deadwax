import Foundation
import Testing
@testable import DeadwaxCore

// Phase 3 after the review of slices 1-2 (phase3-autodownload.md 6.6): the fill's hysteresis and an album's own cover,
// the phone's deficit confirmed before anything here gives way, one number for what the library can give back, the
// library's share of tasks out, songs leaving an album only on two reads, kept song lists read again, Remove on the
// question surviving a check in flight, the last album removed here, a removed album's songs by id, and the store's
// unnamed files. Each a Core rule, each with a mutation that breaks it.

private let t0: Int64 = 1_800_000_000_000
private let minute: Int64 = 60_000
private let day: Int64 = 24 * 60 * minute
private let gb: Int64 = 1_000_000_000
private let mb: Int64 = 1_000_000
private let kb: Int64 = 1_000

private func read(_ album: String, _ count: Int = 2, bytes: Int64 = 100 * mb) -> [FollowedSong] {
    (1...count).map { FollowedSong(id: "\(album)-\($0)", disc: 1, track: $0, size: bytes, suffix: "flac") }
}

private func entry(_ id: String) -> IndexAlbum {
    IndexAlbum(id: id, name: "Album \(id)", songCount: 2, duration: 600)
}

private func followed(_ id: String, _ position: Int = 0, songs: [FollowedSong]? = nil, readAt: Int64 = t0,
                      removedHere: Int64? = nil, left: [String: Int64] = [:]) -> FollowedAlbum {
    FollowedAlbum(album: entry(id), position: position, songs: songs ?? read(id), readAt: readAt,
                  removedHere: removedHere, left: left)
}

private func here(_ album: String, _ origins: Set<DownloadOrigin> = [.library], state: StoredState = .done,
                  count: Int = 2, bytes: Int64 = 100 * mb) -> [StoreSong] {
    (1...count).map { StoreSong(id: "\(album)-\($0)", albumID: album, origins: origins, state: state, bytes: bytes) }
}

private func listed(_ ids: [String]) -> LibraryFollow.Answer {
    .listed(AlbumIndexAnswer(albums: ids.map(entry)))
}

/// A little store run turn after turn as DownloadModel runs it: the turn, its takes (Phase 2's rule: a song left with
/// no origin goes, its album's cover with the album's last song), its asks, every song asked arriving whole, and each
/// album's cover kept as keepAlbum keeps it.
private struct Store {
    var songs: [StoreSong] = []
    var covers: [String: Int64] = [:]
    var coverBytes: Int64
    var asked = 0
    var taken = 0

    init(coverBytes: Int64) { self.coverBytes = coverBytes }

    var bytesHere: Int64 {
        songs.reduce(Int64(0)) { $0 + ($1.state == .done ? $1.bytes : 0) } + covers.values.reduce(0, +)
    }

    mutating func turn(_ ordered: [FollowedAlbum], limit: Int64?, free: Int64) -> LibraryDownloads.Turn {
        let turn = LibraryDownloads.turn(ordered, removed: [], songs: songs, covers: covers, bytesHere: bytesHere,
                                         handToCome: 0, limit: limit, freeSpace: free)
        let take = Set(turn.actions.take)
        taken += take.count
        songs = songs.compactMap { song in
            guard take.contains(song.id) else { return song }
            let left = song.origins.subtracting(LibraryDownloads.gives)
            return left.isEmpty ? nil
                : StoreSong(id: song.id, albumID: song.albumID, origins: left, state: song.state, bytes: song.bytes)
        }
        for album in Array(covers.keys) where !songs.contains(where: { $0.albumID == album }) { covers[album] = nil }
        for ask in turn.actions.ask {
            asked += 1
            for wanted in ask.songs {
                songs.removeAll { $0.id == wanted.id }
                songs.append(StoreSong(id: wanted.id, albumID: ask.album, origins: [.library], state: .done,
                                       bytes: wanted.bytes))
            }
            covers[ask.album] = coverBytes
        }
        return turn
    }
}

@Suite struct LibraryReviewTests {
    // MARK: 1 - an album's own cover, and the hysteresis

    @Test func anAlbumsOwnCoverIsCountedAsItsOwnNotAsAHandDownloads() {
        let ordered = [followed("lib", 0), followed("mixed", 1), followed("new", 2)]
        let songs = here("lib") + here("mixed") + [StoreSong(id: "mixed-3", albumID: "mixed", origins: [.song], bytes: mb)]
        let inputs = LibraryDownloads.inputs(ordered, songs: songs, covers: ["lib": 300 * kb, "mixed": 300 * kb])
        let lib = inputs.albums[0], mixed = inputs.albums[1], new = inputs.albums[2]
        #expect(lib.here == 200 * mb + 300 * kb && lib.bytes == 200 * mb + 300 * kb, "the library's alone: its cover is its own")
        #expect(mixed.here == 200 * mb && mixed.bytes == 200 * mb, "a song by hand on it: the cover is the hand download's")
        #expect(new.bytes == 200 * mb + LibraryFill.albumAllowance && new.here == 0, "not kept yet: the allowance")
        #expect(inputs.givable == lib.here + mixed.here)
        // so the hand downloads' bytes here are the hand's song and the mixed album's cover - not the library's cover
        let turn = LibraryDownloads.turn(ordered, inputs: inputs, removed: [], songs: songs,
                                         bytesHere: 400 * mb + mb + 600 * kb, handToCome: 0,
                                         limit: 400 * mb + mb + 600 * kb + 200 * mb + LibraryFill.albumAllowance + 50 * mb,
                                         freeSpace: 100 * gb)
        #expect(turn.fill.fits == ["lib", "mixed", "new"], "the hand downloads take only their own: \(turn.fill.waits)")
    }

    @Test func anAlbumAtTheEdgeIsNeverAskedAndGivenWayInALoop() {
        // a 5 GB limit, one album; its cover arrives with it at 3 MB (more than the allowance)
        let limit: Int64 = 5 * gb
        let cover: Int64 = 3 * mb
        // just inside the margin: asked once, and its cover keeps it in
        let inside = limit - LibraryFill.albumAllowance - LibraryFill.margin(limit: limit) - 200 * kb
        var store = Store(coverBytes: cover)
        let fits = [followed("L", 0, songs: read("L", 1, bytes: inside))]
        for _ in 0..<6 { _ = store.turn(fits, limit: limit, free: 100 * gb) }
        #expect(store.asked == 1 && store.taken == 0)
        #expect(store.songs.map(\.id) == ["L-1"] && store.covers["L"] == cover)
        // with only 200 KB to spare, no margin: it waits, and nothing moves
        let edge = limit - LibraryFill.albumAllowance - 200 * kb
        var tight = Store(coverBytes: cover)
        let waits = [followed("L", 0, songs: read("L", 1, bytes: edge))]
        for _ in 0..<6 {
            let turn = tight.turn(waits, limit: limit, free: 100 * gb)
            #expect(turn.fill.waits == ["L": .room])
        }
        #expect(tight.asked == 0 && tight.taken == 0)
    }

    @Test func aNewAlbumNeedsTheMarginAHeldOneOnlyToFit() {
        let left = 10 * gb
        let margin = LibraryFill.margin(limit: left)
        #expect(margin == 100 * mb && LibraryFill.margin(limit: nil) == 50 * mb && LibraryFill.margin(limit: gb) == 50 * mb)
        let new = LibraryFill.plan([.init(id: "a", bytes: left - margin + 1)], .init(limit: left, freeSpace: 100 * gb))
        #expect(new.waits == ["a": .room])
        let held = LibraryFill.plan([.init(id: "a", bytes: left, here: 0, toCome: left, held: true)],
                                    .init(limit: left, freeSpace: 100 * gb))
        #expect(held.fits == ["a"], "asked already: it keeps its place while it fits at all")
        let over = LibraryFill.plan([.init(id: "a", bytes: left + 1, here: gb)], .init(limit: left, freeSpace: 100 * gb))
        #expect(over.giveWay == ["a"], "nothing is ever over the limit")
    }

    // MARK: 2 - the phone: what's here stays unless the phone itself is short, seen minutes apart

    @Test func aNewStarAboveAlbumsHereNeverPushesThemOut() {
        // 2.5 GB free, no limit, b and c (5 GB each) here, a new 1 GB star above them
        let ordered = [followed("a", 0, songs: read("a", 1, bytes: gb)),
                       followed("b", 1, songs: read("b", 1, bytes: 5 * gb)),
                       followed("c", 2, songs: read("c", 1, bytes: 5 * gb))]
        let songs = here("b", count: 1, bytes: 5 * gb) + here("c", count: 1, bytes: 5 * gb)
        let turn = LibraryDownloads.turn(ordered, removed: [], songs: songs, covers: ["b": 0, "c": 0],
                                         bytesHere: 10 * gb, handToCome: 0, limit: nil, freeSpace: 2_500_000_000,
                                         deficitConfirmed: true)
        #expect(turn.fill.fits == ["b", "c"] && turn.fill.waits == ["a": .phoneFull])
        #expect(turn.actions.take.isEmpty && turn.actions.ask.isEmpty && turn.fill.deficit == 0)
    }

    @Test func albumsHereGiveWayOnlyForTheDeficitAndOnlyOnceConfirmed() {
        let ordered = [followed("b", 0, songs: read("b", 1, bytes: 5 * gb)),
                       followed("c", 1, songs: read("c", 1, bytes: 5 * gb))]
        let songs = here("b", count: 1, bytes: 5 * gb) + here("c", count: 1, bytes: 5 * gb)
        func turn(free: Int64, handToCome: Int64 = 0, confirmed: Bool) -> LibraryDownloads.Turn {
            LibraryDownloads.turn(ordered, removed: [], songs: songs, covers: ["b": 0, "c": 0], bytesHere: 10 * gb,
                                  handToCome: handToCome, limit: nil, freeSpace: free, deficitConfirmed: confirmed)
        }
        // 1.5 GB free: 0.5 GB short of the reserve
        let once = turn(free: 1_500_000_000, confirmed: false)
        #expect(once.fill.deficit == 500 * mb && once.actions.take.isEmpty, "one reading deletes nothing")
        let held = turn(free: 1_500_000_000, confirmed: true)
        #expect(held.actions.take == ["c-1"] && held.fill.fits == ["b"], "the bottom, only as much as the deficit")
        // a hand download to come that leaves the phone short counts too
        let hand = turn(free: 3 * gb, handToCome: 6_500_000_000, confirmed: true)
        #expect(Set(hand.actions.take) == ["b-1", "c-1"] && hand.fill.deficit == 5_500 * mb)
        // the phone at its reserve: nothing
        #expect(turn(free: 2 * gb, confirmed: true).actions.take.isEmpty)
    }

    @Test func theDeficitIsBelievedOnlyOnPlansMinutesApart() {
        var since: Int64? = nil
        func plan(_ deficit: Bool, at: Int64) -> Bool {
            since = LibraryFill.deficitSince(since, deficit: deficit, now: at)
            return LibraryFill.deficitConfirmed(since: since, now: at)
        }
        #expect(!plan(true, at: 0), "first seen")
        #expect(!plan(true, at: 3 * minute - 1))
        #expect(!plan(false, at: 3 * minute - 1 + 1), "gone for one plan: forgotten")
        #expect(!plan(true, at: 4 * minute))
        #expect(!plan(true, at: 6 * minute), "two minutes since it came back")
        #expect(plan(true, at: 7 * minute))
        #expect(LibraryFill.deficitConfirmMs == 3 * minute)
        #expect(LibraryFill.deficit(freeSpace: 3 * gb, handToCome: 0, reserve: 2 * gb) == 0)
        #expect(LibraryFill.deficit(freeSpace: 3 * gb, handToCome: 2 * gb, reserve: 2 * gb) == gb)
    }

    @Test func newAlbumsFitOnlyAboveTheReserveOnceTheHandDownloadsAndTheHeldAlbumsArrive() {
        // 3 GB free, 500 MB of hand downloads to come: 500 MB over the reserve
        let fits = LibraryFill.plan([.init(id: "n", bytes: 400 * mb)],
                                    .init(handToCome: 500 * mb, limit: nil, freeSpace: 3 * gb))
        #expect(fits.fits == ["n"])
        let short = LibraryFill.plan([.init(id: "n", bytes: 460 * mb)],
                                     .init(handToCome: 500 * mb, limit: nil, freeSpace: 3 * gb))
        #expect(short.waits == ["n": .phoneFull], "the margin")
        // a held album below with 1 GB still to come has its claim first
        let claim = LibraryFill.plan([.init(id: "n", bytes: 460 * mb),
                                      .init(id: "h", bytes: 2 * gb, here: gb, toCome: gb, held: true)],
                                     .init(limit: nil, freeSpace: 3_500_000_000))
        #expect(claim.fits == ["h"] && claim.waits == ["n": .phoneFull])
    }

    // MARK: 11 - one number for what the library can give back

    @Test func thePlannerIsCreditedOnlyWhatTheFillWouldGiveBack() {
        // read and here: 2 GB; read again (unread) and here: 5 GB; a library song on no album of the library: 3 GB
        let ordered = [followed("read", 0, songs: read("read", 2, bytes: gb)),
                       FollowedAlbum(album: entry("rereading"), position: 1)]
        let songs = here("read", bytes: gb) + here("rereading", bytes: 2_500_000_000) + here("orphan", bytes: 1_500_000_000)
        let inputs = LibraryDownloads.inputs(ordered, songs: songs, covers: ["read": 0, "rereading": 0])
        #expect(inputs.givable == 2 * gb && inputs.givable == LibraryFill.givable(inputs.albums))
        // a 2 GB hand album on a phone with 1 GB free: credited 2 GB, it isn't taken on (1 + 2 - 2 < 2)
        let album = (1...2).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "h-\(n)", albumID: "h", disc: 1, track: n, wantedAt: 1, origins: [.album("h")],
                               expected: gb)
        }
        let facts = DownloadPlan.Facts(bytesHere: 10 * gb, libraryHere: inputs.givable, limit: nil, freeSpace: gb)
        #expect(DownloadPlan.handToCome(album, facts) == 0)
        #expect(DownloadPlan.plan(album, facts)["h-1"] == DownloadPlan.Decision(wait: .phoneFull, task: false))
        // the fill: what the library can't give back counts against the limit as it is
        let turn = LibraryDownloads.turn(ordered, inputs: inputs, removed: [], songs: songs, bytesHere: 10 * gb,
                                         handToCome: 0, limit: 10 * gb, freeSpace: 100 * gb)
        #expect(turn.fill.fits == ["read"] && turn.actions.take.isEmpty, "8 GB fixed + read's 2 GB: exactly the limit")
    }

    // MARK: 3 - the library's share of tasks out

    @Test func aHandAlbumGetsItsTasksWithAHundredOfTheLibrarysOut() {
        let library = (0..<50).flatMap { (a: Int) -> [DownloadPlan.Asked] in
            (1...2).map { (n: Int) -> DownloadPlan.Asked in
                DownloadPlan.Asked(id: "l\(a)-\(n)", albumID: "l\(a)", disc: 1, track: n, wantedAt: 0,
                                   origins: [.library], expected: mb, out: true, libraryRank: a)
            }
        }
        let hand = (1...10).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "h-\(n)", albumID: "h", disc: 1, track: n, wantedAt: 5, origins: [.album("h")],
                               expected: mb)
        }
        let plan = DownloadPlan.plan(library + hand, DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 100 * gb))
        #expect((1...10).allSatisfy { plan["h-\($0)"]?.task == true }, "the hand album's ten made")
        let libraryOut = library.filter { plan[$0.id]?.task == true }
        #expect(libraryOut.count == DownloadPlan.libraryMaxOut, "the rest let go, their resume data kept")
        #expect(libraryOut.allSatisfy { $0.libraryRank! < 10 }, "the first in the fill's order stay")
        #expect(plan.values.filter(\.task).count <= DownloadPlan.maxOut)
        // with no hand download, still only the library's share
        let alone = DownloadPlan.plan(library, DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 100 * gb))
        #expect(alone.values.filter(\.task).count == DownloadPlan.libraryMaxOut)
    }

    // MARK: 4 - a song leaves its album only on two reads

    @Test func aReadMarksWhatLeftAndOnlyASecondReadTenMinutesOnAgrees() {
        let album = followed("a", songs: read("a", 3))
        let library: Set<String> = ["a-1", "a-2", "a-3"]
        #expect(LibraryFollow.read(album, songs: [], library: library, at: t0) == nil, "an empty answer is never taken in")
        let first = LibraryFollow.read(album, songs: read("a", 1), library: library, at: t0)!
        #expect(first.left == ["a-2": t0, "a-3": t0] && first.leftAgreed.isEmpty)
        #expect(first.secondReadAt == t0 + 10 * minute)
        let early = LibraryFollow.read(first, songs: read("a", 1), library: library, at: t0 + 10 * minute - 1)!
        #expect(early.leftAgreed.isEmpty && early.left == ["a-2": t0, "a-3": t0])
        // a-3 came back meanwhile: it's no longer marked
        let agreed = LibraryFollow.read(early, songs: read("a", 1) + [FollowedSong(id: "a-3")], library: library,
                                        at: t0 + 10 * minute)!
        #expect(agreed.leftAgreed == ["a-2"] && agreed.left == ["a-2": t0] && agreed.secondReadAt == nil)
        // only what the store has under the library is marked
        #expect(LibraryFollow.read(album, songs: read("a", 1), library: [], at: t0)!.left.isEmpty)
    }

    @Test func aSongIsTakenFromItsAlbumOnlyWhenTwoReadsAgree() {
        let songs = here("a", count: 3)
        let library = Set(songs.map(\.id))
        let start = followed("a", songs: read("a", 3))
        func taken(_ album: FollowedAlbum) -> [String] {
            let ordered = [album]
            let fill = LibraryFill.plan(LibraryFill.albums(ordered), .init(limit: nil, freeSpace: 10_000 * gb))
            return LibraryDownloads.actions(ordered, fill: fill, removed: [], songs: songs).take
        }
        // a mid-rescan answers one song: nothing goes
        let once = LibraryFollow.read(start, songs: read("a", 1), library: library, at: t0)!
        #expect(taken(once).isEmpty)
        let nine = LibraryFollow.read(once, songs: read("a", 1), library: library, at: t0 + 9 * minute)!
        #expect(taken(nine).isEmpty)
        // the rescan done: all three back, nothing goes, nothing marked
        let back = LibraryFollow.read(nine, songs: read("a", 3), library: library, at: t0 + 12 * minute)!
        #expect(taken(back).isEmpty && back.left.isEmpty)
        // a real retag: two reads ten minutes apart
        let retag = LibraryFollow.read(back, songs: read("a", 2), library: library, at: t0 + 20 * minute)!
        #expect(taken(retag).isEmpty)
        let confirmed = LibraryFollow.read(retag, songs: read("a", 2), library: library, at: t0 + 30 * minute)!
        #expect(taken(confirmed) == ["a-3"])
    }

    @Test func anAlbumDueItsSecondReadIsReadThen() {
        let pending = followed("p", 1, left: ["p-2": t0])
        let ordered = [followed("a", 0), pending, followed("u", 2, songs: nil)]
        var unread = ordered
        unread[2].songs = nil
        unread[2].readAt = nil
        #expect(LibraryFollow.toRead(unread, now: t0 + 10 * minute - 1) == ["u"])
        #expect(LibraryFollow.toRead(unread, now: t0 + 10 * minute) == ["u", "p"])
        #expect(LibraryFollow.toRead(unread) == ["u"], "without a time: the unread alone, as before")
    }

    // MARK: 6 - kept song lists read again

    @Test func keptSongListsAreReadAgainAWeekOnAFewAtATime() {
        let now = t0 + 8 * day
        let ordered = [followed("fresh", 0, readAt: t0 + 7 * day), followed("old", 1, readAt: t0),
                       followed("older", 2, readAt: t0 - day), followed("oldest", 3, readAt: t0 - 2 * day)]
        #expect(LibraryFollow.toRead(ordered, now: now, refreshing: 2) == ["oldest", "older"])
        #expect(LibraryFollow.toRead(ordered, now: now, refreshing: 20) == ["oldest", "older", "old"])
        #expect(LibraryFollow.toRead(ordered, now: now, refreshing: 0).isEmpty)
        #expect(LibraryFollow.toRead(ordered, failed: ["oldest"], now: now, refreshing: 1) == ["older"])
        #expect(LibraryFollow.refreshAfterMs == 7 * day && LibraryFollow.refreshesPerCheck == 20)
    }

    // MARK: 10 - unreadable albums don't hold up the rest

    @Test func albumsThatFailedAtAnEarlierCheckAreReadAfterTheRest() {
        let ids = ["a", "b", "c", "d", "e"]
        let ordered = ids.indices.map { (place: Int) -> FollowedAlbum in FollowedAlbum(album: entry(ids[place]), position: place) }
        #expect(LibraryFollow.toRead(ordered, retryLast: ["a", "b"]) == ["c", "d", "e", "a", "b"])
        #expect(LibraryFollow.toRead(ordered, failed: ["c"], retryLast: ["a"]) == ["b", "d", "e", "a"])
        #expect(LibraryFollow.readFailuresPerRun == 12)
    }

    // MARK: 7 - Remove on the question survives a check already in flight

    @Test func aThreeOhFourOfTheHeldListKeepsRemoveStanding() {
        let kept = [followed("a", 0), followed("b", 1)]
        let held = LibraryFollow.sync(kept, answer: listed([]), held: nil, at: t0)
        #expect(held.held == .empty(kept: 2))
        // the Remove answered while a check sent before it was out: that check's 304 doesn't spend it
        let repeated = LibraryFollow.sync(held.albums, answer: .unchanged, held: held.held, at: t0 + minute, believing: true)
        #expect(LibraryFollow.keepsBelieving(repeated, listed: false))
        // the fresh list it was waiting for is believed
        let fresh = LibraryFollow.sync(repeated.albums, answer: listed([]), held: repeated.held, at: t0 + 2 * minute,
                                       believing: true)
        #expect(fresh.believed && LibraryFollow.keepsBelieving(fresh, listed: true))
    }

    // MARK: 8 - the last album removed here

    @Test func removingYourLastAlbumHereRemovesItRatherThanAsking() {
        let last = [followed("a", 0, removedHere: t0)]
        let out = LibraryFollow.sync(last, answer: listed([]), held: nil, at: t0 + 1)
        #expect(out.held == nil && out.removed == ["a"])
        // with another album kept, an empty list is still held
        let two = [followed("a", 0, removedHere: t0), followed("b", 1)]
        let still = LibraryFollow.sync(two, answer: listed([]), held: nil, at: t0 + 1)
        #expect(still.held == .empty(kept: 1) && still.removed.isEmpty)
    }

    // MARK: 9 - a removed album's songs, by id

    @Test func aRemovedAlbumsSongsGoByIdEvenUnderAnotherAlbumId() {
        // downloaded from a queue with no album id, then gained the library's origin
        let songs = [StoreSong(id: "x-1", albumID: "", origins: [.library]),
                     StoreSong(id: "x-2", albumID: "", origins: [.library, .song]),
                     StoreSong(id: "y-1", albumID: "", origins: [.library])]
        let actions = LibraryDownloads.actions([], fill: LibraryFill.plan([], .init(limit: nil, freeSpace: 100 * gb)),
                                               removed: ["x"], removedSongs: ["x-1", "x-2"], songs: songs)
        #expect(Set(actions.take) == ["x-1", "x-2"])
        #expect(LibraryDownloads.deleted(actions, songs: songs) == ["x-1"], "the one also wanted by hand stays")
        // one a retag moved onto an album still in the library stays with it
        let moved = [StoreSong(id: "x-1", albumID: "z", origins: [.library])]
        let z = [followed("z", songs: [FollowedSong(id: "x-1")])]
        #expect(LibraryDownloads.actions(z, fill: LibraryFill.plan(LibraryFill.albums(z), .init(limit: nil, freeSpace: 100 * gb)),
                                         removed: ["x"], removedSongs: ["x-1"], songs: moved).take.isEmpty)
    }

    @Test func debugSaysTheDeficitAndTheSongsLeaving() {
        #expect(LibraryFollowWords.underReserve(500 * mb, confirmed: false) == "500 MB under the reserve \u{00B7} confirming")
        #expect(LibraryFollowWords.underReserve(2 * gb, confirmed: true) == "2 GB under the reserve \u{00B7} giving way")
        let albums = [followed("a", left: ["a-1": t0, "a-2": t0]), followed("b"), followed("c", left: ["c-1": t0])]
        #expect(LibraryFollowWords.leaving(albums) == "3 songs on 2 albums")
        #expect(LibraryFollowWords.leaving([followed("c", left: ["c-1": t0])]) == "1 song on 1 album")
        #expect(LibraryFollowWords.leaving([followed("b")]) == "None")
    }

    @Test func theRemovedAlbumsAreKeptWithTheirSongsAndSliceTwosLinesStillRead() {
        let map = ["x": ["x-1", "x-2"], "y": []]
        let raw = LibraryFollow.removedRaw(map)
        #expect(raw == #"{"x":["x-1","x-2"],"y":[]}"#)
        #expect(LibraryFollow.removed(raw: raw) == map)
        #expect(LibraryFollow.removedRaw([:]) == nil && LibraryFollow.removed(raw: nil).isEmpty)
        #expect(LibraryFollow.removed(raw: "a\nb") == ["a": [], "b": []], "slice 2's lines: by album, as before")
    }

    @Test func aSongALeftMarkIsOnStaysReadOnItsAlbumUntilTheSecondRead() {
        let record = DownloadRecord(song: Song(id: "a-2", title: "Two"), albumID: "", now: t0)
        let entry = followed("a", songs: [read("a")[0]], left: ["a-2": t0])
        let songs = LibraryDownloads.songs([record], origins: ["a-2": [.library]], library: [entry])
        #expect(songs.map(\.albumID) == ["a"])
        // read on another album of the library: that one's
        let other = followed("b", 1, songs: [FollowedSong(id: "a-2")])
        #expect(LibraryDownloads.songs([record], origins: ["a-2": [.library]], library: [entry, other]).map(\.albumID) == ["b"])
    }

    // MARK: 5 - what turning off, and keeping an album off, would delete

    @Test func theConfirmationsSayWhatGoes() {
        let songs = here("a") + here("b", [.library, .song]) + here("c", state: .wanted) + here("d", count: 1, bytes: gb)
        let loses = LibraryDownloads.switchOffLoses(songs)
        #expect(loses.albums == 2 && loses.bytes == 200 * mb + gb)
        #expect(LibraryDownloads.keptOffLoses("a", songs: songs) == 2)
        #expect(LibraryDownloads.keptOffLoses("b", songs: songs) == 0 && LibraryDownloads.keptOffLoses("c", songs: songs) == 0)
        #expect(AutoDownloadWords.offTitle(.yours, albums: 412) == "Remove the 412 albums downloaded with your library?")
        #expect(AutoDownloadWords.offTitle(.store, albums: 1) == "Remove the album downloaded with the collection?")
        #expect(AutoDownloadWords.offMessage(bytes: 12_400_000_000)
                == "They go from this phone (12.4 GB). What you downloaded yourself stays.")
        #expect(AutoDownloadWords.keepOffTitle("Blue") == "Leave Blue off this phone?")
        #expect(AutoDownloadWords.keepOffMessage(.yours, songsHere: 9)
                == "Your library leaves it off until you download it again. Its 9 songs already here go too; songs of it you downloaded yourself stay.")
    }

    // MARK: 12 - the store's own files no row names

    @Test func onlyTheStoresOwnSongFilesThatNoRowNamesAreSwept() {
        let files = ["a.flac", "gone.flac", "b.mp3.part", ".DS_Store", "covers", "x y.flac", "c.flac", "d.FLAC"]
        #expect(DownloadRules.unnamedFiles(files, named: ["a.flac", "c.flac"]) == ["gone.flac"])
        #expect(DownloadRules.unnamedFiles(["a.flac"], named: ["a.flac"]).isEmpty)
    }
}
