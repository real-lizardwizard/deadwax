import DeadwaxCore
import SwiftUI

/// A group box (dw.css's .group and its .legend - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1:
/// the frame and the shared pieces"): drawn, since SwiftUI's GroupBox is the system's. A box's corners in the line's
/// edge, its legend set into the top edge on the ground behind it (`ground`: the panel's, or the page's - .group.onbg) -
/// the legend standing 8 above the box, which whatever holds it leaves room for. VoiceOver reads the legend as the
/// group's heading.
struct MacGroupBox<Content: View>: View {
    let legend: String
    var ground: Color = DWPalette.panel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // .group: padding 14px 12px 12px
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            // .legend: top -9px, left 9px inside the 1 pt edge, padding 0 6px, 16 tall
            Text(legend)
                .font(Typeface.Mac.text(.label).weight(.semibold))
                .foregroundStyle(DWPalette.label)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(ground)
                .offset(x: 10, y: -8)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
    }
}
