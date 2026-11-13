import Foundation
import Testing
@testable import DeadwaxCore

// Your library followed (phase3-autodownload.md 2.2-2.5, its tests 7): what a check makes of deadwax's list, when a check
// is due, the order albums come onto the phone in, and which albums' songs are still to be read.

private let t0: Int64 = 1_800_000_000_000
private let minute: Int64 = 60_000

private func entry(_ id: String, songs: Int? = 10, duration: Double? = 2_400, starred: String? = nil,
                   created: String? = nil, played: String? = nil) -> IndexAlbum {
    IndexAlbum(id: id, name: "Album \(id)", created: created, played: played, starred: starred, songCount: songs,
               duration: duration)
}

private func listed(_ ids: [String], truncated: Bool = false) -> LibraryFollow.Answer {
    .listed(AlbumIndexAnswer(albums: ids.map { entry($0) }, truncated: truncated))
}

private let read = [FollowedSong(id: "s1", size: 30_000_000, suffix: "flac")]

/// The library after a first list of `ids`, each album's songs read.
private func following(_ ids: [String], at: Int64 = t0) -> [FollowedAlbum] {
    LibraryFollow.sync([], answer: listed(ids), held: nil, at: at).albums.map { album in
        var album = album
        album.songs = read
        album.readAt = at
        return album
    }
}

private func ids(_ albums: [FollowedAlbum]) -> [String] { albums.map(\.id) }

@Suite struct LibraryFollowTests {
    // MARK: a 200

    @Test func aFirstListAddsEveryAlbumInItsOrder() {
        let out = LibraryFollow.sync([], answer: listed(["c", "a", "b"]), held: nil, at: t0)
        #expect(out.added == ["c", "a", "b"])
        #expect(ids(out.albums) == ["c", "a", "b"])
        #expect(out.albums.map(\.position) == [0, 1, 2])
        #expect(out.albums.allSatisfy { $0.songs == nil && $0.isListed })
        #expect(out.missing.isEmpty && out.removed.isEmpty && out.held == nil)
    }

    @Test func anAlbumNewToTheListIsAddedAndTheRestMoveInPlace() {
        let kept = following(["a", "b"])
        let out = LibraryFollow.sync(kept, answer: listed(["new", "a", "b"]), held: nil, at: t0 + minute)
        #expect(out.added == ["new"])
        #expect(ids(out.albums) == ["new", "a", "b"])
        #expect(out.albums.map(\.position) == [0, 1, 2])
        #expect(out.albums[1].songs == read, "a kept album keeps its songs")
    }

    @Test func anotherSongCountOrLengthClearsTheSongsAndTheSameEntryKeepsThem() {
        let kept = following(["count", "long", "near", "same"])
        let list = AlbumIndexAnswer(albums: [entry("count", songs: 11), entry("long", duration: 2_400.6),
                                             entry("near", duration: 2_400.5), entry("same")])
        let out = LibraryFollow.sync(kept, answer: .listed(list), held: nil, at: t0 + minute)
        #expect(out.changed == ["count", "long"])
        let byID = Dictionary(uniqueKeysWithValues: out.albums.map { ($0.id, $0) })
        #expect(byID["count"]?.songs == nil && byID["count"]?.readAt == nil)
        #expect(byID["count"]?.album.songCount == 11, "the entry is the new one")
        #expect(byID["long"]?.songs == nil)
        #expect(byID["near"]?.songs == read, "half a second is the same length")
        #expect(byID["same"]?.songs == read)
    }

    @Test func aLengthKnownOnOneSideOnlyCountsAsChanged() {
        #expect(LibraryFollow.songsChanged(entry("a", duration: nil), entry("a", duration: 10)))
        #expect(LibraryFollow.songsChanged(entry("a", duration: 10), entry("a", duration: nil)))
        #expect(!LibraryFollow.songsChanged(entry("a", duration: nil), entry("a", duration: nil)))
        #expect(LibraryFollow.songsChanged(entry("a", songs: nil), entry("a", songs: 3)))
    }

    @Test func duplicatesInAListAreTakenOnce() {
        let out = LibraryFollow.sync([], answer: listed(["a", "b", "a"]), held: nil, at: t0)
        #expect(ids(out.albums) == ["a", "b"])
        #expect(out.added == ["a", "b"])
    }

    // MARK: absences

    @Test func anAbsentAlbumIsMissingFirstAndRemovedOnlyAtACheckTenMinutesOn() {
        let kept = following(["a", "b", "c"])
        let first = LibraryFollow.sync(kept, answer: listed(["a", "c"]), held: nil, at: t0 + minute)
        #expect(first.missing == ["b"] && first.removed.isEmpty)
        #expect(ids(first.albums) == ["a", "c", "b"], "a missing album goes after the listed ones")
        #expect(first.albums.last?.missingSince == t0 + minute)
        #expect(first.albums.last?.songs == read, "nothing of it is let go while it is only missing")

        let early = LibraryFollow.sync(first.albums, answer: listed(["a", "c"]), held: nil,
                                       at: t0 + minute + LibraryFollow.confirmAfterMs - 1)
        #expect(early.removed.isEmpty && early.missing.isEmpty, "a second absence under ten minutes waits")
        #expect(early.albums.last?.missingSince == t0 + minute, "and keeps the first mark")

        let agreed = LibraryFollow.sync(early.albums, answer: listed(["a", "c"]), held: nil,
                                        at: t0 + minute + LibraryFollow.confirmAfterMs)
        #expect(agreed.removed == ["b"], "two checks exactly ten minutes apart agree")
        #expect(ids(agreed.albums) == ["a", "c"])
    }

    @Test func aNotModifiedConfirmsAsAListDoes() {
        let kept = following(["a", "b"])
        let first = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0)
        let early = LibraryFollow.sync(first.albums, answer: .unchanged, held: nil, at: t0 + 9 * minute)
        #expect(early.removed.isEmpty && ids(early.albums) == ["a", "b"])
        let agreed = LibraryFollow.sync(early.albums, answer: .unchanged, held: nil, at: t0 + 10 * minute)
        #expect(agreed.removed == ["b"] && ids(agreed.albums) == ["a"])
        #expect(agreed.added.isEmpty && agreed.changed.isEmpty)
    }

    @Test func aNotModifiedWithNothingMissingChangesNothing() {
        let kept = following(["a", "b"])
        let out = LibraryFollow.sync(kept, answer: .unchanged, held: nil, at: t0 + 20 * minute)
        #expect(out == LibraryFollow.Outcome(albums: kept))
    }

    @Test func aMissingAlbumListedAgainIsBack() {
        let kept = following(["a", "b"])
        let first = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0)
        let again = LibraryFollow.sync(first.albums, answer: listed(["b", "a"]), held: nil, at: t0 + 20 * minute)
        #expect(again.back == ["b"] && again.removed.isEmpty)
        #expect(again.albums.allSatisfy { $0.missingSince == nil })
        #expect(again.albums.first?.songs == read, "its songs were never let go")
    }

    // MARK: removed here

    @Test func removedHereGoesAtTheNextListWithoutIt() {
        var kept = following(["a", "b"])
        kept[1].removedHere = t0 + minute
        let out = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0 + 2 * minute)
        #expect(out.removed == ["b"] && out.missing.isEmpty)
        let unchanged = LibraryFollow.sync(kept, answer: .unchanged, held: nil, at: t0 + 2 * minute)
        #expect(unchanged.removed.isEmpty, "a 304 repeats a list that had it: still listed")
    }

    @Test func removedHereIsClearedByAListAskedAfterItAndKeptByOneAskedBefore() {
        var kept = following(["a", "b"])
        kept[1].removedHere = t0 + 5 * minute
        // a check sent before the Remove answered: its list still has the album, and says nothing of the Remove
        let before = LibraryFollow.sync(kept, answer: listed(["a", "b"]), held: nil, at: t0 + 4 * minute)
        #expect(before.albums[1].removedHere == t0 + 5 * minute)
        // one sent after: the album is listed, so the Remove didn't take (or it was added again)
        let after = LibraryFollow.sync(kept, answer: listed(["a", "b"]), held: nil, at: t0 + 5 * minute)
        #expect(after.albums[1].removedHere == nil)
        let notModified = LibraryFollow.sync(kept, answer: .unchanged, held: nil, at: t0 + 6 * minute)
        #expect(notModified.albums[1].removedHere == nil)
    }

    // MARK: held back

    @Test func anEmptyListMarksNothingAndConfirmsNothing() {
        let kept = following(["a", "b"])
        let first = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0)
        let empty = LibraryFollow.sync(first.albums, answer: listed([]), held: nil, at: t0 + 30 * minute)
        #expect(empty.held == .empty(kept: 2))
        #expect(empty.removed.isEmpty && empty.missing.isEmpty)
        #expect(ids(empty.albums) == ["a", "b"])
        #expect(empty.albums[0].missingSince == nil, "the listed album isn't marked")
        #expect(empty.albums[1].missingSince == t0, "the pending mark survives, unconfirmed")
        #expect(empty.held?.isQuestion == true)
    }

    @Test func anEmptyListToAnEmptyLibraryIsNotHeld() {
        let out = LibraryFollow.sync([], answer: listed([]), held: nil, at: t0)
        #expect(out.held == nil && out.albums.isEmpty)
    }

    @Test func aDropOfMoreThanHalfAndMoreThanTenIsHeld() {
        let all = (0..<20).map { "a\($0)" }
        let kept = following(all)
        let out = LibraryFollow.sync(kept, answer: listed(Array(all.prefix(9))), held: nil, at: t0 + minute)
        #expect(out.held == .drop(gone: 11, of: 20))
        #expect(out.missing.isEmpty && out.removed.isEmpty && out.albums.count == 20)
        #expect(out.held?.isQuestion == true)
    }

    @Test func exactlyHalfOrExactlyTenIsBelieved() {
        let twentyTwo = (0..<22).map { "a\($0)" }
        let half = LibraryFollow.sync(following(twentyTwo), answer: listed(Array(twentyTwo.prefix(11))), held: nil,
                                      at: t0 + minute)
        #expect(half.held == nil && half.missing.count == 11, "11 of 22 is half, not more")
        let twelve = (0..<12).map { "a\($0)" }
        let ten = LibraryFollow.sync(following(twelve), answer: listed(Array(twelve.prefix(2))), held: nil,
                                     at: t0 + minute)
        #expect(ten.held == nil && ten.missing.count == 10, "10 is not more than 10")
    }

    @Test func removedHereAlbumsDontCountTowardsADrop() {
        var kept = following((0..<20).map { "a\($0)" })
        for i in 9..<20 { kept[i].removedHere = t0 }
        let out = LibraryFollow.sync(kept, answer: listed((0..<9).map { "a\($0)" }), held: nil, at: t0 + minute)
        #expect(out.held == nil)
        #expect(out.removed.count == 11)
    }

    @Test func aTruncatedListMarksNothingAndIsNoQuestion() {
        let kept = following(["a", "b", "c"])
        let first = LibraryFollow.sync(kept, answer: listed(["a", "c"]), held: nil, at: t0)
        let out = LibraryFollow.sync(first.albums, answer: listed(["a", "new"], truncated: true), held: nil,
                                     at: t0 + 30 * minute)
        #expect(out.held == .truncated && out.held?.isQuestion == false)
        #expect(out.added == ["new"], "what it lists is still added")
        #expect(out.removed.isEmpty && out.missing.isEmpty)
        #expect(Set(ids(out.albums)) == ["a", "new", "b", "c"])
    }

    @Test func aNotModifiedAfterAHeldListIsHeldToo() {
        let kept = following(["a", "b"])
        let first = LibraryFollow.sync(kept, answer: listed(["a"]), held: nil, at: t0)
        let out = LibraryFollow.sync(first.albums, answer: .unchanged, held: .empty(kept: 2), at: t0 + 30 * minute)
        #expect(out.held == .empty(kept: 2))
        #expect(out.removed.isEmpty && out.albums == first.albums)
    }

    @Test func heldReasonsRoundTripTheirWords() {
        for held: LibraryFollow.Held in [.empty(kept: 412), .drop(gone: 300, of: 412), .truncated] {
            #expect(LibraryFollow.Held(raw: held.raw) == held)
        }
        #expect(LibraryFollow.Held(raw: nil) == nil)
        #expect(LibraryFollow.Held(raw: "drop:3") == nil)
        #expect(LibraryFollow.Held(raw: "empty:x") == nil)
        #expect(LibraryFollow.Held(raw: "truncated:1") == nil)
        #expect(LibraryFollow.Held(raw: "") == nil)
    }

    // MARK: when

    @Test func eachReasonIsDueAsTheSpecSays() {
        for reason in LibraryCheck.allCases {
            #expect(LibraryFollow.due(reason, lastBegan: nil, now: t0), "the first check is always due")
        }
        for reason: LibraryCheck in [.opened, .changedHere, .byHand, .background] {
            #expect(LibraryFollow.due(reason, lastBegan: t0, now: t0))
        }
        for reason: LibraryCheck in [.front, .back] {
            #expect(!LibraryFollow.due(reason, lastBegan: t0, now: t0 + minute - 1))
            #expect(LibraryFollow.due(reason, lastBegan: t0, now: t0 + minute))
        }
        #expect(!LibraryFollow.due(.timer, lastBegan: t0, now: t0 + 15 * minute - 1))
        #expect(LibraryFollow.due(.timer, lastBegan: t0, now: t0 + 15 * minute))
    }

    // MARK: the order

    private static let utc = TimeZone(identifier: "UTC")!
    private static let now = AlbumTime.ms("2026-11-13T12:00:00Z")!

    private func placed(_ album: IndexAlbum, _ scope: AlbumScope = .yours) -> Int64? {
        LibraryFollow.placedAt(album, scope: scope, now: Self.now, zone: Self.utc)
    }

    @Test func anAlbumIsPlacedByTheLaterOfItsStarAndARecentPlay() {
        let star = "2026-10-01T00:00:00Z"
        #expect(placed(entry("a", starred: star)) == AlbumTime.ms(star))
        #expect(placed(entry("a", starred: star, played: "2026-11-10T08:00:00Z")) == AlbumTime.ms("2026-11-10T08:00:00Z"),
                "a play within 30 days, later than the star")
        #expect(placed(entry("a", starred: "2026-11-12T00:00:00Z", played: "2026-11-10T08:00:00Z")) == AlbumTime.ms("2026-11-12T00:00:00Z"),
                "a star later than the play")
        #expect(placed(entry("a", starred: star, played: "2026-10-13T11:59:59Z")) == AlbumTime.ms(star),
                "a play more than 30 days old doesn't count")
        #expect(placed(entry("a", starred: star, played: "2026-10-14T12:00:00Z")) == AlbumTime.ms("2026-10-14T12:00:00Z"),
                "exactly 30 days still counts")
        #expect(placed(entry("a", starred: star, played: "2026-12-01T00:00:00Z")) == Self.now,
                "a play dated ahead counts as now")
        #expect(placed(entry("a", played: "2026-11-01T00:00:00Z")) == AlbumTime.ms("2026-11-01T00:00:00Z"))
        #expect(placed(entry("a")) == nil)
    }

    @Test func yoursFallsBackOnCreatedAndTheCollectionReadsOnlyCreated() {
        let created = "2026-09-01T00:00:00Z"
        #expect(placed(entry("a", created: created)) == AlbumTime.ms(created))
        #expect(placed(entry("a", starred: "2026-10-01T00:00:00Z", created: created), .store) == AlbumTime.ms(created),
                "the collection is by when it got the album, never a star")
    }

    @Test func theOrderIsNewestFirstTiesInDeadwaxsOrderUndatedLast() {
        let albums = [
            FollowedAlbum(album: entry("undated1"), position: 0),
            FollowedAlbum(album: entry("old", starred: "2026-01-01T00:00:00Z"), position: 1),
            FollowedAlbum(album: entry("tieB", starred: "2026-06-01T00:00:00Z"), position: 2),
            FollowedAlbum(album: entry("played", starred: "2025-01-01T00:00:00Z", played: "2026-11-12T00:00:00Z"), position: 3),
            FollowedAlbum(album: entry("tieA", starred: "2026-06-01T00:00:00Z"), position: 4),
            FollowedAlbum(album: entry("undated0"), position: 5),
        ]
        let out = LibraryFollow.ordered(albums, scope: .yours, now: Self.now, zone: Self.utc)
        #expect(ids(out) == ["played", "tieB", "tieA", "old", "undated1", "undated0"])
    }

    @Test func toReadIsTheUnreadListedAlbumsInOrderLessThoseThatFailed() {
        var albums = following(["a", "b", "c", "d"])
        albums[1].songs = nil
        albums[2].songs = nil
        albums[3].songs = nil
        albums[3].missingSince = t0
        #expect(LibraryFollow.toRead(albums) == ["b", "c"], "a missing album is never read")
        #expect(LibraryFollow.toRead(albums, failed: ["b"]) == ["c"])
    }

    @Test func aFollowedSongIsPlannedAsItsStreamIsFetched() {
        let flac = FollowedSong(Song(id: "s", track: 2, discNumber: 1, duration: 200, suffix: "flac", size: 40_000_000))
        #expect(flac.disc == 1 && flac.track == 2)
        #expect(flac.format == "raw" && flac.bytes == 40_000_000)
        let ogg = FollowedSong(id: "o", size: 9_000_000, suffix: "ogg", duration: 200)
        #expect(ogg.format == "mp3")
        #expect(ogg.bytes == DownloadRules.expectedBytes(size: 9_000_000, transcode: true, duration: 200))
        let album = FollowedAlbum(album: entry("a"), position: 0, songs: [flac, ogg])
        #expect(album.bytes == flac.bytes + ogg.bytes)
        #expect(FollowedAlbum(album: entry("a"), position: 0).bytes == nil)
    }
}
