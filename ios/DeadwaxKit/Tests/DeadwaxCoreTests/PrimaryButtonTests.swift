import Foundation
import Testing
@testable import DeadwaxCore

/// The primary button (phase4-library.md 2.8; James: "the color of the play button on the album page doesn't show the
/// play icon"): the web's --dw-primary-* (tests/test_ios_palette.py holds the numbers to theme.css), and its white label
/// measured with WCAG 2's contrast - AA's 4.5:1 for text over the whole gradient but its lightest fifth, 3:1 (a glyph's,
/// a large label's) over all of it; and the old fill, the tint, under 3:1 - what James saw.
@Suite struct PrimaryButtonTests {
    private static func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.001 }

    @Test func wcagsOwnPairs() {
        let white = DeckRGBA(255, 255, 255), black = DeckRGBA(0, 0, 0)
        #expect(Contrast.ratio(white, black) == 21)
        #expect(Contrast.ratio(black, white) == 21, "whichever is lighter")
        #expect(Contrast.ratio(white, white) == 1)
        #expect(Self.near(Contrast.luminance(DeckRGBA(0x76, 0x76, 0x76)), 0.1812), "#767676, the grey of 4.54:1 on white")
        #expect(Self.near(Contrast.ratio(white, DeckRGBA(0x76, 0x76, 0x76)), 4.542))
        #expect(Self.near(Contrast.linear(10), 10.0 / 255 / 12.92), "under 0.04045: the straight part")
        #expect(Contrast.luminance(DeckRGBA(255, 255, 255, 0.1)) == 1, "alpha ignored")
    }

    @Test func theColoursAreTheWebs() {
        #expect(PrimaryButton.top == DeckRGBA(0xA2, 0x4E, 0xF2) && PrimaryButton.bottom == DeckRGBA(0x8A, 0x2E, 0xE0))
        #expect(PrimaryButton.edge == DeckRGBA(0x7C, 0x3A, 0xED) && PrimaryButton.label == DeckRGBA(255, 255, 255))
        #expect(PrimaryButton.highlight == DeckRGBA(255, 255, 255, 0.22))
        #expect(PrimaryButton.pressed == 0.92 && PrimaryButton.radius == 4 && PrimaryButton.largeHeight == 48)
        #expect(PrimaryButton.fill(at: 0) == PrimaryButton.top && PrimaryButton.fill(at: 1) == PrimaryButton.bottom)
        #expect(PrimaryButton.fill(at: 0.5) == DeckRGBA(0x96, 0x3E, 0xE9), "CSS's sRGB mix")
        #expect(PrimaryButton.fill(at: 0.2) == DeckRGBA(0x9D, 0x48, 0xEE), "each channel rounded: green 71.6 is 72")
        #expect(PrimaryButton.fill(at: -1) == PrimaryButton.top && PrimaryButton.fill(at: 3) == PrimaryButton.bottom)
    }

    @Test func theLabelReadsOnTheGradient() {
        let white = PrimaryButton.label
        let bottom = Contrast.ratio(white, PrimaryButton.bottom)
        let middle = Contrast.ratio(white, PrimaryButton.fill(at: 0.5))
        let fifth = Contrast.ratio(white, PrimaryButton.fill(at: 0.2))
        let top = Contrast.ratio(white, PrimaryButton.top)
        #expect(Self.near(bottom, 5.919) && Self.near(middle, 5.045) && Self.near(top, 4.279))
        #expect(fifth >= 4.5, "AA for text from a fifth of the way down: \(fifth)")
        #expect(top >= 3, "a glyph's 3:1 at the very top")
        for step in 0...10 {
            let ratio = Contrast.ratio(white, PrimaryButton.fill(at: Double(step) / 10))
            #expect(ratio >= 3, "3:1 all the way down: \(step) \(ratio)")
            if step >= 2 { #expect(ratio >= 4.5, "4.5:1 from a fifth down: \(step) \(ratio)") }
        }
        #expect(Self.near(Contrast.ratio(white, PrimaryButton.edge), 5.699))
    }

    @Test func pressedItReadsBetter() {
        let white = PrimaryButton.label
        let top = Contrast.brightness(PrimaryButton.top, PrimaryButton.pressed)
        let bottom = Contrast.brightness(PrimaryButton.bottom, PrimaryButton.pressed)
        #expect(top == DeckRGBA(0x95, 0x48, 0xDF) && bottom == DeckRGBA(0x7F, 0x2A, 0xCE))
        #expect(Self.near(Contrast.ratio(white, top), 4.918) && Self.near(Contrast.ratio(white, bottom), 6.720))
        #expect(Contrast.brightness(DeckRGBA(250, 250, 250, 0.5), 2) == DeckRGBA(255, 255, 255, 0.5), "clamped, alpha kept")
    }

    @Test func theButtonStandsOutOnBlackAndTheOldFillDidNot() {
        let black = DeckRGBA(0, 0, 0)
        #expect(Contrast.ratio(PrimaryButton.top, black) >= 3 && Contrast.ratio(PrimaryButton.bottom, black) >= 3,
                "the shape itself: 3:1 against the page")
        let accent = DeckRGBA(0xC0, 0x84, 0xFC)
        let old = Contrast.ratio(PrimaryButton.label, accent)
        #expect(Self.near(old, 2.642) && old < 3, "the tint under a white glyph: what James couldn't see")
    }
}
