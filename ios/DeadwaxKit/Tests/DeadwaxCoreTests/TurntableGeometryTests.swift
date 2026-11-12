import Foundation
import Testing
@testable import DeadwaxCore

/// The turntable's geometry (TurntableGeometry.swift) against lib/turntable.ts and lib/deckClock.ts's own answers
/// (Fixtures/deck/turntable.json), bit for bit over the web's recorded sin, cos, atan2 and hypot: the drawing's places,
/// toStage, the arm's needle and angle and their inverse, 24 seeded drags step by step, the previews and their words,
/// the disc, and the pointer's samples.
@Suite struct TurntableGeometryTests {
    let fixture: JSONValue
    let maths: RecordedMaths
    let trig: TurntableTrig<RecordedMaths>

    init() throws {
        fixture = try DeckFixtures.json("turntable.json")
        maths = DeckFixtures.maths()
        trig = TurntableTrig(maths)
    }

    func n(_ value: JSONValue?) -> Double { DeckFixtures.number(value) }

    func box(_ json: JSONValue?) -> StageBox {
        StageBox(left: n(json?["left"]), top: n(json?["top"]), width: n(json?["width"]), height: n(json?["height"]))
    }

    @Test func theDrawingIsTheWebs() {
        let geometry = fixture["geometry"]
        #expect(geometry?["STAGE"]?["width"]?.double == TurntableGeometry.stage.width)
        #expect(geometry?["STAGE"]?["height"]?.double == TurntableGeometry.stage.height)
        for (name, circle) in [("PLATTER", TurntableGeometry.platter), ("RECORD", TurntableGeometry.record)] {
            #expect(geometry?[name]?["x"]?.double == circle.x && geometry?[name]?["y"]?.double == circle.y && geometry?[name]?["r"]?.double == circle.r, "\(name)")
        }
        #expect(geometry?["GROOVES"]?["outer"]?.double == TurntableGeometry.grooves.outer)
        #expect(geometry?["GROOVES"]?["inner"]?.double == TurntableGeometry.grooves.inner)
        #expect(geometry?["ARM"]?["x"]?.double == TurntableGeometry.arm.x)
        #expect(geometry?["ARM"]?["y"]?.double == TurntableGeometry.arm.y)
        #expect(geometry?["ARM"]?["reach"]?.double == TurntableGeometry.arm.reach)
        let parts = geometry?["ARM_PARTS"]
        #expect(parts?["bar"]?["thick"]?.double == TurntableGeometry.armBar.thick && parts?["bar"]?["radius"]?.double == TurntableGeometry.armBar.radius)
        for (name, part) in [("head", TurntableGeometry.armHead), ("weight", TurntableGeometry.armWeight)] {
            #expect(parts?[name]?["from"]?.double == part.from && parts?[name]?["length"]?.double == part.length
                && parts?[name]?["thick"]?.double == part.thick && parts?[name]?["radius"]?.double == part.radius, "\(name)")
        }
        #expect(parts?["base"]?.double == TurntableGeometry.armBase)
        #expect(parts?["baseEdge"]?.double == TurntableGeometry.armBaseEdge)
        #expect(parts?["lift"]?.double == TurntableGeometry.armLift)
        #expect(parts?["handle"]?.double == TurntableGeometry.armHandle)
        #expect(geometry?["TAP_SLOP_PX"]?.double == TurntableGeometry.tapSlop)
        #expect(DeckFixtures.same(TurntableGeometry.spindleShare, n(geometry?["SPINDLE_SHARE"])))
        #expect(DeckFixtures.same(TurntableGeometry.secondsPerTurn, n(geometry?["SECONDS_PER_TURN"])))

        let places = geometry?["places"]
        func expectCircle(_ name: String, _ place: (left: String, top: String, width: String, height: String)) {
            let want = places?[name]
            #expect(place.left == want?["left"]?.string && place.top == want?["top"]?.string && place.width == want?["width"]?.string
                && place.height == want?["height"]?.string, "\(name): \(place)")
        }
        let record = TurntableGeometry.record
        expectCircle("platter", TurntableGeometry.placeCircle(TurntableGeometry.platter))
        expectCircle("record", TurntableGeometry.placeCircle(record))
        expectCircle("label", TurntableGeometry.placeCircle(StageCircle(x: record.x, y: record.y, r: TurntableGeometry.grooves.inner - 4)))
        expectCircle("spindle", TurntableGeometry.placeCircle(StageCircle(x: record.x, y: record.y, r: TurntableGeometry.spindleShare * record.r)))
        let pivot = TurntableGeometry.placePoint(StagePoint(x: TurntableGeometry.arm.x, y: TurntableGeometry.arm.y))
        #expect(pivot.left == places?["pivot"]?["left"]?.string && pivot.top == places?["pivot"]?["top"]?.string)
        let readout = TurntableGeometry.placePoint(StagePoint(x: PlaySpeed.readout.x, y: PlaySpeed.readout.y))
        #expect(readout.left == places?["readout"]?["left"]?.string && readout.top == places?["readout"]?["top"]?.string)
        #expect(TurntableGeometry.across(TurntableGeometry.armHandle) == places?["handle"]?.string)
        #expect(TurntableGeometry.across(TurntableGeometry.arm.reach) == places?["reach"]?.string)
        #expect(TurntableGeometry.across(TurntableGeometry.armBase) == places?["base"]?.string)
    }

    @Test func theLayoutIsTheDrawingInPoints() {
        //? the phone's layout is the same shares of the plinth the CSS percentages are
        let close = { (a: Double, b: Double) in Swift.abs(a - b) < 1e-9 }
        let layout = TurntableLayout(width: 372)
        #expect(close(layout.height, 368))
        #expect(close(layout.record.left, 18) && close(layout.record.top, 22) && close(layout.record.width, 320) && close(layout.record.height, 320))
        #expect(close(layout.pivot.x, 348) && close(layout.pivot.y, 32))
        #expect(close(layout.handle, 56) && close(layout.reach, 205))
        let small = TurntableLayout(width: 343)
        #expect(Swift.abs(small.record.width - 320 * 343 / 372) < 1e-9)
        #expect(small.faderTravel == PlaySpeed.faderTravel(small.height))
    }

    @Test func toStage() {
        for row in fixture["toStage"]?.array ?? [] {
            let r = row.array ?? []
            let at = TurntableGeometry.toStage(n(r[1]), n(r[2]), box(r[0]))
            #expect(DeckFixtures.same(at.x, n(r[3]["x"])) && DeckFixtures.same(at.y, n(r[3]["y"])), "toStage(\(n(r[1])), \(n(r[2])), \(box(r[0])))")
        }
    }

    @Test func theArm() {
        let rows = fixture["arm"]?.array ?? []
        #expect(rows.count == 54)
        for row in rows {
            let r = row.array ?? []
            let time = n(r[0]), length = n(r[1])
            #expect(DeckFixtures.same(TurntableGeometry.grooveRadius(time, length), n(r[2])), "grooveRadius(\(time), \(length))")
            let needle = trig.needleAt(time, length)
            #expect(DeckFixtures.same(needle.x, n(r[3]["x"])) && DeckFixtures.same(needle.y, n(r[3]["y"])), "needleAt(\(time), \(length))")
            #expect(DeckFixtures.same(trig.armAngle(time, length), n(r[4])), "armAngle(\(time), \(length))")
        }
        for row in fixture["armTimes"]?.array ?? [] {
            let r = row.array ?? []
            #expect(DeckFixtures.same(trig.armTimeAt(n(r[0]), n(r[1])), n(r[2])), "armTimeAt(\(n(r[0])), \(n(r[1])))")
        }
        for row in fixture["pivot"]?.array ?? [] {
            let r = row.array ?? []
            #expect(DeckFixtures.same(trig.angleFromPivot(StagePoint(x: n(r[0]), y: n(r[1]))), n(r[2])))
        }
        #expect(maths.missed.isEmpty, "\(maths.missed.prefix(5))")
    }

    func expectDrag(_ drag: TurntableDrag?, _ want: JSONValue?, _ what: String) {
        guard let want, !want.isNull else {
            #expect(drag == nil, "\(what): a drag where the web has none")
            return
        }
        guard let drag else { Issue.record("\(what): no drag where the web has one"); return }
        #expect(drag.kind.rawValue == want["kind"]?.string && drag.pointer == want["pointer"]?.int && drag.track == want["track"]?.string, "\(what)")
        #expect(DeckFixtures.same(drag.x0, n(want["x0"])) && DeckFixtures.same(drag.y0, n(want["y0"])), "\(what): x0, y0")
        #expect(DeckFixtures.same(drag.travel, n(want["travel"])), "\(what): travel \(drag.travel)")
        if drag.kind == .record {
            #expect(DeckFixtures.same(drag.angle, DeckFixtures.double(want["angle"])), "\(what): angle \(String(describing: drag.angle))")
            #expect(DeckFixtures.same(drag.turned, n(want["turned"])), "\(what): turned \(drag.turned)")
            #expect(DeckFixtures.same(drag.offset, n(want["offset"])), "\(what): offset \(drag.offset)")
        } else {
            #expect(DeckFixtures.same(drag.grab, DeckFixtures.double(want["grab"])), "\(what): grab \(String(describing: drag.grab))")
            #expect(DeckFixtures.same(drag.time, DeckFixtures.double(want["time"])), "\(what): time \(String(describing: drag.time))")
        }
    }

    func preview(_ json: JSONValue?) -> TurntablePreview? {
        guard let json, !json.isNull else { return nil }
        switch json["how"]?.string {
        case "record": return .record(offset: n(json["offset"]))
        case "arm": return .arm(time: DeckFixtures.double(json["time"]))
        default: return .deck(at: n(json["at"]), scrubbing: json["scrubbing"]?.bool == true)
        }
    }

    func samePreview(_ a: TurntablePreview?, _ b: TurntablePreview?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (.record(x)?, .record(y)?): return DeckFixtures.same(x, y)
        case let (.arm(x)?, .arm(y)?): return DeckFixtures.same(x, y)
        case let (.deck(x, s)?, .deck(y, t)?): return DeckFixtures.same(x, y) && s == t
        default: return false
        }
    }

    @Test func theDragsStepByStep() {
        let drags = fixture["drags"]?.array ?? []
        #expect(drags.count == 24)
        for (run, case_) in drags.enumerated() {
            let steps = case_["steps"]?.array ?? []
            let area = box(case_["box"]), length = n(case_["length"])
            let kind = case_["kind"]?.string == "arm" ? TurntableDrag.Kind.arm : .record
            guard let start = steps.first else { continue }
            let x0 = n(start["x"]), y0 = n(start["y"])
            var drag: TurntableDrag? = kind == .arm ? trig.armStart(1, "song", x0, y0) : trig.recordStart(1, "song", x0, y0, area)
            expectDrag(drag, start["drag"], "drag \(run) start")
            var position = 0.0
            for (k, step) in steps.dropFirst().enumerated() {
                let what = "drag \(run) step \(k)"
                let pointer = step["pointer"]?.int ?? 1
                position = n(step["position"])
                let x = n(step["x"]), y = n(step["y"])
                let same = !TurntableGeometry.moves(drag, kind, pointer)
                #expect(same == (step["same"]?.bool == true), "\(what): the same drag")
                let next = kind == .arm ? trig.armMove(drag, pointer, x, y, area, length, position) : trig.recordMove(drag, pointer, x, y, area, length, position)
                expectDrag(next, step["drag"], what)
                #expect(TurntableGeometry.moved(next) == (step["moved"]?.bool == true), "\(what): moved")
                let previewing = TurntableGeometry.preview(next)
                #expect(samePreview(previewing, preview(step["preview"])), "\(what): preview \(String(describing: previewing))")
                #expect(DeckFixtures.same(TurntableGeometry.shownTime(previewing, position, length), n(step["shown"])), "\(what): shown")
                #expect(TurntableGeometry.previewWords(previewing)?.rawValue == step["words"]?.string, "\(what): words")
                drag = next
            }
            for end in case_["ends"]?.array ?? [] {
                let how: DeckLetGo = end["how"]?.string == "up" ? .up : .cancel
                let ended = TurntableGeometry.dragEnd(drag, 1, how, position, length)
                expectDrag(ended.drag, end["drag"], "drag \(run) \(how)")
                #expect(DeckFixtures.same(ended.seek, DeckFixtures.double(end["seek"])), "drag \(run) \(how): seek \(String(describing: ended.seek))")
                #expect(ended.wasDrag == (end["wasDrag"]?.bool == true), "drag \(run) \(how): wasDrag")
            }
            let other = TurntableGeometry.dragEnd(drag, 9, .up, position, length)
            #expect(!other.ended == (case_["otherPointer"]?["same"]?.bool == true) && other.seek == nil && !other.wasDrag, "drag \(run): another pointer's lift")
            #expect((TurntableGeometry.dragFor(drag, "song") == drag) == (case_["dragFor"]?.array?[0].bool == true))
            #expect(TurntableGeometry.dragFor(drag, "other") == nil && case_["dragFor"]?.array?[1].isNull == true)
        }
        #expect(maths.missed.isEmpty, "\(maths.missed.prefix(5))")
    }

    @Test func previewsShownAndCompared() {
        for row in fixture["shown"]?.array ?? [] {
            let r = row.array ?? []
            let p = preview(r[0])
            #expect(DeckFixtures.same(TurntableGeometry.shownTime(p, n(r[1]), n(r[2])), n(r[3])), "shownTime(\(String(describing: p)), \(n(r[1])), \(n(r[2])))")
            #expect(TurntableGeometry.previewWords(p)?.rawValue == r[4].string)
        }
        for row in fixture["same"]?.array ?? [] {
            let r = row.array ?? []
            #expect(TurntableGeometry.samePreview(preview(r[0]), preview(r[1])) == (r[2].bool == true), "samePreview(\(r[0]), \(r[1]))")
        }
    }

    @Test func theDiscAndItsArt() {
        for row in fixture["discs"]?.array ?? [] {
            let r = row.array ?? []
            let songs = r[0].array?.map { (id: $0["id"]?.string ?? "", discNumber: DeckFixtures.double($0["discNumber"])) }
            #expect(TurntableGeometry.playingDisc(songs, r[1].string ?? "") == r[2].int, "playingDisc(\(String(describing: songs)))")
        }
        for row in fixture["discArt"]?.array ?? [] {
            let r = row.array ?? []
            #expect(TurntableGeometry.discArtPath(r[0].string, n(r[1])) == r[2].string, "discArtPath(\(String(describing: r[0].string)), \(n(r[1])))")
        }
    }

    @Test func thePointersSamples() {
        func raw(_ json: JSONValue) -> PointerSamples.Raw {
            let r = json.array ?? []
            return PointerSamples.Raw(pointerId: r[0].int ?? 0, timeStamp: DeckFixtures.double(r[1]), x: n(r[2]), y: n(r[3]))
        }
        let cases = fixture["pointerSamples"]?.array ?? []
        #expect(cases.count == 30)
        for (i, row) in cases.enumerated() {
            let event = raw(row["event"] ?? .null)
            let coalesced = row["coalesced"]?.array?.map(raw)
            let samples = PointerSamples.samples(event, coalesced: coalesced, now: n(row["now"]))
            let want = row["samples"]?.array ?? []
            #expect(samples.count == want.count, "case \(i)")
            for (mine, theirs) in zip(samples, want) {
                let t = theirs.array ?? []
                #expect(DeckFixtures.same(mine.time, n(t[0])) && DeckFixtures.same(mine.x, n(t[1])) && DeckFixtures.same(mine.y, n(t[2])), "case \(i)")
            }
        }
        for row in fixture["eventTimes"]?.array ?? [] {
            let r = row.array ?? []
            #expect(DeckFixtures.same(PointerSamples.eventTime(DeckFixtures.double(r[0]), n(r[1])), n(r[2])), "eventTime(\(r[0]), \(n(r[1])))")
        }
    }
}
