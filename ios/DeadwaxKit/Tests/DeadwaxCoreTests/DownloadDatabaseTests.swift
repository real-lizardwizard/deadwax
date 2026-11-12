import Foundation
import Testing
@testable import DeadwaxCore

// The download store's database (spec 8.2), on a temp file: SQLite is Linux's too (libsqlite3-dev).

private func withDatabase(_ body: (DownloadDatabase, String) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("downloads.sqlite").path
    try body(try DownloadDatabase(path: path), path)
}

@Suite struct DownloadDatabaseTests {
    @Test func theSchemaIsMadeFromNothing() throws {
        try withDatabase { db, path in
            #expect(try db.userVersion() == DownloadDatabase.version)
            #expect(try db.songs().isEmpty)
            #expect(try db.albums().isEmpty)
            #expect(try db.keptPlays().isEmpty)
            #expect(try db.keptQueue() == nil)
            // opened again: nothing made twice
            let again = try DownloadDatabase(path: path)
            #expect(try again.userVersion() == 2)
        }
    }

    @Test func aSongThroughEveryState() throws {
        try withDatabase { db, _ in
            var r = DownloadRecord(id: "s1", albumID: "al", disc: 1, track: 2, suffix: "flac", sizeExpected: 1_000,
                                   duration: 12.5, wantedAt: 100)
            try db.put(r)
            #expect(try db.song("s1") == r)
            r.wait = .wifi
            try db.put(r)
            #expect(try db.song("s1")?.wait == .wifi)
            r = DownloadRules.apply(.taskMade("srv|me|s1|flac"), to: r)
            try db.put(r)
            #expect(try db.song("s1")?.state == .fetching)
            #expect(try db.song("s1")?.task == "srv|me|s1|flac")
            r = DownloadRules.apply(.cancelled(resume: Data([1, 2, 3])), to: r)
            try db.put(r)
            #expect(try db.song("s1")?.resume == Data([1, 2, 3]))
            let flac = FLACFacts(rate: 44_100, bits: 16, md5: String(repeating: "ab", count: 16))
            r = DownloadRules.apply(.arrived(bytes: 1_000, check: .unchecked, flac: flac, at: 200), to: r)
            try db.put(r)
            let done = try db.song("s1")
            #expect(done == r)
            #expect(done?.flac == flac && done?.bytes == 1_000 && done?.doneAt == 200 && done?.resume == nil)
            r = DownloadRules.apply(.checked(.matched), to: r)
            try db.put(r)
            #expect(try db.song("s1")?.check == .matched)
            var failed = DownloadRecord(id: "s2", albumID: "al", format: "mp3", suffix: "mp3", wantedAt: 101)
            failed.tries = 2
            failed = DownloadRules.apply(.refused(status: 404, detail: "Not Found"), to: failed)
            try db.put(failed)
            #expect(try db.song("s2")?.failure == .answered(status: 404, detail: "Not Found"))
            #expect(try db.songs().map(\.id) == ["s1", "s2"], "in the order asked")
            try db.deleteSong("s1")
            #expect(try db.song("s1") == nil)
        }
    }

    @Test func originsAddedAndTakenASongWithNoneGoes() throws {
        try withDatabase { db, _ in
            for id in ["a", "b", "c"] { try db.put(DownloadRecord(id: id, albumID: "al", suffix: "flac", wantedAt: 1)) }
            try db.addOrigin(.song, song: "a", at: 1)
            try db.addOrigin(.album("al"), song: "a", at: 2)
            try db.addOrigin(.album("al"), song: "b", at: 2)
            try db.addOrigin(.album("al"), song: "c", at: 2)
            try db.addOrigin(.other("library"), song: "c", at: 3)
            try db.addOrigin(.album("al"), song: "c", at: 9)
            #expect(try db.origins() == ["a": [.song, .album("al")], "b": [.album("al")], "c": [.album("al"), .other("library")]])
            let gone = try db.removeOrigins([.album("al")], songs: ["a", "b", "c"])
            #expect(gone == ["b"])
            #expect(try db.songs().map(\.id) == ["a", "c"])
            #expect(try db.removeOrigins([.song], songs: ["a"]) == ["a"])
            #expect(try db.origins() == ["c": [.other("library")]])
        }
    }

    @Test func albumsAndTheirLoudnessKeptAsAnswered() throws {
        try withDatabase { db, _ in
            let json = Data(#"{"id":"al","name":"Dummy"}"#.utf8)
            try db.putAlbum(id: "al", json: json, fetchedAt: 5)
            try db.setCover(album: "al", file: "cov-1024.jpg")
            try db.putAlbum(id: "al", json: json, fetchedAt: 6)
            let kept = try db.albums()
            #expect(kept.count == 1 && kept[0].json == json && kept[0].fetchedAt == 6)
            #expect(kept[0].cover == "cov-1024.jpg", "a new answer keeps the cover kept")
            try db.putLoudness(album: "al", json: Data("{}".utf8), algorithm: 3, fetchedAt: 7)
            #expect(try db.loudness().first?.algorithm == 3)
            try db.deleteAlbum("al")
            #expect(try db.albums().isEmpty)
            #expect(try db.loudness().isEmpty)
        }
    }

    @Test func playsKeptAndGivenBackOldestFirst() throws {
        try withDatabase { db, _ in
            let late = try db.keepPlay(songID: "b", timeMs: 2_000)
            try db.keepPlay(songID: "a", timeMs: 1_000)
            try db.keepPlay(songID: "c", timeMs: 2_000)
            #expect(try db.keptPlays().map(\.songID) == ["a", "b", "c"])
            try db.forgetPlay(late)
            #expect(try db.keptPlays().map(\.songID) == ["a", "c"])
        }
    }

    @Test func theQueueSaveIsOneRow() throws {
        try withDatabase { db, _ in
            try db.keepQueue(kind: "queue", body: Data([1]), at: 1)
            try db.keepQueue(kind: "at", body: Data([2]), at: 2)
            #expect(try db.keptQueue() == .init(kind: "at", body: Data([2]), keptAt: 2))
            try db.forgetQueue()
            #expect(try db.keptQueue() == nil)
        }
    }

    @Test func removeAllKeepsThePlaysAndTheQueue() throws {
        try withDatabase { db, _ in
            try db.put(DownloadRecord(id: "a", albumID: "al", suffix: "flac", wantedAt: 1))
            try db.addOrigin(.song, song: "a", at: 1)
            try db.putAlbum(id: "al", json: Data(), fetchedAt: 1)
            try db.keepPlay(songID: "a", timeMs: 1)
            try db.keepQueue(kind: "queue", body: Data([1]), at: 1)
            try db.setMeta("force_quit_at", "123")
            try db.removeAll()
            #expect(try db.songs().isEmpty)
            #expect(try db.origins().isEmpty)
            #expect(try db.albums().isEmpty)
            #expect(try db.keptPlays().count == 1)
            #expect(try db.keptQueue() != nil)
            #expect(try db.meta("force_quit_at") == "123")
            try db.setMeta("force_quit_at", nil)
            #expect(try db.meta("force_quit_at") == nil)
        }
    }

    @Test func aTransactionIsAllOrNothing() throws {
        struct Stop: Error {}
        try withDatabase { db, _ in
            var stopped = false
            do {
                try db.transaction {
                    try db.put(DownloadRecord(id: "a", albumID: "al", suffix: "flac", wantedAt: 1))
                    throw Stop()
                }
            } catch is Stop {
                stopped = true
            }
            #expect(stopped)
            let left = try db.songs()
            #expect(left.isEmpty)
        }
    }

    // MARK: version 2: lyrics (notes/app-lyrics.md 4.7)

    private static let synced = Data(#"{"synced":true,"lines":[{"time":1.5,"text":"One"}]}"#.utf8)
    private static let none = Data(#"{"synced":false,"lines":[]}"#.utf8)

    @Test func aSongsLyricsAreKeptOnlyWhileTheSongIs() throws {
        try withDatabase { db, _ in
            // a song not in the store - removed while its ask was on its way - keeps nothing
            #expect(try db.putLyrics(song: "a", json: Self.synced, etag: #""l1""#, fetchedAt: 10) == false)
            #expect(try db.lyrics("a") == nil)
            let a = DownloadRecord(id: "a", albumID: "al", suffix: "flac", wantedAt: 1)
            try db.put(a)
            #expect(try db.putLyrics(song: "a", json: Self.synced, etag: #""l1""#, fetchedAt: 10))
            #expect(try db.lyrics("a") == .init(songID: "a", json: Self.synced, etag: #""l1""#, fetchedAt: 10))
            // replaced when it differs - none for the song is kept too, with no ETag
            #expect(try db.putLyrics(song: "a", json: Self.none, etag: nil, fetchedAt: 20))
            #expect(try db.lyrics("a") == .init(songID: "a", json: Self.none, etag: nil, fetchedAt: 20))
            // the song's row written again (INSERT OR REPLACE) keeps them: no delete trigger fires
            var done = a
            done.state = .done
            try db.put(done)
            #expect(try db.lyrics("a")?.json == Self.none)
            try db.put(DownloadRecord(id: "b", albumID: "al", suffix: "flac", wantedAt: 2))
            #expect(try db.lyricsSongs() == ["a"])
            try db.putLyrics(song: "b", json: Self.synced, etag: nil, fetchedAt: 30)
            #expect(try db.lyricsSongs() == ["a", "b"])
        }
    }

    @Test func everyWayASongGoesTakesItsLyrics() throws {
        try withDatabase { db, _ in
            for id in ["a", "b", "c", "d", "e"] {
                try db.put(DownloadRecord(id: id, albumID: "al", suffix: "flac", wantedAt: 1))
                try db.addOrigin(.album("al"), song: id, at: 1)
                try db.putLyrics(song: id, json: Self.synced, etag: nil, fetchedAt: 1)
            }
            try db.addOrigin(.song, song: "c", at: 2)
            // deleteSong
            try db.deleteSong("a")
            #expect(try db.lyrics("a") == nil)
            // removeOrigins: the album's Remove Download takes b (its last origin) - c keeps its lyrics while the song
            // it was asked for as still holds it
            #expect(try db.removeOrigins([.album("al")], songs: ["b", "c"]) == ["b"])
            #expect(try db.lyrics("b") == nil)
            #expect(try db.lyrics("c") != nil)
            #expect(try db.removeOrigins([.song], songs: ["c"]) == ["c"])
            #expect(try db.lyrics("c") == nil)
            // removeAll
            #expect(try db.lyricsSongs() == ["d", "e"])
            try db.removeAll()
            #expect(try db.lyricsSongs().isEmpty)
            // a song asked for again after its removal starts with none: none were left behind
            try db.put(DownloadRecord(id: "d", albumID: "al", suffix: "flac", wantedAt: 3))
            #expect(try db.lyrics("d") == nil)
        }
    }

    @Test func aVersionOneFileIsGivenTheLyricsTableEveryRowKept() throws {
        try withDatabase { _, path in
            // the file withDatabase made is version 2: a version-1 file is made beside it, as Phase 2 left one
            let old = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("v1.sqlite").path
            let song = DownloadRecord(id: "a", albumID: "al", suffix: "flac", wantedAt: 1)
            do {
                let v1 = try DownloadDatabase(path: old, upTo: 1)
                #expect(try v1.userVersion() == 1)
                try v1.put(song)
                try v1.addOrigin(.album("al"), song: "a", at: 1)
                try v1.putAlbum(id: "al", json: Data("{}".utf8), fetchedAt: 1)
                try v1.keepPlay(songID: "a", timeMs: 5)
                // no lyrics table in version 1
                #expect(throws: DownloadDatabase.Failure.self) {
                    try v1.putLyrics(song: "a", json: Self.synced, etag: nil, fetchedAt: 1)
                }
            }
            let v2 = try DownloadDatabase(path: old)
            #expect(try v2.userVersion() == 2)
            #expect(try v2.songs() == [song])
            #expect(try v2.origins() == ["a": [.album("al")]])
            #expect(try v2.albums().map(\.id) == ["al"])
            #expect(try v2.keptPlays().map(\.songID) == ["a"])
            #expect(try v2.lyricsSongs().isEmpty)
            #expect(try v2.putLyrics(song: "a", json: Self.synced, etag: #""l1""#, fetchedAt: 2))
            // and the trigger came with the table
            try v2.deleteSong("a")
            #expect(try v2.lyrics("a") == nil)
        }
    }

    @Test func aFileThatIsntADatabaseIsSaidInSQLitesWords() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-bad-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x41, count: 4_096))
        #expect(throws: DownloadDatabase.Failure.self) { _ = try DownloadDatabase(path: path) }
    }
}
