import Foundation

// (Last.fm, slice A4 - deadwax-plans/lastfm.md 3.9; notes/ios.md "Last.fm, slice A4") About, at the foot of the artist
// page and the album page: deadwax's description of the artist or the album (`GET /deadwax/describe/artist|album`,
// src/routes/describe.py - Last.fm's words first since 2.1.42, else Wikipedia's, else Navidrome's), with Wikidata's
// one-line subtitle. The web's lib/describe.ts and app/useDescription.ts ported (ui/test/describe.sim.cjs pins those):
// what is asked, what is drawn of an answer, the link only to its own host, what the session keeps and how long, and
// which answer a page draws. Info's About (About.swift) is another thing: Info > About, the album's facts.

/// deadwax's description of an artist or an album (src/descriptions.py NONE's shape: every field null when there is
/// none) - read loosely, as the Last.fm answers are: a field missing or of another type is nil, and an answer that
/// doesn't say it is the whole story is taken as not (`unavailable`), so it is kept a minute only.
public struct DescribeAnswer: Decodable, Sendable, Equatable {
    public let text: String?
    /// "wikipedia" or "lastfm" (Last.fm's words, and Navidrome's - whose may be Deezer's: the link names only where
    /// it goes).
    public let source: String?
    public let url: String?
    /// Wikidata's one-line description ("English band", "1994 studio album by Portishead").
    public let subtitle: String?
    /// A source couldn't be asked just now: what came is all there is for the moment.
    public let unavailable: Bool

    enum CodingKeys: String, CodingKey {
        case text, source, url, subtitle, unavailable
    }

    public init(text: String? = nil, source: String? = nil, url: String? = nil, subtitle: String? = nil,
                unavailable: Bool = false) {
        self.text = text
        self.source = source
        self.url = url
        self.subtitle = subtitle
        self.unavailable = unavailable
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        text = fields.looseField(String.self, .text)
        source = fields.looseField(String.self, .source)
        url = fields.looseField(String.self, .url)
        subtitle = fields.looseField(String.self, .subtitle)
        unavailable = fields.looseField(Bool.self, .unavailable) ?? true
    }
}

public enum AboutBlock {
    /// The paragraph's lines before More (lastfm.md 3.9) - lines of its own text size, so they grow with it.
    public static let lines = 4

    public enum Kind: String, Sendable, Equatable {
        case artist, album
    }

    /// Whose words a paragraph is - what its link says (AboutWords.source).
    public enum Source: String, Sendable, Equatable {
        case wikipedia, lastfm
    }

    /// The paragraph to draw: its words as deadwax sent them (text, never markup), whose, and its link - nil when
    /// there is none, or it wouldn't go where it says.
    public struct Paragraph: Sendable, Equatable {
        public let text: String
        public let source: Source
        public let url: String?

        public init(text: String, source: Source, url: String?) {
            self.text = text
            self.source = source
            self.url = url
        }
    }

    /// What the block draws under its heading: the subtitle, the paragraph - at least one of them.
    public struct Drawn: Sendable, Equatable {
        public let paragraph: Paragraph?
        public let subtitle: String?

        public init(paragraph: Paragraph?, subtitle: String?) {
            self.paragraph = paragraph
            self.subtitle = subtitle
        }
    }

    // MARK: what is drawn of an answer

    /// deadwax's answer as something to draw (describe.ts descriptionOf), or nil: no words and no subtitle - then
    /// there is no block. A paragraph needs a source this knows; its link only goes where it says.
    public static func of(_ answer: DescribeAnswer?) -> Drawn? {
        let text = line(answer?.text)
        var paragraph: Paragraph?
        if let text, let source = answer?.source.flatMap(Source.init(rawValue:)) {
            paragraph = Paragraph(text: text, source: source, url: link(source, answer?.url))
        }
        let subtitle = line(answer?.subtitle)
        return paragraph != nil || subtitle != nil ? Drawn(paragraph: paragraph, subtitle: subtitle) : nil
    }

    /// One line of words, trimmed as the web's `trim()` does, or nil.
    static func line(_ value: String?) -> String? {
        let text = JSText.trim(value ?? "")
        return text.isEmpty ? nil : text
    }

    /// The longest link followed - LastfmLink's (src/lastfm.py URL_MAX).
    public static let linkMost = LastfmLink.most

    /// A paragraph's link, only to its own host (describe.ts linkFits): Last.fm's an https address on last.fm or a
    /// host under it (LastfmLink, the credit's one rule); Wikipedia's an https address on en.wikipedia.org itself -
    /// printable ASCII only, no `\`, the host as written (a percent in it refused) and no one's name or password
    /// before it (A4's review: a title may hold an `@` - "https://en.wikipedia.org/wiki/@Home" - and the exact host
    /// already stops "https://en.wikipedia.org@evil.com"). Nil otherwise: the paragraph is drawn without it.
    public static func link(_ source: Source, _ url: String?) -> String? {
        switch source {
        case .lastfm:
            return LastfmLink.checked(url)
        case .wikipedia:
            guard let url else { return nil }
            let text = PyText.strip(url)
            let letters = text.unicodeScalars
            guard text.hasPrefix("https://"), letters.count <= linkMost,
                  letters.allSatisfy({ (letter: Unicode.Scalar) -> Bool in (0x21...0x7E).contains(letter.value) }),
                  !text.contains("\\"), let parts = URLComponents(string: text), parts.user == nil,
                  parts.password == nil, let written = parts.percentEncodedHost, !written.contains("%") else {
                return nil
            }
            return written.lowercased() == "en.wikipedia.org" ? text : nil
        }
    }

    /// (A4's review) Whose credit the paragraph is drawn with: Wikipedia's ALWAYS - its CC BY-SA asks for it, so
    /// with no link that goes where it says it is drawn as plain words (as LastfmCredit draws its own) - Last.fm's
    /// only with its link: the route says `lastfm` of Navidrome's words too, which may be Deezer's, so "More on
    /// Last.fm" with nowhere to go would credit the wrong one. Nil for no paragraph.
    public static func credited(_ paragraph: Paragraph?) -> Source? {
        guard let paragraph else { return nil }
        return paragraph.source == .wikipedia || url(paragraph) != nil ? paragraph.source : nil
    }

    /// The paragraph's link as an address to open, or nil.
    public static func url(_ paragraph: Paragraph?) -> URL? {
        guard let paragraph else { return nil }
        return link(paragraph.source, paragraph.url).flatMap { URL(string: $0) }
    }

    // MARK: what is asked

    /// The route's longest Navidrome id (src/routes/describe.py ID_MAX).
    public static let idMost = 256

    /// What a page asks by (describe.ts describeKey): the MusicBrainz id - an artist's, an album's release group's - as
    /// the route takes one (MBID.of: lowercase), and/or Navidrome's id, trimmed, 1 to `idMost` letters. Nil with
    /// neither: nothing is asked, and there is no block.
    public struct Ask: Sendable, Equatable, Hashable {
        public let kind: Kind
        public let mbid: String?
        public let navidromeId: String?

        public init?(kind: Kind, mbid: String?, navidromeId: String?) {
            let mbid = MBID.of(mbid)
            let trimmed = JSText.trim(navidromeId ?? "")
            let id = trimmed.isEmpty || trimmed.unicodeScalars.count > AboutBlock.idMost ? nil : trimmed
            guard mbid != nil || id != nil else { return nil }
            self.kind = kind
            self.mbid = mbid
            self.navidromeId = id
        }

        /// What the session keeps the answer under (an id has no `|`'s place: an MBID has none, and Navidrome's comes
        /// last).
        public var key: String { "\(kind.rawValue)|\(mbid ?? "")|\(navidromeId ?? "")" }

        /// The route's query: only what there is, in the route's names.
        public var query: [(String, String)] {
            var query: [(String, String)] = []
            if let mbid { query.append(("mbid", mbid)) }
            if let navidromeId { query.append(("navidrome_id", navidromeId)) }
            return query
        }
    }

    /// Where a page's question stands: who it is isn't settled yet (`unsettled` - nothing asked, but what the page was
    /// answered last is drawn), there is nothing to ask by (`nothing` - no block), or the question.
    public enum Question: Sendable, Equatable {
        case unsettled
        case nothing
        case ask(Ask)

        public var key: String? {
            if case .ask(let ask) = self { return ask.key }
            return nil
        }

        /// The question as one string, for the page's task: a new one asks again.
        public var token: String {
            switch self {
            case .unsettled: return "?"
            case .nothing: return "-"
            case .ask(let ask): return ask.key
            }
        }
    }

    /// The artist page's question (the web's ArtistPage: once Navidrome's artist and their facts are in): none for an
    /// artist gone from Navidrome; unsettled until their answer is in hand, while who they are on MusicBrainz may still
    /// come from the library's folders (`indexKnown`, or `waited` - SearchPacing.ownedWaitMs, as their albums wait),
    /// and, once that is known, until MusicBrainz has said who they are (`factsSettled`: answered or not) - the one
    /// lookup deadwax's Wikipedia side makes too, then asked once.
    public static func artist(answered: Bool, gone: Bool, navidromeId: String, mbid: String?, indexKnown: Bool,
                              waited: Bool, factsSettled: Bool) -> Question {
        if gone { return .nothing }
        guard answered else { return .unsettled }
        let mbid = MBID.of(mbid)
        if mbid == nil && !indexKnown && !waited { return .unsettled }
        if mbid != nil && !factsSettled { return .unsettled }
        return Ask(kind: .artist, mbid: mbid, navidromeId: navidromeId).map(Question.ask) ?? .nothing
    }

    /// The album page's question (lastfm.md 3.9): its release group and Navidrome's id. The group is the id bridge's
    /// (`storeGroup`, StoreAlbum.releaseGroupMbid - the web's own source) when the page has it; else what the library's
    /// folders of its pressing say (OwnedIndex.forRelease, the first that names one). None for an album gone from
    /// Navidrome; unsettled until the album is in hand, and - with a pressing to look up and no group from the bridge
    /// - while no word of the library's folders is in hand: `/library/owned` still out, or not yet asked
    /// (`ownedSettled`: it has answered, or failed, since the page asked). Only then is it asked by Navidrome's id
    /// alone (A4's review: never Navidrome's words drawn, then replaced by Last.fm's as the folders land). With
    /// neither id, nothing is asked.
    public static func album(answered: Bool, gone: Bool, navidromeId: String?, release: String?, storeGroup: String?,
                             index: OwnedIndex?, ownedSettled: Bool) -> Question {
        if gone { return .nothing }
        guard answered else { return .unsettled }
        if let group = MBID.of(storeGroup) {
            return Ask(kind: .album, mbid: group, navidromeId: navidromeId).map(Question.ask) ?? .nothing
        }
        let release = MBID.of(release)
        if release != nil && index == nil && !ownedSettled { return .unsettled }
        let group = OwnedIndex.forRelease(index, release).lazy
            .compactMap { (album: OwnedAlbum) -> String? in MBID.of(album.releaseGroupMbid) }.first
        return Ask(kind: .album, mbid: group, navidromeId: navidromeId).map(Question.ask) ?? .nothing
    }

    // MARK: the session's answers

    /// How many answers the session keeps (describe.ts DESCRIPTIONS_KEPT) - and how many pages' last questions.
    public static let kept = 200
    /// How long an answer that isn't the whole story is kept, in ms (UNSURE_KEPT_MS): deadwax said a source couldn't be
    /// asked, or deadwax couldn't be asked at all - long enough for Back, short enough to ask again soon.
    public static let unsureKeptMs: Double = 60_000

    /// The session's answers (describe.ts keptDescription and keepDescription): a description, or none, by what was
    /// asked (Ask.key) - the `kept` most recently used, the oldest going; one `unsure` only `unsureKeptMs`. And the
    /// question each page last asked (rememberPageKey), so a page come back to while who it is is still being settled
    /// draws what it was answered.
    public struct Kept: Sendable {
        private var entries: [String: (found: Drawn?, until: Double?)] = [:]
        private var order: [String] = []
        private var pages: [String: String] = [:]
        private var pageOrder: [String] = []

        public init() {}

        /// What is kept for `key`: `.some(drawn)` - a description, or `.some(nil)` for none - or nil when nothing is
        /// (or what was kept a moment has had it). A read makes it the most recently used.
        public mutating func found(_ key: String, now: Double) -> Drawn?? {
            guard let entry = entries[key] else { return nil }
            order.removeAll { $0 == key }
            if let until = entry.until, now >= until {
                entries[key] = nil
                return nil
            }
            order.append(key)
            return .some(entry.found)
        }

        /// An answer kept - for the session, or (`unsure`) for `unsureKeptMs`.
        public mutating func keep(_ key: String, _ found: Drawn?, unsure: Bool, now: Double) {
            entries[key] = (found, unsure ? now + AboutBlock.unsureKeptMs : nil)
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > AboutBlock.kept {
                entries[order.removeFirst()] = nil
            }
        }

        /// The question a page asks, remembered for the session (the `kept` most recent pages).
        public mutating func remember(page: String, key: String) {
            if pages[page] == key { return }
            pages[page] = key
            pageOrder.removeAll { $0 == page }
            pageOrder.append(page)
            while pageOrder.count > AboutBlock.kept {
                pages[pageOrder.removeFirst()] = nil
            }
        }

        /// The question a page last asked this session, or nil.
        public func pageKey(_ page: String) -> String? { pages[page] }

        public var count: Int { entries.count }
    }

    // MARK: which answer a page draws

    /// What one page draws (useDescription's rules): `page` the page's own key (who is looking, and at which artist
    /// or album), `drawn` its block's words, nil for none. Only the answer to the page's question as it is now draws -
    /// the session's (`kept`), or the page's own ask's (`own`: an answer to another question draws nothing). While the
    /// question changes (who it is unsettled a moment, or a new question) what this page drew stays until the new
    /// question's answer replaces it: it never goes and comes back. Another page starts with nothing.
    public struct Showing: Sendable, Equatable {
        public private(set) var page: String?
        public private(set) var drawn: Drawn?
        /// deadwax has answered (or failed) for what was asked, or there was nothing to ask.
        public private(set) var settled = false

        public init() {}

        /// The block's words for `page` - nil for another page's.
        public func drawn(for page: String) -> Drawn? { self.page == page ? drawn : nil }

        /// The page's question now, with the session's answers and its own ask's answer, `now` in ms.
        public mutating func update(page: String, question: Question, kept: inout Kept,
                                    own: (key: String, found: Drawn?)?, now: Double) {
            let key = question.key
            if let key { kept.remember(page: page, key: key) }
            //? who it is still being settled: the question this page asked last time - its answer, when kept, drawn
            let asked = key ?? (question == .unsettled ? kept.pageKey(page) : nil)
            let fromKept: Drawn?? = asked.flatMap { (asked: String) -> Drawn?? in kept.found(asked, now: now) }
            let mine: Drawn?? = own.flatMap { (own: (key: String, found: Drawn?)) -> Drawn?? in
                key != nil && own.key == key ? .some(own.found) : nil
            }
            let answered = fromKept != nil || mine != nil
            settled = answered || question == .nothing
            if self.page != page {
                self.page = page
                drawn = nil
            }
            if let found = fromKept ?? mine {
                drawn = found
            } else if settled {
                drawn = nil
            }
        }
    }

    /// Whether the page's question is to be asked of deadwax now: one is settled, and the session keeps no answer to it.
    public static func asks(_ question: Question, kept: inout Kept, now: Double) -> Ask? {
        guard case .ask(let ask) = question, kept.found(ask.key, now: now) == nil else { return nil }
        return ask
    }
}
