/// The turntable's drawing and a finger on it - the web's ui/src/lib/turntable.ts, ported line for line (notes/ios-
/// specs/turntable.md 2.2-2.5, 3.1): the board's parts in the plinth's own units (372 by 368), the arm's angle for a
/// time and the time for an angle, the record's drag and the arm's, and what the time line shows while either moves.
/// `TurntableGeometry` holds the constants and the sums that need no transcendental function; `TurntableTrig` the
/// rest, over a `DeckMaths`, so with `RecordedMaths` it answers the web's very bits (Fixtures/deck/turntable.json,
/// TurntableGeometryTests). The words are TurntableWords'.

/// A point in the plinth's units, or on screen.
public struct StagePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A box on screen: the plinth's frame there.
public struct StageBox: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double
    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

/// A circle in the plinth's units.
public struct StageCircle: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var r: Double
    public init(x: Double, y: Double, r: Double) {
        self.x = x
        self.y = y
        self.r = r
    }
}

/// A finger on the record or on the arm (turntable.ts:193-222).
public struct TurntableDrag: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case record, arm }
    public var kind: Kind
    public var pointer: Int
    /// The song it began on - a drag doesn't outlive its song.
    public var track: String
    public var x0: Double
    public var y0: Double
    /// The farthest the finger has gone from where it went down.
    public var travel: Double
    /// The record's: the finger's angle round the spindle (nil on the spindle itself), how far it has turned the
    /// record, radians, and the seconds of song that turn is.
    public var angle: Double?
    public var turned: Double
    public var offset: Double
    /// The arm's: the finger's angle less the arm's when it passed the slop, and the time the arm is at.
    public var grab: Double?
    public var time: Double?
}

/// What the time line shows instead of the song's position (turntable.ts:228).
public enum TurntablePreview: Equatable, Sendable {
    case record(offset: Double)
    case arm(time: Double?)
    case deck(at: Double, scrubbing: Bool)
}

/// How a press ends: lifted, or taken by the system (a call, the app leaving the front - the web's pointercancel).
public enum DeckLetGo: String, Equatable, Sendable {
    case up, cancel
}

/// turntable.ts's constants (:52-84) and its sums that need no transcendental function.
public enum TurntableGeometry {
    /// Seconds of song one turn of the record is (:52).
    public static let secondsPerTurn = 1.8
    /// How far a finger goes before a press is a turn, not a tap: CSS px on the web, points on the phone (:55).
    public static let tapSlop = 8.0
    /// The spindle's share of the record's radius: a finger inside it turns nothing (:59).
    public static let spindleShare = 0.12
    /// The drawing's stage, the Turntable board's units (:63-84).
    public static let stage = (width: 372.0, height: 368.0)
    public static let platter = StageCircle(x: 178, y: 182, r: 168)
    public static let record = StageCircle(x: 178, y: 182, r: 160)
    public static let grooves = (outer: 148.0, inner: 64.0)
    public static let arm = (x: 348.0, y: 32.0, reach: 205.0)
    public static let armBar = (thick: 6.0, radius: 3.0)
    public static let armHead = (from: 193.0, length: 28.0, thick: 22.0, radius: 4.0)
    public static let armWeight = (from: -52.0, length: 34.0, thick: 18.0, radius: 5.0)
    public static let armBase = 22.0
    public static let armBaseEdge = 3.0
    public static let armLift = 5.0
    public static let armHandle = 56.0

    /// Degrees a radian (:101).
    public static let deg = 180 / Double.pi

    // ----- the drawing (turntable.ts:61-127)

    /// A share of the stage as the web writes it in CSS: `${+(share * 100).toFixed(4)}%` (:99).
    public static func pct(_ value: Double) -> String {
        "\(JSNumber.string(Double(jsFixed(value * 100, 4)) ?? .nan))%"
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        JSMath.max(low, JSMath.min(high, value))
    }

    /// A circle's box on the stage, as CSS percentages: left, top, width, height (:104).
    public static func placeCircle(_ circle: StageCircle) -> (left: String, top: String, width: String, height: String) {
        (pct((circle.x - circle.r) / stage.width), pct((circle.y - circle.r) / stage.height),
         pct((2 * circle.r) / stage.width), pct((2 * circle.r) / stage.height))
    }

    /// A point on the stage, as CSS percentages (:114).
    public static func placePoint(_ point: StagePoint) -> (left: String, top: String) {
        (pct(point.x / stage.width), pct(point.y / stage.height))
    }

    /// A length across the stage, as a CSS percentage of its width (:119).
    public static func across(_ length: Double) -> String {
        pct(length / stage.width)
    }

    /// A point on screen in the stage's units (:124).
    public static func toStage(_ x: Double, _ y: Double, _ box: StageBox) -> StagePoint {
        if !(box.width > 0) || !(box.height > 0) { return StagePoint(x: 0, y: 0) }
        return StagePoint(x: ((x - box.left) / box.width) * stage.width, y: ((y - box.top) / box.height) * stage.height)
    }

    // ----- the arm (turntable.ts:129-189)

    static func share(_ time: Double, _ length: Double) -> Double {
        length > 0 ? clamp(time / length, 0, 1) : 0
    }

    /// The groove the needle is in at a time: the outer groove at the start, the inner at the end (:137).
    public static func grooveRadius(_ time: Double, _ length: Double) -> Double {
        grooves.outer - (grooves.outer - grooves.inner) * share(time, length)
    }

    /// An angle wrapped to (-180, 180] (:168).
    static func wrapDegrees(_ angle: Double) -> Double {
        let turned = (((angle + 180).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 180
        return turned == -180 ? 180 : turned
    }

    // ----- a finger on the record, or on the arm (turntable.ts:191-368)

    /// The song's position as a drag reads it (:238).
    static func songAt(_ position: Double, _ length: Double) -> Double {
        length > 0 ? clamp(position, 0, length) : JSMath.max(0, JSMath.truthy(position) ? position : 0)
    }

    /// Whether a move by `pointer` moves this drag of this kind - the web's functions hand back the very drag they
    /// were given when it doesn't (`step === drag`), which TurntablePress tests by this.
    public static func moves(_ drag: TurntableDrag?, _ kind: TurntableDrag.Kind, _ pointer: Int) -> Bool {
        guard let drag else { return false }
        return drag.kind == kind && drag.pointer == pointer
    }

    /// Whether a drag has gone past the slop - a turn, not a tap (:307).
    public static func moved(_ drag: TurntableDrag?) -> Bool {
        guard let drag else { return false }
        return drag.travel >= tapSlop
    }

    /// What a drag shows on the time line (:316).
    public static func preview(_ drag: TurntableDrag?) -> TurntablePreview? {
        guard let drag else { return nil }
        if drag.kind == .record { return moved(drag) ? .record(offset: drag.offset) : nil }
        return .arm(time: drag.time)
    }

    /// The time the time line and the arm show (:324).
    public static func shownTime(_ previewing: TurntablePreview?, _ position: Double, _ length: Double) -> Double {
        let song = songAt(position, length)
        guard let previewing else { return song }
        let at: Double
        switch previewing {
        case .record(let offset): at = song + offset
        case .deck(let deckAt, _): at = deckAt
        case .arm(let time): at = time ?? song
        }
        return songAt(at, length)
    }

    /// Which words the time line leads with (:333).
    public static func previewWords(_ previewing: TurntablePreview?) -> TurntableDrag.Kind? {
        guard let previewing else { return nil }
        switch previewing {
        case .deck(_, let scrubbing): return scrubbing ? .record : nil
        case .record: return .record
        case .arm: return .arm
        }
    }

    /// Whether two previews show the same (:340).
    public static func samePreview(_ a: TurntablePreview?, _ b: TurntablePreview?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (.record(x)?, .record(y)?): return x == y
        case let (.arm(x)?, .arm(y)?): return x == y
        case let (.deck(x, s)?, .deck(y, t)?): return x == y && s == t
        default: return false
        }
    }

    /// A finger lifted (or taken by the system) (:356): the drag after it, the seek a drag past the slop asks for, and
    /// whether it was a drag - and `ended`, false where the web hands the very drag back (another pointer's lift).
    public static func dragEnd(_ drag: TurntableDrag?, _ pointer: Int, _ how: DeckLetGo, _ position: Double, _ length: Double)
        -> (drag: TurntableDrag?, seek: Double?, wasDrag: Bool, ended: Bool) {
        guard let drag, drag.pointer == pointer else { return (drag, nil, false, false) }
        let went = moved(drag)
        if how != .up || !went || (drag.kind == .record && drag.offset == 0) { return (nil, nil, went, true) }
        return (nil, shownTime(preview(drag), position, length), true, true)
    }

    /// A drag only while its song plays (:366).
    public static func dragFor(_ drag: TurntableDrag?, _ track: String) -> TurntableDrag? {
        guard let drag else { return nil }
        return WebText.same(drag.track, track) ? drag : nil
    }

    /// The disc of the album the song is on, 1 when it says none (:405).
    public static func playingDisc(_ songs: [(id: String, discNumber: Double?)]?, _ trackId: String) -> Int {
        guard let disc = songs?.first(where: { WebText.same($0.id, trackId) })?.discNumber, disc.isFinite, disc >= 1 else { return 1 }
        return Int(disc.rounded(.down))
    }

    /// deadwax's CD art route for a disc (:412).
    public static func discArtPath(_ albumId: String?, _ disc: Double) -> String? {
        guard let albumId, !albumId.isEmpty else { return nil }
        let number = disc >= 1 ? disc.rounded(.down) : 1
        return "/library/disc_art/navidrome?album=\(encodeURIComponent(albumId))&disc=\(JSNumber.string(number))"
    }

    /// encodeURIComponent: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ) as %XX of its UTF-8.
    static func encodeURIComponent(_ text: String) -> String {
        let digits = Array("0123456789ABCDEF")
        var out = ""
        for byte in text.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E, 0x21, 0x7E, 0x2A, 0x27, 0x28, 0x29:
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out += "%\(digits[Int(byte >> 4)])\(digits[Int(byte & 15)])"
            }
        }
        return out
    }
}

/// turntable.ts's sums that take a transcendental function, over a `DeckMaths`.
public struct TurntableTrig<M: DeckMaths> {
    public let maths: M
    public init(_ maths: M) { self.maths = maths }

    /// Where the needle is on a groove of radius `r`: where the arm's reach from its pivot meets it (:143).
    func needleOn(_ r: Double) -> StagePoint {
        let arm = TurntableGeometry.arm, record = TurntableGeometry.record
        let dx = arm.x - record.x, dy = arm.y - record.y
        let d = maths.hypot(dx, dy)
        let ux = dx / d, uy = dy / d
        let a = (r * r - arm.reach * arm.reach + d * d) / (2 * d)
        let h = JSMath.max(0, r * r - a * a).squareRoot()
        return StagePoint(x: record.x + a * ux - h * uy, y: record.y + a * uy + h * ux)
    }

    /// The needle's place at a time (:152).
    public func needleAt(_ time: Double, _ length: Double) -> StagePoint {
        needleOn(TurntableGeometry.grooveRadius(time, length))
    }

    /// A point's angle from the arm's pivot, degrees (:158).
    public func angleFromPivot(_ point: StagePoint) -> Double {
        maths.atan2(point.y - TurntableGeometry.arm.y, point.x - TurntableGeometry.arm.x) * TurntableGeometry.deg
    }

    /// The arm's angle for a time (:163).
    public func armAngle(_ time: Double, _ length: Double) -> Double {
        angleFromPivot(needleAt(time, length))
    }

    /// The time an arm angle puts the needle at - held to the grooves (:179).
    public func armTimeAt(_ angle: Double, _ length: Double) -> Double {
        if !(length > 0) { return 0 }
        let grooves = TurntableGeometry.grooves, arm = TurntableGeometry.arm, record = TurntableGeometry.record
        let outer = angleFromPivot(needleOn(grooves.outer))
        let span = TurntableGeometry.wrapDegrees(angleFromPivot(needleOn(grooves.inner)) - outer)
        var off = TurntableGeometry.wrapDegrees(angle - outer)
        let inside = span >= 0 ? off >= 0 && off <= span : off <= 0 && off >= span
        if !inside { off = Swift.abs(off) <= Swift.abs(TurntableGeometry.wrapDegrees(off - span)) ? 0 : span }
        let theta = (outer + off) / TurntableGeometry.deg
        let r = maths.hypot(arm.x + arm.reach * maths.cos(theta) - record.x, arm.y + arm.reach * maths.sin(theta) - record.y)
        return TurntableGeometry.clamp((grooves.outer - r) / (grooves.outer - grooves.inner), 0, 1) * length
    }

    func travelled(_ drag: TurntableDrag, _ x: Double, _ y: Double) -> Double {
        JSMath.max(drag.travel, maths.hypot(x - drag.x0, y - drag.y0))
    }

    /// The finger's angle round the spindle, radians - nil on the spindle (:243).
    func recordAngle(_ x: Double, _ y: Double, _ box: StageBox) -> Double? {
        let at = TurntableGeometry.toStage(x, y, box)
        let record = TurntableGeometry.record
        let dx = at.x - record.x, dy = at.y - record.y
        return maths.hypot(dx, dy) < TurntableGeometry.spindleShare * record.r ? nil : maths.atan2(dy, dx)
    }

    /// A finger down on the record (:249).
    public func recordStart(_ pointer: Int, _ track: String, _ x: Double, _ y: Double, _ box: StageBox) -> TurntableDrag {
        TurntableDrag(kind: .record, pointer: pointer, track: track, x0: x, y0: y, travel: 0, angle: recordAngle(x, y, box), turned: 0, offset: 0,
                      grab: nil, time: nil)
    }

    /// The record's drag moved (:261): the turn round the spindle since the last move (the short way), and the
    /// seconds of song it is, held to the song.
    public func recordMove(_ drag: TurntableDrag?, _ pointer: Int, _ x: Double, _ y: Double, _ box: StageBox, _ length: Double,
                           _ position: Double) -> TurntableDrag? {
        guard let drag, TurntableGeometry.moves(drag, .record, pointer) else { return drag }
        let angle = recordAngle(x, y, box)
        var delta = 0.0
        if let angle, let before = drag.angle {
            delta = angle - before
            if delta > Double.pi { delta -= 2 * Double.pi }
            if delta < -Double.pi { delta += 2 * Double.pi }
        }
        let at = TurntableGeometry.songAt(position, length)
        let offset = length > 0
            ? TurntableGeometry.clamp(drag.offset + (delta / (2 * Double.pi)) * TurntableGeometry.secondsPerTurn, -at, length - at)
            : drag.offset
        var next = drag
        next.travel = travelled(drag, x, y)
        next.angle = angle
        next.turned = drag.turned + delta
        next.offset = offset
        return next
    }

    /// A finger down on the arm's handle (:277).
    public func armStart(_ pointer: Int, _ track: String, _ x: Double, _ y: Double) -> TurntableDrag {
        TurntableDrag(kind: .arm, pointer: pointer, track: track, x0: x, y0: y, travel: 0, angle: nil, turned: 0, offset: 0, grab: nil, time: nil)
    }

    /// The arm's drag moved (:289): nothing until past the slop; then the arm follows the finger's angle from the
    /// pivot, less where it was grabbed.
    public func armMove(_ drag: TurntableDrag?, _ pointer: Int, _ x: Double, _ y: Double, _ box: StageBox, _ length: Double,
                        _ position: Double) -> TurntableDrag? {
        guard let drag, TurntableGeometry.moves(drag, .arm, pointer) else { return drag }
        let travel = travelled(drag, x, y)
        var next = drag
        next.travel = travel
        if travel < TurntableGeometry.tapSlop { return next }
        let finger = angleFromPivot(TurntableGeometry.toStage(x, y, box))
        let grab: Double
        if let held = drag.grab {
            grab = held
        } else {
            let share = TurntableGeometry.tapSlop / JSMath.max(TurntableGeometry.tapSlop, maths.hypot(x - drag.x0, y - drag.y0))
            let edge = TurntableGeometry.toStage(drag.x0 + (x - drag.x0) * share, drag.y0 + (y - drag.y0) * share, box)
            grab = armAngle(TurntableGeometry.songAt(position, length), length) - angleFromPivot(edge)
        }
        next.grab = grab
        next.time = armTimeAt(finger + grab, length)
        return next
    }
}

/// The turntable's parts on a plinth of a given width, in points - the web's CSS percentages of the stage, laid out
/// (notes/ios-specs/turntable.md 2.2-2.5): what the view draws and where its touch views sit.
public struct TurntableLayout: Equatable, Sendable {
    /// The plinth's size, points.
    public let width: Double
    public let height: Double

    public init(width: Double) {
        self.width = width
        height = width * TurntableGeometry.stage.height / TurntableGeometry.stage.width
    }

    /// A stage point, in points from the plinth's top left.
    public func point(_ point: StagePoint) -> StagePoint {
        StagePoint(x: point.x / TurntableGeometry.stage.width * width, y: point.y / TurntableGeometry.stage.height * height)
    }

    /// A stage circle's frame, in points.
    public func frame(_ circle: StageCircle) -> StageBox {
        StageBox(left: (circle.x - circle.r) / TurntableGeometry.stage.width * width, top: (circle.y - circle.r) / TurntableGeometry.stage.height * height,
                 width: (2 * circle.r) / TurntableGeometry.stage.width * width, height: (2 * circle.r) / TurntableGeometry.stage.height * height)
    }

    /// A length across the stage, in points.
    public func across(_ length: Double) -> Double {
        length / TurntableGeometry.stage.width * width
    }

    public var platter: StageBox { frame(TurntableGeometry.platter) }
    public var record: StageBox { frame(TurntableGeometry.record) }
    /// The label - 38.75% of the face (app.css's `.app-tt-label`), centred - its ring inside it, the cover inside that
    /// (TurntableFaceParts: the web's boxes are border-box).
    public var label: StageBox { centred(record.width * TurntableFace.labelShare) }
    /// The spindle: 6.25% of the face (`.app-tt-spindle`), centred, its ring inside it.
    public var spindle: StageBox { centred(record.width * TurntableFace.spindleShare) }
    /// A circle `across` points wide on the record's centre.
    func centred(_ across: Double) -> StageBox {
        let box = record
        return StageBox(left: box.left + (box.width - across) / 2, top: box.top + (box.height - across) / 2, width: across, height: across)
    }
    /// The arm's handle, points across (app.css:1314): the stage's 56 units, at least a tap's 44 pt - unless that is
    /// more than 30% of the plinth, which is then the most it is.
    public var handleSize: Double {
        Swift.max(handle, Swift.min(TurntableFace.hit, TurntableFace.handleCap * width))
    }
    public var pivot: StagePoint { point(StagePoint(x: TurntableGeometry.arm.x, y: TurntableGeometry.arm.y)) }
    public var readout: StagePoint { point(StagePoint(x: PlaySpeed.readout.x, y: PlaySpeed.readout.y)) }
    /// The arm's handle's ring and the arm's reach, points.
    public var handle: Double { across(TurntableGeometry.armHandle) }
    public var reach: Double { across(TurntableGeometry.arm.reach) }
    /// The fader's touch target at a 44 pt hit (playSpeed.ts faderTarget), in points.
    public var faderTarget: (left: Double, right: Double) {
        let target = PlaySpeed.faderTarget(width)
        return (across(target.left), across(target.right))
    }
    /// How far the fader's knob travels, points (playSpeed.ts faderTravel).
    public var faderTravel: Double { PlaySpeed.faderTravel(height) }
    /// The fader's target top to bottom, points: the knob's whole travel and a knob's height (SpeedFader.tsx's SPAN).
    public var faderSpan: (top: Double, bottom: Double) {
        let f = PlaySpeed.fader, knob = PlaySpeed.knob
        let top = f.top - knob.height / 2, bottom = f.bottom + knob.height / 2
        return (top / TurntableGeometry.stage.height * height, bottom / TurntableGeometry.stage.height * height)
    }
    /// The readout's least target, points across and down (app.css `.app-tt-readout`'s min-width and min-height:
    /// a tap's 44 pt, at most 14% of the plinth).
    public var readoutTarget: Double { Swift.min(TurntableFace.hit, 0.14 * width) }
}

/// A pointer's samples, as the deck is handed them (the web's ui/src/lib/deckClock.ts eventTime and pointerSamples,
/// :232-277): every coalesced sample of the one pointer, in order, none earlier than the one before nor the same twice.
/// On the phone, a touch's `coalescedTouches` are the list and the touch itself the event (the spec's 3.1).
public enum PointerSamples {
    /// How old an event's stamp may be before the page's clock is used instead (deckClock.ts:110).
    public static let staleMs = 1000.0

    public struct Raw: Equatable, Sendable {
        public var pointerId: Int
        public var timeStamp: Double?
        public var x: Double
        public var y: Double
        public init(pointerId: Int, timeStamp: Double?, x: Double, y: Double) {
            self.pointerId = pointerId
            self.timeStamp = timeStamp
            self.x = x
            self.y = y
        }
    }

    /// An event's own time, or the clock's for one not given, in the future or stale (:232).
    public static func eventTime(_ stamp: Double?, _ now: Double) -> Double {
        guard let stamp, stamp.isFinite, !(stamp > now + 1), !(stamp < now - staleMs) else { return now }
        return stamp
    }

    /// The samples of an event: its coalesced ones of the same pointer (nil for none given), then the event itself
    /// unless the last of them is it (:258).
    public static func samples(_ event: Raw, coalesced: [Raw]?, now: Double) -> [(time: Double, x: Double, y: Double)] {
        var own = (coalesced ?? []).filter { $0.pointerId == event.pointerId }
        if let last = own.last, last.timeStamp == event.timeStamp, last.x == event.x, last.y == event.y {
            // the event is its own last coalesced sample
        } else {
            own.append(event)
        }
        var samples: [(time: Double, x: Double, y: Double)] = []
        for sample in own {
            let time = eventTime(sample.timeStamp, now)
            if let before = samples.last, time < before.time || (time == before.time && sample.x == before.x && sample.y == before.y) { continue }
            samples.append((time, sample.x, sample.y))
        }
        return samples
    }
}
