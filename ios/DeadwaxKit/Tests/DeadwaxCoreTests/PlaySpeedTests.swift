import Foundation
import Testing
@testable import DeadwaxCore

/// The play speed and its fader (PlaySpeed.swift) against lib/playSpeed.ts's own answers (Fixtures/deck/turntable.json's
/// `fader` and `plinths`), bit for bit over the web's recorded log and pow.
@Suite struct PlaySpeedTests {
    let fixture: JSONValue
    let maths: RecordedMaths
    let scale: PlaySpeedScale<RecordedMaths>

    init() throws {
        fixture = try DeckFixtures.json("turntable.json")
        maths = DeckFixtures.maths()
        scale = PlaySpeedScale(maths)
    }

    func n(_ value: JSONValue?) -> Double { DeckFixtures.number(value) }

    @Test func theConstantsAndTheFadersPlace() {
        let constants = fixture["fader"]?["constants"]
        for (name, value) in [("SPEED_MIN", PlaySpeed.min), ("SPEED_MAX", PlaySpeed.max), ("SPEED_NORMAL", PlaySpeed.normal),
                              ("SPEED_DETENT", PlaySpeed.detentWidth), ("SPEED_STEP", PlaySpeed.step), ("SPEED_PAGE", PlaySpeed.page)] {
            #expect(DeckFixtures.same(value, n(constants?[name])), "\(name)")
        }
        let fader = fixture["geometry"]?["FADER"]
        #expect(fader?["x"]?.double == PlaySpeed.fader.x && fader?["top"]?.double == PlaySpeed.fader.top && fader?["bottom"]?.double == PlaySpeed.fader.bottom)
        #expect(fader?["clear"]?.double == PlaySpeed.fader.clear && fader?["slot"]?.double == PlaySpeed.fader.slot && fader?["slotRadius"]?.double == PlaySpeed.fader.slotRadius)
        #expect(fader?["knob"]?["width"]?.double == PlaySpeed.knob.width && fader?["knob"]?["height"]?.double == PlaySpeed.knob.height
            && fader?["knob"]?["radius"]?.double == PlaySpeed.knob.radius && fader?["knob"]?["grip"]?.double == PlaySpeed.knob.grip
            && fader?["knob"]?["gripInset"]?.double == PlaySpeed.knob.gripInset)
        #expect(fader?["mark"]?["overhang"]?.double == PlaySpeed.mark.overhang && fader?["mark"]?["thick"]?.double == PlaySpeed.mark.thick)
        #expect(fixture["geometry"]?["READOUT"]?["x"]?.double == PlaySpeed.readout.x && fixture["geometry"]?["READOUT"]?["y"]?.double == PlaySpeed.readout.y)
        #expect(DeckFixtures.same(PlaySpeed.faderFrom, n(fixture["geometry"]?["FADER_FROM"])))
        for plinth in fixture["plinths"]?.array ?? [] {
            let stage = n(plinth["stage"])
            let target = PlaySpeed.faderTarget(stage), wide = PlaySpeed.faderTarget(stage, hit: 60, cap: 0.2)
            #expect(DeckFixtures.same(target.left, n(plinth["faderTarget"]?["left"])) && DeckFixtures.same(target.right, n(plinth["faderTarget"]?["right"])), "faderTarget(\(stage))")
            #expect(DeckFixtures.same(wide.left, n(plinth["faderTarget60"]?["left"])) && DeckFixtures.same(wide.right, n(plinth["faderTarget60"]?["right"])), "faderTarget(\(stage), 60)")
            #expect(DeckFixtures.same(PlaySpeed.faderTravel(stage * (368.0 / 372.0)), n(plinth["faderTravel"])), "faderTravel(\(stage))")
        }
    }

    @Test func speedsRoundedHeldAndScaled() {
        let rows = fixture["fader"]?["speeds"]?.array ?? []
        #expect(rows.count == 21)
        for row in rows {
            let r = row.array ?? []
            let speed = n(r[0])
            #expect(DeckFixtures.same(PlaySpeed.roundSpeed(speed), n(r[1])), "roundSpeed(\(speed))")
            #expect(DeckFixtures.same(PlaySpeed.clampSpeed(speed), n(r[2])), "clampSpeed(\(speed))")
            #expect(DeckFixtures.same(PlaySpeed.detent(speed), n(r[3])), "detent(\(speed))")
            #expect(DeckFixtures.same(scale.faderShare(speed), n(r[4])), "faderShare(\(speed))")
            #expect(scale.knobTop(speed) == r[5].string, "knobTop(\(speed)): \(scale.knobTop(speed))")
            #expect(TurntableWords.speedLabel(speed) == r[6].string, "speedLabel(\(speed))")
            #expect(TurntableWords.speedWords(speed) == r[7].string, "speedWords(\(speed))")
        }
        for row in fixture["fader"]?["shares"]?.array ?? [] {
            let r = row.array ?? []
            #expect(DeckFixtures.same(scale.speedAt(n(r[0])), n(r[1])), "speedAt(\(n(r[0])))")
        }
        #expect(maths.missed.isEmpty, "\(maths.missed.prefix(5))")
    }

    @Test func theKeys() {
        for row in fixture["fader"]?["keys"]?.array ?? [] {
            let r = row.array ?? []
            let key = r[0].string ?? "", speed = n(r[1])
            #expect(DeckFixtures.same(PlaySpeed.speedKey(key, speed), DeckFixtures.double(r[2])), "speedKey(\(key), \(speed))")
        }
    }

    @Test func aFingerOnTheFader() {
        let drags = fixture["fader"]?["drags"]?.array ?? []
        #expect(drags.count == 8)
        for (run, case_) in drags.enumerated() {
            var drag: PlaySpeed.FaderDrag? = PlaySpeed.faderStart(1, 200)
            for (k, step) in (case_["steps"]?.array ?? []).enumerated() {
                let r = step.array ?? []
                let what = "fader drag \(run) step \(k)"
                let out = scale.faderMove(drag, r[0].int ?? 0, n(r[1]), n(r[2]), n(r[3]))
                #expect(out.same == (r[4].bool == true), "\(what): the same drag")
                let from = r[5].array
                #expect(DeckFixtures.same(out.drag?.from?.y, from.map { n($0[0]) }) && DeckFixtures.same(out.drag?.from?.share, from.map { n($0[1]) }), "\(what): from")
                #expect(DeckFixtures.same(out.speed, DeckFixtures.double(r[6])), "\(what): speed \(String(describing: out.speed))")
                drag = out.drag
            }
            let end = case_["end"]?.array ?? []
            #expect((PlaySpeed.faderEnd(drag, 1) == nil) == (end[0].bool == true))
            #expect((PlaySpeed.faderEnd(drag, 2) == drag) == (end[1].bool == true))
        }
        #expect(maths.missed.isEmpty, "\(maths.missed.prefix(5))")
    }
}
