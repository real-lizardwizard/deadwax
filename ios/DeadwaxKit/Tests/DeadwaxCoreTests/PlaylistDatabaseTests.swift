import Foundation
import Testing
@testable import DeadwaxCore

// The download store's version 6 (phase4-library.md 2.5, 6.3): the downloaded playlists, in the `playlist` table, on a
// temp file - written, read back, an unreadable answer kept unread, Remove All taking them - and a real version-5 file
// brought up to it with every row of every table kept.

private func withFolder(_ body: (String) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-playlists-\(UUID().uuidString)",
                                                                               isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder.path)
}

private func withDatabase(_ body: (DownloadDatabase) throws -> Void) throws {
    try withFolder { folder in
        try body(try DownloadDatabase(path: folder + "/downloads.sqlite"))
    }
}

private let summary = Playlist(id: "p1", name: "Late night", songCount: 2, duration: 400, changed: "2026-11-14T10:00:00Z",
                               owner: "james", coverArt: "pl-p1_x", mine: true, editable: true)
private let answer = PlaylistWithSongs(playlist: summary, songs: [Song(id: "s1", title: "Roads", albumId: "al-d"),
                                                                  Song(id: "s2", title: "Teardrop", albumId: "al-m")])

private func keptRow(_ id: String = "p1", askedAt: Int64 = 5) throws -> KeptPlaylist {
    let body = try JSONEncoder().encode(PlaylistWithSongs(playlist: Playlist(id: id, name: "Late night"), songs: answer.songs))
    return KeptPlaylist(id: id, answer: try JSONDecoder().decode(PlaylistWithSongs.self, from: body), body: body, readAt: 10,
                        missingSince: 11, left: ["s3": 9], askedAt: askedAt)
}

@Suite struct PlaylistDatabaseTests {
    @Test func aDownloadedPlaylistIsWrittenAndReadBackWhole() throws {
        try withDatabase { db in
            #expect(try db.userVersion() == 6 && DownloadDatabase.version == 6)
            #expect(try db.playlists().isEmpty)
            let second = try keptRow("p2", askedAt: 3)
            let first = try keptRow("p1", askedAt: 5)
            try db.putPlaylist(first)
            try db.putPlaylist(second)
            #expect(try db.playlists() == [second, first], "in the order they were downloaded")
            // replaced whole: the marks cleared, the answer as read
            var read = first
            read.missingSince = nil
            read.left = [:]
            read.readAt = 20
            try db.putPlaylist(read)
            #expect(try db.playlists().last == read)
            try db.deletePlaylist("p2")
            #expect(try db.playlists() == [read])
        }
    }

    @Test func aRowWhoseAnswerCantBeReadIsKeptUnread() throws {
        try withDatabase { db in
            try db.putPlaylist(KeptPlaylist(id: "p1", answer: nil, body: Data("not json".utf8), readAt: 1, askedAt: 1))
            // another playlist's answer under this id is no answer for it
            try db.putPlaylist(KeptPlaylist(id: "p2", answer: nil, body: try JSONEncoder().encode(answer), readAt: 1, askedAt: 2))
            try db.execute("UPDATE playlist SET left_songs = 'garbled' WHERE id = 'p1'")
            let rows = try db.playlists()
            try #require(rows.count == 2, "never left out: its songs' origin would read as an orphan's")
            #expect(rows.map(\.id) == ["p1", "p2"])
            #expect(rows.allSatisfy { $0.answer == nil })
            #expect(rows[0].left.isEmpty, "marks that can't be read are none - nothing agreed, nothing taken")
            #expect(rows[0].body == Data("not json".utf8))
        }
    }

    @Test func removeAllTakesThePlaylistsWithTheSongsAndKeepsWhatIsntADownload() throws {
        try withDatabase { db in
            try db.put(DownloadRecord(id: "s1", albumID: "al-d", suffix: "flac", wantedAt: 1))
            try db.addOrigin(.playlist("p1"), song: "s1", at: 1)
            try db.putPlaylist(try keptRow())
            try db.keepPlay(songID: "s1", timeMs: 5)
            try db.putLibrary([FollowedAlbum(album: IndexAlbum(id: "al-d", name: "Dummy"), position: 0)], replacing: [])
            try db.removeAll()
            #expect(try db.playlists().isEmpty && db.songs().isEmpty && db.origins().isEmpty)
            #expect(try db.keptPlays().map(\.songID) == ["s1"])
            #expect(try db.library().map(\.id) == ["al-d"])
        }
    }

    @Test func aPlaylistsSongLosesOnlyItsOriginAndGoesWithNoneLeft() throws {
        try withDatabase { db in
            for id in ["a", "b"] { try db.put(DownloadRecord(id: id, albumID: "al", suffix: "flac", wantedAt: 1)) }
            try db.addOrigin(.playlist("p1"), song: "a", at: 1)
            try db.addOrigin(.playlist("p1"), song: "b", at: 1)
            try db.addOrigin(.album("al"), song: "b", at: 1)
            #expect(try db.origins() == ["a": [.playlist("p1")], "b": [.playlist("p1"), .album("al")]])
            #expect(try db.removeOrigins(DownloadRemoval.playlist("p1"), songs: ["a", "b"]) == ["a"])
            #expect(try db.songs().map(\.id) == ["b"], "kept by its album's download")
            #expect(try db.origins() == ["b": [.album("al")]])
        }
    }

    @Test func aVersionFiveFileIsGivenThePlaylistTableEveryRowOfEveryTableKept() throws {
        try withFolder { folder in
            let path = folder + "/v5.sqlite"
            let song = DownloadRecord(id: "a", albumID: "al", suffix: "flac", sizeExpected: 30, state: .done, bytes: 30,
                                      wantedAt: 1, doneAt: 2)
            let other = DownloadRecord(id: "b", albumID: "al", suffix: "flac", wantedAt: 3)
            var album = FollowedAlbum(album: IndexAlbum(id: "al", name: "Dummy", songCount: 2), position: 0,
                                      songs: [FollowedSong(id: "a"), FollowedSong(id: "b")], readAt: 10, missingSince: 11,
                                      removedHere: 12, keptOff: 13)
            album.left = ["c": 9]
            do {
                let v5 = try DownloadDatabase(path: path, upTo: 5)
                #expect(try v5.userVersion() == 5)
                try v5.put(song)
                try v5.put(other)
                try v5.addOrigin(.album("al"), song: "a", at: 1)
                try v5.addOrigin(.library, song: "b", at: 3)
                // a playlist's origin a store could already hold (Phase 2 reserved the raw): kept as it is
                try v5.execute("INSERT INTO origin (song_id, origin, at) VALUES ('b', 'playlist:p1', 4)")
                try v5.putAlbum(id: "al", json: Data(#"{"id":"al"}"#.utf8), fetchedAt: 1)
                try v5.setCover(album: "al", file: "al.jpg")
                try v5.putLoudness(album: "al", json: Data("{}".utf8), algorithm: 2, fetchedAt: 1)
                #expect(try v5.putLyrics(song: "a", json: Data("{}".utf8), etag: "\"l1\"", fetchedAt: 1))
                try v5.keepPlay(songID: "a", timeMs: 5)
                #expect(try v5.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a"))) > 0)
                try v5.keepQueue(kind: "unsent", body: Data("q".utf8), at: 7)
                try v5.putLibrary([album], replacing: [])
                try v5.setMeta("force_quit_at", "16")
                try v5.setMeta(DownloadDatabase.libraryETagKey, "\"e1\"")
                // no playlist table in version 5
                #expect(throws: DownloadDatabase.Failure.self) { _ = try v5.playlists() }
            }
            let v6 = try DownloadDatabase(path: path)
            #expect(try v6.userVersion() == DownloadDatabase.version)
            #expect(try v6.songs() == [song, other])
            #expect(try v6.origins() == ["a": [.album("al")], "b": [.library, .playlist("p1")]])
            #expect(try v6.albums().map(\.id) == ["al"] && v6.albums().first?.cover == "al.jpg")
            #expect(try v6.loudness().map(\.id) == ["al"])
            #expect(try v6.lyrics("a")?.etag == "\"l1\"")
            #expect(try v6.keptPlays().map(\.songID) == ["a"])
            #expect(try v6.keptStartCount() == 1)
            #expect(try v6.keptQueue()?.body == Data("q".utf8))
            #expect(try v6.library() == [album], "the library followed, its marks and left songs, kept")
            #expect(try v6.meta("force_quit_at") == "16" && v6.meta(DownloadDatabase.libraryETagKey) == "\"e1\"")
            #expect(try v6.playlists().isEmpty)
            // a playlist origin the old file had has no row: the keeper's orphans take it as the store opens (the song
            // stays, its library's origin kept)
            #expect(PlaylistDownloads.orphans(try v6.origins(), kept: Set(try v6.playlists().map(\.id))) == ["p1": ["b"]])
            // and the new table takes a downloaded playlist
            try v6.putPlaylist(try keptRow())
            #expect(try v6.playlists().map(\.id) == ["p1"])
            #expect(PlaylistDownloads.orphans(try v6.origins(), kept: Set(try v6.playlists().map(\.id))).isEmpty)
        }
    }
}
