import Foundation

/// (Last.fm, slice A4 - lastfm.md 3.9) About's words, at the foot of the artist and album pages - describe.ts's, the
/// same on the iPhone and the Mac (DeviceWordsTests holds them in words/iphone.json and words/mac.json).
public enum AboutWords {
    /// The block's heading, as the artist page's other sections have theirs.
    public static let heading = "About"
    /// The paragraph's button, opening it past its four lines - and closing it again.
    public static let more = "More"
    public static let less = "Less"
    /// (A4's review) The Mac album page's About folded to one row, where the page has no room for its four lines - and
    /// the button there, opening the whole words beside the page.
    public static let moreWords = "More\u{2026}"

    /// The link's words, by whose words they are: "From Wikipedia" (Wikipedia's CC BY-SA asks for the credit, so it is
    /// drawn with them), "More on Last.fm" for Last.fm's and Navidrome's - whose may be Deezer's, so it names only where
    /// it goes, never who wrote them.
    public static func source(_ source: AboutBlock.Source) -> String {
        switch source {
        case .wikipedia: return "From Wikipedia"
        case .lastfm: return "More on Last.fm"
        }
    }

    /// VoiceOver's one element: every word - the subtitle, the paragraph whole (the four lines hide only what is
    /// drawn) - and Wikipedia's credit when it is words, with no link to be an action of its own. The heading is its
    /// own element before it, a header as every section's on these pages (A4's review: the headings rotor stops there).
    public static func spoken(_ drawn: AboutBlock.Drawn) -> String {
        let plain = AboutBlock.credited(drawn.paragraph).flatMap { (credit: AboutBlock.Source) -> String? in
            AboutBlock.url(drawn.paragraph) == nil ? source(credit) : nil
        }
        return [drawn.subtitle, drawn.paragraph?.text, plain].compactMap { $0 }.joined(separator: ", ")
    }
}
