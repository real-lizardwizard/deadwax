import DeadwaxCore
import SwiftUI

/// A toggle button (dw.css's .tog - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice R1b: the shared
/// look, and the phone's pieces"; R1's MacToggleStyle, moved here for both): a glyph with no face while off, the
/// selection's fill, edge and words while on. VoiceOver reads it as selected while on - the caller's label says which it
/// is.
///
/// - On the Mac, Shuffle's and Repeat's (.tog): 30, a box's corners, the accent's 4 pt dot 7 under it while on.
/// - On the phone (.tog.sm): 28 at least, square, no dot (`.tog.sm.on::after` draws none), a finger's target of 44
///   round it. R2's Grid and List on the Library's meta line were these; since R2b (James's drawing of 25 Nov) they are
///   two bare glyphs (LibraryLineEnd), so the phone's half is drawn nowhere just now.
struct DWToggleStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(on ? DWPalette.acct : DWPalette.t3)
            .lookSquare(DWLook.here.toggleSize)
            .background {
                if on {
                    DWCorners.boxShape
                        .fill(DWPalette.selbg)
                        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.selbd, lineWidth: 1))
                }
            }
            .overlay(alignment: .bottom) {
                if on, Platform.mac {
                    Circle()
                        .fill(DWPalette.acc)
                        .frame(width: 4, height: 4)
                        // bottom: -7px
                        .offset(y: 7)
                        .accessibilityHidden(true)
                }
            }
            .opacity(configuration.isPressed ? DWPalette.off : 1)
            .contentShape(DWTarget(face: DWCorners.boxShape))
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}
