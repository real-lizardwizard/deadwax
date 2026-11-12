import Foundation
import Testing
@testable import DeadwaxCore

/// TurntablePress against Turntable.tsx's handlers, read line by line (the spec's 3.1): hand-built cases, each the
/// calls the web's handlers make in the order they make them. (The traces through a mounted Turntable the spec's 7.0
/// asks for are still to come; press/handlers.json hashes the handlers so a change to them fails iosdeck.sim.)
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
