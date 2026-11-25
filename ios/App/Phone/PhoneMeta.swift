import DeadwaxCore
import SwiftUI

/// The meta line (dw.css's .meta - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look, and
/// the phone's pieces"): over a list, its count and what it's sorted by - a purple link opening the sort's menu
/// (PhoneMetaLink) - with the list's own toggles at its end (Grid and List, DWToggleStyle): 30 tall at least, 16 in at
/// the left and 10 at the right, 6 apart, in the third colour. Capped at xxxLarge, as the bars are. Drawn nowhere until
/// its slices (R2).
struct PhoneMeta<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.metaGap)) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .font(Typeface.Phone.text(.meta))
        .foregroundStyle(DWPalette.t3)
        // .meta: padding 0 10px 0 16px
        .padding(.leading, CGFloat(PhoneLook.metaLead))
        .padding(.trailing, CGFloat(PhoneLook.metaTrail))
        .lookHeight(PhoneLook.meta)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The meta line's link (.meta .link): its words in the accent with the caret after them, 5 apart - a Menu's label (the
/// sort's), the menu iOS's own. A finger's target round it.
struct PhoneMetaLink: View {
    let words: String

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.linkGap)) {
            Text(words)
            DWCaret(colour: DWPalette.acc)
        }
        .font(Typeface.Phone.text(.meta))
        .foregroundStyle(DWPalette.acc)
        .contentShape(DWTarget(face: Rectangle()))
    }
}
