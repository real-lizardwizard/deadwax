import DeadwaxCore
import SwiftUI

/// (Last.fm, slice A4 - deadwax-plans/lastfm.md 3.9; notes/ios.md "Last.fm, slice A4") About's sizes: the paragraph's
/// four lines are Core's (AboutBlock.lines); the phone's room above the section is Similar Artists' (20), with 6
/// between its parts and 16 between More and the link; the Mac's measure is the drawings' paragraph's (Artist.dc.html's
/// 640). (A4's review) The Mac album page's About folded to one row stands 12 under Properties, its heading and More…
/// 12 apart; the whole words beside that page (AboutWhole) are 440 wide, 16 in from their edge, and scroll past 360.
enum AboutDrawn {
    static let above: CGFloat = 20
    static let gap: CGFloat = 6
    static let footGap: CGFloat = 16
    static let macMeasure: CGFloat = 640
    static let macRowAbove: CGFloat = 12
    static let macRowGap: CGFloat = 12
    static let wholeWidth: CGFloat = 440
    static let wholeEdge: CGFloat = 16
    static let wholeMost: CGFloat = 360
}

/// The faces About is drawn in - the phone's (`phone`, here) or the Mac's (its pages' own, in Typeface's Mac sizes):
/// the subtitle's, the paragraph's and the link's; the gap between them; the link's least height (a finger's target on
/// the phone, none on the Mac); the longest a line runs (nil: the page's width); and (A4's review) the foot's least
/// height when it is ALWAYS drawn under the words - the Mac album page's, so the block's height never waits on whether
/// they run past their lines - nil: drawn only with More or a credit in it.
struct AboutFaces {
    let subtitle: Font
    let words: Font
    let credit: Font
    let gap: CGFloat
    let target: CGFloat
    let measure: CGFloat?
    var footLeast: CGFloat? = nil

    /// The phone's: the subtitle and the link the small words (13), the paragraph the subheadline's 15 - the web's -
    /// each growing with the text; the link's target 44 tall at least.
    static var phone: AboutFaces {
        AboutFaces(subtitle: Typeface.Phone.text(.small), words: Typeface.subheadline, credit: Typeface.Phone.text(.small),
                   gap: AboutDrawn.gap, target: CGFloat(DWLook.here.target), measure: nil)
    }
}

/// About on the phone's artist and album pages, at their foot: the heading as the artist page's other sections have
/// theirs (ArtistSectionHead), then the words - flat, on the page itself, no box. The Mac's pages draw the same words
/// (AboutBlockView) in their own section's style.
struct AboutSection: View {
    let drawn: AboutBlock.Drawn

    var body: some View {
        AboutBlockView(drawn: drawn, faces: .phone) { (words: AboutWordsElement) in
            VStack(alignment: .leading, spacing: 0) {
                ArtistSectionHead(words: AboutWords.heading) { EmptyView() }
                words
            }
        }
        .padding(.top, AboutDrawn.above)
    }
}

/// The words as VoiceOver's one element (AboutSpoken), what a page's `frame` lays under its own heading.
typealias AboutWordsElement = ModifiedContent<AboutWordsView, AboutSpoken>

/// About as both devices draw it (the web's Description.tsx): `frame` lays the heading and the words in the page's own
/// section - the words ONE VoiceOver element (AboutSpoken), the heading outside it, its own element, a header as every
/// section's on these pages (A4's review: so the headings rotor stops at About). More opens the words past their lines
/// in place and Less closes them - opened is for THESE words: the block drawn for another artist or album starts closed
/// again - or, with `opens` (the Mac album page's), More does that instead and the words never grow where they stand.
struct AboutBlockView<Frame: View>: View {
    let drawn: AboutBlock.Drawn
    let faces: AboutFaces
    /// (A4's review) What More does in place of opening the words where they stand - the Mac album page's popover. Nil:
    /// opened in place.
    var opens: (() -> Void)? = nil
    @ViewBuilder let frame: (AboutWordsElement) -> Frame

    /// The words opened past their lines - for these words only.
    @State private var openFor: String?
    /// The words run past their lines, as last measured while closed.
    @State private var overflows = false

    var body: some View {
        let text = drawn.paragraph?.text
        let open = opens == nil && text != nil && openFor == text
        let toggle: () -> Void = opens ?? { () -> Void in openFor = open ? nil : text }
        let more: String? = overflows || open ? (open ? AboutWords.less : AboutWords.more) : nil
        frame(AboutWordsView(drawn: drawn, faces: faces, open: open, overflows: $overflows, toggle: toggle)
            .modifier(AboutSpoken(drawn: drawn, more: more, toggle: toggle)))
            .onChange(of: text) { (_: String?, _: String?) -> Void in openFor = nil }
    }
}

/// About's words as ONE VoiceOver element: every word (AboutWords.spoken - the four lines hide only what is drawn),
/// More or Less as an action while the words run past their lines (`more`, nil: neither), and the link as an action
/// named as it is ("More on Last.fm", "From Wikipedia"). Never the heading: that is the page's, outside it.
struct AboutSpoken: ViewModifier {
    let drawn: AboutBlock.Drawn
    let more: String?
    let toggle: () -> Void

    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        let link = AboutBlock.url(drawn.paragraph)
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AboutWords.spoken(drawn))
            .accessibilityActions {
                if let more {
                    Button(more, action: toggle)
                }
                if let link, let paragraph = drawn.paragraph {
                    Button(AboutWords.source(paragraph.source)) { openURL(link) }
                }
            }
    }
}

/// About's words, drawn in `faces`: the subtitle (quiet, in the third colour), the paragraph in the second at its four
/// lines - or whole, opened - and under it More / Less (while the words run past their lines) and the credit, beside
/// each other, stacked at the accessibility sizes (the credit up to three lines). Whether the words run past their
/// lines is measured: the four lines against the whole, laid out unseen at the same width - again as the width or the
/// text size changes; while open, the last measure stands.
struct AboutWordsView: View {
    let drawn: AboutBlock.Drawn
    let faces: AboutFaces
    let open: Bool
    @Binding var overflows: Bool
    let toggle: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The four lines' height, and the whole's at the same width - 0 until measured.
    @State private var clamped: CGFloat = 0
    @State private var whole: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: faces.gap) {
            if let subtitle = drawn.subtitle {
                Text(subtitle)
                    .font(faces.subtitle)
                    .foregroundStyle(DWPalette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let paragraph = drawn.paragraph {
                words(paragraph.text)
                foot()
            }
        }
        .frame(maxWidth: faces.measure ?? .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func words(_ text: String) -> some View {
        if open {
            paragraph(text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            paragraph(text)
                .lineLimit(AboutBlock.lines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { (drawn: GeometryProxy) -> CGFloat in
                    drawn.size.height
                } action: { (height: CGFloat) -> Void in
                    clamped = height
                    measure()
                }
                .background(alignment: .topLeading) {
                    paragraph(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { (laid: GeometryProxy) -> CGFloat in
                            laid.size.height
                        } action: { (height: CGFloat) -> Void in
                            whole = height
                            measure()
                        }
                }
        }
    }

    private func paragraph(_ text: String) -> Text {
        Text(text)
            .font(faces.words)
            .foregroundStyle(DWPalette.t2)
    }

    @ViewBuilder private func foot() -> some View {
        let more = overflows || open
        if let least = faces.footLeast {
            footParts(more: more)
                .frame(minHeight: least)
        } else if more || AboutBlock.credited(drawn.paragraph) != nil {
            footParts(more: more)
        }
    }

    /// More / Less and the credit, beside each other - stacked at the accessibility sizes.
    @ViewBuilder private func footParts(more: Bool) -> some View {
        let parts = Group {
            if more {
                Button(open ? AboutWords.less : AboutWords.more, action: toggle)
                    .buttonStyle(DWButtonStyle(size: .small))
            }
            AboutCredit(drawn: drawn, faces: faces)
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) { parts }
        } else {
            HStack(alignment: .center, spacing: AboutDrawn.footGap) { parts }
        }
    }

    /// Whether the words run past their lines: the whole taller than the four lines (a point's give for rounding).
    private func measure() {
        guard !open, clamped > 0, whole > 0 else { return }
        let runs = whole > clamped + 1
        if runs != overflows { overflows = runs }
    }
}

/// Whose words they are (AboutBlock.credited): a Link to the page they came from, opening beside the app in the
/// system's browser - Safari on the phone, the Mac's own - only to its own host (AboutBlock.url), so the player plays
/// on; borderless, so in the phone album page's List row it is its own target, never the whole row's. (A4's review)
/// Wikipedia's with no link that goes where it says: its credit as plain words, as LastfmCredit draws its own - the CC
/// BY-SA credit never left out. Nothing for Last.fm's with no link (Navidrome's words come as `lastfm` too).
struct AboutCredit: View {
    let drawn: AboutBlock.Drawn
    let faces: AboutFaces

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let link = AboutBlock.url(drawn.paragraph)
        if let link, let paragraph = drawn.paragraph {
            Link(AboutWords.source(paragraph.source), destination: link)
                .font(faces.credit)
                .foregroundStyle(DWPalette.acc)
                .buttonStyle(.borderless)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: faces.target)
                .contentShape(Rectangle())
        } else if let credit = AboutBlock.credited(drawn.paragraph) {
            Text(AboutWords.source(credit))
                .font(faces.credit)
                .foregroundStyle(DWPalette.t2)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// (A4's review) About's whole words beside the Mac album page (its popover, MacAlbumPage's About): the subtitle, the
/// paragraph whole and the credit, in the page's faces, at a reading measure - scrolling inside past
/// AboutDrawn.wholeMost, the page under it never moved.
struct AboutWhole: View {
    let drawn: AboutBlock.Drawn
    let faces: AboutFaces

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: faces.gap) {
                if let subtitle = drawn.subtitle {
                    Text(subtitle)
                        .font(faces.subtitle)
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let paragraph = drawn.paragraph {
                    Text(paragraph.text)
                        .font(faces.words)
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    AboutCredit(drawn: drawn, faces: faces)
                }
            }
            .padding(AboutDrawn.wholeEdge)
            .frame(width: AboutDrawn.wholeWidth, alignment: .leading)
        }
        .frame(maxHeight: AboutDrawn.wholeMost)
        .fixedSize()
        .presentationBackground(DWPalette.panel)
    }
}
