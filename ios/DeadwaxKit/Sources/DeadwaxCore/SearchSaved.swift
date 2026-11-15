import Foundation

// Phase 5, slice 4 (notes/ios-specs/phase5-search.md 5.1, 6.4): what's saved, the kept answers and More from
// MusicBrainz - the web's lib/searchList.ts (savedFor, kindArea, the saved words), app/searchAnswers.ts (the kept
// answers) and lib/searchResults.ts / lib/songs.ts (appendPage, morePages, appendSongs and their words). Pure; held to
// the web by ios/scripts/export-search-saved-vectors.cjs (SearchSavedVectorTests).

// MARK: what's saved

/// `GET /deadwax/search_musicbrainz/saved` (src/routes/search_musicbrainz.py `saved`): what MusicBrainz's answers saved
/// on disk hold matching the words - each kind in the shape of the route the app already reads it from (`artists` as
/// /artists, `albums` and `credited` as /fully_search, `songs` as /songs). `available` false: nothing could be
/// searched (saving off, no file yet, an index slow or broken) - never an error. Read leniently: a kind missing or of
/// the wrong shape is none.
public struct SavedSearchAnswer: Decodable, Sendable, Equatable {
    public let artists: ArtistSearchAnswer
    public let albums: FullySearchAnswer
    public let songs: SongSearchAnswer
    public let credited: FullySearchAnswer
    public let available: Bool

    enum CodingKeys: String, CodingKey { case artists, albums, songs, credited, available }

    public init(artists: ArtistSearchAnswer = ArtistSearchAnswer(), albums: FullySearchAnswer = FullySearchAnswer(),
                songs: SongSearchAnswer = SongSearchAnswer(), credited: FullySearchAnswer = FullySearchAnswer(),
                available: Bool) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
        self.credited = credited
        self.available = available
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artists = fields.looseField(ArtistSearchAnswer.self, .artists) ?? ArtistSearchAnswer()
        albums = fields.looseField(FullySearchAnswer.self, .albums) ?? FullySearchAnswer()
        songs = fields.looseField(SongSearchAnswer.self, .songs) ?? SongSearchAnswer()
        credited = fields.looseField(FullySearchAnswer.self, .credited) ?? FullySearchAnswer()
        available = fields.looseField(Bool.self, .available) ?? false
    }
}

/// What's saved for some words, as Search keeps it (searchList.ts `SavedFound`): artists as /artists answers them,
/// release groups, the groups credited to exactly the words (`credited`, in studio order - the artist reading's), and
/// songs (`SongSearch.group` of its recordings). Nothing held is left out here: that is worked out as it is drawn.
public struct SavedFound: Sendable, Equatable {
    public let matches: [MBArtistMatch]
    public let groups: [ReleaseGroup]
    public let credited: [ReleaseGroup]?
    public let songs: [FoundSong]

    public init(matches: [MBArtistMatch], groups: [ReleaseGroup], credited: [ReleaseGroup]?, songs: [FoundSong]) {
        self.matches = matches
        self.groups = groups
        self.credited = credited
        self.songs = songs
    }

    /// As Search.tsx's askSaved keeps an answer that was `available`.
    public init(_ answer: SavedSearchAnswer) {
        self.init(matches: answer.artists.matches, groups: answer.albums.releaseGroups,
                  credited: answer.credited.releaseGroups, songs: SongSearch.group(answer.songs.recordings))
    }
}

/// ...and as a view draws it (`SavedAnswer`): `shown` - the groups the library doesn't hold - worked out from the
/// library's index as it is drawn, none before the index is in hand.
public struct SavedAnswer: Sendable, Equatable {
    public let matches: [MBArtistMatch]
    public let groups: [ReleaseGroup]
    public let shown: [ReleaseGroup]
    public let songs: [FoundSong]

    public init(matches: [MBArtistMatch] = [], groups: [ReleaseGroup] = [], shown: [ReleaseGroup] = [],
                songs: [FoundSong] = []) {
        self.matches = matches
        self.groups = groups
        self.shown = shown
        self.songs = songs
    }
}

public enum SearchSaved {
    /// How long the library's moment waits for what's saved, from when it was asked (`SAVED_WAIT_MS`): it answers in
    /// milliseconds; past this it is given up for the words, MusicBrainz's answer alone - so nothing waits on it.
    public static let waitMs = 400

    /// How many of an artist's saved albums the artist reading draws at most (`SAVED_ARTIST_ALBUMS`): MusicBrainz's
    /// page.
    public static let artistAlbums = 12

    /// A studio album or EP as the studio clause reads one (`studioGroup`): an Album or EP with none of the noisy
    /// secondary types.
    public static func studioGroup(_ group: ReleaseGroup) -> Bool {
        let primary = JSText.lowercase(group.primaryType ?? "")
        let noisy = Set(SearchReading.noisySecondaryTypes.map { JSText.lowercase($0) })
        return (primary == "album" || primary == "ep")
            && !(group.secondaryTypes ?? []).contains { noisy.contains(JSText.lowercase($0)) }
    }

    /// What's saved that a view draws for words read this way (`savedFor`): only the kinds MusicBrainz is asked for
    /// (`kinds`), and under the artist reading only the albums credited to that artist - from `credited`, all of
    /// theirs saved - the studio ones when MusicBrainz is asked the studio clause (`studio`), in studio order,
    /// `artistAlbums` of them. `shown` from `index`, none until it is in hand (an album you have drawn twice, else).
    public static func savedFor(_ reading: SearchPlan, _ saved: SavedFound?, kinds: [SearchKind], studio: Bool,
                                index: OwnedIndex?) -> SavedAnswer? {
        guard let saved else { return nil }
        let artist = reading.kind == .artist ? Fold.key(reading.artist) : ""
        func keep(_ group: ReleaseGroup) -> Bool {
            (artist.isEmpty || WebText.same(Fold.key(Credits.name(group.artistCredit)), artist)) && (!studio || studioGroup(group))
        }
        let albums = kinds.contains(.albums)
        let groups: [ReleaseGroup]
        if !albums {
            groups = []
        } else if !artist.isEmpty {
            groups = Array(SearchAlbums.studioOrder((saved.credited ?? saved.groups).filter(keep)).prefix(artistAlbums))
        } else {
            groups = saved.groups.filter(keep)
        }
        return SavedAnswer(matches: kinds.contains(.artists) ? saved.matches : [], groups: groups,
                           shown: index.map { SearchAlbums.notInLibrary(groups, $0) } ?? [],
                           songs: kinds.contains(.songs) ? saved.songs : [])
    }
}

// MARK: a kind view's MusicBrainz rows, kept in place

/// What a kind view drew below its library's rows for its words (searchList.ts `KindArea`): what's saved leading
/// (`lead`), what landed after (`rest`), what each key was drawn as, and whether MusicBrainz's failure has been drawn
/// below the lead - kept so that what lands late never moves what was drawn.
public struct KindArea: Sendable, Equatable {
    public enum From: String, Sendable, Equatable { case saved, musicbrainz }

    public let lead: [String]
    public let rest: [String]
    public let from: [String: From]
    public let problem: Bool

    public init(lead: [String], rest: [String], from: [String: From], problem: Bool) {
        self.lead = lead
        self.rest = rest
        self.from = from
        self.problem = problem
    }

    /// A kind view's rows below its library's (`kindArea`): what's saved, then MusicBrainz's answer - each row once
    /// drawn kept in its place and as what it was drawn as (else as what still holds it); what's saved leads only while
    /// nothing of MusicBrainz's - its rows, or its failure - has been drawn below it, and anything new after that goes
    /// at the foot. `above`: the keys drawn above (the library's); `problem`: MusicBrainz's failure drawn now.
    public static func arrange(_ before: KindArea?, saved: [SearchRow], musicbrainz: [SearchRow], above: Set<String>,
                               problem: Bool = false) -> (lead: [SearchRow], rest: [SearchRow], area: KindArea) {
        //? a Map by key, as the web's: the first place kept, the last row
        func byKey(_ rows: [SearchRow]) -> (order: [String], rows: [String: SearchRow]) {
            var order: [String] = []
            var found: [String: SearchRow] = [:]
            for row in rows where !above.contains(row.key) {
                if found[row.key] == nil { order.append(row.key) }
                found[row.key] = row
            }
            return (order, found)
        }
        let savedBy = byKey(saved)
        let answerBy = byKey(musicbrainz)
        var from: [String: From] = [:]
        var placed = Set<String>()
        var lead: [SearchRow] = []
        var rest: [SearchRow] = []
        func put(_ into: inout [SearchRow], _ row: SearchRow?, _ source: From) {
            guard let row, !placed.contains(row.key) else { return }
            into.append(row)
            placed.insert(row.key)
            from[row.key] = source
        }
        func again(_ into: inout [SearchRow], _ key: String) {
            let was: From = before?.from[key] == .musicbrainz ? .musicbrainz : .saved
            let same = was == .musicbrainz ? answerBy.rows : savedBy.rows
            if let row = same[key] {
                put(&into, row, was)
            } else if was == .musicbrainz {
                put(&into, savedBy.rows[key], .saved)
            } else {
                put(&into, answerBy.rows[key], .musicbrainz)
            }
        }
        for key in before?.lead ?? [] { again(&lead, key) }
        for key in before?.rest ?? [] { again(&rest, key) }
        let below = !(before?.rest.isEmpty ?? true) || (before?.problem ?? false)
        for key in savedBy.order {
            if below { put(&rest, savedBy.rows[key], .saved) } else { put(&lead, savedBy.rows[key], .saved) }
        }
        for key in answerBy.order { put(&rest, answerBy.rows[key], .musicbrainz) }
        let area = KindArea(lead: lead.map(\.key), rest: rest.map(\.key), from: from,
                            problem: problem || (before?.problem ?? false))
        return (lead, rest, area)
    }
}

// MARK: the kept answers

/// One of MusicBrainz's search answers, as Search keeps it.
public enum KeptSearchAnswer: Sendable, Equatable {
    case albums(FullySearchAnswer)
    case artists(ArtistSearchAnswer)
    case songs(SongSearchAnswer)
}

/// Search's kept MusicBrainz answers (app/searchAnswers.ts): the last `count` search answers - albums, artists and
/// songs - by the exact ask (its route, words and page), successes only, for the app's life, so words searched before
/// (cut back from "portishead third" to "portishead", Back, a chip there and back) are answered with no request at all
/// - drawn whole at the library's moment. Only first pages are kept: More from MusicBrainz always asks.
public struct SearchAnswersKept: Sendable {
    /// How many are kept (`SEARCH_ANSWERS_KEPT`).
    public static let count = 24

    private var order: [String] = []
    private var answers: [String: KeptSearchAnswer] = [:]

    public init() {}

    /// The answer kept for this ask (`keptAnswer`) - nil when none is.
    public func kept(_ key: String) -> KeptSearchAnswer? { answers[key] }

    /// Keep a success as the newest (`keepAnswer`); the oldest goes past `count`.
    public mutating func keep(_ key: String, _ answer: KeptSearchAnswer) {
        order.removeAll { $0 == key }
        order.append(key)
        answers[key] = answer
        while order.count > Self.count {
            answers[order.removeFirst()] = nil
        }
    }

    /// The keys kept, oldest first.
    public var keys: [String] { order }

    /// The ask's key: its route and what it sends - each a page of the app's own size from the first.
    public static func albumsKey(_ query: String) -> String { "fully_search\n\(query)\n\(SearchAlbums.limit)" }
    public static func artistsKey(_ name: String) -> String { "artists\n\(name)\n\(MBArtistSearch.limit)" }
    public static func songsKey(_ query: String) -> String { "songs\n\(query)\n\(SongSearch.limit)" }

    /// The albums kept for an ask (Search.tsx `keptAlbums`): its first query's, and - a reading that wasn't free words
    /// finding nothing - its fallback's. Nil when either answer needed isn't kept; the query that answered with it.
    public func albums(_ ask: SearchState.AlbumsAsk) -> (found: FullySearchAnswer, query: String)? {
        guard case .albums(let first)? = kept(Self.albumsKey(ask.first)) else { return nil }
        guard first.releaseGroups.isEmpty, let fallback = ask.fallback, !fallback.isEmpty else { return (first, ask.first) }
        guard case .albums(let again)? = kept(Self.albumsKey(fallback)) else { return nil }
        return (again, fallback)
    }

    /// The artists kept for an ask (`keptArtists`).
    public func artists(_ ask: SearchState.ArtistsAsk) -> ArtistSearchAnswer? {
        guard case .artists(let found)? = kept(Self.artistsKey(ask.name)) else { return nil }
        return found
    }

    /// The songs kept for an ask (`keptSongs`): its query's, and - a title beside an artist finding no song - its
    /// fallback's.
    public func songs(_ ask: SearchState.SongsAsk) -> (found: SongSearchAnswer, query: String)? {
        guard case .songs(let first)? = kept(Self.songsKey(ask.first)) else { return nil }
        guard first.recordings.isEmpty, let fallback = ask.fallback, !fallback.isEmpty else { return (first, ask.first) }
        guard case .songs(let again)? = kept(Self.songsKey(fallback)) else { return nil }
        return (again, fallback)
    }
}

// MARK: More from MusicBrainz

public enum SearchMore {
    /// The furthest offset MusicBrainz's search routes take (`MUSICBRAINZ_OFFSET_MAX`, the routes' *_OFFSET_MAX).
    public static let offsetMax = 1000

    /// Whether there is another page (`morePages`): `.more` - More asks for it; `.end` - every answer is in; `.far` -
    /// more match, but past `offsetMax`, so a word more is the way on.
    public enum Pages: String, Sendable, Equatable { case more, end, far }

    /// `next`: where the next page starts (every answer so far, held ones too); `count` MusicBrainz's own total, or
    /// unknown - a full last page then taken to mean there may be more; a page that brought nothing ends it.
    public static func pages(next: Int, count: Int?, last: Int, limit: Int) -> Pages {
        if last <= 0 { return .end }
        let remaining = count.map { next < $0 } ?? (last >= limit)
        if !remaining { return .end }
        return next <= offsetMax ? .more : .far
    }

    /// One more page of albums appended (searchResults.ts `appendPage`): the groups not already got, and of those the
    /// ones shown - the held left out as the first page leaves them. `added` the rows the page brought, `held` how many
    /// of its new groups the library holds.
    public static func appendPage(_ groups: [ReleaseGroup], _ shown: [ReleaseGroup], _ page: [ReleaseGroup],
                                  _ index: OwnedIndex?) -> (groups: [ReleaseGroup], shown: [ReleaseGroup], added: Int, held: Int) {
        var known = Set(groups.map(\.id))
        var fresh: [ReleaseGroup] = []
        for group in page where known.insert(group.id).inserted {
            fresh.append(group)
        }
        let showing = SearchAlbums.notInLibrary(fresh, index)
        return (groups + fresh, shown + showing, showing.count, fresh.count - showing.count)
    }

    /// What a page of albums brought, in words (`morePageWords`): `note` drawn under the rows, `said` announced.
    public static func pageWords(added: Int, held: Int, personal: Bool) -> (note: String?, said: String) {
        let place = personal ? Whose.inTheCollection : Whose.inYourLibrary
        if added > 0 { return (nil, "\(added) more \(added == 1 ? "album" : "albums") found") }
        if held == 1 { return ("The next album found is \(place) already.", "The next album is \(place) already") }
        if held > 0 {
            return ("The next \(held) albums found are all \(place) already.", "The next \(held) albums are all \(place) already")
        }
        return ("No more results.", "No more results")
    }

    /// What a page of artists brought, announced (Search.tsx's askMoreArtists): the page's own count.
    public static func artistsSaid(_ page: Int) -> String {
        "\(page) more \(page == 1 ? "artist" : "artists") found"
    }

    /// One more page of the song search merged in (songs.ts `appendSongs`): every page's recordings regrouped, the
    /// songs drawn kept in their places (a later take adding its albums in place), every other song after them in the
    /// order found. `added` the new songs, `grown` the albums the songs drawn gained.
    public static func appendSongs(_ recordings: [MBRecording], _ page: [MBRecording], drawn: [FoundSong]? = nil)
        -> (recordings: [MBRecording], songs: [FoundSong], added: Int, grown: Int) {
        let all = recordings + page
        let regrouped = SongSearch.group(all)
        var byKey: [FoldKey: FoundSong] = [:]
        for song in regrouped { byKey[FoldKey(song.key)] = song }
        var kept: [FoundSong] = []
        var grown = 0
        for was in drawn ?? SongSearch.group(recordings) {
            guard let now = byKey[FoldKey(was.key)] else { continue }
            kept.append(now)
            grown += now.albums.count - was.albums.count
        }
        let keys = Set(kept.map { FoldKey($0.key) })
        let fresh = regrouped.filter { !keys.contains(FoldKey($0.key)) }
        return (all, kept + fresh, fresh.count, grown)
    }

    /// What a page of songs brought, in words (`moreSongsWords`).
    public static func songsWords(added: Int, grown: Int) -> (note: String?, said: String) {
        if added > 0 { return (nil, "\(added) more \(added == 1 ? "song" : "songs") found") }
        if grown > 0 {
            let albums = "\(grown) more \(grown == 1 ? "album" : "albums")"
            return ("No new songs - \(albums) for the songs above.", "No new songs - \(albums) for the songs above")
        }
        return ("No more results.", "No more results")
    }

    /// The button's words (Search.tsx's kindView): "More albums", "More artists", "More songs".
    public static func button(_ kind: SearchKind) -> String {
        switch kind {
        case .albums: return "More albums"
        case .artists: return "More artists"
        case .songs: return "More songs"
        }
    }

    /// Past the furthest page: "That's all for this search - add a word to narrow it."
    public static let far = "That's all for this search - add a word to narrow it."
}

// MARK: the words

extension SearchWords {
    /// What is announced of what's saved, as the sections holding it are drawn (`savedWords`): "Found earlier: 1 song."
    public static func saved(_ counts: [SearchKind: Int]) -> String {
        let said = count(counts)
        return said.isEmpty ? "" : "Found earlier: \(said)."
    }

    /// Said when nothing answered and what's saved is drawn (`SAVED_AWAY_SAID`).
    public static let savedAwaySaid = "Showing earlier results - searching for more isn't working right now."

    /// What is announced for MusicBrainz once every kind asked has settled (`musicBrainzWords`): "Also found: 3
    /// albums." - "More found: …" when what's saved is drawn above (`saved`); when no kind answered, that searching for
    /// more isn't working (or, under what's saved, that these are earlier results).
    public static func musicBrainz(_ counts: [SearchKind: Int], answered: Bool, saved: Bool = false) -> String {
        if !answered { return saved ? savedAwaySaid : moreUnsearched }
        let said = count(counts)
        if saved { return said.isEmpty ? "Nothing more found." : "More found: \(said)." }
        return said.isEmpty ? "Nothing more found." : "Also found: \(said)."
    }

    /// MusicBrainz's failure where what's saved is drawn above it (`savedAwayWords`): showing earlier results - `short`
    /// for a slot's one row; a refusal's own words, as ever.
    public static func savedAway(_ failure: MBFailure, short: Bool = false) -> String {
        if failure.refused { return failure.message }
        if failure.busy { return short ? "Showing earlier results." : "Showing earlier results - try again in a moment for more." }
        if failure.unavailable { return short ? "Showing earlier results." : savedAwaySaid }
        return failure.message
    }

    /// A late kind's slot when MusicBrainz's answer brought nothing that isn't drawn above it already
    /// (`nothingMoreWords`): "No more albums for “…”."
    public static func nothingMore(_ kind: SearchKind, _ text: String) -> String {
        "No more \(kindWords(kind).many) for \u{201C}\(text)\u{201D}."
    }
}
