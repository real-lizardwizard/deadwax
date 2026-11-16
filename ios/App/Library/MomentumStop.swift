import SwiftUI
import UIKit

/// A Library list's momentum, stopped by its index (notes/ios.md "The letter bar beats momentum"; James: "if the
/// library is still scrolling by momentum, I can't use the letter bar on the right side. I'd like that seek bar to
/// override the momentum").
///
/// Why it is needed: the index (ShelfIndexStrip) is laid over the list, not in it, so a finger on it never reaches the
/// list's UIScrollView - which is why it didn't stop the list as a touch on the list does - and its jump, a
/// ScrollViewReader `scrollTo`, can be dropped by SwiftUI while that scroll view is still decelerating: the list flies
/// on as if the index hadn't been touched (the haptic tick still comes). Measured on this Mac's Catalyst build of the
/// same SwiftUI as iOS 27.2: a `scrollTo` during a deceleration was dropped in three flings of seven - SwiftUI never set
/// the offset, and the list glided on to the end; the same deceleration stopped first with
/// `setContentOffset(contentOffset, animated: false)` - UIKit's own stop, which ends a deceleration and tells the
/// scroll view's delegate - took the jump in seven of seven.
///
/// So the index stops the list itself, at touch-down, before it jumps: `stop()`. The list's UIScrollView is found by a
/// view of no size inside the list's content (`stopsMomentum(_:)`), up its superviews.
@MainActor
final class MomentumStop {
    /// The list's scroll view, found from inside its content.
    fileprivate(set) weak var scrollView: UIScrollView?

    init() {}

    /// The list stopped where it is, if it is still moving by momentum - nothing at rest. `isDecelerating` is UIKit's
    /// own "the finger is up and it glides on" (a finger on the list stops a glide and ends it), so it asks no more. The
    /// jump that follows then takes.
    func stop() {
        guard let scrollView, scrollView.isDecelerating else { return }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }
}

extension View {
    /// Put on a ScrollView's content: finds that scroll view for `stop`, from a view of no size at the content's top
    /// that takes no touch and VoiceOver doesn't see.
    func stopsMomentum(_ stop: MomentumStop) -> some View {
        background(alignment: .top) {
            ScrollViewFinder(stop: stop)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

private struct ScrollViewFinder: UIViewRepresentable {
    let stop: MomentumStop

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.stop = stop
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.stop = stop
        view.find()
    }
}

private final class FinderView: UIView {
    weak var stop: MomentumStop?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        find()
    }

    /// The nearest scroll view up the superviews: the list's own (the Library's pager, across, is further up).
    func find() {
        guard window != nil, let stop else { return }
        var at = superview
        while let view = at {
            if let scrollView = view as? UIScrollView {
                if stop.scrollView !== scrollView { stop.scrollView = scrollView }
                return
            }
            at = view.superview
        }
    }
}
