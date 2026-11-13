import Foundation
import Testing
@testable import DeadwaxCore

// The planner's library units (phase3-autodownload.md 2.7, slice 2): after every hand unit, in the fill's order, their
// room the fill's - only the phone's reserve checked here; a hand unit's room counts the hand downloads alone.

private let gb: Int64 = 1_000_000_000

private func hand(_ id: String, songs: Int = 2, each: Int64 = gb, at: Int64) -> [DownloadPlan.Asked] {
    (1...songs).map { n in
        DownloadPlan.Asked(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: at, origins: [.album(id)], expected: each)
    }
}

private func library(_ id: String, rank: Int, songs: Int = 2, each: Int64 = gb, at: Int64 = 0,
                     out: Bool = false) -> [DownloadPlan.Asked] {
    (1...songs).map { n in
        DownloadPlan.Asked(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: at, origins: [.library],
                           expected: each, out: out, libraryRank: rank)
    }
}

private func facts(here: Int64 = 0, libraryHere: Int64 = 0, limit: StorageLimit = .gb20, free: Int64 = 100 * gb,
                   reach: Reach = .online) -> DownloadPlan.Facts {
    DownloadPlan.Facts(bytesHere: here, libraryHere: libraryHere, limit: limit.bytes, freeSpace: free, reach: reach)
}

@Suite struct LibraryPlanTests {
    @Test func aSongOnlyTheLibraryWantsIsPlannedWithItsAlbumInALibraryUnit() {
        let only = DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.library], expected: 1)
        #expect(only.unit == "library:al" && only.isLibrary)
        let both = DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.library, .album("al")], expected: 1)
        #expect(both.unit == "album:al" && !both.isLibrary, "a song also asked for by hand is planned as the hand's")
        let alone = DownloadPlan.Asked(id: "s", albumID: "al", wantedAt: 1, origins: [.library, .song], expected: 1)
        #expect(alone.unit == "song:s")
    }

    @Test func libraryUnitsComeAfterEveryHandUnitInTheFillsOrder() {
        let songs = library("second", rank: 1, at: 1) + library("first", rank: 0, at: 2) + hand("late", at: 99)
        let walked = DownloadPlan.walk(songs, facts())
        #expect(walked.order == ["album:late", "library:first", "library:second"])
    }

    @Test func aLibraryUnitsRoomIsTheFillsOnlyThePhoneIsChecked() {
        // 19 GB here by hand: a hand unit of 2 GB waits for room - the library's, decided by the fill, doesn't
        let plan = DownloadPlan.plan(hand("h", at: 1) + library("l", rank: 0), facts(here: 19 * gb))
        #expect(plan["h-1"]?.wait == .room)
        #expect(plan["l-1"] == DownloadPlan.Decision(wait: .queued, task: true))
        // the phone under its reserve holds it
        let full = DownloadPlan.plan(library("l", rank: 0), facts(limit: .none, free: 3 * gb))
        #expect(full["l-1"] == DownloadPlan.Decision(wait: .phoneFull, task: false))
    }

    @Test func aHandUnitFitsAgainstTheHandDownloadsAloneTheLibrarysBytesAreItsToGiveBack() {
        // 19 GB here, 15 of it the library's: a 2 GB hand album fits the 20 GB limit
        let plan = DownloadPlan.plan(hand("h", at: 1), facts(here: 19 * gb, libraryHere: 15 * gb))
        #expect(plan["h-1"]?.task == true)
        // and on a phone with 1 GB free, the library's 15 GB here are counted as the room it will make
        let phone = DownloadPlan.plan(hand("h", at: 1), facts(here: 19 * gb, libraryHere: 15 * gb, limit: .none, free: gb))
        #expect(phone["h-1"]?.task == true)
        #expect(DownloadPlan.plan(hand("h", at: 1), facts(here: 19 * gb, limit: .none, free: gb))["h-1"]?.wait == .phoneFull)
    }

    @Test func aLibraryUnitWaitsForTheHandDownloadsAheadOfItOnThePhone() {
        // 6 GB free: the hand album's 2 GB leave 4, so 2 GB over the reserve - one library album of 2 GB, not two
        let plan = DownloadPlan.plan(hand("h", at: 1) + library("a", rank: 0) + library("b", rank: 1),
                                     facts(limit: .none, free: 6 * gb))
        #expect(plan["h-1"]?.task == true && plan["a-1"]?.task == true)
        #expect(plan["b-1"]?.wait == .phoneFull)
    }

    @Test func aStartedLibraryUnitGoesOn() {
        let plan = DownloadPlan.plan(library("l", rank: 0, out: true), facts(limit: .none, free: gb))
        #expect(plan["l-1"]?.task == true)
    }

    @Test func libraryUnitsShareTheWaitsAndTheHundredTasks() {
        let offline = DownloadPlan.plan(library("l", rank: 0), facts(reach: .unreachable))
        #expect(offline["l-1"] == DownloadPlan.Decision(wait: .deadwax, task: false))
        let many = (0..<60).flatMap { library("l\($0)", rank: $0) } + hand("h", songs: 50, each: 1, at: 1)
        let plan = DownloadPlan.plan(many, facts(limit: .none))
        #expect(plan.values.filter(\.task).count == DownloadPlan.maxOut)
        #expect((1...50).allSatisfy { plan["h-\($0)"]?.task == true }, "the hand's first")
    }

    @Test func handToComeIsWhatTheHandUnitsThatFitHaveYetToReceive() {
        let received = DownloadPlan.Asked(id: "r-1", albumID: "r", wantedAt: 0, origins: [.song], expected: 3 * gb,
                                          received: gb)
        let songs = hand("h", at: 1) + hand("big", songs: 1, each: 30 * gb, at: 2) + library("l", rank: 0) + [received]
        #expect(DownloadPlan.handToCome(songs, facts()) == 2 * gb + 2 * gb, "the big one waits; the library's aren't the hand's")
    }
}
