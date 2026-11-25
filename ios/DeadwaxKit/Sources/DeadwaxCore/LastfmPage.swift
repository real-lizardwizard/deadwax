import Foundation

/// How Last.fm's answer comes onto an artist page (lastfm.md 3.1's Arrival, the web's describe.ts rules): NOTHING MOVES
/// UNDER A FINGER.
///
/// - With Last.fm on, deadwax in reach and no answer kept for the artist this session, everything below Play and Shuffle
///   waits - for the answer, or `waitMs` after the artist's own answer is in hand, whichever comes first - with no
///   spinner (`Arrival`).
/// - Top Songs goes where it belongs, above the albums, when its answer came within that wait; one later goes after the
///   albums for the page's life (`placeOf`, judged once - describe.ts's).
/// - The hero's listeners line keeps its height from the first frame whenever it may be drawn at all (`Shown`), so Play
///   never moves as it fills.
/// - The session's answers (`Kept`): the last `kept` artists', so a page opened again draws at once, in place - an
///   answer that couldn't be had whole (or at all) kept only `unsureKeptMs`, then asked again (UNSURE_KEPT_MS).
public enum LastfmPage {
    /// How long the page waits for Last.fm's answer after the artist's own is in hand, in ms. It rests on deadwax's kept
    /// answers coming back in about 100 ms, as the descriptions' do; a cold one takes Last.fm's own time, unmeasured.
    public static let waitMs = 800
    /// How many artists' answers the session keeps.
    public static let kept = 64
    /// How long an answer not had whole is kept, in ms (describe.ts UNSURE_KEPT_MS).
    public static let unsureKeptMs: Double = 60_000

    /// Where Top Songs goes: in its place, between Play and the albums - or after the albums, for an answer that came
    /// once they were drawn.
    public enum Place: Sendable, Equatable {
        case inPlace, afterAlbums
    }

    /// describe.ts `placeOf`: where it was put already, else - the first time there is something to draw - in place
    /// while the albums aren't drawn yet, after them once they are. Nil while there is nothing.
    public static func placeOf(was: Place?, present: Bool, albumsDrawn: Bool) -> Place? {
        if let was { return was }
        guard present else { return nil }
        return albumsDrawn ? .afterAlbums : .inPlace
    }

    /// What the page waits for, and where Top Songs went - one per page and artist.
    public struct Arrival: Sendable, Equatable {
        /// Everything below Play and Shuffle is drawn.
        public private(set) var released: Bool
        public private(set) var place: Place?

        /// A page opening: it waits only with Last.fm on, deadwax in reach and no answer kept (`kept`: whether the
        /// session's answer has songs to draw - nil for none kept). One kept draws at once, in place.
        public init(state: LastfmState, online: Bool, kept: Bool?) {
            if let kept {
                released = true
                place = LastfmPage.placeOf(was: nil, present: kept, albumsDrawn: false)
            } else {
                released = !(state == .on && online)
                place = nil
            }
        }

        /// The page is holding what lies below Play.
        public var holding: Bool { !released }

        /// An answer came (`present`: it has songs to draw): where they go judged first, then everything drawn.
        public mutating func answered(present: Bool) {
            place = LastfmPage.placeOf(was: place, present: present, albumsDrawn: released)
            released = true
        }

        /// `waitMs` passed, deadwax went out of reach or Last.fm isn't on any more: everything drawn, the answer (if
        /// it comes) after the albums.
        public mutating func release() {
            released = true
        }
    }

    // MARK: what the page draws

    /// What deadwax's Last.fm is, for this page: /me's word - except that an answer saying Last.fm isn't enabled while
    /// /me (read as the app opened or came back) still said on is believed at once: refused when it couldn't be had
    /// (Last.fm refusing the key - the route's parts unavailable), off when nothing was asked (no key). So a key that
    /// Last.fm refuses shows on the next artist page, not only once the app comes back.
    public static func state(me: LastfmState, answer: LastfmArtist?) -> LastfmState {
        guard me == .on, let answer, !answer.enabled else { return me }
        return answer.unavailable ? .refused : .off
    }

    /// What of Last.fm's the page draws (lastfm.md 3.1): the hero's line (`heroLine` - its height kept from the first
    /// frame - and its words), Top Songs, and the foot line - each only with Last.fm on, the foot line only off or
    /// refused, and only for whoever runs deadwax (`Access.seesDetail`).
    public struct Shown: Sendable, Equatable {
        public let heroLine: Bool
        public let listeners: String?
        public let topSongs: Bool
        public let foot: String?
    }

    /// `reserved`: the page has drawn the hero's line already (`drawsLine`, as the page kept it) - its height stays for
    /// the page's life, blank, whatever comes after (an answer saying Last.fm isn't enabled, deadwax out of reach before
    /// any answer), so Play never moves (the review of A1).
    public static func shown(state: LastfmState, online: Bool, answer: LastfmArtist?, seesDetail: Bool,
                             reserved: Bool = false) -> Shown {
        let on = state == .on
        let usable = on && answer?.enabled == true ? answer : nil
        let heroLine = reserved || drawsLine(state: state, online: online, answer: answer)
        let foot: String?
        switch state {
        case .off: foot = LastfmWords.footOff
        case .refused: foot = LastfmWords.footRefused
        case .on, .absent: foot = nil
        }
        return Shown(heroLine: heroLine, listeners: heroLine ? LastfmWords.listeners(usable?.listeners) : nil,
                     topSongs: !(usable?.topSongs ?? []).isEmpty, foot: seesDetail ? foot : nil)
    }

    /// Whether the hero's line is drawn for this state of things: Last.fm on, and the page online or an answer in hand
    /// that Last.fm is enabled - its height there from the first frame. `state` is `state(me:answer:)`'s. Once true for
    /// a page, the page keeps the line (`shown`'s `reserved`).
    public static func drawsLine(state: LastfmState, online: Bool, answer: LastfmArtist?) -> Bool {
        state == .on && (online || answer?.enabled == true)
    }

    /// Whether an answer has songs to draw - what `placeOf` calls present.
    public static func present(_ answer: LastfmArtist?) -> Bool {
        answer?.enabled == true && !(answer?.topSongs ?? []).isEmpty
    }

    // MARK: asking

    /// Who the answer is asked for: their MusicBrainz id when known, and their name (as the route takes them - the name
    /// trimmed, at most `nameMax` characters, else left out) - nil with neither.
    public struct Ask: Sendable, Equatable {
        public let mbid: String?
        public let name: String?

        public init?(mbid: String?, name: String?) {
            let mbid = MBID.of(mbid)
            let trimmed = PyText.strip(name ?? "")
            let name = trimmed.isEmpty || trimmed.unicodeScalars.count > LastfmPage.nameMax ? nil : trimmed
            guard mbid != nil || name != nil else { return nil }
            self.mbid = mbid
            self.name = name
        }

        /// What the session keeps the answer under.
        public var key: String { "\(mbid ?? "")|\(name ?? "")" }
    }

    /// The route's longest name (src/routes/lastfm.py NAME_MAX).
    public static let nameMax = 200

    // MARK: the session's answers

    /// The last `kept` artists' answers, by Navidrome's artist id (beside their own answer, ArtistsModel), each with who
    /// it was asked about (`asked`, Ask.key) - the most recently kept last. One `unsure` (not had whole, Last.fm not
    /// enabled, or no answer at all: a failure) is kept only `unsureKeptMs`.
    public struct Kept: Sendable {
        /// What is kept for an artist: their answer, or none (an ask that failed - kept a moment, so Back draws at once).
        public enum Held: Sendable, Equatable {
            case answer(LastfmArtist)
            case failed

            public var answer: LastfmArtist? {
                if case .answer(let answer) = self { return answer }
                return nil
            }
        }

        public struct Entry: Sendable, Equatable {
            public let held: Held
            public let asked: String
        }

        private var entries: [String: (entry: Entry, until: Double?)] = [:]
        private var order: [String] = []

        public init() {}

        /// What is kept for the artist, unless its moment has passed (`now` in ms).
        public func entry(_ id: String, now: Double) -> Entry? {
            guard let kept = entries[id] else { return nil }
            if let until = kept.until, now >= until { return nil }
            return kept.entry
        }

        /// An artist's answer kept - nil for an ask that failed.
        public mutating func keep(_ id: String, _ answer: LastfmArtist?, asked: String, now: Double) {
            let unsure = answer.map { (answer: LastfmArtist) -> Bool in answer.unavailable || !answer.enabled } ?? true
            entries[id] = (Entry(held: answer.map(Held.answer) ?? .failed, asked: asked),
                           unsure ? now + LastfmPage.unsureKeptMs : nil)
            order.removeAll { $0 == id }
            order.append(id)
            while order.count > LastfmPage.kept {
                entries[order.removeFirst()] = nil
            }
        }

        public var count: Int { entries.count }
    }
}
