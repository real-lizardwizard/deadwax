import DeadwaxCore
import SwiftUI

/// A card (dw.css's .card - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look, and the
/// phone's pieces"): a download on its way and a notice on Requests (R8), the Library's refresh problem (R1c) - the
/// drawing's Sources and sign-in cards are their own slices'. (R1c - notes/ios.md "The redesign, slice R1c: the phone
/// is flat (2026-11-25)"; James, 25 Nov: "everything should just look like it's part of the interface, not laid on
/// top") No face: what it holds sits on the page, 14 above and below and none at its sides,
/// over a hairline (#1c1b22) under the whole card - a row of the page, as `.dw.ph .card` draws it.
struct PhoneCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            // .dw.ph .card: padding 14px 0, border-bottom 1px solid #1c1b22, background none
            .padding(.vertical, CGFloat(PhoneLook.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.cardRule) }
    }
}

/// A group (.group, .group > .legend): (R1c) no face and no edge - its heading over its rows, at 13 and semibold in the
/// second colour at the group's leading edge, a header for VoiceOver, standing in the 28 of room the group keeps above
/// itself; the rows at the page's own sides. Its rows (DWFieldRow's, PhoneKV, PhoneGo) each draw their hairline under
/// them, which separate them as the panel did; the last one's falls under the group's foot, clipped, as
/// `.field:last-child` draws none.
struct PhoneGroup<Content: View>: View {
    var legend: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(PhoneLook.legendLift - PhoneLook.legendLine)) {
            if let legend {
                Text(legend)
                    // .dw.ph .group > .legend: font-weight 600, left 0
                    .font(Typeface.Phone.text(.legend).weight(.semibold))
                    .foregroundStyle(DWPalette.t2)
                    .lookHeight(PhoneLook.legendLine)
                    .padding(.leading, CGFloat(PhoneLook.legendSide))
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            // the last row's hairline under the foot, clipped
            .padding(.bottom, -1)
            .clipped()
            // .dw.ph .group: padding 2px 0, no border, no background
            .padding(.horizontal, CGFloat(PhoneLook.groupSide))
            .padding(.vertical, CGFloat(PhoneLook.groupEnds))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // .group: margin-top 28px, the legend standing in it
        .padding(.top, CGFloat(legend == nil ? PhoneLook.groupAbove
                                              : PhoneLook.groupAbove - PhoneLook.legendLift))
    }
}

/// A fact's row (.kv): its label at the left, white, 116 wide at least, and its value at the right in the second colour -
/// 42 tall at least at the row's 16, on its hairline - the value on the label's first baseline, as `.kv` is (25 Nov).
/// `mono`, a value the drawings set in the readout face (`.mono.s`: Courier Prime at the small 13). One element for
/// VoiceOver: its label, then its value.
struct PhoneKV: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.kvGap)) {
            Text(label)
                .foregroundStyle(DWPalette.kvLabel)
                .frame(minWidth: CGFloat(PhoneLook.kvLabelWidth), alignment: .leading)
            Spacer(minLength: 0)
            if mono {
                Text(value)
                    .font(Typeface.Phone.mono(.small))
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(value)
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(Typeface.Phone.text(.row))
        .lookHeight(PhoneLook.kvRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .combine)
    }
}

/// A row that goes somewhere (.go): what it holds 8 apart at the row's 16, 46 tall at least on its hairline - a chevron
/// at its end the caller's (PhoneChevron). One element for VoiceOver unless the caller holds a control in it that must
/// be its own (`combined: false`).
struct PhoneGo<Content: View>: View {
    var combined = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.goGap)) {
            content
        }
        .font(Typeface.Phone.text(.row))
        .foregroundStyle(DWPalette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookHeight(PhoneLook.goRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .contentShape(Rectangle())
        .accessibilityElement(children: combined ? .combine : .contain)
    }
}

/// A row's way on: the chevron, in the third colour.
struct PhoneChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(Typeface.Phone.text(.small).weight(.semibold))
            .foregroundStyle(DWPalette.t3)
            .accessibilityHidden(true)
    }
}
