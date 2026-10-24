import Foundation

/// The test album: "Start test" by "deadwax test" (ios/scripts/make-test-album.py), eight songs of
/// three beeps each, the first beep at a known time, then two that are one tone cut in two. Phase 0
/// plays them to hear whether a song's start is lost - on AirPods, from silence - and whether a join
/// has a gap or a click.
public enum TestSounds {
    public static let query = "Start test"
    public static let album = "Start test"
    public static let artist = "deadwax test"
    /// search3 answers a page; the album is ten songs, and a library may hold other matches.
    public static let pageSize = 100

    /// The album's songs out of a search's, disc then track then title, each id once.
    public static func pick(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        let wanted = songs.filter { song in
            guard fold(song.album) == fold(album) else { return false }
            if let by = song.artist, fold(by) != fold(artist) { return false }
            return seen.insert(song.id).inserted
        }
        return wanted.sorted { a, b in
            let left = (a.discNumber ?? 1, a.track ?? Int.max, a.name)
            let right = (b.discNumber ?? 1, b.track ?? Int.max, b.name)
            return left < right
        }
    }

    static func fold(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// The Hi-res row: a 24/192 FLAC from the library, found by paging every song (an empty search).
public enum HiRes {
    public static let pageSize = 500
    /// At most this many pages are asked for: 10,000 songs.
    public static let maxPages = 20

    /// The best hi-res FLAC among `songs`: 192 kHz 24-bit first (what check 8 asks for, even beside a
    /// 352.8 or 384 kHz file), then the highest rate above 48 kHz, then the most bits. Nil when there
    /// is no FLAC above 48 kHz (or the server doesn't say rates - OpenSubsonic's `samplingRate`).
    public static func best(_ songs: [Song]) -> Song? {
        let flac = songs.filter { ($0.suffix ?? "").lowercased() == "flac" && ($0.samplingRate ?? 0) > 48_000 }
        func rank(_ song: Song) -> (Int, Int, Int) {
            let rate = song.samplingRate ?? 0
            let bits = song.bitDepth ?? 0
            return (rate == 192_000 && bits == 24 ? 1 : 0, rate, bits)
        }
        var best: Song?
        for song in flac where best == nil || rank(song) > rank(best!) {
            best = song
        }
        return best
    }

    /// Whether a found song is the 24/192 the check asks for, or only the best there is.
    public static func isTwentyFourOneNinetyTwo(_ song: Song) -> Bool {
        song.samplingRate == 192_000 && song.bitDepth == 24
    }
}
