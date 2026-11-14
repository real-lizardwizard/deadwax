import Foundation

// The Search box's reading (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2.1): the web's ui/src/lib/searchQuery.ts
// - which artist the words name, if any, and what is left as a title - with the queries MusicBrainz is asked by it
// (first asked in slice 2, ported now with the reading they belong to). Held to the web by
// Fixtures/search/search-vectors.json (ios/scripts/export-search-vectors.cjs).

/// How the box was read (searchQuery.ts `SearchPlan`): MusicBrainz's query, and what the words were taken for.
public struct SearchPlan: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Equatable, Hashable, CaseIterable {
        /// an artist named, a title with them
        case albumByArtist = "album-by-artist"
        /// the whole box an artist's name
        case artist
        /// anything else
        case free
    }

    /// MusicBrainz's `query`.
    public let query: String
    public let kind: Kind
    /// The artist it was read as, in the library's spelling - nil for free words.
    public let artist: String?
    /// The album title it was read as - nil unless `albumByArtist`.
    public let title: String?

    public init(query: String, kind: Kind, artist: String?, title: String?) {
        self.query = query
        self.kind = kind
        self.artist = artist
        self.title = title
    }
}

public enum SearchReading {
    /// How long after typing stops the library is asked (`LIBRARY_SETTLE_MS`), in milliseconds.
    public static let librarySettleMs = 200
    /// ...and MusicBrainz, from slice 2 (`MUSICBRAINZ_SETTLE_MS`).
    public static let musicBrainzSettleMs = 700
    /// The fewest characters MusicBrainz is asked for by the pause alone (`MUSICBRAINZ_MIN_CHARS`).
    public static let musicBrainzMinChars = 3
    /// The most the box takes (`SEARCH_MAX_CHARS`) - the server's `q` takes 200.
    public static let maxCharacters = 200
    /// What "va" and "various artists" name, unless the library has its own.
    public static let variousArtists = "Various Artists"

    /// The library's artists as the box is read against them (`artistNames`): each name trimmed, keyed by its
    /// foldName, the first spelling kept - and "va" and "various artists" for Various Artists unless a name already
    /// folds to either.
    public static func artistNames(_ artists: [String?]) -> [FoldKey: String] {
        var names: [FoldKey: String] = [:]
        for artist in artists {
            let name = JSText.trim(artist ?? "")
            let key = Fold.key(name)
            if !key.isEmpty, names[FoldKey(key)] == nil { names[FoldKey(key)] = name }
        }
        for alias in ["va", "various artists"] where names[FoldKey(alias)] == nil {
            names[FoldKey(alias)] = variousArtists
        }
        return names
    }

    /// The box read (`searchQuery`) - nil when it holds nothing. The whole box a name: that artist; else the longest
    /// name at either end with words left (separators stripped from them; at one length, the start before the end):
    /// an album by that artist; else free words. `filter` is ANDed onto the query (the type filter, slice 2).
    public static func read(_ text: String, names: [FoldKey: String], filter: String = "") -> SearchPlan? {
        let words = Self.words(text)
        guard !words.isEmpty else { return nil }
        func named(_ part: ArraySlice<String>) -> String? {
            names[FoldKey(Fold.key(part.joined(separator: " ")))]
        }
        func plan(_ query: String, _ kind: SearchPlan.Kind, _ artist: String?, _ title: String?) -> SearchPlan {
            SearchPlan(query: withTypeFilter(query, filter), kind: kind, artist: artist, title: title)
        }
        if let whole = named(words[...]) {
            return plan("artist:\(quoteTerm(whole))", .artist, whole, nil)
        }
        var length = words.count - 1
        while length >= 1 {
            let leadingRest = strip(words[length...])
            if let leading = named(words[..<length]), !leadingRest.isEmpty {
                let title = leadingRest.joined(separator: " ")
                return plan(fieldedAlbumQuery(title, leading), .albumByArtist, leading, title)
            }
            let trailingRest = strip(words[..<(words.count - length)])
            if let trailing = named(words[(words.count - length)...]), !trailingRest.isEmpty {
                let title = trailingRest.joined(separator: " ")
                return plan(fieldedAlbumQuery(title, trailing), .albumByArtist, trailing, title)
            }
            length -= 1
        }
        return plan(words.joined(separator: " "), .free, nil, nil)
    }

    /// `text.trim().split(/\s+/).filter(Boolean)`: the words, split on runs of JavaScript's white space.
    public static func words(_ text: String) -> [String] {
        var words: [String] = []
        var word = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if JSText.isTrimmed(scalar) {
                if !word.isEmpty { words.append(String(word)) }
                word = String.UnicodeScalarView()
            } else {
                word.append(scalar)
            }
        }
        if !word.isEmpty { words.append(String(word)) }
        return words
    }

    /// The words without those that only separate an artist from a title (`- – — : / | · •` alone) at either end.
    static func strip(_ words: ArraySlice<String>) -> ArraySlice<String> {
        var part = words
        while let first = part.first, isSeparator(first) { part = part.dropFirst() }
        while let last = part.last, isSeparator(last) { part = part.dropLast() }
        return part
    }

    /// `/^[-–—:/|·•]+$/`.
    static func isSeparator(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { (scalar: Unicode.Scalar) -> Bool in
            switch scalar.value {
            case 0x2D, 0x2013, 0x2014, 0x3A, 0x2F, 0x7C, 0xB7, 0x2022: return true
            default: return false
            }
        }
    }

    /// A term in double quotes, its backslashes and quotes escaped (`quoteTerm`).
    public static func quoteTerm(_ text: String) -> String {
        //? scalar by scalar, as JS's replace works on code units - Foundation's search would take a quote followed by a
        //? combining mark as one character, and leave it
        var out = String.UnicodeScalarView()
        out.append("\"")
        for scalar in text.unicodeScalars {
            if scalar == "\\" || scalar == "\"" { out.append("\\") }
            out.append(scalar)
        }
        out.append("\"")
        return String(out)
    }

    /// `(query) AND filter`, or the query alone with no filter (`withTypeFilter`).
    public static func withTypeFilter(_ query: String, _ filter: String) -> String {
        filter.isEmpty ? query : "(\(query)) AND \(filter)"
    }

    /// An album by its title and artist, as credited or as called now (release.ts `fieldedAlbumQuery`).
    public static func fieldedAlbumQuery(_ album: String, _ artist: String) -> String {
        "releasegroup:\(quoteTerm(album)) AND (artist:\(quoteTerm(artist)) OR artistname:\(quoteTerm(artist)))"
    }
}
