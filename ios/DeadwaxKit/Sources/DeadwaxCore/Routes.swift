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
    public static let search = Endpoint(method: "GET", path: "/deadwax/navidrome/search", query: ["q", "artistCount", "artistOffset", "albumCount", "albumOffset", "songCount", "songOffset"])
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
    /// One album across its ids - asked by Navidrome's (`StoreAlbum`), only when there is a library (Access.hasLibrary);
    /// and (Phase 5, slice 2) by a release you hold, for Navidrome's album of it - a held album Search found opening yours.
    public static let storeAlbum = Endpoint(method: "GET", path: "/deadwax/store/album", query: ["navidrome_id", "release_mbid"])
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

    // app 0.10's (Phase 4, phase4-library.md 0): Navidrome's own playlists, as the person signed in
    public static let playlists = Endpoint(method: "GET", path: "/deadwax/navidrome/playlists", query: [])
    public static let playlist = Endpoint(method: "GET", path: "/deadwax/navidrome/playlists/{playlist_id}", query: [])
    // and slice 2's writes, each as the person signed in (the owner check is deadwax's): a new playlist
    // (`NewPlaylistBody` -> `PlaylistWithSongs`), songs added at its end (`PlaylistAddBody` -> `PlaylistAddAnswer`),
    // Edit's Done (`PlaylistEditBody` -> `PlaylistWithSongs`) and a delete (no body -> `PlaylistDeleted`)
    public static let createPlaylist = Endpoint(method: "POST", path: "/deadwax/navidrome/playlists", query: [])
    public static let addToPlaylist = Endpoint(method: "POST", path: "/deadwax/navidrome/playlists/{playlist_id}/add", query: [])
    public static let editPlaylist = Endpoint(method: "POST", path: "/deadwax/navidrome/playlists/{playlist_id}/edit", query: [])
    public static let deletePlaylist = Endpoint(method: "POST", path: "/deadwax/navidrome/playlists/{playlist_id}/delete", query: [])
    // slice 3b's (phase4-library.md 2.8): the Library's Shuffle of your whole library - a new order of every song of a
    // scope with its first page (`ShuffleStart`; `playing` the order the last tap played, for deadwax to claim; `claim`
    // the feed's fresh order, played at once), and a page of an order from `offset` (`ShufflePage`; a 404 once deadwax
    // no longer holds it)
    public static let shuffle = Endpoint(method: "GET", path: "/deadwax/navidrome/shuffle", query: ["scope", "playing", "claim"])
    public static let shufflePage = Endpoint(method: "GET", path: "/deadwax/navidrome/shuffle/{token}", query: ["offset"])
    // slice 4's (phase4-library.md 2.6): every artist, Navidrome's getArtists flattened (`ArtistList`), and one artist
    // with their albums (getArtist, `ArtistWithAlbums`; `{}` for one Navidrome doesn't have)
    public static let artists = Endpoint(method: "GET", path: "/deadwax/navidrome/artists", query: [])
    public static let artist = Endpoint(method: "GET", path: "/deadwax/navidrome/artists/{artist_id}", query: [])
    // Phase 5, slice 1's (phase5-search.md 0, 2.6): every album on disk, reduced to which album and edition it is
    // (`OwnedAnswer`, with an ETag) - the names Search reads the box against, and whose an unstarred album is
    public static let libraryOwned = Endpoint(method: "GET", path: "/deadwax/library/owned", query: [])
    // Phase 5, slice 2's (phase5-search.md 6.2): MusicBrainz's albums for the box (`FullySearchAnswer` - asked with
    // `releases=false` and `quick=true`, `SearchAlbums.limit` of them), one album's every pressing with its tracklist
    // (`ReleaseGroupAnswer`, the album you don't have), and its front cover from the Cover Art Archive through deadwax
    // (server 2.1.24; a 404 for an older server's missing route is drawn as the empty cover)
    public static let fullySearch = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/fully_search", query: ["query", "limit", "releases", "offset", "quick"])
    public static let releaseGroup = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/release_group", query: ["release_group_mbid"])
    public static let archiveCover = Endpoint(method: "GET", path: "/deadwax/coverart/{kind}/{mbid}", query: ["size"])
    // Phase 5, slice 3's (phase5-search.md 6.3): MusicBrainz's artists going by the box's words (`ArtistSearchAnswer`,
    // `MBArtistSearch.limit` of them) and its songs (`SongSearchAnswer`, `SongSearch.limit` recordings) - and a
    // MusicBrainz artist's page: who they are (`MBArtistFacts`) and their albums (`DiscographyAnswer`, a browse)
    public static let searchArtists = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/artists", query: ["name", "limit", "offset"])
    public static let searchSongs = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/songs", query: ["query", "limit", "offset"])
    public static let artistFacts = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/artist", query: ["mbid"])
    public static let discography = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/discography", query: ["artist_mbid", "types", "studio_only"])
    // Phase 5, slice 4's (phase5-search.md 6.4): what MusicBrainz's answers saved on deadwax hold matching the words
    // (`SavedSearchAnswer`, server 2.0.0-player.56) - asked beside the library as the words settle, given up after
    // `SearchSaved.waitMs`; the three searches above take `offset` for More from MusicBrainz
    public static let savedSearch = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/saved", query: ["words"])
    // Phase 6, slice 1's (phase6-get-requests.md 0): the Requests tab - the asker's downloads with slskd's progress laid
    // on (`JobsAnswer`), a download cancelled (only left, for one somebody else waits for too), moved to the next source
    // or asked of the same one again (200 either way, the refusal in `problem`), and the finished ones cleared
    public static let jobs = Endpoint(method: "GET", path: "/deadwax/download/jobs", query: [])
    public static let cancelJob = Endpoint(method: "POST", path: "/deadwax/download/jobs/{job_id}/cancel", query: [])
    public static let retryJob = Endpoint(method: "POST", path: "/deadwax/download/jobs/{job_id}/retry", query: [])
    public static let retryJobSame = Endpoint(method: "POST", path: "/deadwax/download/jobs/{job_id}/retry_same", query: [])
    public static let clearJobs = Endpoint(method: "POST", path: "/deadwax/download/jobs/clear", query: [])
    // Phase 6, slice 2's (phase6-get-requests.md 0): Get - what the store and the downloads already have of a pressing
    // (`StoreStateAnswer`, no search), Soulseek searched for it and its folders ranked (`FindCandidatesAnswer`), a
    // folder asked for (`EnqueueAnswer`), and You > Getting albums as kept on deadwax (`GetSettings`: the Format a
    // search is scored by, the floor the chips start as)
    public static let storeState = Endpoint(method: "POST", path: "/deadwax/download/store_state", query: [])
    public static let findCandidates = Endpoint(method: "POST", path: "/deadwax/download/find_candidates", query: [])
    public static let enqueue = Endpoint(method: "POST", path: "/deadwax/download/enqueue", query: [])
    public static let preferences = Endpoint(method: "GET", path: "/deadwax/me/preferences", query: [])

    /// The levels spec's name for `levelAlbum`: the album's levels warmed before its first play.
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
        playlists, playlist, createPlaylist, addToPlaylist, editPlaylist, deletePlaylist,
        shuffle, shufflePage,
        artists, artist,
        libraryOwned,
        fullySearch, releaseGroup, archiveCover,
        searchArtists, searchSongs, artistFacts, discography,
        savedSearch,
        jobs, cancelJob, retryJob, retryJobSame, clearJobs,
        storeState, findCandidates, enqueue, preferences,
    ]

    /// The routes given longer than the transport's own 8 seconds to answer, in seconds: the album index reads every
    /// album of a scope from Navidrome, a page at a time, before it answers; AutoEq's search may wait for deadwax's
    /// first fetch of AutoEq's list (src/autoeq.py FIRST_FETCH_SECONDS, 15 s) and a profile for its file
    /// (PROFILE_DEADLINE_SECONDS, 15 s); MusicBrainz's albums for the box take about eight seconds to give up while
    /// MusicBrainz turns searches away (SEARCH_PATIENCE), and an album's pressings with their tracklists up to five
    /// MusicBrainz pages; the artists and songs are quick searches as the albums are, an artist's facts one request with
    /// MusicBrainz's ten attempts (3 s apart while it is busy), and their albums a browse of up to five pages; the
    /// downloads ask slskd for every open one's transfers and each queued one's place in its queue, a cancel stops each
    /// transfer and clears the partials, a move to the next source tries each runner-up in turn until one takes it, a
    /// retry of the same one asks slskd again and a clear tidies the cancelled ones' transfers first; the store's look
    /// may ask slskd how far a download in flight has got (3 s) after the store index; a search for sources is two
    /// rounds of slskd's search, each start waiting up to SEARCH_TURN_SECONDS (30 s) at deadwax's gate and each round
    /// waited on for up to SLSKD_SEARCH_TIMEOUT (60 s at most) + 17 s, beside up to 8 s looking up the artist's former
    /// names, and slskd's state, answers and ranking around them - 292 s at worst (slice 2's review, finding 3); and an
    /// enqueue has no bound on the server at all (the release's lock, then slskd's, which answers once the peer is
    /// reached), so it is given the search's, and an answer that never comes isn't taken for a refusal
    /// (RequestOverlays.unanswered) - tests/test_ios_contract.py holds each above the server's.
    public static let timeouts: [Endpoint: Double] = [albumIndex: 30, autoEqSearch: 20, autoEqProfile: 20, libraryOwned: 30, fullySearch: 20, releaseGroup: 60, searchArtists: 20, searchSongs: 20, artistFacts: 60, discography: 60, jobs: 20, cancelJob: 30, retryJob: 60, retryJobSame: 30, clearJobs: 30, storeState: 20, findCandidates: 300, enqueue: 300]
}

/// The Cover Art Archive's thumbnail sizes the app asks deadwax's relay for (`Routes.archiveCover`'s `size`, which takes
/// 250, 500 or 1200 - the contract test checks each).
public enum ArchiveCoverSize {
    /// A list's row.
    public static let row = 250
    /// The album you don't have's own cover.
    public static let hero = 1200
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
