import DeadwaxCore
import SwiftUI
import UIKit

/// The Library's top (the squared look, 14 Nov - notes/ios.md "The squared look"). James, on app 0.11: "the search bar
/// is kinda in the way"; "let's put a magnifying glass button on the left side of the slider, and then maybe refine the
/// slider size a little so the top looks complete. maybe square off the slider"; "but the search button and options
/// button at the top can be circles". So the Library's root draws its own top in place of the navigation bar: Find's
/// magnifying glass, the switch filling the room between, and the ••• - the two circles (CircleFace) evenly spaced
/// round it, 16 pt in from each edge as the pages are - and, only while Find is open, its field under them, with
/// Cancel. On --dw-tab-bar, as the tab bar is, running up under the status bar, a hairline of --dw-border at its foot;
/// the offline banner under it (LibraryView).
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
    @ViewBuilder let find: Find
    @ViewBuilder let switcher: Switch
    @ViewBuilder let more: More

    @Environment(\.displayScale) private var displayScale
    @Environment(DebugModel.self) private var debug
    /// How far the row comes down under the status bar and the island (TopClearance.room): measured afresh with nothing
    /// presented, kept as it is under a presentation.
    @State private var clearance: CGFloat = 0
    /// The probe behind the row, for SwiftUI's own moments: the row appearing, SwiftUI's geometry for it changing.
    @State private var eyes = TopProbe.Eyes()
    /// What SwiftUI last said of the row - its top in SwiftUI's global space, its top safe area - for Debug's reading.
    @State private var swiftUI: [CGFloat] = []

    /// Between the circles' targets and the switch: their faces' 4 pt of target and this make 12 pt either side.
    private static var gap: CGFloat { 8 }
    /// To the circles' targets from the edges: with their 4 pt, the pages' 16 pt gutter.
    private static var side: CGFloat { 12 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Self.gap) {
                Button(action: openFind) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(CircleFace())
                .accessibilityLabel(findLabel)
                .accessibilityShowsLargeContentViewer {
                    Label(findLabel, systemImage: "magnifyingglass")
                }
                switcher
                    .frame(maxWidth: .infinity)
                more
            }
            if finding {
                find
                    .padding(.horizontal, CircleFace.target / 2 - CircleFace.face / 2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Self.side)
        .padding(.top, clearance)
        .padding(.bottom, finding ? 8 : 2)
        .frame(maxWidth: .infinity)
        .background {
            Palette.tabBar
                .ignoresSafeArea(.container, edges: .top)
        }
        // the row's own frame, never the fill's: its top is the row's top, its padding inside it, so coming down never
        // moves what it reads
        .background {
            TopProbe(eyes: eyes) { (sample: TopProbe.Sample) -> Void in
                take(sample)
            }
        }
        .overlay(alignment: .bottom) {
            Palette.border
                .frame(height: 1 / max(displayScale, 1))
                .accessibilityHidden(true)
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

/// The switch (the squared look): the web's segmented control (app.css .app-segmented, .app-segment) - a well of
/// --dw-well with a --dw-border edge and its inset shade, the chosen page's segment in the toggled tint (--dw-toggled-bg,
/// its --dw-toggled-border edge, --dw-accent-text), the others --dw-text-2 - squared to a control's corners
/// (Corners.control), in place of iOS's segmented Picker, whose corners can't be changed. The pages in the order kept;
/// a tap chooses one (`choose` - the pager moved, at once under Reduce Motion), and the chosen segment slides to the
/// page shown however it changed - a tap or a swipe settling - except under Reduce Motion, where it moves at once.
///
/// VoiceOver: "Library pages", each page a button with its title, the one shown selected. Its words: footnote,
/// semibold, the web's - growing with the text size up to the first accessibility size and holding there; a title
/// too long for its segment shrinks to 70% of that, then truncates at its end; and at the accessibility sizes a long
/// press on a segment shows its title large (the Large Content Viewer). Each segment's target reaches 6 pt past the
/// well above and below, the row's height (the web's --app-segment-reach).
struct LibrarySwitchControl: View {
    let order: [LibraryPage]
    let shown: LibraryPage
    let choose: (LibraryPage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var chosen

    /// --dw-segmented: the well's height; a segment's inside the well's edge and padding.
    private static let well: CGFloat = 32
    private static let segment: CGFloat = 28
    /// --app-segment-gap: between the segments.
    private static let gap: CGFloat = 2
    /// --app-segment-reach: a segment's target past the well, above and below.
    private static let reach: CGFloat = 6
    private static let hairline: CGFloat = 1

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(order) { (page: LibraryPage) in
                segment(page)
            }
        }
        .padding(Self.hairline)
        .frame(minHeight: Self.well)
        .background(Palette.well, in: Corners.controlShape)
        .overlay(alignment: .top) {
            // the well's inset shade (--dw-well-inset), inside its top edge
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(height: Self.hairline)
                .padding(.horizontal, Corners.control)
                .padding(.top, Self.hairline)
                .accessibilityHidden(true)
        }
        .overlay(Corners.controlShape.strokeBorder(Palette.border, lineWidth: Self.hairline))
        .animation(reduceMotion ? nil : .snappy, value: shown)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LibrarySwitchWords.switchLabel)
    }

    private func segment(_ page: LibraryPage) -> some View {
        let on = page == shown
        return Button {
            choose(page)
        } label: {
            Text(page.title)
                .font(Typeface.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .foregroundStyle(on ? Palette.accentText : Palette.text2)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: Self.segment)
                .background {
                    if on {
                        Corners.controlShape
                            .fill(Palette.toggledFill)
                            .overlay(Corners.controlShape.strokeBorder(Palette.toggledEdge, lineWidth: Self.hairline))
                            .matchedGeometryEffect(id: "chosen", in: chosen)
                    }
                }
                .contentShape(SegmentReach(reach: Self.reach))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(page.title)
        }
    }
}

/// A segment's target: its own box, reaching `reach` past it above and below (never into the next segment).
private struct SegmentReach: Shape {
    let reach: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -reach))
    }
}
