import Foundation
import Testing
@testable import DeadwaxCore

// The fill (phase3-autodownload.md 2.6, its tests 7): which albums of your library fit, whole, after every hand
// download - and which albums here give way.

private let gb: Int64 = 1_000_000_000

private func album(_ id: String, _ bytes: Int64?, here: Int64 = 0, keptOff: Bool = false) -> LibraryFill.AlbumFacts {
    LibraryFill.AlbumFacts(id: id, bytes: bytes, here: here, keptOff: keptOff)
}

/// Plenty of phone: 200 GB free.
private func facts(hand: Int64 = 0, toCome: Int64 = 0, limit: StorageLimit = .gb20, free: Int64 = 200 * gb) -> LibraryFill.Facts {
    LibraryFill.Facts(handBytes: hand, handToCome: toCome, limit: limit.bytes, freeSpace: free)
}

@Suite struct LibraryFillTests {
    @Test func everythingFitsWhenThereIsRoom() {
        let plan = LibraryFill.plan([album("a", 2 * gb), album("b", 3 * gb)], facts())
        #expect(plan.fits == ["a", "b"] && plan.waits.isEmpty && plan.giveWay.isEmpty)
        #expect(plan.bytes == 5 * gb && plan.allFit && plan.fit == 2 && plan.of == 2)
    }

    @Test func theLimitIsReachedInOrderAndASmallerAlbumAfterABigOneFits() {
        let plan = LibraryFill.plan([album("a", 8 * gb), album("b", 8 * gb), album("big", 6 * gb), album("small", 3 * gb)],
                                    facts())
        #expect(plan.fits == ["a", "b", "small"])
        #expect(plan.waits == ["big": .room])
        #expect(plan.bytes == 19 * gb && !plan.allFit)
    }

    @Test func handDownloadsAreTakenFromTheLimitFirst() {
        let plan = LibraryFill.plan([album("a", 8 * gb), album("b", 8 * gb)], facts(hand: 5 * gb))
        #expect(plan.fits == ["a"] && plan.waits == ["b": .room], "20 GB less 5 by hand leaves room for one")
    }

    @Test func withNoLimitThePhoneAloneDecides() {
        let plan = LibraryFill.plan([album("a", 50 * gb), album("b", 50 * gb), album("c", 50 * gb)],
                                    facts(hand: 30 * gb, limit: .none, free: 130 * gb))
        // 130 GB free less the 2 GB reserve: two albums of 50
        #expect(plan.fits == ["a", "b"] && plan.waits == ["c": .phoneFull])
    }

    @Test func anAlbumThatFitsTheLimitButNotThePhoneHoldsItsRoomUnderTheLimit() {
        // 20 GB limit; the phone has 9 GB free, 7 once its reserve is kept
        let plan = LibraryFill.plan([album("first", 5 * gb), album("phone", 10 * gb), album("after", 6 * gb),
                                     album("tiny", 1 * gb)], facts(free: 9 * gb))
        #expect(plan.waits["phone"] == .phoneFull)
        #expect(plan.waits["after"] == .room, "the phone-full album keeps its 10 GB of the limit: 5 + 10 + 6 > 20")
        #expect(plan.fits == ["first", "tiny"])
    }

    @Test func whatHandDownloadsHaveYetToReceiveIsTakenFromThePhone() {
        let plan = LibraryFill.plan([album("a", 5 * gb)], facts(hand: 5 * gb, toCome: 5 * gb, free: 11 * gb))
        // 11 free - 5 to come - 2 reserve = 4: not enough
        #expect(plan.waits == ["a": .phoneFull])
    }

    @Test func theLibrarysBytesHereAreThePhonesToGive() {
        // the phone is 1 GB free, under its reserve - 8 GB of the library is here: the bottom gives the 1 GB short
        let albums = [album("a", 4 * gb, here: 4 * gb), album("b", 3 * gb, here: 3 * gb), album("c", 2 * gb, here: 1 * gb)]
        var short = facts(free: 1 * gb)
        short.deficitConfirmed = true
        let plan = LibraryFill.plan(albums, short)
        #expect(plan.deficit == 1 * gb)
        #expect(plan.fits == ["a", "b"])
        #expect(plan.waits == ["c": .phoneFull])
        #expect(plan.giveWay == ["c"], "the phone under its reserve takes from the bottom")
        // seen once: nothing gives way yet
        let once = LibraryFill.plan(albums, facts(free: 1 * gb))
        #expect(once.fits == ["a", "b", "c"] && once.giveWay.isEmpty && once.deficit == 1 * gb)
    }

    @Test func anAlbumHereNeedsNoMoreOfThePhone() {
        // nothing free above the reserve, but the album is here whole
        let plan = LibraryFill.plan([album("a", 5 * gb, here: 5 * gb)], facts(free: 2 * gb))
        #expect(plan.fits == ["a"] && plan.giveWay.isEmpty)
    }

    @Test func aLoweredLimitGivesWayFromTheBottomAndOnlyAlbumsHere() {
        let plan = LibraryFill.plan([album("a", 4 * gb, here: 4 * gb), album("b", 4 * gb, here: 4 * gb),
                                     album("c", 4 * gb), album("d", 4 * gb, here: 2 * gb)], facts(limit: .gb5))
        #expect(plan.fits == ["a"])
        #expect(plan.waits == ["b": .room, "c": .room, "d": .room])
        #expect(plan.giveWay == ["b", "d"], "c has nothing here to give")
    }

    @Test func unreadAndKeptOffAlbumsAreSkippedAndCounted() {
        let plan = LibraryFill.plan([album("unread", nil), album("off", 3 * gb, here: 1 * gb, keptOff: true),
                                     album("a", 19 * gb), album("unreadHere", nil, here: 2 * gb)], facts())
        #expect(plan.fits == ["a"], "neither holds room under the limit")
        #expect(plan.waits == ["unread": .unread, "off": .keptOff, "unreadHere": .unread])
        #expect(plan.giveWay == ["off"], "a kept-off album here goes; an unread one is never given way")
        #expect(plan.of == 4 && plan.fit == 1)
        #expect(plan.count(.unread) == 2 && plan.count(.keptOff) == 1 && plan.count(.room) == 0)
    }

    @Test func anUnreadAlbumsBytesHereArentThePhonesToGive() {
        // 1 GB free, 3 GB of an album being read again here: not counted as room, since it isn't given way
        let plan = LibraryFill.plan([album("rereading", nil, here: 3 * gb), album("a", 2 * gb)], facts(free: 1 * gb))
        #expect(plan.waits == ["rereading": .unread, "a": .phoneFull])
        #expect(plan.giveWay.isEmpty)
    }

    @Test func anEmptyLibraryFitsNothingOfNothing() {
        let plan = LibraryFill.plan([], facts())
        #expect(plan.fit == 0 && plan.of == 0 && plan.bytes == 0)
    }

    @Test func theFillsAlbumsLeaveOutSongsWantedByHand() {
        let songs = [FollowedSong(id: "s1", size: 1 * gb, suffix: "flac"), FollowedSong(id: "s2", size: 2 * gb, suffix: "flac")]
        let read = FollowedAlbum(album: IndexAlbum(id: "a"), position: 0, songs: songs)
        let unread = FollowedAlbum(album: IndexAlbum(id: "b"), position: 1)
        let off = FollowedAlbum(album: IndexAlbum(id: "c"), position: 2, songs: [], missingSince: 5, keptOff: 9)
        let albums = LibraryFill.albums([read, unread, off], hand: ["s2"], here: ["a": 1 * gb])
        #expect(albums == [album("a", 1 * gb, here: 1 * gb), album("b", nil), album("c", 0, keptOff: true)],
                "a missing album stays in the fill until it is removed")
    }
}
