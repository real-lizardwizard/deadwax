import Foundation

/// One deadwax route the app calls: its method, its path as the server declares it (path
/// parameters in braces, named as in src/), and the query parameters the app may send.
///
/// tests/test_ios_contract.py reads the `Endpoint(...)` lines below from this file and checks each
/// against the server's own routes, so a route renamed or a parameter dropped on the server fails
/// in the Python suite, where the server is changed. Keep each on one line, in this exact form.
public struct Endpoint: Sendable, Hashable {
    public let method: String
    public let path: String
    public let query: [String]

    public init(method: String, path: String, query: [String]) {
        self.method = method
        self.path = path
        self.query = query
    }
}

public enum Routes {
    // Phase 0's
    public static let health = Endpoint(method: "GET", path: "/deadwax/health", query: [])
    public static let me = Endpoint(method: "GET", path: "/deadwax/me", query: [])
    public static let signIn = Endpoint(method: "POST", path: "/deadwax/auth/login", query: [])
    public static let signOut = Endpoint(method: "POST", path: "/deadwax/auth/logout", query: [])
    public static let search = Endpoint(method: "GET", path: "/deadwax/navidrome/search", query: ["q", "artistCount", "albumCount", "songCount", "songOffset"])
    public static let stream = Endpoint(method: "GET", path: "/deadwax/navidrome/stream/{song_id}", query: ["format"])
    public static let cover = Endpoint(method: "GET", path: "/deadwax/navidrome/cover/{cover_id}", query: ["size"])

    // Phase 1's: the Library, an album, a song
    /// Whether there is a Navidrome to play from (`{configured, ok, server, problem}`).
    public static let navidromeStatus = Endpoint(method: "GET", path: "/deadwax/navidrome/status", query: [])
    /// Every album of a scope (`yours`, `store`) in one answer, with an ETag - asked with 30 s to answer (`timeouts`).
    public static let albumIndex = Endpoint(method: "GET", path: "/deadwax/navidrome/album_index", query: ["scope"])
    /// One album with its songs (`Album`), `{}` when Navidrome has none by that id.
    public static let album = Endpoint(method: "GET", path: "/deadwax/navidrome/albums/{album_id}", query: [])
    /// One song as Navidrome has it now (`Song`) - play count and credits.
    public static let song = Endpoint(method: "GET", path: "/deadwax/navidrome/songs/{song_id}", query: [])
    /// Counts a play (`submission=true`) or says what's playing (`false`).
    public static let scrobble = Endpoint(method: "POST", path: "/deadwax/navidrome/scrobble/{song_id}", query: ["submission", "time"])

    // Phase 1's: Normalization
    /// "This album is about to be played": deadwax measures its songs not yet measured (202, `{state}`).
    public static let levelAlbum = Endpoint(method: "POST", path: "/deadwax/navidrome/level/album/{album_id}", query: [])
    /// What deadwax would level one song at (`level` album or track) - Info's Normalization row.
    public static let songLevel = Endpoint(method: "GET", path: "/deadwax/navidrome/level/{song_id}", query: ["level"])
    /// An album's songs' measured loudness, raw (server 2.1.1).
    public static let loudness = Endpoint(method: "GET", path: "/deadwax/navidrome/loudness/album/{album_id}", query: [])

    // Phase 1's: resume what was playing
    public static let queue = Endpoint(method: "GET", path: "/deadwax/navidrome/queue", query: [])
    public static let saveQueue = Endpoint(method: "POST", path: "/deadwax/navidrome/queue", query: [])
    public static let saveQueueAt = Endpoint(method: "POST", path: "/deadwax/navidrome/queue/at", query: [])

    // Phase 1's: the id bridge and your library (logins on)
    /// One album across its ids - asked by Navidrome's (`StoreAlbum`), only when there is a library (Access.hasLibrary).
    public static let storeAlbum = Endpoint(method: "GET", path: "/deadwax/store/album", query: ["navidrome_id"])
    public static let myLibrary = Endpoint(method: "GET", path: "/deadwax/me/library", query: [])
    public static let libraryAdd = Endpoint(method: "POST", path: "/deadwax/me/library/add", query: [])
    public static let libraryRemove = Endpoint(method: "POST", path: "/deadwax/me/library/remove", query: [])
    public static let librarySeen = Endpoint(method: "POST", path: "/deadwax/me/library/seen", query: [])

    // app 0.4's: lyrics (server 2.1.5)
    /// A song's lyrics for Now Playing (`SongLyrics`: synced, plain or none), as Navidrome has them for the asker,
    /// with an ETag - asked again with it (`DeadwaxClient.lyrics(songID:ifNoneMatch:)`).
    public static let lyrics = Endpoint(method: "GET", path: "/deadwax/navidrome/lyrics/{song_id}", query: [])

    // the EQ's AutoEq (server 2.1.7, eq.md 2.2): deadwax's copy of AutoEq's list searched, and one result's profile
    /// AutoEq's rows whose names hold every word of `q` (`AutoEqResults`), at most `limit` (`AutoEqAsk.limit`).
    public static let autoEqSearch = Endpoint(method: "GET", path: "/deadwax/eq/autoeq", query: ["q", "limit"])
    /// One result's ParametricEQ.txt (`AutoEqProfile`), by its 16-hex-digit id.
    public static let autoEqProfile = Endpoint(method: "GET", path: "/deadwax/eq/autoeq/{id}", query: [])

    // the turntable's /scrub fallback (turntable.md 4.5): a window of a song whose copy isn't whole on the phone yet
    /// A stretch of a FLAC song from `at` for `seconds` (at most `DeckScrub.maxSeconds`) as a FLAC file of its own,
    /// its place in the song in `X-Deadwax-Window` (`DeckScrub.Header`). Asked without `max_rate` and `level`, so it
    /// is the original's own frames: the phone converts and levels them as it does a local file's.
    public static let scrub = Endpoint(method: "GET", path: "/deadwax/navidrome/scrub/{song_id}", query: ["at", "seconds"])
    // the turntable's face (turntable.md 2.3)
    /// An album's CD art for one disc: `disc<N>.*`, then `disc.*`, in the album's folder; a 404 when it has none.
    public static let discArt = Endpoint(method: "GET", path: "/deadwax/library/disc_art/navidrome", query: ["album", "disc"])

    // app 0.8's: play history (server 2.1.14, notes/play-history.md)
    /// The person's plays, newest first - a page of `limit` (`PlayHistory.page`), before the cursor of the last page's
    /// last (`before_at`, `before_id`) when asked for an older one (`HistoryPage`).
    public static let history = Endpoint(method: "GET", path: "/deadwax/me/history", query: ["limit", "before_at", "before_id"])
    /// Songs started, kept for the person: a batch of at most `PlayHistory.postMax` (`HistoryPost`) -> `HistoryTaken`.
    public static let recordHistory = Endpoint(method: "POST", path: "/deadwax/me/history", query: [])

    /// The levels spec's name for `levelAlbum`: the album's levels warmed before its first play.
    // app 0.10's (Phase 4, phase4-library.md 0): Navidrome's own playlists, as the person signed in
    public static let playlists = Endpoint(method: "GET", path: "/deadwax/navidrome/playlists", query: [])
    public static let playlist = Endpoint(method: "GET", path: "/deadwax/navidrome/playlists/{playlist_id}", query: [])

    public static var warmLevels: Endpoint { levelAlbum }

    /// Every route the app calls - what the contract test checks.
    public static let all: [Endpoint] = [
        health, me, signIn, signOut, search, stream, cover,
        navidromeStatus, albumIndex, album, song, scrobble,
        levelAlbum, songLevel, loudness,
        queue, saveQueue, saveQueueAt,
        storeAlbum, myLibrary, libraryAdd, libraryRemove, librarySeen,
        lyrics,
        autoEqSearch, autoEqProfile,
        scrub, discArt,
        history, recordHistory,
        playlists, playlist,
    ]

    /// The routes given longer than the transport's own 8 seconds to answer, in seconds: the album index reads every
    /// album of a scope from Navidrome, a page at a time, before it answers; AutoEq's search may wait for deadwax's
    /// first fetch of AutoEq's list (src/autoeq.py FIRST_FETCH_SECONDS, 15 s) and a profile for its file
    /// (PROFILE_DEADLINE_SECONDS, 15 s) - tests/test_ios_contract.py holds each above the server's.
    public static let timeouts: [Endpoint: Double] = [albumIndex: 30, autoEqSearch: 20, autoEqProfile: 20]
}

/// The cover sizes the app asks for (`Routes.cover`'s `size`) - the contract test checks each is within the server's
/// bounds (16 to 2000), as it does the search's page sizes (`TestSounds`, `HiRes`). Navidrome resizes to and keeps
/// each size asked, so the app asks for a few, never the pixels of whatever view it draws in.
public enum CoverSize {
    /// A list's row.
    public static let row = 128
    /// A grid's tile, and the mini player.
    public static let tile = 400
    /// An album page's, and Now Playing's.
    public static let hero = 1024
    /// The lock screen's.
    public static let lockScreen = 1024

    /// The sizes asked, smallest first.
    public static let steps = [row, tile, hero]

    /// The smallest size asked that is at least `pixels`, else the largest.
    public static func step(for pixels: Int) -> Int {
        steps.first { $0 >= pixels } ?? hero
    }
}

/// The fields a sign-in sends (src/routes/auth.py `SignIn`). The contract test checks them too.
public struct SignInBody: Codable, Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}
