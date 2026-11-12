import Foundation
import Testing
@testable import DeadwaxCore

/// The platter (Platter.swift) against lib/platter.ts's own answers (Fixtures/deck/platter.json), bit for bit over the
/// web's recorded exp and log: deck.sim's 54 flicks, each plan and where it has the record at 33 times, each phase on
/// its own, the plans at the odd ends, the hand's speed over deck.sim's sample sets, and the pull.
@Suite struct PlatterTests {
    let fixture: JSONValue
    let maths: RecordedMaths
    let plans: PlatterPlans<RecordedMaths>

    init() throws {
        fixture = try DeckFixtures.json("platter.json")
        maths = DeckFixtures.maths()
        plans = PlatterPlans(maths)
    }

    func phase(_ json: JSONValue) -> PlatterPhase? {
        guard let fields = json.array, let kind = fields.first?.string else { return nil }
        let n = { (i: Int) in DeckFixtures.number(fields[i]) }
        switch kind {
        case "pull": return .pull(x0: n(1), v0: n(2), a: n(3), duration: n(4))
        case "decay": return .decay(x0: n(1), v0: n(2), base: n(3), sign: fields[4].double ?? .nan, c: n(5), k: n(6), duration: n(7))
        case "rest": return .rest(x0: n(1), duration: n(2))
        default: return nil
        }
    }

    func samePhase(_ a: PlatterPhase, _ b: PlatterPhase) -> Bool {
        switch (a, b) {
        case let (.pull(x0, v0, acc, d), .pull(y0, w0, bcc, e)):
            return DeckFixtures.same(x0, y0) && DeckFixtures.same(v0, w0) && DeckFixtures.same(acc, bcc) && DeckFixtures.same(d, e)
        case let (.decay(x0, v0, base, sign, c, k, d), .decay(y0, w0, base2, sign2, c2, k2, e)):
            return DeckFixtures.same(x0, y0) && DeckFixtures.same(v0, w0) && DeckFixtures.same(base, base2) && sign == sign2
                && DeckFixtures.same(c, c2) && DeckFixtures.same(k, k2) && DeckFixtures.same(d, e)
        case let (.rest(x0, d), .rest(y0, e)):
            return DeckFixtures.same(x0, y0) && DeckFixtures.same(d, e)
        default:
            return false
        }
    }

    /// A plan against the web's, field by field.
    func expectPlan(_ plan: Plan, _ want: JSONValue?, _ what: String) {
        guard let want else { Issue.record("\(what): no plan in the fixture"); return }
        let phases = (want["phases"]?.array ?? []).compactMap(phase)
        #expect(plan.phases.count == phases.count, "\(what): phases")
        for (mine, theirs) in zip(plan.phases, phases) {
            #expect(samePhase(mine, theirs), "\(what): \(mine) is not the web's \(theirs)")
        }
        #expect(DeckFixtures.same(plan.duration, DeckFixtures.number(want["duration"])), "\(what): duration")
        #expect(DeckFixtures.same(plan.x, DeckFixtures.number(want["x"])), "\(what): x")
        #expect(DeckFixtures.same(plan.v, DeckFixtures.number(want["v"])), "\(what): v")
        #expect(DeckFixtures.same(plan.target, DeckFixtures.number(want["target"])), "\(what): target")
        #expect(plan.clamped?.rawValue == want["clamped"]?.string, "\(what): clamped")
    }

    @Test func theConstantsAreTheWebs() {
        let constants = fixture["constants"]
        let mine: [(String, Double)] = [
            ("SPIN_UP_S", Platter.spinUpS), ("SPIN_DOWN_S", Platter.spinDownS), ("MOTOR_PULL", Platter.motorPull),
            ("FRICTION_VISCOUS", Platter.frictionViscous), ("FRICTION_DRY", plans.frictionDry), ("END_MARGIN_S", Platter.endMarginS),
            ("VELOCITY_WINDOW_MS", Platter.velocityWindowMs), ("MAX_SPEED", Platter.maxSpeed),
            ("DEGREES_PER_SECOND", Platter.degreesPerSecond), ("RELEASE_TAIL_MS", Platter.releaseTailMs),
        ]
        for (name, value) in mine {
            #expect(DeckFixtures.same(value, DeckFixtures.number(constants?[name])), "\(name)")
        }
    }

    @Test func everyFlickIsTheWebsPlanAndCourse() {
        let flicks = fixture["flicks"]?.array ?? []
        let motored = flicks.filter { $0["motor"]?.bool == true }.count
        #expect(flicks.count - motored + motored / 5 == 54, "deck.sim's 54 flicks, each motored one at five targets")
        for (i, flick) in flicks.enumerated() {
            let x = DeckFixtures.number(flick["x"]), v = DeckFixtures.number(flick["v"])
            let motor = flick["motor"]?.bool == true
            let target = DeckFixtures.double(flick["target"])
            let plan = motor ? plans.motor(x, v, 425, target ?? 1) : plans.coast(x, v, 425)
            let what = "flick \(i) (x \(x), v \(v), \(motor ? "motor to \(target ?? 1)" : "coasting"))"
            expectPlan(plan, flick["plan"], what)
            let course = DeckFixtures.doubles(flick["at"]?.string)
            #expect(course.count == 33 * 3, "\(what): the course")
            for k in stride(from: 0, to: course.count - 2, by: 3) {
                let at = plans.planAt(plan, course[k])
                #expect(DeckFixtures.same(at.x, course[k + 1]) && DeckFixtures.same(at.v, course[k + 2]),
                        "\(what): planAt(\(course[k])) is (\(course[k + 1]), \(course[k + 2])), not (\(at.x), \(at.v))")
            }
            for (p, phaseCourse) in (flick["phases"]?.array ?? []).enumerated() where p < plan.phases.count {
                let points = DeckFixtures.doubles(phaseCourse.string)
                for k in stride(from: 0, to: points.count - 2, by: 3) {
                    let at = plans.phaseAt(plan.phases[p], points[k])
                    #expect(DeckFixtures.same(at.x, points[k + 1]) && DeckFixtures.same(at.v, points[k + 2]), "\(what): phase \(p) at \(points[k])")
                }
            }
        }
        #expect(maths.missed.isEmpty, "the platter asked Math what the web never did: \(maths.missed.prefix(5))")
    }

    @Test func theOddEnds() {
        for (i, row) in (fixture["odd"]?.array ?? []).enumerated() {
            let x = DeckFixtures.number(row["x"]), v = DeckFixtures.number(row["v"])
            let length = DeckFixtures.number(row["length"]), target = DeckFixtures.number(row["target"])
            expectPlan(plans.motor(x, v, length, target), row["motor"], "odd \(i) motor (x \(x), v \(v), length \(length))")
            expectPlan(plans.coast(x, v, length), row["coast"], "odd \(i) coast (x \(x), v \(v), length \(length))")
        }
        #expect(maths.missed.isEmpty, "\(maths.missed.prefix(5))")
    }

    @Test func theHandsSpeed() {
        let sets = fixture["speeds"]?.array ?? []
        #expect(sets.count == 7)
        for set in sets {
            let samples = (set["samples"]?.array ?? []).map {
                HandSample(time: DeckFixtures.number($0.array?[0]), turned: DeckFixtures.number($0.array?[1]))
            }
            let name = set["name"]?.string ?? "?"
            for row in set["at"]?.array ?? [] {
                let r = row.array ?? []
                let time = DeckFixtures.number(r[0])
                #expect(DeckFixtures.same(Platter.handSpeed(samples, time), DeckFixtures.number(r[1])), "\(name): handSpeed at \(time)")
                #expect(DeckFixtures.same(Platter.releaseSpeed(samples, time), DeckFixtures.number(r[2])), "\(name): releaseSpeed at \(time)")
                #expect(DeckFixtures.same(Platter.handSpeed(samples, time, windowMs: 45), DeckFixtures.number(r[3])), "\(name): handSpeed 45 at \(time)")
                #expect(DeckFixtures.same(Platter.releaseSpeed(samples, time, windowMs: 45, tailMs: 10), DeckFixtures.number(r[4])),
                        "\(name): releaseSpeed 45/10 at \(time)")
            }
        }
    }

    @Test func thePull() {
        for row in fixture["acceleration"]?.array ?? [] {
            let r = row.array ?? []
            let v = DeckFixtures.number(r[0]), on = r[1].bool == true, target = DeckFixtures.number(r[2])
            #expect(DeckFixtures.same(plans.acceleration(v, on, target), DeckFixtures.number(r[3])), "acceleration(\(v), \(on), \(target))")
        }
    }

    @Test func platformMathsMakesTheSamePlansToTheEar() {
        //? the phone's own libm, against the web's answers: not bit for bit (that is RecordedMaths' job), but where
        //? the record ends up can't differ by more than a hair - a sanity check that PlatformMaths is wired to the
        //? right functions
        let mine = PlatterPlans(PlatformMaths())
        for flick in (fixture["flicks"]?.array ?? []).prefix(40) {
            let x = DeckFixtures.number(flick["x"]), v = DeckFixtures.number(flick["v"])
            let plan = flick["motor"]?.bool == true ? mine.motor(x, v, 425, DeckFixtures.double(flick["target"]) ?? 1) : mine.coast(x, v, 425)
            let want = DeckFixtures.number(flick["plan"]?["x"])
            #expect(Swift.abs(plan.x - want) < 1e-9, "\(x), \(v): \(plan.x) against \(want)")
        }
    }
}
