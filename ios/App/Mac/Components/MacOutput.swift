import DeadwaxCore
import SwiftUI

/// Where the music plays (the drawings' "MacBook speakers ▾" beside EQ - the Mac redesign, slice R1, notes/ios.md "The
/// Mac redesign, slice R1: the frame and the shared pieces"), for R4's bar: the system's own AirPlay button - its picker
/// is macOS's, and AVRoutePickerView can't be opened from a button of ours - with the output's name beside it, as the
/// EQ names it (EQOutputs' name, renamed where you renamed it).
struct MacOutput: View {
    @Environment(EQModel.self) private var eq

    /// (R4) Whether the name is drawn beside the button: the bar leaves it out in a narrow window, so the display keeps
    /// its room (notes/ios.md "The redesign, slice R4: the player bar, the mini player and the tab bar").
    var named = true

    /// The AirPlay button's square, a small button's height.
    private static let picker = CGFloat(MacLook.smallButtonHeight)

    var body: some View {
        let name = eq.settings.setting(for: eq.route).shownName
        HStack(spacing: 4) {
            AirPlayButton()
                .frame(width: Self.picker, height: Self.picker)
            if named {
                Text(name)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        // (R4) truncated past its room in the bar, or left out there: the whole name over it
        .help(name)
    }
}
