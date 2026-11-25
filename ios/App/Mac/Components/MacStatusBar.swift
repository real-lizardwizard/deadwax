import DeadwaxCore
import SwiftUI

/// The status bar under the page (dw.css's .status - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice
/// R1: the frame and the shared pieces"): 24 tall, its gradient, the frame's rule and a sheen along its top, the page's
/// facts in the third colour - "140 albums", "1,612 songs" - each 10 in either side with a divider after it, and the
/// trailing ones ("Navidrome up to date") at its right. The page in front says them (MacStatusItems); the frame draws
/// the bar while it has something to say.
struct MacStatusBar: View {
    let items: MacStatusItems.Items

    var body: some View {
        HStack(spacing: 0) {
            facts(items.leading)
            Spacer(minLength: 0)
            facts(items.trailing)
        }
        // .status: padding 0 4px
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(MacLook.statusHeight))
        .background(MacPalette.statusFace)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                DWRule(colour: DWPalette.frame)
                DWRule(colour: MacPalette.statusSheen)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func facts(_ facts: [String]) -> some View {
        ForEach(Array(facts.enumerated()), id: \.offset) { (index: Int, fact: String) in
            Text(fact)
                .font(Typeface.Mac.text(.label))
                .foregroundStyle(DWPalette.t3)
                .lineLimit(1)
                .padding(.horizontal, 10)
            // .status > div: border-right 1px solid #262430, 14 tall - none after the last of a side
            if index < facts.count - 1 {
                DWRule(colour: MacPalette.divider, vertical: true)
                    .frame(height: 14)
            }
        }
    }
}
