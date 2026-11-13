// What a touch on the turntable does (notes/ios-specs/turntable.md 3.1): ui/src/player/Turntable.tsx's handlers -
// onRecordDown (:303), onArmDown (:316), onMove (:323), onRelease (:363), onRecordClick (:401), onArmKey (:417) and the
// silent line's rule (:288-290) - and NowPlaying.tsx's turntable toggle (:282), ported as a state machine over the
// deck (`PressDeck`, which DeckRules is) and the player (`PressHost`). The touch views only turn touches into its
// calls: `recordDown`, `armDown`, `moved` (every coalesced sample, as PointerSamples has them), `ended` (.up or
// .cancel) and `armKey`. UIKit has no click after a lift, so the lift of a touch that came down on the record runs the
// click's rule (onRecordClick) after the release's own work, in the same call - the order the web's events come in.
// Held to the web by Fixtures/deck/press/*.json (the real Turntable mounted and driven, every call its handlers make);
// the handlers' source is hashed there too, so a change to any of them fails iosdeck.sim until this follows.

/// What a press asks of the player and the screen.
public protocol PressHost: AnyObject {
    func playing() -> Bool
    /// the song's length, seconds - 0 while it isn't known
    func length() -> Double
    /// the song's id
    func track() -> String
    func seek(_ seconds: Double)
    /// the player's play or pause (its toggle)
    func toggle()
    /// a gesture the deck engine may start from (the web's wakeDeckAudio)
    func wake()
    /// the record's frame on the screen now, points
    func box() -> StageBox
    /// the song's position the turntable last drew (Turntable.tsx's drawnAt)
    func drawnAt() -> Double
    /// the time the time line shows (shownTime of the preview), for the arm's keys
    func shown() -> Double
    /// now, ms
    func now() -> Double
    /// the song is a FLAC (or the bench's windows are given), and the deck engine can't be had at all
    func flac() -> Bool
    func noAudio() -> Bool
}

/// The deck as a press drives it.
public protocol PressDeck: AnyObject {
    func live() -> Bool
    func taken() -> Bool
    func anchor() -> Double
    func pressed(_ time: Double)
    func holdStill(_ held: Bool)
    func touched(_ time: Double, turned: Double, offset: Double)
    @discardableResult func takeOver(_ time: Double?, quick: Bool) -> Double
    func hand(_ time: Double, turned: Double, at: Double)
    func release(_ time: Double, cancel: Bool) -> DeckReleased
    func pausing() -> Double?
    func resuming() -> Double?
    func armTaken()
}

extension DeckRules: PressDeck {}

public final class TurntablePress<M: DeckMaths> {
    /// Turntable.tsx:32
    static var degrees: Double { 180 / Double.pi }

    let deck: PressDeck
    let host: PressHost
    let trig: TurntableTrig<M>

    /// the finger on the record or the arm (held.current)
    public private(set) var drag: TurntableDrag?
    /// the press the deck's (live.current)
    var live = false
    /// a turn past a tap, or a take: the click after it is no tap (turned.current)
    var turned = false
    var pressBox: StageBox?
    /// how far the record stays turned, degrees (setTurn)
    public private(set) var turn = 0.0
    /// (2.0.7) the song whose first silent turn was noticed (turnedSilent)
    public private(set) var turnedSilent: String?
    /// told each time the drag changes (setDrag)
    public var dragChanged: ((TurntableDrag?) -> Void)?
    /// The touch the turntable follows: the web's primary pointer (`pressable`'s isPrimary, :301) - the first finger
    /// down on the record or the arm, until it lifts or is cancelled. A second finger meanwhile (on the arm while the
    /// record is held, or the other way round) is no primary pointer on the web and starts nothing; the phone's views
    /// each follow a touch of their own, so the rule is kept here. `onRecord`: it came down on the record, whose lift
    /// the click follows - the drag gone under it (the song changed) or not, as a browser's click still comes.
    var following: (pointer: Int, onRecord: Bool)?
    /// A touch is followed: the fader takes none meanwhile (slice 4 - SpeedFader.tsx:61 asks isPrimary too).
    public var follows: Bool { following != nil }

    public init(deck: PressDeck, host: PressHost, maths: M) {
        self.deck = deck
        self.host = host
        trig = TurntableTrig(maths)
    }

    func setDrag(_ next: TurntableDrag?) {
        drag = next
        dragChanged?(next)
    }

    /// The face's turn the hand adds, degrees (Turntable.tsx:426, `handTurn`): what stays turned, and the drag's own
    /// while the record's drag has moved or the deck took it - drawn round the deck's own angle.
    public var handTurn: Double {
        guard let drag, drag.kind == .record, TurntableGeometry.moved(drag) || (live && deck.taken()) else { return turn }
        return turn + drag.turned * Self.degrees
    }

    /// The silent record's line (:288-290): from the first silent turn of the song until the song changes.
    public var silentLine: String? {
        let track = host.track()
        guard let turnedSilent, turnedSilent == track, !track.isEmpty else { return nil }
        return TurntableWords.silentNote(flac: host.flac(), noAudio: host.noAudio())
    }

    /// The deck lets go of the drag (the record taken by a press that rested): the hand's turn counts from here
    /// (the host's `grabbed`, Turntable.tsx:237).
    public func grabbed() {
        turned = true
        if var now = drag, now.kind == .record {
            now.offset = 0
            setDrag(now)
        }
    }

    /// The song changed (:270): a drag for the song before goes, and seeks nowhere.
    public func songChanged(_ track: String) {
        if let drag, TurntableGeometry.dragFor(drag, track) == nil { setDrag(nil) }
    }

    /// onRecordDown (:303): a finger on the record - the deck's press when it can sound there, .11's otherwise.
    public func recordDown(pointer: Int, x: Double, y: Double, time: Double?) {
        if let following, following.pointer != pointer { return }
        following = (pointer, true)
        turned = false
        let box = host.box()
        pressBox = box
        live = deck.live()
        setDrag(trig.recordStart(pointer, host.track(), x, y, box))
        if live { deck.pressed(PointerSamples.eventTime(time, host.now())) } else { deck.holdStill(true) }
    }

    /// onArmDown (:316)
    public func armDown(pointer: Int, x: Double, y: Double) {
        if let following, following.pointer != pointer { return }
        //? a press on an arm with no length is still the primary pointer, which a second finger isn't
        following = (pointer, false)
        if !(host.length() > 0) { return }
        pressBox = host.box()
        deck.armTaken()
        setDrag(trig.armStart(pointer, host.track(), x, y))
    }

    /// onMove (:323): `samples` the move's own, in order (PointerSamples.samples), the last where the finger is now.
    public func moved(pointer: Int, samples: [(time: Double, x: Double, y: Double)]) {
        guard let now = drag, let lastSample = samples.last else { return }
        let within = pressBox ?? host.box()
        let length = host.length()
        if now.kind == .record && live {
            var turning = now
            var changed = false
            for sample in samples {
                guard TurntableGeometry.moves(turning, .record, pointer),
                      let next = trig.recordMove(turning, pointer, sample.x, sample.y, within, length, deck.taken() ? deck.anchor() : host.drawnAt()),
                      next.kind == .record else { continue }
                if !deck.taken() {
                    deck.touched(sample.time, turned: next.turned, offset: next.offset)
                    if TurntableGeometry.moved(next) { deck.takeOver(sample.time, quick: true) }
                }
                if deck.taken() { deck.hand(sample.time, turned: next.turned, at: deck.anchor() + next.offset) }
                if TurntableGeometry.moved(next) { turned = true }
                turning = next
                changed = true
            }
            if changed { setDrag(turning) }
            return
        }
        guard TurntableGeometry.moves(now, now.kind, pointer) else { return }
        let next = now.kind == .record
            ? trig.recordMove(now, pointer, lastSample.x, lastSample.y, within, length, host.drawnAt())
            : trig.armMove(now, pointer, lastSample.x, lastSample.y, within, length, host.drawnAt())
        if let next, next.kind == .record, TurntableGeometry.moved(next) {
            turned = true
            let track = host.track()
            if turnedSilent != track { turnedSilent = track }
        }
        setDrag(next)
    }

    /// onRelease (:363), and for the lift of a touch that came down on the record the click's rule after it
    /// (onRecordClick, :401) - a cancel has none, nor has a second finger, which a browser sends no click for.
    public func ended(pointer: Int, how: DeckLetGo, time: Double?) {
        let followed = following?.pointer == pointer ? following : nil
        if followed != nil { following = nil }
        released(pointer: pointer, how: how, time: time)
        if how == .up && followed?.onRecord == true { recordClick() }
    }

    func released(pointer: Int, how: DeckLetGo, time: Double?) {
        let now = drag
        if how == .up, let now, now.pointer == pointer { host.wake() }
        let length = host.length()
        if let now, now.kind == .record, live, now.pointer == pointer {
            let taken = deck.taken()
            let out = deck.release(PointerSamples.eventTime(time, host.now()), cancel: how == .cancel)
            if how == .up && (TurntableGeometry.moved(now) || taken) {
                turn += now.turned * Self.degrees
                turned = true
            }
            setDrag(nil)
            if let seek = out.seek, length > 0 { host.seek(seek) }
            if out.play && !host.playing() { host.toggle() }
            return
        }
        if let now, now.kind == .record, now.pointer == pointer { deck.holdStill(false) }
        let end = TurntableGeometry.dragEnd(now, pointer, how, host.drawnAt(), length)
        if !end.ended { return }
        if let now, now.kind == .record, end.wasDrag, how == .up {
            turn += now.turned * Self.degrees
            turned = true
        }
        setDrag(end.drag)
        if let seek = end.seek, length > 0 { host.seek(seek) }
    }

    /// The touch the turntable follows let go as a cancel (an audio interruption, 4.6: after `DeckRules.interrupted()`)
    /// - nothing, with none.
    public func cancelFollowed() {
        guard let following else { return }
        ended(pointer: following.pointer, how: .cancel, time: nil)
    }

    /// onRecordClick (:401) - THE TAP: play or pause, nothing awaited before it.
    func recordClick() {
        host.wake()
        if turned {
            turned = false
            return
        }
        let length = host.length()
        if host.playing() {
            let landing = deck.pausing()
            host.toggle()
            if let landing, length > 0 { host.seek(landing) }
        } else {
            let from = deck.resuming()
            if let from, length > 0 { host.seek(from) }
            host.toggle()
        }
    }

    /// onArmKey (:417): a key on the arm seeks; returns whether it was one.
    @discardableResult
    public func armKey(_ key: String) -> Bool {
        guard let target = Scrub.keyTarget(key, from: host.shown(), length: host.length()) else { return false }
        host.seek(target)
        return true
    }

    /// NowPlaying.tsx's toggle (:282) with the turntable showing: a pause winds the record down, a play during a coast
    /// or a wind-down starts from where the record is.
    public static func toggle(_ deck: PressDeck?, _ host: PressHost) {
        host.wake()
        if host.playing() {
            let landing = deck?.pausing() ?? nil
            host.toggle()
            if let landing { host.seek(landing) }
            return
        }
        let from = deck?.resuming() ?? nil
        if let from { host.seek(from) }
        host.toggle()
    }
}
