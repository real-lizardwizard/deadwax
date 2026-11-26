import Foundation

/// Similar Artists on an artist's page (Last.fm, slice A2 - deadwax-plans/lastfm.md 3.4; notes/ios.md "Last.fm, slice
/// A2"): the artists Last.fm calls similar (`LastfmArtist.similar`, its order) met with the library's artists, as round
/// pictures under the albums - and See All's grid past four.
///
/// - **Yours**: Last.fm's `mbid` equal to a library artist's `musicBrainzId` (two library artists with one id: the
///   first in the list's order, as ArtistJoin's claims keep the first); else EXACTLY ONE library artist whose folded
///   name (Fold.key, compared as FoldKey's UTF-16 units) is Last.fm's - two who share it ("Low" and "LOW") are no
///   match, so neither is guessed at - and only where one side has no id: two different ids are two artists (the UK
///   Nirvana of 1967 is never your Seattle Nirvana; A2's review, correcting lastfm.md 3.4's "else by name"). A tile of
///   yours is that artist, drawn with their own name and Navidrome's picture, opening their page.
/// - **Theirs**: anyone else with an `mbid`, drawn with Last.fm's name, the person glyph and "Not in your library",
///   opening their MusicBrainz page - where Get is. One with no `mbid` has nowhere to open, and is left out.
/// - Each artist once (the first, Last.fm's higher place, kept), never the page's own artist, at most `shown`.
/// - The library's artists not in hand (none asked yet, or the ask failed): every tile theirs - it degrades, it
///   doesn't break. The page draws the tiles once the list has answered or `SearchPacing.ownedWaitMs` has passed
///   since it was asked for (the page's own wait, begun with the ask - A2's review).
public enum SimilarArtists {
    /// The most tiles a page draws.
    public static let shown = 12
    /// See All is offered past this many: the page's row shows them, a mouse reaches every one in See All's grid.
    public static let seeAllPast = 4
    /// See All's grid: a tile's least width, in points.
    public static let gridMin: Double = 112

    /// (A2's review) A tile's side on the phone: `gridMin` grown with the text (`scaled`, the view's ScaledMetric) - but
    /// never wider than the page it is drawn on (`page`, its width measured; nil before it is), so at AX5 (some 379
    /// points) a tile still fits a 343-point page, See All's grid one column, never off both edges.
    public static func side(_ scaled: Double, page: Double?) -> Double {
        guard let page, page > 0 else { return scaled }
        return min(scaled, page)
    }

    /// What a tile opens: an artist of the library's page, or a MusicBrainz artist's.
    public enum Opens: Sendable, Equatable, Hashable {
        case artist(Artist)
        case musicBrainz(mbid: String, name: String)
    }

    /// One tile: whose it is (and so what it opens), and the name it draws.
    public struct Tile: Sendable, Equatable, Identifiable {
        public let opens: Opens
        public let name: String

        /// `artist:<Navidrome id>` for yours, `mb:<mbid>` for theirs - never the same.
        public var id: String {
            switch opens {
            case .artist(let artist): return "artist:\(artist.id)"
            case .musicBrainz(let mbid, _): return "mb:\(mbid)"
            }
        }

        /// One of yours.
        public var yours: Bool {
            if case .artist = opens { return true }
            return false
        }

        /// Under the name: nothing for yours, "Not in your library" for theirs.
        public var line: String { yours ? "" : LastfmWords.notInLibrary }

        /// What VoiceOver reads: "Pond", "GUM, Not in your library".
        public var spoken: String { yours ? name : "\(name), \(line)" }

        /// Navidrome's picture of yours; none of theirs (no picture is looked up for an artist you don't have).
        public var coverArt: String? {
            if case .artist(let artist) = opens { return artist.coverArt }
            return nil
        }
    }

    /// The library's artists, as the tiles meet them: by MusicBrainz id (the first in the list with it) and by folded
    /// name (every one with it), each keyed by FoldKey - UTF-16 units, as the rest of Core compares fold keys, never
    /// Swift's canonical equivalence. Made once per list (ArtistsModel's serial).
    public struct Library: Sendable {
        let byMbid: [FoldKey: Artist]
        let byName: [FoldKey: [Artist]]

        public init(_ artists: [Artist]) {
            var byMbid: [FoldKey: Artist] = [:]
            var byName: [FoldKey: [Artist]] = [:]
            for artist in artists {
                if let mbid = MBID.of(artist.musicBrainzId).map(FoldKey.init), byMbid[mbid] == nil { byMbid[mbid] = artist }
                let key = FoldKey(Fold.key(artist.name))
                if !key.units.isEmpty { byName[key, default: []].append(artist) }
            }
            self.byMbid = byMbid
            self.byName = byName
        }

        /// The library's artist Last.fm's is: by id, else the one artist with that folded name where one of the two has
        /// no id - nil for none, for two of the name, or for two different ids.
        func match(_ similar: LastfmSimilarArtist) -> Artist? {
            if let mbid = similar.mbid, let artist = byMbid[FoldKey(mbid)] { return artist }
            let key = FoldKey(Fold.key(similar.name))
            guard !key.units.isEmpty, let named = byName[key], named.count == 1 else { return nil }
            let artist = named[0]
            if let theirs = similar.mbid, let ours = MBID.of(artist.musicBrainzId), FoldKey(theirs) != FoldKey(ours) {
                return nil
            }
            return artist
        }
    }

    /// The page's tiles: Last.fm's similar artists (in its order) met with the library (`library` nil: not in hand -
    /// every tile theirs), each once, never the page's own artist (`id`, Navidrome's, and `mbid`), at most `shown`.
    public static func tiles(_ similar: [LastfmSimilarArtist]?, library: Library?, page id: String,
                             mbid: String?) -> [Tile] {
        let own = MBID.of(mbid)
        var tiles: [Tile] = []
        var seen: Set<String> = []
        for artist in similar ?? [] {
            guard tiles.count < shown else { break }
            let tile: Tile
            if let yours = library?.match(artist) {
                guard yours.id != id else { continue }
                let name = PyText.strip(yours.name ?? "")
                tile = Tile(opens: .artist(yours), name: name.isEmpty ? artist.name : name)
            } else if let theirs = artist.mbid {
                guard theirs != own else { continue }
                tile = Tile(opens: .musicBrainz(mbid: theirs, name: artist.name), name: artist.name)
            } else {
                continue
            }
            guard seen.insert(tile.id).inserted else { continue }
            tiles.append(tile)
        }
        return tiles
    }

    /// Whether the tiles are drawn: the library's artists answered (or failed), or the page has waited
    /// `SearchPacing.ownedWaitMs` for them - so a tile of yours isn't drawn as theirs only to change in a moment.
    public static func drawsTiles(listKnown: Bool, waited: Bool) -> Bool {
        listKnown || waited
    }

    /// Whether the section is drawn, or its room held: Last.fm on and enabled, with similar artists to meet.
    public static func listed(_ answer: LastfmArtist?) -> Bool {
        answer?.enabled == true && !(answer?.similar ?? []).isEmpty
    }

    /// See All, past `seeAllPast`.
    public static func seesAll(_ tiles: [Tile]) -> Bool {
        tiles.count > seeAllPast
    }
}
