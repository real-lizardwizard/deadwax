import DeadwaxCore
import SwiftUI

/// The mini player's ground and its seek line (dw.css's .mini - the redesign, slice R1b, notes/ios.md "The redesign,
/// slice R1b: the shared look, and the phone's pieces"): the parts R4 restyles the mini player with - (R1c, notes/ios.md
/// "The redesign, slice R1c: the phone is flat (2026-11-25)") its ground the page's black under a #1c1b22 hairline, 60
/// tall at least with the cover flush left (PhoneLook's sizes), and the 2 pt seek line along that edge, the part played
/// in the purple gradient. MiniPlayerView itself - its one drag, its bare Play in a 48 target, its words - is R4's.
struct PhoneMiniGround: View {
    var body: some View {
        DWPalette.miniFace
            .overlay(alignment: .top) { DWRule(colour: DWPalette.miniEdge) }
            .accessibilityHidden(true)
    }
}

/// The mini player's seek line (.mini > .prog): the track in the line's colour, the part played over it from the left in
/// the purple gradient - the gradient across the part played, as `.prog > i`'s is.
struct PhoneSeekLine: View {
    /// How much has played, 0 to 1.
    let part: Double

    var body: some View {
        DWPalette.seekTrack
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DWPalette.seekFill)
                    .scaleEffect(x: CGFloat(min(max(part, 0), 1)), y: 1, anchor: .leading)
            }
            .frame(height: CGFloat(PhoneLook.seekLine))
            .accessibilityHidden(true)
    }
}
