import DeadwaxCore
import SwiftUI
import UIKit

/// The cover viewer's zoom (notes/ios.md "The cover, full screen"), a UIScrollView through UIViewRepresentable: on iOS
/// 17 SwiftUI has a pinch (MagnifyGesture) and a drag but no zooming scroll view, so a pinch about the fingers, a pan
/// that stops at the image's edges and carries on with momentum, and a zoom to a rect would each be written again by
/// hand. UIScrollView does them all, as Photos' are.
///
/// - The cover is fitted to the screen at zoom 1, centred, and zooms to CoverZoom.maximum - a pinch, or a double-tap
///   (CoverZoom.doubleTapped) about the point tapped and back. Zoomed, a drag pans, never past the image's edges
///   (`bounces` off; only the pinch springs back from past its ends).
/// - At rest, a drag down (`dismissPan`, which the scroll view's own pan waits on) moves the cover with the finger and
///   says how far (`onDrag`, for the ground's fade); let go past CoverZoom.closes it closes (`onClose`), else springs
///   back. Zoomed, that pan never begins, and the scroll view's pans.
/// - A new image (the full size landing over the one drawn) crossfades in where the old one was, the zoom and the
///   place looked at kept.
/// - For VoiceOver the scroll view is the one element: the image, named for its album (`label`), adjustable - a swipe
///   up or down zooms (CoverZoom.stepped) and its value says the zoom - scrolled about with three fingers when zoomed,
///   and closed by the escape (two-finger Z), as the close button does.
struct CoverZoomer: UIViewRepresentable {
    let image: UIImage?
    let label: String
    /// How far down the cover is held (points), and whether that is a spring back to rest.
    let onDrag: (_ dragged: CGFloat, _ settling: Bool) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> CoverZoomHost {
        CoverZoomHost()
    }

    func updateUIView(_ host: CoverZoomHost, context: Context) {
        host.onDrag = onDrag
        host.onClose = onClose
        host.scroll.accessibilityLabel = label
        host.show(image)
    }
}

/// The scroll view's holder: it lays the scroll view over itself (by centre and size, so a drag's transform stands)
/// and owns the gestures.
final class CoverZoomHost: UIView, UIScrollViewDelegate {
    let scroll = CoverScrollView()
    private let imageView = UIImageView()
    private let doubleTap = UITapGestureRecognizer()
    private let dismissPan = UIPanGestureRecognizer()
    private let panRule = DismissPanRule()
    var onDrag: ((CGFloat, Bool) -> Void)?
    var onClose: (() -> Void)?
    /// The size the cover was last fitted to.
    private var fittedFor: CGSize = .zero
    /// Let go to close: the cover stays where it went while the viewer fades.
    private var closing = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        scroll.host = self
        scroll.delegate = self
        scroll.backgroundColor = .clear
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = CGFloat(CoverZoom.leastMaximum)
        scroll.bounces = false
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        scroll.addSubview(imageView)
        addSubview(scroll)

        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(doubleTapped(_:)))
        scroll.addGestureRecognizer(doubleTap)

        panRule.scroll = scroll
        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = panRule
        dismissPan.addTarget(self, action: #selector(panned(_:)))
        scroll.addGestureRecognizer(dismissPan)
        // zoomed, the close pan doesn't begin and the scroll view's pans; at rest the close pan has it
        scroll.panGestureRecognizer.require(toFail: dismissPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.bounds.size = bounds.size
        scroll.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if bounds.size != fittedFor {
            fittedFor = bounds.size
            fit(keepingPlace: true)
        }
    }

    /// The image to show: the first drawn at once, a later one (the full size) crossfaded in over it.
    func show(_ image: UIImage?) {
        guard image !== imageView.image else { return }
        let had = imageView.image != nil
        if had, let image, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: imageView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.imageView.image = image
            }
        } else {
            imageView.image = image
        }
        fit(keepingPlace: had)
    }

    // MARK: fitting and centring

    private var zoom: Double { Double(scroll.zoomScale) }

    /// The cover fitted to the screen at zoom 1, its maximum from its pixels - and, zoomed, the same zoom kept over the
    /// same place in it (a new image, the screen's size changing).
    private func fit(keepingPlace: Bool) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            scroll.zoomScale = 1
            imageView.frame = .zero
            scroll.contentSize = .zero
            return
        }
        let zoomed = keepingPlace && !CoverZoom.atRest(zoom)
        let kept = scroll.zoomScale
        let place = zoomed ? lookedAt() : nil
        scroll.zoomScale = 1
        let fitted = CoverZoom.fitted(width: Double(image.size.width), height: Double(image.size.height),
                                      inWidth: Double(bounds.width), inHeight: Double(bounds.height))
        imageView.frame = CGRect(x: 0, y: 0, width: fitted.width, height: fitted.height)
        scroll.contentSize = imageView.frame.size
        let pixels = Double(max(image.size.width, image.size.height) * image.scale)
        let most = CoverZoom.maximum(pixels: pixels, fitted: max(fitted.width, fitted.height),
                                     scale: Double(traitCollection.displayScale))
        scroll.maximumZoomScale = CGFloat(most)
        if let place {
            scroll.zoomScale = min(kept, CGFloat(most))
            centre()
            look(at: place)
        } else {
            centre()
            scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
        }
    }

    /// The cover centred while it is smaller than the screen either way: the room around it as insets, so a pan
    /// stops at its edges.
    private func centre() {
        let shown = imageView.frame.size
        let across = max(0, (scroll.bounds.width - shown.width) / 2)
        let down = max(0, (scroll.bounds.height - shown.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: down, left: across, bottom: down, right: across)
    }

    /// The point of the cover at the screen's centre, as a part of its width and height.
    private func lookedAt() -> CGPoint {
        let at = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: imageView)
        let size = imageView.bounds.size
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: at.x / size.width, y: at.y / size.height)
    }

    /// That point back at the screen's centre, as near as the cover's edges allow.
    private func look(at place: CGPoint) {
        let size = imageView.bounds.size
        let at = imageView.convert(CGPoint(x: place.x * size.width, y: place.y * size.height), to: scroll)
        scroll.contentOffset = clamped(CGPoint(x: at.x - scroll.bounds.width / 2, y: at.y - scroll.bounds.height / 2))
    }

    /// An offset kept inside the cover's edges.
    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scroll.contentInset
        let lowX = -inset.left
        let lowY = -inset.top
        let highX = max(lowX, scroll.contentSize.width - scroll.bounds.width + inset.right)
        let highY = max(lowY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        return CGPoint(x: min(max(offset.x, lowX), highX), y: min(max(offset.y, lowY), highY))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
    }

    // MARK: the gestures

    /// A double-tap: from rest, in about the point tapped; zoomed, back out.
    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        zoom(to: CoverZoom.doubleTapped(zoom, maximum: Double(scroll.maximumZoomScale)), about: tap.location(in: imageView),
             animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Zoomed to `target` about a point of the cover (its own points at zoom 1), or back to rest.
    private func zoom(to target: Double, about point: CGPoint, animated: Bool) {
        if CoverZoom.atRest(target) {
            scroll.setZoomScale(1, animated: animated)
            return
        }
        let shown = CoverZoom.zoomRect(x: Double(point.x), y: Double(point.y), zoom: target,
                                       width: Double(scroll.bounds.width), height: Double(scroll.bounds.height))
        scroll.zoom(to: CGRect(x: shown.x, y: shown.y, width: shown.width, height: shown.height), animated: animated)
    }

    /// The drag down that closes, at rest: the cover follows the finger, and is let go to close or to spring back.
    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard !closing else { return }
        let moved = pan.translation(in: self)
        switch pan.state {
        case .began, .changed:
            scroll.transform = CGAffineTransform(translationX: moved.x, y: moved.y)
            onDrag?(moved.y, false)
        case .ended:
            if CoverZoom.closes(dragged: Double(moved.y), speed: Double(pan.velocity(in: self).y)) {
                closing = true
                onClose?()
            } else {
                settle()
            }
        default:
            settle()
        }
    }

    /// Back to rest, springing.
    private func settle() {
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.scroll.transform = .identity
        }
        onDrag?(0, true)
    }

    // MARK: VoiceOver

    /// A swipe up (`zoomIn`) or down on the image: twice or half the zoom, about the middle of what is shown.
    fileprivate func step(zoomIn: Bool) {
        let target = CoverZoom.stepped(zoom, zoomIn: zoomIn, maximum: Double(scroll.maximumZoomScale))
        let middle = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: imageView)
        zoom(to: target, about: middle, animated: false)
    }

    /// A three-finger scroll, zoomed: most of a screen that way, never past the edges; false at rest or at an edge,
    /// so VoiceOver says there is no more.
    fileprivate func page(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard !CoverZoom.atRest(zoom) else { return false }
        let across = scroll.bounds.width * 0.8
        let down = scroll.bounds.height * 0.8
        var offset = scroll.contentOffset
        switch direction {
        case .up: offset.y += down
        case .down: offset.y -= down
        case .left: offset.x += across
        case .right: offset.x -= across
        default: return false
        }
        let moved = clamped(offset)
        guard moved != scroll.contentOffset else { return false }
        scroll.setContentOffset(moved, animated: false)
        let middle = lookedAt()
        UIAccessibility.post(notification: .pageScrolled,
                             argument: CoverViewerWords.showing(across: Double(middle.x), down: Double(middle.y)))
        return true
    }

    fileprivate func escape() -> Bool {
        guard !closing else { return true }
        closing = true
        onClose?()
        return true
    }
}

/// The zooming scroll view, VoiceOver's one element of the viewer: the image named for its album, its zoom adjustable.
final class CoverScrollView: UIScrollView {
    weak var host: CoverZoomHost?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .adjustable]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var accessibilityValue: String? {
        get { CoverViewerWords.zoom(Double(zoomScale)) }
        set {}
    }

    override var accessibilityHint: String? {
        get { CoverZoom.atRest(Double(zoomScale)) ? nil : CoverViewerWords.panHint }
        set {}
    }

    override func accessibilityIncrement() {
        host?.step(zoomIn: true)
    }

    override func accessibilityDecrement() {
        host?.step(zoomIn: false)
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        host?.page(direction) ?? false
    }

    override func accessibilityPerformEscape() -> Bool {
        host?.escape() ?? false
    }
}

/// When the drag that closes may begin: at rest, a drag more down than across.
@MainActor
private final class DismissPanRule: NSObject, UIGestureRecognizerDelegate {
    weak var scroll: UIScrollView?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let scroll,
              CoverZoom.atRest(Double(scroll.zoomScale)) else { return false }
        let moved = pan.translation(in: scroll)
        let speed = pan.velocity(in: scroll)
        let down = moved.y != 0 ? moved : speed
        return down.y > 0 && abs(down.y) > abs(down.x)
    }
}
