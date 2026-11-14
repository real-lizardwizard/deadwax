import DeadwaxCore
import SwiftUI

// The web's two buttons (Phase 4, slice 3b - phase4-library.md 2.8; James: "the color of the play button on the album
// page doesn't show the play icon"): the primary - player.css's .pl-pill.is-primary and app.css's primary buttons, a
// purple gradient under a white label - and the secondary pill beside it (.pl-pill). They replace `.borderedProminent`,
// whose fill was the app's tint (#C084FC, the web's accent for text on black) under a white label, 2.64:1; and, in the
// same pair, `.bordered`, so the pair is one shape. Their numbers are Core's (PrimaryButton, held to theme.css by
// tests/test_ios_palette.py; the secondary's TurntablePalette, held by the deck's tokens.json), and the label's contrast
// measured there (PrimaryButtonTests): 4.57:1 or more wherever a label is drawn, 4.28:1 at the very top edge.

extension Palette {
    /// --dw-primary-bg: #a24ef2 to #8a2ee0, top to bottom.
    static let primaryFill = LinearGradient(colors: [colour(PrimaryButton.top), colour(PrimaryButton.bottom)],
                                            startPoint: .top, endPoint: .bottom)
    /// --dw-primary-border #7c3aed.
    static let primaryEdge = colour(PrimaryButton.edge)
    /// --dw-primary-highlight: white at 0.22, a 1 pt line inside the top edge.
    static let primaryHighlight = colour(PrimaryButton.highlight)
    /// --dw-text: the primary's label and glyph.
    static let primaryLabel = colour(PrimaryButton.label)
    /// The primary's purple, solid - the gradient's foot: the pull's armed disc (3.5).
    static let primary = colour(PrimaryButton.bottom)
}

/// The primary button: one main action - an album's and a playlist's Play (`large`, the web's 48 pt pill), Add to my
/// library, Use for, Create, Sign in, Try again, Set up Navidrome, Turn On. Darkened while pressed (brightness 0.92, the
/// web's filter), faded to Palette.off while it can't be used.
struct PrimaryFace: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonFace(configuration: configuration, primary: true, large: large)
    }
}

/// The secondary pill (.pl-pill): the action beside a primary one - an album's and a playlist's Shuffle, Not Now, Cancel,
/// Change address - so the pair is one shape. The look button's face (--dw-secondary-bg), lightening as pressed
/// (--dw-secondary-bg-active, the same gradient reversed).
struct SecondaryPill: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonFace(configuration: configuration, primary: false, large: large)
    }
}

private struct ButtonFace: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let large: Bool

    @Environment(\.isEnabled) private var isEnabled

    /// The control's own height (the boards' 36 pt, --dw-control-height), and the web's pill.
    private static let height: CGFloat = 36
    private static let hairline: CGFloat = 1

    var body: some View {
        let radius = CGFloat(PrimaryButton.radius)
        let shape = RoundedRectangle(cornerRadius: radius)
        let pressed = configuration.isPressed
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? Palette.primaryLabel : Palette.onSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: large ? CGFloat(PrimaryButton.largeHeight) : Self.height)
            .background {
                if primary {
                    shape.fill(Palette.primaryFill)
                } else {
                    shape.fill(pressed ? Palette.secondaryFillPressed : Palette.secondaryFill)
                }
            }
            .overlay(alignment: .top) {
                // the highlight: a line inside the top edge, following its corners (LookFace's)
                shape.inset(by: Self.hairline * 1.5)
                    .stroke(primary ? Palette.primaryHighlight : Palette.highlight, lineWidth: Self.hairline)
                    .mask(alignment: .top) { Rectangle().frame(height: radius) }
            }
            .overlay(shape.strokeBorder(primary ? Palette.primaryEdge : Palette.secondaryEdge, lineWidth: Self.hairline))
            // brightness(0.92) over the whole button, the primary's press (--dw-primary-pressed)
            .colorMultiply(primary && pressed ? Color(white: PrimaryButton.pressed) : .white)
            .opacity(isEnabled ? 1 : Palette.off)
            .contentShape(shape)
    }
}
