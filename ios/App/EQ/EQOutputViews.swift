import DeadwaxCore
import SwiftUI

// The outputs as the EQ's pages draw them (eq.md 3.2, 3.12). Named EQOutputViews, not the spec's EQOutputs.swift:
// Core already has an EQOutputs, and one name for two things in two modules is a trap for whoever reads either.

/// The output's row at the top of its EQ page (3.2): its symbol in `.title2` `quiet`, 32 pt wide; its name in
/// `.headline`; under it "Connected now" or "Not connected". One element with the header trait - "James's AirPods Pro,
/// connected now". When the page switches to the route, the name and symbol crossfade over 0.2 s (at once under Reduce
/// Motion).
struct EQOutputHeader: View {
    let output: EQOutput
    let connected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: output.symbol)
                .font(Typeface.symbol(.title2))
                .foregroundStyle(Palette.quiet)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(output.name)
                    .font(Typeface.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connected ? EQWords.Screen.connected : EQWords.Screen.notConnected)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: output.key)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EQWords.Screen.outputSaid(output.name, connected: connected))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A row of Other outputs (3.12): the output's symbol, its name, its short setting at the right ("Off", "Bass Boost") -
/// the chevron is its link's. As a Settings row, the value under the name when the two don't fit side by side. (R3b) On
/// the phone (`phone`) a row of its group (PhoneGo): the symbol in the third colour, the name at the row's 16, the
/// setting in the second colour and the chevron at its end - one element.
struct EQOtherOutputRow: View {
    let output: EQOutput
    let short: String
    var phone = false

    var body: some View {
        if phone {
            PhoneGo {
                Image(systemName: output.symbol)
                    .foregroundStyle(DWPalette.t3)
                    .accessibilityHidden(true)
                Text(output.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(short)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                PhoneChevron()
            }
        } else {
            LabeledContent {
                Text(short)
            } label: {
                Label {
                    Text(output.name)
                } icon: {
                    Image(systemName: output.symbol)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
    }
}

/// (R3b) The output at the top of the phone's EQ page (iEQ's `.btn` across the page): "Output" in the second colour, the
/// page's output's name - and "Not connected" after it, for one that isn't - and a caret, in a button's face 44 tall at
/// least; under the face AirPlay's own button (AVRoutePickerView, its glyph clear), so a tap there is AirPlay's - the
/// system's output picker - as Now Playing's output column is (OutputItem). The face is drawn only: VoiceOver reaches
/// AirPlay's button, which (R3b's review) says the page's output as the old header did - "James's AirPods Pro",
/// "Connected now" or "Not connected" - and, as its hint, that a double tap opens AirPlay and where the music plays now.
/// The name crossfades when the page follows the route.
struct EQOutputButton: View {
    let output: EQOutput
    let connected: Bool
    /// Where the music plays now (the route's name), said in AirPlay's button's hint.
    let playsTo: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What VoiceOver says of it: the page's output, whether it's connected, and AirPlay's double tap.
    private var said: AirPlaySaid {
        AirPlaySaid(label: output.name, value: connected ? EQWords.Screen.connected : EQWords.Screen.notConnected,
                    hint: EQWords.Screen.outputHint(playsTo: playsTo))
    }

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.goGap)) {
            Text(EQWords.Screen.output)
                .foregroundStyle(DWPalette.t2)
            Text(connected ? output.name : output.name + " · " + EQWords.Screen.notConnected)
                .foregroundStyle(DWPalette.buttonText)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: output.key)
            DWCaret(colour: DWPalette.buttonText)
        }
        .font(Typeface.Look.text(.button).weight(.medium))
        .padding(.horizontal, CGFloat(DWLook.here.buttonPadding))
        .padding(.vertical, typeSize.isAccessibilitySize ? CGFloat(PhoneLook.groupEnds) * 3 : 0)
        .frame(maxWidth: .infinity)
        .lookHeight(DWLook.here.target)
        .background {
            DWRaised(shape: DWCorners.buttonShape, face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen,
                     edge: DWPalette.buttonEdge, drop: DWPalette.buttonDrop)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background {
            AirPlayButton(glyph: false, playsTo: playsTo, said: said)
        }
    }
}
