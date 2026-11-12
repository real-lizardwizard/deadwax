import Foundation
import Testing
@testable import DeadwaxCore

/// The turntable's colours (TurntablePalette.swift) against theme.css's tokens (Fixtures/deck/tokens.json, the spec's
/// 2.14): a web token changed fails here rather than drifting.
@Suite struct TurntablePaletteTests {
    @Test func everyColourIsItsTokens() throws {
        let fixture = try DeckFixtures.json("tokens.json")
        for entry in TurntablePalette.tokens {
            let colours = fixture["tokens"]?[entry.token]?["colours"]?.array ?? []
            guard entry.index < colours.count, let rgba = colours[entry.index].array, rgba.count == 4 else {
                Issue.record("\(entry.name): \(entry.token) names no colour \(entry.index)")
                continue
            }
            let want = DeckRGBA(rgba[0].int ?? -1, rgba[1].int ?? -1, rgba[2].int ?? -1, rgba[3].double ?? -1)
            #expect(entry.colour == want, "\(entry.name) is \(entry.colour), \(entry.token) \(want)")
        }
    }

    @Test func theSecondaryButtonsPressIsItsFaceTurnedOver() throws {
        //? the web's active gradient is its rest one upside down; the Palette draws it from the same two colours
        let fixture = try DeckFixtures.json("tokens.json")
        let rest = fixture["tokens"]?["--dw-secondary-bg"]?["colours"]?.array ?? []
        let pressed = fixture["tokens"]?["--dw-secondary-bg-active"]?["colours"]?.array ?? []
        #expect(rest.count == 2 && pressed.count == 2 && rest[0] == pressed[1] && rest[1] == pressed[0])
    }
}
