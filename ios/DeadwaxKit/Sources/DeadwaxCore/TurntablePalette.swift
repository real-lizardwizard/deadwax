/// The turntable's and the fader's colours (notes/ios-specs/turntable.md 2.14), as the RGBA each of the app's Palette
/// colours is made from - named after the web's tokens and holding their values, so nothing in the drawing is a raw
/// value outside the Palette. The values are held to theme.css by Fixtures/deck/tokens.json (the exporter reads them
/// out of it), so a change to a web token fails the phone's test rather than drifting. The app's Palette
/// (ios/App) turns each into a SwiftUI Color.
public struct DeckRGBA: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int
    public let alpha: Double
    public init(_ red: Int, _ green: Int, _ blue: Int, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum TurntablePalette {
    public static let ttPlinth = DeckRGBA(0x19, 0x17, 0x1E)
    public static let ttPlatter = DeckRGBA(0x2A, 0x27, 0x30)
    public static let ttVinyl = DeckRGBA(0x14, 0x12, 0x17)
    /// The grooves' rings: black at 0.2.
    public static let ttGroove = DeckRGBA(0, 0, 0, 0.2)
    /// The sheen's two highlights.
    public static let ttSheenHigh = DeckRGBA(255, 255, 255, 0.07)
    public static let ttSheenLow = DeckRGBA(255, 255, 255, 0.05)
    public static let ttLabel = DeckRGBA(0x14, 0x14, 0x14)
    public static let ttLabelEdge = DeckRGBA(255, 255, 255, 0.3)
    public static let ttSpindle = DeckRGBA(0x0E, 0x0C, 0x12)
    public static let ttSpindleEdge = DeckRGBA(255, 255, 255, 0.25)
    public static let ttArm = DeckRGBA(0xC9, 0xC6, 0xD1)
    public static let ttArmHead = DeckRGBA(0xD8, 0xD5, 0xDE)
    public static let ttArmWeight = DeckRGBA(0x8E, 0x8A, 0x96)
    public static let ttPivot = DeckRGBA(0x3A, 0x36, 0x42)
    public static let ttPivotEdge = DeckRGBA(0x56, 0x52, 0x5F)
    public static let ttHandleEdge = DeckRGBA(235, 235, 245, 0.18)
    /// The head's shadow while held (TurntableGeometry.headLift): `--dw-shadow`'s colour, black at 0.5. Not in `tokens`
    /// yet - tokens.json has no `--dw-shadow`, and adding it to the exporter's list writes every fixture again; main's
    /// web lift brings it.
    public static let ttHeadShadow = DeckRGBA(0, 0, 0, 0.5)
    /// The fader's slot (the app's barTrack).
    public static let barTrack = DeckRGBA(0x12, 0x11, 0x17)
    /// The plinth's edge, the slot's, the readout's well (the app's barEdge).
    public static let barEdge = DeckRGBA(0x2C, 0x2A, 0x36)
    /// The fader's mark.
    public static let textTertiary = DeckRGBA(0x8E, 0x8E, 0xA3)
    /// The mark at exactly 1x.
    public static let greenIcon = DeckRGBA(0x34, 0xD3, 0x99)
    /// Focus rings only.
    public static let accent = DeckRGBA(0xC0, 0x84, 0xFC)
    /// The readout off 1x, the chip's text.
    public static let accentText = DeckRGBA(0xD8, 0xB4, 0xFE)
    public static let toggledFill = DeckRGBA(168, 85, 247, 0.18)
    public static let toggledEdge = DeckRGBA(192, 132, 252, 0.45)
    /// The readout's face at 1x: black at 0.2, over the plinth.
    public static let ttWell = DeckRGBA(0, 0, 0, 0.2)
    /// A 1 pt inner shadow, 1 pt down.
    public static let wellInset = DeckRGBA(0, 0, 0, 0.5)
    /// A 1 pt line inside the top edge (the plinth, the look button).
    public static let highlight = DeckRGBA(255, 255, 255, 0.06)
    /// The look button's face, top to bottom, and pressed.
    public static let secondaryFillTop = DeckRGBA(255, 255, 255, 0.09)
    public static let secondaryFillBottom = DeckRGBA(255, 255, 255, 0.05)
    public static let secondaryEdge = DeckRGBA(255, 255, 255, 0.1)
    /// The look button's glyph.
    public static let onSecondary = DeckRGBA(0xE8, 0xE8, 0xF0)

    /// Each colour's web token, and which of the colours the token's value names it is (0 the first) - what the test
    /// holds against tokens.json. `quiet` is Color.secondary, as Phase 1 mapped `--dw-text-2`, so it isn't here.
    public static let tokens: [(name: String, colour: DeckRGBA, token: String, index: Int)] = [
        ("ttPlinth", ttPlinth, "--dw-tt-plinth", 0),
        ("ttPlatter", ttPlatter, "--dw-tt-platter", 0),
        ("ttVinyl", ttVinyl, "--dw-tt-vinyl", 0),
        ("ttGroove", ttGroove, "--dw-tt-grooves", 2),
        ("ttSheenHigh", ttSheenHigh, "--dw-tt-sheen", 1),
        ("ttSheenLow", ttSheenLow, "--dw-tt-sheen", 4),
        ("ttLabel", ttLabel, "--dw-tt-label", 0),
        ("ttLabelEdge", ttLabelEdge, "--dw-tt-label-edge", 0),
        ("ttSpindle", ttSpindle, "--dw-tt-spindle", 0),
        ("ttSpindleEdge", ttSpindleEdge, "--dw-tt-spindle-edge", 0),
        ("ttArm", ttArm, "--dw-tt-arm", 0),
        ("ttArmHead", ttArmHead, "--dw-tt-arm-head", 0),
        ("ttArmWeight", ttArmWeight, "--dw-tt-arm-weight", 0),
        ("ttPivot", ttPivot, "--dw-tt-pivot", 0),
        ("ttPivotEdge", ttPivotEdge, "--dw-tt-pivot-edge", 0),
        ("ttHandleEdge", ttHandleEdge, "--dw-tt-handle-edge", 0),
        ("barTrack", barTrack, "--dw-track", 0),
        ("barEdge", barEdge, "--dw-border", 0),
        ("textTertiary", textTertiary, "--dw-text-3", 0),
        ("greenIcon", greenIcon, "--dw-green-icon", 0),
        ("accent", accent, "--dw-accent", 0),
        ("accentText", accentText, "--dw-accent-text", 0),
        ("toggledFill", toggledFill, "--dw-toggled-bg", 0),
        ("toggledEdge", toggledEdge, "--dw-toggled-border", 0),
        ("ttWell", ttWell, "--dw-well", 0),
        ("wellInset", wellInset, "--dw-well-inset", 0),
        ("highlight", highlight, "--dw-highlight", 0),
        ("secondaryFillTop", secondaryFillTop, "--dw-secondary-bg", 0),
        ("secondaryFillBottom", secondaryFillBottom, "--dw-secondary-bg", 1),
        ("secondaryFillPressedTop", secondaryFillBottom, "--dw-secondary-bg-active", 0),
        ("secondaryFillPressedBottom", secondaryFillTop, "--dw-secondary-bg-active", 1),
        ("secondaryEdge", secondaryEdge, "--dw-secondary-border", 0),
        ("onSecondary", onSecondary, "--dw-text-on-secondary", 0),
    ]
}
