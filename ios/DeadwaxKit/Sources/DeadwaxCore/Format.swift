import Foundation

/// Times and formats as the screens write them - the web app's ui/src/lib/format.ts (trackTime, formatDuration,
/// sharedFormat), lib/scrub.ts's clock and lib/titles.ts's long title, ported line for line, with the album page's
/// own lines (AlbumPage.tsx: the meta line, the footer, a row's number and artist) beside them. Every answer is held
/// to what the TypeScript itself answers: Tests/DeadwaxCoreTests/Fixtures/screens/format.json, written by
/// ios/scripts/export-screen-vectors.cjs (ui/test/iosscreens.sim.cjs keeps it current).
///
/// The numbers are written as JavaScript writes them (`JSNumber`): "Infinity:NaN" for a length of Infinity, never
/// Swift's "inf:nan" - About's own trackTime (About.swift) writes the latter, and agrees with this one on every finite
/// length; the two fold into this one when About is next touched.
public enum Format {
    /// A track's running time, "4:05" - "" for none, 0 or NaN (format.ts trackTime: Math.round, then whole minutes
    /// and the seconds left, two digits).
    public static func trackTime(_ seconds: Double?) -> String {
        guard let seconds, JSNumber.truthy(seconds) else { return "" }
        let whole = WebText.round(seconds)
        return "\(JSNumber.string((whole / 60).rounded(.down))):\(JSNumber.padTwo(JSNumber.string(whole.truncatingRemainder(dividingBy: 60))))"
    }

    /// An album's running time, coarse: "42 min", "1h 12m" - "" for none (format.ts formatDuration).
    public static func formatDuration(_ seconds: Double) -> String {
        guard JSNumber.truthy(seconds) else { return "" }
        let minutes = WebText.round(seconds / 60)
        if minutes < 60 { return "\(JSNumber.string(minutes)) min" }
        return "\(JSNumber.string((minutes / 60).rounded(.down)))h \(JSNumber.string(minutes.truncatingRemainder(dividingBy: 60)))m"
    }

    /// A position as Now Playing's clocks write it, "3:07" - whole seconds, floored, never below 0:00 (scrub.ts clock).
    public static func clock(_ seconds: Double) -> String {
        let whole = JSNumber.max(0, (JSNumber.truthy(seconds) ? seconds : 0).rounded(.down))
        return "\(JSNumber.string((whole / 60).rounded(.down))):\(JSNumber.padTwo(JSNumber.string(whole.truncatingRemainder(dividingBy: 60))))"
    }

    /// The one format every song of an album is in - "FLAC" - from Navidrome's `suffix`, uppercased; nil when they
    /// differ, one has none, or there are none (format.ts sharedFormat).
    public static func sharedFormat(_ songs: [Song]) -> String? {
        sharedFormat(suffixes: songs.map(\.suffix))
    }

    /// The same, from the suffixes alone.
    public static func sharedFormat(suffixes: [String?]) -> String? {
        let formats = WebText.unique(suffixes.map { ($0 ?? "").uppercased() })
        guard formats.count == 1, let only = formats.first, !only.isEmpty else { return nil }
        return only
    }

    /// The most letters a title has before it is drawn a step smaller (titles.ts LONG_TITLE).
    public static let longTitle = 60

    /// Whether an album's title is long enough to be drawn a step smaller: over `longTitle` letters once trimmed,
    /// counted as code points (titles.ts isLongTitle).
    public static func isLongTitle(_ title: String?) -> Bool {
        WebText.trim(title ?? "").unicodeScalars.count > longTitle
    }
}

/// The album page's own lines (ui/src/player/AlbumPage.tsx), as the page writes them.
public enum AlbumPageLines {
    /// The line under the artist: genre, year and the shared format, those there are, joined by " · ".
    public static func meta(genre: String?, year: Int?, format: String?) -> String {
        var parts: [String] = []
        if let genre, !genre.isEmpty { parts.append(genre) }
        if let year, year != 0 { parts.append(String(year)) }
        if let format, !format.isEmpty { parts.append(format) }
        return parts.joined(separator: DiscHeadings.dot)
    }

    /// The meta line of an album as Navidrome answered it, with its songs' shared format.
    public static func meta(_ album: Album?) -> String {
        meta(genre: album?.genre, year: album?.year, format: Format.sharedFormat(album?.song ?? []))
    }

    /// Every song's length added up, in order - a song with none counts 0.
    public static func total(_ songs: [Song]) -> Double {
        songs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    /// Under the songs: "12 songs, 48 min" - "1 song", and no time when there is none.
    public static func footer(_ songs: [Song]) -> String {
        let count = songs.count
        let total = total(songs)
        let time = JSNumber.truthy(total) ? ", \(Format.formatDuration(total))" : ""
        return "\(count) \(count == 1 ? "song" : "songs")\(time)"
    }

    /// A row's number: the song's track number, blank when it has none (the playing song's row draws its bars).
    public static func number(_ song: Song) -> String {
        song.track.map { String($0) } ?? ""
    }

    /// A row's artist line: the song's own artist, only when it has one and it isn't the album's (JS's `!==`).
    public static func artistShown(_ song: Song, albumArtist: String?) -> String? {
        guard let artist = song.artist, !artist.isEmpty else { return nil }
        if let albumArtist, WebText.same(artist, albumArtist) { return nil }
        return artist
    }

    /// Whether the page asks deadwax to measure the album's levels as it opens (player/levelling.ts warmAlbum): the
    /// player's Normalization isn't Off, and a song of it is a FLAC - deadwax levels only FLAC. Fire and forget.
    public static func warms(_ setting: Normalization, songs: [Song]?) -> Bool {
        setting != .off && (songs ?? []).contains { $0.isFlac }
    }

    /// A row's ••• button's name.
    public static func moreForSong(_ title: String) -> String { "More for \(title)" }
    /// The toolbar's ••• button's name.
    public static let moreForAlbum = "More for this album"
    /// The spinner's name until the songs are drawn.
    public static let loading = "Loading"
}

/// The few ways JavaScript writes and compares numbers that the screens' words lean on, kept to JavaScript's rules.
enum JSNumber {
    /// `String(n)` for what the screens write: whole numbers without a ".0", -0 as "0", and NaN and the infinities
    /// by JavaScript's names.
    static func string(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        return WebText.number(value)
    }

    /// A number as `||` and `?:` read it: anything but 0, -0 and NaN.
    static func truthy(_ value: Double) -> Bool {
        value != 0 && !value.isNaN
    }

    /// `String.prototype.padStart(2, '0')`.
    static func padTwo(_ text: String) -> String {
        text.utf16.count < 2 ? "0" + text : text
    }

    /// `Math.max(a, b)`: NaN when either is, and +0 over -0 - which Swift's `max` doesn't keep to.
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? b : a }
        return a > b ? a : b
    }

    /// `Math.min(a, b)`: NaN when either is, and -0 under +0.
    static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? a : b }
        return a < b ? a : b
    }
}
