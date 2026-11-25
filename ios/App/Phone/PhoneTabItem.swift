import DeadwaxCore
import SwiftUI

/// A tab bar's item, and Now Playing's bottom row's (dw.css's .tabbar > a - the redesign, slice R1b, notes/ios.md "The
/// redesign, slice R1b: the shared look, and the phone's pieces"): its icon over its words, 49 tall at least, the
/// accent's while shown, #8a8a9c otherwise - and lit, the lit line over it on the bar's top edge. The icons are the
/// caller's, the app's own (filled SF Symbols and the squared Library stack - the build plan's section 8), 24 at least.
/// The bar is R4's and the row R3's: drawn nowhere until then.
///
/// One element for VoiceOver - its words, selected while shown - with the Large Content Viewer's icon and words when the
/// text is large, as the tab bar's own are. Capped at xxxLarge, as the tab bar is.
struct PhoneTabItem<Icon: View>: View {
    let words: String
    /// Whether it is the one shown (a tab), or on (Now Playing's Lyrics).
    let shown: Bool
    /// Whether the lit line stands over it: the tab bar's shown tab. Now Playing's row lights none.
    var lit = false
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: CGFloat(PhoneLook.tabGap)) {
                icon
                    .lookSquare(PhoneLook.tabIcon)
                Text(words)
                    .font(Typeface.Phone.text(.tabItem).weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(shown ? DWPalette.acc : DWPalette.tabItemText)
            .frame(maxWidth: .infinity)
            .lookHeight(PhoneLook.tabItem)
            .overlay(alignment: .top) {
                if lit {
                    // .tabbar > a.on::before: top -7px, on the bar's edge
                    PhoneLitLine()
                        .offset(y: -CGFloat(PhoneLook.litLineLift))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(words)
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label {
                Text(words)
            } icon: {
                icon
            }
        }
    }
}

/// The lit line over the shown tab (.tabbar > a.on::before): 24 x 2, square, in the accent.
struct PhoneLitLine: View {
    var body: some View {
        Rectangle()
            .fill(DWPalette.acc)
            .frame(width: CGFloat(PhoneLook.litLineWidth), height: CGFloat(PhoneLook.litLineHeight))
            .accessibilityHidden(true)
    }
}
