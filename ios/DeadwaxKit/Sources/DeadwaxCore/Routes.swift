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
    /// and (Phase 5, slice 2) by a release you hold, for Navidrome's album of it - a held album Search found opening yours;
    /// and (manual search, slice A2, server 2.1.40) by a download, for a manual search's Done row.
    public static let storeAlbum = Endpoint(method: "GET", path: "/deadwax/store/album", query: ["job_id", "navidrome_id", "release_mbid"])
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
    // Phase 6, slice 3's (phase6-get-requests.md 0, 2.11, 2.12): a download somebody else asked for joined from the
    // store line (`JoinAnswer`; 409 in words for one that landed, stopped or was cleared since), and You > Getting
    // albums changed on the phone - only what was chosen (`GetChoice`), answered with all three as they stand after it
    public static let joinJob = Endpoint(method: "POST", path: "/deadwax/download/jobs/{job_id}/join", query: [])
    public static let savePreferences = Endpoint(method: "PUT", path: "/deadwax/me/preferences", query: [])
    // Album info (2026-11-15, notes/ios.md "Album info"): one of the store's folders of an album, every file's tags read
    // from the disk as it is asked (`AlbumFiles`) - the track viewer's route, a user's: what only the files' tags hold
    // (Media, Catalogue number, Barcode, Country, Status), by the folder the id bridge names
    public static let libraryTracks = Endpoint(method: "GET", path: "/deadwax/library/tracks", query: ["album"])
    // Edit album (Phase 8, slice 1 - notes/ios.md "Edit album on the phone"): the library's scan without its tracks
    // (server 2.1.28's `tracks=false`, kept per page with its ETag), MusicBrainz's pressings of a group without their
    // tracklists and one pressing with its tracklist (the editor's two asks), the retag's preview and apply (Edit
    // albums'; the plan worked out again by apply, never sent), the cover alone (`art/fetch`), the folder's cover
    // (`/library/art`, by its path), and It's fine as it is / Ask about it again (Look after the library's)
    public static let libraryAlbums = Endpoint(method: "GET", path: "/deadwax/library/albums", query: ["tracks"])
    public static let releases = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/releases", query: ["release_group_mbid", "tracks"])
    public static let release = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/release", query: ["release_mbid"])
    public static let retagPreview = Endpoint(method: "POST", path: "/deadwax/library/retag/preview", query: [])
    public static let retagApply = Endpoint(method: "POST", path: "/deadwax/library/retag/apply", query: [])
    public static let artFetch = Endpoint(method: "POST", path: "/deadwax/library/art/fetch", query: [])
    public static let libraryArt = Endpoint(method: "GET", path: "/deadwax/library/art", query: ["album"])
    public static let queueIgnore = Endpoint(method: "POST", path: "/deadwax/library/queue/ignore", query: [])
    public static let queueUnignore = Endpoint(method: "POST", path: "/deadwax/library/queue/unignore", query: [])
    // Edit album's Tags (Phase 8, slice 2 - notes/ios.md "Edit album on the phone"): a tag edit's preview and apply
    // (Edit albums'; the plan worked out again by apply, never sent), and one picture inside one track (the track's
    // page, by the album's folder, the file's name and the picture's place in it)
    public static let tagsPreview = Endpoint(method: "POST", path: "/deadwax/library/tags/preview", query: [])
    public static let tagsApply = Endpoint(method: "POST", path: "/deadwax/library/tags/apply", query: [])
    public static let trackPicture = Endpoint(method: "GET", path: "/deadwax/library/tracks/picture", query: ["album", "file", "index"])
    // Edit album's Artwork and Lyrics (Phase 8, slice 3): Get lyrics and Get CD art for the folder (Edit albums'; each
    // chooses nothing, so it needs no preview), and one CD art picture beside the tracks, by the folder and its name
    public static let lyricsFetch = Endpoint(method: "POST", path: "/deadwax/library/lyrics/fetch", query: [])
    public static let discArtFetch = Endpoint(method: "POST", path: "/deadwax/library/disc_art/fetch", query: [])
    public static let libraryDiscArt = Endpoint(method: "GET", path: "/deadwax/library/disc_art", query: ["album", "file"])
    // Edit album's Delete (Phase 8, slice 4): what deleting the folder takes, read live, and the delete itself (both
    // Look after the library's)
    public static let deletionSummary = Endpoint(method: "GET", path: "/deadwax/library/deletion_summary", query: ["album"])
    public static let deleteAlbum = Endpoint(method: "POST", path: "/deadwax/library/delete", query: [])
    // The artist tools (Phase 8, slice 5 - notes/ios.md "The artist tools on the phone"): one of the library's names
    // for an artist as the scan knows it, and a picture in their folder (both a user's); Artist images' preview and
    // apply, the candidates' pictures through deadwax's relay (2.1.32) and the MusicBrainz artist search (Edit albums');
    // Move albums' preview and apply (Look after the library's) - every apply sent the body its preview was, the
    // server working the plan out again
    public static let libraryArtist = Endpoint(method: "GET", path: "/deadwax/library/artist", query: ["name"])
    public static let artistArt = Endpoint(method: "GET", path: "/deadwax/library/artist/art", query: ["artist", "kind"])
    public static let artistImagesPreview = Endpoint(method: "POST", path: "/deadwax/library/artist/images/preview", query: [])
    public static let artistImagesApply = Endpoint(method: "POST", path: "/deadwax/library/artist/images/apply", query: [])
    public static let artistPicture = Endpoint(method: "GET", path: "/deadwax/library/artist/picture", query: ["url"])
    public static let artistSearch = Endpoint(method: "POST", path: "/deadwax/library/artist/search", query: [])
    public static let refilePreview = Endpoint(method: "POST", path: "/deadwax/library/artist/refile/preview", query: [])
    public static let refileApply = Endpoint(method: "POST", path: "/deadwax/library/artist/refile/apply", query: [])
    // Needs a look (Phase 8, slice 6 - notes/ios.md "Needs a look on the phone"): how many albums need a look, read off
    // the saved scan (Settings > Manage's row), and an album noted as looked at as the editor leaves it (both Look after
    // the library's) - the list itself is the scan's (`libraryAlbums`), the marks slice 1's
    public static let queueSummary = Endpoint(method: "GET", path: "/deadwax/library/queue/summary", query: [])
    public static let queueReviewed = Endpoint(method: "POST", path: "/deadwax/library/queue/reviewed", query: [])
    // Library care (Phase 8, slice 7 - notes/ios.md "Library care on the phone"): Rescan, answered as the scan without
    // its tracks (server change A's `tracks=false`), and In nobody's library with its flags' Add for them and Dismiss
    // (all Look after the library's) - the runs are slice 1's and 3's Get cover, Get CD art and Get lyrics, one album at
    // a time
    public static let rescan = Endpoint(method: "POST", path: "/deadwax/library/rescan", query: ["tracks"])
    public static let held = Endpoint(method: "GET", path: "/deadwax/library/held", query: [])
    public static let heldAdd = Endpoint(method: "POST", path: "/deadwax/library/held/flags/{flag_id}/add", query: [])
    public static let heldDismiss = Endpoint(method: "POST", path: "/deadwax/library/held/flags/{flag_id}/dismiss", query: [])
    // Server settings (Phase 8, slice 8 - notes/ios.md "Server settings on the phone"): the settings and their one save,
    // MusicBrainz's saved answers and their Clear (all Settings and the log's), and Connections' two pings (a user's -
    // the rows show only for whoever runs deadwax; Navidrome's row is `navidromeStatus`). Re-time saved lyrics is
    // `lyricsFetch` with `retime`, one album at a time
    public static let serverSettings = Endpoint(method: "GET", path: "/deadwax/settings", query: [])
    public static let saveServerSettings = Endpoint(method: "PUT", path: "/deadwax/settings", query: [])
    public static let savedAnswers = Endpoint(method: "GET", path: "/deadwax/settings/musicbrainz_cache", query: [])
    public static let clearSavedAnswers = Endpoint(method: "POST", path: "/deadwax/settings/musicbrainz_cache/clear", query: [])
    public static let pingMusicBrainz = Endpoint(method: "GET", path: "/deadwax/search_musicbrainz/ping", query: [])
    public static let pingSlskd = Endpoint(method: "GET", path: "/deadwax/monitor_slskd/ping", query: [])
    // The event log (Phase 8, slice 9 - notes/ios.md "The event log on the phone"): the lines deadwax kept since it
    // started, and the stream of them as they're logged - Settings and the log's both. The stream is read as it comes
    // (`DeadwaxClient.logStream`, through HTTPLineTransport), never as one answer
    public static let recentLog = Endpoint(method: "GET", path: "/deadwax/interface_logs/recent", query: [])
    public static let logStream = Endpoint(method: "GET", path: "/deadwax/interface_logs/interface_logs", query: ["after", "boot"])
    // Change password (Phase 8, slice 10 - notes/ios.md "Change password on the phone"): a user's route, for anyone
    // signed in through their own Navidrome account. Its answer's cookie is this phone's new sign-in
    public static let ownPassword = Endpoint(method: "POST", path: "/deadwax/me/password", query: [])
    // People (Phase 8, slice 11 - notes/ios.md "People on the phone"): People's state and Navidrome's accounts, its
    // unlock and lock, and its six writes - all People's (only Navidrome's admins hold it). A write is answered after
    // Navidrome has been asked, as the unlocked admin; a refusal of kind "locked" means the unlock ran out
    public static let people = Endpoint(method: "GET", path: "/deadwax/people", query: [])
    public static let unlockPeople = Endpoint(method: "POST", path: "/deadwax/people/unlock", query: [])
    public static let lockPeople = Endpoint(method: "POST", path: "/deadwax/people/lock", query: [])
    public static let createPerson = Endpoint(method: "POST", path: "/deadwax/people/create", query: [])
    public static let resetPassword = Endpoint(method: "POST", path: "/deadwax/people/{person_id}/password", query: [])
    public static let setAdmin = Endpoint(method: "POST", path: "/deadwax/people/{person_id}/admin", query: [])
    public static let removePerson = Endpoint(method: "POST", path: "/deadwax/people/{person_id}/remove", query: [])
    public static let forgetPerson = Endpoint(method: "POST", path: "/deadwax/people/forget", query: [])
    public static let savePermissions = Endpoint(method: "POST", path: "/deadwax/people/{person_id}/permissions", query: [])

    /// The levels spec's name for `levelAlbum`: the album's levels warmed before its first play.
    public static var warmLevels: Endpoint { levelAlbum }

    /// Edit album's search (Phase 8, slice 1): `fullySearch` asked as the web's editor asks it - no `quick`, so
    /// MusicBrainz's ten attempts, 3 s apart while it is busy, as an artist's facts are - given an artist's facts' time
    /// rather than the box's 20 s (tests/test_ios_contract.py holds it there).
    public static let editorSearchTimeout: Double = 60

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
        joinJob, savePreferences,
        libraryTracks,
        libraryAlbums, releases, release, retagPreview, retagApply, artFetch, libraryArt, queueIgnore, queueUnignore,
        tagsPreview, tagsApply, trackPicture,
        lyricsFetch, discArtFetch, libraryDiscArt,
        deletionSummary, deleteAlbum,
        libraryArtist, artistArt, artistImagesPreview, artistImagesApply, artistPicture, artistSearch,
        refilePreview, refileApply,
        queueSummary, queueReviewed,
        rescan, held, heldAdd, heldDismiss,
        serverSettings, saveServerSettings, savedAnswers, clearSavedAnswers, pingMusicBrainz, pingSlskd,
        recentLog, logStream,
        ownPassword,
        people, unlockPeople, lockPeople, createPerson, resetPassword, setAdmin, removePerson, forgetPerson,
        savePermissions,
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
    /// (RequestOverlays.unanswered); a join waits for the same release's lock as an enqueue or a move to the next source
    /// does, so it is given a move's time; and an Add to my library stars the pressing in Navidrome as you before it
    /// answers (my_library.py `_star_now`: up to six calls a folder, each through a client that gives up after 10 s a
    /// phase), so it is given time for one call that never answers on top of the rest (slice 3's review); and Album
    /// info's read of a folder's files opens every file there as it is asked (read_album_details: each file twice, and
    /// its pictures' sizes), which a box set on a disk that has to spin up can take a while over - nothing waits on it
    /// past AlbumInfoWords.settleSeconds, so it is given time to land late rather than fail -
    /// tests/test_ios_contract.py holds each above the server's: Album info's above the transport's own 8 s and the
    /// sheet's hold, and the route still with no bound of its own (nothing there to wait longer than). Edit album's
    /// (Phase 8, slice 1): the library's scan reads every folder whose mtime moved, and a first scan of a large library
    /// takes minutes, with no bound on the server; a group's pressings and one pressing's tracklist are MusicBrainz's
    /// pages with its ten attempts; a preview reads every file of the folder; an apply's worst case is 420 s - the
    /// cover fetched twice (the full size's 1200 px fallback, 55 s each), Navidrome's two baseline calls (5 s each)
    /// and then RENAME_WAIT_RANGE's 300 s on the timer when they can't be read (the wait on Navidrome's scan, 90 s and
    /// one last poll, is shorter) - with the plan, the writes and the move on top, so it is given 480; the cover alone
    /// that fetch twice and a write, so 120; the
    /// folder's cover a read of a file, or of the audio's pictures; the marks a row of SQLite -
    /// tests/test_ios_edit_contract.py holds each. Tags' (slice 2): a tag edit's preview reads every file named (up to
    /// MAX_EDITS), as a retag's preview does, so it is given a retag preview's 60; its apply reads them again and
    /// writes each changed one, then the scan's cache and the store index's row - no network, no wait, no bound of its
    /// own - so it is given twice that at least, and a minute more for each 1.2 GB of the files edited (EditWaits,
    /// review 16 Nov: a file whose new tags outgrow the room before its audio is written whole); a track's picture a
    /// read of one file - tests/test_ios_edit_parts_contract.py holds each. Artwork's and Lyrics' (slice 3): Get lyrics
    /// and Get CD art are given these at least, and as long as the album in hand needs (EditWaits, review 16 Nov) - Get
    /// lyrics asks LRCLIB for every track without lyrics, two at a time (src/lyrics.py CONCURRENCY), under each of up
    /// to two names, by its exact lookup and then a search (10 s to connect, 30 s to answer and 15 s of busy pauses
    /// apiece), so a disc of twelve tracks is given 23 minutes; Get CD art lists the release's images on the Cover Art
    /// Archive, else asks fanart.tv (25 s), then fetches each disc's picture - each Archive address three requests of
    /// 55 s through its redirects; one still longer is said as maybe finished (a Get only adds, so asking again is
    /// harmless); a CD art picture a read of one file. Delete's (slice 4): the summary walks the
    /// folder (every file under it, the scan's ignored ones too) and, with logins on, reads who holds it from SQLite -
    /// a folder's read, given a preview's 60; the delete removes the folder, then writes the saved scan and the store's
    /// rows - no network, no wait - so it is given a tag apply's 120. The artist tools' (slice 5, its waits worked
    /// out again after review, 16 Nov): one MusicBrainz request at its worst is ten attempts, each waiting out the
    /// rate limiter's 5 s window and then turned away and paused at its longest - a 429's 6 s, a failed connection's
    /// 6.5 and 7 at the last two - 111.5 s (ArtistWaits.musicBrainz). One name's
    /// summary reads the saved scan (a walk of the library where there is none), so it is given the scan's 120; a
    /// picture in their folder a read of one file; Artist images' preview the scan, who they are (a MusicBrainz search
    /// when neither the page nor the files say, then their lookup - two requests at their worst), TheAudioDB's,
    /// fanart.tv's and Wikidata's answers in turn (10 s to connect and 15 to answer each) and one more such request for
    /// each Commons picture's width - with five, 660 at least, and as long as the last look's Commons pictures need
    /// (ArtistWaits); one past it writes nothing, and is said with Look again; its apply the same lookup and sources
    /// again and then each picture chosen fetched in turn (10 s and 30 s a request, through Commons' two redirects), so
    /// it is given 600 at least and as long as the pictures in hand need; a candidate's picture through deadwax's relay
    /// answers within its 7 s deadline (PICTURE_DEADLINE_SECONDS), under the transport's own 8 s, so it has no entry;
    /// the search one MusicBrainz search, and an artist's facts one lookup, each given 120, past its 111.5; Move albums'
    /// preview the scan, who they are (a search and a lookup at their worst) and every file of the name's albums read,
    /// so 480; its apply the same and the album artist tag written, then each folder moved and the saved scan and the
    /// store index's rows written - no bound of its own - so it is given 600 at least, and a minute more for each 1.2 GB
    /// of the name's albums (ArtistWaits) - tests/test_ios_artist_manage.py holds each. Needs a look's (slice 6): the
    /// count reads the saved scan, never the disk - loaded from SQLite once after a restart - and waits for Navidrome's
    /// first listing at most LISTING_WAIT_SECONDS (3 s), so it is given ten times that; noting an album looked at is a
    /// row of SQLite, as the marks are, so 20 - tests/test_ios_needs_look.py holds both. Library care's (slice 7): a
    /// rescan drops the cache and reads every file of the library with no bound of its own, so it is given 300 s and one
    /// that never answers may have finished (said, and the library read again); In nobody's library and its writes are
    /// SQLite alone, each store call its own connection that may wait out the busy timeout (store._connect's 10 s)
    /// first: the list's two calls (the ledger, the open flags) 30, Add for them's five (the open flags, the album
    /// followed, the flag closed, the grants, the job's row) 60, Dismiss's two (the flag closed, the job's row) 30 -
    /// tests/test_ios_library_care.py holds them to the handlers. Server settings' (slice 8): the settings' read stats
    /// every path and probes slskd's folder (at most PROBE_VISITS folders walked) with no bound of its own, so it is
    /// given 30 and pinned there; the save writes each setting's row and reads the overrides back - each store call its
    /// own connection that may wait out the busy timeout (10 s) - then reads the settings as the GET does, so it is given
    /// 60 at least and 30 + 10 s a call (ServerSettings.saveWait); the saved answers' size is a SQLite count on the cache's
    /// one thread, 30, and Clear a DELETE and a VACUUM of the file there, 120 - no bound on the server for either, so both
    /// pinned; MusicBrainz's ping one request with MusicBrainz's ten attempts, 120, past its 111.5 (ArtistWaits); slskd's
    /// ping a call through slskd's own client with no timeout of its own, 30, pinned - tests/test_ios_server_settings.py
    /// holds each. The event log's (slice 9): the history is what deadwax holds in memory, answered at once - the
    /// transport's own 8; the stream is meant never to end, so its 45 is the most it may say nothing between two bytes
    /// (EventStream.silence), three of its 15 s keepalives - tests/test_ios_event_log.py holds both. Change password's
    /// (slice 10): the handler waits on its sign-in throttle's lock for the name (a sign-in holding it asks Navidrome
    /// once), the session read before it and three store calls in it (each may wait out SQLite's busy timeout, 10 s),
    /// and four calls to Navidrome, each its connection and its read (the native API's 10 s, its PUT's 30, the proof's
    /// getUser 10) - 180 s at worst, so it is given 240 - tests/test_ios_change_password.py holds it there. People's (slice
    /// 11): each route reads the session first, and every call it makes is a store call that may wait out SQLite's busy
    /// timeout (10 s) or a call to Navidrome, each its connection and its read (the native API's 10 s, its writes' 30,
    /// the Subsonic proof's 10) - the read is given 120 at least and 30 s more for each account listed last time; Unlock
    /// waits on the name's sign-in throttle (another unlock holding it: its login and a store call), so 120; each write
    /// waits on the one write lock for another write's worst (a reset's 130) before its own, so Make account, Reset,
    /// the admin flip and Remove 300 and Forget and the permissions 240 (PeopleWaits); Lock forgets the unlock in memory,
    /// the transport's own 8 - tests/test_ios_people.py holds each to the handlers.
    public static let timeouts: [Endpoint: Double] = [albumIndex: 30, autoEqSearch: 20, autoEqProfile: 20, libraryOwned: 30, fullySearch: 20, releaseGroup: 60, searchArtists: 20, searchSongs: 20, artistFacts: 120, discography: 60, jobs: 20, cancelJob: 30, retryJob: 60, retryJobSame: 30, clearJobs: 30, storeState: 20, findCandidates: 300, enqueue: 300, joinJob: 60, libraryAdd: 60, libraryTracks: 30, libraryAlbums: 120, releases: 60, release: 60, retagPreview: 60, retagApply: 480, artFetch: 120, libraryArt: 30, queueIgnore: 20, queueUnignore: 20, tagsPreview: 60, tagsApply: 120, trackPicture: 30, lyricsFetch: 600, discArtFetch: 360, libraryDiscArt: 30, deletionSummary: 60, deleteAlbum: 120, libraryArtist: 120, artistArt: 30, artistImagesPreview: 660, artistImagesApply: 600, artistSearch: 120, refilePreview: 480, refileApply: 600, queueSummary: 30, queueReviewed: 20, rescan: 300, held: 30, heldAdd: 60, heldDismiss: 30, serverSettings: 30, saveServerSettings: 60, savedAnswers: 30, clearSavedAnswers: 120, pingMusicBrainz: 120, pingSlskd: 30, logStream: 45, ownPassword: 240, people: 120, unlockPeople: 120, createPerson: 300, resetPassword: 300, setAdmin: 300, removePerson: 300, forgetPerson: 240, savePermissions: 240]
}

/// The Cover Art Archive's thumbnail sizes the app asks deadwax's relay for (`Routes.archiveCover`'s `size`, which takes
/// 250, 500 or 1200 - the contract test checks each).
public enum ArchiveCoverSize {
    /// A list's row.
    public static let row = 250
    /// The album you don't have's own cover, and Edit album's Compare covers full screen.
    public static let hero = 1200
    /// (Phase 8, slice 1) Edit album's Compare covers, beside the folder's (phase8-managing.md 3.3).
    public static let compare = 500
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
