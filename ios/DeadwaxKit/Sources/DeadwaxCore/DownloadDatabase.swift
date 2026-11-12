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
/// - `play_pending`, `queue_pending`: plays and the latest queue save kept until deadwax answers (7.6).
/// - `meta`: the store's own facts (`force_quit_at`).
///
/// Not thread-safe: one owner (the App's DownloadStore) calls it from one place at a time.
public final class DownloadDatabase {
    /// The schema's version (`PRAGMA user_version`).
    public static let version = 1

    /// SQLite said no: its own words, for whoever runs deadwax.
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let words: String
        public var description: String { words }
    }

    private var db: OpaquePointer?

    /// Opens (or makes) the database at `path` and brings its schema up to `version`.
    public init(path: String) throws {
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
        try migrate()
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

    /// The schema made from nothing (version 0), in one transaction.
    private func migrate() throws {
        let current = try integer("PRAGMA user_version") ?? 0
        guard current < Self.version else { return }
        try transaction {
            if current < 1 {
                for statement in Self.schema { try execute(statement) }
            }
            try execute("PRAGMA user_version = \(Self.version)")
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

    /// The song's row and its origins gone.
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

    /// The latest queue save not yet sent: one row, replaced by each.
    public struct KeptQueue: Sendable, Equatable {
        /// Which route it goes to: `queue` or `at` (Routes.saveQueue, saveQueueAt).
        public let kind: String
        public let body: Data
        public let keptAt: Int64
    }

    public func keepQueue(kind: String, body: Data, at: Int64) throws {
        try run("INSERT OR REPLACE INTO queue_pending (one, kind, body, kept_at) VALUES (1, ?, ?, ?)",
                [.text(kind), .blob(body), .int(at)])
    }

    public func keptQueue() throws -> KeptQueue? {
        try query("SELECT kind, body, kept_at FROM queue_pending WHERE one = 1") { row in
            guard let kind = row.text(0), let body = row.blob(1) else { return nil }
            return KeptQueue(kind: kind, body: body, keptAt: row.int(2) ?? 0)
        }.first
    }

    public func forgetQueue() throws {
        try run("DELETE FROM queue_pending")
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

    /// Remove All Downloads: every song, origin, album and loudness - the plays and the queue save kept (they aren't
    /// downloads).
    public func removeAll() throws {
        try transaction {
            for table in ["origin", "song", "album", "loudness"] { try execute("DELETE FROM \(table)") }
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

    private func execute(_ sql: String) throws {
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
