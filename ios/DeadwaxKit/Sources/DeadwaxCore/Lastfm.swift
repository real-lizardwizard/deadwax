import Foundation

// Last.fm on the artist page (deadwax-plans/lastfm.md 2.5, 2.7, 3.7; notes/ios.md "Last.fm, slice A1"): what deadwax
// says of Last.fm in /me, its answer for an artist (`GET /deadwax/lastfm/artist`), the key a top song meets a library
// song by, and the one host its links may go to. deadwax asks Last.fm itself and keeps its answers; the app only reads
// deadwax's.

/// What deadwax says of Last.fm (`/me`'s `lastfm`, server 2.1.36): `on` with a key Last.fm takes, `off` with no
/// LASTFM_API_KEY, `refused` while Last.fm refuses the key. `absent` is an older deadwax, with no `lastfm` in /me at
/// all, or a word this app doesn't know - a departure from the spec's "absent as off" (2.7): an older deadwax has no
/// LASTFM_API_KEY to point anyone at, so the page draws nothing of Last.fm's and no foot line either.
public enum LastfmState: Sendable, Equatable {
    case on, off, refused, absent

    /// `/me`'s word, read as carefully as anything read back: anything but the three is `absent`.
    public init(said: String?) {
        switch said {
        case "on": self = .on
        case "off": self = .off
        case "refused": self = .refused
        default: self = .absent
        }
    }
}

/// One of an artist's top songs as deadwax passes it on (src/lastfm.py `_kept_songs`): Last.fm's title as it wrote
/// it, its plays and listeners, and its page on Last.fm. Read leniently: only a title is needed - a song without one
/// (or with an empty one) is left out of the list.
public struct LastfmTrack: Decodable, Sendable, Equatable, Hashable {
    public let title: String
    public let playcount: Int?
    public let listeners: Int?
    /// Its page on Last.fm - only an https address on last.fm (LastfmLink), else nil.
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case title, playcount, listeners, url
    }

    public init(title: String, playcount: Int? = nil, listeners: Int? = nil, url: String? = nil) {
        self.title = title
        self.playcount = playcount
        self.listeners = listeners
        self.url = LastfmLink.checked(url)
    }

    /// No title, or one that is only white space: not a song (the list leaves it out).
    struct NoTitle: Error {}

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = fields.looseField(String.self, .title), !PyText.strip(title).isEmpty else { throw NoTitle() }
        self.title = title
        playcount = LastfmArtist.count(fields.looseField(Int.self, .playcount))
        listeners = LastfmArtist.count(fields.looseField(Int.self, .listeners))
        url = LastfmLink.checked(fields.looseField(String.self, .url))
    }
}

/// deadwax's answer for an artist (`GET /deadwax/lastfm/artist`, server 2.1.41 - lastfm.md 2.5): whether Last.fm is
/// there at all (`enabled`), whether a part couldn't be had just now (`unavailable` - kept a moment only), why not for
/// whoever runs deadwax (`why`), the artist's page, their listeners and their top songs (nil when they couldn't be had,
/// none when Last.fm lists none). Every field read leniently: a part absent or malformed is nil. `similar` and
/// `top_albums` are slice A2's.
public struct LastfmArtist: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let unavailable: Bool
    public let why: String?
    /// The artist's page on Last.fm (LastfmLink), the credit's link.
    public let url: String?
    public let listeners: Int?
    public let topSongs: [LastfmTrack]?

    enum CodingKeys: String, CodingKey {
        case enabled, unavailable, why, url, listeners
        case topSongs = "top_songs"
    }

    public init(enabled: Bool = true, unavailable: Bool = false, why: String? = nil, url: String? = nil,
                listeners: Int? = nil, topSongs: [LastfmTrack]? = nil) {
        self.enabled = enabled
        self.unavailable = unavailable
        self.why = why
        self.url = LastfmLink.checked(url)
        self.listeners = Self.count(listeners)
        self.topSongs = topSongs
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        // an answer that doesn't say it is enabled draws nothing; one that doesn't say it is whole is kept a moment only
        enabled = fields.looseField(Bool.self, .enabled) ?? false
        unavailable = fields.looseField(Bool.self, .unavailable) ?? true
        why = fields.looseField(String.self, .why)
        url = LastfmLink.checked(fields.looseField(String.self, .url))
        listeners = Self.count(fields.looseField(Int.self, .listeners))
        topSongs = fields.looseList(LastfmTrack.self, .topSongs)
    }

    /// A count as deadwax sends one (lastfm.py `count`): never negative.
    static func count(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

/// Where a Last.fm link may go (lastfm.py `lastfm_url`, server 2.1.41 - deadwax passes on no other): an https address
/// on last.fm or a host under it, printable ASCII with no space, `\` (a browser reads it as "/") or `@` (what is before
/// it is a user name, not the host) nor a `%` in its host, at most `most` letters - else nowhere, and the credit is
/// drawn as words alone.
public enum LastfmLink {
    /// lastfm.py URL_MAX.
    public static let most = 2048

    public static func checked(_ link: String?) -> String? {
        guard let link else { return nil }
        let text = PyText.strip(link)
        let letters = text.unicodeScalars
        guard text.hasPrefix("https://"), letters.count <= most,
              letters.allSatisfy({ (letter: Unicode.Scalar) -> Bool in (0x21...0x7E).contains(letter.value) }),
              !text.contains("\\"), !text.contains("@"),
              let written = URLComponents(string: text)?.percentEncodedHost, !written.contains("%") else { return nil }
        // the host as written: Python's urlparse decodes nothing, so a percent-encoded one ("evil.com%2elast.fm",
        // "%6Cast.fm") is no host on last.fm there, nor here (the review of A1)
        let host = written.lowercased()
        return host == "last.fm" || host.hasSuffix(".last.fm") ? text : nil
    }

    /// The link as an address to open, or nil.
    public static func url(_ link: String?) -> URL? {
        checked(link).flatMap { URL(string: $0) }
    }
}

/// The key a Last.fm top song meets a library song by (lastfm.py `match_key`, lastfm.md 2.4): a feature aside, a
/// feature tail and a dash take dropped (`strip`), then songs.ts titleKey (Core's SongTitle.key) - so "Let It Happen -
/// 2015 Remaster" and "Lost in Yesterday (feat. X)" are the songs you have as "Let It Happen" and "Lost in Yesterday",
/// while "Roads (Max Cooper remix)", "- Radio Edit" and "- Demo" stay songs of their own. Held to
/// tests/fixtures/lastfm/match-vectors.json through its copy in Fixtures/lastfm/ (LastfmMatchTests).
public enum LastfmMatch {
    public static func key(_ title: String?) -> String {
        SongTitle.key(strip(title))
    }

    /// lastfm.py `strip_title`, steps 1-3, matched as Python's `re` matches them (PyText): the title otherwise as it was.
    public static func strip(_ title: String?) -> String {
        var text = dropFeatureAsides(Array((title ?? "").unicodeScalars))
        if let tail = firstTail(text) { text = Array(text[..<tail]) }
        while let dash = dashes(text).last, takeWord(text, from: dash.end) {
            text = Array(text[..<dash.start])
        }
        return PyText.strip(String(String.UnicodeScalarView(text)))
    }

    /// Step 1, `FEATURE_ASIDE.sub("", …)`: `\s*[(\[]\s*(?:feat\.|feat\s|ft\.|ft\s|featuring\s|with\s)[^)\]]*[)\]]`,
    /// case-insensitive - every one, leftmost first.
    static func dropFeatureAsides(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var at = 0
        while at < s.count {
            if let end = featureAside(s, at) {
                at = end
            } else {
                out.append(s[at])
                at += 1
            }
        }
        return out
    }

    private static func featureAside(_ s: [Unicode.Scalar], _ from: Int) -> Int? {
        var at = PyText.spaces(s, from)
        guard at < s.count, s[at] == "(" || s[at] == "[" else { return nil }
        at = PyText.spaces(s, at + 1)
        let words: [(String, Bool)] = [("feat.", false), ("feat", true), ("ft.", false), ("ft", true),
                                       ("featuring", true), ("with", true)]
        guard words.contains(where: { (word: (String, Bool)) -> Bool in
            guard let end = PyText.word(s, at, word.0) else { return false }
            return !word.1 || (end < s.count && PyText.isSpace(s[end]))
        }) else { return nil }
        var close = at
        while close < s.count, s[close] != ")", s[close] != "]" { close += 1 }
        return close < s.count ? close + 1 : nil
    }

    /// Step 2: the first `\s+(?:feat\.|ft\.|featuring)\s` outside every bracket - where the title is cut.
    static func firstTail(_ s: [Unicode.Scalar]) -> Int? {
        var at = 0
        while at < s.count {
            if let end = featureTail(s, at) {
                if PyText.depth(s[..<at]) == 0 { return at }
                at = end
            } else {
                at += 1
            }
        }
        return nil
    }

    private static func featureTail(_ s: [Unicode.Scalar], _ from: Int) -> Int? {
        let at = PyText.spaces(s, from)
        guard at > from else { return nil }
        for word in ["feat.", "ft.", "featuring"] {
            if let end = PyText.word(s, at, word), end < s.count, PyText.isSpace(s[end]) { return end + 1 }
        }
        return nil
    }

    /// Step 3's dashes, `\s+[-–]\s+`, outside every bracket - each where it starts and where its spaces end.
    static func dashes(_ s: [Unicode.Scalar]) -> [(start: Int, end: Int)] {
        var found: [(start: Int, end: Int)] = []
        var at = 0
        while at < s.count {
            let dash = PyText.spaces(s, at)
            if dash > at, dash < s.count, s[dash] == "-" || s[dash].value == 0x2013 {
                let end = PyText.spaces(s, dash + 1)
                if end > dash + 1 {
                    if PyText.depth(s[..<at]) == 0 { found.append((at, end)) }
                    at = end
                    continue
                }
            }
            at += 1
        }
        return found
    }

    /// `TAKE_WORD.search(text[from:])`: `\b(?:live|remaster|remastered|mono|stereo)\b`, case-insensitive, anywhere in the
    /// rest - the dash's words name another take.
    static func takeWord(_ s: [Unicode.Scalar], from: Int) -> Bool {
        guard from < s.count else { return false }
        for at in from..<s.count where at == from || !PyText.isWord(s[at - 1]) {
            for word in ["live", "remaster", "remastered", "mono", "stereo"] {
                if let end = PyText.word(s, at, word), end == s.count || !PyText.isWord(s[end]) { return true }
            }
        }
        return false
    }
}

/// Python's `re` and `str`, as src/lastfm.py's patterns match a title: `\s` is str.isspace's 29 (the information
/// separators U+001C-U+001F and NEL among them, unlike JavaScript's), `\w` str.isalnum and `_`, IGNORECASE folds
/// a letter with its other case and Python's own extra folds (ſ for s, ı and İ for i, K for k) - each read off
/// Python 3 by hand (notes/ios.md "Last.fm, slice A1").
enum PyText {
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "_" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return scalar.properties.numericType != nil
        }
    }

    /// Past every white space from `from`.
    static func spaces(_ s: [Unicode.Scalar], _ from: Int) -> Int {
        var at = from
        while at < s.count, isSpace(s[at]) { at += 1 }
        return at
    }

    /// `word` (lowercase ASCII) at `at`, case-insensitive as Python's IGNORECASE: where it ends, or nil.
    static func word(_ s: [Unicode.Scalar], _ at: Int, _ word: String) -> Int? {
        var end = at
        for letter in word.unicodeScalars {
            guard end < s.count, same(s[end], letter) else { return nil }
            end += 1
        }
        return end
    }

    private static func same(_ scalar: Unicode.Scalar, _ letter: Unicode.Scalar) -> Bool {
        if scalar == letter { return true }
        if letter.value >= 0x61, letter.value <= 0x7A, scalar.value == letter.value - 0x20 { return true }
        switch (letter, scalar.value) {
        case ("s", 0x17F), ("i", 0x130), ("i", 0x131), ("k", 0x212A): return true
        default: return false
        }
    }

    /// lastfm.py `_depth`: how many brackets are open at the end.
    static func depth(_ s: ArraySlice<Unicode.Scalar>) -> Int {
        var depth = 0
        for scalar in s {
            if scalar == "(" || scalar == "[" {
                depth += 1
            } else if scalar == ")" || scalar == "]", depth > 0 {
                depth -= 1
            }
        }
        return depth
    }

    /// `str.strip()`: white space off both ends.
    static func strip(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars
        while let first = scalars.first, isSpace(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, isSpace(last) { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }
}
