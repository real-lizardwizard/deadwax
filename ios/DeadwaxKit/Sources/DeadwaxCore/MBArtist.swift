import Foundation

// MusicBrainz's artists in Search (Phase 5, slice 3 - notes/ios-specs/phase5-search.md 2.3, 6.3): `/artists`' answer
// (Search's Artists, beside the library's own), and a MusicBrainz artist's page - who they are (`/artist`, the web's
// artistPage.ts factsLine) and their albums (`/discography`, artistRows over MusicBrainz's groups alone: each marked
// with what the library holds of it, newest first). Held to the web by Fixtures/search/search-songs-vectors.json.

/// MusicBrainz's artist search, as Search asks it.
public enum MBArtistSearch {
    /// How many artists one ask brings (searchList.ts `ARTIST_SEARCH_LIMIT`, the route's own default).
    public static let limit = 10
}

/// `GET /deadwax/search_musicbrainz/artists` (`ArtistSearchResponse`): the artists going by a name, each as
/// src/artists.py's artist_match shapes them - and how many match in all, when MusicBrainz said.
public struct ArtistSearchAnswer: Decodable, Sendable, Equatable {
    public let matches: [MBArtistMatch]
    public let count: Int?

    enum CodingKeys: String, CodingKey { case matches, count }

    public init(matches: [MBArtistMatch] = [], count: Int? = nil) {
        self.matches = matches
        self.count = count
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        matches = fields.looseList(MBArtistMatch.self, .matches) ?? []
        count = fields.looseField(Int.self, .count)
    }
}

/// `GET /deadwax/search_musicbrainz/artist` (`ArtistFacts`) - the part the page's line under the name reads: their type,
/// where they're from, when they began and ended. Every field may be empty.
public struct MBArtistFacts: Decodable, Sendable, Equatable {
    public let mbid: String?
    public let name: String
    public let type: String
    public let disambiguation: String
    public let country: String
    public let area: String
    public let beginArea: String
    public let began: String
    public let endedOn: String
    public let ended: Bool

    enum CodingKeys: String, CodingKey {
        case mbid, name, type, disambiguation, country, area, began, ended
        case beginArea = "begin_area"
        case endedOn = "ended_on"
    }

    public init(mbid: String? = nil, name: String = "", type: String = "", disambiguation: String = "", country: String = "",
                area: String = "", beginArea: String = "", began: String = "", endedOn: String = "", ended: Bool = false) {
        self.mbid = mbid
        self.name = name
        self.type = type
        self.disambiguation = disambiguation
        self.country = country
        self.area = area
        self.beginArea = beginArea
        self.began = began
        self.endedOn = endedOn
        self.ended = ended
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        mbid = fields.looseField(String.self, .mbid)
        name = fields.looseField(String.self, .name) ?? ""
        type = fields.looseField(String.self, .type) ?? ""
        disambiguation = fields.looseField(String.self, .disambiguation) ?? ""
        country = fields.looseField(String.self, .country) ?? ""
        area = fields.looseField(String.self, .area) ?? ""
        beginArea = fields.looseField(String.self, .beginArea) ?? ""
        began = fields.looseField(String.self, .began) ?? ""
        endedOn = fields.looseField(String.self, .endedOn) ?? ""
        ended = fields.looseField(Bool.self, .ended) ?? false
    }
}

/// `GET /deadwax/search_musicbrainz/discography` (`DiscographyResponse`): every release group credited to the artist -
/// cut at 500 (`truncated`), and `problem` when MusicBrainz failed part way: then the list is not their albums.
public struct DiscographyAnswer: Decodable, Sendable, Equatable {
    public let releaseGroups: [ReleaseGroup]
    public let truncated: Bool
    public let problem: String?

    enum CodingKeys: String, CodingKey {
        case truncated, problem
        case releaseGroups = "release-groups"
    }

    public init(releaseGroups: [ReleaseGroup] = [], truncated: Bool = false, problem: String? = nil) {
        self.releaseGroups = releaseGroups
        self.truncated = truncated
        self.problem = problem
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        releaseGroups = fields.looseList(ReleaseGroup.self, .releaseGroups) ?? []
        truncated = fields.looseField(Bool.self, .truncated) ?? false
        problem = fields.looseField(String.self, .problem)
    }

    /// Whether MusicBrainz broke the list off: "not in your library" on half of them would be a claim made of half an
    /// answer (ArtistPage.tsx's browse).
    public var brokenOff: Bool { !(problem ?? "").isEmpty }
}

/// A MusicBrainz artist's page (ArtistPage.tsx for an artist known only by MusicBrainz, with lib/artistPage.ts's
/// rules): the line under their name, their albums as rows, each row's line and tick, and the page's words.
public enum MBArtistPage {
    /// One of their albums (artistPage.ts `ArtistRow`, made from MusicBrainz's group alone - no album of Navidrome's
    /// claims it here): what the library holds of it, by its folders.
    public struct Row: Sendable, Equatable, Identifiable {
        /// `group:<id>`.
        public let key: String
        public let title: String
        public let year: String?
        public let group: ReleaseGroup
        /// In the library - nil while `/library/owned` hasn't answered.
        public let held: Bool?
        /// Held, and a folder of it yours - nil when not held.
        public let yours: Bool?
        /// How many releases of it the library holds: "2 pressings" past one.
        public let editions: Int
        /// The releases the library holds of it, in the order a copy is opened - what the id bridge is asked about.
        public let releases: [String]
        /// What MusicBrainz calls it, when it isn't a plain album: "Live album", "Compilation".
        public let kind: String?

        public var id: String { key }
    }

    /// How many artists' pages the session keeps (ArtistPage.tsx `ARTISTS_KEPT`): who they are and their albums, so
    /// Back to one draws it at once and asks nothing.
    public static let kept = 20

    public static let studioOnly = "Studio only"
    public static let loading = "Loading their albums\u{2026}"
    public static let away = "Their other albums can't be shown right now - try again in a few minutes."
    public static let truncated = "Showing their first 500 albums."
    public static let offline = "Their albums show once deadwax is back."

    /// No row to draw: with Studio only on, how to see the rest.
    public static func none(studio: Bool) -> String {
        studio ? "No studio albums found - turn off Studio only to see them all." : "No other albums found."
    }

    /// The rows (`artistRows([], groups, index)`): each group once, newest year first (the undated last), then by its
    /// folded title, then by key.
    public static func rows(_ groups: [ReleaseGroup], index: OwnedIndex?) -> [Row] {
        var seen = Set<[UInt16]>()
        var rows: [Row] = []
        for group in groups {
            if group.id.isEmpty || !seen.insert(Array(group.id.utf16)).inserted { continue }
            let holding = SearchAlbums.heldInOrder(OwnedIndex.forGroup(index, groupId: group.id).held)
            let releases = WebText.unique(holding.compactMap { MBID.of($0.releaseMbid) })
            let mine = !holding.isEmpty
            let editions = WebText.unique(holding.map { (folder: OwnedAlbum) -> String in
                MBID.of(folder.releaseMbid).map { "r:\($0)" } ?? "f:\(folder.path)"
            }).count
            let kind = SearchAlbums.kind(group)
            rows.append(Row(key: "group:\(group.id)", title: group.title ?? "", year: SearchAlbums.year(group), group: group,
                            held: mine ? true : index != nil ? false : nil,
                            yours: mine ? holding.contains { $0.yours != false } : nil,
                            editions: editions, releases: releases, kind: kind == "Album" ? nil : kind))
        }
        //? localeCompare: ICU's collation, as WebCollation approximates it
        let folded = rows.map { Fold.key($0.title) }
        return rows.indices.sorted { (a: Int, b: Int) -> Bool in
            let (x, y) = (rows[a], rows[b])
            switch (x.year, y.year) {
            case (nil, .some): return false
            case (.some, nil): return true
            case let (.some(first), .some(second)) where first != second:
                return FoldKey(second) < FoldKey(first)
            default: break
            }
            let title = SongSearch.collate(folded[a], folded[b])
            if title != 0 { return title < 0 }
            let key = WebCollation.compare(x.key, y.key)
            if key != 0 { return key < 0 }
            return a < b
        }.map { rows[$0] }
    }

    /// A row's line (artistPage.ts `rowLine`): "1994 · in your library · 2 pressings", "2008 · Live album · not in your
    /// library" - nothing of the library while it hasn't said.
    public static func line(_ row: Row, personal: Bool) -> String {
        var parts: [String] = []
        if let year = row.year { parts.append(year) }
        if let kind = row.kind, !kind.isEmpty { parts.append(kind) }
        if let held = row.held {
            parts.append(held ? Whose.heldPhrase(personal: personal, yours: row.yours) : "not in your library")
            if held && row.editions > 1 { parts.append("\(row.editions) pressings") }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// The row's tick (ArtistPage.tsx's): held, and yours - or every held row without a library of your own.
    public static func marked(_ row: Row, personal: Bool) -> Bool {
        row.held == true && (!personal || row.yours != false)
    }

    /// Whether a row's tap asks the id bridge first (`openRow`): a held album with releases the library holds - else it
    /// opens the album you don't have at once.
    public static func asksBridge(_ row: Row) -> Bool {
        row.held == true && !row.releases.isEmpty
    }

    /// Who they are, in a line (`factsLine`): "Group · Bristol · since 1991", "Group · London · 1965 to 2014".
    public static func factsLine(_ facts: MBArtistFacts?) -> String {
        guard let facts else { return "" }
        let began = WebText.prefix(facts.began, 4)
        let ended = WebText.prefix(facts.endedOn, 4)
        let span: String
        if !began.isEmpty && !ended.isEmpty {
            span = "\(began) to \(ended)"
        } else if !began.isEmpty {
            span = facts.ended ? "\(began), ended" : "since \(began)"
        } else {
            span = ended.isEmpty ? "" : "until \(ended)"
        }
        let place = Credits.first(facts.beginArea, Credits.first(facts.area, facts.country))
        return [facts.type, place, span].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
