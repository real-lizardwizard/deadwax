import DeadwaxCore
import DeadwaxTurntable
import UIKit

// The plinth on the screen (notes/ios-specs/turntable.md 2.2-2.6, 2.10, 3.1, 5.1): DeadwaxTurntable's layer tree in a
// UIView, the record's, the arm's and the fader's touch views over it, and the VoiceOver elements the web's own roles
// are - the record, the arm, the fader and the readout. Everything it shows is the DeckController's: the controller
// writes each frame through `draw(_:)`, and the touch views hand it their touches. The drawing itself takes no touch
// and says nothing to VoiceOver (the web's aria-hidden). The readout's face and its tap are drawn over Now Playing's
// column instead (TurntableReadoutLayer), above the line a failure lays over the plinth's foot; its VoiceOver element is
// here, in the web's reading order.

/// The turntable's UIKit view: the layers, the touch views, the accessibility elements.
final class TurntableDeckUIView: UIView {
    private let layers: TurntableLayers
    private weak var deck: DeckController?
    private let record: DeckTouchView
    private let arm: DeckTouchView
    private let fader: FaderTouchView
    private let recordElement: RecordElement
    private let armElement: ArmElement
    private let faderElement: FaderElement
    private let readoutElement: ReadoutElement
    private(set) var layout: TurntableLayout

    init(deck: DeckController, layout: TurntableLayout, scale: CGFloat) {
        self.deck = deck
        self.layout = layout
        layers = TurntableLayers(layout: layout, scale: scale, flipped: false)
        // the readout is drawn over Now Playing's column, above the foot line (TurntableReadoutLayer)
        layers.drawsReadout = false
        record = DeckTouchView(kind: .record)
        arm = DeckTouchView(kind: .arm)
        fader = FaderTouchView()
        recordElement = RecordElement(accessibilityContainer: NSObject())
        armElement = ArmElement(accessibilityContainer: NSObject())
        faderElement = FaderElement(accessibilityContainer: NSObject())
        readoutElement = ReadoutElement(accessibilityContainer: NSObject())
        super.init(frame: CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        backgroundColor = .clear
        clipsToBounds = false
        layer.addSublayer(layers.root)
        for view in [record, arm] {
            view.deck = deck
            view.space = self
            addSubview(view)
        }
        fader.deck = deck
        fader.space = self
        addSubview(fader)
        for element in [recordElement, armElement, faderElement, readoutElement] as [UIAccessibilityElement] {
            element.accessibilityContainer = self
        }
        recordElement.deck = deck
        armElement.deck = deck
        faderElement.deck = deck
        readoutElement.deck = deck
        isAccessibilityElement = false
        accessibilityElements = [recordElement, armElement, faderElement, readoutElement]
        place()
        deck.attach(self, layout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A new size for the plinth (the room changed: Dynamic Type, a notice): everything laid again.
    func relay(_ next: TurntableLayout) {
        guard next != layout else { return }
        layout = next
        layers.lay(next)
        place()
        deck?.attach(self, layout: next)
    }

    func detach() {
        deck?.detach(self)
    }

    private func place() {
        // the root's actions are none (TurntableLayers): a move is never animated
        layers.root.position = CGPoint(x: layout.width / 2, y: layout.height / 2)
        let face = layout.record
        record.frame = CGRect(x: face.left, y: face.top, width: face.width, height: face.height)
        recordElement.accessibilityFrameInContainerSpace = record.frame
        let size = layout.handleSize
        arm.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        // the fader's target: a tap wide beside the record, never on it (faderTarget), the knob's whole travel down
        let target = layout.faderTarget, span = layout.faderSpan
        fader.frame = CGRect(x: target.left, y: span.top, width: target.right - target.left, height: span.bottom - span.top)
        faderElement.accessibilityFrameInContainerSpace = fader.frame
    }

    /// A frame's drawing (2.6): the layers' transforms, the arm's touch view and VoiceOver frame on the needle.
    func draw(_ look: TurntableLook) {
        layers.set(look)
        let needle = layout.point(look.needle)
        arm.center = CGPoint(x: needle.x, y: needle.y)
        armElement.accessibilityFrameInContainerSpace = arm.frame
        // the readout's element where TurntableReadoutLayer draws it: its face or a tap's target, the larger
        let speed = look.speed ?? PlaySpeed.normal
        let points = TurntableReadout.points(layout, scaled: Double(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12)))
        let face = TurntableReadout.size(speed, points: points)
        let width = Swift.max(Double(face.width), layout.readoutTarget), height = Swift.max(Double(face.height), layout.readoutTarget)
        let at = layout.readout
        readoutElement.accessibilityFrameInContainerSpace = CGRect(x: at.x - width / 2, y: at.y - height / 2, width: width, height: height)
    }

    func setCover(_ image: CGImage?) { layers.setCover(image) }
    func setArt(_ image: CGImage?) { layers.setArt(image) }

    /// A touch outside the record's circle and the handle's passes through (3.1): the plinth itself is no control.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Each touch's number on the turntable, as a browser numbers its pointers - one count for the record, the arm and the
/// fader, so no two of them share one.
@MainActor
private enum TouchNumbers {
    static var last = 0
    static func next() -> Int {
        last += 1
        return last
    }
}

/// The record's or the arm's touch view (3.1): round, following one touch - the first that lands, as the web's element
/// follows one pointer - and handing the deck every coalesced sample of it, in order, in the deck view's points and
/// the host clock's milliseconds, deduplicated by the web's rule (PointerSamples). Never predicted touches: the voice
/// plays the hand 120 ms late so it never has to guess.
private final class DeckTouchView: UIView {
    let kind: TurntableDrag.Kind
    weak var deck: DeckController?
    /// the view whose points the press measures in (its box is that view's bounds)
    weak var space: UIView?
    private var following: (touch: UITouch, pointer: Int)?

    init(kind: TurntableDrag.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Round: the record's circle, the handle's ring.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let r = Swift.min(bounds.width, bounds.height) / 2
        let dx = point.x - bounds.midX, dy = point.y - bounds.midY
        return dx * dx + dy * dy <= r * r
    }

    private static func ms(_ seconds: TimeInterval) -> Double { seconds * 1_000 }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard following == nil, let touch = touches.first, let space, let deck else { return }
        let pointer = TouchNumbers.next()
        following = (touch, pointer)
        let at = touch.location(in: space)
        deck.touchDown(kind, pointer: pointer, x: Double(at.x), y: Double(at.y), time: Self.ms(touch.timestamp))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let following, touches.contains(following.touch), let space, let deck else { return }
        let touch = following.touch
        let pointer = following.pointer
        let raw = { (sample: UITouch) -> PointerSamples.Raw in
            let at = sample.location(in: space)
            return PointerSamples.Raw(pointerId: pointer, timeStamp: Self.ms(sample.timestamp), x: Double(at.x), y: Double(at.y))
        }
        let coalesced = event?.coalescedTouches(for: touch)?.map(raw)
        let samples = PointerSamples.samples(raw(touch), coalesced: coalesced, now: Self.ms(CACurrentMediaTime()))
        // Debug's recording (6.3) keeps what UIKit gave, before PointerSamples kept or dropped any: each sample's own
        // timestamp, seconds, and place
        let given = deck.isRecording ? (event?.coalescedTouches(for: touch) ?? [touch]).map { (sample: UITouch) -> (time: Double, x: Double, y: Double) in
            let at = sample.location(in: space)
            return (sample.timestamp, Double(at.x), Double(at.y))
        } : []
        deck.touchMoved(pointer: pointer, samples: samples, raw: given)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches, how: .up)
    }

    /// UIKit took the touch (a call's screen, the app leaving the front, Control Centre): the web's pointercancel.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches, how: .cancel)
    }

    private func end(_ touches: Set<UITouch>, how: DeckLetGo) {
        guard let following, touches.contains(following.touch) else { return }
        self.following = nil
        deck?.touchEnded(pointer: following.pointer, how: how, time: Self.ms(following.touch.timestamp))
    }
}

/// The fader's touch view (5.1, 3.1): its target - a tap wide beside the record, the knob's whole travel down -
/// following one touch, the first that lands, and only while the record and the arm follow none (the web's isPrimary).
/// Only where the finger is now matters (the speed follows it as it moves); a touch UIKit takes is let go where it had
/// got to, as the web's pointercancel.
private final class FaderTouchView: UIView {
    weak var deck: DeckController?
    weak var space: UIView?
    private var following: (touch: UITouch, pointer: Int)?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard following == nil, let touch = touches.first, let space, let deck else { return }
        let pointer = TouchNumbers.next()
        guard deck.faderDown(pointer: pointer, y: Double(touch.location(in: space).y)) else { return }
        following = (touch, pointer)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let following, touches.contains(following.touch), let space else { return }
        deck?.faderMoved(pointer: following.pointer, y: Double(following.touch.location(in: space).y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        end(touches)
    }

    private func end(_ touches: Set<UITouch>) {
        guard let following, touches.contains(following.touch) else { return }
        self.following = nil
        deck?.faderEnded(pointer: following.pointer)
    }
}

/// The record (2.10): a button named for what a tap does; activating it is the tap.
private final class RecordElement: UIAccessibilityElement {
    weak var deck: DeckController?

    override var accessibilityLabel: String? {
        get { deck?.recordLabel }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .button }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        deck?.recordActivated()
        return true
    }
}

/// The arm (2.10): adjustable, "Tonearm: position in the song", its value the clock line; a swipe moves it 5 s, as the
/// scrubber's. Not enabled while the song's length isn't known (the web's aria-disabled).
private final class ArmElement: UIAccessibilityElement {
    weak var deck: DeckController?

    override var accessibilityLabel: String? {
        get { TurntableWords.arm }
        set {}
    }

    override var accessibilityValue: String? {
        get { deck?.armValue }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { deck?.armAdjusts == true ? .adjustable : [.adjustable, .notEnabled] }
        set {}
    }

    override func accessibilityIncrement() {
        deck?.armAdjusted(increment: true)
    }

    override func accessibilityDecrement() {
        deck?.armAdjusted(increment: false)
    }
}

/// The fader (2.10): adjustable, "Speed", its value the speed in words ("normal speed", "1.25 times"); a swipe up or
/// down a hundredth (the web's arrow keys, SPEED_STEP), past the detent as the keys go - an increment from 1x is 1.01x.
private final class FaderElement: UIAccessibilityElement {
    weak var deck: DeckController?

    override var accessibilityLabel: String? {
        get { TurntableWords.fader }
        set {}
    }

    override var accessibilityValue: String? {
        get { deck?.faderValue }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .adjustable }
        set {}
    }

    override func accessibilityIncrement() {
        deck?.faderAdjusted(increment: true)
    }

    override func accessibilityDecrement() {
        deck?.faderAdjusted(increment: false)
    }
}

/// The readout (2.10): a button named for the speed and what a tap does - "Speed: normal", "Speed 1.25x: back to normal
/// speed" - not enabled at 1x, as the web's button is disabled there. Activating it is the tap.
private final class ReadoutElement: UIAccessibilityElement {
    weak var deck: DeckController?

    override var accessibilityLabel: String? {
        get { deck?.readoutLabel }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { deck?.player.speed == PlaySpeed.normal ? [.button, .notEnabled] : .button }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        deck?.readoutTapped()
        return true
    }
}
