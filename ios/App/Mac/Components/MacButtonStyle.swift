import DeadwaxCore
import SwiftUI

/// The Mac's buttons, as dw.css's .btn draws them (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1:
/// the frame and the shared pieces"): 26 tall (22 small), a glossy face in a 1 pt edge with a drop under it, pressed in
/// while held (MacRaised), faded while it can't be used.
///
/// - `.normal`: .btn - the toolbar's and a dialog's own.
/// - `.pri`: .btn.pri, the purple one - a page's Play, a dialog's Save. Return presses it only where the caller says
///   so (`.returnPresses()`, Platform's - a dialog's one action), never in a toolbar over a list, whose Return opens the
///   row selected.
/// - `.danger`: .btn.red - Delete, Remove.
/// - `.on`: .btn.on - a toolbar's button for a panel that is open (Queue, Lyrics, Info), drawn in the selection's colours.
///
/// (The kinds are named for what they do, never for a colour - `.red` or `.primary` would read, to
/// tests/test_ios_mac_look.py, as SwiftUI's own colours.)
///
/// SwiftUI's own `.bordered` would be the system's capsule: none of the Mac's views use it.
struct MacButtonStyle: ButtonStyle {
    enum Kind: Sendable {
        case normal, pri, danger, on
    }

    var kind: Kind = .normal
    /// .btn.sm: 22 tall, 8 either side, the small size's words.
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        MacButtonBody(configuration: configuration, kind: kind, small: small)
    }
}

/// The button as drawn: the style's body, where the environment can be read.
private struct MacButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: MacButtonStyle.Kind
    let small: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(Typeface.Mac.text(small ? .small : .control).weight(weight))
            .foregroundStyle(words)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            // .btn: padding 0 11px (.btn.sm 0 8px); gap 6px between a glyph and the words is the label's own HStack
            .padding(.horizontal, small ? 8 : 11)
            .frame(height: CGFloat(small ? MacLook.smallButtonHeight : MacLook.buttonHeight))
            .background { face }
            .contentShape(MacCorners.buttonShape)
            .opacity(enabled ? 1 : MacPalette.off)
    }

    /// .btn's weight 500; .btn.pri and .btn.red 600.
    private var weight: Font.Weight {
        switch kind {
        case .pri, .danger: return .semibold
        case .normal, .on: return .medium
        }
    }

    private var words: Color {
        switch kind {
        case .normal: return MacPalette.buttonText
        case .pri: return MacPalette.primaryText
        case .danger: return MacPalette.redText
        case .on: return MacPalette.selt
        }
    }

    @ViewBuilder private var face: some View {
        let pressed = configuration.isPressed && enabled
        switch kind {
        case .normal:
            MacRaised(shape: MacCorners.buttonShape, face: MacPalette.buttonFace, sheen: MacPalette.buttonSheen,
                      edge: MacPalette.buttonEdge, drop: MacPalette.buttonDrop, pressed: pressed)
        case .pri:
            MacRaised(shape: MacCorners.buttonShape, face: MacPalette.primaryFace, sheen: MacPalette.primarySheen,
                      edge: MacPalette.primaryEdge, drop: MacPalette.primaryDrop, pressed: pressed)
        case .danger:
            // .btn.red keeps .btn's sheen and drop
            MacRaised(shape: MacCorners.buttonShape, face: MacPalette.redFace, sheen: MacPalette.buttonSheen,
                      edge: MacPalette.redEdge, drop: MacPalette.buttonDrop, pressed: pressed)
        case .on:
            // .btn.on: the selection's fill and edge, .btn's sheen and drop
            MacRaised(shape: MacCorners.buttonShape, face: MacPalette.selbg, sheen: MacPalette.buttonSheen,
                      edge: MacPalette.selbd, drop: MacPalette.buttonDrop, pressed: pressed)
        }
    }
}
