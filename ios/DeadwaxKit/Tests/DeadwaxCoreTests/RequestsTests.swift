import Foundation
import Testing
@testable import DeadwaxCore

/// The Requests tab's rules the web's TypeScript doesn't hold (RequestsVectorTests holds the rest): the phone's own
/// poll (RequestsPolling - none offline, none in the background), what /download/jobs and its four writes send and
/// answer, a Done row's notes, Confirm before cancelling, and the board's small edges.
@Suite struct RequestsTests {
    // MARK: the poll

    @Test func thePollIsFastOnRequestsSlowForSomethingOnItsWayAndNoneOtherwise() {
        let open: Double? = RequestsPolling.delay(open: true, hasActive: false, filing: false, online: true, watching: .requests)
        let openActive: Double? = RequestsPolling.delay(open: true, hasActive: true, filing: true, online: true, watching: .requests)
        let filing: Double? = RequestsPolling.delay(open: false, hasActive: true, filing: true, online: true, watching: .other)
        let away: Double? = RequestsPolling.delay(open: false, hasActive: true, filing: false, online: true, watching: .other)
        let idle: Double? = RequestsPolling.delay(open: false, hasActive: false, filing: false, online: true, watching: .other)
        // (Speed A, fix 6) the root with nothing moving once a second, the web's pace while something is
        #expect(open == 1)
        #expect(openActive == 0.5)
        #expect(filing == 1)
        #expect(away == 5)
        #expect(idle == nil)
    }

    @Test func nothingIsAskedOfflineNorInTheBackground() {
        for open in [false, true] {
            for active in [false, true] {
                let offline: Double? = RequestsPolling.delay(open: open, hasActive: active, filing: active, online: false,
                                                             watching: .requests)
                let hidden: Double? = RequestsPolling.delay(open: open, hasActive: active, filing: active, online: true,
                                                            watching: .hidden)
                #expect(offline == nil)
                #expect(hidden == nil)
            }
        }
        #expect(!RequestsPolling.asks(online: false, watching: .requests))
        #expect(!RequestsPolling.asks(online: true, watching: .hidden))
        #expect(RequestsPolling.asks(online: true, watching: .other))
    }

    @Test func comingBackFromTheBackgroundAsksOnceOnAnyTabButRequests() {
        #expect(RequestsWatch.asksAgain(.hidden, .other))
        #expect(!RequestsWatch.asksAgain(.hidden, .requests))
        #expect(!RequestsWatch.asksAgain(.other, .other))
        #expect(!RequestsWatch.asksAgain(.requests, .other))
        #expect(RequestsWatch.watching(shown: true, tab: "requests", depth: 0, sheetOpen: false) == .requests)
        #expect(RequestsWatch.watching(shown: true, tab: "requests", depth: 1, sheetOpen: false) == .other)
        #expect(RequestsWatch.watching(shown: true, tab: "requests", depth: 0, sheetOpen: true) == .other)
        #expect(RequestsWatch.watching(shown: false, tab: "requests", depth: 0, sheetOpen: false) == .hidden)
    }

    // MARK: what deadwax sends

    @Test func aJobIsReadAsDeadwaxSendsItWithLoginsOff() throws {
        let json = #"""
        {"jobs":[{"attempt":2,"id":7,"artist":"Portishead","album":"Dummy","year":"1994","username":"mellotron",
        "directory":"music\\Portishead","status":"queued","error":null,"created_at":"2026-11-06T20:44:00+00:00",
        "updated_at":"2026-11-06T20:45:00+00:00","release_mbid":"76df3287-6cda-33eb-8e9a-044b5e15ffdd",
        "release_group_mbid":null,"edition":null,"outcome":null,"queue_position":4,"progress":12.5,
        "state":"Queued, Remotely","speed":0,"bytes_transferred":1048576,"files_done":1,"files_total":11,
        "files_failed":0,"failure_reason":null,"matched":true}],"tracking_enabled":true}
        """#
        let answer: JobsAnswer = try JSONDecoder().decode(JobsAnswer.self, from: Data(json.utf8))
        #expect(answer.trackingEnabled)
        let job = try #require(answer.jobs.first)
        #expect(job.id == 7 && job.status == "queued" && job.isActive)
        #expect(job.attempt == 2 && job.queuePosition == 4 && job.progress == 12.5 && job.bytesTransferred == 1_048_576)
        #expect(job.filesDone == 1 && job.filesTotal == 11 && job.filesFailed == 0 && job.matched == true)
        #expect(job.mine == nil && job.shared == nil && job.requestedBy == nil && job.library == nil)
        #expect(job.alternativesLeft == nil)
        let row: RequestRow = try #require(RequestsView.make(RequestsInput(jobs: answer.jobs), now: 0).rows(.downloading).first)
        #expect(row.line == "Portishead \u{00B7} from mellotron \u{00B7} 2nd try")
        #expect(row.data == "1 of 11 files")
        #expect(row.cover == "76df3287-6cda-33eb-8e9a-044b5e15ffdd")
    }

    @Test func aJobIsReadAsDeadwaxSendsItWithLoginsOn() throws {
        let json = #"""
        {"jobs":[{"attempt":1,"id":9,"artist":"Massive Attack","album":"Mezzanine","year":null,"username":"vinylhead",
        "directory":"x","status":"failed","error":"the peer refused to send it","created_at":"2026-11-06T20:44:00+00:00",
        "updated_at":null,"release_mbid":null,"release_group_mbid":null,"edition":"2014 vinyl","outcome":"failed",
        "queue_position":null,"progress":0.0,"state":null,"speed":0,"bytes_transferred":0,"files_done":0,
        "files_total":10,"matched":false,"alternatives_left":2,"mine":true,"shared":true,"requested_by":["ethan"],
        "library":null}],"tracking_enabled":false}
        """#
        let answer: JobsAnswer = try JSONDecoder().decode(JobsAnswer.self, from: Data(json.utf8))
        #expect(!answer.trackingEnabled)
        let job = try #require(answer.jobs.first)
        #expect(!job.isActive && job.alternativesLeft == 2 && job.requestedBy == ["ethan"] && job.mine == true)
        let row: RequestRow = try #require(RequestsView.make(RequestsInput(jobs: answer.jobs), now: 0).rows(.attention).first)
        #expect(row.askedBy == "Asked by you and ethan")
        #expect(row.cancelWords.action == "Cancel for everyone")
        #expect(row.nextPeer?.label == "Another source \u{00B7} 2 left")
        #expect(row.askAgain?.label == "Same source again")
    }

    @Test func anOddFieldIsNoneAndTheRowIsStillRead() throws {
        let json = #"""
        {"jobs":[{"id":3,"status":"queued","queue_position":"4th","progress":"x","requested_by":["ethan",7],"mine":1},
        {"id":4,"status":"failed"}],"tracking_enabled":true}
        """#
        let answer: JobsAnswer = try JSONDecoder().decode(JobsAnswer.self, from: Data(json.utf8))
        #expect(answer.jobs.map { $0.id } == [3, 4])
        let odd = answer.jobs[0]
        #expect(odd.queuePosition == nil && odd.progress == nil && odd.mine == nil)
        #expect(odd.requestedBy == ["ethan"])
        //? the id and the status are what a row is: without either, the answer isn't deadwax's
        let broken = Data(#"{"jobs":[{"status":"queued"}],"tracking_enabled":true}"#.utf8)
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(JobsAnswer.self, from: broken) }
    }

    @Test func theFourWritesAreTheRoutesTheyName() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/jobs", 200, #"{"jobs":[],"tracking_enabled":true}"#)
        transport.answer("/deadwax/download/jobs/12/cancel", 200,
                         #"{"status":"ok","left":true,"cancelled":0,"partials_removed":0,"partials_problem":null}"#)
        transport.answer("/deadwax/download/jobs/12/retry", 200,
                         #"{"moved":false,"username":null,"directory":null,"left":0,"problem":"no other peers to try - search again for more"}"#)
        transport.answer("/deadwax/download/jobs/12/retry_same", 200,
                         #"{"retried":true,"username":"mellotron","files":3,"problem":null}"#)
        transport.answer("/deadwax/download/jobs/clear", 200, #"{"status":"ok","removed":4}"#)

        let jobs: JobsAnswer = try await deadwax.jobs()
        #expect(jobs.jobs.isEmpty && jobs.trackingEnabled)
        #expect(transport.last?.method == "GET")
        #expect(transport.last?.timeout == 20)

        let cancelled: CancelAnswer = try await deadwax.cancelJob(12)
        #expect(cancelled.left == true && cancelled.cancelled == 0)
        #expect(transport.last?.method == "POST" && transport.last?.url.path == "/deadwax/download/jobs/12/cancel")
        #expect(transport.last?.body == nil)
        #expect(transport.last?.headers["Cookie"] != nil)

        let moved: RetryAnswer = try await deadwax.retryJob(12)
        #expect(!moved.moved && moved.problem == "no other peers to try - search again for more" && moved.left == 0)
        #expect(transport.last?.method == "POST" && transport.last?.timeout == 60)

        let again: RetrySameAnswer = try await deadwax.retryJobSame(12)
        #expect(again.retried && again.problem == nil)
        #expect(transport.last?.url.path == "/deadwax/download/jobs/12/retry_same")

        let cleared: ClearAnswer = try await deadwax.clearJobs()
        #expect(cleared.removed == 4)
        #expect(transport.last?.method == "POST" && transport.last?.url.path == "/deadwax/download/jobs/clear")
    }

    @Test func aDoneRowsAlbumIsAskedOfTheIdBridgeByItsPressing() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/store/album", 200,
                         #"{"release_mbid":"7f2a","release_group_mbid":"g1","navidrome_id":null,"present":[{"id":3,"path":"Portishead/Dummy (1994)","exists":true}],"other_pressings":[]}"#)
        let answer: StoreAlbum = try await deadwax.storeAlbum(releaseMbid: "7f2a")
        #expect(transport.last?.method == "GET")
        #expect(transport.last?.url.query == "release_mbid=7f2a")
        //? a folder held, Navidrome not having it yet: "Not ready to play yet"
        #expect(answer.navidromeId == nil && answer.present.count == 1)
        let note: String = RequestWords.note(present: !answer.present.isEmpty, navidromeProblem: nil)
        #expect(note == RequestWords.notInNavidrome)
        let id: String? = try await deadwax.navidromeAlbum(releaseMbid: "7f2a")
        #expect(id == nil)
    }

    @Test func aRefusedWriteIsThrownInDeadwaxsWords() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/jobs/3/retry", 409, #"{"detail":"this download is queued, not failed or cancelled"}"#)
        do {
            _ = try await deadwax.retryJob(3)
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(ErrorWords.kind(of: error) == .refused)
        }
        transport.answer("/deadwax/download/jobs/3/cancel", 404, #"{"detail":"No such download job"}"#)
        do {
            _ = try await deadwax.cancelJob(3)
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(ErrorWords.kind(of: error) == .notFound)
        }
    }

    // MARK: words the board says by itself

    @Test func aDoneRowsNoteNamesTheMusicServerFirst() {
        let unset = NavidromeGate.Checked(status: NavidromeStatus(configured: false, ok: false))
        let down = NavidromeGate.Checked(status: NavidromeStatus(configured: true, ok: false))
        let up = NavidromeGate.Checked(status: NavidromeStatus(configured: true, ok: true))
        let offline = NavidromeGate.Checked(status: NavidromeStatus(configured: true, ok: false), offline: true)
        #expect(RequestWords.cantOpen(nil) == nil)
        #expect(RequestWords.cantOpen(unset) == RequestWords.cantOpenUnset)
        #expect(RequestWords.cantOpen(down) == RequestWords.cantOpenDown)
        #expect(RequestWords.cantOpen(offline) == RequestWords.cantOpenOffline)
        #expect(RequestWords.cantOpen(up) == nil)
        #expect(RequestWords.note(present: true, navidromeProblem: nil) == RequestWords.notInNavidrome)
        #expect(RequestWords.note(present: false, navidromeProblem: nil) == RequestWords.notInStore)
        #expect(RequestWords.note(present: true, navidromeProblem: RequestWords.cantOpenDown) == RequestWords.cantOpenDown)
    }

    @Test func theEmptyBoardAndAFailedLookSayWhatTheyShould() {
        #expect(RequestWords.emptyLine(gets: true, device: .iPhone) == RequestWords.empty(.iPhone))
        #expect(RequestWords.emptyLine(gets: false, device: .iPhone) == RequestWords.getOff)
        #expect(RequestWords.keepsAsking(empty: true) == RequestWords.keepsAsking)
        #expect(RequestWords.keepsAsking(empty: false) == RequestWords.keepsAskingBelow)
        let empty: RequestsView = RequestsView.make(RequestsInput(), now: 0)
        #expect(empty.empty && !empty.clearable && empty.arriving.isEmpty)
        #expect(RequestSection.allCases.allSatisfy { empty.rows($0).isEmpty })
    }

    @Test func confirmBeforeCancellingIsOnUnlessTurnedOff() {
        #expect(ConfirmCancel.read(nil))
        #expect(ConfirmCancel.read("on"))
        #expect(ConfirmCancel.read("anything"))
        #expect(!ConfirmCancel.read("off"))
        #expect(ConfirmCancel.stored(true) == "on")
        #expect(ConfirmCancel.stored(false) == "off")
        #expect(ConfirmCancel.read(ConfirmCancel.stored(false)) == false)
    }

    // MARK: the board's edges

    @Test func aRequestBecomesItsJobOnceAPollListsIt() {
        let pending = PendingDownload(key: "pending-1", artist: "Portishead", album: "Dummy", username: "mellotron")
        var overlays = RequestOverlays.none.withPending(pending)
        #expect(overlays.activeCount([]) == 1)
        overlays = overlays.settlePending("pending-1", .job(31))
        //? not listed yet: still drawn as the request
        #expect(overlays.visiblePending([]).map { $0.key } == ["pending-1"])
        let job = DownloadJob(id: 31, status: "queued", artist: "Portishead", album: "Dummy")
        #expect(overlays.visiblePending([job]).isEmpty)
        #expect(overlays.reconcile([job]).pending.isEmpty)
    }

    @Test func aRefusedRequestKeepsItsDetailAndGoesWithClearDone() {
        let pending = PendingDownload(key: "pending-1", artist: "A", album: "B", username: "u", detail: "POST failed")
        let refused = RequestOverlays.none.withPending(pending).settlePending("pending-1", .refused(error: "nope", detail: nil))
        #expect(refused.pending.first?.error == "nope" && refused.pending.first?.detail == "POST failed")
        #expect(refused.activeCount([]) == 0)
        #expect(refused.withoutRefused().pending.isEmpty)
        let view: RequestsView = RequestsView.make(RequestsInput(pending: refused.pending), now: 0)
        #expect(view.clearable)
        #expect(view.rows(.attention).first?.line == "A \u{00B7} from u \u{00B7} didn't start")
    }

    @Test func aCancelThatOnlyLeavesIsSaidAsLeavingAndThenLeft() {
        let shared = DownloadJob(id: 4, status: "queued", artist: "Björk", album: "Homogenic", username: "vinylhead",
                                 mine: true, shared: true)
        let before: RequestsView = RequestsView.make(RequestsInput(jobs: [shared], cancelling: [4]), now: 0)
        let row = before.rows(.waiting).first
        #expect(row?.cancel == .cancelling && row?.brief == "leaving\u{2026}")
        #expect(RequestWords.cancelLabel(before.rows(.waiting)[0]) == "Leave Homogenic")
        let after: RequestsView = RequestsView.make(RequestsInput(), now: 0)
        let heard: RequestChanges.Said = RequestChanges.changes(before: before, now: after)
        #expect(heard.said == "Homogenic: left - it carries on for whoever else asked")
        #expect(heard.gone.count == 1 && heard.gone[0].key == "job-4" && heard.gone[0].focus == nil)
    }

    @Test func aSpeedIsMeasuredOverASecondAndKeptThroughQuietPolls() {
        var samples = SpeedSamples()
        let job = { (bytes: Double, status: String) -> DownloadJob in
            DownloadJob(id: 1, status: status, bytesTransferred: bytes)
        }
        #expect(samples.sample([job(0, "downloading")], now: 0).isEmpty)
        //? under a second: nothing to say yet
        #expect(samples.sample([job(500_000, "downloading")], now: 500).isEmpty)
        let measured: [Int: Double] = samples.sample([job(1_048_576, "downloading")], now: 1000)
        #expect(measured == [1: 1_048_576])
        //? quiet: the last rate kept for 6 s
        let quiet: [Int: Double] = samples.sample([job(1_048_576, "downloading")], now: 6000)
        #expect(quiet == [1: 1_048_576])
        let stale: [Int: Double] = samples.sample([job(1_048_576, "downloading")], now: 7001)
        #expect(stale.isEmpty)
        //? finished: forgotten
        _ = samples.sample([job(2_000_000, "organized")], now: 8000)
        #expect(samples.isEmpty)
    }

    // MARK: slice 1's review

    @Test func aDoneRowsLookLetGoIsLookedForAgain() {
        var flight = DoneLooks.InFlight()
        let rows: [DoneLooks.Row] = [DoneLooks.Row(release: "r1", since: 0)]
        _ = flight.begin("r1")
        //? out: not asked again until it answers
        let whileOut: DoneLooks.Looks = DoneLooks.looks(rows, held: DoneLooks.Held(inFlight: flight.releases), now: 20_000)
        #expect(whileOut.look.isEmpty)
        //? deadwax went out of reach: every look let go, so back in reach the release is looked for again
        flight.clear()
        let back: DoneLooks.Looks = DoneLooks.looks(rows, held: DoneLooks.Held(inFlight: flight.releases), now: 20_000)
        #expect(back.look == ["r1"])
    }

    @Test func anOldAskEndingLateLeavesTheNewOneInFlight() {
        var flight = DoneLooks.InFlight()
        let first: Int = flight.begin("r1")
        flight.clear()
        let second: Int = flight.begin("r1")
        //? the first, let go, ends after the second began: the second is still out
        flight.end("r1", ticket: first)
        #expect(flight.contains("r1"))
        flight.end("r1", ticket: second)
        #expect(!flight.contains("r1"))
        #expect(flight.releases.isEmpty)
    }

    @Test func anAskEndsHoweverItEnds() {
        var flight = DoneLooks.InFlight()
        //? answered, failed or cancelled, the one end takes it out of flight
        let ticket: Int = flight.begin("r2")
        let other: Int = flight.begin("r3")
        flight.end("r2", ticket: ticket)
        #expect(!flight.contains("r2"))
        #expect(flight.releases == ["r3"])
        flight.end("r3", ticket: other)
        #expect(flight.releases.isEmpty)
    }

    @Test func aSecondClearDoneThatFailsGivesBackOnlyWhatItTook() {
        let done = DownloadJob(id: 1, status: "organized")
        let failed = DownloadJob(id: 2, status: "failed")
        let going = DownloadJob(id: 3, status: "downloading")
        var overlays = RequestOverlays.none
        let first: [Int] = overlays.toClear([done, failed, going])
        #expect(first == [1, 2])
        overlays.cleared.formUnion(first)
        //? a second Clear done before a poll agrees with the first: nothing left to take
        #expect(overlays.toClear([done, failed, going]).isEmpty)
        //? one finished since: only it is taken, and a failure gives back only it
        let late = DownloadJob(id: 4, status: "organized")
        let second: [Int] = overlays.toClear([done, failed, going, late])
        #expect(second == [4])
        overlays.cleared.formUnion(second)
        overlays.cleared.subtract(second)
        let shown: [Int] = overlays.visibleJobs([done, failed, going, late]).map { $0.id }
        #expect(shown == [3, 4])
        //? (every finished job polled, the web's rule, would have taken the first clear's rows and given them back)
        #expect(RequestOverlays.finishedIds([done, failed, going, late]) == [1, 2, 4])
    }

    @Test func theDoneRowsTimesAreKeptOnlyForJobsStillListed() {
        let since: [String: Double] = ["job-1": 0, "job-2": 5_000, "job-3": 9_000]
        //? job 1 cleared and gone, job 3 hidden by a clear still waiting for its poll: listed, so kept
        let kept: [String: Double] = DoneLooks.kept(since, listed: [DownloadJob(id: 2, status: "organized"),
                                                                    DownloadJob(id: 3, status: "failed")])
        #expect(kept == ["job-2": 5_000, "job-3": 9_000])
        #expect(DoneLooks.kept(since, listed: []).isEmpty)
        #expect(RequestRow.key(job: 7) == "job-7")
    }
}
