import Foundation

/// The web's primary button (Phase 4, slice 3b - notes/ios-specs/phase4-library.md 2.8; James: "the color of the play
/// button on the album page doesn't show the play icon"): theme.css's --dw-primary-* as app.css's .app-rg-get and
/// player.css's .pl-pill.is-primary draw it - a purple gradient, a 1 pt edge, a highlight inside its top edge, a white
/// label, 4 pt corners, its fill darkened while pressed. The app's Palette and PrimaryFace turn these into SwiftUI; they replace
/// `.borderedProminent`, whose fill was the app's tint (#C084FC, the web's accent for text on black) under a white
/// label - 2.64:1. tests/test_ios_palette.py holds every number here to theme.css and player.css.
public enum PrimaryButton {
    /// --dw-primary-bg: linear-gradient(to bottom, #a24ef2 0%, #8a2ee0 100%).
    public static let top = DeckRGBA(0xA2, 0x4E, 0xF2)
    public static let bottom = DeckRGBA(0x8A, 0x2E, 0xE0)
    /// --dw-primary-border, a 1 pt edge (--dw-hairline).
    public static let edge = DeckRGBA(0x7C, 0x3A, 0xED)
    /// --dw-primary-highlight: inset 0 1px 0 rgba(255, 255, 255, 0.22) - a 1 pt line inside the top edge.
    public static let highlight = DeckRGBA(255, 255, 255, 0.22)
    /// --dw-text: the label and its glyph.
    public static let label = DeckRGBA(255, 255, 255)
    /// --dw-primary-pressed: brightness(0.92). The web darkens the whole button by it, its label too - white made
    /// #ebebeb, 4.13:1 at the top of the pressed fill, under AA where a label's top line is drawn. The phone darkens the
    /// fill and the edge alone (slice 3b's review), so the label stays white: 4.92:1 at the top pressed, 6.72:1 at the
    /// foot. A small, deliberate difference from the web, for the label's sake.
    public static let pressed = 0.92
    /// The fill's two ends and the edge while pressed: each darkened by `pressed`, as CSS's brightness() does.
    public static let pressedTop = Contrast.brightness(top, pressed)
    public static let pressedBottom = Contrast.brightness(bottom, pressed)
    public static let pressedEdge = Contrast.brightness(edge, pressed)
    /// --dw-radius-control.
    public static let radius = 4.0
    /// --pl-pill-height: the album's and the playlist's Play and Shuffle.
    public static let largeHeight = 48.0

    /// The gradient's colour `at` (0 its top, 1 its bottom), as CSS mixes a linear-gradient: in sRGB, each channel
    /// rounded.
    public static func fill(at: Double) -> DeckRGBA {
        Contrast.mix(top, bottom, at)
    }

    /// The pressed fill's colour `at`, the same way.
    public static func pressedFill(at: Double) -> DeckRGBA {
        Contrast.mix(pressedTop, pressedBottom, at)
    }
}

/// WCAG 2's contrast (its relative luminance, sRGB): what the primary's label was measured with.
public enum Contrast {
    /// One channel, 0-255, as linear light.
    static func linear(_ channel: Int) -> Double {
        let c = Double(channel) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// The colour's relative luminance, 0 (black) to 1 (white) - its alpha ignored.
    public static func luminance(_ colour: DeckRGBA) -> Double {
        0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }

    /// The contrast ratio of two colours, 1 to 21, whichever is lighter.
    public static func ratio(_ a: DeckRGBA, _ b: DeckRGBA) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `a` towards `b` by `t` (0 to 1), each channel rounded - opaque.
    public static func mix(_ a: DeckRGBA, _ b: DeckRGBA, _ t: Double) -> DeckRGBA {
        let k = min(max(t, 0), 1)
        func channel(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * k).rounded()) }
        return DeckRGBA(channel(a.red, b.red), channel(a.green, b.green), channel(a.blue, b.blue))
    }

    /// `colour` with every channel multiplied by `by` (CSS's brightness()), rounded.
    public static func brightness(_ colour: DeckRGBA, _ by: Double) -> DeckRGBA {
        func channel(_ x: Int) -> Int { min(255, Int((Double(x) * by).rounded())) }
        return DeckRGBA(channel(colour.red), channel(colour.green), channel(colour.blue), colour.alpha)
    }
}
