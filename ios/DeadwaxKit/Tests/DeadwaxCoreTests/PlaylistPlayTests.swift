import Foundation
import Testing
@testable import DeadwaxCore

/// Playing a playlist (phase4-library.md 2.3): each song with its own album, at the songs level, its albums remembered
/// as stubs - and the routes' answers read. The rules the web's TypeScript answers are PlaylistVectorTests'; these are
/// the ones it doesn't hold in lib/ (PlaylistPage.tsx's own `tracks`, the picks, the lines).
@Suite struct PlaylistPlayTests {
    static let roads = Song(id: "s1", title: "Roads", album: "Dummy", albumId: "al-d", artist: "Portishead",
                            duration: 305, suffix: "flac", contentType: "audio/flac", samplingRate: 44100, bitDepth: 16,
                            channelCount: 2, coverArt: "al-d", displayAlbumArtist: "Portishead")
    static let teardrop = Song(id: "s2", title: "Teardrop", album: "Mezzanine", albumId: "al-m", artist: "Massive Attack",
                               duration: 330.5, coverArt: "al-m")
    static let loose = Song(id: "s3", title: "Loose", album: "Somewhere", artist: "Nobody", duration: 61)
    static let blankAlbum = Song(id: "s4", title: "Blank", albumId: "", duration: 12)

    @Test func eachSongIsQueuedWithItsOwnAlbum() {
        let tracks = PlaylistPlay.tracks([Self.roads, Self.teardrop, Self.loose, Self.blankAlbum], level: .track)
        #expect(tracks.map(\.albumId) == ["al-d", "al-m", nil, nil])
        #expect(tracks.map(\.album) == ["Dummy", "Mezzanine", "Somewhere", ""])
        #expect(tracks.map(\.coverArt) == ["al-d", "al-m", nil, nil])
        #expect(tracks.map(\.artist) == ["Portishead", "Massive Attack", "Nobody", ""])
        #expect(tracks.allSatisfy { $0.level == .track })
        // the song's own format, as the album page's would carry it
        #expect(tracks[0] == QueueTrack(id: "s1", title: "Roads", artist: "Portishead", album: "Dummy", albumId: "al-d",
                                        coverArt: "al-d", duration: 305, contentType: "audio/flac", suffix: "flac",
                                        sampleRate: 44100, bitDepth: 16, channels: 2, level: .track))
    }

    @Test func aPlaylistPlaysAtTheSongsLevel() {
        // Auto levels a playlist song by song (not as an album); Song and Album as they say; Off plays the files as they are
        #expect(PlaylistPlay.songsLevel(.auto) == .track)
        #expect(PlaylistPlay.songsLevel(.song) == .track)
        #expect(PlaylistPlay.songsLevel(.album) == .album)
        #expect(PlaylistPlay.songsLevel(.off) == nil)
        // where an album's Play would be the album level under Auto
        #expect(QueuePickWords.playLevel(.auto) == .album)
        let plan = PlaylistPlay.plan([Self.roads, Self.teardrop], setting: .auto) { _ in nil }
        #expect(plan.tracks.map(\.level) == [.track, .track])
        #expect(plan.albums.map(\.id) == ["al-d", "al-m"])
        #expect(plan.albums.allSatisfy { $0.partial })
    }

    @Test func thePlanKeepsAnAlbumHeldWhole() {
        let whole = Album(id: "al-d", name: "Dummy", artist: "Portishead", song: [Self.roads, Song(id: "s9", albumId: "al-d")])
        let plan = PlaylistPlay.plan([Self.roads, Self.teardrop], setting: .off) { (id: String) -> Album? in
            id == "al-d" ? whole : nil
        }
        #expect(plan.albums.first == whole)
        #expect(plan.albums.last?.partial == true)
        #expect(plan.tracks.allSatisfy { $0.level == nil })
    }

    @Test func thePicksForARowAndTheWholePlaylist() throws {
        let row = PlaylistPlay.pick(song: Self.roads)
        #expect(row.label == "Roads" && row.tracks == [Self.roads] && row.albumIds == ["al-d"] && row.queuedAs == nil)
        #expect(PlaylistPlay.pick(song: Self.loose).albumIds == [])
        let all = try #require(PlaylistPlay.pick(name: "Late night", songs: [Self.roads, Self.loose, Self.teardrop, Self.roads]))
        #expect(all.label == "Late night" && all.tracks.count == 4 && all.queuedAs == nil)
        #expect(all.albumIds == ["al-d", "al-m"])
        #expect(PlaylistPlay.pick(name: "Empty", songs: []) == nil)
        // queued as songs: Auto at each song's own level
        #expect(all.choose(.next, setting: .auto)?.level == .track)
    }

    @Test func aPagesLengthIsItsSongsOwn() {
        #expect(PlaylistRules.total([Self.roads, Self.teardrop, Self.loose, Song(id: "none")]) == 696.5)
        #expect(PlaylistRules.total([]) == 0)
        #expect(PlaylistRules.songsLine(4, seconds: PlaylistRules.total([Self.roads, Self.teardrop, Self.loose])) == "4 songs, 12 min")
    }

    @Test func aRowsLineIsItsArtistAndAlbum() {
        #expect(PlaylistRules.songLine(Self.roads) == "Portishead · Dummy")
        #expect(PlaylistRules.songLine(Song(id: "a", album: "Dummy")) == "Dummy")
        #expect(PlaylistRules.songLine(Song(id: "b", album: "", artist: "Portishead")) == "Portishead")
        #expect(PlaylistRules.songLine(Song(id: "c")) == "")
    }

    @Test func theScreensOwnWords() {
        #expect(PlaylistWords.files(3) == "From files (3)")
        #expect(PlaylistWords.openFailed("Try again.") == "Couldn't open this playlist. Try again.")
        #expect(PlaylistWords.refreshFailed("x") == "Couldn't update this playlist - showing it as it was. x")
        // the vocabulary: none of the phone's own lines names what a listener never reads
        for line in [PlaylistWords.offlineList, PlaylistWords.offlinePage, PlaylistWords.newPlaylistTitle,
                     PlaylistWords.songsHeading] {
            for banned in ["Navidrome", "the store", "Browse", "everything", "sync", "cache"] {
                #expect(!line.contains(banned), "\(line)")
            }
        }
    }

    @Test func aStubIsNeverSentAndInfoCountsNoneOfItsAlbum() throws {
        let read = try JSONDecoder().decode(Album.self, from: Data(#"{"id": "al", "partial": true, "song": []}"#.utf8))
        #expect(!read.partial)
        let stub = try #require(PlaylistPlay.albums([Self.roads]).first)
        #expect(stub.partial && stub.musicBrainzId == nil && stub.song == [Self.roads])
        #expect(AboutAlbum(album: stub).partial == true)
        #expect(AboutAlbum(album: read).partial == nil)
        // the encoder never writes it (it isn't a coding key)
        let written = try #require(String(data: JSONEncoder().encode(stub), encoding: .utf8))
        #expect(!written.contains("partial"))
    }

    // MARK: the answers

    static let summary = #"{"id": "pl1", "name": "Late night", "comment": "", "songCount": 2, "duration": 635, "created": "2026-10-01T10:00:00Z", "changed": "2026-11-01T10:00:00Z", "owner": "james", "public": false, "coverArt": "pl-pl1_abc", "mine": true, "editable": true}"#

    @Test func theListIsRead() async throws {
        let (client, transport) = client(session: "s")
        let shared = #"{"id": "pl2", "name": "Sam's", "comment": "Hers", "songCount": 0, "duration": 0, "created": "", "changed": "", "owner": "sam", "public": true, "coverArt": null, "mine": false, "editable": false}"#
        // a playlist that can't be read is left out, not the list
        transport.answer("/deadwax/navidrome/playlists", 200, #"{"playlists": [\#(Self.summary), \#(shared), {"name": "no id"}]}"#)
        let list = try await client.playlists()
        #expect(list.map(\.id) == ["pl1", "pl2"])
        #expect(list[0] == Playlist(id: "pl1", name: "Late night", songCount: 2, duration: 635, created: "2026-10-01T10:00:00Z",
                                    changed: "2026-11-01T10:00:00Z", owner: "james", coverArt: "pl-pl1_abc", mine: true,
                                    editable: true))
        #expect(list[1].isPublic && list[1].coverArt == nil && list[1].comment == "Hers")
        #expect(transport.last?.method == "GET")
        transport.answer("/deadwax/navidrome/playlists", 200, #"{"playlists": []}"#)
        #expect(try await client.playlists().isEmpty)
        transport.answer("/deadwax/navidrome/playlists", 200, #"{}"#)
        #expect(try await client.playlists().isEmpty)
    }

    @Test func onePlaylistIsReadWithItsSongs() async throws {
        let (client, transport) = client(session: "s")
        let songs = #"[{"id": "s1", "title": "Roads", "albumId": "al-d", "duration": 305}, {"id": "s1", "title": "Roads", "albumId": "al-d"}, {"title": "no id"}]"#
        transport.answer("/deadwax/navidrome/playlists/pl 1", 200, #"{"playlist": \#(Self.summary), "songs": \#(songs), "hidden": 2}"#)
        let found = try await client.playlist(id: "pl 1")
        #expect(found.playlist.id == "pl1" && found.hidden == 2)
        #expect(found.songs.map(\.id) == ["s1", "s1"])
        #expect(transport.last?.url.path == "/deadwax/navidrome/playlists/pl 1")
        // a field of the wrong type is its empty value; hidden never below none
        transport.answer("/deadwax/navidrome/playlists/odd", 200, #"{"playlist": {"id": "odd", "name": 4, "public": "yes", "coverArt": ""}, "songs": "none", "hidden": -3}"#)
        let odd = try await client.playlist(id: "odd")
        #expect(odd.playlist == Playlist(id: "odd") && odd.songs.isEmpty && odd.hidden == 0)
        // gone: a 404, thrown for the page's gone line
        await #expect(throws: APIFailure.self) { try await client.playlist(id: "gone") }
        do {
            _ = try await client.playlist(id: "gone")
        } catch {
            #expect(ErrorWords.kind(of: error) == .notFound)
        }
    }
}
