import DeadwaxCore
import SwiftUI

/// A chip (dw.css's .chip and its colours - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice R1b: the
/// shared look, and the phone's pieces"; R1's MacChip, moved here for both): a few words - a format, a state ("Held",
/// "Needs a look") - 19 tall on the Mac, 22 at least on the phone, a chip's corners (the Mac's 3, the phone's square).
struct DWChip: View {
    /// What the chip says, by meaning - each dw.css's colour (named so, never by a colour: test_ios_mac_look.py reads a
    /// bare `.red` or `.green` as SwiftUI's own).
    enum Tone: Sendable {
        /// .chip: a fact (a format, a count)
        case plain
        /// .chip.amber: waiting, held, needs a look
        case caution
        /// .chip.green: done, in the library
        case good
        /// .chip.purple: the accent's - this one, chosen
        case marked
        /// .chip.red: failed, refused
        case bad
    }

    let words: String
    var tone: Tone = .plain

    var body: some View {
        Text(words)
            .font(Typeface.Look.text(.chip).weight(.semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
            // .chip: padding 0 7px, on both
            .padding(.horizontal, 7)
            .lookHeight(DWLook.here.chipHeight)
            .background(fill, in: DWCorners.chipShape)
            .overlay(DWCorners.chipShape.strokeBorder(edge, lineWidth: 1))
    }

    private var text: Color {
        switch tone {
        case .plain: return DWPalette.t2
        case .caution: return DWPalette.amberText
        case .good: return DWPalette.greenText
        case .marked: return DWPalette.acct
        case .bad: return DWPalette.redChipText
        }
    }

    private var fill: Color {
        switch tone {
        case .plain: return DWPalette.card
        case .caution: return DWPalette.amberFill
        case .good: return DWPalette.greenFill
        case .marked: return DWPalette.countFill
        case .bad: return DWPalette.redChipFill
        }
    }

    private var edge: Color {
        switch tone {
        case .plain: return DWPalette.line
        case .caution: return DWPalette.amberEdge
        case .good: return DWPalette.greenEdge
        case .marked: return DWPalette.countEdge
        case .bad: return DWPalette.redChipEdge
        }
    }
}

/// A count's badge (.count): a sidebar row's - Requests' downloads on their way, Needs a look's albums - in the mono
/// face, purple, at least 18 wide and 17 tall (on the phone 17 at least, growing with the text). VoiceOver hears the
/// row's own words for it, never the badge alone.
struct DWCount: View {
    let count: String

    var body: some View {
        Text(count)
            .font(Typeface.Look.mono(.count).weight(.semibold))
            .foregroundStyle(DWPalette.acct)
            .lineLimit(1)
            .fixedSize()
            // .count: padding 0 5px, min-width 18px
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .lookHeight(DWLook.here.countHeight)
            .background(DWPalette.countFill, in: DWCorners.chipShape)
            .overlay(DWCorners.chipShape.strokeBorder(DWPalette.countEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
