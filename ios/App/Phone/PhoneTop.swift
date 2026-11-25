import DeadwaxCore
import SwiftUI

/// The compact top (dw.css's .topbar - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look,
/// and the phone's pieces"): a page's own bar, 44 tall at least over no ground of its own (`.dw.ph .topbar`'s none - the
/// page's shows through), what leads it at the left (the purple Back), what trails it at the right (small buttons, a
/// •••), and a page's name centred between them, never under either. With the page's own title in it - the Library's
/// "Library", 28 and bold at its left - it is the titled top, 50 tall at least. Capped at xxxLarge, as the tab bar is.
/// The large title under it is PhoneBigTitle. Drawn nowhere until its slices (R2 onwards).
struct PhoneTop<Leading: View, Trailing: View>: View {
    /// The page's own title at the top's left (the titled top).
    var title: String?
    /// A page's name, centred.
    var name: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.topGap)) {
            HStack(spacing: CGFloat(PhoneLook.topGap)) {
                if let title {
                    Text(title)
                        .font(Typeface.Phone.text(.topTitle).weight(.bold))
                        .tracking(CGFloat(PhoneLook.titledTopTracking))
                        .foregroundStyle(DWPalette.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
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
        // .topbar: padding 0 12px (the titled top's leading side 16)
        .padding(.leading, CGFloat(title == nil ? PhoneLook.topSide : PhoneLook.titledTopSide))
        .padding(.trailing, CGFloat(PhoneLook.topSide))
        .lookHeight(title == nil ? PhoneLook.top : PhoneLook.titledTop)
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
    /// A top with nothing at its left but its title, if any.
    init(title: String? = nil, name: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, name: name, leading: { EmptyView() }, trailing: trailing)
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
