import DeadwaxCore
import SwiftUI

/// The title strip across the window's top (dw.css's .titlebar - the Mac redesign, slice R1, notes/ios.md "The Mac
/// redesign, slice R1: the frame and the shared pieces"): 28 tall, its gradient under the window's own traffic lights,
/// the page's title centred in the quiet colour. macOS's title bar takes no gradient, so its title stays hidden
/// (Platform's `titleVisibility = .hidden`) and this is drawn where it is - the frame laid under the title bar, the strip
/// as tall as the bar where the bar is taller than 28 (`height`). The window's name for the Window menu is set apart
/// (Platform.nameWindow).
///
/// It is drawing only: it takes no click, so a drag on it is the title bar's - the window moves - and VoiceOver skips it
/// (the title is the window's own, which VoiceOver reads).
struct MacTitleStrip: View {
    let title: String
    let height: CGFloat

    /// Room either side for the traffic lights (.lights: 10 in, three 12 pt lights 8 apart), so a long title never runs
    /// under them.
    private static let lights: CGFloat = 80

    var body: some View {
        Text(title)
            .font(Typeface.Mac.text(.small).weight(.medium))
            .foregroundStyle(DWPalette.t2)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Self.lights)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(MacPalette.titleFace)
            .overlay(alignment: .top) { DWRule(colour: MacPalette.titleSheen) }
            .overlay(alignment: .bottom) { DWRule(colour: MacPalette.titleEdge) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
