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
    /// own - so it is given twice that; a track's picture a read of one file - tests/test_ios_edit_parts_contract.py
    /// holds each. Artwork's and Lyrics' (slice 3): Get lyrics asks LRCLIB for every track without lyrics, two at a time
    /// (src/lyrics.py CONCURRENCY), each by its exact lookup and then a search (10 s to connect and 30 s to answer
    /// apiece), so a disc of twelve tracks takes 480 s at worst - given 600, and one still longer is said as maybe
    /// finished (Get lyrics only adds, so asking again is harmless); Get CD art lists the release's images on the
    /// Cover Art Archive (55 s), else asks fanart.tv (25 s), then fetches each disc's picture (55 s) - a box of four
    /// discs 300 s at worst, given 360; a CD art picture a read of one file.
    public static let timeouts: [Endpoint: Double] = [albumIndex: 30, autoEqSearch: 20, autoEqProfile: 20, libraryOwned: 30, fullySearch: 20, releaseGroup: 60, searchArtists: 20, searchSongs: 20, artistFacts: 60, discography: 60, jobs: 20, cancelJob: 30, retryJob: 60, retryJobSame: 30, clearJobs: 30, storeState: 20, findCandidates: 300, enqueue: 300, joinJob: 60, libraryAdd: 60, libraryTracks: 30, libraryAlbums: 120, releases: 60, release: 60, retagPreview: 60, retagApply: 480, artFetch: 120, libraryArt: 30, queueIgnore: 20, queueUnignore: 20, tagsPreview: 60, tagsApply: 120, trackPicture: 30, lyricsFetch: 600, discArtFetch: 360, libraryDiscArt: 30]
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
