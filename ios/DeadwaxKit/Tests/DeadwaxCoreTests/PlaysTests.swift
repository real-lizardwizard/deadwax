import Foundation
import Testing
@testable import DeadwaxCore

/// Plays: the web's rule held to the TypeScript's own answers (Fixtures/levels/plays-vectors.json), and the
/// phone's bookkeeping around it, traced the way the engine will drive it.
@Suite struct PlayRuleTests {
    @Test func theRuleIsTheWebs() throws {
        let plays = try LevelVectors.plays()
        #expect(plays.countsAsPlayed.count > 100)
        for each in plays.countsAsPlayed {
            #expect(PlayRule.countsAsPlayed(listened: each.listened, duration: each.duration) == each.played,
                    "\(each.listened) of \(each.duration)")
        }
        for each in plays.listenedStep {
            #expect(PlayRule.listenedStep(previous: each.previous, now: each.now, elapsed: each.elapsed, rate: each.rate,
                                          seeked: each.seeked) == each.step, "\(each)")
        }
        for each in plays.splitAcrossJoin {
            let split = PlayRule.splitAcrossJoin(previous: each.previous, oldLength: each.oldLength, now: each.now,
                                                 elapsed: each.elapsed, rate: each.rate, seeked: each.seeked)
            #expect(split.before == each.split.before && split.after == each.split.after, "\(each)")
        }
        #expect(PlayRule.slack == plays.constants.LISTEN_SLACK_SECONDS)
        #expect(plays.constants.NEW_LISTEN.listen == Listen.new)
    }

    @Test func aListenIsTheWebs() throws {
        let scripts = try LevelVectors.plays().listens
        #expect(scripts.count >= 5)
        for script in scripts {
            var listen = Listen.new
            for step in script.steps {
                switch step.kind {
                case "started":
                    let (next, nowPlaying) = listen.started(atMs: try #require(step.now))
                    #expect(nowPlaying == step.nowPlaying)
                    listen = next
                case "heard":
                    let (next, submit) = listen.hearing(try #require(step.seconds), of: try #require(step.duration))
                    #expect(submit == step.submit)
                    listen = next
                default:
                    Issue.record("a step this test doesn't know: \(step.kind)")
                }
                #expect(listen == step.listen.listen)
            }
        }
    }

    @Test func theEdgesOfTheRule() {
        #expect(!PlayRule.countsAsPlayed(listened: 30, duration: 30))
        #expect(PlayRule.countsAsPlayed(listened: 15.5, duration: 31))
        #expect(!PlayRule.countsAsPlayed(listened: 239.9, duration: 1000))
        #expect(PlayRule.countsAsPlayed(listened: 240, duration: 1000))
        #expect(!PlayRule.countsAsPlayed(listened: 1000, duration: .nan))
        #expect(!PlayRule.countsAsPlayed(listened: 1000, duration: 0))
    }
}

/// A report as it goes to deadwax.
@Suite struct PlayReportTests {
    @Test func aReportsQuery() {
        func pairs(_ report: PlayReport) -> [String] { report.query.map { "\($0.0)=\($0.1)" } }
        #expect(pairs(.nowPlaying(songID: "a")) == ["submission=false"])
        #expect(pairs(.played(songID: "a", atMs: 1_700_000_000_123)) == ["submission=true", "time=1700000000123"])
        #expect(PlayReport.played(songID: "b", atMs: 1).songID == "b")
    }

    @Test func aPlaysTimeIsWholeMilliseconds() {
        #expect(ListenTracker.wallMs(Date(timeIntervalSince1970: 1_700_000_000.1239)) == 1_700_000_000_123)
        #expect(ListenTracker.wallMs(Date(timeIntervalSince1970: 0)) == 0)
    }
}

/// The tracker, fed as the engine feeds it.
@Suite struct ListenTrackerTests {
    /// Ticks once a second from `from` to `to` (positions in the song; the clock moves with them).
    static func play(_ tracker: inout ListenTracker, from: Double, to: Double, every: Double = 1, clockFrom: Double, duration: Double) -> [PlayReport] {
        var reports: [PlayReport] = []
        var position = from
        var clock = clockFrom
        while position + every <= to + 1e-9 {
            position += every
            clock += every
            if let report = tracker.tick(position: position, monotonic: clock, duration: duration) { reports.append(report) }
        }
        return reports
    }

    @Test func nowPlayingOnceAListenHasBegun() {
        var tracker = ListenTracker()
        #expect(tracker.began(wallMs: 1) == nil, "nothing playing: nothing to say")
        tracker.newListen(songID: "a", at: 0)
        #expect(tracker.began(wallMs: 1000) == .nowPlaying(songID: "a"))
        #expect(tracker.began(wallMs: 2000) == nil, "a pause carried on from is the same listen")
        #expect(tracker.listen.startedAt == 1000)
    }

    @Test func aSongIsPlayedOnceHalfOfItIsHeard() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 10)
        _ = tracker.began(wallMs: 5000)
        let reports = Self.play(&tracker, from: 0, to: 200, clockFrom: 10, duration: 200)
        #expect(reports == [.played(songID: "a", atMs: 5000)])
        #expect(tracker.listen.heard == 200 && tracker.listen.submitted)
    }

    @Test func fourMinutesIsEnoughOfALongOne() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "long", at: 0)
        _ = tracker.began(wallMs: 7)
        #expect(Self.play(&tracker, from: 0, to: 239, clockFrom: 0, duration: 1200).isEmpty)
        #expect(Self.play(&tracker, from: 239, to: 240, clockFrom: 239, duration: 1200) == [.played(songID: "long", atMs: 7)])
    }

    @Test func thirtySecondsOrLessNeverCounts() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "short", at: 0)
        _ = tracker.began(wallMs: 1)
        #expect(Self.play(&tracker, from: 0, to: 30, clockFrom: 0, duration: 30).isEmpty)
        //? and a length not known yet (0) never counts either
        tracker.newListen(songID: "unknown", at: 100)
        _ = tracker.began(wallMs: 2)
        #expect(Self.play(&tracker, from: 0, to: 300, clockFrom: 100, duration: 0).isEmpty)
    }

    @Test func nothingIsHeardBeforeItBegins() {
        //? a queue put back at 1:35, not yet played: the jump from 0 isn't heard, nor anything before Play
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0, from: 95)
        #expect(tracker.tick(position: 96, monotonic: 1, duration: 200) == nil)
        #expect(tracker.listen.heard == 0)
        _ = tracker.began(wallMs: 9000)
        #expect(Self.play(&tracker, from: 96, to: 196, clockFrom: 1, duration: 200) == [.played(songID: "a", atMs: 9000)])
        #expect(tracker.listen.heard == 100)
    }

    @Test func aSeekCountsNothing() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        _ = Self.play(&tracker, from: 0, to: 10, clockFrom: 0, duration: 200)
        tracker.seeked()
        #expect(tracker.tick(position: 150, monotonic: 11, duration: 200) == nil)
        #expect(tracker.listen.heard == 10)
        //? the next step from there counts again
        _ = tracker.tick(position: 151, monotonic: 12, duration: 200)
        #expect(tracker.listen.heard == 11)
        //? backwards counts nothing, seeked or not
        _ = tracker.tick(position: 20, monotonic: 13, duration: 200)
        #expect(tracker.listen.heard == 11)
    }

    @Test func aLockedPhonesSparseUpdatesStillCount() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        #expect(Self.play(&tracker, from: 0, to: 100, every: 5, clockFrom: 0, duration: 200) == [.played(songID: "a", atMs: 1)])
        #expect(tracker.listen.heard == 100)
        //? but a position that runs ahead of the clock counts only what the clock allows
        var ahead = ListenTracker()
        ahead.newListen(songID: "b", at: 0)
        _ = ahead.began(wallMs: 1)
        _ = ahead.tick(position: 60, monotonic: 10, duration: 200)
        #expect(ahead.listen.heard == 10.5)
    }

    @Test func aRestartIsANewListenAndCountsAgain() {
        //? previous past 3 s, play on a song that has ended, Repeat One's next time round: a new listen each
        var tracker = ListenTracker()
        var reports: [PlayReport] = []
        for round in 0..<2 {
            tracker.newListen(songID: "a", at: Double(round) * 1000)
            if let now = tracker.began(wallMs: Int64(round) * 1_000_000) { reports.append(now) }
            reports += Self.play(&tracker, from: 0, to: 120, clockFrom: Double(round) * 1000, duration: 200)
        }
        #expect(reports == [.nowPlaying(songID: "a"), .played(songID: "a", atMs: 0),
                            .nowPlaying(songID: "a"), .played(songID: "a", atMs: 1_000_000)])
    }

    @Test func aRetryFromWhereItStoppedIsTheSameListen() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        _ = Self.play(&tracker, from: 0, to: 60, clockFrom: 0, duration: 200)
        //? the stream failed at 60; the engine opens it again from there, a while later
        tracker.seeked()
        #expect(tracker.began(wallMs: 99_000) == nil)
        #expect(tracker.tick(position: 60, monotonic: 75, duration: 200) == nil)
        #expect(Self.play(&tracker, from: 60, to: 100, clockFrom: 75, duration: 200) == [.played(songID: "a", atMs: 1)])
    }

    @Test func aJoinGivesTheOldSongItsRestAndTheNewOneItsStart() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0, from: 100)
        _ = tracker.began(wallMs: 1000)
        #expect(Self.play(&tracker, from: 100, to: 199, clockFrom: 0, duration: 200).isEmpty)
        #expect(tracker.tick(position: 199.5, monotonic: 99.5, duration: 200) == nil)
        #expect(tracker.listen.heard == 99.5)
        //? the ticker first sees song b half a second in: the half second left of a crosses a's rule
        let reports = tracker.join(into: "b", oldLength: 200, newPosition: 0.5, monotonic: 100.5, newDuration: 180, wallMs: 5000)
        #expect(reports == [.played(songID: "a", atMs: 1000), .nowPlaying(songID: "b")])
        #expect(tracker.songID == "b")
        #expect(tracker.listen == Listen(heard: 0.5, startedAt: 5000, submitted: false))
        //? and b counts on from there under its own id
        #expect(Self.play(&tracker, from: 0.5, to: 90, every: 0.5, clockFrom: 100.5, duration: 180) == [.played(songID: "b", atMs: 5000)])
    }

    @Test func aJoinAfterASeekCountsNothingAcrossIt() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        _ = Self.play(&tracker, from: 0, to: 50, clockFrom: 0, duration: 200)
        tracker.seeked()
        let reports = tracker.join(into: "b", oldLength: 200, newPosition: 3, monotonic: 51, newDuration: 180, wallMs: 2)
        #expect(reports == [.nowPlaying(songID: "b")])
        #expect(tracker.listen.heard == 0)
    }

    @Test func aJoinFromASongNeverBegunSaysOnlyWhatsPlaying() {
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0, from: 199)
        let reports = tracker.join(into: "b", oldLength: 200, newPosition: 0.2, monotonic: 1, newDuration: 180, wallMs: 3)
        #expect(reports == [.nowPlaying(songID: "b")])
        //? and nothing at all once stopped
        tracker.stop()
        #expect(tracker.songID == nil)
        #expect(tracker.tick(position: 10, monotonic: 2, duration: 180) == nil)
        #expect(tracker.began(wallMs: 4) == nil)
        #expect(tracker == ListenTracker())
    }

    @Test func everyPlayCarriesItsTime() {
        //? a play is only ever made with the listen's start: no submission=true without time
        var tracker = ListenTracker()
        var reports: [PlayReport] = []
        for (index, id) in ["a", "b", "c"].enumerated() {
            tracker.newListen(songID: id, at: Double(index) * 500)
            if let now = tracker.began(wallMs: Int64(index + 1) * 10) { reports.append(now) }
            reports += Self.play(&tracker, from: 0, to: 150, clockFrom: Double(index) * 500, duration: 200)
        }
        let plays = reports.filter { if case .played = $0 { return true } else { return false } }
        #expect(plays == [.played(songID: "a", atMs: 10), .played(songID: "b", atMs: 20), .played(songID: "c", atMs: 30)])
        #expect(plays.allSatisfy { $0.query.contains { $0.0 == "time" } })
    }
}
