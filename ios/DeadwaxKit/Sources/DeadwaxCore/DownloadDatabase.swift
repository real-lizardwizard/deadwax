import CSQLite
import Foundation

/// The download store's database (spec 8.2): one person's downloads on this phone, in SQLite - `PRAGMA user_version`,
/// WAL. A state change per song changes a row, where a JSON ledger would rewrite every song's many times over.
///
/// - `album`: the album's answer (`GET /navidrome/albums/{id}`'s body as it came), for every album with a song asked
///   for or here - so a downloaded album's page draws from the phone, online or not.
/// - `loudness`: its loudness answer, so it plays at the same level offline.
/// - `song`: one row per song asked for or here (`DownloadRecord`). Progress is never kept: it is read from the tasks.
/// - `origin`: why each song is wanted - a song with none left is removed.
/// - `play_pending`, `queue_pending`: plays kept until deadwax answers, and the queue this phone last saved or took -
///   a save deadwax hasn't answered among them (7.5, 7.6; QueueKept).
/// - `meta`: the store's own facts (`force_quit_at`).
/// - `lyrics` (version 2, app 0.4): each downloaded song's lyrics answer (`GET /navidrome/lyrics/{song_id}`'s body as it
///   came, none included) and its ETag, so they show offline (notes/app-lyrics.md 4.7). Kept only for a song in `song`,
///   and gone with its row whichever way the row goes - the trigger `song_lyrics_go`.
/// - `start_pending` (version 3, app 0.8): the songs this phone started that deadwax hasn't taken yet - its play history
///   (PlayHistory.swift), each start's moment, song (HistorySong's JSON), queue and entry, and whether it has counted -
///   sent oldest first, before the kept plays. Like the plays, not downloads: Remove All leaves them. The newest page of
///   the person's history deadwax answered is kept in `meta` (`PlayHistory.keptPageKey`), so recent plays show offline.
/// - `library` (version 4, Phase 3): your library as this phone follows it (phase3-autodownload.md 2.1, 5.1) - each
///   album deadwax last listed, its place, the list's entry for it, its songs as the fill reads them once read, and its
///   marks (missing since, removed here, kept off); the list's ETag, scope and held reason in `meta`. Not downloads:
///   Remove All leaves it. Version 5 (Phase 3, after the review) adds `left_songs`: the songs a read found had left the
///   album, each with when (FollowedAlbum.left).
/// - `playlist` (version 6, Phase 4 slice 3): the downloaded playlists (phase4-library.md 2.5) - each one's last answer
///   (`GET /navidrome/playlists/{id}`'s body as it came), when it was read, when it went missing, the songs a read found
///   had left it (KeptPlaylist.left) and when it was downloaded - so it opens and plays offline, and is kept in step.
///   Downloads: Remove All takes it with the songs.
///
/// Not thread-safe: one owner (the App's DownloadStore) calls it from one place at a time.
public final class DownloadDatabase {
    /// The schema's version (`PRAGMA user_version`): 1, Phase 2's (app 0.3); 2, the lyrics (app 0.4); 3, the play
    /// history's starts (app 0.8); 4, your library followed (Phase 3); 5, the songs that left its albums (Phase 3); 6,
    /// the downloaded playlists (Phase 4).
    public static let version = 6

    /// SQLite said no: its own words, for whoever runs deadwax.
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let words: String
        public var description: String { words }
    }

    private var db: OpaquePointer?

    /// Opens (or makes) the database at `path` and brings its schema up to `version`.
    public convenience init(path: String) throws {
        try self.init(path: path, upTo: Self.version)
    }

    /// ...up to `target` - an older version's file, for the tests of a migration from it.
    init(path: String, upTo target: Int) throws {
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard opened == SQLITE_OK, let handle else {
            let words = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite couldn't open \(path) (\(opened))."
            sqlite3_close(handle)
            throw Failure(words: words)
        }
        db = handle
        sqlite3_busy_timeout(handle, 2_000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try migrate(to: target)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: the schema

    static let schema: [String] = [
        """
        CREATE TABLE album (
          id TEXT PRIMARY KEY,
          json BLOB NOT NULL,
          cover TEXT,
          fetched_at INTEGER NOT NULL)
        """,
        """
        CREATE TABLE loudness (
          album_id TEXT PRIMARY KEY,
          json BLOB NOT NULL,
          algorithm INTEGER NOT NULL,
          fetched_at INTEGER NOT NULL)
        """,
        """
        CREATE TABLE song (
          id TEXT PRIMARY KEY,
          album_id TEXT NOT NULL,
          disc INTEGER, track INTEGER,
          format TEXT NOT NULL,
          suffix TEXT NOT NULL,
          size_expected INTEGER,
          duration REAL,
          state TEXT NOT NULL,
          wait TEXT,
          check_state TEXT,
          bytes INTEGER,
          flac_rate INTEGER, flac_bits INTEGER, flac_md5 TEXT,
          tries INTEGER NOT NULL DEFAULT 0,
          failure TEXT,
          failure_raw TEXT,
          task TEXT,
          resume BLOB,
          wanted_at INTEGER NOT NULL,
          done_at INTEGER)
        """,
        "CREATE INDEX song_album ON song (album_id)",
        """
        CREATE TABLE origin (
          song_id TEXT NOT NULL,
          origin TEXT NOT NULL,
          at INTEGER NOT NULL,
          PRIMARY KEY (song_id, origin))
        """,
        "CREATE TABLE play_pending (id INTEGER PRIMARY KEY, song_id TEXT NOT NULL, time_ms INTEGER NOT NULL)",
        """
        CREATE TABLE queue_pending (one INTEGER PRIMARY KEY CHECK (one = 1), kind TEXT NOT NULL, body BLOB NOT NULL,
                                    kept_at INTEGER NOT NULL)
        """,
        "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)",
    ]

    /// Version 2's (app 0.4): a downloaded song's lyrics, and the trigger that takes them with the song's row - by
    /// `deleteSong`, by `removeOrigins` taking a song's last origin, by `removeAll`, and by any way added later, in the
    /// same transaction. (`put`'s INSERT OR REPLACE of a song already there fires no delete trigger - SQLite's
    /// recursive_triggers is off - so a song's row written again keeps its lyrics.)
    static let lyricsSchema: [String] = [
        """
        CREATE TABLE lyrics (
          song_id TEXT PRIMARY KEY,
          json BLOB NOT NULL,
          etag TEXT,
          fetched_at INTEGER NOT NULL)
        """,
        """
        CREATE TRIGGER song_lyrics_go AFTER DELETE ON song
          BEGIN DELETE FROM lyrics WHERE song_id = OLD.id; END
        """,
    ]

    /// Version 3's (app 0.8): the starts not yet taken - `song_id` beside the song's JSON, for a counted play to find its
    /// start by (`countStart`); `counted` 0 or 1.
    static let historySchema: [String] = [
        """
        CREATE TABLE start_pending (
          id INTEGER PRIMARY KEY,
          at INTEGER NOT NULL,
          song_id TEXT NOT NULL,
          song BLOB NOT NULL,
          counted INTEGER NOT NULL DEFAULT 0,
          queue TEXT,
          entry INTEGER)
        """,
        "CREATE INDEX start_pending_at ON start_pending (at, id)",
    ]

    /// Version 4's (Phase 3): your library as this phone follows it - `entry` the list's IndexAlbum JSON, `songs` the
    /// FollowedSong JSON array (NULL until read), the marks in ms.
    static let librarySchema: [String] = [
        """
        CREATE TABLE library (
          album_id TEXT PRIMARY KEY,
          position INTEGER NOT NULL,
          entry BLOB NOT NULL,
          songs BLOB,
          read_at INTEGER,
          missing_since INTEGER,
          removed_here INTEGER,
          kept_off INTEGER)
        """,
    ]

    /// Version 5's (Phase 3, after the review): the songs a read of the album no longer had - FollowedAlbum.left's JSON
    /// (song id to ms), NULL for none.
    static let leftSchema: [String] = ["ALTER TABLE library ADD COLUMN left_songs BLOB"]

    /// Version 6's (Phase 4, slice 3): the downloaded playlists - `json` the answer's body, `left_songs` KeptPlaylist.left's
    /// JSON (song id to ms, NULL for none), the times in ms.
    static let playlistSchema: [String] = [
        """
        CREATE TABLE playlist (
          id TEXT PRIMARY KEY,
          json BLOB NOT NULL,
          read_at INTEGER NOT NULL,
          missing_since INTEGER,
          left_songs BLOB,
          asked_at INTEGER NOT NULL)
        """,
    ]

    /// The schema brought from the file's version up to `target` (the newest, but in a test), in one transaction: made
    /// from nothing (version 0), or an older file - every row kept - given what came after it: a version-1 file (Phase
    /// 2's) the lyrics table, a version-2 file the starts' table, and so on - a version-5 file the playlists'.
    private func migrate(to target: Int) throws {
        let current = try integer("PRAGMA user_version") ?? 0
        guard current < target else { return }
        try transaction {
            if current < 1 {
                for statement in Self.schema { try execute(statement) }
            }
            if current < 2, target >= 2 {
                for statement in Self.lyricsSchema { try execute(statement) }
            }
            if current < 3, target >= 3 {
                for statement in Self.historySchema { try execute(statement) }
            }
            if current < 4, target >= 4 {
                for statement in Self.librarySchema { try execute(statement) }
            }
            if current < 5, target >= 5 {
                for statement in Self.leftSchema { try execute(statement) }
            }
            if current < 6, target >= 6 {
                for statement in Self.playlistSchema { try execute(statement) }
            }
            try execute("PRAGMA user_version = \(target)")
        }
    }

    /// The schema's version as the file has it.
    public func userVersion() throws -> Int { Int(try integer("PRAGMA user_version") ?? 0) }

    // MARK: songs

    static let songColumns = """
        id, album_id, disc, track, format, suffix, size_expected, duration, state, wait, check_state, bytes, \
        flac_rate, flac_bits, flac_md5, tries, failure, failure_raw, task, resume, wanted_at, done_at
        """

    /// Every song asked for or here.
    public func songs() throws -> [DownloadRecord] {
        try query("SELECT \(Self.songColumns) FROM song ORDER BY wanted_at, album_id, disc, track, id", [], Self.record)
    }

    public func song(_ id: String) throws -> DownloadRecord? {
        try query("SELECT \(Self.songColumns) FROM song WHERE id = ?", [.text(id)], Self.record).first
    }

    /// Writes `record` whole (made, or replaced).
    public func put(_ record: DownloadRecord) throws {
        let r = record
        try run("INSERT OR REPLACE INTO song (\(Self.songColumns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
            .text(r.id), .text(r.albumID), .int(r.disc.map(Int64.init)), .int(r.track.map(Int64.init)), .text(r.format),
            .text(r.suffix), .int(r.sizeExpected), .real(r.duration), .text(r.state.rawValue), .text(r.wait?.rawValue),
            .text(r.check?.rawValue), .int(r.bytes), .int(r.flac.map { Int64($0.rate) }), .int(r.flac.map { Int64($0.bits) }),
            .text(r.flac?.md5), .int(Int64(r.tries)), .text(r.failure?.code), .text(r.failure?.raw), .text(r.task),
            .blob(r.resume), .int(r.wantedAt), .int(r.doneAt),
        ])
    }

    /// The song's row and its origins gone - and its lyrics, by the trigger.
    public func deleteSong(_ id: String) throws {
        try transaction {
            try run("DELETE FROM origin WHERE song_id = ?", [.text(id)])
            try run("DELETE FROM song WHERE id = ?", [.text(id)])
        }
    }

    static func record(_ row: Row) -> DownloadRecord? {
        guard let id = row.text(0), let album = row.text(1), let format = row.text(4), let suffix = row.text(5),
              let state = row.text(8).flatMap(StoredState.init(rawValue:)), let wanted = row.int(20) else { return nil }
        var flac: FLACFacts?
        if let rate = row.int(12), let bits = row.int(13), let md5 = row.text(14) {
            flac = FLACFacts(rate: Int(rate), bits: Int(bits), md5: md5)
        }
        return DownloadRecord(
            id: id, albumID: album, disc: row.int(2).map(Int.init), track: row.int(3).map(Int.init), format: format,
            suffix: suffix, sizeExpected: row.int(6), duration: row.real(7), state: state,
            wait: row.text(9).flatMap(DownloadWait.init(rawValue:)), check: row.text(10).flatMap(CopyCheck.init(rawValue:)),
            bytes: row.int(11), flac: flac, tries: Int(row.int(15) ?? 0),
            failure: row.text(16).flatMap { DownloadFailure(code: $0, raw: row.text(17)) }, task: row.text(18),
            resume: row.blob(19), wantedAt: wanted, doneAt: row.int(21))
    }

    // MARK: origins

    /// `origin` added to `song` (kept with its first `at`).
    public func addOrigin(_ origin: DownloadOrigin, song: String, at: Int64) throws {
        try run("INSERT OR IGNORE INTO origin (song_id, origin, at) VALUES (?, ?, ?)", [.text(song), .text(origin.raw), .int(at)])
    }

    /// Every song's origins.
    public func origins() throws -> [String: Set<DownloadOrigin>] {
        var all: [String: Set<DownloadOrigin>] = [:]
        let rows: [(String, String)] = try query("SELECT song_id, origin FROM origin") { row in
            guard let song = row.text(0), let origin = row.text(1) else { return nil }
            return (song, origin)
        }
        for (song, origin) in rows { all[song, default: []].insert(DownloadOrigin(raw: origin)) }
        return all
    }

    /// `removed` taken from `songs`' origins; the songs left with none are deleted (their rows and origins) - their ids
    /// returned, for their files to go too.
    @discardableResult
    public func removeOrigins(_ removed: Set<DownloadOrigin>, songs: [String]) throws -> [String] {
        var gone: [String] = []
        try transaction {
            for song in songs {
                for origin in removed { try run("DELETE FROM origin WHERE song_id = ? AND origin = ?", [.text(song), .text(origin.raw)]) }
                let left = try integer("SELECT COUNT(*) FROM origin WHERE song_id = ?", [.text(song)]) ?? 0
                if left == 0 {
                    try run("DELETE FROM song WHERE id = ?", [.text(song)])
                    gone.append(song)
                }
            }
        }
        return gone
    }

    // MARK: albums and their loudness

    /// An album's answer as it is kept.
    public struct KeptAnswer: Sendable, Equatable {
        public let id: String
        public let json: Data
        /// covers/<file>, once kept (for an album); the loudness's algorithm (for its loudness).
        public let cover: String?
        public let algorithm: Int?
        public let fetchedAt: Int64
    }

    public func putAlbum(id: String, json: Data, fetchedAt: Int64) throws {
        try run("""
            INSERT INTO album (id, json, fetched_at) VALUES (?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at
            """, [.text(id), .blob(json), .int(fetchedAt)])
    }

    public func setCover(album: String, file: String?) throws {
        try run("UPDATE album SET cover = ? WHERE id = ?", [.text(file), .text(album)])
    }

    public func albums() throws -> [KeptAnswer] {
        try query("SELECT id, json, cover, fetched_at FROM album ORDER BY id") { row in
            guard let id = row.text(0), let json = row.blob(1) else { return nil }
            return KeptAnswer(id: id, json: json, cover: row.text(2), algorithm: nil, fetchedAt: row.int(3) ?? 0)
        }
    }

    /// The album's answer and its loudness gone.
    public func deleteAlbum(_ id: String) throws {
        try transaction {
            try run("DELETE FROM album WHERE id = ?", [.text(id)])
            try run("DELETE FROM loudness WHERE album_id = ?", [.text(id)])
        }
    }

    public func putLoudness(album: String, json: Data, algorithm: Int, fetchedAt: Int64) throws {
        try run("INSERT OR REPLACE INTO loudness (album_id, json, algorithm, fetched_at) VALUES (?, ?, ?, ?)",
                [.text(album), .blob(json), .int(Int64(algorithm)), .int(fetchedAt)])
    }

    public func loudness() throws -> [KeptAnswer] {
        try query("SELECT album_id, json, algorithm, fetched_at FROM loudness ORDER BY album_id") { row in
            guard let id = row.text(0), let json = row.blob(1) else { return nil }
            return KeptAnswer(id: id, json: json, cover: nil, algorithm: row.int(2).map(Int.init), fetchedAt: row.int(3) ?? 0)
        }
    }

    // MARK: lyrics (version 2, notes/app-lyrics.md 4.7)

    /// A downloaded song's lyrics answer as it is kept.
    public struct KeptLyrics: Sendable, Equatable {
        public let songID: String
        /// The route's body as it came - none for the song included.
        public let json: Data
        /// Its ETag, for the next ask to be a 304.
        public let etag: String?
        /// ms since 1970.
        public let fetchedAt: Int64
    }

    /// The song's lyrics answer kept (made, or replaced) - only while the song has a row: false, and nothing kept, for
    /// a song not in the store (removed while its ask was on its way), so no lyrics are ever left without their song.
    @discardableResult
    public func putLyrics(song: String, json: Data, etag: String?, fetchedAt: Int64) throws -> Bool {
        // the SELECT's WHERE keeps SQLite from reading ON CONFLICT's ON as a join's
        try run("""
            INSERT INTO lyrics (song_id, json, etag, fetched_at)
              SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM song WHERE id = ?)
            ON CONFLICT (song_id) DO UPDATE SET json = excluded.json, etag = excluded.etag, fetched_at = excluded.fetched_at
            """, [.text(song), .blob(json), .text(etag), .int(fetchedAt), .text(song)])
        return sqlite3_changes(db) > 0
    }

    /// The song's lyrics answer, when one is kept.
    public func lyrics(_ song: String) throws -> KeptLyrics? {
        // the closure's type said, for ios.yml's older Swift (as keptQueue's)
        try query("SELECT song_id, json, etag, fetched_at FROM lyrics WHERE song_id = ?", [.text(song)]) { (row: Row) -> KeptLyrics? in
            guard let id = row.text(0), let json = row.blob(1) else { return nil }
            return KeptLyrics(songID: id, json: json, etag: row.text(2), fetchedAt: row.int(3) ?? 0)
        }.first
    }

    /// The songs with lyrics kept - the backfill's "which done songs have none".
    public func lyricsSongs() throws -> Set<String> {
        Set(try query("SELECT song_id FROM lyrics") { (row: Row) -> String? in row.text(0) })
    }

    // MARK: plays and the queue kept for later (7.6)

    /// A play deadwax couldn't be told of, with when its listen began (ms).
    public struct KeptPlay: Sendable, Equatable {
        public let id: Int64
        public let songID: String
        public let timeMs: Int64
    }

    @discardableResult
    public func keepPlay(songID: String, timeMs: Int64) throws -> Int64 {
        try run("INSERT INTO play_pending (song_id, time_ms) VALUES (?, ?)", [.text(songID), .int(timeMs)])
        return sqlite3_last_insert_rowid(db)
    }

    /// The plays kept, oldest first.
    public func keptPlays() throws -> [KeptPlay] {
        try query("SELECT id, song_id, time_ms FROM play_pending ORDER BY time_ms, id") { row in
            guard let id = row.int(0), let song = row.text(1), let time = row.int(2) else { return nil }
            return KeptPlay(id: id, songID: song, timeMs: time)
        }
    }

    public func forgetPlay(_ id: Int64) throws {
        try run("DELETE FROM play_pending WHERE id = ?", [.int(id)])
    }

    // MARK: starts not yet taken (version 3, app 0.8)

    /// A start kept until deadwax takes it, with its row's id.
    public struct KeptStart: Sendable, Equatable {
        public let id: Int64
        public let played: Played
    }

    /// A start kept (its `counted` as it is now). The row's id.
    @discardableResult
    public func keepStart(_ played: Played) throws -> Int64 {
        let song: Data
        do {
            song = try JSONEncoder().encode(HistorySong(played.song))
        } catch {
            throw Failure(words: "The start of \(played.song.id) couldn't be written (\(error)).")
        }
        try run("INSERT INTO start_pending (at, song_id, song, counted, queue, entry) VALUES (?, ?, ?, ?, ?, ?)",
                [.int(played.at), .text(played.song.id), .blob(song), .int(played.counted ? 1 : 0),
                 .text(played.queue), .int(played.entry.map { Int64($0) })])
        return sqlite3_last_insert_rowid(db)
    }

    /// The starts kept, oldest first - at most `limit` (a batch), or every one. A row whose song can't be read is left
    /// out (and never sent).
    public func keptStarts(limit: Int? = nil) throws -> [KeptStart] {
        let bounded = limit.map { " LIMIT \(max(0, $0))" } ?? ""
        return try query("SELECT id, at, song, counted, queue, entry FROM start_pending ORDER BY at, id\(bounded)") { (row: Row) -> KeptStart? in
            guard let id = row.int(0), let at = row.int(1), let data = row.blob(2),
                  let song = try? JSONDecoder().decode(HistorySong.self, from: data) else { return nil }
            let entry = row.int(5).flatMap { Int(exactly: $0) }
            return KeptStart(id: id, played: Played(at: at, counted: (row.int(3) ?? 0) != 0, queue: row.text(4),
                                                    entry: entry, song: song.track))
        }
    }

    /// How many starts are kept.
    public func keptStartCount() throws -> Int {
        Int(try integer("SELECT COUNT(*) FROM start_pending") ?? 0)
    }

    /// Starts deadwax took (or will never take), forgotten - each only while it is as it was read: one counted since
    /// (a play counted while its batch was on its way, whose scrobble may have reached deadwax before the batch did)
    /// stays, to go again counted - deadwax ORs it in. How many were forgotten.
    @discardableResult
    public func forgetStarts(_ sent: [KeptStart]) throws -> Int {
        guard !sent.isEmpty else { return 0 }
        var gone = 0
        try transaction {
            for start in sent {
                try run("DELETE FROM start_pending WHERE id = ? AND (counted != 0) = ?",
                        [.int(start.id), .int(start.played.counted ? 1 : 0)])
                gone += Int(sqlite3_changes(db))
            }
        }
        return gone
    }

    /// A counted play's start, if it is still kept, marked counted - it goes with it (deadwax's insert ORs it in).
    public func countStart(songID: String, at: Int64) throws {
        try run("UPDATE start_pending SET counted = 1 WHERE song_id = ? AND at = ?", [.text(songID), .int(at)])
    }

    /// The queue this phone last saved or took, and whether deadwax has it: one row, replaced by each (QueueKept
    /// reads and writes it - `keptResume`, `keepResume`).
    public struct PendingQueue: Sendable, Equatable {
        /// Whether deadwax has it: QueueKept's `unsent` or `sent`.
        public let kind: String
        public let body: Data
        public let keptAt: Int64
    }

    public func keepQueue(kind: String, body: Data, at: Int64) throws {
        try run("INSERT OR REPLACE INTO queue_pending (one, kind, body, kept_at) VALUES (1, ?, ?, ?)",
                [.text(kind), .blob(body), .int(at)])
    }

    public func keptQueue() throws -> PendingQueue? {
        // the closure's type said: Xcode 26.6's Swift (ios.yml's runner) can't infer T from a multi-statement closure
        // whose result is only read through `.first`, as 6.3 can
        try query("SELECT kind, body, kept_at FROM queue_pending WHERE one = 1") { (row: Row) -> PendingQueue? in
            guard let kind = row.text(0), let body = row.blob(1) else { return nil }
            return PendingQueue(kind: kind, body: body, keptAt: row.int(2) ?? 0)
        }.first
    }

    public func forgetQueue() throws {
        try run("DELETE FROM queue_pending")
    }

    // MARK: your library followed (version 4, phase3-autodownload.md 2.1, 5.1)

    /// The meta keys the library's facts are kept under: the scope its list is of, that list's ETag, why its absences
    /// weren't believed (`LibraryFollow.Held.raw`), when the last check that answered began (ms), and how long the
    /// first read of every album's songs took (Debug's, slice 1: "<seconds> <albums>").
    public static let libraryScopeKey = "library_scope"
    public static let libraryETagKey = "library_etag"
    public static let libraryHeldKey = "library_held"
    public static let libraryCheckedKey = "library_checked_at"
    public static let libraryFirstReadKey = "library_first_read"
    /// (slice 2) You said Remove to the empty list's or the large drop's question: such a list is believed until a list
    /// that needs no believing comes ("1").
    public static let libraryBelieveKey = "library_believe"
    /// (slice 2) You said Keep Them: the question is put away until a list is believed again ("1").
    public static let libraryHeldKeptKey = "library_held_kept"
    /// (slice 2) The albums checks removed whose library downloads haven't been let go yet (ids, one per line) - kept with
    /// the list that removed them, so a quit between the two loses nothing.
    public static let libraryRemovedKey = "library_removed"
    static let libraryKeys = [libraryScopeKey, libraryETagKey, libraryHeldKey, libraryCheckedKey, libraryFirstReadKey,
                              libraryBelieveKey, libraryHeldKeptKey, libraryRemovedKey]

    /// Your library as this phone follows it, in its place. A row whose entry can't be read is left out (the next list
    /// adds it again); songs that can't be read are unread.
    public func library() throws -> [FollowedAlbum] {
        let decoder = JSONDecoder()
        return try query("""
            SELECT album_id, position, entry, songs, read_at, missing_since, removed_here, kept_off, left_songs
            FROM library ORDER BY position, album_id
            """) { row in
            guard let id = row.text(0), let entry = row.blob(2),
                  let album = try? decoder.decode(IndexAlbum.self, from: entry), album.id == id else { return nil }
            let songs = row.blob(3).flatMap { try? decoder.decode([FollowedSong].self, from: $0) }
            let left = row.blob(8).flatMap { try? decoder.decode([String: Int64].self, from: $0) } ?? [:]
            return FollowedAlbum(album: album, position: Int(row.int(1) ?? 0), songs: songs,
                                 readAt: songs == nil ? nil : row.int(4), missingSince: row.int(5),
                                 removedHere: row.int(6), keptOff: row.int(7), left: left)
        }
    }

    /// `albums` as the library, `old` being the library as last read: the rows of albums no longer in it deleted, and
    /// only the rows that differ written - a 200 that moved one album's place rewrites the rows after it, not every
    /// song list. One transaction.
    public func putLibrary(_ albums: [FollowedAlbum], replacing old: [FollowedAlbum]) throws {
        var before: [String: FollowedAlbum] = [:]
        for entry in old { before[entry.id] = entry }
        let ids = Set(albums.map(\.id))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try transaction {
            for id in before.keys where !ids.contains(id) {
                try run("DELETE FROM library WHERE album_id = ?", [.text(id)])
            }
            for entry in albums where before[entry.id] != entry {
                let songs = try entry.songs.map { try encoder.encode($0) }
                let left: Data? = try entry.left.isEmpty ? nil : encoder.encode(entry.left)
                try run("""
                    INSERT OR REPLACE INTO library
                      (album_id, position, entry, songs, read_at, missing_since, removed_here, kept_off, left_songs)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.text(entry.id), .int(Int64(entry.position)), .blob(try encoder.encode(entry.album)),
                          .blob(songs), .int(songs == nil ? nil : entry.readAt), .int(entry.missingSince),
                          .int(entry.removedHere), .int(entry.keptOff), .blob(left)])
            }
        }
    }

    /// An album's songs, read at `at`, and the songs found to have left it (LibraryFollow.read) - kept only while the
    /// album is in the library. Whether it was.
    @discardableResult
    public func setLibrarySongs(album: String, songs: [FollowedSong], left: [String: Int64] = [:], at: Int64) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let marks: Data? = try left.isEmpty ? nil : encoder.encode(left)
        try run("UPDATE library SET songs = ?, read_at = ?, left_songs = ? WHERE album_id = ?",
                [.blob(try encoder.encode(songs)), .int(at), .blob(marks), .text(album)])
        return sqlite3_changes(db) > 0
    }

    /// Remove from my library answered in this app at `at` (ms): the next list without it removes it at once. Whether
    /// the album was in the library.
    @discardableResult
    public func setRemovedHere(album: String, at: Int64) throws -> Bool {
        try run("UPDATE library SET removed_here = ? WHERE album_id = ?", [.int(at), .text(album)])
        return sqlite3_changes(db) > 0
    }

    /// (slice 2) Remove Download on an album of the library at `at` (ms): left off this phone - or nil, downloaded again.
    /// Whether the album was in the library.
    @discardableResult
    public func setKeptOff(album: String, at: Int64?) throws -> Bool {
        try run("UPDATE library SET kept_off = ? WHERE album_id = ?", [.int(at), .text(album)])
        return sqlite3_changes(db) > 0
    }

    /// The library forgotten: every row, and its meta - followed again from nothing.
    public func forgetLibrary() throws {
        try transaction {
            try execute("DELETE FROM library")
            for key in Self.libraryKeys {
                try setMeta(key, nil)
            }
        }
    }

    // MARK: downloaded playlists (version 6, phase4-library.md 2.5)

    /// The downloaded playlists, in the order they were downloaded. A row's answer that can't be read is kept unread
    /// (`answer` nil - read again; nothing asked or taken by it), never left out: its songs' origin would read as an
    /// orphan's. Marks that can't be read are none.
    public func playlists() throws -> [KeptPlaylist] {
        let decoder = JSONDecoder()
        return try query("""
            SELECT id, json, read_at, missing_since, left_songs, asked_at FROM playlist ORDER BY asked_at, id
            """) { row in
            guard let id = row.text(0), let json = row.blob(1) else { return nil }
            let answer = (try? decoder.decode(PlaylistWithSongs.self, from: json))
                .flatMap { (read: PlaylistWithSongs) -> PlaylistWithSongs? in read.playlist.id == id ? read : nil }
            let left = row.blob(4).flatMap { (data: Data) -> [String: Int64]? in
                try? decoder.decode([String: Int64].self, from: data)
            } ?? [:]
            return KeptPlaylist(id: id, answer: answer, body: json, readAt: row.int(2) ?? 0, missingSince: row.int(3),
                                left: left, askedAt: row.int(5) ?? 0)
        }
    }

    /// A downloaded playlist written whole (made, or replaced).
    public func putPlaylist(_ kept: KeptPlaylist) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let left: Data? = try kept.left.isEmpty ? nil : encoder.encode(kept.left)
        try run("""
            INSERT OR REPLACE INTO playlist (id, json, read_at, missing_since, left_songs, asked_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, [.text(kept.id), .blob(kept.body), .int(kept.readAt), .int(kept.missingSince), .blob(left),
                  .int(kept.askedAt)])
    }

    /// A downloaded playlist's row gone (its songs' origin is taken after it, by removeOrigins).
    public func deletePlaylist(_ id: String) throws {
        try run("DELETE FROM playlist WHERE id = ?", [.text(id)])
    }

    // MARK: meta

    public func meta(_ key: String) throws -> String? {
        try query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) }.first
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [.text(key), .text(value)])
        } else {
            try run("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }

    // MARK: everything

    /// Remove All Downloads: every song, origin, album and loudness, every downloaded playlist (Phase 4), and (by the
    /// trigger) every song's lyrics - the plays, the starts, the queue save and the library followed kept (they aren't
    /// downloads).
    public func removeAll() throws {
        try transaction {
            for table in ["origin", "song", "album", "loudness", "playlist"] { try execute("DELETE FROM \(table)") }
        }
    }

    /// `body` in one transaction: all of it, or none.
    public func transaction(_ body: () throws -> Void) throws {
        if sqlite3_get_autocommit(db) == 0 {
            // already inside one: part of it
            try body()
            return
        }
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: SQLite

    /// A value bound to a statement's `?`.
    enum Value {
        case text(String?)
        case int(Int64?)
        case real(Double?)
        case blob(Data?)
    }

    /// A result row.
    struct Row {
        let statement: OpaquePointer

        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

        func text(_ column: Int32) -> String? {
            guard !isNull(column), let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }

        func int(_ column: Int32) -> Int64? { isNull(column) ? nil : sqlite3_column_int64(statement, column) }

        func real(_ column: Int32) -> Double? { isNull(column) ? nil : sqlite3_column_double(statement, column) }

        func blob(_ column: Int32) -> Data? {
            guard !isNull(column) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: pointer, count: count)
        }
    }

    private func failure(_ what: String) -> Failure {
        Failure(words: "\(what): \(String(cString: sqlite3_errmsg(db)))")
    }

    /// Internal (not private) for the migration tests, which write an older version's rows as it wrote them.
    func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let words = message.map { String(cString: $0) } ?? "SQLite said no"
            sqlite3_free(message)
            throw Failure(words: words)
        }
    }

    /// SQLite's own "copy it now" destructor (SQLITE_TRANSIENT, a macro Swift can't import).
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure("Preparing a query")
        }
        for (index, value) in values.enumerated() {
            let at = Int32(index + 1)
            let bound: Int32
            switch value {
            case .text(let text?): bound = sqlite3_bind_text(statement, at, text, -1, Self.transient)
            case .int(let number?): bound = sqlite3_bind_int64(statement, at, number)
            case .real(let number?): bound = sqlite3_bind_double(statement, at, number)
            case .blob(let data?):
                bound = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, at, bytes.baseAddress ?? UnsafeRawPointer(bitPattern: 1), Int32(bytes.count), Self.transient)
                }
            default: bound = sqlite3_bind_null(statement, at)
            }
            guard bound == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw failure("Binding a value")
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let stepped = sqlite3_step(statement)
        guard stepped == SQLITE_DONE || stepped == SQLITE_ROW else { throw failure("Writing") }
    }

    private func query<T>(_ sql: String, _ values: [Value] = [], _ read: (Row) -> T?) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var out: [T] = []
        while true {
            let stepped = sqlite3_step(statement)
            if stepped == SQLITE_DONE { break }
            guard stepped == SQLITE_ROW else { throw failure("Reading") }
            if let value = read(Row(statement: statement)) { out.append(value) }
        }
        return out
    }

    private func integer(_ sql: String, _ values: [Value] = []) throws -> Int64? {
        try query(sql, values) { $0.int(0) }.first
    }
}
