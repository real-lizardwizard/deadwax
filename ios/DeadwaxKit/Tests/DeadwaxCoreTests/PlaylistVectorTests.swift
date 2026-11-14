import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/playlists/playlist-vectors.json: what the web's TypeScript (lib/playlists.ts, lib/playedAlbums.ts) answers,
/// written by ios/scripts/export-playlist-vectors.cjs - never by hand - and the shapes it is read into.
enum PlaylistVectors {
    struct Vectors: Decodable {
        struct Words: Decodable {
            let PLAYLISTS_EMPTY, PLAYLISTS_EMPTY_HOW, PLAYLIST_EMPTY, PLAYLIST_GONE, listFailed: String
        }
        struct Constants: Decodable {
            let PLAYLIST_NAME_MAX, PLAYLIST_COMMENT_MAX, PLAYLIST_SONGS_MAX, PLAYLISTS_KEPT: Int
            let PLAYLISTS_FRESH_MS: Double
            let PLAYED_KEPT, QUEUE_ALBUMS_KEPT: Int
        }
        struct ReadOnly: Decodable { let songs: Int; let words: String?; let canEdit: Bool }
        struct PlaylistCase: Decodable {
            let playlist: Playlist
            let group: String
            let rowLine: String
            let ownerLine: String
            let readOnly: [ReadOnly]
        }
        struct Grouped: Decodable { let yours: [String]; let shared: [String]; let files: [String] }
        struct GroupCase: Decodable { let name: String; let ids: [String]; let groups: Grouped }
        struct CountCase: Decodable { let n: Int; let text: String }
        struct LengthCase: Decodable { let seconds: Double; let text: String }
        struct LineCase: Decodable { let n: Int; let seconds: Double; let text: String }
        struct HiddenCase: Decodable { let hidden: Int; let text: String }
        struct Stub: Decodable, Equatable {
            let id: String
            let name: String?
            let artist: String?
            let coverArt: String?
            let year: Int?
            let songs: [String]
            let partial: Bool
        }
        struct StubCase: Decodable { let name: String; let songs: [Song]; let albums: [Stub]; let stubFor: [Stub] }
        struct HeldCase: Decodable { let name: String; let songs: [Song]; let held: [Stub]; let albums: [Stub] }
        struct PlayedStep: Decodable { let op: String; let ids: [String]; let held: [String] }
        struct PlayedRun: Decodable { let name: String; let kept: Int?; let queueKept: Int?; let steps: [PlayedStep] }

        let words: Words
        let constants: Constants
        let playlists: [PlaylistCase]
        let groups: [GroupCase]
        let songCount: [CountCase]
        let lengthText: [LengthCase]
        let songsLine: [LineCase]
        let hiddenWords: [HiddenCase]
        let stubs: [StubCase]
        let withHeld: [HeldCase]
        let played: [PlayedRun]
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("playlists/playlist-vectors.json"))
    }

    /// An Album as the fixture holds a stub.
    static func stub(_ album: Album) -> Vectors.Stub {
        Vectors.Stub(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year,
                     songs: (album.song ?? []).map(\.id), partial: album.partial)
    }

    /// A held album the fixture names, as an Album with songs of those ids (the album's own answer or a stub).
    static func album(_ held: Vectors.Stub) -> Album {
        Album(id: held.id, name: held.name, artist: held.artist, coverArt: held.coverArt, year: held.year,
              song: held.songs.map { Song(id: $0, albumId: held.id) }, partial: held.partial)
    }

    /// The album a store run names, by id alone.
    struct Named: Identifiable, Sendable { let id: String }
}

@Suite struct PlaylistVectorTests {
    let vectors: PlaylistVectors.Vectors

    init() throws {
        vectors = try PlaylistVectors.load()
    }

    @Test func theWordsAndLimitsAreTheWebs() {
        #expect(PlaylistWords.playlistsEmpty == vectors.words.PLAYLISTS_EMPTY)
        #expect(PlaylistWords.playlistsEmptyHow == vectors.words.PLAYLISTS_EMPTY_HOW)
        #expect(PlaylistWords.playlistEmpty == vectors.words.PLAYLIST_EMPTY)
        #expect(PlaylistWords.playlistGone == vectors.words.PLAYLIST_GONE)
        #expect(PlaylistWords.listFailed("Why it failed.") == vectors.words.listFailed)
        #expect(PlaylistRules.nameMax == vectors.constants.PLAYLIST_NAME_MAX)
        #expect(PlaylistRules.commentMax == vectors.constants.PLAYLIST_COMMENT_MAX)
        #expect(PlaylistRules.songsMax == vectors.constants.PLAYLIST_SONGS_MAX)
        #expect(PlaylistRules.freshSeconds * 1000 == vectors.constants.PLAYLISTS_FRESH_MS)
        #expect(PlaylistRules.kept == vectors.constants.PLAYLISTS_KEPT)
        #expect(PlayedAlbums<Album>.playedKept == vectors.constants.PLAYED_KEPT)
        #expect(PlayedAlbums<Album>.queueAlbumsKept == vectors.constants.QUEUE_ALBUMS_KEPT)
    }

    @Test func slice1sEmptyLineIsTheWebsFirstSentence() {
        // the web's empty playlist line, up to its first full stop - the rest names Add to a playlist (slice 2)
        #expect(PlaylistWords.playlistEmptyNow == "Nothing in this playlist yet.")
        #expect(vectors.words.PLAYLIST_EMPTY.hasPrefix(PlaylistWords.playlistEmptyNow + " "))
        #expect(vectors.words.PLAYLISTS_EMPTY == PlaylistWords.playlistsEmpty)
    }

    @Test func eachPlaylistsGroupAndLines() {
        #expect(vectors.playlists.count >= 15)
        for one in vectors.playlists {
            let playlist = one.playlist
            #expect(PlaylistRules.group(of: playlist).rawValue == one.group, "\(playlist.id)")
            #expect(PlaylistRules.rowLine(playlist) == one.rowLine, "\(playlist.id)")
            #expect(PlaylistRules.ownerLine(playlist) == one.ownerLine, "\(playlist.id)")
            for row in one.readOnly {
                #expect(PlaylistRules.readOnlyWords(playlist, songs: row.songs) == row.words, "\(playlist.id) \(row.songs)")
                #expect(PlaylistRules.canEdit(playlist, songs: row.songs) == row.canEdit, "\(playlist.id) \(row.songs)")
            }
        }
        // every group is among the cases
        #expect(Set(vectors.playlists.map(\.group)) == Set(PlaylistGroup.allCases.map(\.rawValue)))
    }

    @Test func theGroupsKeepTheListsOrder() {
        let byId = Dictionary(vectors.playlists.map { ($0.playlist.id, $0.playlist) }, uniquingKeysWith: { first, _ in first })
        for one in vectors.groups {
            let groups = PlaylistRules.groups(one.ids.compactMap { byId[$0] })
            #expect(groups.yours.map(\.id) == one.groups.yours, "\(one.name)")
            #expect(groups.shared.map(\.id) == one.groups.shared, "\(one.name)")
            #expect(groups.files.map(\.id) == one.groups.files, "\(one.name)")
            #expect(groups[.yours] == groups.yours && groups[.shared] == groups.shared && groups[.files] == groups.files)
        }
    }

    @Test func theCountsLengthsAndHiddenLine() {
        for one in vectors.songCount { #expect(PlaylistRules.songCount(one.n) == one.text, "\(one.n)") }
        for one in vectors.lengthText { #expect(PlaylistRules.lengthText(one.seconds) == one.text, "\(one.seconds)") }
        for one in vectors.songsLine {
            #expect(PlaylistRules.songsLine(one.n, seconds: one.seconds) == one.text, "\(one.n) \(one.seconds)")
        }
        for one in vectors.hiddenWords { #expect(PlaylistRules.hiddenWords(one.hidden) == one.text, "\(one.hidden)") }
    }

    @Test func theAlbumStubsAndTheirOwnAlbum() {
        for one in vectors.stubs {
            #expect(PlaylistPlay.albums(one.songs).map(PlaylistVectors.stub) == one.albums, "\(one.name)")
            #expect(one.songs.map { PlaylistVectors.stub(PlaylistPlay.stub(for: $0)) } == one.stubFor, "\(one.name)")
        }
    }

    @Test func whatIsHeldIsNeverReplacedByAStub() {
        for one in vectors.withHeld {
            let held = Dictionary(one.held.map { ($0.id, PlaylistVectors.album($0)) }, uniquingKeysWith: { first, _ in first })
            let made = PlaylistPlay.withHeld(PlaylistPlay.albums(one.songs)) { (id: String) -> Album? in held[id] }
            #expect(made.map(PlaylistVectors.stub) == one.albums, "\(one.name)")
        }
    }

    @Test func theAlbumsPlayedFromAreKeptAsTheWebKeepsThem() {
        for run in vectors.played {
            var store = run.kept.map { PlayedAlbums<PlaylistVectors.Named>(kept: $0, queueKept: run.queueKept ?? $0) }
                ?? PlayedAlbums<PlaylistVectors.Named>()
            let named = Set(run.steps.flatMap(\.ids))
            for (index, step) in run.steps.enumerated() {
                let albums = step.ids.map { PlaylistVectors.Named(id: $0) }
                switch step.op {
                case "remember": store.remember(albums[0])
                case "queue": store.rememberQueue(albums)
                case "also": store.also(albums[0])
                default: Issue.record("an op the test doesn't know: \(step.op)")
                }
                let held = named.filter { store.get($0) != nil }.sorted()
                #expect(held == step.held, "\(run.name), step \(index) (\(step.op))")
                #expect(store.count == step.held.count, "\(run.name), step \(index)")
            }
        }
    }
}
