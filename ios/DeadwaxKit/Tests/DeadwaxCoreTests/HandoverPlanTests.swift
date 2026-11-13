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

    /// (slice 3, slice 2's review question 2) The deck engine made the voice again at a new output rate: the window it
    /// had is gone, so the rules ask for one again where the record is - and a press meanwhile is silent, not sounding a
    /// window the voice no longer has.
    @Test func aDroppedWindowIsAskedForAgain() {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        rules.setShowing(true)
        #expect(world.asks.count == 1)
        answer(world)
        #expect(rules.live(), "the window in: a press sounds")
        world.time += 10
        rules.windowDropped()
        #expect(world.asks.count == 2, "asked again")
        #expect(!rules.live(), "until it comes, a press is silent")
        answer(world)
        #expect(rules.live())
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

    /// A post's numbers, in order: a take's at, rate, time and until; a drive's at, rate, accel (nil for "-"),
    /// time and until.
    func numbers(_ effect: String) -> [Double?] {
        effect.split(separator: " ").dropFirst(2).map { $0 == "-" ? nil : Double(bitPattern: UInt64($0, radix: 16)!) }
    }

    /// The song heard at `at`: the engine's report, to every listener (the judge among them).
    func heard(_ world: TraceWorld, _ at: Double) {
        world.at = at
        for listener in world.listeners { listener.run(at) }
    }

    /// A playing record held at 60 from 1300, turned a little back over 60 ms and let go, the lead as given - the
    /// window answered first, or left for later. The release's answer; the plan's timer and its end (page ms); the
    /// second timer set - the resume's, when the lead leaves time for one (the judge's, when it doesn't).
    func letGo(_ world: TraceWorld, _ rules: DeckRules<PlatformMaths>, lead: Double, answered: Bool = true)
        -> (out: DeckReleased, plan: Int?, end: Double, resume: Int?) {
        rules.handoverLead = { _, _ in lead }
        rules.setShowing(true)
        if answered { answer(world) }
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
        let timers = world.effects.filter { $0.hasPrefix("timer ") }.map { $0.split(separator: " ") }
        let key = { (i: Int) -> Int? in i < timers.count ? Int(timers[i][1])! : nil }
        let ms = timers.first.map { Double(bitPattern: UInt64($0[2], radix: 16)!) } ?? .nan
        return (out, key(0), world.time + ms, key(1))
    }

    @Test func reduceMotionsTakeHoldsUntilTheSongIsHeard() throws {
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
        let take = try #require(world.effects.first { $0.hasPrefix("post take ") })
        let n = numbers(take)
        let landing = PlatterPlans(PlatformMaths()).motor(60, 0, 425, 1).x
        #expect(n[0] == landing && n[1] == 1 && n[2] == 1.3)
        //? held until the judge hears the song - not a take's 0.12 s, which would go still for the lead's rest
        #expect(Swift.abs(n[3]! - n[2]! - DeckConstants.handoverMaxS) < 1e-9, "\(take)")
        //? the gesture's play: paused where it was sought, nothing fades; heard past it, the voice fades
        world.isPlaying = true
        rules.playingChanged(true)
        world.effects = []
        heard(world, out.seek!)
        #expect(!world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
        heard(world, out.seek! + 0.03)
        #expect(world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
    }

    @Test func aLateResumeIsJudgedAtItsTargetAndEndsThePlan() throws {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        let (out, plan, _, _) = letGo(world, rules, lead: 5)
        //? played in the gesture, no timer asks it: its second timer is the judge's HANDOVER_MAX_S
        #expect(out.play && rules.resumeAsked && rules.ledTimer == nil && !world.effects.contains("resume"))
        let target = try #require(out.seek)
        //? the gesture's play is the deck's own: the plan runs on
        world.isPlaying = true
        rules.playingChanged(true)
        guard case .plan = rules.motion else { Issue.record("the plan ended at the play"); return }
        //? the song still where it was sought, far past plan.x: a judge at plan.x would fade the voice here
        world.effects = []
        heard(world, target)
        #expect(!world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
        //? heard past its target before the plan's end: the coast is over - faded, turning, the plan's timer gone
        heard(world, target + 0.03)
        #expect(world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
        guard case .turning = rules.motion else { Issue.record("not turning: \(rules.motion)"); return }
        let planKey = try #require(plan)
        #expect(rules.planTimer == nil && world.timers[planKey] == nil, "\(world.effects)")
        #expect(!world.effects.contains("resume"))
    }

    @Test func aPlanResumedEarlyHoldsAtItsEndAndAsksNoSecondResume() throws {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        let (out, plan, end, resume) = letGo(world, rules, lead: 0.2)
        let x = try #require(out.seek)
        world.time = end - 200
        world.timers.removeValue(forKey: try #require(resume))?()
        rules.playingChanged(true)
        //? the song paused at plan.x, not yet heard: the judge waits
        world.effects = []
        heard(world, x)
        #expect(!world.effects.contains { $0.hasPrefix("post fade") })
        //? the plan's end: only the hold - the song's speed from plan.x, stamped at the end, HANDOVER_MAX_S long
        world.time = end
        world.timers.removeValue(forKey: try #require(plan))?()
        #expect(!world.effects.contains("resume") && !rules.resumeAsked, "\(world.effects)")
        let drives = world.effects.filter { $0.hasPrefix("post drive ") }
        #expect(drives.count == 1, "\(world.effects)")
        let n = numbers(try #require(drives.first))
        #expect(n[0] == x && n[1] == 1 && n[2] == nil)
        #expect(Swift.abs(n[3]! - end / 1000) < 1e-9 && Swift.abs(n[4]! - n[3]! - DeckConstants.handoverMaxS) < 1e-9)
        guard case .turning = rules.motion else { Issue.record("not turning: \(rules.motion)"); return }
        heard(world, x + 0.03)
        #expect(world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
    }

    @Test func aResumeAskedForOnePlanIsNotTheNexts() throws {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        let (_, _, end, resume) = letGo(world, rules, lead: 0.2)
        world.time = end - 200
        world.timers.removeValue(forKey: try #require(resume))?()
        #expect(rules.resumeAsked)
        //? taken again before the player says it plays, and let go again: a new plan, whose resume is still to come
        rules.pressed(world.time)
        rules.takeOver(world.time)
        for k in 1...6 {
            world.time += 10
            rules.hand(world.time, turned: -0.02 * Double(k), at: 60 - 0.006 * Double(k))
        }
        let out = rules.release(world.time, cancel: false)
        #expect(!out.play)
        guard case .plan = rules.motion else { Issue.record("no new plan: \(rules.motion)"); return }
        #expect(!rules.resumeAsked)
    }

    @Test func aPlanThatSoundsOnlyAfterItsResumeIsStillHandedOver() throws {
        let world = world()
        let rules = DeckRules(host: world, clock: world, maths: PlatformMaths(), reduced: false)
        let (out, plan, end, resume) = letGo(world, rules, lead: 0.2, answered: false)
        let x = try #require(out.seek)
        //? the resume, with no window yet: no judge
        world.effects = []
        world.time = end - 200
        world.timers.removeValue(forKey: try #require(resume))?()
        rules.playingChanged(true)
        #expect(world.effects.contains("resume") && !world.effects.contains("listen"), "\(world.effects)")
        //? the window comes in the plan's last 200 ms: the record's sound takes up the coast
        world.time = end - 100
        world.effects = []
        answer(world)
        #expect(world.effects.contains { $0.hasPrefix("post take ") }, "\(world.effects)")
        //? at the plan's end the judge starts, and the voice holds the song's speed from plan.x
        world.effects = []
        world.time = end
        world.timers.removeValue(forKey: try #require(plan))?()
        #expect(world.effects.contains("listen") && !world.effects.contains("resume"), "\(world.effects)")
        let drive = try #require(world.effects.first { $0.hasPrefix("post drive ") })
        #expect(numbers(drive)[0] == x)
        heard(world, x)
        #expect(!world.effects.contains { $0.hasPrefix("post fade") })
        heard(world, x + 0.03)
        #expect(world.effects.contains { $0.hasPrefix("post fade") }, "\(world.effects)")
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
