import Foundation
import Testing
@testable import DeadwaxCore

// Phase 3, slice 3, after its review (phase3-autodownload.md 6.8): reads a background run cut short hold the asks
// below them; the charger's task asked whatever wait the songs show; a launch that can't read its settings changes no
// request but the one it used up; a run's budget inside iOS's 30 seconds; a stalled task doesn't hold the batch.

private let gb: Int64 = 1_000_000_000
private let mb: Int64 = 1_000_000
private let minute: Int64 = 60_000

private func followed(_ id: String, _ position: Int, unread: Bool = false) -> FollowedAlbum {
    let songs = (1...2).map { (n: Int) -> FollowedSong in
        FollowedSong(id: "\(id)-\(n)", disc: 1, track: n, size: 100 * mb, suffix: "flac")
    }
    return FollowedAlbum(album: IndexAlbum(id: id, name: "Album \(id)", songCount: 2, duration: 600), position: position,
                         songs: unread ? nil : songs, readAt: unread ? nil : 1)
}

private func library(_ id: String, rank: Int, songs: Int = 3, out: Set<Int> = [], idle: [Int: Int64] = [:])
    -> [DownloadPlan.Asked] {
    (1...songs).map { (n: Int) -> DownloadPlan.Asked in
        DownloadPlan.Asked(id: "\(id)-\(n)", albumID: id, disc: 1, track: n, wantedAt: 0, origins: [.library],
                           expected: mb, out: out.contains(n), resumable: out.contains(n), libraryRank: rank,
                           idleMs: idle[n])
    }
}

private func charging(on: Bool = true) -> DownloadPlan.Facts {
    DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 100 * gb, onlyWhileCharging: on, charging: true)
}

private func tasks(_ plan: [String: DownloadPlan.Decision], album: String) -> [String] {
    plan.filter { $0.key.hasPrefix(album + "-") && $0.value.task }.map(\.key).sorted()
}

@Suite struct LibraryBackgroundReviewTests {
    // MARK: 2 - reads cut short

    @Test func readsABackgroundRunCutShortHoldTheAsksBelowThemUntilARunReadsToTheEnd() {
        let ordered = [followed("a", 0), followed("b", 1, unread: true), followed("c", 2)]
        // the run stopped by its cap: no longer running, still pending
        #expect(LibraryFollow.readsPending(running: false, cutShort: true, ordered: ordered))
        #expect(LibraryFollow.readsPending(running: true, cutShort: false, ordered: ordered))
        #expect(!LibraryFollow.readsPending(running: false, cutShort: false, ordered: ordered))
        // nothing left to read: nothing held, cut or not
        let allRead = [followed("a", 0), followed("c", 1)]
        #expect(!LibraryFollow.readsPending(running: true, cutShort: true, ordered: allRead))
        // and what that holds: c, below the unread b, isn't asked for
        let pending = LibraryFollow.readsPending(running: false, cutShort: true, ordered: ordered)
        let fill = LibraryFill.plan(LibraryFill.albums(ordered), .init(limit: nil, freeSpace: 10_000 * gb))
        let actions = LibraryDownloads.actions(ordered, fill: fill, removed: [], songs: [], readsPending: pending)
        #expect(actions.ask.map(\.album) == ["a"])
    }

    @Test func aCutHoldsUntilARunReadsToTheEndOrGivesUpOnFailures() {
        #expect(LibraryFollow.cutShort(after: .cut, was: false))
        #expect(LibraryFollow.cutShort(after: .cut, was: true))
        #expect(!LibraryFollow.cutShort(after: .toTheEnd, was: true))
        // too many failures moves on, as before: an unreadable album never holds the library
        #expect(!LibraryFollow.cutShort(after: .failures, was: true))
        // a run that couldn't ask (offline), or was stopped from outside, changes nothing
        #expect(LibraryFollow.cutShort(after: .couldntAsk, was: true))
        #expect(!LibraryFollow.cutShort(after: .couldntAsk, was: false))
    }

    // MARK: 3 - the charger's task, whatever the wait

    @Test func theChargersTaskIsAskedWhateverWaitTheSongsShow() {
        // unplugged and away (deadwax unreachable): the songs show deadwax's wait, not the charger's
        let songs = library("l", rank: 0)
        let away = DownloadPlan.Facts(bytesHere: 0, limit: nil, freeSpace: 100 * gb, reach: .unreachable,
                                      onlyWhileCharging: true, charging: false)
        #expect(DownloadPlan.plan(songs, away).values.allSatisfy { $0.wait == .deadwax })
        let toCome = LibraryBackground.libraryToCome(songs)
        #expect(toCome)
        #expect(LibraryBackground.asks(readable: true, on: true, onlyWhileCharging: true, libraryToCome: toCome)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .ask])
        // nothing of the library to come, Only while charging off, or the switch off: the charger's is cancelled
        #expect(LibraryBackground.asks(readable: true, on: true, onlyWhileCharging: true, libraryToCome: false)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .cancel])
        #expect(LibraryBackground.asks(readable: true, on: true, onlyWhileCharging: false, libraryToCome: true)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .cancel])
        #expect(LibraryBackground.asks(readable: true, on: false, onlyWhileCharging: true, libraryToCome: true)
                == [LibraryBackground.refreshID: .cancel, LibraryBackground.chargingID: .cancel])
        // the store not open yet: left as it is
        #expect(LibraryBackground.asks(readable: true, on: true, onlyWhileCharging: true, libraryToCome: nil)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .leave])
        // a song you asked for too isn't the library's to come: it never waits for the charger
        let yours = DownloadPlan.Asked(id: "y-1", albumID: "y", wantedAt: 1, origins: [.library, .song], expected: mb)
        #expect(!LibraryBackground.libraryToCome([yours]))
    }

    // MARK: 1, 8 - the request used up, a launch that can't read its settings

    @Test func aLaunchThatCantReadItsSettingsChangesNoRequestButPutsBackTheOneItUsedUp() {
        // before the first unlock every switch reads off: nothing cancelled
        #expect(LibraryBackground.asks(readable: false, on: false, onlyWhileCharging: false, libraryToCome: false)
                == [LibraryBackground.refreshID: .leave, LibraryBackground.chargingID: .leave])
        #expect(LibraryBackground.asks(readable: false, on: false, onlyWhileCharging: false, libraryToCome: false,
                                       ran: LibraryBackground.refreshID)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .leave])
        // a run asks for the next as it begins; the charger's, used up while the store isn't open, put back
        #expect(LibraryBackground.asks(readable: true, on: true, onlyWhileCharging: true, libraryToCome: nil,
                                       ran: LibraryBackground.chargingID)
                == [LibraryBackground.refreshID: .ask, LibraryBackground.chargingID: .ask])
        // ...but one the settings say isn't wanted is cancelled, used up or not
        #expect(LibraryBackground.asks(readable: true, on: false, onlyWhileCharging: true, libraryToCome: true,
                                       ran: LibraryBackground.refreshID)
                == [LibraryBackground.refreshID: .cancel, LibraryBackground.chargingID: .cancel])
        // readable: the mark a launch that read them leaves, or the phone unlocked now (a first launch ever)
        #expect(LibraryBackground.stateReadable(kept: true, protectedDataAvailable: false))
        #expect(LibraryBackground.stateReadable(kept: false, protectedDataAvailable: true))
        #expect(!LibraryBackground.stateReadable(kept: false, protectedDataAvailable: false))
    }

    // MARK: 1, 5 - the budgets

    @Test func aRunsBudgetIsWellInsideIOSsThirtySeconds() {
        #expect(LibraryBackground.openWaitMs < LibraryBackground.followMs)
        #expect(LibraryBackground.followMs < LibraryBackground.runMs)
        #expect(LibraryBackground.runMs <= 20_000 && LibraryBackground.eventsMs <= 25_000)
        // a relaunch's plan gets what its events left of one budget, never less than nothing
        #expect(LibraryBackground.left(LibraryBackground.eventsMs, elapsedMs: 5_000) == 20_000)
        #expect(LibraryBackground.left(LibraryBackground.eventsMs, elapsedMs: 25_000) == 0)
        #expect(LibraryBackground.left(LibraryBackground.eventsMs, elapsedMs: 40_000) == 0)
        #expect(LibraryBackground.left(LibraryBackground.eventsMs, elapsedMs: -3) == LibraryBackground.eventsMs)
    }

    // MARK: 4 - a stalled task

    @Test func aStalledTaskDoesntHoldTheBatchAndTheLibraryMovesOn() {
        // a's last song has hung for 30 minutes, its others here: b gets the tasks, a's is let go (resume data kept)
        let a = [DownloadPlan.Asked(id: "a-3", albumID: "a", disc: 1, track: 3, wantedAt: 0, origins: [.library],
                                    expected: mb, out: true, resumable: true, libraryRank: 0,
                                    idleMs: DownloadPlan.stallMs)]
        let songs = a + library("b", rank: 1)
        let plan = DownloadPlan.plan(songs, charging())
        #expect(plan["a-3"] == DownloadPlan.Decision(wait: .queued, task: false))
        #expect(tasks(plan, album: "b") == ["b-1", "b-2", "b-3"])
        // a minute short of it: a is still the batch
        let notYet = [DownloadPlan.Asked(id: "a-3", albumID: "a", disc: 1, track: 3, wantedAt: 0, origins: [.library],
                                         expected: mb, out: true, libraryRank: 0, idleMs: DownloadPlan.stallMs - minute)]
        let waiting = DownloadPlan.plan(notYet + library("b", rank: 1), charging())
        #expect(waiting["a-3"]?.task == true && tasks(waiting, album: "b").isEmpty)
        #expect(DownloadPlan.stallMs == 30 * minute)
    }

    @Test func aStalledTaskInAMovingBatchIsMadeAgainAndTheBatchStays() {
        // a-1 moving, a-2 hung: a stays the batch, a-2 let go (made again from its resume data at the next plan)
        let songs = library("a", rank: 0, out: [1, 2], idle: [1: 0, 2: DownloadPlan.stallMs]) + library("b", rank: 1)
        let plan = DownloadPlan.plan(songs, charging())
        #expect(plan["a-1"]?.task == true && plan["a-2"]?.task == false && plan["a-3"]?.task == true)
        #expect(tasks(plan, album: "b").isEmpty)
        // the next plan: a-2 no longer out, made again with the rest of a
        let next = library("a", rank: 0, out: [1, 3]) + library("b", rank: 1)
        #expect(tasks(DownloadPlan.plan(next, charging()), album: "a") == ["a-1", "a-2", "a-3"])
        // with Only while charging off there is no batch to hold, and a running task is never let go for it
        let off = DownloadPlan.plan(songs, charging(on: false))
        #expect(off["a-2"]?.task == true)
        // nothing known of a task's bytes is never a stall
        #expect(!library("a", rank: 0, out: [1])[0].stalled && !library("a", rank: 0, idle: [1: DownloadPlan.stallMs])[0].stalled)
    }
}
