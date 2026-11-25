import DeadwaxCore
import SwiftUI

/// The well a field sits in (dw.css's .well and .in - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice
/// R1: the frame and the shared pieces"): sunk - the darkest ground, a shadow inside its top, the line's edge - and,
/// while its field has the cursor, the accent's edge in place of the system's focus ring (the web's own focus ring,
/// app.css's `outline: var(--app-ring) solid var(--dw-accent)`).
struct MacWell: View {
    var focused = false

    var body: some View {
        MacCorners.buttonShape
            .fill(MacPalette.well.shadow(.inner(color: MacPalette.wellShade, radius: 1, x: 0, y: 1)))
            .overlay(MacCorners.buttonShape.strokeBorder(focused ? MacPalette.acc : MacPalette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A text field (.in): 24 tall in its well, the window's words in white, its prompt in the third colour. SwiftUI's
/// plain field with the system's focus ring off, so the well's edge is the only one; Tab reaches it as any field.
struct MacField: View {
    let prompt: String
    @Binding var text: String
    /// What VoiceOver calls it, where the prompt isn't its name.
    var spoken: String?

    @FocusState private var focused: Bool

    var body: some View {
        TextField(spoken ?? prompt, text: $text, prompt: Text(prompt).foregroundStyle(MacPalette.t3))
            .textFieldStyle(.plain)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(MacPalette.fieldText)
            .autocorrectionDisabled()
            .focused($focused)
            .focusEffectDisabled()
            // .in: padding 0 8px
            .padding(.horizontal, 8)
            .frame(height: CGFloat(MacLook.fieldHeight))
            .background { MacWell(focused: focused) }
    }
}

/// A field's row (.field): its label right-aligned, 84 wide, 8 from what it labels.
struct MacFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Typeface.Mac.text(.control))
                .foregroundStyle(MacPalette.t2)
                .lineLimit(1)
                .frame(width: CGFloat(MacLook.labelWidth), alignment: .trailing)
                .accessibilityHidden(true)
            content
                .accessibilityLabel(label)
        }
        // .field: min-height 28px
        .frame(minHeight: CGFloat(MacLook.findHeight))
    }
}
