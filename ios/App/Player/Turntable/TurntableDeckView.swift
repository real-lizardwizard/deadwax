import DeadwaxCore
import DeadwaxTurntable
import UIKit

// The plinth on the screen (notes/ios-specs/turntable.md 2.2-2.6, 2.10, 3.1): DeadwaxTurntable's layer tree in a
// UIView, the record's and the arm's touch views over it, and the two VoiceOver elements the web's own roles are.
// Everything it shows is the DeckController's: the controller writes each frame through `draw(_:)`, and the touch views
// hand it their touches. The drawing itself takes no touch and says nothing to VoiceOver (the web's aria-hidden).
// The fader's touch view is slice 4's.

/// The turntable's UIKit view: the layers, the touch views, the accessibility elements.
final class TurntableDeckUIView: UIView {
    private let layers: TurntableLayers
    private weak var deck: DeckController?
    private let record: DeckTouchView
    private let arm: DeckTouchView
    private let recordElement: RecordElement
    private let armElement: ArmElement
    private(set) var layout: TurntableLayout

    init(deck: DeckController, layout: TurntableLayout, scale: CGFloat) {
        self.deck = deck
        self.layout = layout
        layers = TurntableLayers(layout: layout, scale: scale, flipped: false)
        record = DeckTouchView(kind: .record)
        arm = DeckTouchView(kind: .arm)
        recordElement = RecordElement(accessibilityContainer: NSObject())
        armElement = ArmElement(accessibilityContainer: NSObject())
        super.init(frame: CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        backgroundColor = .clear
        clipsToBounds = false
        layer.addSublayer(layers.root)
        for view in [record, arm] {
            view.deck = deck
            view.space = self
            addSubview(view)
        }
        recordElement.accessibilityContainer = self
        armElement.accessibilityContainer = self
        recordElement.deck = deck
        armElement.deck = deck
        isAccessibilityElement = false
        accessibilityElements = [recordElement, armElement]
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
    }

    /// A frame's drawing (2.6): the layers' transforms, the arm's touch view and VoiceOver frame on the needle.
    func draw(_ look: TurntableLook) {
        layers.set(look)
        let needle = layout.point(look.needle)
        arm.center = CGPoint(x: needle.x, y: needle.y)
        armElement.accessibilityFrameInContainerSpace = arm.frame
    }

    func setCover(_ image: CGImage?) { layers.setCover(image) }
    func setArt(_ image: CGImage?) { layers.setArt(image) }

    /// A touch outside the record's circle and the handle's passes through (3.1): the plinth itself is no control.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
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
    /// each touch's number, as a browser numbers its pointers
    private static var numbered = 0

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
        Self.numbered += 1
        let pointer = Self.numbered
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
        deck.touchMoved(pointer: pointer, samples: samples)
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
