import DeadwaxCore
import SwiftUI

/// A chip (dw.css's .chip and its colours - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"): 19 tall, a chip's corners, a few words - a format, a state ("Held", "Needs a look").
struct MacChip: View {
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
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
            // .chip: padding 0 7px
            .padding(.horizontal, 7)
            .frame(height: CGFloat(MacLook.chipHeight))
            .background(fill, in: MacCorners.chipShape)
            .overlay(MacCorners.chipShape.strokeBorder(edge, lineWidth: 1))
    }

    private var text: Color {
        switch tone {
        case .plain: return MacPalette.t2
        case .caution: return MacPalette.amberText
        case .good: return MacPalette.greenText
        case .marked: return MacPalette.acct
        case .bad: return MacPalette.redChipText
        }
    }

    private var fill: Color {
        switch tone {
        case .plain: return MacPalette.card
        case .caution: return MacPalette.amberFill
        case .good: return MacPalette.greenFill
        case .marked: return MacPalette.countFill
        case .bad: return MacPalette.redChipFill
        }
    }

    private var edge: Color {
        switch tone {
        case .plain: return MacPalette.line
        case .caution: return MacPalette.amberEdge
        case .good: return MacPalette.greenEdge
        case .marked: return MacPalette.countEdge
        case .bad: return MacPalette.redChipEdge
        }
    }
}

/// A count's badge (.count): a sidebar row's - Requests' downloads on their way, Needs a look's albums - in the mono
/// face, purple, at least 18 wide and 17 tall. VoiceOver hears the row's own words for it, never the badge alone.
struct MacCount: View {
    let count: String

    var body: some View {
        Text(count)
            .font(Typeface.Mac.mono(.count).weight(.semibold))
            .foregroundStyle(MacPalette.acct)
            .lineLimit(1)
            .fixedSize()
            // .count: padding 0 5px, min-width 18px
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .frame(height: CGFloat(MacLook.countHeight))
            .background(MacPalette.countFill, in: MacCorners.chipShape)
            .overlay(MacCorners.chipShape.strokeBorder(MacPalette.countEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
