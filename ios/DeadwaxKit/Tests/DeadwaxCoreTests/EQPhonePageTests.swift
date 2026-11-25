import Foundation
import Testing
@testable import DeadwaxCore

/// (R3b; R3's review) A filter's editor left with a field still typed in - Back, the sheet's strip, the sheet put down -
/// applies what was typed, as leaving the field does: in range, applied; out of range or nothing typed, nothing changes.
@Suite struct EQPhonePageTests {
    static let peak = EQFilter(id: 3, kind: .peak, fc: 1000, gain: 2, width: .q(1))

    @Test func whatWasTypedIsApplied() {
        #expect(EQEditorRules.leaving([.frequency: "250"], filter: Self.peak)
                == EQFilter(id: 3, kind: .peak, fc: 250, gain: 2, width: .q(1)))
        // the phone's decimal mark, and the minus a keyboard types
        #expect(EQEditorRules.leaving([.gain: "-3,5"], filter: Self.peak)?.gain == -3.5)
        #expect(EQEditorRules.leaving([.q: "0.7"], filter: Self.peak)?.width == .q(0.7))
        // the id kept: the same filter, changed
        #expect(EQEditorRules.leaving([.gain: "4"], filter: Self.peak)?.id == 3)
    }

    /// Out of range stays unapplied, as its field does: nothing changes, and nothing else typed is held back by it.
    @Test func outOfRangeChangesNothing() {
        #expect(EQEditorRules.leaving([.frequency: "30000"], filter: Self.peak) == nil)
        #expect(EQEditorRules.leaving([.gain: "abc"], filter: Self.peak) == nil)
        let both = EQEditorRules.leaving([.frequency: "30000", .gain: "5"], filter: Self.peak)
        #expect(both?.fc == 1000 && both?.gain == 5)
    }

    /// Nothing typed, or the value it already has: nothing to apply.
    @Test func nothingTypedNothingApplied() {
        #expect(EQEditorRules.leaving([:], filter: Self.peak) == nil)
        #expect(EQEditorRules.leaving([.frequency: "1000"], filter: Self.peak) == nil)
    }

    /// An empty Q where the type has a default is that default, as a field left empty is (3.8); a peak has none, so
    /// its empty Q is refused and nothing changes.
    @Test func anEmptyWidthIsTheTypesDefault() {
        let pass = EQFilter(id: 4, kind: .highPass, fc: 30, width: .q(0.5))
        let left = EQEditorRules.leaving([.q: ""], filter: pass)
        #expect(left != nil && left?.width == nil)
        #expect(EQEditorRules.leaving([.q: ""], filter: Self.peak) == nil)
    }

    /// (R3b's review) The output's button to VoiceOver: its name and value the page's output's (EQOutputButton), its
    /// hint AirPlay's double tap and where the music plays now - nothing of where when that isn't known.
    @Test func theOutputButtonsHint() {
        #expect(EQWords.Screen.outputHint(playsTo: "James's iPhone") == "Opens AirPlay. Playing on James's iPhone now.")
        #expect(EQWords.Screen.outputHint(playsTo: " AirPods Pro ") == "Opens AirPlay. Playing on AirPods Pro now.")
        #expect(EQWords.Screen.outputHint(playsTo: "") == "Opens AirPlay.")
        #expect(EQWords.Screen.outputHint(playsTo: "  ") == "Opens AirPlay.")
        #expect(EQWords.Screen.output == "Output" && EQWords.Screen.on == "EQ on")
    }
}
