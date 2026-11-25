import DeadwaxCore
import SwiftUI

/// A checkbox (dw.css's input[type=checkbox] - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"): drawn, since the iOS SDK has no `.checkbox` toggle style. A 13 pt box - in a well while
/// it is off, the checkbox's purple (its accent-color) with a white tick while it is on - and its words beside it; a
/// click anywhere on it turns it. VoiceOver reads one element, a toggle, with its state.
struct MacCheckbox: View {
    let words: String
    @Binding var on: Bool

    /// input[type=checkbox]: 13 x 13.
    private static let box: CGFloat = 13

    var body: some View {
        Button {
            on.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    if on {
                        DWCorners.chipShape.fill(DWPalette.checkFill)
                        Image(systemName: "checkmark")
                            .font(Typeface.symbol(size: 8, weight: .heavy))
                            .foregroundStyle(DWPalette.text)
                    } else {
                        DWCorners.chipShape
                            .fill(DWPalette.well.shadow(.inner(color: DWPalette.wellShade, radius: 1, x: 0, y: 1)))
                            .overlay(DWCorners.chipShape.strokeBorder(DWPalette.line, lineWidth: 1))
                    }
                }
                .frame(width: Self.box, height: Self.box)
                Text(words)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.head)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words)
        .accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)
    }
}
