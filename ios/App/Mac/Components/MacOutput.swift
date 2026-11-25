import DeadwaxCore
import SwiftUI

/// Where the music plays (the drawings' "MacBook speakers ▾" beside EQ - the Mac redesign, slice R1, notes/ios.md "The
/// Mac redesign, slice R1: the frame and the shared pieces"), for R4's bar: the system's own AirPlay button - its picker
/// is macOS's, and AVRoutePickerView can't be opened from a button of ours - with the output's name beside it, as the
/// EQ names it (EQOutputs' name, renamed where you renamed it).
struct MacOutput: View {
    @Environment(EQModel.self) private var eq

    /// The AirPlay button's square, a small button's height.
    private static let picker = CGFloat(MacLook.smallButtonHeight)

    var body: some View {
        HStack(spacing: 4) {
            AirPlayButton()
                .frame(width: Self.picker, height: Self.picker)
            Text(eq.settings.setting(for: eq.route).shownName)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(MacPalette.t2)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}
