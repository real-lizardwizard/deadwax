import DeadwaxCore
import SwiftUI

/// The player's keys (dw.css's .key and .key.big - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1:
/// the frame and the shared pieces"), for R4's bar: round keys - 34, Play's 46 and purple - each in its dark ring with a
/// drop under it, pressed in while held (DWRaised). Their glyphs are SF Symbols (Typeface.symbol), the label's own. The
/// Mac's alone: the phone's play and skip are bare sharp glyphs (James, 25 Nov: "Sharp glyphs"). Shuffle's and Repeat's
/// toggles are App/Look's DWToggleStyle since R1b.
struct MacKeyStyle: ButtonStyle {
    /// .key.big: Play's.
    var big = false

    func makeBody(configuration: Configuration) -> some View {
        let size = CGFloat(big ? MacLook.bigKeySize : MacLook.keySize)
        return configuration.label
            .foregroundStyle(big ? MacPalette.bigKeyText : MacPalette.keyText)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    if big {
                        // box-shadow 0 0 0 3px #0b0a0f, 0 0 0 4px #2c2a36: two rings round it
                        Circle().fill(MacPalette.bigKeyOuterRing).padding(-4)
                        Circle().fill(MacPalette.bigKeyRing).padding(-3)
                        DWRaised(shape: Circle(), face: MacPalette.bigKeyFace, sheen: MacPalette.bigKeySheen,
                                  edge: MacPalette.bigKeyEdge, drop: MacPalette.keyDrop, pressed: configuration.isPressed)
                    } else {
                        // box-shadow 0 0 0 2px #0b0a0f
                        Circle().fill(MacPalette.keyRing).padding(-2)
                        DWRaised(shape: Circle(), face: MacPalette.keyFace, sheen: MacPalette.keySheen,
                                  edge: MacPalette.keyEdge, drop: MacPalette.keyDrop, pressed: configuration.isPressed)
                    }
                }
                .accessibilityHidden(true)
            }
            .contentShape(Circle())
    }
}

/// The player's display (.lcd): the darkest well, the line's edge either side, a shadow inside its top - what's playing
/// drawn in it, the caller's.
struct MacDisplay<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(MacPalette.lcd.shadow(.inner(color: MacPalette.lcdShade, radius: 2.5, x: 0, y: 2)))
            .overlay(alignment: .leading) { DWRule(colour: DWPalette.line, vertical: true) }
            .overlay(alignment: .trailing) { DWRule(colour: DWPalette.line, vertical: true) }
    }
}
