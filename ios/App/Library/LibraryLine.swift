import DeadwaxCore
import SwiftUI

/// (the redesign, slice R2b - notes/ios.md "The redesign, slice R2b: the Library's top, one row again") Yours | All as
/// a page's quiet line draws it: the side drawn, and choosing one - LibraryView's own `choose`, R2's (the side kept,
/// and on All the collection's Shuffle asked ahead). A page is handed one only where Yours | All shows
/// (LibraryPages.sides: with a library of your own, on your albums, while deadwax can be reached or All is chosen -
/// R2's review), nil elsewhere.
struct LibrarySideChoice {
    let side: LibrarySide
    let choose: (LibrarySide) -> Void
}

/// (R2b) The trailing end of the Library's quiet line (iLibrary's .meta .views and .meta .scope): on Albums alone
/// (LibraryLine.layouts), Grid and List, two bare glyphs; then, where it shows, Yours | All - two words with a hairline
/// between them. James, 25 Nov: "lets put the grid/list next to yours/all". Words and bare glyphs, nothing boxed, and
/// one rule for their colours (dw.css's: `.v` the accent and `.v.on` white; `.scope > b` white and semibold, the other
/// word a `.link`, the accent): white is where you are, purple what a tap goes to - the layout shown and the side
/// shown white, the other of each purple.
///
/// Grid and List are LibraryModel's layout, kept per device as it always was; a side is the page's LibrarySideChoice.
/// To VoiceOver: Grid and List, the shown one selected; Yours | All a group - "Your library or all music" - of the two
/// words, the shown one selected, as R2's switch read. Each a finger's target, reaching up and down to 44 (DWTarget),
/// and each word's over the room between it and the hairline.
struct LibraryLineEnd: View {
    let page: LibraryPage
    let sides: LibrarySideChoice?

    @Environment(LibraryModel.self) private var library
    /// The hairline between Yours and All (.scope > i's 12), grown with the line's words.
    @ScaledMetric(relativeTo: .footnote) private var rule = CGFloat(PhoneLook.sidesRule)

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.metaGap)) {
            if LibraryLine.layouts(on: page) {
                HStack(spacing: CGFloat(PhoneLook.metaGlyphGap)) {
                    glyph(.grid, symbol: "square.grid.2x2", words: LibrarySwitchWords.grid)
                    glyph(.list, symbol: "list.bullet", words: LibrarySwitchWords.list)
                }
                // .meta .views: margin-right 10px, before Yours | All
                .padding(.trailing, sides == nil ? 0 : CGFloat(PhoneLook.metaGlyphsAfter))
            }
            if let sides {
                HStack(spacing: 0) {
                    word(.yours, sides, after: CGFloat(PhoneLook.sidesGap))
                    DWRule(colour: DWPalette.metaRule, vertical: true)
                        .frame(height: rule)
                    word(.all, sides, before: CGFloat(PhoneLook.sidesGap))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(LibrarySwitchWords.sidesLabel)
            }
        }
    }

    /// Grid or List (.meta .v): white while it is the layout, purple while a tap would make it so.
    private func glyph(_ layout: LibraryLayout, symbol: String, words: String) -> some View {
        let on = library.layout == layout
        return Button {
            library.layout = layout
        } label: {
            Image(systemName: symbol)
                .font(Typeface.symbol(.body).weight(.medium))
                .foregroundStyle(on ? DWPalette.text : DWPalette.acc)
                .lookSquare(PhoneLook.metaGlyph)
                .contentShape(DWTarget(face: Rectangle()))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Yours or All (.scope > b, .scope > .link): white and semibold while it is the side drawn, purple while a tap
    /// would choose it. The room to the hairline (.scope's gap) is inside its target.
    private func word(_ each: LibrarySide, _ sides: LibrarySideChoice, before: CGFloat = 0,
                      after: CGFloat = 0) -> some View {
        let on = each == sides.side
        return Button {
            sides.choose(each)
        } label: {
            Text(each.title)
                .font(Typeface.Phone.text(.meta).weight(on ? .semibold : .regular))
                .foregroundStyle(on ? DWPalette.text : DWPalette.acc)
                .lineLimit(1)
                .padding(.leading, before)
                .padding(.trailing, after)
                .contentShape(DWTarget(face: Rectangle()))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
