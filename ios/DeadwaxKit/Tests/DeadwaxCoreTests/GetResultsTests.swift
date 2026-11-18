import Foundation
import Testing
@testable import DeadwaxCore

/// Artwork and Lyrics' Gets (Phase 8, slice 3 - phase8-managing.md 3.5): what each sends - the web's very bodies, never
/// replacing anything - what each answer reads as, a CD art picture asked by name, and how a run that didn't work is
/// told apart: a 404 is a fact (nothing on the Archive), a refusal wrote nothing, a 5xx or no answer may have written.
@Suite struct GetResultsTests {
    @Test func eachGetSendsTheWebsBodyAndNeverReplaces() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/art/fetch", 200, #"{"written": "cover.jpg", "replaced": null}"#)
        let cover = try await deadwax.getCover(path: "A/B")
        #expect(cover.written == "cover.jpg")
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B"), "replace": .bool(false), "release_mbid": .null],
                "GetArtButton's body: the folder's own release, nothing replaced")
        #expect(transport.last?.timeout == 120)

        transport.answer("/deadwax/library/lyrics/fetch", 200,
                         #"{"written": 3, "replaced": 0, "kept": 8, "instrumental": 0, "missing": 1, "failed": 0, "untagged": 0, "synced": 2, "unexpected": 1}"#)
        let lyrics = try await deadwax.getLyrics(ScanAlbum(path: "A/B", trackCount: 12, lyricsCount: 8))
        #expect(lyrics == LyricsSummary(written: 3, kept: 8, missing: 1, synced: 2))
        #expect(GetResults.lyricsResult(lyrics) == "Saved lyrics for 3 tracks (2 synced), 8 already had them, 1 not on LRCLIB.")
        #expect(GetResults.label(.lyrics, { var run = GetRun(kind: .lyrics, path: "A/B"); run.done(lyrics); return run }(),
                                 trackCount: 12) == "Lyrics \u{b7} 11 of 12")
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B"), "replace": .bool(false), "retime": .bool(false)])
        // four tracks to ask, two at a time: 540 s, under the route's own 600
        #expect(transport.last?.timeout == 600)
        _ = try await deadwax.getLyrics(ScanAlbum(path: "A/B", trackCount: 12))
        #expect(transport.last?.timeout == 1380, "twelve tracks asked: six rounds of 220 s, and the minute's margin")

        transport.answer("/deadwax/library/disc_art/fetch", 200, #"{"written": ["disc1.png", "disc2.png"], "source": "fanart.tv"}"#)
        let disc = try await deadwax.getDiscArt(ScanAlbum(path: "A/B", discCount: 2))
        #expect(disc == DiscArtFetched(written: ["disc1.png", "disc2.png"], source: "fanart.tv"))
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B")])
        #expect(transport.last?.timeout == 600,
                "two discs: the listing, fanart.tv's, two pictures and the margin - 580 s")
        _ = try await deadwax.getDiscArt(ScanAlbum(path: "A/B", discCount: 1))
        #expect(transport.last?.timeout == 420)
    }

    @Test func aCDArtPictureIsAskedByItsNameAndAMissingOneIsNothing() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/disc_art", 404, #"{"detail": "no such image"}"#)
        #expect(try await deadwax.libraryDiscArt(path: "A/B", file: "disc 2.png") == nil)
        #expect(transport.last?.url.path == "/deadwax/library/disc_art")
        #expect(transport.last?.headers["Accept"] == "image/*")
        let query = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.map(\.name) == ["album", "file"] && query.map(\.value) == ["A/B", "disc 2.png"])
        transport.answer("/deadwax/library/disc_art", 200, "PNG")
        #expect(try await deadwax.libraryDiscArt(path: "A/B", file: "disc.png") == Data("PNG".utf8))
        transport.answer("/deadwax/library/disc_art", 500, #"{"detail": "boom"}"#)
        await #expect(throws: APIFailure.self) { try await deadwax.libraryDiscArt(path: "A/B", file: "disc.png") }
    }

    @Test func anAnswerMissingItsFieldsIsReadAsNothing() throws {
        let summary = try JSONDecoder().decode(LyricsSummary.self, from: Data(#"{"written": "3", "kept": null}"#.utf8))
        #expect(summary == LyricsSummary())
        let disc = try JSONDecoder().decode(DiscArtFetched.self, from: Data(#"{"written": "disc.png"}"#.utf8))
        #expect(disc.written.isEmpty && disc.source.isEmpty)
    }

    /// LibraryParts' run: a 404 is "none" (Look again) for both pictures; any other failure "failed" (Try again).
    /// The phone tells a refusal (nothing written) from a 5xx or no answer at all (it may have written - the folder is
    /// read again), as Release's apply does; a cancelled Get is neither.
    @Test func howARunEndedDecidesWhetherTheFolderIsReadAgain() throws {
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        func ended(_ kind: GetResults.Kind, _ error: any Error) -> GetRun {
            var run = GetRun(kind: kind, path: "A/B")
            run.failed(error, admin: false)
            return run
        }
        let none = APIFailure.answered(.init(status: 404, method: "POST", path: "/library/art/fetch",
                                             detail: "the Cover Art Archive has no front cover for that release"))
        #expect(ended(.cover, none).state == .none && !ended(.cover, none).wrote)
        #expect(ended(.cover, none).said == "The Cover Art Archive has no front cover for that release.")
        #expect(GetResults.label(.cover, ended(.cover, none), trackCount: 1) == "Look again")
        #expect(ended(.disc, none).state == .none)

        let refused = APIFailure.answered(.init(status: 400, method: "POST", path: "/library/disc_art/fetch",
                                                detail: "this album already has CD art: disc.jpg"))
        #expect(ended(.disc, refused).state == .failed && !ended(.disc, refused).wrote)
        #expect(ended(.disc, refused).said == "This album already has CD art: disc.jpg.")

        let lost = APIFailure.timeout(.init(server: server, method: "POST", path: "/library/lyrics/fetch",
                                            reason: "The request timed out.", device: .iPhone))
        #expect(ended(.lyrics, lost).state == .unanswered && ended(.lyrics, lost).wrote)
        #expect(GetResults.label(.lyrics, ended(.lyrics, lost), trackCount: 12) == "Try again")
        let crashed = APIFailure.answered(.init(status: 500, method: "POST", path: "/library/art/fetch"))
        #expect(ended(.cover, crashed).state == .unanswered)
        #expect(ended(.cover, crashed).said?.isEmpty == false && ended(.cover, crashed).said?.contains("500") == false)

        var working = GetRun(kind: .disc, path: "A/B")
        #expect(working.state == .working && !working.wrote && working.said == nil)
        #expect(GetResults.label(.disc, working, trackCount: 1) == "Getting CD art\u{2026}")
        working.done()
        #expect(working.wrote && working.said == nil && working.summary == nil)
        #expect(APIFailure.isCancellation(CancellationError()), "the model checks it first, and never ends a cancelled Get")
    }

    @Test func theButtonsAreOfferedAsTheWebOffersThem() {
        let bare = ScanAlbum(path: "A/B", trackCount: 12, lyricsCount: 12)
        #expect(!GetResults.offersCover(bare) && !GetResults.offersDiscArt(bare) && !GetResults.offersLyrics(bare, ran: false))
        #expect(GetResults.offersLyrics(bare, ran: true), "once run, it stays to say what it came to")
        let matched = ScanAlbum(path: "A/B", releaseMbid: "b84ee12a", trackCount: 12, lyricsCount: 8, discArt: ["cd.jpg"])
        #expect(GetResults.offersCover(matched) && GetResults.offersDiscArt(matched) && GetResults.offersLyrics(matched, ran: false))
        let own = ScanAlbum(path: "A/B", releaseMbid: "b84ee12a", art: "file", discArt: ["Disc1.png", "cd.jpg"])
        #expect(!GetResults.offersCover(own) && !GetResults.offersDiscArt(own))
        #expect(GetResults.discArtPointer(own) == "deadwax never replaces CD art it saved.")
        #expect(GetResults.lyricsLine(8, 12) == "8 of 12 tracks have lyrics saved beside them, as a .lrc.")
        #expect(GetResults.lyricsLine(1, 1) == "1 of 1 track has lyrics saved beside it, as a .lrc.")
    }
}
