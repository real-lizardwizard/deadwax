import Foundation
import Testing
@testable import DeadwaxCore

/// Library care (Phase 8, slice 7 - phase8-managing.md 6): what the vectors can't reach - the four routes as the web asks
/// them, the scan's size and time the page reads, and every decision CareRuns and Held.Flow make for the page: one run
/// at a time, Stop and the phone's own stops landing after the album out, a kind held behind until a read begun after
/// its run, Rescan's busy and what follows it, the reads the page makes, and In nobody's library one write at a time.
@Suite struct LibraryCareTests {
    static func album(_ path: String, art: String = "", release: String = "mbid", discArt: [String] = [], lyrics: Int = 0,
                      tracks: Int = 10, artist: String = "Björk", name: String = "Post") -> ScanAlbum {
        ScanAlbum(path: path, artist: artist, album: name, releaseMbid: release, art: art, trackCount: tracks,
                  lyricsCount: lyrics, discArt: discArt)
    }

    static let five = (1...5).map { album("Björk/Album \($0)") }

    /// A CareRuns with a read to trust in hand.
    static func ready() -> CareRuns {
        var runs = CareRuns()
        runs.readLanded(runs.readBegan())
        return runs
    }

    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    static let noAnswer = APIFailure.timeout(.init(server: server, method: "POST", path: "/library/art/fetch", reason: "timed out"))

    // MARK: the routes

    @Test func rescanIsAskedWithoutTracksAndReadsItsHeaders() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/rescan", 200,
                         #"{"albums": [{"path": "Björk/Post (1995)", "artist": "Björk", "album": "Post", "track_count": 11, "total_size": 412000000}], "problem": null, "issue_types": {}}"#,
                         headers: ["X-Scanned-At": "1763300000.5", "X-Scan-Seconds": "4.21", "X-Scan-Cached": "0",
                                   "X-Scan-Stale": "0", "ETag": "\"abc\""])
        let (answer, etag) = try await deadwax.rescan()
        #expect(transport.last?.method == "POST")
        #expect(transport.last?.url.query == "tracks=false")
        #expect(transport.last?.timeout == 300)
        #expect(transport.last?.body == nil, "nothing sent: the route takes only its query")
        #expect(answer.albums.map(\.path) == ["Björk/Post (1995)"])
        #expect(answer.albums.first?.totalSize == 412_000_000)
        #expect(answer.scannedAt == 1_763_300_000.5)
        #expect(answer.scanSeconds == 4.21)
        #expect(!answer.stale)
        #expect(etag == "\"abc\"")

        // a scan without the header took no time anyone knows
        transport.answer("/deadwax/library/rescan", 200, #"{"albums": []}"#)
        #expect(try await deadwax.rescan().answer.scanSeconds == 0)
        // without Look after the library: a 403, in a Managing page's words
        transport.answer("/deadwax/library/rescan", 403, #"{"detail": "needs Look after the library"}"#)
        do {
            _ = try await deadwax.rescan()
            Issue.record("a 403 is thrown")
        } catch {
            #expect(EditWords.said(error, failed: LibraryCare.readFailed, admin: false) == EditWords.noPermission)
            #expect(RetagFlow.outcome(of: error) == .refused)
        }
    }

    @Test func inNobodysLibraryIsAskedAsTheWebAsksIt() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/held", 200, #"""
        {"count": 2,
         "albums": [{"id": 4, "path": "A/B", "artist": "A", "album": "B", "edition": "", "year": "1999", "release_mbid": null,
                     "formats": ["FLAC"], "track_count": 9},
                    {"path": "no id - left out"},
                    {"id": 5, "path": "C/D", "artist": "C", "album": "", "edition": "Deluxe", "year": "", "release_mbid": "x",
                     "formats": [], "track_count": 0}],
         "flags": [{"id": 7, "album_id": 3, "artist": null, "album": "Post", "path": null, "release_mbid": null,
                    "users": ["ana", "ben"], "created_at": 1763300000}]}
        """#)
        let held = try await deadwax.heldByNobody()
        #expect(transport.last?.method == "GET" && transport.last?.timeout == 30)
        #expect(held.count == 2)
        #expect(held.albums.map(\.id) == [4, 5])
        #expect(held.albums[0] == Held.UnheldAlbum(id: 4, path: "A/B", artist: "A", album: "B", year: "1999", formats: ["FLAC"],
                                             trackCount: 9))
        #expect(Held.albumName(held.albums[1]) == "Unknown album · C")
        #expect(held.flags == [Held.Flag(id: 7, albumId: 3, album: "Post", users: ["ana", "ben"], createdAt: 1_763_300_000)])
        #expect(Held.flagName(held.flags[0]) == "Post")
        #expect(Held.flagWords(held.flags[0]) == "ana and ben asked for it. Every file was already in its folder, which "
                + "holds another pressing or an untagged copy - so nobody was given it.")

        transport.answer("/deadwax/library/held/flags/7/add", 200, #"{"added": true, "users": ["ana", "ben"]}"#)
        #expect(try await deadwax.addFlagged(7) == Held.Added(added: true, users: ["ana", "ben"]))
        #expect(transport.last?.method == "POST" && transport.last?.body == nil && transport.last?.timeout == 20)
        transport.answer("/deadwax/library/held/flags/7/dismiss", 200, #"{"dismissed": true}"#)
        #expect(try await deadwax.dismissFlag(7) == Held.Dismissed(dismissed: true))
        #expect(transport.last?.url.path == "/deadwax/library/held/flags/7/dismiss" && transport.last?.timeout == 20)

        // dealt with already: deadwax's own words, shown as they came
        transport.answer("/deadwax/library/held/flags/7/add", 409, #"{"detail": "That has been dealt with already."}"#)
        do {
            _ = try await deadwax.addFlagged(7)
            Issue.record("a 409 is thrown")
        } catch {
            #expect(RetagFlow.outcome(of: error) == .refused)
            #expect(EditWords.said(error, failed: Held.addFailed, admin: false) == "That has been dealt with already.")
        }
        // no database: a 503, deadwax's words still said
        transport.answer("/deadwax/library/held", 503, #"{"detail": "deadwax can't read its database, so it can't say who holds what"}"#)
        do {
            _ = try await deadwax.heldByNobody()
            Issue.record("a 503 is thrown")
        } catch {
            #expect(EditWords.said(error, failed: Held.readFailed, admin: false).hasPrefix("deadwax can't read its database"))
        }
    }

    @Test func theRoutesAreListedAndGivenTheirTime() {
        for endpoint in [Routes.rescan, Routes.held, Routes.heldAdd, Routes.heldDismiss] {
            #expect(Routes.all.contains(endpoint))
        }
        #expect(Routes.rescan.method == "POST" && Routes.rescan.query == ["tracks"])
        #expect(Routes.held.method == "GET")
        #expect(Routes.timeouts[Routes.rescan] == 300)
        #expect(Routes.timeouts[Routes.held] == 30)
        #expect(Routes.timeouts[Routes.heldAdd] == 20 && Routes.timeouts[Routes.heldDismiss] == 20)
        // the runs' steps are slice 1's and 3's routes, each with its own wait
        #expect(Routes.timeouts[Routes.artFetch] == 120)
        #expect(EditWaits.lyrics(Self.album("A/B", tracks: 40)) >= Routes.timeouts[Routes.lyricsFetch]!)
    }

    // MARK: runs

    @Test func aRunGoesOneAlbumAtATimeAndTellsTheCountOfEachWrite() throws {
        var runs = Self.ready()
        let got1 = runs.start(.covers, Self.five, allowed: true, online: true)
        #expect(got1)
        #expect(runs.stopLabel(.covers) == "Stop after this album · 1 of 5")
        guard case .album(let first) = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        #expect(first.path == "Björk/Album 1")
        // nothing more while that one is out
        let got2 = runs.next(allowed: true, online: true)
        #expect(got2 == .nothing)
        let got3 = runs.finished(.answered(.init(written: 1)))
        #expect(got3)
        #expect(runs.stopLabel(.covers) == "Stop after this album · 2 of 5")
        guard case .album = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        let got4 = runs.finished(.answered(.init(missing: 1)))
        #expect(!got4, "none to find: nothing written, nothing told")
        guard case .album = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        let got5 = runs.finished(.unanswered(.init(failed: 1)))
        #expect(got5, "no answer: it may have written")
        guard case .album = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        let got6 = runs.finished(.answered(.init(failed: 1)))
        #expect(!got6)
        guard case .album = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        let got7 = runs.finished(.answered(.init(written: 1)))
        #expect(got7)
        let got8 = runs.next(allowed: true, online: true)
        #expect(got8 == .ended(.covers))
        #expect(runs.under == nil)
        #expect(runs.result(.covers) == "Got 2 covers. 1 has none in the Cover Art Archive. 2 failed - run it again to try "
                + "them again.")
        // nothing told past the end
        let got9 = runs.finished(.answered(.init(written: 1)))
        #expect(!got9)
        let got10 = runs.next(allowed: true, online: true)
        #expect(got10 == .nothing)
    }

    @Test func oneRunAtATimeOnlyFromAReadToTrustAndNeverOfNone() {
        var runs = CareRuns()
        let got11 = runs.start(.covers, Self.five, allowed: true, online: true)
        #expect(!got11, "no read to trust yet")
        #expect(runs.targets(.covers, Self.five) == nil)
        runs.readLanded(runs.readBegan())
        let got12 = runs.start(.covers, Self.five, allowed: false, online: true)
        #expect(!got12, "not this person's part")
        let got13 = runs.start(.covers, Self.five, allowed: true, online: false)
        #expect(!got13, "out of reach")
        let covered = Self.five.map { Self.album($0.path, art: "file") }
        let got14 = runs.start(.covers, covered, allowed: true, online: true)
        #expect(!got14, "none to take")
        let got15 = runs.start(.lyrics, Self.five, allowed: true, online: true)
        #expect(got15)
        #expect(!runs.startOpen(.covers, Self.five, allowed: true, online: true), "one run at a time")
        let got16 = runs.start(.covers, Self.five, allowed: true, online: true)
        #expect(!got16)
        let got17 = runs.start(.lyrics, Self.five, allowed: true, online: true)
        #expect(!got17, "asked again while running: nothing")
        #expect(runs.under?.kind == .lyrics && runs.under?.run.total == 5)
    }

    @Test func narrowingDecidesWhatStartTakes() {
        var runs = Self.ready()
        let albums = [Self.album("Sigur Rós/( ) (2002)", artist: "Sigur Rós", name: "( )"), Self.album("Björk/Post (1995)")]
        runs.narrow = " sigur  ros "
        #expect(runs.targets(.covers, albums)?.map(\.path) == ["Sigur Rós/( ) (2002)"])
        let got18 = runs.start(.covers, albums, allowed: true, online: true)
        #expect(got18)
        #expect(runs.under?.albums.map(\.path) == ["Sigur Rós/( ) (2002)"])
        runs.narrow = "nothing at all"
        #expect(runs.under?.albums.count == 1, "the run's albums were fixed as Start was pressed")
    }

    @Test func stopLandsAfterTheAlbumOutOnce() {
        var runs = Self.ready()
        _ = runs.start(.disc, Self.five, allowed: true, online: true)
        _ = runs.next(allowed: true, online: true)
        let got19 = runs.stop(.disc)
        #expect(got19)
        let got20 = runs.stop(.disc)
        #expect(!got20, "pressed once")
        let got21 = runs.stop(.covers)
        #expect(!got21, "not that kind's run")
        #expect(runs.stopping(.disc))
        #expect(runs.stopLabel(.disc) == "Stopping after 1 of 5")
        // the album out still counts
        let got22 = runs.finished(.answered(.init(written: 1)))
        #expect(got22)
        let got23 = runs.next(allowed: true, online: true)
        #expect(got23 == .ended(.disc))
        #expect(runs.result(.disc) == "Got CD art for 1 album. Stopped at 1 of 5.")
        #expect(runs.ended[.disc]?.stop == .pressed)
    }

    @Test func theAppGoingToTheBackgroundStopsItAfterTheAlbumOutAndStartCarriesOn() {
        var runs = Self.ready()
        let albums = (1...60).map { Self.album("Björk/Album \($0)") }
        _ = runs.start(.covers, albums, allowed: true, online: true)
        for _ in 0..<13 {
            _ = runs.next(allowed: true, online: true)
            runs.finished(.answered(.init(written: 1)))
        }
        guard case .album = runs.next(allowed: true, online: true) else { Issue.record("the 14th album"); return }
        runs.suspended()
        #expect(runs.stopLabel(.covers) == "Stopping after 14 of 60")
        runs.finished(.answered(.init(written: 1)))
        let got24 = runs.next(allowed: true, online: true)
        #expect(got24 == .ended(.covers))
        #expect(runs.result(.covers) == "Got 14 covers. Stopped at 14 of 60. It stopped as the app went to the background - "
                + "Get covers carries on.")
        // behind until a read begun after it lands: then Start takes only those still without a cover
        #expect(runs.targets(.covers, albums) == nil)
        let ticket = runs.readBegan()
        let now = albums.enumerated().map { $0.offset < 14 ? Self.album($0.element.path, art: "file") : $0.element }
        runs.readLanded(ticket)
        #expect(runs.targets(.covers, now)?.count == 46)
        let got25 = runs.start(.covers, now, allowed: true, online: true)
        #expect(got25)
        #expect(runs.result(.covers) == "", "the next of its kind under way")
        // a background with nothing under way stops nothing
        var idle = Self.ready()
        idle.suspended()
        #expect(idle == Self.ready())
    }

    @Test func outOfReachStopsTheRunAndTheScanIsReadAgainBeforeAnythingStarts() {
        var runs = Self.ready()
        _ = runs.start(.lyrics, Self.five, allowed: true, online: true)
        guard case .album(let album) = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        runs.reach(false)
        #expect(!runs.real, "a scan from before the gap isn't trusted")
        let got26 = runs.finished(BulkTargets.step(.lyrics, album, failure: Self.noAnswer))
        #expect(got26)
        let got27 = runs.next(allowed: true, online: true)
        #expect(got27 == .ended(.lyrics))
        #expect(runs.result(.lyrics) == "Saved lyrics for 0 tracks. 10 failed - try them again from the album's own Get "
                + "lyrics, in Edit album. Stopped at 1 of 5 albums. It stopped as deadwax went out of reach - Get lyrics "
                + "carries on once it's back.")
        #expect(runs.behind[.lyrics] != nil, "an album that never answered may have written")
        // back: nothing starts until a read begun now lands
        runs.reach(true)
        #expect(!runs.startOpen(.lyrics, Self.five, allowed: true, online: true))
        #expect(runs.readsNow(shown: true, online: true, again: false, loaded: true, reading: false))
        runs.readLanded(runs.readBegan())
        #expect(runs.real && runs.behind.isEmpty)
        #expect(runs.startOpen(.lyrics, Self.five, allowed: true, online: true))
        // and next() itself says so, should reach go unheard
        _ = runs.start(.lyrics, Self.five, allowed: true, online: true)
        let got28 = runs.next(allowed: true, online: false)
        #expect(got28 == .ended(.lyrics))
        #expect(runs.ended[.lyrics] == CareRuns.Ended(run: .init(total: 5, running: false), stop: .outOfReach))
    }

    @Test func thePermissionGoingStopsTheRunBeforeTheNextAlbum() {
        var runs = Self.ready()
        _ = runs.start(.covers, Self.five, allowed: true, online: true)
        _ = runs.next(allowed: true, online: true)
        runs.finished(.answered(.init(written: 1)))
        let got29 = runs.next(allowed: false, online: true)
        #expect(got29 == .ended(.covers))
        #expect(runs.result(.covers) == "Got 1 cover. Stopped at 1 of 5. It stopped: running it needs Edit albums, which "
                + "an admin hasn't given you.")
    }

    @Test func theSessionEndingStopsTheRunAfterTheAlbumOut() {
        var runs = Self.ready()
        _ = runs.start(.disc, Self.five, allowed: true, online: true)
        _ = runs.next(allowed: true, online: true)
        runs.sessionEnded()
        #expect(runs.stopping(.disc), "the album out is let finish")
        runs.finished(.answered(.init(written: 1)))
        let gotSE = runs.next(allowed: true, online: true)
        #expect(gotSE == .ended(.disc))
        #expect(runs.result(.disc) == "Got CD art for 1 album. Stopped at 1 of 5. It stopped as your session ended - "
                + "sign in again, and Get CD art carries on.")
        // nothing under way: nothing to stop
        var idle = Self.ready()
        idle.sessionEnded()
        #expect(idle == Self.ready())
    }

    @Test func aCancelledAlbumCountsNothingAndEndsTheRun() {
        var runs = Self.ready()
        _ = runs.start(.covers, Self.five, allowed: true, online: true)
        guard case .album(let album) = runs.next(allowed: true, online: true) else { Issue.record("an album"); return }
        let step = BulkTargets.step(.covers, album, failure: CancellationError())
        #expect(step == .cancelled)
        let got30 = runs.finished(step)
        #expect(!got30)
        let got31 = runs.next(allowed: true, online: true)
        #expect(got31 == .ended(.covers))
        #expect(runs.run(.covers)?.done == 0)
        #expect(runs.result(.covers) == "Got 0 covers. Stopped at 0 of 5.")
        #expect(runs.behind[.covers] == nil, "nothing written, nothing that may have been")
    }

    @Test func aKindIsBehindOnlyUntilAReadBegunAfterItsRunLands() {
        var runs = Self.ready()
        let early = runs.readBegan()
        _ = runs.start(.covers, Self.five, allowed: true, online: true)
        _ = runs.next(allowed: true, online: true)
        runs.finished(.answered(.init(written: 1)))
        runs.stop(.covers)
        _ = runs.next(allowed: true, online: true)
        #expect(runs.behind[.covers] != nil)
        #expect(runs.targets(.covers, Self.five) == nil)
        #expect(LibraryCare.note(.covers, targets: runs.targets(.covers, Self.five), typed: "") == LibraryCare.checking)
        runs.readLanded(early)
        #expect(runs.behind[.covers] != nil, "a read begun before the run ended still lists what it did as missing")
        runs.readLanded(runs.readBegan())
        #expect(runs.behind[.covers] == nil)
        // a run that wrote nothing leaves nothing behind
        _ = runs.start(.disc, Self.five, allowed: true, online: true)
        runs.stop(.disc)
        _ = runs.next(allowed: true, online: true)
        #expect(runs.behind.isEmpty)
    }

    @Test func theScreenStaysOnOnlyWhileARunGoesAndItsPageShows() {
        var runs = Self.ready()
        #expect(!runs.keepsScreenOn(visible: true))
        _ = runs.start(.covers, Self.five, allowed: true, online: true)
        #expect(runs.keepsScreenOn(visible: true))
        #expect(!runs.keepsScreenOn(visible: false))
        runs.stop(.covers)
        _ = runs.next(allowed: true, online: true)
        #expect(!runs.keepsScreenOn(visible: true))
    }

    // MARK: Rescan and the reads

    @Test func rescanIsOneAtATimeAndSaysWhatFollows() {
        var runs = Self.ready()
        let got32 = runs.rescan(allowed: false, online: true, problem: false, reading: false)
        #expect(got32 == nil)
        let got33 = runs.rescan(allowed: true, online: false, problem: false, reading: false)
        #expect(got33 == nil)
        let got34 = runs.rescan(allowed: true, online: true, problem: true, reading: false)
        #expect(got34 == nil)
        let got35 = runs.rescan(allowed: true, online: true, problem: false, reading: true)
        #expect(got35 == nil, "a read is out")
        let ticket = runs.rescan(allowed: true, online: true, problem: false, reading: false)
        #expect(ticket != nil && runs.rescanning)
        let got36 = runs.rescan(allowed: true, online: true, problem: false, reading: false)
        #expect(got36 == nil, "ours is out")
        #expect(!runs.readsNow(shown: true, online: true, again: true, loaded: true, reading: false), "no read over it")
        let got37 = runs.rescanEnded(ticket!, .landed(albums: 3))
        #expect(got37 == CareRuns.AfterRescan(readAgain: false, tell: true,
                                                                                         mayHaveFinished: false))
        #expect(!runs.rescanning && runs.landed == ticket)
        // an empty library tells nothing (the web announces only albums found)
        let empty = runs.rescan(allowed: true, online: true, problem: false, reading: false)!
        let got38 = runs.rescanEnded(empty, .landed(albums: 0))
        #expect(got38 == .nothing)
        let lost = runs.rescan(allowed: true, online: true, problem: false, reading: false)!
        let got39 = runs.rescanEnded(lost, .unanswered)
        #expect(got39 == CareRuns.AfterRescan(readAgain: true, tell: true, mayHaveFinished: true))
        #expect(runs.landed == empty, "never answered: nothing landed")
        let refused = runs.rescan(allowed: true, online: true, problem: false, reading: false)!
        let got40 = runs.rescanEnded(refused, .refused)
        #expect(got40 == .nothing)
        let dropped = runs.rescan(allowed: true, online: true, problem: false, reading: false)!
        let got41 = runs.rescanEnded(dropped, .dropped)
        #expect(got41 == .nothing)
        #expect(!runs.rescanning)
        #expect(LibraryCare.busy(rescanning: true, reading: false) && LibraryCare.busy(rescanning: false, reading: true))
    }

    @Test func thePageReadsWhenItMust() {
        var runs = CareRuns()
        #expect(runs.readsNow(shown: true, online: true, again: false, loaded: false, reading: false), "the first read")
        #expect(!runs.readsNow(shown: false, online: true, again: false, loaded: false, reading: false), "not shown")
        #expect(!runs.readsNow(shown: true, online: false, again: false, loaded: false, reading: false), "out of reach")
        #expect(!runs.readsNow(shown: true, online: true, again: false, loaded: false, reading: true), "one is out")
        runs.readLanded(runs.readBegan())
        #expect(!runs.readsNow(shown: true, online: true, again: false, loaded: true, reading: false), "nothing to do")
        #expect(runs.readsNow(shown: true, online: true, again: true, loaded: true, reading: false), "shown again")
        runs.reach(false)
        #expect(runs.readsNow(shown: true, online: true, again: false, loaded: true, reading: false), "back in reach")
    }

    // MARK: the phone's words

    @Test func thePhonesOwnWordsNameTheButtonThatCarriesOn() {
        for kind in BulkTargets.kinds {
            #expect(LibraryCare.stopped(.background, kind: kind)?.contains(LibraryCare.label(kind)) == true)
            #expect(LibraryCare.stopped(.outOfReach, kind: kind)?.contains(LibraryCare.label(kind)) == true)
            #expect(LibraryCare.stopped(.sessionEnded, kind: kind)?.contains(LibraryCare.label(kind)) == true)
            #expect(LibraryCare.stopped(.pressed, kind: kind) == nil, "the web's Stopped at says it")
            #expect(LibraryCare.stopped(.cancelled, kind: kind) == nil)
        }
        #expect(LibraryCare.startLabel(.lyrics, count: 14) == "Get lyrics · 14")
        #expect(LibraryCare.waiting(for: .covers) == "One run at a time - this one can start once Covers has finished.")
        #expect(ManagingWords.label(.care) == LibraryCare.title)
    }

    // MARK: In nobody's library

    @Test func inNobodysLibraryWritesOneAtATimeFromAReadToTrust() {
        var flow = Held.Flow()
        let got42 = flow.begin(7, online: true)
        #expect(!got42, "nothing read yet")
        let first = flow.readBegan()
        flow.readLanded(first)
        let got43 = flow.begin(7, online: false)
        #expect(!got43, "out of reach")
        let got44 = flow.begin(7, online: true)
        #expect(got44)
        #expect(flow.acting == 7)
        let got45 = flow.begin(8, online: true)
        #expect(!got45, "one at a time: a second tap asks nothing")
        #expect(!flow.open(online: true))
        flow.ended()
        #expect(flow.open(online: true))
        flow.outOfReach()
        #expect(!flow.open(online: true), "back in reach, the list is read again first")
        flow.readLanded(first)
        #expect(!flow.real, "a read from before the gap")
        flow.readLanded(flow.readBegan())
        #expect(flow.open(online: true))
        #expect(Held.Write.add.failed == Held.addFailed && Held.Write.dismiss.failed == Held.dismissFailed)
    }

    @Test func showAllListsEveryAlbumAndOnlyPastTwenty() {
        let albums = (1...21).map { Held.UnheldAlbum(id: $0, path: "A/\($0)") }
        #expect(Held.listedAlbums(albums, all: false).count == 20)
        #expect(Held.listedAlbums(albums, all: true).count == 21)
        #expect(Held.showLabel(all: false, count: 21) == "Show all 21")
        #expect(Held.showLabel(all: true, count: 21) == "Show fewer")
        #expect(Held.showLabel(all: false, count: 20) == nil)
        #expect(Held.line(1) == "1 album nobody has in their library")
    }
}
