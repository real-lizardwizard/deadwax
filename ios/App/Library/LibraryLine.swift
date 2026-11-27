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

/// (R2b) The trailing end of the Library's quiet line: on Albums alone (LibraryLine.layouts), Grid and List, two bare
/// glyphs; then, where it shows, Yours | All, two words. James, 25 Nov: "lets put the grid/list next to yours/all".
///
/// (27 Nov - notes/ios.md "The Library's line underlines what is chosen (27 Nov)") James: "it's not immediately clear
/// which of 'yours' or 'all' is selected, and most others in that row"; shown three ways, "Yeah I like the underline".
/// Each is a choice (iLibrary's `.meta .opt`), in pairs (`.meta .pair`): grey, the line's third colour, until it is
/// chosen; chosen, white - a word semibold too - over the accent's 2 pt line, the switch's own (DWChosenLine). Purple
/// words in the line are only for what opens or goes somewhere: the order with its caret (PhoneMetaLink) and New
/// playlist…, the pages' own. The two of a pair are 6 apart with no hairline between Yours and All, and Grid and List's
/// pair 14 before Yours | All, on the line's own 6 (as iLibrary draws it). Nothing else in the line moved.
///
/// Grid and List are LibraryModel's layout, kept per device as it always was; a side is the page's LibrarySideChoice.
/// To VoiceOver: Grid and List, the shown one selected; Yours | All a group - "Your library or all music" - of the two
/// words, the shown one selected, as R2's switch read: the line under it is decoration, never the only cue. Each a
/// finger's target, reaching up and down to 44 (DWTarget), and each holding its half of the room between it and the
/// other of its pair, so every point of a pair takes a tap.
struct LibraryLineEnd: View {
    let page: LibraryPage
    let sides: LibrarySideChoice?

    @Environment(LibraryModel.self) private var library
    /// A glyph's ink on the phone (iLibrary's `.opt svg`), growing with the line's words.
    @ScaledMetric(relativeTo: Typeface.Phone.Size.meta.scaled.style) private var ink = CGFloat(PhoneLook.optInk)

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.metaGap)) {
            if LibraryLine.layouts(on: page) {
                HStack(spacing: 0) {
                    glyph(.grid, symbol: "square.grid.2x2", words: LibrarySwitchWords.grid, after: half)
                    glyph(.list, symbol: "list.bullet", words: LibrarySwitchWords.list, before: half)
                }
                // iLibrary's first .pair: margin-right 14px, before Yours | All
                .padding(.trailing, sides == nil ? 0 : CGFloat(PhoneLook.pairAfter))
            }
            if let sides {
                HStack(spacing: 0) {
                    word(.yours, sides, after: half)
                    word(.all, sides, before: half)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(LibrarySwitchWords.sidesLabel)
            }
        }
    }

    /// Half the room between the two of a pair (.pair's gap): each one's, inside its target.
    private var half: CGFloat {
        CGFloat(PhoneLook.pairGap) / 2
    }

    /// Grid or List (.opt holding its glyph): chosen while it is the layout. The glyph's weight is the same either way,
    /// as the drawing's stroke is.
    private func glyph(_ layout: LibraryLayout, symbol: String, words: String, before: CGFloat = 0,
                       after: CGFloat = 0) -> some View {
        let on = library.layout == layout
        return Button {
            library.layout = layout
        } label: {
            face(symbol)
                .modifier(LineChoice(on: on, before: before, after: after))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// (27 Nov's review) A glyph as iLibrary draws it (`.opt svg`): on the phone the symbol fitted to the drawing's ink
    /// (PhoneLook.optInk, 12.75 of its box's 17) and scaled with the line's words, so its box of 17 is what the line
    /// holds until the ink outgrows it - at xxxLarge, the line's cap, where the box grows with it rather than cut it. On
    /// the Mac's offline line (Downloaded, the phone's Albums page borrowed) the Mac's own 13 pt symbol, as it was.
    @ViewBuilder
    private func face(_ symbol: String) -> some View {
        if Platform.mac {
            Image(systemName: symbol)
                .font(Typeface.symbol(.body).weight(.medium))
                .lookSquare(PhoneLook.optGlyph)
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .font(Typeface.symbol(.body).weight(.medium))
                .frame(width: ink, height: ink)
                .lookSquare(PhoneLook.optGlyph)
        }
    }

    /// Yours or All (.opt holding its word): chosen while it is the side drawn - semibold then (.opt.on's 600).
    private func word(_ each: LibrarySide, _ sides: LibrarySideChoice, before: CGFloat = 0,
                      after: CGFloat = 0) -> some View {
        let on = each == sides.side
        return Button {
            sides.choose(each)
        } label: {
            Text(each.title)
                .font(Typeface.Phone.text(.meta).weight(on ? .semibold : .regular))
                .lineLimit(1)
                .modifier(LineChoice(on: on, before: before, after: after))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// (27 Nov) A choice in the line (`.meta .opt`), its words or glyph: in the third colour until it is chosen, then white
/// over the switch's lit line (`.opt.on`); its room either side (3), the line as wide as the two; 28 tall at least, the
/// line at its foot. Then the half of its pair's room it holds, and a finger's target over all of it.
private struct LineChoice: ViewModifier {
    let on: Bool
    let before: CGFloat
    let after: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(on ? DWPalette.text : DWPalette.t3)
            .padding(.horizontal, CGFloat(PhoneLook.optPadding))
            .lookHeight(PhoneLook.opt)
            .modifier(DWChosenLine(on: on))
            .padding(.leading, before)
            .padding(.trailing, after)
            .contentShape(DWTarget(face: Rectangle()))
    }
}
