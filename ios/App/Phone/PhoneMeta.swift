import DeadwaxCore
import SwiftUI

/// The meta line (dw.css's .meta - the redesign, slice R1b, notes/ios.md "The redesign, slice R1b: the shared look, and
/// the phone's pieces"): over a list, its count and what it's sorted by - a purple link opening the sort's menu
/// (PhoneMetaLink) - with what the page's line holds at its end. Since R2b (notes/ios.md "The redesign, slice R2b: the
/// Library's top, one row again") the Library's quiet line, as iLibrary, iArtists and iPlaylists draw it: 32 tall at
/// least, 16 in at either side, 6 apart, in the third colour, words and bare glyphs with nothing boxed - its end
/// LibraryLineEnd's Grid and List and Yours | All (since 27 Nov grey until chosen, the chosen one white over the
/// switch's lit line; purple words only for the order and New playlist…, which open something). Capped at xxxLarge, as
/// the bars are.
///
/// Where all of it doesn't fit on one line it gives way inside itself first (MetaLine - R2b's review): the count's noun
/// dropped ("2318 · Year, newest first"), VoiceOver still hearing it ("2318 albums"). Only where even that doesn't fit
/// does its end fold onto a line of its own under the words, at the trailing edge, the count in full again - and its
/// words wrap there only should even the short count need more than the line. Never a word cut. Each way is laid out
/// and measured as it is drawn - a ViewThatFits of MetaLine's ways, in their order - so the face and the text size
/// decide where it gives way.
struct PhoneMeta<Words: View, End: View>: View {
    /// The count's words in full - "140 albums", "12 of 140 albums" while Find finds; "" while there is none.
    let count: String
    /// Words follow the count (the order, New playlist…): a dot between them.
    let follows: Bool
    let words: Words
    let end: End

    /// The count, a dot, then `words` (the order, New playlist…); `trailing` at the line's end.
    init(count: String, @ViewBuilder then words: () -> Words, @ViewBuilder trailing end: () -> End) {
        self.count = count
        follows = true
        self.words = words()
        self.end = end()
    }

    /// The count alone (Songs': Navidrome's order is its one order); `trailing` at the line's end.
    init(count: String, @ViewBuilder trailing end: () -> End) where Words == EmptyView {
        self.count = count
        follows = false
        words = EmptyView()
        self.end = end()
    }

    var body: some View {
        // MetaLine.Fit's ways, in its order: the first whose width fits is drawn, the last where none does
        ViewThatFits(in: .horizontal) {
            line(.full)
            line(.short)
            line(.folded)
            line(.foldedShort)
        }
        .font(Typeface.Phone.text(.meta))
        .foregroundStyle(DWPalette.t3)
        // .meta: padding 0 16px (iLibrary's `padding-right: 16px` over .meta's 10)
        .padding(.leading, CGFloat(PhoneLook.metaLead))
        .padding(.trailing, CGFloat(PhoneLook.metaTrail))
        .lookHeight(PhoneLook.meta)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The line drawn `fit`'s way: its count in full or without its noun - read in full either way - then the words,
    /// and its end on the line or folded under it.
    private func line(_ fit: MetaLine.Fit) -> some View {
        PhoneMetaLine(folded: fit.folded) {
            HStack(spacing: CGFloat(PhoneLook.metaGap)) {
                if !count.isEmpty {
                    Text(MetaLine.count(count, fit))
                        .accessibilityLabel(count)
                    if follows {
                        Text(verbatim: "·")
                            .accessibilityHidden(true)
                    }
                }
                words
            }
            HStack(spacing: CGFloat(PhoneLook.metaGap)) {
                end
            }
        }
    }
}

/// (R2b) The meta line's words and its end laid out one way (MetaLine.place - on one line, or `folded`): its width
/// asked (nil), the way's own width at its two ends' own (MetaLine.width) - what PhoneMeta's ViewThatFits measures; given
/// one, the words in the room they are given (MetaLine.wordsRoom) and each end where Core puts it.
private struct PhoneMetaLine: Layout {
    let folded: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let line = placed(proposal.width, subviews) else { return .zero }
        return CGSize(width: line.width, height: line.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let line = placed(bounds.width, subviews) else { return }
        subviews[0].lookPlace(line.words, in: bounds)
        subviews[1].lookPlace(line.end, in: bounds)
    }

    /// The words and the end measured and placed in `width` (their own way's width, where none is given).
    private func placed(_ width: CGFloat?, _ subviews: Subviews) -> MetaLine.Placed? {
        guard subviews.count == 2 else {
            assertionFailure("PhoneMetaLine lays out the line's words and its end, not \(subviews.count) views")
            return nil
        }
        let ideal = LookSize(subviews[0].sizeThatFits(.unspecified))
        let end = LookSize(subviews[1].sizeThatFits(.unspecified))
        let room = width.map { (given: CGFloat) -> Double in Double(given) }
            ?? MetaLine.width(words: ideal.width, end: end.width, folded: folded)
        let given = MetaLine.wordsRoom(room, end: end.width, folded: folded)
        let words = LookSize(subviews[0].sizeThatFits(ProposedViewSize(width: CGFloat(given), height: nil)))
        return MetaLine.place(words: words, end: end, room: room, folded: folded)
    }
}

/// The meta line's link (.meta .link): its words in the accent with the caret after them, 5 apart - a Menu's label (the
/// sort's), the menu iOS's own. A finger's target round it.
struct PhoneMetaLink: View {
    let words: String

    var body: some View {
        HStack(spacing: CGFloat(PhoneLook.linkGap)) {
            Text(words)
            DWCaret(colour: DWPalette.acc)
        }
        .font(Typeface.Phone.text(.meta))
        .foregroundStyle(DWPalette.acc)
        .contentShape(DWTarget(face: Rectangle()))
    }
}
