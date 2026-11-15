import DeadwaxCore
import SwiftUI

/// The Library's top (the squared look, 14 Nov - notes/ios.md "The squared look"). James, on app 0.11: "the search bar
/// is kinda in the way"; "let's put a magnifying glass button on the left side of the slider, and then maybe refine the
/// slider size a little so the top looks complete. maybe square off the slider"; "but the search button and options
/// button at the top can be circles". So the Library's root draws its own top in place of the navigation bar: Find's
/// magnifying glass, the switch filling the room between, and the ••• - the two circles (CircleFace) evenly spaced
/// round it, 16 pt in from each edge as the pages are - and, only while Find is open, its field under them, with
/// Cancel. On --dw-tab-bar, as the tab bar is, running up under the status bar, a hairline of --dw-border at its foot;
/// the offline banner under it (LibraryView).
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
        .padding(.bottom, finding ? 8 : 2)
        .frame(maxWidth: .infinity)
        .background {
            Palette.tabBar
                .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottom) {
            Palette.border
                .frame(height: 1 / max(displayScale, 1))
                .accessibilityHidden(true)
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
                .font(.footnote.weight(.semibold))
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
