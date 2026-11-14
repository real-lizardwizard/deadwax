import Foundation
import Testing
@testable import DeadwaxCore

// Phase 3, slice 3 (phase3-autodownload.md 2.8, 2.9; open question 11, literal): Only while charging - the library's
// songs wait for the charger, an unplug lets their tasks go with their resume data, hand downloads never wait, and
// with it on one album at a time is handed to iOS - and the background's pure parts: when each task is asked for, and
// the runs Debug keeps.

private let gb: Int64 = 1_000_000_000
private let mb: Int64 = 1_000_000

private func hand(_ id: String, songs: Int = 2, at: Int64 = 1) -> [DownloadPlan.Asked] {
    (1...songs).map { (n: Int) -> DownloadPlan.Asked in
        DownloadPlan.Asked(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: at, origins: [.album(id)],
                           expected: mb)
    }
}

private func library(_ id: String, rank: Int, songs: Int = 5, out: Set<Int> = [], resumable: Bool = false)
    -> [DownloadPlan.Asked] {
    (1...songs).map { (n: Int) -> DownloadPlan.Asked in
        DownloadPlan.Asked(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: 0, origins: [.library],
                           expected: mb, out: out.contains(n), resumable: resumable, libraryRank: rank)
    }
}

private func facts(on: Bool, charging: Bool, reach: Reach = .online) -> DownloadPlan.Facts {
    DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 100 * gb, reach: reach, onlyWhileCharging: on,
                       charging: charging)
}

private func tasks(_ plan: [String: DownloadPlan.Decision], album: String) -> [String] {
    plan.filter { $0.key.hasPrefix(album + "-") && $0.value.task }.map(\.key).sorted()
}

@Suite struct LibraryChargingTests {
    // MARK: the wait

    @Test func unpluggedTheLibraryWaitsForTheChargerAndAHandDownloadDoesnt() {
        let songs = library("l", rank: 0) + hand("h")
        let unplugged = DownloadPlan.plan(songs, facts(on: true, charging: false))
        #expect((1...5).allSatisfy { unplugged["l-\($0)"] == DownloadPlan.Decision(wait: .charging, task: false) })
        #expect(unplugged["h-1"]?.task == true && unplugged["h-2"]?.task == true, "a hand download never waits for it")
        // a song your library and you both want is yours: it doesn't wait
        let both = DownloadPlan.Asked(id: "b-1", albumID: "b", wantedAt: 2, origins: [.library, .song], expected: mb,
                                      libraryRank: 1)
        #expect(DownloadPlan.plan([both], facts(on: true, charging: false))["b-1"]?.task == true)
        // plugged in, or the setting off: it goes
        #expect(tasks(DownloadPlan.plan(songs, facts(on: true, charging: true)), album: "l").count == 5)
        #expect(tasks(DownloadPlan.plan(songs, facts(on: false, charging: false)), album: "l").count == 5)
        #expect(!facts(on: false, charging: false).libraryWaitsToCharge && facts(on: true, charging: false).libraryWaitsToCharge)
    }

    @Test func theSharedWaitsComeFirst() {
        let plan = DownloadPlan.plan(library("l", rank: 0), facts(on: true, charging: false, reach: .unreachable))
        #expect(plan["l-1"] == DownloadPlan.Decision(wait: .deadwax, task: false))
    }

    @Test func anUnplugLetsTheLibrarysTasksGoAndKeepsTheHands() {
        let songs = library("l", rank: 0, out: [1, 2], resumable: true) + [
            DownloadPlan.Asked(id: "h-1", albumID: "h", wantedAt: 1, origins: [.album("h")], expected: mb, out: true)]
        let plan = DownloadPlan.plan(songs, facts(on: true, charging: false))
        #expect(plan["l-1"] == DownloadPlan.Decision(wait: .charging, task: false), "cancelled, its resume data kept")
        #expect(plan["l-2"] == DownloadPlan.Decision(wait: .charging, task: false))
        #expect(plan["h-1"]?.task == true)
        // what is to come is the hand's alone
        #expect(DownloadPlan.handToCome(songs, facts(on: true, charging: false)) == mb)
    }

    // MARK: one album at a time

    @Test func onlyOneAlbumIsHandedToIOSAtATime() {
        let songs = library("a", rank: 0) + library("b", rank: 1) + library("c", rank: 2)
        let plan = DownloadPlan.plan(songs, facts(on: true, charging: true))
        #expect(tasks(plan, album: "a").count == 5 && tasks(plan, album: "b").isEmpty && tasks(plan, album: "c").isEmpty)
        #expect(plan["b-1"] == DownloadPlan.Decision(wait: .queued, task: false))
        // off, the library's 20 span albums
        let off = DownloadPlan.plan(songs, facts(on: false, charging: false))
        #expect(off.values.filter(\.task).count == 15)
    }

    @Test func theBatchIsTheFirstAlbumWithATaskOutAndTheOthersAreLetGo() {
        // b has tasks out (handed to iOS before), c too; a above them has none: b stays the batch, c's are let go
        let songs = library("a", rank: 0) + library("b", rank: 1, out: [1, 2]) + library("c", rank: 2, out: [1])
        let plan = DownloadPlan.plan(songs, facts(on: true, charging: true))
        #expect(tasks(plan, album: "b") == ["b-1", "b-2", "b-3", "b-4", "b-5"], "its outs kept, the rest of it made")
        #expect(tasks(plan, album: "a").isEmpty)
        #expect(plan["c-1"] == DownloadPlan.Decision(wait: .queued, task: false), "let go, its resume data kept")
    }

    @Test func aBigAlbumIsHandedOverTwentyAtATimeAndNeverWithAnother() {
        let songs = library("big", rank: 0, songs: 30) + library("next", rank: 1)
        let plan = DownloadPlan.plan(songs, facts(on: true, charging: true))
        #expect(tasks(plan, album: "big").count == DownloadPlan.libraryMaxOut && tasks(plan, album: "next").isEmpty)
        // hand downloads beside the batch take their own slots
        let withHand = DownloadPlan.plan(songs + hand("h", songs: 10), facts(on: true, charging: true))
        #expect(tasks(withHand, album: "h").count == 10 && tasks(withHand, album: "big").count == 20)
    }

    @Test func anAlbumThatWaitsForThePhoneIsntTheBatch() {
        // a 3 GB album on a phone with 4 GB free waits phoneFull; the next small one is the batch
        let big = (1...3).map { (n: Int) -> DownloadPlan.Asked in
            DownloadPlan.Asked(id: "a-\(n)", albumID: "a", disc: 1, track: n, wantedAt: 0, origins: [.library],
                               expected: gb, libraryRank: 0)
        }
        let songs = big + library("b", rank: 1)
        let facts = DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 4 * gb, onlyWhileCharging: true, charging: true)
        let plan = DownloadPlan.plan(songs, facts)
        #expect(plan["a-1"] == DownloadPlan.Decision(wait: .phoneFull, task: false))
        #expect(tasks(plan, album: "b").count == 5)
    }

    // MARK: the power, the tasks asked for, the runs kept

    @Test func chargingIsChargingOrFullNothingElse() {
        #expect(PowerState.allCases.filter(\.charging) == [.charging, .full])
        #expect(DownloadWait.charging.rawValue == "charging" && DownloadWait(rawValue: "charging") == .charging)
        #expect(DownloadWait.charging.isTheSettings && !DownloadWait.charging.isTheNetwork)
    }

    @Test func theRefreshIsAskedWithTheSwitchOnAndTheChargersOnlyWithTheLibraryToCome() {
        // (after the review: whatever wait the songs show - LibraryBackgroundReviewTests)
        func asks(_ on: Bool, _ charging: Bool, _ toCome: Bool) -> [String: LibraryBackground.Ask] {
            LibraryBackground.asks(readable: true, on: on, onlyWhileCharging: charging, libraryToCome: toCome)
        }
        #expect(asks(false, true, true).values.allSatisfy { $0 == .cancel })
        #expect(asks(true, false, true) == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .cancel])
        #expect(asks(true, true, false) == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .cancel])
        #expect(asks(true, true, true) == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .ask])
        #expect(LibraryBackground.identifiers == ["net.lizardlounge.deadwax.library", "net.lizardlounge.deadwax.charging"])
        #expect(LibraryBackground.refreshAfterMs == 15 * 60_000 && LibraryBackground.readsPerRun == 20)
    }

    @Test func debugKeepsTheLastFiveRunsNewestFirst() {
        var runs: [LibraryBackground.Run] = []
        for n in 0..<7 {
            let run = LibraryBackground.Run(task: LibraryBackground.refreshID, began: Int64(n), seconds: 1,
                                            outcome: .ran(checked: true, read: n, downloading: 0, charging: false))
            runs = LibraryBackground.keep(run, in: runs)
        }
        #expect(runs.map(\.began) == [6, 5, 4, 3, 2])
        #expect(LibraryBackground.runs(raw: LibraryBackground.raw(runs)) == runs)
        #expect(LibraryBackground.raw([]) == nil && LibraryBackground.runs(raw: Data("nope".utf8)).isEmpty)
        let every: [LibraryBackground.Outcome] = [.ran(checked: false, read: 0, downloading: 2, charging: true), .off,
                                                  .couldntAsk, .expired]
        for outcome in every {
            let run = LibraryBackground.Run(task: LibraryBackground.chargingID, began: 1, seconds: 2, outcome: outcome)
            #expect(LibraryBackground.runs(raw: LibraryBackground.raw([run])) == [run])
        }
    }

    // MARK: the words

    @Test func theWordsSayIt() {
        #expect(DownloadWords.wait(.charging) == "Waiting for the phone to charge")
        #expect(DownloadWords.waitSetting(.charging, limit: .gb20) == "Only while charging is on - in You > Downloads.")
        #expect(AutoDownloadWords.onlyWhileCharging == "Only while charging")
        #expect(AutoDownloadWords.chargingNote(.yours)
                == "Your library's albums download only while the phone is charging. Albums you download yourself don't wait.")
        #expect(AutoDownloadWords.chargingNote(.store).hasPrefix("The collection's albums download"))
        #expect(AutoDownloadWords.everyLine.contains(AutoDownloadWords.chargingNote(.yours)))
        #expect(PowerState.allCases.map(LibraryFollowWords.power)
                == ["Not known", "Not charging", "Charging", "Full, on the charger"])
        let now: Int64 = 10 * 3_600_000
        let ran = LibraryBackground.Run(task: LibraryBackground.refreshID, began: now - 2 * 3_600_000, seconds: 4.2,
                                        outcome: .ran(checked: true, read: 3, downloading: 1, charging: true))
        #expect(LibraryFollowWords.backgroundRun(ran, now: now)
                == "Refresh \u{00B7} checked, 3 read, 1 album downloading, charging \u{00B7} 4.20 s \u{00B7} 2 h ago")
        let expired = LibraryBackground.Run(task: LibraryBackground.chargingID, began: now, seconds: 30, outcome: .expired)
        #expect(LibraryFollowWords.backgroundRun(expired, now: now) == "Charger \u{00B7} ended by iOS \u{00B7} 30.00 s \u{00B7} just now")
        let off = LibraryBackground.Run(task: LibraryBackground.refreshID, began: now, seconds: 0, outcome: .off)
        #expect(LibraryFollowWords.backgroundRun(off, now: now).contains("Download your library is off"))
        let failed = LibraryBackground.Run(task: LibraryBackground.refreshID, began: now, seconds: 1,
                                           outcome: .ran(checked: false, read: 0, downloading: 0, charging: false))
        #expect(LibraryFollowWords.backgroundRun(failed, now: now).hasPrefix("Refresh \u{00B7} check failed, not charging"))
    }
}
