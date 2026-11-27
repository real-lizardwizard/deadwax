import Foundation
import Testing
@testable import DeadwaxCore

/// Speed A - what's asked again (notes/ios.md "Speed A: what's asked again"): the pure parts of its six fixes.
@Suite struct SpeedATests {
    // MARK: fix 1 - covers kept on disk

    @Test func onlyTheCoversAreKeptOnDisk() {
        let (deadwax, _) = client(session: "s")
        // Navidrome's covers at a size, and the Cover Art Archive's fronts through the relay
        #expect(CoverDisk.takes(deadwax.coverRequest(coverID: "al-1_6566", size: 300)))
        #expect(CoverDisk.takes(deadwax.coverRequest(coverID: "a/b c", size: 300)), "an id with a slash is one segment")
        #expect(CoverDisk.takes(deadwax.archiveCoverRequest(ArchiveCoverID(.release, "b84ee12a-09ef-421b-82de-0441a926375b"),
                                                            size: 250)))
        // never the viewer's full size (its own capped read), nor anything else
        #expect(!CoverDisk.takes(deadwax.fullCoverRequest(coverID: "al-1")))
        #expect(!CoverDisk.takes(deadwax.streamRequest(songID: "s1", format: "raw")))
        #expect(!CoverDisk.takes(deadwax.discArtRequest(albumID: "al-1", disc: 1)))
        #expect(!CoverDisk.takes(deadwax.request(Routes.album, path: ["album_id": "al-1"])))
        #expect(!CoverDisk.takes(deadwax.request(Routes.libraryAlbums, query: [("tracks", "false")])))
        #expect(!CoverDisk.takes(deadwax.request(Routes.libraryArt, query: [("album", "A/B")])),
                "a folder's cover is asked by its path: an Edit replaces it under the same address")
        var posted = deadwax.coverRequest(coverID: "al-1", size: 300)
        posted.method = "POST"
        #expect(!CoverDisk.takes(posted))
        // the place and the bound
        #expect(CoverDisk.folder == "deadwax-covers")
        #expect(CoverDisk.diskBytes == 256 * 1024 * 1024)
    }

    @Test func aTemplatesPartsAreEachOneSegment() {
        #expect(CoverDisk.matches("/deadwax/navidrome/cover/al-1", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(!CoverDisk.matches("/deadwax/navidrome/cover/", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(!CoverDisk.matches("/deadwax/navidrome/cover/a/b", "/deadwax/navidrome/cover/{cover_id}"))
        #expect(CoverDisk.matches("/deadwax/coverart/release/x", "/deadwax/coverart/{kind}/{mbid}"))
        #expect(!CoverDisk.matches("/deadwax/coverart/release", "/deadwax/coverart/{kind}/{mbid}"))
    }

    // MARK: fix 2 - an album's answer kept

    private typealias Stamp = KeptAnswers<String>.Stamp

    @Test func anAnswerKeptIsReadUnderTheSameStampAlone() {
        var kept = KeptAnswers<String>(most: KeptAlbums.most)
        let now = Stamp(person: 1, session: 1, writes: 0)
        kept.keep("al-1", "Dummy", stamp: now)
        #expect(kept.answer("al-1", stamp: now) == "Dummy")
        #expect(kept.answer("al-2", stamp: now) == nil)
        // a write deadwax was told of (an Edit's apply, a delete, a re-file) drops everything at the next look
        let written = Stamp(person: 1, session: 1, writes: 1)
        #expect(kept.answer("al-1", stamp: written) == nil)
        #expect(kept.count == 0)
        // and an answer asked before it, landing after, keeps nothing - nor is anything read under the old stamp
        kept.keep("al-1", "Dummy (before the write)", stamp: now)
        #expect(kept.answer("al-1", stamp: written) == nil)
        #expect(kept.answer("al-1", stamp: now) == nil)
        kept.keep("al-1", "Dummy", stamp: written)
        #expect(kept.answer("al-1", stamp: written) == "Dummy")
        // an older ask landing late takes nothing away from what is kept under the newer stamp
        kept.keep("al-2", "Third (before the write)", stamp: now)
        #expect(kept.answer("al-1", stamp: written) == "Dummy")
        #expect(kept.answer("al-2", stamp: written) == nil)
    }

    @Test func anotherPersonNeverReadsTheAnswersOfTheOneBefore() {
        var kept = KeptAnswers<String>(most: KeptAlbums.most)
        let james = Stamp(person: 1, session: 1, writes: 5)
        kept.keep("al-1", "James's", stamp: james)
        // signed out, someone else signed in: the person counter and the pages' session move, the writes start again
        let ethan = Stamp(person: 2, session: 2, writes: 0)
        #expect(kept.answer("al-1", stamp: ethan) == nil)
        // James's ask landing late keeps nothing for Ethan
        kept.keep("al-2", "James's late one", stamp: james)
        #expect(kept.answer("al-2", stamp: ethan) == nil)
        // a sign-in again as the same person is another person to the store too
        kept.keep("al-1", "Ethan's", stamp: ethan)
        #expect(kept.answer("al-1", stamp: Stamp(person: 3, session: 3, writes: 0)) == nil)
    }

    @Test func theOldestKeptGoesPastTheMostAndOneCanBeForgotten() {
        var kept = KeptAnswers<String>(most: 3)
        let now = Stamp(person: 1, session: 1, writes: 0)
        for id in ["a", "b", "c"] { kept.keep(id, id, stamp: now) }
        // kept again moves it to the newest
        kept.keep("a", "a again", stamp: now)
        kept.keep("d", "d", stamp: now)
        #expect(kept.answer("b", stamp: now) == nil)
        #expect(kept.answer("a", stamp: now) == "a again")
        #expect(kept.count == 3)
        kept.forget("a")
        #expect(kept.answer("a", stamp: now) == nil)
        #expect(kept.count == 2)
        #expect(KeptAlbums.most == 40)
    }

    // MARK: fix 3 - Edit opens without the whole scan

    private static let scanBody = #"{"albums": [{"path": "Portishead/Dummy", "artist": "Portishead", "album": "Dummy"}], "issue_types": {}, "problem": null}"#

    @Test func aKeptScanIsReadBackOnlyForItsServerAndSession() throws {
        let kept = ScanKept(server: "192.168.3.20:8090", session: "cookie-1", etag: "\"abc\"", body: Data(Self.scanBody.utf8))
        let bytes = try kept.encoded()
        #expect(ScanKept.read(bytes, server: "192.168.3.20:8090", session: "cookie-1") == kept)
        // another person (another session), a sign-in again, another server, logins off: none of theirs
        #expect(ScanKept.read(bytes, server: "192.168.3.20:8090", session: "cookie-2") == nil)
        #expect(ScanKept.read(bytes, server: "192.168.3.21:8090", session: "cookie-1") == nil)
        #expect(ScanKept.read(bytes, server: "192.168.3.20:8090", session: nil) == nil)
        #expect(ScanKept.read(Data("not a record".utf8), server: "192.168.3.20:8090", session: "cookie-1") == nil)
        // the cookie itself is never written - only its digest
        #expect(!String(decoding: bytes, as: UTF8.self).contains("cookie-1"))
        #expect(ScanKept.who(nil) == "-" && ScanKept.who("") == "-" && ScanKept.who("cookie-1") != ScanKept.who("cookie-2"))
        // another version is no record
        let older = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""version":1"#, with: #""version":0"#)
        #expect(ScanKept.read(Data(older.utf8), server: "192.168.3.20:8090", session: "cookie-1") == nil)
        // the body is deadwax's, read as a fresh answer is, with the 304's headers laid on
        let answer = try #require(kept.answer(HTTPResponse(status: 304, headers: ["X-Scanned-At": "1763251200.5",
                                                                                   "X-Scan-Stale": "1"])))
        #expect(answer.albums.map(\.path) == ["Portishead/Dummy"])
        #expect(answer.scannedAt == 1_763_251_200.5 && answer.stale)
        #expect(ScanKept.folder(server: "192.168.3.20:8090") == ["deadwax", "192%2E168%2E3%2E20%3A8090", "library-scan"])
    }

    @Test func aScanIsWrittenAndReadInTheCachesFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("speed-a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let files = ScanFiles(base: base)
        #expect(files.read(server: "s", session: "c") == nil)
        let kept = ScanKept(server: "s", session: "c", etag: "\"1\"", body: Data(Self.scanBody.utf8))
        files.write(kept)
        #expect(files.read(server: "s", session: "c") == kept)
        #expect(files.file(server: "s").path.hasSuffix("deadwax/s/library-scan/scan.kept"))
        // the next person's scan replaces it: one per server
        let next = ScanKept(server: "s", session: "d", etag: "\"2\"", body: Data(Self.scanBody.utf8))
        files.write(next)
        #expect(files.read(server: "s", session: "c") == nil)
        #expect(files.read(server: "s", session: "d") == next)
    }

    @Test func theScanIsAskedWithTheKeptETagAndA304IsThatScan() async throws {
        let (deadwax, transport) = client(session: "s")
        transport.answer("/deadwax/library/albums", 200, Self.scanBody, headers: ["ETag": "\"abc\"", "X-Scan-Stale": "0"])
        guard case .fresh(let answer, let etag, let body) = try await deadwax.libraryScanKeeping(ifNoneMatch: nil) else {
            Issue.record("no answer"); return
        }
        #expect(transport.last?.url.query == "tracks=false" && transport.last?.headers["If-None-Match"] == nil)
        #expect(etag == "\"abc\"" && body == Data(Self.scanBody.utf8) && answer.albums.count == 1)
        transport.answer("/deadwax/library/albums", 304, "", headers: ["ETag": "\"abc\"", "X-Scanned-At": "5"])
        guard case .unchanged(let unchanged) = try await deadwax.libraryScanKeeping(ifNoneMatch: "\"abc\"") else {
            Issue.record("not unchanged"); return
        }
        #expect(transport.last?.headers["If-None-Match"] == "\"abc\"")
        #expect(unchanged.header("X-Scanned-At") == "5")
        // a 304 to a request that sent no ETag is no answer
        await #expect(throws: APIFailure.self) { _ = try await deadwax.libraryScanKeeping(ifNoneMatch: nil) }
    }

    // MARK: fix 4 - Artists' one-minute rule

    @Test func theArtistsAreAskedAgainAsTheyShowOnlyOnceTheListIsOverAMinuteOld() {
        typealias Landed = ListFreshness.Landed
        // the album index's own minute
        #expect(ListFreshness.freshMs == AlbumIndexState.freshMs && ListFreshness.freshMs == 60_000)
        // none in hand: asked
        #expect(ListFreshness.asks(landed: nil, writes: 0, failed: false, onItsWay: nil, now: 1_000))
        // landed under a minute ago: drawn as it is, nothing asked - a minute exactly is still fresh, as the index's
        let landed = Landed(at: 1_000, writes: 3, settled: true)
        #expect(!ListFreshness.asks(landed: landed, writes: 3, failed: false, onItsWay: nil, now: 1_000 + 30_000))
        #expect(!ListFreshness.asks(landed: landed, writes: 3, failed: false, onItsWay: nil, now: 1_000 + 60_000))
        #expect(ListFreshness.asks(landed: landed, writes: 3, failed: false, onItsWay: nil, now: 1_000 + 60_001))
        // the same edge as the album index's refreshIfOld
        var index = AlbumIndexState()
        index.restore(.store, answer: AlbumIndexAnswer(albums: []), etag: nil, at: 1_000)
        let atAMinute = index.refreshIfOld(.store, now: 1_000 + 60_000)
        let pastIt = index.refreshIfOld(.store, now: 1_000 + 60_001)
        #expect(!atAMinute && pastIt)
        // a write told of since it was asked (an Edit's apply, a delete, a re-file): asked at once, as a new generation
        #expect(ListFreshness.asks(landed: landed, writes: 4, failed: false, onItsWay: nil, now: 1_000 + 1))
        // and one asked within the settle of the writes moving may be from before Navidrome scanned them: asked again at
        // each show until one asked after it has landed
        #expect(!ListFreshness.settled(askedAt: 5_000 + 9_999, writesMovedAt: 5_000))
        #expect(ListFreshness.settled(askedAt: 5_000 + 10_000, writesMovedAt: 5_000) && AlbumEdit.settleMs == 10_000)
        #expect(ListFreshness.settled(askedAt: 5_000, writesMovedAt: nil))
        let early = Landed(at: 1_000, writes: 4, settled: false)
        #expect(ListFreshness.asks(landed: early, writes: 4, failed: false, onItsWay: nil, now: 1_000 + 1))
        #expect(!ListFreshness.asks(landed: early, writes: 4, failed: false, onItsWay: 4, now: 1_000 + 1))
        // the last ask failed: asked again as the screen shows (offline and back, a sign-in that ended)
        #expect(ListFreshness.asks(landed: landed, writes: 3, failed: true, onItsWay: nil, now: 1_000 + 1))
        // never while one asked under the same writes is on its way - one asked before a write is no answer to it
        #expect(!ListFreshness.asks(landed: nil, writes: 3, failed: false, onItsWay: 3, now: 1_000))
        #expect(!ListFreshness.asks(landed: landed, writes: 3, failed: true, onItsWay: 3, now: 1_000 + 120_000))
        #expect(ListFreshness.asks(landed: landed, writes: 4, failed: false, onItsWay: 3, now: 1_000 + 1))
    }
}
