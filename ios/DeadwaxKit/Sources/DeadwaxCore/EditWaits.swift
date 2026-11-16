import Foundation

/// How long the phone waits for Edit album's three long writes - Get lyrics, Get CD art and Tags' Apply - worked out
/// for the album in hand from what the server does for it, past its worst case with a minute's margin, and never less
/// than `Routes.timeouts` gives the route (review, 16 Nov: a fixed wait was passed by a long album - twelve tracks
/// asked under two names can keep LRCLIB 22 minutes at worst, and the Archive's redirects make even one disc's CD art
/// close to six). A wait that still runs out is no failure said as one: the write is said as maybe finished and the
/// folder read again (GetRun's unanswered, RetagFlow's), never sent again unseen.
///
/// Each figure is the server's own, read from its source by tests/test_ios_edit_parts_contract.py - a request's longest
/// silence is its connection's timeout and its read's (httpx's `read` is the wait for the next piece, and these
/// answers are small), and the waits are rounded up to the minute, so the transport keeps a handful of sessions
/// (URLSessionTransport keeps one per wait).
public enum EditWaits {
    /// The plan, the writes, the scan's cache and the answer's way back, over the network's worst case.
    public static let margin: Double = 60

    // MARK: Get lyrics (src/lyrics.py fetch_album_lyrics, src/api/lrclib_endpoint.py)

    /// One LRCLIB request's longest silence: its connection (10 s) and its read (30 s).
    public static let lrclibRequest: Double = 40
    /// Its waits while LRCLIB says it is busy (a 429 or 503): three pauses at most, none longer than 5 s.
    public static let lrclibBusy: Double = 15
    /// The names a track is asked under, in turn: its own artist, then its album artist (lookup_from_tags).
    public static let lrclibNames: Double = 2
    /// The requests for each name: the exact lookup, then the search.
    public static let lrclibRequestsPerName: Double = 2
    /// Tracks asked at once (lyrics.CONCURRENCY).
    public static let lyricsAtOnce = 2

    // MARK: Get CD art (src/routes/library.py fetch_disc_art)

    /// One Cover Art Archive request's longest silence: its connection (10 s) and its read (45 s).
    public static let archiveRequest: Double = 55
    /// The requests behind one Archive address, each its own silence: coverartarchive.org's redirect to archive.org,
    /// archive.org's to the server holding the item, and that server's answer.
    public static let archiveHops: Double = 3
    /// fanart.tv's listing, asked when the Archive has nothing for the discs: its connection (10 s) and its read
    /// (15 s).
    public static let fanartListing: Double = 25

    // MARK: Tags' Apply (src/track_tags.py execute_tag_edits)

    /// A file whose new tags outgrow the room before its audio is written whole (mutagen moves the audio along): read
    /// and written again at a slow disk's pace - a USB disk, or one that has to spin up - in bytes a second.
    public static let rewriteBytesPerSecond: Double = 20_000_000

    /// Get lyrics for `album`: every track without a lyrics file is asked (none replaced - the scan's lyricsCount
    /// counts the same files src/lyrics.py skips as kept), `lyricsAtOnce` at a time, each under both its names, each
    /// name by both requests, each request as slow as it can be and as busy.
    public static func lyrics(_ album: ScanAlbum) -> Double {
        let asked = max(1, album.trackCount - album.lyricsCount)
        let rounds = Double((asked + lyricsAtOnce - 1) / lyricsAtOnce)
        let track = lrclibNames * lrclibRequestsPerName * (lrclibRequest + lrclibBusy)
        return wait(rounds * track + margin, floor: Routes.timeouts[Routes.lyricsFetch])
    }

    /// Get CD art for `album`: the Archive's listing, fanart.tv's when the Archive has none, then each disc's picture
    /// in turn - the Archive's, the slower of the two (fanart.tv's is one 40 s request).
    public static func discArt(_ album: ScanAlbum) -> Double {
        let address = archiveRequest * archiveHops
        let pictures = Double(max(1, album.discCount)) * address
        return wait(address + fanartListing + pictures + margin, floor: Routes.timeouts[Routes.discArtFetch])
    }

    /// Tags' Apply over files of `bytes` in all: the route's own wait (the files' tags read and written, the scan's
    /// cache and the store index), and on top every file written whole at `rewriteBytesPerSecond` - an album of 24-bit
    /// 192 kHz FLAC is gigabytes.
    public static func tagsApply(bytes: Double) -> Double {
        let floor = Routes.timeouts[Routes.tagsApply] ?? 120
        let rewrite = bytes.isFinite && bytes > 0 ? bytes / rewriteBytesPerSecond : 0
        return wait(floor + rewrite, floor: floor)
    }

    /// Up to the next whole minute, and never under the route's own.
    static func wait(_ seconds: Double, floor: Double?) -> Double {
        max(floor ?? 0, (seconds / 60).rounded(.up) * 60)
    }
}
