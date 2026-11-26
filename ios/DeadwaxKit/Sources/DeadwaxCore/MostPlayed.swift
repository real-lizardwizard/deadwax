import Foundation

/// An artist's most-played SONGS (the redesign, slice R6 - notes/ios.md "The redesign, slice R6: an artist"): the songs
/// of their albums in hand you have played most, by Navidrome's play count - the Mac artist page's Most played, under
/// their discography. Songs, by your plays: not Last.fm's Top Songs (TopSongs, everyone's listens), and not slice A2's
/// order of their ALBUMS by plays, which is another list with another rule.
///
/// - EACH SONG ONCE ACROSS ITS PRESSINGS: a song is its key - the one Top Songs meets songs by (LastfmMatch.key: "Let It
///   Happen" and "Let It Happen - 2015 Remaster" are one song, "Elephant (Max Cooper remix)" another) - so a song on the
///   standard and the deluxe pressing is listed once.
/// - ITS PLAYS ARE ONE TAKE'S, NEVER A SUM: the most-played take's own count (a tie, the first in album order), and the
///   row is that take - its album, the song a tap plays - so the number beside it is the one its album's page shows
///   under Plays (check 560).
/// - THE ORDER: most plays first; a tie in album order - the albums as given (the page's play order: newest first,
///   undated last), then the song's own place on its album.
/// - A song never played (Navidrome sends no count until it has been, or 0) isn't listed, nor one with no title to key.
/// - The `most` most played.
public enum MostPlayedSongs {
    /// The most the list holds.
    public static let most = 10

    public struct Row: Sendable, Equatable, Identifiable {
        /// Its place in the list, from 0.
        public let rank: Int
        /// The take listed - the most played of the song's.
        public let song: Song
        public let album: Album
        /// That take's own play count.
        public let plays: Int

        public var id: String { song.id }

        public var title: String { song.title ?? "" }

        /// Under the title: "{album} · {year}", as a top song's.
        public var line: String { LastfmWords.albumLine(album.name, year: album.year) }

        /// Its plays as a Plays cell says them: "12", "1,411".
        public var playsWords: String { ArtistTotals.plays(plays) }
    }

    /// The list, from `albums` - each with its songs, in the page's play order.
    public static func rows(_ albums: [Album]) -> [Row] {
        // every take with a key and a play count, in album order
        var takes: [(key: String, song: Song, album: Album, plays: Int, at: Int)] = []
        var seen = Set<String>()
        for album in albums {
            for song in album.song ?? [] where seen.insert(song.id).inserted {
                guard let plays = song.playCount, plays > 0 else { continue }
                let key = LastfmMatch.key(song.title)
                guard !key.isEmpty else { continue }
                takes.append((key, song, album, plays, takes.count))
            }
        }
        // a song is its most-played take: a tie, the first in album order
        var best: [String: Int] = [:]
        for (index, take) in takes.enumerated() {
            if let kept = best[take.key], takes[kept].plays >= take.plays { continue }
            best[take.key] = index
        }
        let listed = best.values.sorted { (a: Int, b: Int) -> Bool in
            takes[a].plays != takes[b].plays ? takes[a].plays > takes[b].plays : takes[a].at < takes[b].at
        }
        return listed.prefix(most).enumerated().map { (rank: Int, index: Int) -> Row in
            Row(rank: rank, song: takes[index].song, album: takes[index].album, plays: takes[index].plays)
        }
    }

    /// A tap on a row: every listed song that plays now (`playable` - offline, only those on this device), in the
    /// list's order, played from this one - nil when this one doesn't (as TopSongs.play).
    public static func play(_ rows: [Row], from rank: Int, playable: (Song) -> Bool) -> (songs: [Song], at: Int)? {
        let songs = rows.filter { (row: Row) -> Bool in playable(row.song) }
        guard let at = songs.firstIndex(where: { (row: Row) -> Bool in row.rank == rank }) else { return nil }
        return (songs.map(\.song), at)
    }
}
