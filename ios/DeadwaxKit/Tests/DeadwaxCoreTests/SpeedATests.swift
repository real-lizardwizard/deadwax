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
        // (after review) never a downloaded album's cover - a file of its own, asked as before - nor a caller's own
        // revalidation of a copy it keeps
        var download = deadwax.coverRequest(coverID: "al-1", size: 1024)
        download.mayKeepOnDisk = false
        #expect(!CoverDisk.takes(download))
        #expect(deadwax.coverRequest(coverID: "al-1", size: 300).mayKeepOnDisk, "every request may, unless told not")
        var revalidating = deadwax.coverRequest(coverID: "al-1", size: 300)
        revalidating.headers["if-none-match"] = "\"abc\""
        #expect(!CoverDisk.takes(revalidating))
        // the place - not the first build's, which is removed - and the bound
        #expect(CoverDisk.folder == "deadwax-cover-disk")
        #expect(CoverDisk.oldFolder == "deadwax-covers")
        #expect(CoverDisk.diskBytes == 256 * 1024 * 1024)
    }

    /// (After review) The session's cookie is never written to disk with a cover: the request a cover is kept under is
    /// its address alone, and what is kept of the answer is the four headers that say what it is and how long it stands.
    @Test func aCoverIsKeptUnderItsAddressAloneAndNeverWithTheCookie() throws {
        let (deadwax, _) = client(session: "the-session")
        let request = deadwax.coverRequest(coverID: "al-1_6566", size: 300)
        #expect(request.headers["Cookie"] != nil, "the cover is asked with the session, as every route is")
        let key = CoverDisk.key(request)
        #expect(key.headers.isEmpty)
        #expect(key.headers["Cookie"] == nil)
        #expect(key.url == request.url && key.method == "GET" && key.body == nil)
        let archive = deadwax.archiveCoverRequest(ArchiveCoverID(.release, "b84ee12a-09ef-421b-82de-0441a926375b"),
                                                  size: 250)
        #expect(CoverDisk.key(archive).headers.isEmpty)
        // a 200's own headers, the four alone - never Set-Cookie, nor anything else deadwax answers
        let answer = ["Content-Type": "image/jpeg", "cache-control": "public, max-age=31536000, immutable",
                      "ETag": "\"x1\"", "Last-Modified": "Wed, 26 Nov 2026 10:00:00 GMT",
                      "Set-Cookie": "deadwax_session=the-session; HttpOnly", "Vary": "Cookie", "Content-Length": "4"]
        let kept = try #require(CoverDisk.kept(status: 200, headers: answer, now: 1_000))
        #expect(Set(kept.keys) == Set(CoverDisk.keptHeaders + [CoverDisk.keptAtHeader]))
        #expect(kept["Cache-Control"] == "public, max-age=31536000, immutable")
        #expect(kept[CoverDisk.keptAtHeader] == "1000.0")
        #expect(!kept.values.contains { $0.contains("the-session") })
        // a placeholder (no-store) and anything but a 200 are never kept
        #expect(CoverDisk.kept(status: 200, headers: ["Cache-Control": "no-store"], now: 1_000) == nil)
        #expect(CoverDisk.kept(status: 404, headers: ["Cache-Control": "private, max-age=60"], now: 1_000) == nil)
        #expect(CoverDisk.kept(status: 304, headers: ["ETag": "\"x1\""], now: 1_000) == nil)
    }

    /// (After review) A kept cover stands for its max-age - a day at most, whatever Navidrome's year says - and is then
    /// asked again with its validators; no-cache, or nothing said, asks every time.
    @Test func aKeptCoverStandsADayAtMostThenIsAskedWithItsValidators() throws {
        #expect(CoverDisk.freshMost == 86_400)
        #expect(CoverDisk.freshSeconds("public, max-age=31536000, immutable") == 86_400)
        #expect(CoverDisk.freshSeconds("private, max-age=604800") == 86_400, "the Archive's week, a day too")
        #expect(CoverDisk.freshSeconds("private, max-age=60") == 60)
        #expect(CoverDisk.freshSeconds("public, no-cache") == 0)
        #expect(CoverDisk.freshSeconds("no-cache, max-age=600") == 0)
        #expect(CoverDisk.freshSeconds("max-age=-5") == 0)
        #expect(CoverDisk.freshSeconds("max-age=soon") == 0)
        #expect(CoverDisk.freshSeconds(nil) == 0)
        #expect(CoverDisk.freshSeconds("No-Store") == nil)
        let year = try #require(CoverDisk.kept(status: 200, headers: ["Cache-Control": "public, max-age=31536000, immutable",
                                                                       "ETag": "\"x1\""], now: 1_000))
        #expect(CoverDisk.ask(held: year, now: 1_000) == .kept)
        #expect(CoverDisk.ask(held: year, now: 1_000 + 86_399) == .kept)
        #expect(CoverDisk.ask(held: year, now: 1_000 + 86_400) == .revalidate(["If-None-Match": "\"x1\""]))
        #expect(CoverDisk.ask(held: year, now: 999) == .revalidate(["If-None-Match": "\"x1\""]), "the clock moved back")
        let noCache = try #require(CoverDisk.kept(status: 200, headers: ["Cache-Control": "public, no-cache",
                                                                          "ETag": "\"x2\"",
                                                                          "Last-Modified": "Wed, 26 Nov 2026 10:00:00 GMT"],
                                                  now: 1_000))
        #expect(CoverDisk.ask(held: noCache, now: 1_000) == .revalidate(["If-None-Match": "\"x2\"",
                                                                          "If-Modified-Since": "Wed, 26 Nov 2026 10:00:00 GMT"]))
        // nothing to revalidate by: asked as it is (the copy still draws offline); nothing kept: asked as it is
        let bare = try #require(CoverDisk.kept(status: 200, headers: ["Content-Type": "image/png"], now: 1_000))
        #expect(CoverDisk.ask(held: bare, now: 1_000) == .fetch)
        #expect(CoverDisk.ask(held: nil, now: 1_000) == .fetch)
        #expect(CoverDisk.ask(held: ["ETag": "\"x3\"", "Cache-Control": "max-age=600"], now: 1_000)
                == .revalidate(["If-None-Match": "\"x3\""]), "a copy with no time kept stands no longer")
        // a 304 keeps the copy again as of then, its own Cache-Control and validators over the copy's; no-store drops it
        let again = try #require(CoverDisk.revalidated(noCache, by: ["cache-control": "private, max-age=600",
                                                                     "ETag": "\"x2\"", "Content-Type": "text/plain"],
                                                       now: 5_000))
        #expect(again["Cache-Control"] == "private, max-age=600" && again["ETag"] == "\"x2\"")
        #expect(again["Last-Modified"] == "Wed, 26 Nov 2026 10:00:00 GMT" && again["Content-Type"] == nil)
        #expect(CoverDisk.ask(held: again, now: 5_599) == .kept)
        #expect(CoverDisk.revalidated(noCache, by: ["Cache-Control": "no-store"], now: 5_000) == nil)
        let typed = try #require(CoverDisk.revalidated(bare, by: ["Content-Type": "text/html"], now: 5_000))
        #expect(typed["Content-Type"] == "image/png", "a 304's type says nothing of the body it didn't send")
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

    // MARK: fix 5 - the artist page's requests in order

    @Test func anArtistPageAsksWhichAlbumsAreYoursOnlyWhenItIsNotInHandOrAWriteCame() {
        // not in hand (the first page of a launch, another person): asked, whatever was asked before
        #expect(OwnedCheck.asks(inHand: false, writes: 0, askedUnder: nil))
        #expect(OwnedCheck.asks(inHand: false, writes: 2, askedUnder: 2))
        // in hand, and an artist page has asked under these writes: not asked again - as the album page doesn't
        #expect(!OwnedCheck.asks(inHand: true, writes: 2, askedUnder: 2))
        // in hand, but no artist page has asked since the person signed in, or a write came since one did: asked
        #expect(OwnedCheck.asks(inHand: true, writes: 0, askedUnder: nil))
        #expect(OwnedCheck.asks(inHand: true, writes: 3, askedUnder: 2))
    }

    // MARK: fix 6 - Requests' polling

    @Test func requestsRootIsLookedAtOnceASecondWhileNothingMoves() {
        func delay(open: Bool, active: Bool, filing: Bool) -> Double? {
            RequestsPolling.delay(open: open, hasActive: active, filing: filing, online: true, watching: .requests)
        }
        #expect(RequestsPolling.idleOpenSeconds == 1 && RequestsPolling.openSeconds == 0.5)
        // the root showing, nothing on its way: once a second
        #expect(delay(open: true, active: false, filing: false) == 1)
        // something on its way, or being filed: the web's half second, from the first look that sees it
        #expect(delay(open: true, active: true, filing: false) == 0.5)
        #expect(delay(open: true, active: true, filing: true) == 0.5)
        #expect(delay(open: true, active: false, filing: true) == 0.5)
        // away from the root, as before
        #expect(delay(open: false, active: true, filing: true) == 1)
        #expect(delay(open: false, active: true, filing: false) == 5)
        #expect(delay(open: false, active: false, filing: false) == nil)
    }
}
