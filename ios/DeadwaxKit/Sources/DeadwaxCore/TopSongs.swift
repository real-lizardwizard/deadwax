import Foundation

/// An artist's top songs on their page (lastfm.md 3.2): Last.fm's list, in its order, each met with a song of the page's
/// albums or said to be not in your library.
///
/// - A SONG YOU HAVE: its key (LastfmMatch.key) is a song's of the page's albums. Of every song with that key, the
///   earliest album wins - by its year, undated last - then the page's play order, then disc and track: so the studio
///   take beats a later live album's. Each library song meets one top song at most, the higher first.
/// - A SONG YOU DON'T HAVE: no album of the page's has it.
/// - BEFORE EVERY ALBUM'S SONGS ARE IN, a row is only waiting: drawn with Last.fm's title and a blank line, it does
///   nothing when tapped - it fills in place once they are.
/// - A SONG THAT MAY BE YOURS (the review of A1): no album in hand has it, but an album of theirs whose songs aren't in
///   hand might - one that didn't load, or, while deadwax can't be reached, one neither the page nor this device has
///   the songs of. It is never said to be not in your library: drawn as a waiting row, dimmed, it does nothing.
public enum TopSongs {
    /// How many the artist page shows; See All shows every one (the answer's ten at most).
    public static let shown = 5
    /// The most a list holds (src/lastfm.py TOP_SONGS).
    public static let most = 10

    public enum Kind: Sendable, Equatable {
        /// The albums' songs aren't all in yet.
        case waiting
        case have(song: Song, album: Album)
        case missing
        /// No album in hand has it, and an album of theirs whose songs aren't in hand may.
        case unknown
    }

    public struct Row: Sendable, Equatable, Identifiable {
        /// Its place in Last.fm's list, from 0.
        public let rank: Int
        public let top: LastfmTrack
        public let kind: Kind

        public var id: Int { rank }

        /// The library song's own title for one you have; Last.fm's for the rest.
        public var title: String {
            if case .have(let song, _) = kind, let title = song.title, !title.isEmpty { return title }
            return top.title
        }

        /// Under the title: "{album} · {year}" for one you have, "Not in your library" for one you don't - and nothing
        /// while it waits.
        public var line: String {
            switch kind {
            case .waiting, .unknown: return ""
            case .have(_, let album): return LastfmWords.albumLine(album.name, year: album.year)
            case .missing: return LastfmWords.notInLibrary
            }
        }

        public var song: Song? {
            if case .have(let song, _) = kind { return song }
            return nil
        }
    }

    /// The rows of Last.fm's list (its first `most`), met with `albums`' songs - the page's albums, in its play order,
    /// with their songs - or, while those aren't all in (`albums` nil), every row waiting. With `unknown` (an album of
    /// theirs isn't among `albums`: its songs aren't in hand), a song none of them has may be yours: `.unknown`.
    public static func rows(_ top: [LastfmTrack], albums: [Album]?, unknown: Bool = false) -> [Row] {
        let top = Array(top.prefix(most))
        guard let albums else {
            return top.enumerated().map { (rank: Int, track: LastfmTrack) -> Row in Row(rank: rank, top: track, kind: .waiting) }
        }
        var candidates = Self.candidates(albums)
        return top.enumerated().map { (rank: Int, track: LastfmTrack) -> Row in
            let key = LastfmMatch.key(track.title)
            guard !key.isEmpty, let at = candidates.firstIndex(where: { (one: Candidate) -> Bool in one.key == key })
            else { return Row(rank: rank, top: track, kind: unknown ? .unknown : .missing) }
            let found = candidates.remove(at: at)
            return Row(rank: rank, top: track, kind: .have(song: found.song, album: found.album))
        }
    }

    /// What the rows are met with (`rows`' `albums` and `unknown`): the page's albums (`order`, its play order) whose
    /// songs are in hand - online the asks' own, nil (every row waiting) until each album has answered or failed;
    /// while deadwax can't be reached, the asks' or else this device's (`kept`) - and whether any of theirs isn't among
    /// them. So an album that didn't load, or isn't on the device, never makes its songs "not in your library".
    public static func library(order: [String], asks: ArtistAlbumAsks<Album>, online: Bool,
                               kept: (String) -> Album?) -> (albums: [Album], unknown: Bool)? {
        let albums: [Album]
        if online {
            guard asks.order == order, asks.settled else { return nil }
            albums = asks.answers
        } else {
            albums = order.compactMap { (id: String) -> Album? in asks.ready[id] ?? kept(id) }
        }
        return (albums, albums.count < order.count)
    }

    /// What MusicBrainz's song search is asked for a song you don't have: Last.fm's title as the server keys it
    /// (`LastfmMatch.strip` - "Let It Happen - 2015 Remaster" asks for "Let It Happen", "X (feat. Y)" for "X"), or the
    /// title as written when that strips to nothing, with the page's artist (`SongSearch.fieldedQuery`).
    public static func searchQuery(title: String, artist: String) -> String {
        let stripped = LastfmMatch.strip(title)
        return SongSearch.fieldedQuery(title: stripped.isEmpty ? title : stripped, artist: artist)
    }

    /// A library song a top song may be: its key, and where it stands in the earliest-first order.
    struct Candidate {
        let key: String
        let song: Song
        let album: Album
        let year: Int?
        let albumAt: Int
        let disc: Int?
        let track: Int?
        let songAt: Int
    }

    /// Every song of the albums with a key, earliest first: the album's year (undated last), the page's order, disc,
    /// track (none last), then the album's own order.
    static func candidates(_ albums: [Album]) -> [Candidate] {
        var all: [Candidate] = []
        var seen = Set<String>()
        for (albumAt, album) in albums.enumerated() {
            let year = album.year.flatMap { (year: Int) -> Int? in year > 0 ? year : nil }
            for (songAt, song) in (album.song ?? []).enumerated() where seen.insert(song.id).inserted {
                let key = LastfmMatch.key(song.title)
                guard !key.isEmpty else { continue }
                all.append(Candidate(key: key, song: song, album: album, year: year, albumAt: albumAt,
                                     disc: song.discNumber, track: song.track, songAt: songAt))
            }
        }
        func before(_ a: Int?, _ b: Int?) -> Bool? {
            switch (a, b) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return nil
            }
        }
        return all.sorted { (a: Candidate, b: Candidate) -> Bool in
            if let earlier = before(a.year, b.year) { return earlier }
            if a.albumAt != b.albumAt { return a.albumAt < b.albumAt }
            if let earlier = before(a.disc, b.disc) { return earlier }
            if let earlier = before(a.track, b.track) { return earlier }
            return a.songAt < b.songAt
        }
    }

    /// A tap on a song you have: every top song you have that plays now (`playable` - offline, only those on this
    /// device), in Last.fm's order, played from this one - nil when this one doesn't.
    public static func play(_ rows: [Row], from rank: Int, playable: (Song) -> Bool) -> (songs: [Song], at: Int)? {
        let songs = rows.compactMap { (row: Row) -> (rank: Int, song: Song)? in
            guard let song = row.song, playable(song) else { return nil }
            return (row.rank, song)
        }
        guard let at = songs.firstIndex(where: { $0.rank == rank }) else { return nil }
        return (songs.map(\.song), at)
    }

    /// A song you don't have whose search failed, as its row says it for the visit: MusicBrainz away (its routes' 503)
    /// in the spec's words, anything else as ErrorWords says it - its own words only for whoever runs deadwax.
    public static func trouble(_ error: any Error, admin: Bool) -> String {
        RetagWords.musicBrainzAway(error) ? LastfmWords.away : ErrorWords.of(error, admin: admin).said
    }

    /// A song you don't have, found by MusicBrainz's song search (SongSearch.group of a fielded title-and-artist
    /// query): the album to open - the first album (as sortAlbums has them) of the first song that is this one
    /// (LastfmMatch.key) and theirs: their MusicBrainz id among its artists when the page knows it, else its credit
    /// their name (Fold.key). Nil when none is.
    public static func album(_ found: [FoundSong], title: String, mbid: String?, name: String) -> SongAlbum? {
        let key = LastfmMatch.key(title)
        guard !key.isEmpty else { return nil }
        let id = MBID.of(mbid)
        let theirName = FoldKey(Fold.key(name))
        return found.first { (song: FoundSong) -> Bool in
            guard LastfmMatch.key(song.title) == key, !song.albums.isEmpty else { return false }
            if let id {
                return song.artists.contains { (artist: SongArtist) -> Bool in MBID.of(artist.id) == id }
            }
            return !theirName.units.isEmpty && FoldKey(Fold.key(song.credit)) == theirName
        }?.albums.first
    }
}
