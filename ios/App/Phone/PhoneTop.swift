import DeadwaxCore
import SwiftUI

/// The compact top (dw.css's .topbar - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look,
/// and the phone's pieces"): a page's own bar, 44 tall at least over no ground of its own (`.dw.ph .topbar`'s none - the
/// page's shows through), what leads it at the left (the purple Back), what trails it at the right (small buttons, a
/// •••), and a page's name centred between them, never under either. Capped at xxxLarge, as the tab bar is. The large
/// title under it is PhoneBigTitle. (R2's titled top - the Library's "Library", 28 and bold at its left - went in R2b:
/// the Library's top is its one row again, LibraryTop's, with PhoneCircleStyle's two glyphs.)
struct PhoneTop<Leading: View, Trailing: View>: View {
    /// A page's name, centred.
    var name: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.topGap)) {
            HStack(spacing: CGFloat(PhoneLook.topGap)) {
                leading
            }
            .onGeometryChange(for: CGFloat.self) { (side: GeometryProxy) -> CGFloat in
                side.size.width
            } action: { (width: CGFloat) -> Void in
                leadingWidth = width
            }
            Spacer(minLength: 0)
            trailing
                .onGeometryChange(for: CGFloat.self) { (side: GeometryProxy) -> CGFloat in
                    side.size.width
                } action: { (width: CGFloat) -> Void in
                    trailingWidth = width
                }
        }
        // .topbar: padding 0 12px
        .padding(.horizontal, CGFloat(PhoneLook.topSide))
        .lookHeight(PhoneLook.top)
        .overlay {
            // .topbar > .ttl: centred across the whole top, clear of what leads and trails it
            if let name {
                Text(name)
                    .font(Typeface.Phone.text(.topName).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(1)
                    .padding(.horizontal, CGFloat(PhoneLook.topSide + PhoneLook.topGap) + max(leadingWidth, trailingWidth))
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension PhoneTop where Leading == EmptyView {
    /// A top with nothing at its left.
    init(name: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(name: name, leading: { EmptyView() }, trailing: trailing)
    }
}

/// (the redesign, slice R2b - notes/ios.md "The redesign, slice R2b: the Library's top, one row again") The Library's
/// two circles (dw.css's .circ): Find's magnifying glass and the •••, James's of 14 Nov again ("but the search button
/// and options button at the top can be circles"). (R1c - notes/ios.md "The redesign, slice R1c: the phone is flat
/// (2026-11-25)") **Bare glyphs now, with no face**: white (`.dw.ph .circ`'s #fff), at the text style nearest 21 pt
/// (`.circ svg`'s 21 - title3's 20), centred in the 36 x 34 box the circle was (`.circ`), in a finger's 44 pt target
/// that reaches 4 pt past it either side into the row's 12 and 5 above and below it, so it never reaches a neighbour's;
/// faded while held, as a toggle is, and while it can't be used. For a Menu too (`.menuStyle(.button)`, whose label
/// takes the button style in use). Its glyph grows with the text to the largest standard size the row is capped at,
/// and a long press then shows it large.
///
/// The ••• isn't drawn in the accent while its menu is open (the drawing's `.circ.on`): SwiftUI's Menu tells its label
/// nothing of whether it is open, and the one documented way to know - UIKit's context-menu interaction, a UIButton of
/// our own with its menu rebuilt as a UIMenu - would rebuild the menu itself, which this slice keeps as it is.
struct PhoneCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PhoneCircleFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PhoneCircleFace<Label: View>: View {
    let label: Label
    let pressed: Bool

    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let face = CGFloat(PhoneLook.circle)
        let tall = CGFloat(PhoneLook.circleHeight)
        let target = max(face, CGFloat(DWLook.here.target))
        label
            .font(Typeface.symbol(.title3))
            .foregroundStyle(DWPalette.text)
            .frame(width: face, height: tall)
            .opacity(enabled && !pressed ? 1 : DWPalette.off)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
    }
}

/// The compact top's back link (.back): the accent's chevron and the page it goes back to, at 17, in a finger's target.
/// VoiceOver reads it as iOS's own back button is read: the page, then "Back" (PhonePieceWords.back).
struct PhoneBack: View {
    /// The page it goes back to ("Library").
    let words: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Image(systemName: "chevron.left")) \(words)")
                .font(Typeface.Phone.text(.back))
                .foregroundStyle(DWPalette.acc)
                .lineLimit(1)
                .contentShape(DWTarget(face: Rectangle()))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PhonePieceWords.back(to: words))
    }
}

/// The large title under the compact top (.big): 34, bold, its letters drawn closer, 16 in - a header for VoiceOver. It
/// grows with the text size, uncapped, as iOS's own large title does.
struct PhoneBigTitle: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.big).weight(.bold))
            .tracking(CGFloat(PhoneLook.bigTracking))
            .foregroundStyle(DWPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            // .big: padding 2px 16px 10px
            .padding(.top, CGFloat(PhoneLook.bigAbove))
            .padding(.horizontal, CGFloat(PhoneLook.bigSide))
            .padding(.bottom, CGFloat(PhoneLook.bigBelow))
            .accessibilityAddTraits(.isHeader)
    }
}
