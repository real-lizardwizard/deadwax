import Foundation

/// Last.fm's words on the artist page (lastfm.md 3.6) - the same on the iPhone and the Mac (DeviceWordsTests holds them
/// in words/iphone.json and words/mac.json). Slice A1's: Top Songs, its rows' lines, the credit, the two troubles of a
/// song you don't have, the listeners line and the foot line for whoever runs deadwax.
public enum LastfmWords {
    // MARK: Top Songs

    public static let topSongs = "Top Songs"
    public static let seeAll = "See All"
    /// The credit under the rows, opening the artist's page on Last.fm beside the app.
    public static let credit = "From Last.fm"
    /// A top song none of the page's albums has.
    public static let notInLibrary = "Not in your library"
    /// A song you don't have whose album MusicBrainz's song search didn't find - said on its row for the visit.
    public static let notFound = "Couldn't find its album on MusicBrainz."
    /// ...and MusicBrainz away (deadwax's 503).
    public static let away = "MusicBrainz isn't answering - try again in a few minutes."

    /// A song you have's line: "{album} · {year}", or "{album}" with no year (0 or none) - and with no album's name,
    /// the year alone.
    public static func albumLine(_ album: String?, year: Int?) -> String {
        let year = year.flatMap { (year: Int) -> String? in year > 0 ? String(year) : nil }
        return [album.flatMap { (name: String) -> String? in name.isEmpty ? nil : name }, year]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: listeners

    /// "2.3M listeners" under the name (lastfm.md 3.3) - ROUNDED DOWN, so it never says more than Last.fm did: exact
    /// under 1,000 ("1 listener", "850 listeners"); then thousands, millions and billions, one decimal under 10 of
    /// each and whole above ("2.3K", "230K", "2.3M", "23M", "1.2B"), never ".0". Nil for 0 or none: the line is blank.
    public static func listeners(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        if count == 1 { return "1 listener" }
        return "\(short(count)) listeners"
    }

    /// A count as the listeners line says it.
    static func short(_ count: Int) -> String {
        guard count >= 1_000 else { return String(count) }
        let (unit, letter): (Int, String) = count < 1_000_000 ? (1_000, "K")
            : count < 1_000_000_000 ? (1_000_000, "M") : (1_000_000_000, "B")
        let tenths = count / (unit / 10)
        guard tenths < 100 else { return "\(count / unit)\(letter)" }
        return tenths % 10 == 0 ? "\(tenths / 10)\(letter)" : "\(tenths / 10).\(tenths % 10)\(letter)"
    }

    // MARK: the foot line (whoever runs deadwax only)

    /// With no LASTFM_API_KEY.
    public static let footOff = "Top songs, similar artists and radio come from Last.fm - add a Last.fm API key in Server settings to see them."
    /// While Last.fm refuses the key.
    public static let footRefused = "Last.fm refused deadwax's API key - check LASTFM_API_KEY in Server settings. It's the API key, not the shared secret."
    /// The foot line's button: Server settings' Connections, where LASTFM_API_KEY is.
    public static let serverSettings = ServerSettings.title
}
