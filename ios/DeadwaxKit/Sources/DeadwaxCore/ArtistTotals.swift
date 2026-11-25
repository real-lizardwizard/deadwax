import Foundation

/// One artist's totals (the redesign, slice R2 - notes/ios.md "The redesign, slice R2: Albums and Artists, and the
/// Library's top"): the songs on their albums in the album index, the plays and when one of them was last played - the
/// Mac's Artists list's Songs, Plays and Last played columns, and the songs on the phone's artist row ("6 albums · 59
/// songs"). The Albums column is Navidrome's own albumCount (its review: a split album or a compilation counts in each
/// artist's Albums there, but in the index it is one artistId's, so its songs and plays are that artist's alone).
public struct ArtistTotal: Sendable, Equatable {
    public var songs: Int
    public var plays: Int
    /// The latest of their albums' `played`, in whole milliseconds since 1970 - nil while none of them says it was.
    public var lastPlayed: Int64?

    public init(songs: Int = 0, plays: Int = 0, lastPlayed: Int64? = nil) {
        self.songs = songs
        self.plays = plays
        self.lastPlayed = lastPlayed
    }
}

/// The artists' totals and their words (slice R2). Summed from the album index - `/album_index`'s rows, what Navidrome
/// sent with each album (its songCount, playCount and played) - and nothing else: no new route, no ask per artist. Each
/// album counts under its own `artistId` alone, so two artists of one name are two, and an album with no artistId is
/// nobody's. Navidrome counts an album's plays as its songs are played, so an artist's plays are the plays of the songs
/// on their albums.
public enum ArtistTotals {
    /// Every artist's totals over `albums`, by artistId.
    public static func of(_ albums: [IndexAlbum], zone: TimeZone = .current) -> [String: ArtistTotal] {
        var totals: [String: ArtistTotal] = [:]
        for album in albums {
            guard let artist = album.artistId, !artist.isEmpty else { continue }
            var total = totals[artist] ?? ArtistTotal()
            total.songs += max(album.songCount ?? 0, 0)
            total.plays += max(album.playCount ?? 0, 0)
            if let played = playedAt(album, zone: zone) {
                total.lastPlayed = max(total.lastPlayed ?? played, played)
            }
            totals[artist] = total
        }
        return totals
    }

    /// When an album was last played: its `played` read as the Library reads its dates (AlbumTime) - nil when Navidrome
    /// sent none, or none after 1970 (its zero time, 0001-01-01, means never).
    public static func playedAt(_ album: IndexAlbum, zone: TimeZone = .current) -> Int64? {
        guard let ms = AlbumTime.ms(album.played, zone: zone), ms > 0 else { return nil }
        return ms
    }

    // MARK: the words

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The Last played column, as the design's Artists list words it (Artists.dc.html): "today", "yesterday", "3 days
    /// ago", "last week", then the day - "12 Nov", with its year when it isn't this one ("12 Nov 2025"). Days are the
    /// calendar's in `zone`, the device's; a time after `now` (a clock set wrong) is today. Nothing for never: a nil is
    /// never drawn as a date.
    public static func lastPlayedWords(_ ms: Int64?, now: Int64, zone: TimeZone = .current) -> String {
        guard let ms else { return "" }
        let days = day(now, zone: zone) - day(ms, zone: zone)
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "last week"
        default:
            let played = civil(day(ms, zone: zone))
            let shown = "\(played.day) \(months[played.month - 1])"
            return played.year == civil(day(now, zone: zone)).year ? shown : "\(shown) \(played.year)"
        }
    }

    /// The calendar day of `ms` in `zone`, counted from 1 January 1970.
    static func day(_ ms: Int64, zone: TimeZone) -> Int64 {
        let offset = Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000))) * 1000
        let local = ms + offset
        let perDay: Int64 = 86_400_000
        return local >= 0 ? local / perDay : -((-local + perDay - 1) / perDay)
    }

    /// The civil date of a day counted from 1 January 1970 (Howard Hinnant's days_from_civil, backwards).
    static func civil(_ days: Int64) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (Int(y), Int(m), Int(d))
    }

    /// "1 artist", "48 artists", "1,612 songs" - the status bar's counts, their thousands marked.
    public static func count(_ count: Int, one: String, many: String) -> String {
        "\(AlbumInfo.grouped(count)) \(count == 1 ? one : many)"
    }

    public static func artists(_ count: Int) -> String { self.count(count, one: "artist", many: "artists") }
    public static func albums(_ count: Int) -> String { self.count(count, one: "album", many: "albums") }
    public static func songs(_ count: Int) -> String { self.count(count, one: "song", many: "songs") }

    /// The status bar's selection, while a row is selected.
    public static let oneSelected = "1 selected"

    /// (R2's review) The status bar's albums under the artists listed: the albums of the index whose artistId is one of
    /// `artists`, each counted once - never the Albums column summed, which counts a split album under each of its
    /// artists.
    public static func albumCount(of artists: Set<String>, in albums: [IndexAlbum]) -> Int {
        var counted = Set<String>()
        for album in albums {
            guard let artist = album.artistId, !artist.isEmpty, artists.contains(artist) else { continue }
            counted.insert(album.id)
        }
        return counted.count
    }

    /// (R2's review) Now, in whole milliseconds since 1970 - Last played's `now`, read as a page shows and again at a
    /// day's change, never once per cell.
    public static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// A plays count, its thousands marked: "1,411"; "" for none, as the design leaves a cell with nothing.
    public static func plays(_ count: Int) -> String { count > 0 ? AlbumInfo.grouped(count) : "" }

    /// A count in a column (Albums, Songs), its thousands marked: "1,612"; "" for one Navidrome didn't give.
    public static func number(_ count: Int?) -> String {
        count.map { (count: Int) -> String in AlbumInfo.grouped(max(count, 0)) } ?? ""
    }

    /// The phone's artist row (iArtists.dc.html): "6 albums · 59 songs" - the album count as ArtistWords.albumCountLine
    /// words it, the songs after it once the album index has them, then the row's place ("in the collection"). With no
    /// songs in hand (`songs` nil or 0) it is albumCountLine's own words, as the row said before.
    public static func rowLine(albums: Int?, songs: Int?, place: String = "") -> String {
        guard let songs, songs > 0 else { return ArtistWords.albumCountLine(albums, place: place) }
        let albumCount = albums ?? 0
        var parts: [String] = []
        if albumCount > 0 { parts.append("\(albumCount) \(albumCount == 1 ? "album" : "albums")") }
        parts.append(self.songs(songs))
        let line = parts.joined(separator: " · ")
        return place.isEmpty ? line : "\(line) \(place)"
    }
}

/// (R2) The Mac's Albums and Artists pages' words (Albums.dc.html, Artists.dc.html): their columns' headers and the
/// toolbar's words its other words don't already say - the same on every device, so none of them is a device's word.
public enum LibraryColumnWords {
    public static let album = "Album"
    public static let artist = "Artist"
    public static let year = "Year"
    public static let songs = "Songs"
    public static let albums = "Albums"
    public static let plays = "Plays"
    public static let lastPlayed = "Last played"
    /// The toolbar's label before its order's pop-up.
    public static let sort = "Sort"
    /// The toolbar's Grid | List, to VoiceOver.
    public static let layout = "Show as"
    /// (R2's review) The album playing's mark in the Album column (Albums.dc.html's a.playing), to VoiceOver.
    public static let playing = "Playing"

    /// (R2's review) Play's help while it has nothing to play: in Grid (`list` false) nothing is selected, so the way is
    /// List; in List, a row to select; with one selected whose songs are still coming, nothing to say.
    public static func playHelp(list: Bool, selected: Bool, artist: Bool) -> String {
        let what = artist ? "an artist" : "an album"
        let them = artist ? "them" : "it"
        if !list { return "Select " + what + " in List to play " + them + "." }
        return selected ? "" : "Select " + what + " to play " + them + "."
    }
}
