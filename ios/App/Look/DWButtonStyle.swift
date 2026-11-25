import DeadwaxCore
import SwiftUI

/// The new look's buttons on both devices, as dw.css's .btn draws them (the redesign, slices R1 and R1b - notes/ios.md
/// "The redesign, slice R1b: the shared look, and the phone's pieces"; R1's MacButtonStyle, moved here for both): a
/// glossy face in a 1 pt edge with a drop under it, pressed in while held (DWRaised; the phone's purple darkened, as
/// PrimaryFace's is), faded while it can't be used - in
/// its device's sizes (DWLook), corners (DWCorners) and type (Typeface.Look). On the Mac 26 tall (22 small), exact; on
/// the phone 36 (32 small, 48 large) at least, growing with the text, and a finger's target of 44 round a smaller face.
///
/// - `.normal`: .btn - the toolbar's and a dialog's own.
/// - `.pri`: .btn.pri, the purple one - a page's Play, a dialog's Save. On the phone the app's own purple (PrimaryButton's,
///   `.dw.ph .btn.pri`), on the Mac dw.css's. Return presses it only where the caller says so (`.returnPresses()`,
///   Platform's - a dialog's one action), never in a toolbar over a list, whose Return opens the row selected.
/// - `.danger`: .btn.red - Delete, Remove.
/// - `.on`: .btn.on - a toolbar's button for a panel that is open (Queue, Lyrics, Info), drawn in the selection's colours.
///
/// (The kinds are named for what they do, never for a colour - `.red` or `.primary` would read, to
/// tests/test_ios_mac_look.py, as SwiftUI's own colours.)
///
/// SwiftUI's own `.bordered` would be the system's capsule: none of the new look's views use it.
struct DWButtonStyle: ButtonStyle {
    enum Kind: Sendable {
        case normal, pri, danger, on
    }

    /// .btn, .btn.sm and .btn.lg (the phone's: an album's Play and Shuffle, a foot's Save - the Mac's large is a button's).
    enum Size: Sendable {
        case standard, small, large
    }

    var kind: Kind = .normal
    var size: Size = .standard
    /// .grow: the button takes the room it's given, its words centred (a foot's main action, an album's Play).
    var fills = false

    func makeBody(configuration: Configuration) -> some View {
        DWButtonBody(configuration: configuration, kind: kind, size: size, fills: fills)
    }
}

/// The button as drawn: the style's body, where the environment can be read.
private struct DWButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DWButtonStyle.Kind
    let size: DWButtonStyle.Size
    let fills: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(Typeface.Look.text(role).weight(weight))
            .foregroundStyle(words)
            .lineLimit(1)
            .fixedSize(horizontal: !fills, vertical: false)
            // .btn: padding 0 11px on the Mac (.btn.sm 0 8px), 0 13px on the phone (.btn.sm 0 11px); the gap of 6
            // between a glyph and the words is the label's own HStack
            .padding(.horizontal, CGFloat(padding))
            .frame(maxWidth: fills ? .infinity : nil)
            .lookHeight(height)
            .background { face }
            .contentShape(DWTarget(face: DWCorners.buttonShape))
            .opacity(enabled ? 1 : DWPalette.off)
    }

    private var role: Typeface.Look.Role {
        switch size {
        case .standard: return .button
        case .small: return .smallButton
        case .large: return .largeButton
        }
    }

    private var height: Double {
        let look = DWLook.here
        switch size {
        case .standard: return look.buttonHeight
        case .small: return look.smallButtonHeight
        case .large: return look.largeButtonHeight
        }
    }

    private var padding: Double {
        let look = DWLook.here
        switch size {
        case .standard: return look.buttonPadding
        case .small: return look.smallButtonPadding
        case .large: return look.largeButtonPadding
        }
    }

    /// .btn's weight 500; .btn.pri and .btn.red 600, and the phone's .btn.lg.
    private var weight: Font.Weight {
        switch kind {
        case .pri, .danger: return .semibold
        case .normal, .on: return size == .large && !Platform.mac ? .semibold : .medium
        }
    }

    private var words: Color {
        switch kind {
        case .normal: return DWPalette.buttonText
        case .pri: return Platform.mac ? DWPalette.primaryText : DWPalette.phonePrimaryText
        case .danger: return DWPalette.redText
        case .on: return DWPalette.selt
        }
    }

    @ViewBuilder private var face: some View {
        let pressed = configuration.isPressed && enabled
        switch kind {
        case .normal:
            DWRaised(shape: DWCorners.buttonShape, face: DWPalette.buttonFace, sheen: DWPalette.buttonSheen,
                     edge: DWPalette.buttonEdge, drop: DWPalette.buttonDrop, pressed: pressed)
        case .pri:
            if Platform.mac {
                DWRaised(shape: DWCorners.buttonShape, face: DWPalette.primaryFace, sheen: DWPalette.primarySheen,
                         edge: DWPalette.primaryEdge, drop: DWPalette.primaryDrop, pressed: pressed)
            } else {
                // the phone's: the app's own purple, PrimaryButton's (`.dw.ph .btn.pri`) - and pressed, PrimaryFace's
                // reviewed press (slice 3b): the fill and the edge darkened by PrimaryButton.pressed (brightness 0.92,
                // theme.css's --dw-primary-pressed), the highlight kept and nothing turned over, so an album's Play
                // presses as it does today when it moves to this style
                DWRaised(shape: DWCorners.buttonShape,
                         face: pressed ? DWPalette.phonePrimaryPressedFace : DWPalette.phonePrimaryFace,
                         sheen: DWPalette.phonePrimarySheen,
                         edge: pressed ? DWPalette.phonePrimaryPressedEdge : DWPalette.phonePrimaryEdge,
                         drop: DWPalette.phonePrimaryDrop)
            }
        case .danger:
            // .btn.red keeps .btn's sheen and drop
            DWRaised(shape: DWCorners.buttonShape, face: DWPalette.redFace, sheen: DWPalette.buttonSheen,
                     edge: DWPalette.redEdge, drop: DWPalette.buttonDrop, pressed: pressed)
        case .on:
            // .btn.on: the selection's fill and edge, .btn's sheen and drop
            DWRaised(shape: DWCorners.buttonShape, face: DWPalette.selbg, sheen: DWPalette.buttonSheen,
                     edge: DWPalette.selbd, drop: DWPalette.buttonDrop, pressed: pressed)
        }
    }
}
