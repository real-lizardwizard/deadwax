/// The play speed and its fader - the web's ui/src/lib/playSpeed.ts, ported line for line (notes/ios-specs/
/// turntable.md 5.1): the speeds the player takes, in hundredths, the fader's octave scale and its 1x detent, its keys,
/// its place on the plinth and a finger on it. `PlaySpeed` holds what needs no transcendental function;
/// `PlaySpeedScale` the scale's log and pow, over a `DeckMaths` (Fixtures/deck/turntable.json, PlaySpeedTests). The
/// words it makes are TurntableWords'.

public enum PlaySpeed {
    /// The slowest and fastest the player plays (playSpeed.ts:24-25), and the song's own speed (:27).
    public static let min = 0.25
    public static let max = 2.0
    public static let normal = 1.0
    /// A drag within this of 1x lands on 1x exactly - the fader's detent (:29).
    public static let detentWidth = 0.02
    /// What an arrow key moves it by, and Page Up and Page Down (:31-32).
    public static let step = 0.01
    public static let page = 0.1

    /// The speed in hundredths (:35).
    public static func roundSpeed(_ speed: Double) -> Double {
        JSMath.round(speed * 100) / 100
    }

    /// Whether a value is a speed the player takes (:40).
    public static func isSpeed(_ value: Double) -> Bool {
        value.isFinite && value >= min && value <= max
    }

    /// Any number as a speed: held to the range, in hundredths - 1x for one that isn't a number (:45).
    public static func clampSpeed(_ speed: Double) -> Double {
        if !speed.isFinite { return normal }
        return roundSpeed(JSMath.max(min, JSMath.min(max, speed)))
    }

    /// The detent: a speed within SPEED_DETENT of 1x is 1x (:51).
    public static func detent(_ speed: Double) -> Double {
        Swift.abs(speed - normal) <= detentWidth + 1e-9 ? normal : speed
    }

    /// What a key does to the speed, nil for a key that isn't the fader's (:83).
    public static func speedKey(_ key: String, _ speed: Double) -> Double? {
        switch key {
        case "ArrowUp", "ArrowRight": return clampSpeed(speed + step)
        case "ArrowDown", "ArrowLeft": return clampSpeed(speed - step)
        case "PageUp": return clampSpeed(speed + page)
        case "PageDown": return clampSpeed(speed - page)
        case "Home": return min
        case "End": return max
        default: return nil
        }
    }

    // ----- the fader on the plinth (playSpeed.ts:104-153)

    /// The fader, in the plinth's units (:113): its line, top and bottom of its travel, the gap from the record, its
    /// slot, its knob and the mark at 1x.
    public static let fader = (x: 359.0, top: 150.0, bottom: 318.0, clear: 1.0, slot: 6.0, slotRadius: 2.0)
    public static let knob = (width: 20.0, height: 12.0, radius: 3.0, grip: 1.5, gripInset: 3.0)
    public static let mark = (overhang: 2.0, thick: 2.0)
    /// The readout under it (:123).
    public static let readout = (x: 344.0, y: 349.0)
    /// Where the fader's target may start: the record's rim (:127).
    public static let faderFrom = TurntableGeometry.record.x + TurntableGeometry.record.r + fader.clear

    /// The fader's touch target across the plinth, in its units, for a plinth `stage` points wide: a `hit` wide, at
    /// most `cap` of the stage, never over the record (:137).
    public static func faderTarget(_ stage: Double, hit: Double = 44, cap: Double = 0.14) -> (left: Double, right: Double) {
        let width = JSMath.min((hit / JSMath.max(stage, 1e-9)) * TurntableGeometry.stage.width, cap * TurntableGeometry.stage.width)
        let left = JSMath.max(faderFrom, fader.x - width / 2)
        return (left, left + width)
    }

    /// How far the knob travels on screen for a stage `height` tall (:151).
    public static func faderTravel(_ height: Double) -> Double {
        ((fader.bottom - fader.top) / TurntableGeometry.stage.height) * JSMath.max(0, height)
    }

    /// A finger on the fader (:157): where it went down, and once past the slop where the drag is measured from.
    public struct FaderDrag: Equatable, Sendable {
        public var pointer: Int
        public var y0: Double
        public var from: (y: Double, share: Double)?
        public static func == (a: FaderDrag, b: FaderDrag) -> Bool {
            a.pointer == b.pointer && a.y0 == b.y0 && a.from?.y == b.from?.y && a.from?.share == b.from?.share
        }
    }

    public static func faderStart(_ pointer: Int, _ y: Double) -> FaderDrag {
        FaderDrag(pointer: pointer, y0: y, from: nil)
    }

    /// The finger let go: the drag is over - unless it is another pointer's (:190).
    public static func faderEnd(_ drag: FaderDrag?, _ pointer: Int) -> FaderDrag? {
        guard let drag else { return nil }
        return drag.pointer == pointer ? nil : drag
    }
}

/// The fader's octave scale, over a `DeckMaths`.
public struct PlaySpeedScale<M: DeckMaths> {
    public let maths: M
    public init(_ maths: M) { self.maths = maths }

    /// How far up the fader a speed is, 0 to 1, by octaves (:56).
    public func faderShare(_ speed: Double) -> Double {
        let held = JSMath.max(PlaySpeed.min, JSMath.min(PlaySpeed.max, speed.isFinite ? speed : PlaySpeed.normal))
        return maths.log(held / PlaySpeed.min) / maths.log(PlaySpeed.max / PlaySpeed.min)
    }

    /// The speed at a share of the fader's travel, in hundredths, through the detent (:62).
    public func speedAt(_ share: Double) -> Double {
        let at = JSMath.max(0, JSMath.min(1, share.isFinite ? share : 0))
        return PlaySpeed.detent(PlaySpeed.clampSpeed(PlaySpeed.min * maths.pow(PlaySpeed.max / PlaySpeed.min, at)))
    }

    /// The knob's centre for a speed, as a CSS share of the stage's height (:146).
    public func knobTop(_ speed: Double) -> String {
        let fader = PlaySpeed.fader
        return TurntableGeometry.pct((fader.bottom - faderShare(speed) * (fader.bottom - fader.top)) / TurntableGeometry.stage.height)
    }

    /// The fader's drag moved (:177): nothing until past the slop, then the speed the finger's travel puts it at -
    /// `same` where the web hands the very drag back (anything but the move that passes the slop).
    public func faderMove(_ drag: PlaySpeed.FaderDrag?, _ pointer: Int, _ y: Double, _ travel: Double, _ speed: Double)
        -> (drag: PlaySpeed.FaderDrag?, speed: Double?, same: Bool) {
        guard let drag, drag.pointer == pointer, travel > 0 else { return (drag, nil, true) }
        var held = drag
        //? the web hands the very drag back once it has its `from`; a new one the move that sets it
        let same = held.from != nil
        if held.from == nil {
            let moved = y - held.y0
            if Swift.abs(moved) < TurntableGeometry.tapSlop { return (drag, nil, true) }
            held.from = (held.y0 + JSMath.sign(moved) * TurntableGeometry.tapSlop, faderShare(speed))
        }
        let from = held.from!
        return (held, speedAt(from.share + (from.y - y) / travel), same)
    }
}
