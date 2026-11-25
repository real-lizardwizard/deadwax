import DeadwaxCore
import SwiftUI

/// A card (dw.css's .card - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look, and the
/// phone's pieces"): what it holds 12 in, on #1c1b22, square - Settings' account card, a song's on its album. Drawn
/// nowhere until its slices.
struct PhoneCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(CGFloat(PhoneLook.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DWPalette.cardFace, in: DWCorners.boxShape)
    }
}

/// A group (.group, .group > .legend): its rows on #17161d inside the line's edge, 12 in either side, square - its legend
/// standing above it in the 28 of room it keeps above itself, at 13 in the second colour, a header for VoiceOver. Its
/// rows (DWFieldRow's, PhoneKV, PhoneGo) each draw their hairline under them; the last one's falls under the group's foot,
/// clipped, as `.field:last-child` draws none.
struct PhoneGroup<Content: View>: View {
    var legend: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(PhoneLook.legendLift - PhoneLook.legendLine)) {
            if let legend {
                Text(legend)
                    .font(Typeface.Phone.text(.legend).weight(.medium))
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
            // .group: padding 2px 12px, inside its 1 pt edge
            .padding(.horizontal, CGFloat(PhoneLook.groupSide) + 1)
            .padding(.vertical, CGFloat(PhoneLook.groupEnds) + 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DWPalette.groupFace, in: DWCorners.boxShape)
            .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
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
