import DeadwaxCore
import SwiftUI
import UIKit

/// A song row's swipe to Add to Queue (notes/ios.md "Add to Queue: the swipe, and the menus' one item"; 16 Nov, James:
/// "Can we also add swiping to add to queue"). Swipe a song row right, from its leading edge as Apple Music's are: a
/// full swipe adds the song, a partial one leaves one button, Add to Queue, standing; a light success haptic, and the
/// notice the •••'s Add to Queue says ("Added to Up Next: Roads" - none when the music starts from it, the mini player
/// saying so), which VoiceOver reads. On every row whose ••• offers Add to Queue, by the same rule (Core's
/// AddToQueue.pick of the row's own •••'s request) and through the same call (PlayerModel.addToQueue) - never on Up
/// Next's rows, a grid's tiles, or a row whose ••• leaves it out (offline, a song not on this phone).
///
/// TWO WAYS, ONE LOOK. A List's row (an album's page, a playlist's) takes SwiftUI's own leading swipe action - UIKit's
/// swipe, which already lives with the list's scroll and the back swipe, and is VoiceOver's action of the row. A row of
/// a ScrollView's stack (Library's Songs and All songs, Search) has no swipe actions, so it is drawn by hand: a
/// sideways pan (UIKit's, which never begins for a pan up or down, so the scroll is untouched; nor from the screen's
/// leading edge, the back swipe's; and iOS 26's back swipe from the content, and the Library's pager on its Songs
/// page, wait for it - a swipe right that starts on a song adds it there too) over Core's QueueSwipe, drawn as the
/// List's is - the purple out from the screen's edge, the symbol beside the row, one button's width open.
/// Those rows put the VoiceOver action on their main element themselves (`addToQueueAction`). Moving Songs and Search
/// to Lists instead would have re-laid-out both screens (Search's sections, slots and disclosures most of all) with
/// nothing to check them on but the phone.
extension View {
    /// The row's swipe. `request` is the row's own •••'s (nil: none).
    func addsToQueue(_ request: QueueMenuRequest?, in place: QueueRowPlace) -> some View {
        modifier(AddToQueueRow(request: request, place: place))
    }

    /// The row's VoiceOver action, "Add to Queue", on its main element - a stack's rows' (a List's swipe action is its
    /// row's action already). Offered where the swipe is.
    func addToQueueAction(_ request: QueueMenuRequest?) -> some View {
        modifier(AddToQueueAction(request: request))
    }
}

/// Where a song row with the swipe is drawn.
enum QueueRowPlace {
    /// A List's row: SwiftUI's own leading swipe action.
    case list
    /// A row of a ScrollView's stack, `inset` points in from the screen's leading edge (the stack's padding): the swipe
    /// drawn by hand, its purple running from the screen's edge as a List's does.
    case stack(inset: CGFloat)
}

/// What the swipe, its VoiceOver action and the ••• share: Core's rule for what a row's request adds, and the one call.
@MainActor
struct QueueAdder {
    let player: PlayerModel
    let downloads: DownloadModel
    let reachability: Reachability

    /// What Add to Queue adds of the request - nil: not offered.
    func pick(_ request: QueueMenuRequest?) -> QueuePick<Song>? {
        guard let request else { return nil }
        return AddToQueue.pick(request.pick, online: reachability.online, gone: request.gone, here: downloads.isHere)
    }

    /// Added, now - the rule asked again as it is now. True when something was queued.
    func add(_ request: QueueMenuRequest?) -> Bool {
        guard let request, let pick = pick(request) else { return false }
        return player.addToQueue(pick, album: request.album)
    }
}

private struct AddToQueueRow: ViewModifier {
    let request: QueueMenuRequest?
    let place: QueueRowPlace

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    /// One more each time the swipe added: the success haptic.
    @State private var added = 0

    @ViewBuilder func body(content: Content) -> some View {
        let adder = QueueAdder(player: player, downloads: downloads, reachability: reachability)
        let offered = adder.pick(request) != nil
        switch place {
        case .list:
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if offered {
                        Button {
                            add(adder)
                        } label: {
                            Label(AddToQueue.words, systemImage: AddToQueue.symbol)
                        }
                        .tint(Palette.queueSwipe)
                    }
                }
                .sensoryFeedback(.success, trigger: added)
        case .stack(let inset):
            content
                .modifier(HandSwipe(offered: offered, inset: inset) { add(adder) })
                .sensoryFeedback(.success, trigger: added)
        }
    }

    private func add(_ adder: QueueAdder) {
        if adder.add(request) { added += 1 }
    }
}

private struct AddToQueueAction: ViewModifier {
    let request: QueueMenuRequest?

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    func body(content: Content) -> some View {
        let adder = QueueAdder(player: player, downloads: downloads, reachability: reachability)
        let offered = adder.pick(request) != nil
        content.accessibilityActions {
            if offered {
                Button(AddToQueue.words) {
                    _ = adder.add(request)
                }
            }
        }
    }
}

/// The one stack row standing open: another opening shuts it, as a List's do.
@MainActor
@Observable
private final class OpenQueueSwipe {
    static let shared = OpenQueueSwipe()
    var row: UUID?
}

/// The swipe drawn by hand (Core's QueueSwipe has every number and decision): the row follows the finger rightwards;
/// past half the row a light tick, and letting go there adds and shuts it; let go with the button half out or more (or
/// flung right) and it stands open on the button - a tap on the button adds, a tap on the row, a swipe back, another
/// row opening or the list scrolling shuts it. Below iOS 18 (no UIKit gesture in SwiftUI) there is no swipe: the
/// row's VoiceOver action and its ••• are the way.
private struct HandSwipe: ViewModifier {
    let offered: Bool
    let inset: CGFloat
    let add: () -> Void

    /// How far right the row stands.
    @State private var offset: CGFloat = 0
    /// Where it stood as the pan began.
    @State private var from: CGFloat = 0
    @State private var panning = false
    @State private var width: CGFloat = 0
    /// Past the full swipe: the tick as it crosses.
    @State private var full = false
    @State private var me = UUID()

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            swiped(content)
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    private func swiped(_ content: Content) -> some View {
        let standing = offset > 0 && !panning
        return content
            .overlay {
                // standing open: a tap on the row shuts it, and plays or opens nothing
                if standing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { shut() }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .background(alignment: .leading) {
                if offset > 0 { button }
            }
            .gesture(SidewaysPan(enabled: offered, open: offset > 0, changed: moved, ended: letGo, cancelled: { shut() }))
            .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in
                proxy.size.width
            } action: { (now: CGFloat) -> Void in
                width = now
            }
            .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in
                proxy.frame(in: .global).minY
            } action: { (_: CGFloat) -> Void in
                // the list scrolled (or rows landed above): an open row shuts, as a List's does
                if offset > 0 && !panning { shut() }
            }
            .onChange(of: OpenQueueSwipe.shared.row) { _, row in
                if row != me, offset > 0, !panning { shut() }
            }
            .onChange(of: offered) { _, now in
                if !now { shut(animated: false) }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: full) { (was: Bool, now: Bool) -> Bool in now && !was }
    }

    /// The button behind the row: the purple from the screen's edge to `offset` (the gap the row's inset leaves
    /// between it and the row, as a List cell's), the symbol in its last button's width, beside the row.
    private var button: some View {
        Button {
            shut()
            add()
        } label: {
            Palette.queueSwipe
                .frame(width: offset)
                .overlay(alignment: .trailing) {
                    Image(systemName: AddToQueue.symbol)
                        .font(Typeface.symbol(.body).weight(.semibold))
                        .foregroundStyle(Palette.onQueueSwipe)
                        .frame(width: QueueSwipe.button)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -inset)
        // the row's own action says it (addToQueueAction)
        .accessibilityHidden(true)
    }

    private func moved(_ dx: CGFloat) {
        if !panning {
            panning = true
            from = offset
            OpenQueueSwipe.shared.row = me
        }
        offset = QueueSwipe.moved(dx, from: from, width: width)
        full = QueueSwipe.full(offset, width: width)
    }

    private func letGo(_ dx: CGFloat, _ velocity: CGFloat) {
        panning = false
        offset = QueueSwipe.moved(dx, from: from, width: width)
        full = false
        switch QueueSwipe.release(at: offset, velocity: velocity, width: width) {
        case .add:
            shut()
            add()
        case .open:
            withAnimation(.snappy(duration: 0.25)) { offset = QueueSwipe.button }
        case .shut:
            shut()
        }
    }

    private func shut(animated: Bool = true) {
        panning = false
        full = false
        if animated {
            withAnimation(.snappy(duration: 0.25)) { offset = 0 }
        } else {
            offset = 0
        }
        if OpenQueueSwipe.shared.row == me { OpenQueueSwipe.shared.row = nil }
    }
}

/// The hand-drawn swipe's pan: UIKit's, so it can refuse to begin - for a pan up or down (the list's scroll keeps it),
/// leftwards on a shut row, and from the screen's leading edge (the back swipe's) - which a SwiftUI DragGesture
/// inside a ScrollView can't. iOS 26's back swipe from the page's content, a sideways pan above it, waits for it to
/// fail, as it does for a List's swipe actions; the back swipe from the edge never does.
@available(iOS 18.0, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let open: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
    let cancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
        context.coordinator.open = open
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: nil).x
        switch recognizer.state {
        case .began, .changed:
            changed(dx)
        case .ended:
            ended(dx, recognizer.velocity(in: nil).x)
        case .cancelled, .failed:
            cancelled()
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// The row stands open: a pan leftwards may begin, to shut it.
        var open = false

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let moved = pan.translation(in: nil)
            let at = pan.location(in: nil)
            return QueueSwipe.begins(dx: moved.x, dy: moved.y, startX: at.x - moved.x, open: open)
        }

        /// Another sideways pan on the same touch waits for the row's to fail: iOS 26's back swipe from the page's
        /// content, and the Library's pager (its Songs page, with logins off) - a swipe right that starts on a song
        /// adds it, as everywhere else; leftwards, or from the screen's edge, the row's fails at once and the page
        /// turns. Never the list's own scroll (up and down only), nor the back swipe from the screen's edge.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard other is UIPanGestureRecognizer, !(other is UIScreenEdgePanGestureRecognizer) else { return false }
            if let scroll = other.view as? UIScrollView {
                return scroll.contentSize.width > scroll.bounds.width + 1
            }
            return true
        }
    }
}
