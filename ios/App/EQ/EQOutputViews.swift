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
                .font(.title2)
                .foregroundStyle(Palette.quiet)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(output.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connected ? EQWords.Screen.connected : EQWords.Screen.notConnected)
                    .font(.footnote)
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
/// the chevron is its link's. As a Settings row, the value under the name when the two don't fit side by side.
struct EQOtherOutputRow: View {
    let output: EQOutput
    let short: String

    var body: some View {
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
