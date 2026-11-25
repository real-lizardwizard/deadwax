import DeadwaxCore
import SwiftUI

/// A chip (dw.css's .chip and its colours - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice R1b: the
/// shared look, and the phone's pieces"; R1's MacChip, moved here for both): a few words - a format, a state ("Held",
/// "Needs a look") - 19 tall on the Mac, in a chip's corners (the Mac's 3).
///
/// (R1c - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") **On the phone no face**: its words in
/// its tone's colour at 13 medium, with a 6 pt dot of that colour before them where the tone means something (good,
/// caution, bad, marked - `.dw.ph .chip.green::before`); a plain chip is its words alone. 5 either side, as tall as its
/// words; the dot grows with them.
///
/// (R1c's review) **But a chip that `keepsFace`** - the Library's New mark (LibraryNewMark), a mark on a picture like
/// the count badge - keeps R1b's face on the phone too: 12.5 semibold in a square chip 22 tall at least, 7 either side,
/// its tone's fill and edge (dw.css's `.dw.ph .chip` before the flat block). The Mac's chip is faced whatever it says.
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
    /// (R1c's review) On the phone, R1b's face rather than the flat chip's dot and words: the New mark's alone.
    var keepsFace = false

    /// (R1c) The phone's dot, 6 at the standard size, growing with the chip's words.
    @ScaledMetric(relativeTo: .footnote) private var dot = CGFloat(DWFlat.dot)

    var body: some View {
        if Platform.mac || keepsFace {
            faced
        } else {
            flat
        }
    }

    /// (R1c) The phone's: the dot and the words, no face.
    private var flat: some View {
        HStack(spacing: CGFloat(DWFlat.dotGap)) {
            if tone != .plain {
                Circle()
                    .fill(text)
                    .frame(width: dot, height: dot)
                    .accessibilityHidden(true)
            }
            Text(words)
                .font(Typeface.Look.text(.chip).weight(.medium))
                .foregroundStyle(text)
                .lineLimit(1)
                .fixedSize()
        }
        // .dw.ph .chip: margin 0 5px, height auto
        .padding(.horizontal, CGFloat(DWFlat.chipSide))
        .lookHeight(DWLook.here.chipHeight)
    }

    /// The Mac's, R1's - and (R1c's review) the phone's New mark, R1b's: its type 12.5 there (`.facedChip`; a flat
    /// chip's is 13) and 22 tall at least (DWFlat's; DWLook's is a flat chip's, as tall as its words).
    private var faced: some View {
        Text(words)
            .font(Typeface.Look.text(Platform.mac ? .chip : .facedChip).weight(.semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
            // .chip: padding 0 7px, on both
            .padding(.horizontal, 7)
            .lookHeight(Platform.mac ? DWLook.here.chipHeight : DWFlat.facedChipHeight)
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
