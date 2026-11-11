import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/scrub.json: lib/scrub.ts - ui/test/scrub.sim.cjs's checks by name, the readout's runs of events,
/// seeded drags, and sweeps of timeAt, keyTarget and reportedPosition, each as the TypeScript answered it.
@Suite struct ScreenScrubTests {
    let fixture = try! Web.load("scrub")

    func drag(_ web: Web) -> Scrub.Drag? {
        web.isNull ? nil : Scrub.Drag(pointer: web["pointer"].int!, track: web["track"].string!, time: web["time"].num!)
    }

    func pending(_ web: Web) -> Scrub.PendingSeek? {
        web.isNull ? nil : Scrub.PendingSeek(target: web["target"].num!, since: web["since"].num!)
    }

    func reading(_ web: Web) -> Scrub.SeekReading? {
        guard !web.isNull else { return nil }
        let end = web["clockEnd"]
        return Scrub.SeekReading(asked: web["asked"].num!, length: web["length"].num!, track: web["track"].string!, said: web["said"].num,
                                 closed: web["closed"].bool!, judging: web["judging"].bool!,
                                 clockEnd: end.isNull ? nil : .init(at: end["at"].num!, position: end["position"].num!), off: web["off"].num)
    }

    func event(_ web: Web) -> Scrub.SeekEvent {
        switch web["kind"].string! {
        case "asked": return .asked(asked: web["asked"].num!, length: web["length"].num!, track: web["track"].string!)
        case "seeked": return .seeked(position: web["position"].num!)
        case "other seek": return .otherSeek
        case "song change": return .songChange
        case "failed": return .failed
        case "paused": return .paused
        case "clock": return .clock(position: web["position"].num!, at: web["at"].num!)
        default: return .ended(position: web["position"].num!, at: web["at"].num!, rate: web["rate"].num!)
        }
    }

    func compare(_ label: String, _ swift: Scrub.Drag?, _ web: Web, _ diffs: ScreenDiffs) {
        diffs.check("\(label): a drag", swift != nil, !web.isNull)
        guard let swift, !web.isNull else { return }
        diffs.check("\(label): pointer", swift.pointer, web["pointer"].int!)
        diffs.text("\(label): track", swift.track, web["track"])
        diffs.number("\(label): time", swift.time, web["time"])
    }

    func compare(_ label: String, _ swift: Scrub.SeekReading?, _ web: Web, _ diffs: ScreenDiffs) {
        diffs.check("\(label): a reading", swift != nil, !web.isNull)
        guard let swift, !web.isNull else { return }
        diffs.number("\(label): asked", swift.asked, web["asked"])
        diffs.number("\(label): length", swift.length, web["length"])
        diffs.text("\(label): track", swift.track, web["track"])
        diffs.number("\(label): said", swift.said, web["said"])
        diffs.flag("\(label): closed", swift.closed, web["closed"])
        diffs.flag("\(label): judging", swift.judging, web["judging"])
        diffs.number("\(label): clockEnd at", swift.clockEnd?.at, web["clockEnd"]["at"])
        diffs.number("\(label): clockEnd position", swift.clockEnd?.position, web["clockEnd"]["position"])
        diffs.number("\(label): off", swift.off, web["off"])
    }

    @Test func theFixtureIsThere() {
        #expect(fixture["sim"].list.count > 45)
        #expect(fixture["readings"].list.count > 100 && fixture["drags"].list.count == 60)
        expectMadeFrom(fixture, ["ui/src/lib/scrub.ts"])
    }

    @Test func theConstantsAreTheWebs() {
        let constants = fixture["constants"]
        #expect(Screens.same(Scrub.keyStep, constants["KEY_STEP_S"].num))
        #expect(Screens.same(Scrub.pageStep, constants["PAGE_STEP_S"].num))
        #expect(Screens.same(Scrub.pendingMaxMs, constants["PENDING_MAX_MS"].num))
        #expect(Screens.same(Scrub.endSlack, constants["END_SLACK_S"].num))
        #expect(Screens.same(Scrub.landedWithin, constants["LANDED_WITHIN_S"].num))
    }

    /// scrub.sim.cjs's checks, each by its name.
    @Test func theSimsChecks() {
        let diffs = ScreenDiffs()
        for check in fixture["sim"].list {
            let name = check["name"].string ?? "?"
            let args = check["args"]
            let result = check["result"]
            switch check["fn"].string! {
            case "timeAt":
                diffs.number(name, Scrub.timeAt(x: args[0].num!, left: args[1].num!, width: args[2].num!, length: args[3].num!), result)
            case "keyTarget":
                diffs.number(name, Scrub.keyTarget(args[0].string!, from: args[1].num!, length: args[2].num!), result)
            case "reportedPosition":
                diffs.number(name, Scrub.reportedPosition(pending(args[0]), position: args[1].num!, now: args[2].num!), result)
            case "shownTime":
                diffs.number(name, Scrub.shownTime(drag(args[0]), position: args[1].num!, length: args[2].num!), result)
            case "dragStart":
                compare(name, Scrub.dragStart(pointer: args[0].int!, track: args[1].string!, time: args[2].num!), result, diffs)
            case "dragMove":
                compare(name, Scrub.dragMove(drag(args[0]), pointer: args[1].int!, time: args[2].num!), result, diffs)
            case "dragEnd":
                let ended = Scrub.dragEnd(drag(args[0]), pointer: args[1].int!, how: Scrub.Release(rawValue: args[2].string!)!)
                compare(name, ended.drag, result["drag"], diffs)
                diffs.number("\(name): seek", ended.seek, result["seek"])
            case "dragFor":
                compare(name, Scrub.dragFor(drag(args[0]), track: args[1].string!), result, diffs)
            case "clock":
                diffs.text(name, Scrub.clock(args[0].num!), result)
            default:
                diffs.check("\(name): a function this test knows", check["fn"].string, "a known one")
            }
        }
        diffs.done()
    }

    @Test("a move to where it already is is the same drag (no render)")
    func theSameDrag() {
        let drag = Scrub.dragStart(pointer: 7, track: "song-a", time: 90)
        #expect(Scrub.dragMove(drag, pointer: 7, time: 90) == drag)
        #expect(Scrub.dragMove(drag, pointer: 8, time: 250) == drag)
        #expect(Scrub.dragEnd(drag, pointer: 7, how: .cancel).seek == nil)
    }

    /// The readout's runs: every reading and its words after each event - scrub.sim.cjs's readout checks by name, and
    /// seeded runs.
    @Test func seekReadingsAreTheWebs() {
        let diffs = ScreenDiffs()
        for run in fixture["readings"].list {
            let name = run["name"].string ?? "?"
            var current = reading(run["from"])
            if run["events"].list.isEmpty && !run["words"].isNull {
                diffs.text(name, Scrub.describeSeek(current), run["words"])
            }
            for (index, step) in zip(run["events"].list, run["after"].list).enumerated() {
                current = Scrub.seekStep(current, event(step.0))
                compare("\(name) after event \(index)", current, step.1["reading"], diffs)
                diffs.text("\(name) after event \(index): words", Scrub.describeSeek(current), step.1["words"])
            }
        }
        diffs.done()
    }

    @Test func seededDragsAreTheWebs() {
        let diffs = ScreenDiffs()
        for (run, steps) in fixture["drags"].list.enumerated() {
            var state: Scrub.Drag?
            for (index, step) in steps.list.enumerated() {
                let label = "drag run \(run) step \(index) (\(step["op"]))"
                switch step["op"].string! {
                case "start": state = Scrub.dragStart(pointer: step["pointer"].int!, track: step["track"].string!, time: step["time"].num!)
                case "move": state = Scrub.dragMove(state, pointer: step["pointer"].int!, time: step["time"].num!)
                case "end":
                    let ended = Scrub.dragEnd(state, pointer: step["pointer"].int!, how: Scrub.Release(rawValue: step["how"].string!)!)
                    state = ended.drag
                    diffs.number("\(label): seek", ended.seek, step["result"])
                case "for": state = Scrub.dragFor(state, track: step["track"].string!)
                default: diffs.number("\(label): shown", Scrub.shownTime(state, position: step["position"].num!, length: step["length"].num!), step["result"])
                }
                compare(label, state, step["drag"], diffs)
            }
        }
        diffs.done()
    }

    @Test func sweepsAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["timeAt"].list {
            diffs.number("timeAt(\(row[0]), \(row[1]), \(row[2]), \(row[3]))",
                         Scrub.timeAt(x: row[0].num!, left: row[1].num!, width: row[2].num!, length: row[3].num!), row[4])
        }
        for row in fixture["keys"].list {
            diffs.number("keyTarget(\(row[0]), \(row[1]), \(row[2]))", Scrub.keyTarget(row[0].string!, from: row[1].num!, length: row[2].num!), row[3])
        }
        for row in fixture["reported"].list {
            diffs.number("reportedPosition(\(row[0]), \(row[1]), \(row[2]))",
                         Scrub.reportedPosition(pending(row[0]), position: row[1].num!, now: row[2].num!), row[3])
        }
        diffs.done()
    }

    /// The phone's own rule (no 'seeked' event): a seek on its way is let go of once the engine reports within
    /// `landedWithin` of its target - closer than 1.5 s, as the readout counts a landing - or after `pendingMaxMs`.
    @Test func aSeekOnItsWayIsLetGoOfOnceItHasLanded() {
        let pending = Scrub.PendingSeek(target: 120, since: 1000)
        #expect(Scrub.landedWithin == 1.5)
        for (position, landed) in [(120.0, true), (121.49, true), (118.51, true), (121.5, false), (118.5, false), (121.51, false),
                                   (118.49, false), (25.0, false), (Double.nan, false), (Double.infinity, false)] {
            #expect(Scrub.landed(pending, position: position) == landed, "landed at \(position)")
            #expect((Scrub.settled(pending, position: position, now: 1500) == nil) == landed, "settled at \(position)")
        }
        //? landed or not, it lets go after PENDING_MAX_MS - and not before
        #expect(Scrub.settled(pending, position: 25, now: 1000 + Scrub.pendingMaxMs - 1) == pending)
        #expect(Scrub.settled(pending, position: 25, now: 1000 + Scrub.pendingMaxMs) == nil)
        #expect(Scrub.settled(nil, position: 25, now: 1500) == nil)
        //? a target of NaN never lands: it waits out its 20 s
        #expect(!Scrub.landed(Scrub.PendingSeek(target: .nan, since: 0), position: 0))
    }

    /// The scenario the rule is for: a seek to 2:00 that lands at once. With `reportedPosition` alone the thumb and both
    /// clocks stayed at 2:00 for 20 s while the song played on; let go of by `settled`, they follow the song.
    @Test func aSeekThatLandsAtOnceIsFollowed() {
        var pending: Scrub.PendingSeek? = Scrub.PendingSeek(target: 120, since: 0)
        var shown: [Double] = []
        //? the engine: its position is the target until the new place plays, then where it plays
        for (now, position) in [(0.0, 25.0), (100.0, 120.0), (1000.0, 120.3), (2000.0, 121.0), (3000.0, 122.0)] {
            pending = Scrub.settled(pending, position: position, now: now)
            shown.append(Scrub.reportedPosition(pending, position: position, now: now))
        }
        #expect(shown == [120, 120, 120.3, 121, 122])
        #expect(pending == nil)
        //? an engine still reporting where the song was keeps the target shown - the thumb never snaps back
        let waiting = Scrub.PendingSeek(target: 180, since: 0)
        #expect(Scrub.settled(waiting, position: 25, now: 3000) == waiting)
        #expect(Scrub.reportedPosition(Scrub.settled(waiting, position: 25, now: 3000), position: 25, now: 3000) == 180)
    }

    @Test func voiceOversAdjustIsTheArrows() {
        #expect(Scrub.adjusted(increment: true, from: 60, length: 300) == 65)
        #expect(Scrub.adjusted(increment: false, from: 2, length: 300) == 0)
        #expect(Scrub.adjusted(increment: true, from: 0, length: 0) == nil)
    }
}
