import Testing
@testable import DeadwaxCore

/// The handover on the phone (the spec's 3.5): its arithmetic - D, the predicted start, the lead, the late target,
/// Reduce Motion's - over hand-built cases, and DeckRules with a lead: the resume asked early, taken as its own, the
/// judge from the resume. None of it is in a web trace (theirs have the lead at 0).
@Suite struct HandoverPlanTests {
    @Test func theVoicesDelayAsHeard() {
        let d = HandoverTiming.voiceDelay(clockLead: 0.004, latency: 0.012)
        #expect(d == DeckVoice.handDelayS + DeckVoice.lookaheadS + 0.004 + 0.012)
        #expect(Swift.abs(d - 0.1375) < 1e-12)
    }

    @Test func thePredictedStart() {
        #expect(HandoverTiming.predictedLocal([]) == 0.3)
        #expect(HandoverTiming.predictedLocal([0.2, 0.4, 0.25]) == 0.25)
        //? the last five only, and an even count's middle two
        #expect(HandoverTiming.predictedLocal([9, 0.1, 0.2, 0.3, 0.4, 0.5]) == 0.3)
        #expect(HandoverTiming.predictedLocal([0.2, 0.3]) == 0.25)
        //? a stream: before any, 0.3 s and a second for every 300 of position; fitted, a + b x position
        #expect(Swift.abs(HandoverTiming.predictedStream([], at: 60) - 0.5) < 1e-12)
        let line = [(position: 0.0, seconds: 0.25), (position: 100.0, seconds: 0.35), (position: 200.0, seconds: 0.45)]
        #expect(Swift.abs(HandoverTiming.predictedStream(line, at: 300) - 0.55) < 1e-12)
        //? never faster the deeper it is
        let falling = [(position: 0.0, seconds: 0.5), (position: 100.0, seconds: 0.3)]
        #expect(Swift.abs(HandoverTiming.predictedStream(falling, at: 300) - 0.4) < 1e-12)
        #expect(HandoverTiming.lead(predicted: 0.3, voiceDelay: 0.14) == 0.3 - 0.14)
        #expect(HandoverTiming.lead(predicted: 0.1, voiceDelay: 0.14) == 0)
        #expect(HandoverTiming.holdsAcross(predicted: 0.4, planSeconds: 1.2))
        #expect(!HandoverTiming.holdsAcross(predicted: 2.5, planSeconds: 1.2))
    }

    @Test func theTargets() {
        let plans = PlatterPlans(PlatformMaths())
        let plan = plans.motor(100, -3, 425, 1)
        #expect(plan.duration > 0.3)
        //? resumed 0.1 s into the plan with a lead of 0.15: where the plan has the record 0.25 s in
        let early = HandoverTiming.lateTarget(plan, plans, sinceMs: 1000, resumeMs: 1100, lead: 0.15, speed: 1)
        #expect(early == plans.planAt(plan, 0.25).x)
        //? resumed past the plan's end: carried on at the player's speed
        let late = HandoverTiming.lateTarget(plan, plans, sinceMs: 1000, resumeMs: 1000 + plan.duration * 1000 + 50, lead: 0.2, speed: 1.5)
        #expect(Swift.abs(late - (plan.x + 1.5 * 0.25)) < 1e-9)
        #expect(HandoverTiming.reducedTarget(planX: 80, speed: 2, lead: 0.15) == 80.3)
    }

    /// A world with a window round 60, the song playing there.
    func world() -> TraceWorld {
        let song = DeckSong(id: "time", length: 425, flac: true, kind: "FLAC")
        let world = TraceWorld(DeckRulesTests.Case(name: "lead", songs: [song], words: [], inputs: [], stamps: [:], count: 0, spans: [], whole: nil))
        world.set(song: 0, playing: 1, at: 60, ready: 1, made: 1)
        world.time = 1000
        return world
    }

    func answer(_ world: TraceWorld) {
        let window = DeckWindow(channels: [world.zeros(40 * 48000)], start: 56, end: 96, rate: 48000, source: .file, bytes: 1, madeIn: 0)
        world.asks.last?(.success(window))
    }

    @Test func aLeadResumesTheSongEarlyAndItsPlayIsItsOwn() throws {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        rules.handoverLead = { _, _ in 0.2 }
        rules.setShowing(true)
        answer(world)
        rules.pressed(1000)
        world.time = 1300
        rules.takeOver(1300)
        rules.playingChanged(false)
        for k in 1...6 {
            world.time = 1300 + Double(k) * 10
            rules.hand(world.time, turned: -0.02 * Double(k), at: 60 - 0.006 * Double(k))
        }
        world.effects = []
        let out = rules.release(world.time, cancel: false)
        #expect(out.play == false && out.seek != nil)
        //? the plan's end on its timer, and the resume 200 ms before it
        let timers = world.effects.filter { $0.hasPrefix("timer ") }
        #expect(timers.count == 2, "\(world.effects)")
        let ms = timers.map { Double(bitPattern: UInt64($0.split(separator: " ")[2], radix: 16)!) }
        #expect(Swift.abs(ms[1] - (ms[0] - 200)) < 1e-9, "\(ms)")
        let resumeTimer = Int(timers[1].split(separator: " ")[1])!
        world.effects = []
        world.time += ms[1]
        world.timers.removeValue(forKey: resumeTimer)?()
        #expect(world.effects.contains("resume") && rules.resumeAsked)
        //? the player says it plays: the deck's own resume - nothing fades, the plan runs on
        world.effects = []
        rules.playingChanged(true)
        #expect(!rules.resumeAsked && !world.effects.contains { $0.hasPrefix("post fade") })
        //? the song heard past where it was sought: the record's sound fades, before the plan's end
        world.effects = []
        world.at = out.seek! + 0.03
        for listener in world.listeners { listener.run(world.at) }
        #expect(world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
    }

    @Test func aLeadTooLateForTheTimerSeeksAhead() {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        //? a lead longer than any plan: resumed at once, sought to where the record will be when the song is heard
        rules.handoverLead = { _, _ in 5 }
        rules.setShowing(true)
        answer(world)
        rules.pressed(1000)
        world.time = 1300
        rules.takeOver(1300)
        world.time = 1310
        rules.hand(1310, turned: -0.02, at: 59.99)
        let out = rules.release(1312, cancel: false)
        #expect(out.play)
        #expect(rules.resumeAsked)
        #expect((out.seek ?? 0) > 59.99 + 3, "carried on past the plan's end at speed: \(out.seek ?? .nan)")
    }

    @Test func reduceMotionWithALeadTakesAtTheLanding() {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: true)
        rules.handoverLead = { _, _ in 0.15 }
        rules.setShowing(true)
        answer(world)
        rules.pressed(1000)
        world.time = 1300
        rules.takeOver(1300)
        world.effects = []
        let out = rules.release(1300, cancel: false)
        #expect(out.play)
        #expect(world.effects.first == "post stop" && world.effects.contains { $0.hasPrefix("post take ") }, "\(world.effects)")
        //? a release from rest: the landing is the motor's from there, the song sought 0.15 s on at speed
        let landing = PlatterPlans(PlatformMaths()).motor(60, 0, 425, 1).x
        #expect(Swift.abs((out.seek ?? 0) - (landing + 0.15)) < 1e-9, "\(out.seek ?? .nan)")
    }

    @Test func withNoLeadTheWebsShortcutStands() {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: true)
        rules.setShowing(true)
        answer(world)
        rules.pressed(1000)
        world.time = 1300
        rules.takeOver(1300)
        let out = rules.release(1300, cancel: false)
        #expect(out.play && out.seek == PlatterPlans(PlatformMaths()).motor(60, 0, 425, 1).x)
        #expect(!rules.resumeAsked)
    }
}
