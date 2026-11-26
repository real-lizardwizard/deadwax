import DeadwaxCore
import SwiftUI

/// A checkbox (dw.css's input[type=checkbox] - the redesign, slice R11, notes/ios.md "The redesign, slice R11: Tags,
/// Artwork, Lyrics and Delete"; R1's MacCheckbox, made here for both): drawn, since the iOS SDK has no `.checkbox`
/// toggle style. A click or a tap anywhere on it turns it; VoiceOver reads one element, a toggle, with its state.
///
/// - On the Mac, MacCheckbox as R1 drew it: a 13 pt box in a well while it is off, the checkbox's purple (its
///   accent-color) with a white tick while it is on, and its words beside it.
/// - On the phone (`.dw.ph input[type=checkbox]`): a square box of 20, growing with the text, flat - its edge alone while
///   it is off, the purple with a white tick while it is on - and a finger's target of 44 round it (DWTarget).
/// - `showsWords` false where what is round it says what it ticks (the Mac's Tags table, a row's title beside it):
///   VoiceOver hears its words still.
struct DWCheckbox: View {
    let words: String
    @Binding var on: Bool
    var showsWords = true

    var body: some View {
        Button {
            on.toggle()
        } label: {
            HStack(spacing: 6) {
                DWCheckMark(on: on)
                if showsWords {
                    Text(words)
                        .font(Typeface.Look.text(.field))
                        .foregroundStyle(DWPalette.head)
                }
            }
            .contentShape(DWTarget(face: DWCorners.chipShape))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words)
        .accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// The checkbox's box alone, ticked or not - DWCheckbox's, and a row's that is itself the button turning it (the
/// phone's Tags rows: the whole row ticks, as iEditTags' `<label class="row">` does). Hidden from VoiceOver: what holds
/// it says whether it is ticked.
struct DWCheckMark: View {
    let on: Bool

    /// input[type=checkbox]: 13 x 13 on the Mac.
    private static let macBox: CGFloat = 13
    /// .dw.ph input[type=checkbox]: 20 x 20 on the phone, growing with the text.
    @ScaledMetric(relativeTo: .body) private var phoneBox: CGFloat = 20

    var body: some View {
        let side = Platform.mac ? Self.macBox : phoneBox
        ZStack {
            if on {
                DWCorners.chipShape.fill(DWPalette.checkFill)
                Image(systemName: "checkmark")
                    .font(Typeface.symbol(size: Platform.mac ? 8 : side * 0.55, weight: .heavy))
                    .foregroundStyle(DWPalette.text)
            } else if Platform.mac {
                DWCorners.chipShape
                    .fill(DWPalette.well.shadow(.inner(color: DWPalette.wellShade, radius: 1, x: 0, y: 1)))
                    .overlay(DWCorners.chipShape.strokeBorder(DWPalette.line, lineWidth: 1))
            } else {
                // flat: the empty box's edge alone, in the third colour - seen on the page's black
                DWCorners.chipShape.strokeBorder(DWPalette.t3, lineWidth: 1.5)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
