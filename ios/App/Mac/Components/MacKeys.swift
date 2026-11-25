import DeadwaxCore
import SwiftUI

/// The player's keys (dw.css's .key, .key.big and .tog - the Mac redesign, slice R1, notes/ios.md "The Mac redesign,
/// slice R1: the frame and the shared pieces"), for R4's bar: round keys - 34, Play's 46 and purple - each in its dark
/// ring with a drop under it, pressed in while held (MacRaised); and Shuffle's and Repeat's toggles, 30 with a box's
/// corners, lit in the selection's colours with the accent's dot under them while on. Their glyphs are SF Symbols
/// (Typeface.symbol), the label's own.
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
                        MacRaised(shape: Circle(), face: MacPalette.bigKeyFace, sheen: MacPalette.bigKeySheen,
                                  edge: MacPalette.bigKeyEdge, drop: MacPalette.keyDrop, pressed: configuration.isPressed)
                    } else {
                        // box-shadow 0 0 0 2px #0b0a0f
                        Circle().fill(MacPalette.keyRing).padding(-2)
                        MacRaised(shape: Circle(), face: MacPalette.keyFace, sheen: MacPalette.keySheen,
                                  edge: MacPalette.keyEdge, drop: MacPalette.keyDrop, pressed: configuration.isPressed)
                    }
                }
                .accessibilityHidden(true)
            }
            .contentShape(Circle())
    }
}

/// Shuffle's and Repeat's toggle (.tog): no face while off, the selection's while on, with the accent's 4 pt dot 7 under
/// it. VoiceOver reads it as selected while on - the caller's label says which it is.
struct MacToggleStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        let size = CGFloat(MacLook.toggleSize)
        return configuration.label
            .foregroundStyle(on ? MacPalette.acct : MacPalette.t3)
            .frame(width: size, height: size)
            .background {
                if on {
                    MacCorners.boxShape
                        .fill(MacPalette.selbg)
                        .overlay(MacCorners.boxShape.strokeBorder(MacPalette.selbd, lineWidth: 1))
                }
            }
            .overlay(alignment: .bottom) {
                if on {
                    Circle()
                        .fill(MacPalette.acc)
                        .frame(width: 4, height: 4)
                        // bottom: -7px
                        .offset(y: 7)
                        .accessibilityHidden(true)
                }
            }
            .opacity(configuration.isPressed ? MacPalette.off : 1)
            .contentShape(MacCorners.boxShape)
            .accessibilityAddTraits(on ? .isSelected : [])
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
            .overlay(alignment: .leading) { MacRule(colour: MacPalette.line, vertical: true) }
            .overlay(alignment: .trailing) { MacRule(colour: MacPalette.line, vertical: true) }
    }
}
