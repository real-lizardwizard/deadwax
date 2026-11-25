import DeadwaxCore
import SwiftUI

/// The purple switch (dw.css's .sw - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look, and
/// the phone's pieces"), as a ToggleStyle: a Toggle drawn with it (`.toggleStyle(.phoneSwitch)`) is still iOS's switch to
/// VoiceOver - its label, its value, a double tap to change it. 46 x 28 and round (round stays round): on, in the app's
/// own purple (PrimaryButton's) with its knob at the right; off, the darkest ground in the line's edge, its knob grey at
/// the left. Its label leads the row, the switch at its end, and the whole row is the target, 44 tall at least. While it
/// can't be used (`.disabled`), faded as every control the app can't use is (DWPalette.off). Drawn nowhere until its
/// slices (R9's Settings).
struct PhoneSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        PhoneSwitchRow(configuration: configuration)
    }
}

/// The switch's row as drawn: the style's body, where the environment can be read.
private struct PhoneSwitchRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: CGFloat(PhoneLook.goGap)) {
                configuration.label
                Spacer(minLength: 0)
                PhoneSwitchFace(on: configuration.isOn)
            }
            .lookHeight(DWLook.here.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : DWPalette.off)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}

extension ToggleStyle where Self == PhoneSwitchStyle {
    /// The purple switch.
    static var phoneSwitch: PhoneSwitchStyle { PhoneSwitchStyle() }
}

/// The switch as drawn: its round track - a shade inside its top - and its knob, with a drop under it.
private struct PhoneSwitchFace: View {
    let on: Bool

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            if on {
                DWCorners.roundShape
                    .fill(DWPalette.switchFace.shadow(.inner(color: DWPalette.switchShade, radius: 1, x: 0, y: 1)))
                    .overlay(DWCorners.roundShape.strokeBorder(DWPalette.switchEdge, lineWidth: 1))
            } else {
                DWCorners.roundShape
                    .fill(DWPalette.switchOffFace.shadow(.inner(color: DWPalette.switchShade, radius: 1, x: 0, y: 1)))
                    .overlay(DWCorners.roundShape.strokeBorder(DWPalette.switchOffEdge, lineWidth: 1))
            }
            Circle()
                .fill(on ? DWPalette.switchKnob : DWPalette.switchOffKnob)
                .frame(width: CGFloat(PhoneLook.knob), height: CGFloat(PhoneLook.knob))
                .shadow(color: DWPalette.switchKnobDrop, radius: 1, x: 0, y: 1)
                // .sw::after: 2px in from inside its 1 pt edge
                .padding(CGFloat(PhoneLook.knobInset) + 1)
        }
        .frame(width: CGFloat(PhoneLook.switchWidth), height: CGFloat(PhoneLook.switchHeight))
        .accessibilityHidden(true)
    }
}
