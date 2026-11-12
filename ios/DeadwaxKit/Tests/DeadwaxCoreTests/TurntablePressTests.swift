import Foundation
import Testing
@testable import DeadwaxCore

/// TurntablePress against Turntable.tsx's handlers, read line by line (the spec's 3.1): hand-built cases, each the
/// calls the web's handlers make in the order they make them. The traces of the real Turntable driven are replayed by
/// TurntablePressTraceTests, below.
@Suite struct TurntablePressTests {
    final class FakeDeck: PressDeck {
        var calls: [String] = []
        var isLive = true
        var isTaken = false
        var anchorAt = 60.0
        var released = DeckReleased(seek: nil, play: false)
        var landing: Double?
        var from: Double?
        func live() -> Bool { calls.append("live"); return isLive }
        func taken() -> Bool { isTaken }
        func anchor() -> Double { anchorAt }
        func pressed(_ time: Double) { calls.append("pressed \(time)") }
        func holdStill(_ held: Bool) { calls.append("holdStill \(held)") }
        func touched(_ time: Double, turned: Double, offset: Double) { calls.append("touched \(time)") }
        func takeOver(_ time: Double?, quick: Bool) -> Double {
            calls.append("takeOver \(time ?? -1) \(quick)")
            isTaken = true
            return anchorAt
        }
        func hand(_ time: Double, turned: Double, at: Double) { calls.append("hand \(time)") }
        func release(_ time: Double, cancel: Bool) -> DeckReleased {
            calls.append("release \(time) \(cancel ? "cancel" : "up")")
            isTaken = false
            return released
        }
        func pausing() -> Double? { calls.append("pausing"); return landing }
        func resuming() -> Double? { calls.append("resuming"); return from }
        func armTaken() { calls.append("armTaken") }
    }

    final class FakeHost: PressHost {
        var calls: [String] = []
        var isPlaying = true
        var songLength = 425.0
        var time = 1000.0
        var isFlac = false
        func playing() -> Bool { isPlaying }
        func length() -> Double { songLength }
        func track() -> String { "time" }
        func seek(_ seconds: Double) { calls.append("seek \(seconds)") }
        func toggle() {
            calls.append("toggle")
            isPlaying.toggle()
        }
        func wake() { calls.append("wake") }
        //? the stage drawn at its own size: a point and a pixel are a stage unit
        func box() -> StageBox { StageBox(left: 0, top: 0, width: TurntableGeometry.stage.width, height: TurntableGeometry.stage.height) }
        func drawnAt() -> Double { 60 }
        func shown() -> Double { 60 }
        func now() -> Double { time }
        func flac() -> Bool { isFlac }
        func noAudio() -> Bool { false }
    }

    func press(_ deck: FakeDeck, _ host: FakeHost) -> TurntablePress<PlatformMaths> {
        TurntablePress(deck: deck, host: host, maths: PlatformMaths())
    }

    /// A point on the record, `degrees` round from its right, 100 units from the spindle.
    func onRecord(_ degrees: Double) -> (x: Double, y: Double) {
        let record = TurntableGeometry.record
        let a = degrees * Double.pi / 180
        return (record.x + 100 * cos(a), record.y + 100 * sin(a))
    }

    @Test func aTapOnAPlayingRecordWindsItDown() {
        let deck = FakeDeck(), host = FakeHost()
        deck.landing = 61.5
        let p = press(deck, host)
        let at = onRecord(0)
        p.recordDown(pointer: 1, x: at.x, y: at.y, time: 1000)
        host.time = 1080
        p.ended(pointer: 1, how: .up, time: 1080)
        #expect(deck.calls == ["live", "pressed 1000.0", "release 1080.0 up", "pausing"])
        #expect(host.calls == ["wake", "wake", "toggle", "seek 61.5"])
        #expect(p.drag == nil)
    }

    @Test func aTapOnAPausedRecordPlaysFromWhereItIs() {
        let deck = FakeDeck(), host = FakeHost()
        host.isPlaying = false
        deck.from = 63.25
        let p = press(deck, host)
        let at = onRecord(30)
        p.recordDown(pointer: 1, x: at.x, y: at.y, time: 1000)
        host.time = 1050
        p.ended(pointer: 1, how: .up, time: 1050)
        #expect(deck.calls == ["live", "pressed 1000.0", "release 1050.0 up", "resuming"])
        #expect(host.calls == ["wake", "wake", "seek 63.25", "toggle"])
    }

    @Test func aTurnPastTheSlopIsTakenFromThePressAndIsNoTap() {
        let deck = FakeDeck(), host = FakeHost()
        deck.released = DeckReleased(seek: 58.5, play: false)
        let p = press(deck, host)
        let a = onRecord(0), b = onRecord(1), c = onRecord(8)
        p.recordDown(pointer: 1, x: a.x, y: a.y, time: 1000)
        p.moved(pointer: 1, samples: [(1008, b.x, b.y), (1016, c.x, c.y)])
        host.time = 1030
        p.ended(pointer: 1, how: .up, time: 1030)
        //? inside the slop the deck only keeps the sample; past it the take is from the press, and the hand goes on
        #expect(deck.calls == ["live", "pressed 1000.0", "touched 1008.0", "touched 1016.0", "takeOver 1016.0 true", "hand 1016.0", "release 1030.0 up"])
        //? the seek the release asks for - and the click after the turn is no tap: no toggle
        #expect(host.calls == ["wake", "seek 58.5", "wake"])
        #expect(p.turn != 0)
    }

    @Test func aReleaseThatAsksToPlayPlaysInTheGesture() {
        let deck = FakeDeck(), host = FakeHost()
        host.isPlaying = false
        deck.isTaken = true
        deck.released = DeckReleased(seek: 70, play: true)
        let p = press(deck, host)
        let a = onRecord(0)
        p.recordDown(pointer: 1, x: a.x, y: a.y, time: 1000)
        host.time = 1300
        p.ended(pointer: 1, how: .up, time: 1300)
        //? taken (by a rest): the record stays where the hand left it, and the click is no tap
        #expect(host.calls == ["wake", "seek 70.0", "toggle", "wake"])
    }

    @Test func aReleaseThatAsksToPlayLeavesAPlayingSongAlone() {
        //? :382's `!player.playing`: a song already playing (played from elsewhere meanwhile) isn't toggled to a pause
        let deck = FakeDeck(), host = FakeHost()
        deck.isTaken = true
        deck.released = DeckReleased(seek: 70, play: true)
        let p = press(deck, host)
        let a = onRecord(0)
        p.recordDown(pointer: 1, x: a.x, y: a.y, time: 1000)
        host.time = 1300
        p.ended(pointer: 1, how: .up, time: 1300)
        #expect(host.calls == ["wake", "seek 70.0", "wake"])
    }

    @Test func aCancelSeeksNothingAndIsNoClick() {
        let deck = FakeDeck(), host = FakeHost()
        let p = press(deck, host)
        let a = onRecord(0)
        p.recordDown(pointer: 1, x: a.x, y: a.y, time: 1000)
        host.time = 1200
        p.ended(pointer: 1, how: .cancel, time: 1200)
        #expect(deck.calls == ["live", "pressed 1000.0", "release 1200.0 cancel"])
        #expect(host.calls.isEmpty)
    }

    @Test func aSilentPressHoldsTheRecordStillAndSaysWhy() {
        let deck = FakeDeck(), host = FakeHost()
        deck.isLive = false
        let p = press(deck, host)
        let a = onRecord(0), b = onRecord(12)
        p.recordDown(pointer: 1, x: a.x, y: a.y, time: 1000)
        #expect(p.silentLine == nil)
        p.moved(pointer: 1, samples: [(1016, b.x, b.y)])
        //? the first silent turn of the song: the line, as the web words it for a song that isn't a FLAC
        #expect(p.silentLine == TurntableWords.silentNote(flac: false, noAudio: false))
        host.time = 1040
        p.ended(pointer: 1, how: .up, time: 1040)
        #expect(deck.calls == ["live", "holdStill true", "holdStill false"])
        //? .11's drag: sought to where it shows, and the click after the turn is no tap
        #expect(host.calls.count == 3 && host.calls[0] == "wake" && host.calls[1].hasPrefix("seek ") && host.calls[2] == "wake")
    }

    @Test func theArm() {
        let deck = FakeDeck(), host = FakeHost()
        host.songLength = 0
        let p = press(deck, host)
        p.armDown(pointer: 2, x: 250, y: 40)
        #expect(deck.calls.isEmpty && p.drag == nil, "no length: the arm can't be taken")
        host.songLength = 425
        p.armDown(pointer: 2, x: 250, y: 40)
        #expect(deck.calls == ["armTaken"] && p.drag?.kind == .arm)
        #expect(p.armKey("ArrowRight"))
        #expect(host.calls == ["seek \(Scrub.keyTarget("ArrowRight", from: 60, length: 425)!)"])
        #expect(!p.armKey("a"))
    }

    @Test func nowPlayingsToggle() {
        let deck = FakeDeck(), host = FakeHost()
        deck.landing = 64
        TurntablePress<PlatformMaths>.toggle(deck, host)
        #expect(deck.calls == ["pausing"] && host.calls == ["wake", "toggle", "seek 64.0"])
        deck.calls = []
        host.calls = []
        deck.from = nil
        TurntablePress<PlatformMaths>.toggle(deck, host)
        #expect(deck.calls == ["resuming"] && host.calls == ["wake", "toggle"])
        host.calls = []
        TurntablePress<PlatformMaths>.toggle(nil, host)
        #expect(host.calls == ["wake", "toggle"], "no turntable's deck: a plain pause")
    }
}

/// TurntablePress held to the web's handlers as they ran (Fixtures/deck/press/*.json, the spec's 7.0): the real
/// Turntable mounted as turntable.sim mounts it, over deck.sim's harness and a fake player, driven by pointer events,
/// the arm's keys and Now Playing's transport - every call its handlers made, in order, with what the deck returned and
/// the state after it. Replayed into TurntablePress over a deck and a player that answer as the web's did, every call
/// must be the web's, in the web's order, its doubles bit for bit with RecordedMaths (within 1e-9 with the platform's);
/// the record's turn as drawn and the silent line too.
@Suite struct TurntablePressTraceTests {
    /// What a call or an answer says: a number by its bits, or a word.
    enum Token: Equatable, CustomStringConvertible {
        case number(Double)
        case word(String)

        init(_ json: JSONValue) {
            switch json {
            case .null: self = .word("null")
            case .bool(let flag): self = .word(flag ? "true" : "false")
            case .number(let n): self = .word(n == n.rounded() ? String(Int(n)) : String(n))
            case .string(let text):
                if text.count > 17, text.dropFirst(16).first == " ", let value = DeckFixtures.double(json) { self = .number(value) } else { self = .word(text) }
            default: self = .word("?")
            }
        }

        var description: String {
            switch self {
            case .number(let x): return "\(x)"
            case .word(let w): return w
            }
        }

        /// Bit for bit, or (`near`) within 1e-9 of the larger.
        func same(_ other: Token, near: Bool) -> Bool {
            switch (self, other) {
            case let (.number(a), .number(b)):
                if DeckFixtures.same(a, b) { return true }
                return near && a.isFinite && b.isFinite && abs(a - b) <= 1e-9 * Swift.max(1, abs(a), abs(b))
            case let (.word(a), .word(b)): return a == b
            default: return false
            }
        }
    }

    /// The web's call, what it returned, and the state after it.
    struct Expected {
        let words: [Token]
        let returns: [JSONValue]
        let after: [String: JSONValue]
    }

    /// The deck and the player, answering as the web's did: queries from the state the trace last said, each call's
    /// answer and the state after it from the web's call at the same place.
    final class Script {
        var expected: [Expected] = []
        var made: [[Token]] = []
        var world: (([String: JSONValue]) -> Void)?

        func begin(_ calls: [Expected]) {
            expected = calls
            made = []
        }

        /// A call made: noted, and the web's at the same place answered with.
        func call(_ words: [Token]) -> [JSONValue] {
            made.append(words)
            guard made.count <= expected.count else { return [] }
            let web = expected[made.count - 1]
            world?(web.after)
            return web.returns
        }
    }

    final class Host: PressHost {
        let script: Script
        var isPlaying = false, songLength = 0.0, trackId = "", drawn = 0.0, shownAt = 0.0, time = 0.0
        var isFlac = false, isNoAudio = false
        var frame = StageBox(left: 0, top: 0, width: 0, height: 0)
        init(_ script: Script) { self.script = script }
        func playing() -> Bool { isPlaying }
        func length() -> Double { songLength }
        func track() -> String { trackId }
        func seek(_ seconds: Double) { _ = script.call([.word("seek"), .number(seconds)]) }
        func toggle() { _ = script.call([.word("toggle")]) }
        func wake() { _ = script.call([.word("wake")]) }
        func box() -> StageBox { frame }
        func drawnAt() -> Double { drawn }
        func shown() -> Double { shownAt }
        func now() -> Double { time }
        func flac() -> Bool { isFlac }
        func noAudio() -> Bool { isNoAudio }
    }

    final class Deck: PressDeck {
        let script: Script
        var isLive = false, isTaken = false, anchorAt = 0.0
        init(_ script: Script) { self.script = script }
        func live() -> Bool { isLive }
        func taken() -> Bool { isTaken }
        func anchor() -> Double { anchorAt }
        func pressed(_ time: Double) { _ = script.call([.word("pressed"), .number(time)]) }
        func holdStill(_ held: Bool) { _ = script.call([.word("holdStill"), .word(held ? "true" : "false")]) }
        func touched(_ time: Double, turned: Double, offset: Double) {
            _ = script.call([.word("touched"), .number(time), .number(turned), .number(offset)])
        }
        func takeOver(_ time: Double?, quick: Bool) -> Double {
            DeckFixtures.number(script.call([.word("takeOver"), time.map { .number($0) } ?? .word("undefined"), .word(quick ? "true" : "false")]).first)
        }
        func hand(_ time: Double, turned: Double, at: Double) {
            _ = script.call([.word("hand"), .number(time), .number(turned), .number(at)])
        }
        func release(_ time: Double, cancel: Bool) -> DeckReleased {
            let out = script.call([.word("release"), .number(time), .word(cancel ? "cancel" : "up")])
            return DeckReleased(seek: out.first.flatMap { DeckFixtures.double($0) }, play: out.count > 1 ? out[1].bool ?? false : false)
        }
        func pausing() -> Double? { script.call([.word("pausing")]).first.flatMap { DeckFixtures.double($0) } }
        func resuming() -> Double? { script.call([.word("resuming")]).first.flatMap { DeckFixtures.double($0) } }
        func armTaken() { _ = script.call([.word("armTaken")]) }
    }

    static let inputs: Set<String> = ["down", "armDown", "move", "up", "cancel", "key", "nowPlaying", "song", "grabbed"]
    static let calls: Set<String> = ["pressed", "holdStill", "touched", "takeOver", "hand", "release", "pausing", "resuming",
                                     "armTaken", "seek", "toggle", "wake"]

    static func names() throws -> [String] {
        let folder = try Fixtures.url("deck/press")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") && $0 != "handlers.json" }.sorted()
    }

    /// Replays one trace; returns what differs from the web, in words, and how many calls and checks agreed.
    static func replay<M: DeckMaths>(_ name: String, _ maths: M, near: Bool) throws -> (problems: [String], calls: Int, checks: Int) {
        let json = try DeckFixtures.json("press/\(name)")
        let events = json["events"]?.array ?? []
        let script = Script()
        let host = Host(script)
        let deck = Deck(script)
        let box = (json["box"]?.array ?? []).map { DeckFixtures.number($0) }
        host.frame = StageBox(left: box[0], top: box[1], width: box[2], height: box[3])
        func apply(_ fields: [String: JSONValue]) {
            for (key, value) in fields {
                switch key {
                case "playing": host.isPlaying = value.bool ?? false
                case "live": deck.isLive = value.bool ?? false
                case "taken": deck.isTaken = value.bool ?? false
                case "anchor": deck.anchorAt = DeckFixtures.number(value)
                case "length": host.songLength = DeckFixtures.number(value)
                case "track": host.trackId = value.string ?? ""
                case "drawnAt": host.drawn = DeckFixtures.number(value)
                case "shown": host.shownAt = DeckFixtures.number(value)
                case "now": host.time = DeckFixtures.number(value)
                case "flac": host.isFlac = value.bool ?? false
                case "noAudio": host.isNoAudio = value.bool ?? false
                default: break
                }
            }
        }
        script.world = apply
        let press = TurntablePress(deck: deck, host: host, maths: maths)
        var problems: [String] = []
        var agreed = 0, checks = 0
        func number(_ value: JSONValue) -> Double { DeckFixtures.number(value) }
        var expectedTurn = 0.0
        var expectedSilent: String?
        //? Turntable.tsx:426's handTurn, as the render draws it, and the silent line (:289), against the web's
        func look(_ at: Int) -> Int {
            let drag = press.drag
            let hand = drag.map { $0.kind == .record && (TurntableGeometry.moved($0) || (press.live && deck.taken())) } ?? false
            let turn = press.turn + (hand ? drag!.turned * TurntablePress<M>.degrees : 0)
            if !Token.number(turn).same(.number(expectedTurn), near: near) { problems.append("event \(at): the record drawn turned \(turn), not \(expectedTurn)") }
            if press.silentLine != expectedSilent { problems.append("event \(at): the silent line \(press.silentLine ?? "nil"), not \(expectedSilent ?? "nil")") }
            return 2
        }
        var i = 0
        while i < events.count {
            let event = events[i].array ?? []
            let what = event.first?.string ?? ""
            let a = Array(event.dropFirst())
            if what == "world" {
                apply(a.first?.object ?? [:])
                i += 1
                continue
            }
            //? the record's turn as drawn and the silent line: checked where the web says they changed, and after every
            //? input - a change the Swift makes and the web doesn't is caught there
            if what == "turn" || what == "silent" {
                if what == "turn" { expectedTurn = number(a[0]) } else { expectedSilent = a[0].string }
                checks += look(i)
                i += 1
                continue
            }
            guard Self.inputs.contains(what) else {
                problems.append("event \(i): \(what) is neither an input nor a check - a call the web's handlers made that no input before it explains")
                i += 1
                continue
            }
            //? the calls the web's handlers made for this input, each with what came back and the state after it
            var expected: [Expected] = []
            var j = i + 1
            while j < events.count, let call = events[j].array, let named = call.first?.string, Self.calls.contains(named) {
                let body = Array(call.dropFirst())
                let arrow = body.firstIndex(of: .string("->"))
                let words = [Token.word(named)] + body[..<(arrow ?? body.count)].map(Token.init)
                let returns = arrow.map { Array(body[($0 + 1)...]) } ?? []
                var after: [String: JSONValue] = [:]
                if j + 1 < events.count, let next = events[j + 1].array, next.first?.string == "after" {
                    after = next.dropFirst().first?.object ?? [:]
                    j += 1
                }
                expected.append(Expected(words: words, returns: returns, after: after))
                j += 1
            }
            script.begin(expected)
            switch what {
            case "down":
                press.recordDown(pointer: a[0].int ?? -1, x: number(a[1]), y: number(a[2]), time: number(a[3]))
            case "armDown":
                press.armDown(pointer: a[0].int ?? -1, x: number(a[1]), y: number(a[2]))
            case "move":
                let id = a[0].int ?? -1
                func raw(_ triple: JSONValue) -> PointerSamples.Raw {
                    let t = triple.array ?? []
                    return PointerSamples.Raw(pointerId: id, timeStamp: number(t[0]), x: number(t[1]), y: number(t[2]))
                }
                let coalesced = a[1].array.map { $0.map(raw) }
                let samples = PointerSamples.samples(raw(a[2]), coalesced: coalesced, now: host.time)
                press.moved(pointer: id, samples: samples)
            case "up":
                press.ended(pointer: a[0].int ?? -1, how: .up, time: number(a[1]))
            case "cancel":
                press.ended(pointer: a[0].int ?? -1, how: .cancel, time: number(a[1]))
            case "key":
                press.armKey(a[0].string ?? "")
            case "nowPlaying":
                TurntablePress<M>.toggle(deck, host)
            case "song":
                press.songChanged(a[0].string ?? "")
            case "grabbed":
                press.grabbed()
            default:
                break
            }
            let made = script.made
            for k in 0..<Swift.max(made.count, expected.count) {
                let mine = k < made.count ? made[k] : []
                let web = k < expected.count ? expected[k].words : []
                let same = mine.count == web.count && zip(mine, web).allSatisfy { $0.same($1, near: near) }
                if same { agreed += 1 } else {
                    problems.append("event \(i) (\(what)), call \(k): made [\(mine.map(\.description).joined(separator: " "))], the web's [\(web.map(\.description).joined(separator: " "))]")
                }
            }
            //? what the render drew and Now Playing was told after it, then both checked
            i = j
            while i < events.count, let next = events[i].array, let named = next.first?.string, named == "turn" || named == "silent" {
                if named == "turn" { expectedTurn = number(next[1]) } else { expectedSilent = next[1].string }
                i += 1
            }
            checks += look(i - 1)
        }
        return (problems, agreed, checks)
    }

    @Test func theTracesAreThere() throws {
        let names = try Self.names()
        #expect(names.count >= 12, "the spec's 7.0's press traces: \(names)")
        for name in names {
            let json = try DeckFixtures.json("press/\(name)")
            #expect((json["events"]?.array?.count ?? 0) > 3, "\(name)")
        }
    }

    @Test(arguments: try names())
    func everyCallIsTheWebsBitForBit(_ name: String) throws {
        let maths = DeckFixtures.maths()
        let out = try Self.replay(name, maths, near: false)
        #expect(out.problems.isEmpty, "\(name): \(out.problems.prefix(6).joined(separator: "; "))")
        #expect(out.calls > 0, "\(name): no calls compared")
        #expect(maths.missed.isEmpty, "\(name): Math calls the web never made: \(maths.missed.prefix(4))")
    }

    @Test(arguments: try names())
    func andWithThePlatformsMaths(_ name: String) throws {
        let out = try Self.replay(name, PlatformMaths(), near: true)
        #expect(out.problems.isEmpty, "\(name): \(out.problems.prefix(6).joined(separator: "; "))")
    }
}
