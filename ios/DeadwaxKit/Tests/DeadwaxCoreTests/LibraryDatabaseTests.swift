import Foundation
import Testing
@testable import DeadwaxCore

// The download store's version 4 (phase3-autodownload.md 5.1, its tests 7): your library as this phone follows it, in
// the `library` table, on a temp file - and version 5's `left_songs` (after the review).

private func withFolder(_ body: (String) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-library-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder.path)
}

private func withDatabase(_ body: (DownloadDatabase) throws -> Void) throws {
    try withFolder { folder in
        try body(try DownloadDatabase(path: folder + "/downloads.sqlite"))
    }
}

private let songs = [FollowedSong(id: "s1", disc: 1, track: 1, size: 30_000_000, suffix: "flac", contentType: "audio/flac",
                                  duration: 241.5),
                     FollowedSong(id: "s2", disc: 1, track: 2, size: nil, suffix: "ogg", duration: 180)]

private func followed(_ id: String, _ position: Int, songs: [FollowedSong]? = nil, readAt: Int64? = nil,
                      missingSince: Int64? = nil, removedHere: Int64? = nil, keptOff: Int64? = nil) -> FollowedAlbum {
    FollowedAlbum(album: IndexAlbum(id: id, name: "Album \(id)", artist: "Someone", created: "2026-11-01T10:00:00Z",
                                    starred: "2026-11-02T10:00:00Z", songCount: 2, duration: 421.5),
                  position: position, songs: songs, readAt: readAt, missingSince: missingSince,
                  removedHere: removedHere, keptOff: keptOff)
}

@Suite struct LibraryDatabaseTests {
    @Test func anAlbumKeepsItsEntryItsSongsAndEveryMark() throws {
        try withDatabase { db in
            #expect(try db.library().isEmpty)
            let album = followed("a", 0, songs: songs, readAt: 10, missingSince: 11, removedHere: 12, keptOff: 13)
            let bare = followed("b", 1)
            try db.putLibrary([album, bare], replacing: [])
            #expect(try db.library() == [album, bare])
        }
    }

    @Test func aListReplacedDeletesWhatIsGoneAndKeepsWhatStays() throws {
        try withDatabase { db in
            let first = [followed("a", 0, songs: songs, readAt: 10), followed("b", 1, songs: songs, readAt: 10),
                         followed("c", 2)]
            try db.putLibrary(first, replacing: [])
            let kept = try db.library()
            var moved = followed("a", 1, songs: songs, readAt: 10)
            moved.missingSince = 20
            let next = [followed("new", 0), moved, followed("c", 2)]
            try db.putLibrary(next, replacing: kept)
            #expect(try db.library() == [followed("new", 0), moved, followed("c", 2)])
        }
    }

    @Test func onlyTheRowsThatDifferAreWritten() throws {
        try withDatabase { db in
            let first = [followed("a", 0, songs: songs, readAt: 10), followed("b", 1)]
            try db.putLibrary(first, replacing: [])
            // what the store holds for "b" changes behind the list's back: putting the same list leaves it alone
            #expect(try db.setLibrarySongs(album: "b", songs: songs, at: 30))
            try db.putLibrary(first, replacing: first)
            #expect(try db.library().last?.songs == songs, "an unchanged row isn't written again")
        }
    }

    @Test func songsAreSetOnlyOnAnAlbumOfTheLibrary() throws {
        try withDatabase { db in
            try db.putLibrary([followed("a", 0)], replacing: [])
            #expect(try db.setLibrarySongs(album: "a", songs: songs, at: 50))
            #expect(try !db.setLibrarySongs(album: "gone", songs: songs, at: 50))
            let row = try db.library().first
            #expect(row?.songs == songs && row?.readAt == 50)
            #expect(try db.library().count == 1)
        }
    }

    @Test func removedHereIsMarkedOnAnAlbumOfTheLibrary() throws {
        try withDatabase { db in
            try db.putLibrary([followed("a", 0)], replacing: [])
            #expect(try db.setRemovedHere(album: "a", at: 77))
            #expect(try !db.setRemovedHere(album: "elsewhere", at: 77))
            #expect(try db.library().first?.removedHere == 77)
        }
    }

    @Test func keptOffIsMarkedAndClearedOnAnAlbumOfTheLibrary() throws {
        try withDatabase { db in
            try db.putLibrary([followed("a", 0, songs: songs, readAt: 1)], replacing: [])
            #expect(try db.setKeptOff(album: "a", at: 88))
            #expect(try !db.setKeptOff(album: "elsewhere", at: 88))
            #expect(try db.library().first?.keptOff == 88)
            #expect(try db.setKeptOff(album: "a", at: nil))
            #expect(try db.library().first?.keptOff == nil)
            #expect(try db.library().first?.songs == songs, "nothing else moves")
        }
    }

    @Test func removeAllLeavesTheLibraryAndForgetLibraryTakesItWithItsMeta() throws {
        try withDatabase { db in
            try db.putLibrary([followed("a", 0, songs: songs, readAt: 1)], replacing: [])
            try db.setMeta(DownloadDatabase.libraryETagKey, "\"e\"")
            try db.setMeta(DownloadDatabase.libraryScopeKey, "yours")
            try db.setMeta(DownloadDatabase.libraryHeldKey, "truncated")
            try db.setMeta(DownloadDatabase.libraryCheckedKey, "5")
            try db.setMeta(DownloadDatabase.libraryFirstReadKey, "252.0 3000")
            try db.setMeta("force_quit_at", "9")
            try db.removeAll()
            #expect(try db.library().count == 1, "the library isn't a download")
            #expect(try db.meta(DownloadDatabase.libraryETagKey) == "\"e\"")
            try db.forgetLibrary()
            #expect(try db.library().isEmpty)
            for key in DownloadDatabase.libraryKeys {
                #expect(try db.meta(key) == nil)
            }
            #expect(try db.meta("force_quit_at") == "9", "the store's own facts stay")
        }
    }

    @Test func aVersionThreeFileIsGivenTheLibraryTableEveryRowKept() throws {
        try withFolder { folder in
            let path = folder + "/v3.sqlite"
            let song = DownloadRecord(id: "a", albumID: "al", suffix: "flac", wantedAt: 1)
            do {
                let v3 = try DownloadDatabase(path: path, upTo: 3)
                #expect(try v3.userVersion() == 3)
                try v3.put(song)
                try v3.addOrigin(.album("al"), song: "a", at: 1)
                try v3.putAlbum(id: "al", json: Data("{}".utf8), fetchedAt: 1)
                try v3.keepPlay(songID: "a", timeMs: 5)
                try v3.setMeta("force_quit_at", "16")
                #expect(try v3.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a"))) > 0)
                // no library table in version 3
                #expect(throws: DownloadDatabase.Failure.self) { _ = try v3.library() }
            }
            let v4 = try DownloadDatabase(path: path)
            #expect(try v4.userVersion() == DownloadDatabase.version)
            #expect(try v4.songs() == [song])
            #expect(try v4.origins() == ["a": [.album("al")]])
            #expect(try v4.albums().map(\.id) == ["al"])
            #expect(try v4.keptPlays().map(\.songID) == ["a"])
            #expect(try v4.keptStartCount() == 1)
            #expect(try v4.meta("force_quit_at") == "16")
            #expect(try v4.library().isEmpty)
            try v4.putLibrary([followed("x", 0)], replacing: [])
            #expect(try v4.library().map(\.id) == ["x"])
        }
    }

    // MARK: version 5 (after the review): the songs a read found had left their album

    @Test func theSongsFoundToHaveLeftAreKeptWithTheRow() throws {
        try withDatabase { db in
            var album = followed("a", 0, songs: songs, readAt: 10)
            album.left = ["s3": 9, "s4": 10]
            try db.putLibrary([album, followed("b", 1)], replacing: [])
            #expect(try db.library() == [album, followed("b", 1)])
            #expect(try db.library().last?.left.isEmpty == true)
            // a read sets them with the songs, and a read that finds none left clears them
            #expect(try db.setLibrarySongs(album: "b", songs: songs, left: ["s9": 40], at: 40))
            #expect(try db.library().last?.left == ["s9": 40])
            #expect(try db.setLibrarySongs(album: "b", songs: songs, at: 50))
            #expect(try db.library().last?.left.isEmpty == true && db.library().last?.readAt == 50)
        }
    }

    @Test func aVersionFourFileIsGivenTheLeftColumnEveryRowKept() throws {
        try withFolder { folder in
            let path = folder + "/v4.sqlite"
            let album = followed("a", 0, songs: songs, readAt: 10, missingSince: 11, removedHere: 12, keptOff: 13)
            do {
                let v4 = try DownloadDatabase(path: path, upTo: 4)
                #expect(try v4.userVersion() == 4)
                try v4.execute("INSERT INTO library (album_id, position, entry, songs, read_at, missing_since, removed_here, kept_off) VALUES ('a', 0, '\(String(decoding: try JSONEncoder().encode(album.album), as: UTF8.self))', '\(String(decoding: try JSONEncoder().encode(songs), as: UTF8.self))', 10, 11, 12, 13)")
                try v4.setMeta("library_etag", "\"e1\"")
            }
            let v5 = try DownloadDatabase(path: path)
            #expect(try v5.userVersion() == 5)
            #expect(try v5.library() == [album], "the row kept, nothing found to have left it")
            #expect(try v5.meta("library_etag") == "\"e1\"")
            #expect(try v5.setLibrarySongs(album: "a", songs: songs, left: ["s3": 20], at: 20))
            #expect(try v5.library().first?.left == ["s3": 20])
        }
    }
}
