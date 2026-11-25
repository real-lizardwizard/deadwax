import DeadwaxCore
import SwiftUI

/// The well a field sits in (dw.css's .well and .in - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice
/// R1b: the shared look, and the phone's pieces"; R1's MacWell, moved here for both): sunk - the darkest ground, a shadow
/// inside its top, the line's edge - and, while its field has the cursor, the accent's edge in place of the system's
/// focus ring (the web's own focus ring, app.css's `outline: var(--app-ring) solid var(--dw-accent)`). A button's
/// corners: the Mac's 4, the phone's square.
struct DWWell: View {
    var focused = false

    var body: some View {
        DWCorners.buttonShape
            .fill(DWPalette.well.shadow(.inner(color: DWPalette.wellShade, radius: 1, x: 0, y: 1)))
            .overlay(DWCorners.buttonShape.strokeBorder(focused ? DWPalette.acc : DWPalette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A text field (.in) in its well: the words in white, its prompt in the third colour - 24 tall on the Mac, 36 at least
/// on the phone at 16 (so iOS never zooms to it). SwiftUI's plain field with the system's focus ring off, so the well's
/// edge is the only one; Tab reaches it as any field. On the phone a finger's target of 44 round its 36 pt well: a tap
/// just above or below the well puts the cursor in it (the well's own target, under the field, which takes the taps on
/// itself first).
struct DWField: View {
    let prompt: String
    @Binding var text: String
    /// What VoiceOver calls it, where the prompt isn't its name.
    var spoken: String?

    @FocusState private var focused: Bool

    var body: some View {
        TextField(spoken ?? prompt, text: $text, prompt: Text(prompt).foregroundStyle(DWPalette.t3))
            .textFieldStyle(.plain)
            .font(Typeface.Look.text(.field))
            .foregroundStyle(DWPalette.fieldText)
            .autocorrectionDisabled()
            .focused($focused)
            .focusEffectDisabled()
            // .in: padding 0 8px, on both
            .padding(.horizontal, 8)
            .lookHeight(DWLook.here.fieldHeight)
            .background {
                DWWell(focused: focused)
                    .contentShape(DWTarget(face: DWCorners.buttonShape))
                    .onTapGesture {
                        focused = true
                    }
            }
    }
}

/// A field's row (.field), 8 from what it labels. On the Mac its label right-aligned, 84 wide, in the second colour, the
/// row 28 tall at least; on the phone a card's row - its label at the left, white, 88 wide at least, the row 44 tall at
/// least on its hairline (a group clips the last one's, as `.field:last-child` draws none).
struct DWFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        if Platform.mac {
            HStack(spacing: 8) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .frame(width: CGFloat(DWLook.here.labelWidth), alignment: .trailing)
                    .accessibilityHidden(true)
                content
                    .accessibilityLabel(label)
            }
            // .field: min-height 28px
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
        } else {
            HStack(spacing: 8) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.rowText)
                    .frame(minWidth: CGFloat(DWLook.here.labelWidth), alignment: .leading)
                    .accessibilityHidden(true)
                content
                    .accessibilityLabel(label)
            }
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        }
    }
}
