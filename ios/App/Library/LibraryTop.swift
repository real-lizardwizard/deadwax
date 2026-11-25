import DeadwaxCore
import SwiftUI
import UIKit

/// The Library's top - since the redesign's slice R2b (notes/ios.md "The redesign, slice R2b: the Library's top, one
/// row again") one row again, iLibrary's .ltop. James, 25 Nov: "The top of the library on iOS is actually kinda a
/// mess, can we streamline it a bit?" So it is his own row from 14 Nov (the squared look - notes/ios.md "The squared
/// look": "let's put a magnifying glass button on the left side of the slider", "but the search button and options
/// button at the top can be circles") in the redesign's look: Find's circle 16 in from the leading edge, the switch of
/// the pages filling the room between - one square well of equal segments, the page shown lit, the pages in the order
/// kept - 12 from each circle, and the •••'s circle 16 in from the trailing edge (PhoneCircleStyle, the look's raised
/// face drawn round), 52 tall at least (LibraryTopRow). Where the switch's equal segments need more than the row leaves
/// them (LibraryTopFit - four pages at the larger text sizes on a narrow phone) it folds onto a row of its own under
/// the circles rather than cut a word short. Capped at xxxLarge, as the bars are. Find opens its field under the row,
/// with Cancel, as it always has. Over the phone's own black ground (`.dw.ph`), running up under the status bar; each
/// page's quiet line (PhoneMeta, LibraryLineEnd) and the offline banner under it. R2 (25 Nov, the same day) had drawn
/// it as iLibrary's first titled top - "Library", Yours | All, Find and the ••• as small square buttons - with a strip
/// of the pages and Downloaded under it; the title and the strip went, Yours | All moved to the line, Downloaded back
/// to the •••.
///
/// The row measures itself (15 Nov, James, a second time: "the library's top still doesn't clear the dynamic island"):
/// laid out in the safe area its views are given, it still stood in the island's strip on his iPhone 17 Pro, so it
/// comes down by whatever of the window's own top safe area its top, as drawn on the screen, doesn't clear
/// (TopClearance) - nothing, laid out as it should be.
///
/// Read by UIKit since 18 Nov (James: "after pulling up the play screen and going back to library, the top bar is back
/// inside the Dynamic Island"; notes/ios.md "The Library's top after Now Playing"): a probe behind the row (TopProbe)
/// reads where the row's top is in its own window and that window's top inset - never SwiftUI's global space, never a
/// guessed key window - each time UIKit puts it in a window, lays it out or changes its safe area, a presentation the
/// app made goes, the scene comes to the front, and SwiftUI asks (the row appearing, its geometry changing). Under a
/// presentation the row keeps the room it has; with nothing presented it is measured afresh (TopClearance.room). The
/// last reading is Debug's (DebugModel.libraryTop).
///
/// Too low after Now Playing (20 Nov, James: "well now the whole screen is too low", "It's after I leave the player";
/// notes/ios.md "The Library's top, too low after Now Playing"): read as the tabs came back into the window, the row was
/// 117 points above its top edge, came down twice the inset, then settled at the edge with nothing telling the probe. So
/// a row above its window's top edge keeps the room it has (TopClearance.settled), and every ask is followed by reads
/// again for a while, whatever is presented, so the row is read once it has settled.
struct LibraryTop<Find: View, Switch: View, More: View>: View {
    /// Find is open: its field drawn under the row.
    let finding: Bool
    /// The magnifying glass's words: the page shown's own Find prompt ("Find in albums").
    let findLabel: String
    /// The magnifying glass: Find opened (or its field focused again).
    let openFind: () -> Void
    /// The switch's words - the pages shown, in the order kept: what its equal segments need across is measured from
    /// them (DWSegmentedNeed), so the row knows whether it holds the switch.
    let pages: [String]
    @ViewBuilder let find: Find
    /// The switch of the pages (DWSegmented, large).
    @ViewBuilder let switcher: Switch
    @ViewBuilder let more: More

    @Environment(DebugModel.self) private var debug
    /// How far the row comes down under the status bar and the island (TopClearance.room): measured afresh with nothing
    /// presented, kept as it is under a presentation.
    @State private var clearance: CGFloat = 0
    /// The probe behind the row, for SwiftUI's own moments: the row appearing, SwiftUI's geometry for it changing.
    @State private var eyes = TopProbe.Eyes()
    /// What SwiftUI last said of the row - its top in SwiftUI's global space, its top safe area - for Debug's reading.
    @State private var swiftUI: [CGFloat] = []
    /// What the switch needs across and the row's width, as last laid out: whether the row folds, for VoiceOver's
    /// order (LibraryTopRow places by its own measure, never by these).
    @State private var needs: CGFloat = 0
    @State private var wide: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // iLibrary's .ltop: Find's circle, the switch, the •••'s circle - and, hidden, what the switch needs
            LibraryTopRow {
                Button(action: openFind) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(PhoneCircleStyle())
                .accessibilityLabel(findLabel)
                .accessibilityShowsLargeContentViewer {
                    Label(findLabel, systemImage: "magnifyingglass")
                }
                .accessibilitySortPriority(LibraryTopFit.priority(.find, folds: folds))
                switcher
                    .accessibilitySortPriority(LibraryTopFit.priority(.switcher, folds: folds))
                more
                    .accessibilitySortPriority(LibraryTopFit.priority(.more, folds: folds))
                DWSegmentedNeed(words: pages)
                    .onGeometryChange(for: CGFloat.self) { (need: GeometryProxy) -> CGFloat in
                        need.size.width
                    } action: { (width: CGFloat) -> Void in
                        needs = width
                    }
            }
            // VoiceOver reads the row as it is drawn (LibraryTopFit.reading): folded, the circles before the switch
            .accessibilityElement(children: .contain)
            .onGeometryChange(for: CGFloat.self) { (row: GeometryProxy) -> CGFloat in
                row.size.width
            } action: { (width: CGFloat) -> Void in
                wide = width
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if finding {
                find
                    .padding(.horizontal, LibraryLook.side)
                    .padding(.bottom, LibraryLook.findBelow)
                    .transition(.opacity)
            }
        }
        .padding(.top, clearance)
        .frame(maxWidth: .infinity)
        .background {
            Palette.page
                .ignoresSafeArea(.container, edges: .top)
        }
        // the row's own frame, never the fill's: its top is the row's top, its padding inside it, so coming down never
        // moves what it reads
        .background {
            TopProbe(eyes: eyes) { (sample: TopProbe.Sample) -> Void in
                take(sample)
            }
        }
        // SwiftUI's account of the row - its top in SwiftUI's global space, the safe area it is given: either changed,
        // the probe reads at once, in this pass, where the room changed before the probe, and again once UIKit has laid
        // out what moved (SwiftUI's numbers are Debug's, never the room's)
        .onGeometryChange(for: [CGFloat].self) { (proxy: GeometryProxy) -> [CGFloat] in
            [proxy.frame(in: .global).minY, proxy.safeAreaInsets.top]
        } action: { (measured: [CGFloat]) -> Void in
            swiftUI = measured
            eyes.probe?.now("geometry")
            eyes.probe?.soon("geometry")
        }
        // back on screen - the tabs back from under Now Playing's full-screen cover, another tab, a page popped: read
        // again, once what is under way is laid out
        .onAppear { eyes.probe?.soon("appear") }
    }

    /// Whether the row folds its switch under its circles, as last laid out (LibraryTopFit.folds) - nothing laid out yet,
    /// not.
    private var folds: Bool {
        wide > 0 && LibraryTopFit.folds(needs: Double(needs), width: Double(wide))
    }

    /// The probe's reading: the room worked out again (TopClearance.room - kept under a presentation, afresh otherwise),
    /// and the reading kept for Debug, each only when it changed.
    private func take(_ sample: TopProbe.Sample) {
        let room = TopClearance.room(kept: Double(clearance), top: Double(sample.top), windowTop: Double(sample.windowTop),
                                     presented: sample.presented)
        if CGFloat(room) != clearance { clearance = CGFloat(room) }
        let said = swiftUI.count == 2 ? swiftUI.map { (value: CGFloat) -> Double in Double(value) } : nil
        let reading = TopClearance.Reading(top: Double(sample.top), windowTop: Double(sample.windowTop), room: room,
                                           presented: sample.presented, cause: sample.cause,
                                           swiftTop: said?[0], swiftSafe: said?[1])
        if debug.libraryTop != reading { debug.libraryTop = reading }
    }
}

/// (R2b) iLibrary's .ltop laid out where Core puts each view (LibraryTopFit.row and .place): Find's circle 16 in from the
/// leading edge and the •••'s 16 in from the trailing one, each centred where its 34 pt face is drawn (its 44 pt target
/// reaching 5 pt past it, into the room round it), and the switch filling the room between, 12 from each face, at its
/// own width where that is less (the Mac's) - or, where its equal segments need more than that room
/// (LibraryTopFit.folds), on a row of its own under the circles, as far in from each edge as they are, with the room
/// under it the row would give it beside them. The row 52 tall at least, what is in it centred in it. Its views, in
/// order: Find, the switch, the ••• and the switch's need (DWSegmentedNeed, hidden - placed, never seen or heard).
private struct LibraryTopRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let row = placed(proposal.width, subviews) else { return .zero }
        return CGSize(width: row.width, height: row.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let row = placed(bounds.width, subviews) else { return }
        subviews[0].lookPlace(row.find, in: bounds)
        subviews[1].lookPlace(row.switcher, in: bounds)
        subviews[2].lookPlace(row.more, in: bounds)
        subviews[3].lookPlace(row.need, in: bounds)
    }

    /// The row in `width` (where none is given, as wide as the switch needs beside its circles): its views measured -
    /// the switch in the room the row offers it - and placed.
    private func placed(_ width: CGFloat?, _ subviews: Subviews) -> LibraryTopFit.Placed? {
        guard subviews.count == 4 else {
            assertionFailure("LibraryTopRow lays out Find, the switch, the more and the need, not \(subviews.count) views")
            return nil
        }
        let need = LookSize(subviews[3].sizeThatFits(.unspecified))
        let row = LibraryTopFit.row(needs: need.width, width: width.map { (given: CGFloat) -> Double in Double(given) })
        let switcher = LookSize(subviews[1].sizeThatFits(ProposedViewSize(width: CGFloat(row.room), height: nil)))
        return LibraryTopFit.place(row, find: LookSize(subviews[0].sizeThatFits(.unspecified)), switcher: switcher,
                                   more: LookSize(subviews[2].sizeThatFits(.unspecified)), need: need)
    }
}

/// LibraryTop's eyes in UIKit (18 Nov, notes/ios.md "The Library's top after Now Playing"): a view of the row's own
/// frame, drawn behind it, that reads - in its OWN window, never a guessed key window - where its top is
/// (`convert(bounds, to: nil)`, the window's coordinates, whatever SwiftUI's global space says) and that window's top
/// safe area, and whether something is presented over the window. Out of a window it reads nothing (under a full-screen
/// cover iOS takes the tabs out of the window).
///
/// When: UIKit putting it in a window, laying it out and changing its safe area; a presentation the app made going
/// (Notification.Name.appPresentationGone, after its onDismiss); the scene coming to the front; and SwiftUI's asks (the
/// row appearing, SwiftUI's geometry changing). Each reads once, on the main loop's next turn, after the layout under
/// way - however many ask meanwhile; SwiftUI's geometry changing reads at once in its action too (`now`), so the room
/// changes in the pass that moved the row, as it did before the probe. After each ask it reads again every `gap`,
/// `tries` times (3 s) after the last, whatever is presented (20 Nov): UIKit can move the row's container without a
/// word to it or to SwiftUI - the tabs back from under Now Playing's cover settled 117 points lower than they were first
/// read - and a cover going reads afresh as soon as it has gone, even should its onDismiss come before UIKit lets it go.
/// A sheet left up longer keeps the room until its going is said.
///
/// Nothing in it is drawn or touchable, and VoiceOver passes it by.
private struct TopProbe: UIViewRepresentable {
    /// LibraryTop's hold on its probe, for SwiftUI's own moments. Weak: the probe is UIKit's to keep.
    @MainActor final class Eyes {
        weak var probe: Probe?
    }

    /// One reading: the row's top in its window, the window's top inset, whether something is presented over it, and
    /// what asked.
    struct Sample {
        let top: CGFloat
        let windowTop: CGFloat
        let presented: Bool
        let cause: String
    }

    let eyes: Eyes
    let measured: (Sample) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.measured = measured
        eyes.probe = probe
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.measured = measured
        eyes.probe = probe
    }

    final class Probe: UIView {
        /// After an ask, read again this often...
        private static let gap: TimeInterval = 0.25
        /// ...this many times after the last: 3 s, past any presentation's going and the tabs settling after it.
        private static let tries = 12

        var measured: ((Sample) -> Void)?
        /// What asked for the reading waiting for the main loop's next turn - nil while none waits.
        private var waiting: String?
        /// Reads again: one waiting, and how many are left since the last ask.
        private var againWaiting = false
        private var left = 0
        /// The last ask - what Debug's "after …" says of a read again ("window, again").
        private var asked = ""

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            backgroundColor = .clear
            let centre = NotificationCenter.default
            centre.addObserver(self, selector: #selector(presentationGone), name: .appPresentationGone, object: nil)
            centre.addObserver(self, selector: #selector(sceneActive), name: UIScene.didActivateNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            soon("window")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            soon("layout")
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            soon("safe area")
        }

        @objc private func presentationGone() {
            soon("presentation gone")
        }

        @objc private func sceneActive() {
            soon("scene active")
        }

        /// A reading now (SwiftUI's geometry changing - LibraryTop reads in its action), the reads again started afresh.
        func now(_ cause: String) {
            follow(cause)
            read(cause)
        }

        /// A reading on the main loop's next turn - one, however many ask before it - the reads again started afresh.
        func soon(_ cause: String) {
            follow(cause)
            schedule(cause)
        }

        /// An ask: `tries` reads again from here, said as after it.
        private func follow(_ cause: String) {
            left = Self.tries
            asked = cause
        }

        /// A reading on the main loop's next turn, after the layout under way - one, however many ask before it.
        private func schedule(_ cause: String) {
            guard waiting == nil else { return }
            waiting = cause
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let cause = waiting ?? ""
                waiting = nil
                read(cause)
            }
        }

        /// Where the row's top is in its window, that window's top inset and whether something is presented over it,
        /// told to LibraryTop - nothing out of a window. Then a read again, while any are left.
        private func read(_ cause: String) {
            guard let window else { return }
            let presented = presentedOver(window)
            measured?(Sample(top: convert(bounds, to: nil).minY, windowTop: window.safeAreaInsets.top,
                             presented: presented, cause: cause))
            readAgain()
        }

        /// Read again a moment later, as long as there are reads left since the last ask: whatever UIKit moves without a
        /// word, and a presentation's going, read once they have settled.
        private func readAgain() {
            guard !againWaiting, left > 0 else { return }
            againWaiting = true
            left -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.gap) { [weak self] in
                guard let self else { return }
                againWaiting = false
                schedule("\(asked), again")
            }
        }

        /// Something presented over `window`: by its root view controller - and, should a container nearer the row
        /// have presented it, by the controller the row is in.
        private func presentedOver(_ window: UIWindow) -> Bool {
            if window.rootViewController?.presentedViewController != nil { return true }
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller.presentedViewController != nil }
                responder = current.next
            }
            return false
        }
    }
}
