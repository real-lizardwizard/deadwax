import SwiftUI

/// A raised face, as dw.css draws a button or a player's key (the Mac redesign, slice R1 - notes/ios.md "The Mac
/// redesign, slice R1: the frame and the shared pieces"): its gradient, a sheen along its top inside its edge (the rule's
/// `inset 0 1px 0`), its 1 pt edge and its drop under it (`0 1px 1px`) - and pressed, the gradient turned over and the
/// sheen gone, so it sits in rather than lights up (the web's secondary pill turns its gradient over when pressed; dw.css
/// draws no pressed state of its own). Every colour is the caller's, from MacPalette.
struct MacRaised<Face: InsettableShape>: View {
    let shape: Face
    let face: LinearGradient
    let sheen: Color
    let edge: Color
    let drop: Color
    var pressed = false

    var body: some View {
        ZStack {
            if pressed {
                shape.fill(face)
                    .rotationEffect(.degrees(180))
            } else {
                shape.fill(face)
                shape.inset(by: 1)
                    .fill(face.shadow(.inner(color: sheen, radius: 0, x: 0, y: 1)))
            }
            shape.strokeBorder(edge, lineWidth: 1)
        }
        .shadow(color: drop, radius: 0.5, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

/// A 1 pt line along an edge of a strip (a border-top, a border-bottom) or its sheen just inside it.
struct MacRule: View {
    let colour: Color
    var vertical = false

    var body: some View {
        colour
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}
