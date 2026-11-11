import Foundation
import Testing
@testable import DeadwaxCore

/// The album list kept across launches (KeptAlbumIndex, the phone's own - D2): read back only for the server, person
/// and scope it was written for, the answer exactly as it was read, and each name its own file.
@Suite struct LibraryKeptTests {
    static let server = "http://192.168.1.10:8090"

    static let every = IndexAlbum(id: "abbey", name: "Abbey Road", artist: "The Beatles", artistId: "ar-1",
                                  coverArt: "al-abbey", year: 1969, genre: "Rock", created: "2026-09-02T10:00:00Z",
                                  played: "2026-10-01T10:00:00Z", playCount: 3, starred: "2026-10-02T10:00:00Z",
                                  musicBrainzId: "", songCount: 17, duration: 2832)
    static let bare = IndexAlbum(id: "bare")

    static func kept(user: String = "james", scope: AlbumScope = .yours,
                     answer: AlbumIndexAnswer = AlbumIndexAnswer(albums: [every, bare], truncated: false)) -> KeptAlbumIndex {
        KeptAlbumIndex(server: server, user: user, scope: scope, etag: #""3f2a9c""#, at: 1_791_210_151_000, answer: answer)
    }

    @Test func aListReadsBackAsItWasKept() throws {
        let kept = Self.kept()
        let read = try #require(KeptAlbumIndex.read(try kept.encoded(), server: Self.server, user: "james", scope: .yours))
        #expect(read == kept)
        #expect(read.answer.albums == [Self.every, Self.bare])
        #expect(read.etag == #""3f2a9c""#)
        let at: Int64 = 1_791_210_151_000
        #expect(read.at == at)
        #expect(read.version == KeptAlbumIndex.currentVersion)
    }

    @Test func aCappedListStaysCapped() throws {
        let kept = Self.kept(answer: AlbumIndexAnswer(albums: [Self.bare], truncated: true))
        let read = try #require(KeptAlbumIndex.read(try kept.encoded(), server: Self.server, user: "james", scope: .yours))
        #expect(read.answer.truncated)
    }

    /// The dev stand-in's float `created` was read as nil (IndexAlbum is lenient): kept, it stays nil - "Date
    /// unknown", as the web reads it - and the list is kept whole.
    @Test func aFieldReadAsNothingIsKeptAsNothing() throws {
        let json = Data(#"{"albums":[{"id":"nobody","name":"Untitled","created":1729000000.5,"year":1999}],"truncated":false}"#.utf8)
        let answer = try JSONDecoder().decode(AlbumIndexAnswer.self, from: json)
        let kept = Self.kept(scope: .store, answer: answer)
        let read = try #require(KeptAlbumIndex.read(try kept.encoded(), server: Self.server, user: "james", scope: .store))
        #expect(read.answer.albums.first?.created == nil)
        #expect(read.answer.albums.first?.year == 1999)
        #expect(read.answer.albums.first?.name == "Untitled")
    }

    @Test func aListIsNeverDrawnForSomeoneElse() throws {
        let data = try Self.kept().encoded()
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: "james", scope: .yours) != nil)
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: "ethan", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: "James", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: "", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: "james", scope: .store) == nil)
        #expect(KeptAlbumIndex.read(data, server: "http://192.168.1.11:8090", user: "james", scope: .yours) == nil)
    }

    /// Two spellings of one name a disk may fold into one file: the record says whose it is, as code units.
    @Test func namesTheDiskMightFoldStayApart() throws {
        let composed = "Jos\u{E9}"
        let decomposed = "Jose\u{301}"
        let data = try Self.kept(user: composed).encoded()
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: composed, scope: .yours) != nil)
        #expect(KeptAlbumIndex.read(data, server: Self.server, user: decomposed, scope: .yours) == nil)
        #expect(KeptAlbumIndex.fileName(user: composed, scope: .yours) != KeptAlbumIndex.fileName(user: decomposed, scope: .yours))
    }

    @Test func anotherVersionOrOtherBytesAreNoList() throws {
        let data = try Self.kept().encoded()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = KeptAlbumIndex.currentVersion + 1
        let other = try JSONSerialization.data(withJSONObject: object)
        #expect(KeptAlbumIndex.read(other, server: Self.server, user: "james", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(Data("not json".utf8), server: Self.server, user: "james", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(Data(), server: Self.server, user: "james", scope: .yours) == nil)
        #expect(KeptAlbumIndex.read(Data(#"{"albums":[],"truncated":false}"#.utf8), server: Self.server, user: "james",
                                    scope: .yours) == nil)
    }

    @Test func eachNameIsItsOwnFileName() {
        #expect(KeptAlbumIndex.fileName(user: "james", scope: .yours) == "user-james.yours.json")
        #expect(KeptAlbumIndex.fileName(user: "james", scope: .store) == "user-james.store.json")
        #expect(KeptAlbumIndex.fileName(user: "", scope: .store) == "user-.store.json")
        #expect(KeptAlbumIndex.safeName("a/b") == "a%2Fb")
        #expect(KeptAlbumIndex.safeName("..") == "%2E%2E")
        #expect(KeptAlbumIndex.safeName("%") == "%25")
        #expect(KeptAlbumIndex.safeName("a%2Fb") == "a%252Fb")
        #expect(KeptAlbumIndex.safeName("\u{E9}") == "%C3%A9")
        #expect(KeptAlbumIndex.safeName("\n") == "%0A")
        #expect(KeptAlbumIndex.safeName("James") != KeptAlbumIndex.safeName("james"))
        #expect(KeptAlbumIndex.folder(server: Self.server) == ["http%3A%2F%2F192%2E168%2E1%2E10%3A8090", "album-index"])
        // nothing but letters, digits and the escapes' "%": no separator, no dot, nothing a file system reads twice
        for name in ["a/b", "..", "x y", "\u{1F3B5}", "Jos\u{E9}", "[::1]:8090"] {
            #expect(KeptAlbumIndex.safeName(name).unicodeScalars.allSatisfy {
                ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A)
                    || ($0.value >= 0x61 && $0.value <= 0x7A) || $0 == "%"
            })
        }
    }

    /// One name to one file name: decoding the escapes gives the name back, so no two names share a file.
    @Test func aSafeNameDecodesToTheName() {
        for name in ["james", "a/b", "%", "a%2Fb", "Jos\u{E9}", "Jose\u{301}", "", "\u{1F3B5} music", "[::1]:8090"] {
            #expect(KeptAlbumIndex.safeName(name).removingPercentEncoding == name)
        }
    }
}
