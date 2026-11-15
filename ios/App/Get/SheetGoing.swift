import SwiftUI
import UIKit

/// (Phase 6, slice 3's review, finding 4) Says when the sheet it sits in starts going for good - a swipe down let go
/// past the point of no return, Cancel, a hand-over to Requests - rather than once its slide off the screen has ended,
/// which is when SwiftUI's onDisappear comes: the Sources sheet lets its search go then, so a pick landing during the
/// slide asks for nothing.
///
/// UIKit tells a view controller it will disappear as the dismissal's transition begins. For a swipe that is as the
/// finger starts it, and whether it will finish is known only once the finger lifts (`notifyWhenInteractionChanges`):
/// a swipe pulled back says nothing, and the search carries on. Only the sheet itself going counts (its presented
/// controller `isBeingDismissed`), never something shown over it. Nothing here is drawn or touchable.
///
/// What UIKit is relied on for - that a representable's controller inside a sheet hears viewWillDisappear as the sheet
/// goes - is read from UIKit's documented appearance forwarding, not yet seen on a phone (docs/ios.md's checks); the
/// sheet's onDisappear stays as the backstop.
struct SheetGoing: UIViewControllerRepresentable {
    let going: () -> Void

    func makeUIViewController(context: Context) -> Watcher {
        Watcher(going: going)
    }

    func updateUIViewController(_ watcher: Watcher, context: Context) {
        watcher.going = going
    }

    final class Watcher: UIViewController {
        var going: () -> Void

        init(going: @escaping () -> Void) {
            self.going = going
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard sheetIsGoing else { return }
            guard let coordinator = transitionCoordinator, coordinator.isInteractive else {
                going()
                return
            }
            // a swipe: going for good only once the finger lifts without pulling it back
            coordinator.notifyWhenInteractionChanges { [weak self] (context: any UIViewControllerTransitionCoordinatorContext) in
                if !context.isCancelled { self?.going() }
            }
        }

        /// The controller the sheet presents - the top of this one's parents - is being dismissed.
        private var sheetIsGoing: Bool {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            return top.isBeingDismissed
        }
    }
}
