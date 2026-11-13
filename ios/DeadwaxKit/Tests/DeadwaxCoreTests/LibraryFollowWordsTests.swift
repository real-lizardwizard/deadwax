import Foundation
import Testing
@testable import DeadwaxCore

// Debug's Your library and the downloads log's library lines (phase3-autodownload.md 3.5).

private let now: Int64 = 1_800_000_000_000
private let gb: Int64 = 1_000_000_000

@Suite struct LibraryFollowWordsTests {
    @Test func timesAgoAndDurations() {
        #expect(LibraryFollowWords.ago(now - 59_999, now: now) == "just now")
        #expect(LibraryFollowWords.ago(now + 5_000, now: now) == "just now")
        #expect(LibraryFollowWords.ago(now - 60_000, now: now) == "1 min ago")
        #expect(LibraryFollowWords.ago(now - 59 * 60_000, now: now) == "59 min ago")
        #expect(LibraryFollowWords.ago(now - 3 * 3_600_000, now: now) == "3 h ago")
        #expect(LibraryFollowWords.ago(now - 72 * 3_600_000, now: now) == "3 days ago")
        #expect(LibraryFollowWords.duration(0.844) == "0.84 s")
        #expect(LibraryFollowWords.duration(252.4) == "4 min 12 s")
    }

    @Test func theLastCheckSaysWhatCameBack() {
        let listed = LibraryCheckRecord(reason: .front, result: .listed(albums: 3_010), began: now - 180_000, seconds: 0.84)
        #expect(LibraryFollowWords.lastCheck(listed, now: now) == "200 \u{00B7} 3,010 albums \u{00B7} 0.84 s \u{00B7} 3 min ago")
        let one = LibraryCheckRecord(reason: .front, result: .listed(albums: 1), began: now, seconds: 0.1)
        #expect(LibraryFollowWords.lastCheck(one, now: now).hasPrefix("200 \u{00B7} 1 album \u{00B7}"))
        let same = LibraryCheckRecord(reason: .byHand, result: .unchanged, began: now, seconds: 0.12)
        #expect(LibraryFollowWords.lastCheck(same, now: now) == "unchanged (304) \u{00B7} 0.12 s \u{00B7} just now")
        let failed = LibraryCheckRecord(reason: .timer, result: .failed("deadwax didn't answer"), began: now, seconds: 30)
        #expect(LibraryFollowWords.lastCheck(failed, now: now).hasPrefix("failed: deadwax didn't answer"))
    }

    @Test func theLogSaysEveryCountThatMoved() {
        let record = LibraryCheckRecord(reason: .front, result: .listed(albums: 3_010), began: now, seconds: 0.84)
        let outcome = LibraryFollow.Outcome(albums: [], added: ["a"], missing: ["b"], removed: ["c", "d"])
        #expect(LibraryFollowWords.logLine(record, outcome)
                == "library front: 200, 3,010 albums, 1 added, 1 missing, 2 removed (0.84 s)")
        let held = LibraryFollow.Outcome(albums: [], held: .drop(gone: 300, of: 412))
        #expect(LibraryFollowWords.logLine(record, held) == "library front: 200, 3,010 albums, held: drop:300:412 (0.84 s)")
        let failed = LibraryCheckRecord(reason: .back, result: .failed("timed out"), began: now, seconds: 30)
        #expect(LibraryFollowWords.logLine(failed, nil) == "library back: failed: timed out (30.00 s)")
    }

    @Test func theFirstReadIsTimedPerAlbum() {
        #expect(LibraryFollowWords.firstRead(seconds: 252, albums: 3_000) == "4 min 12 s for 3,000 albums \u{00B7} 84 ms each")
        #expect(LibraryFollowWords.firstRead(seconds: 0.5, albums: 0) == "0.50 s")
    }

    @Test func wouldFitSaysNOfM() {
        let some = LibraryFill.plan([.init(id: "a", bytes: 15 * gb), .init(id: "b", bytes: 10 * gb), .init(id: "c", bytes: nil)],
                                    .init(limit: StorageLimit.gb20.bytes, freeSpace: 100 * gb))
        #expect(LibraryFollowWords.wouldFit(some, limit: .gb20) == "1 of 3 fit in 20 GB")
        #expect(LibraryFollowWords.fitDetail(some) == "They take 15 GB \u{00B7} 1 over the limit \u{00B7} 1 not read yet")
        let all = LibraryFill.plan([.init(id: "a", bytes: gb)], .init(limit: nil, freeSpace: 100 * gb))
        #expect(LibraryFollowWords.wouldFit(all, limit: .none) == "All 1 fit on this phone")
        let none = LibraryFill.plan([], .init(limit: nil, freeSpace: 100 * gb))
        #expect(LibraryFollowWords.wouldFit(none, limit: .none) == "0 of 0 fit on this phone")
        let full = LibraryFill.plan([.init(id: "a", bytes: 5 * gb, here: gb), .init(id: "b", bytes: 1, keptOff: true)],
                                    .init(limit: nil, freeSpace: 2 * gb))
        #expect(LibraryFollowWords.fitDetail(full) == "They take 0 MB \u{00B7} 1 wait for room on the phone \u{00B7} 1 kept off \u{00B7} 1 would give way")
    }

    @Test func missingAndHeld() {
        let listed = FollowedAlbum(album: IndexAlbum(id: "a"), position: 0)
        var gone = FollowedAlbum(album: IndexAlbum(id: "b"), position: 1)
        gone.missingSince = now - 4 * 60_000
        var later = FollowedAlbum(album: IndexAlbum(id: "c"), position: 2)
        later.missingSince = now - 60_000
        #expect(LibraryFollowWords.missing([listed], now: now) == "None")
        #expect(LibraryFollowWords.missing([listed, gone, later], now: now) == "2 (the first 4 min ago)")
        #expect(LibraryFollowWords.held(nil) == "No")
        #expect(LibraryFollowWords.held(.empty(kept: 1_412)).contains("1,412"))
        #expect(LibraryFollowWords.held(.drop(gone: 300, of: 412)).contains("300 of 412"))
        #expect(LibraryFollowWords.held(.truncated).contains("10,000"))
        #expect(LibraryFollowWords.read(2_998, of: 3_010) == "2,998 of 3,010")
        #expect(LibraryFollowWords.scope(.yours) != LibraryFollowWords.scope(.store))
    }
}
