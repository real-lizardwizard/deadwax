import DeadwaxCore
import SwiftUI

/// A page's toolbar (dw.css's .bar - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the frame and
/// the shared pieces"): 40 tall across the page's top, its gradient, a sheen along its top and the frame's rule under
/// it, holding the page's buttons (MacButtonStyle) 6 apart, 12 in from either side. Each slice fills it from its page's
/// ••• menu's own items. Not NSToolbar, which would sit in the window's title bar.
struct MacToolbar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(MacLook.toolbarHeight))
        .background(MacPalette.toolbarFace)
        .overlay(alignment: .top) { MacRule(colour: MacPalette.toolbarSheen) }
        .overlay(alignment: .bottom) { MacRule(colour: MacPalette.frame) }
        .accessibilityElement(children: .contain)
    }
}

/// The groove between a toolbar's groups (.groove): a dark line 20 tall with a sheen beside it, 5 either side.
struct MacGroove: View {
    var body: some View {
        HStack(spacing: 0) {
            MacRule(colour: MacPalette.groove, vertical: true)
            MacRule(colour: MacPalette.grooveSheen, vertical: true)
        }
        .frame(height: CGFloat(MacLook.grooveHeight))
        .padding(.horizontal, 5)
        .accessibilityHidden(true)
    }
}
