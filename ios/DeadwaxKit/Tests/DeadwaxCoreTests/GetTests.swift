import Foundation
import Testing
@testable import DeadwaxCore

/// Phase 6, slices 2 and 3 by hand: what the vectors can't hold - the store line as the phone draws it (Join only with
/// Get albums), the bodies as JSON goes over the wire, a real answer of each route decoded, the client's requests, the
/// album page taking the store line's word, a Get whose answer never came, and slice 3's auto-pick decision and You's
/// choices laid over deadwax's word (useCandidateSearch.ts and useGetSettings.ts, which the exporter can't compile).
@Suite struct GetTests {
    static let credit = [MBArtistCredit(name: "Portishead", artist: .init(id: "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11", name: "Portishead"))]
    static let group = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01", title: "Third", firstReleaseDate: "2008-04-28",
                                    primaryType: "Album", artistCredit: credit)
    static let pressing = PageRelease(
        id: "r-cd", title: "Third", date: "2008-04-28", country: "GB", disambiguation: nil,
        media: [MBMedium(position: 1, format: "CD", tracks: [
            MBTrack(number: "1", position: 1, title: "Silence", length: 299_000, recording: .init(title: "Silence", length: 298_960)),
            MBTrack(number: "2", position: 2, title: "Hunter", length: 217_000),
        ])],
        eventDates: ["2008-04-28"], labelInfo: [.init(label: "Island", catalogNumber: "1764331")], artistCredit: credit,
        eventCountries: ["GB"])

    // MARK: the store line, as the phone draws it (slice 3)

    @Test func theCollectionsPressingIsSaidWithAddUnderIt() {
        let held = HeldPressing(path: "Portishead/Third (2008)", paths: ["Portishead/Third (2008)"], trackCount: 11,
                                expectedTracks: 11, formats: ["flac"], complete: true, yours: false)
        let answer = StoreStateAnswer(held: held)
        let web = StoreLine.statusFor(answer, cancelIn: .requests, floor: nil)
        #expect(web?.title == StoreLine.inTheStore && web?.add == true && web?.lines.last == StoreLine.addNote)
        // Add is drawn for anyone, as every page of the web's gives it - with Get albums or without
        #expect(StoreLine.drawn(answer, floor: nil, joins: true) == web)
        #expect(StoreLine.drawn(answer, floor: nil, joins: false) == web)
        // added from the box: yours now, the add line gone, the button's place kept (it says it was added)
        let added = StoreLine.addedStatus(web!)
        #expect(added.title == StoreLine.heldTitle && added.add)
        #expect(added.lines == ["Portishead/Third (2008)", "11 of 11 tracks \u{00B7} FLAC"])
        // a status with no Add is as it was
        let yours = StoreStateAnswer(held: HeldPressing(path: "P/T", trackCount: 2, expectedTracks: 0, complete: true))
        let mine = StoreLine.statusFor(yours, cancelIn: .requests)!
        #expect(StoreLine.drawn(yours, floor: nil, joins: true) == mine && StoreLine.addedStatus(mine) == mine)
    }

    @Test func somebodyElsesDownloadHasJoinOnlyForSomeoneWhoGetsAlbums() {
        let download = DownloadInFlight(jobId: 41, status: "downloading", username: "mellotron", files: 11, doneFiles: 4,
                                        yours: false, formats: ["mp3"], bitrates: [320])
        let answer = StoreStateAnswer(downloading: download)
        let web = StoreLine.statusFor(answer, cancelIn: .requests, floor: .lossless)
        #expect(web?.joinJobId == 41 && web?.lines.last == StoreLine.joinNote(.requests))
        #expect(StoreLine.drawn(answer, floor: .lossless, joins: true) == web)
        let without = StoreLine.drawn(answer, floor: .lossless, joins: false)
        #expect(without?.title == "Already downloading for someone else")
        #expect(without?.lines == ["From mellotron \u{00B7} MP3 320k \u{00B7} 4 of 11 files",
                                   "It's below your quality floor (Lossless), and getting a copy of your own isn't offered yet."])
        #expect(without?.joinJobId == nil)
    }

    // MARK: the bodies

    @Test func aGetSearchesWithTheReleaseFlatAndItsFormat() throws {
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        let body = FindCandidatesBody(release: release, format: .losslessOnly, queryOverride: "")
        let data = try JSONEncoder().encode(body)
        let sent = try JSONDecoder().decode([String: SentValue].self, from: data)
        #expect(Set(sent.keys) == ["artist", "album_artist", "artist_mbids", "album", "year", "original_year", "release_mbid",
                                   "edition_tags", "tracks", "release_group_mbid", "disambiguation", "media_format",
                                   "country", "catalog_number", "format_preference", "query_override"])
        #expect(sent["format_preference"] == .string("lossless_only") && sent["query_override"] == .string(""))
        #expect(sent["disambiguation"] == .null, "a pressing's four are sent, null when it has none")
        #expect(sent["catalog_number"] == .string("1764331") && sent["country"] == .string("GB"))
        //? the server's length_ms is an int: a whole number goes without a fraction
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""length_ms":298960"#) && text.contains(#""length_ms":217000"#))
        #expect(release.label == "Portishead - Third")
        // the album as a whole: none of a pressing's four, no tracks, no release id
        let whole = try JSONDecoder().decode([String: SentValue].self,
                                             from: JSONEncoder().encode(GetRelease.build(group: Self.group, release: nil)))
        #expect(whole["disambiguation"] == nil && whole["media_format"] == nil && whole["country"] == nil)
        #expect(whole["release_mbid"] == .null && whole["tracks"] == .list([]) && whole["year"] == .string("2008"))
    }

    static func candidate(_ user: String, _ folder: String, score: Double = 0.9) -> Candidate {
        Candidate(username: user, directory: "Music\\\(folder)", directoryName: folder, score: score, formats: ["flac"],
                  bitDepths: [16], sampleRates: [44100], files: [CandidateFile(filename: "Music\\\(folder)\\01.flac", size: 31_415_926)])
    }

    @Test func aCardsGetSendsTheFolderAndTheNextTenAsShown() throws {
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        let shown = (0..<14).map { Self.candidate("peer\($0)", "Third \($0)") }
        let picked = shown[3]
        let body = EnqueueBody(candidate: picked, release: release, shown: shown)
        #expect(body.username == "peer3" && body.directory == "Music\\Third 3" && body.files == picked.files)
        #expect(body.alternatives.map(\.username) == ["peer0", "peer1", "peer2", "peer4", "peer5", "peer6", "peer7", "peer8",
                                                      "peer9", "peer10"])
        // the same peer's other folder is another source: a folder is a peer's AND its directory
        let same = EnqueueBody(candidate: picked, release: release, shown: [picked, Self.candidate("peer3", "Third MP3")])
        #expect(same.alternatives.map(\.directory) == ["Music\\Third MP3"])
        let sent = try JSONDecoder().decode([String: SentValue].self, from: JSONEncoder().encode(body))
        #expect(Set(sent.keys) == ["username", "files", "directory", "release", "alternatives", "quality"])
        #expect(sent["quality"] == .object(["formats": .list([.string("flac")]), "bitrates": .list([]),
                                            "bit_depths": .list([.number(16)]), "sample_rates": .list([.number(44100)]),
                                            "variable_bitrate": .bool(false)]))
        let text = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        #expect(text.contains(#""size":31415926"#), "EnqueueFile's size is an int")
        if case .list(let alternatives)? = sent["alternatives"], case .object(let first)? = alternatives.first {
            #expect(Set(first.keys) == ["username", "directory", "files", "score", "quality"])
        } else {
            Issue.record("no alternatives")
        }
    }

    // MARK: the answers

    @Test func aRealSearchAnswerIsRead() throws {
        //? as routes/download.py's find_candidates sends it: _serialize_candidate's every key, signals null where not
        //? judged, measured_* only for a peer measured before, and the store's four
        let json = #"""
        {"downloading":null,"downloading_part":null,"held":null,"other_pressings":[{"path":"Portishead/Third (2008) [Deluxe]","release_mbid":"r-dlx","edition":"Deluxe","year":"2008","track_count":13,"formats":["flac"]}],
         "query":"Portishead Third","queries":["Portishead Third"],"response_count":41,
         "candidates":[{"username":"mellotron","directory":"@@x\\Music\\Third","directory_name":"Third","score":0.9213,
          "signals":{"title_match":1.0,"track_count":1.0,"duration_match":null,"edition":0.8,"format":1.0,"peer":0.75},
          "matched_tracks":11,"expected_tracks":11,"audio_file_count":11,"detected_edition_tags":[],"disc_folders":[],
          "formats":["flac"],"upload_speed":2202009,"queue_length":0,"has_free_slot":true,"total_size":313524224,
          "bitrates":[],"bit_depths":[16],"sample_rates":[44100],"variable_bitrate":false,
          "missing_tracks":[],"missing_count":0,"audio_expected":11,
          "files":[{"filename":"@@x\\Music\\Third\\01 Silence.flac","size":28511232}],
          "measured_speed":1887436.8,"measured_samples":3,"measured_at":"2026-11-14T20:00:00+00:00"}]}
        """#
        let answer = try JSONDecoder().decode(FindCandidatesAnswer.self, from: Data(json.utf8))
        #expect(answer.responseCount == 41 && answer.candidates.count == 1 && answer.store.otherPressings.count == 1)
        let found = try #require(answer.candidates.first)
        #expect(found.signals["duration_match"] == nil && found.signals["peer"] == 0.75)
        #expect(Sources.percent(found) == 92 && Sources.qualityText(found) == "FLAC 16/44.1")
        #expect(Sources.speedFact(found).text == "~1.8 MB/s" && Sources.speedFact(found).kind == .measured)
        #expect(Sources.tracksText(found) == "11 of 11" && Sources.size(found.totalSize) == "299 MB")
        #expect(StoreLine.notes(answer.store) == ["You also have another pressing: Deluxe \u{00B7} FLAC \u{00B7} Portishead/Third (2008) [Deluxe]"])
        #expect(Sources.signalChips(found).map(\.label) == ["Track names", "Track count", "Edition", "Format", "Availability"])
    }

    @Test func anEnqueueAnswerIsAJobOrAJoin() throws {
        let queued = try JSONDecoder().decode(EnqueueAnswer.self, from: Data(#"{"status":"ok","queued":11,"job_id":57}"#.utf8))
        #expect(queued.jobId == 57 && queued.queued == 11 && !queued.joined)
        let joined = try JSONDecoder().decode(EnqueueAnswer.self,
                                              from: Data(#"{"status":"ok","queued":0,"job_id":41,"joined":true}"#.utf8))
        #expect(joined.jobId == 41 && joined.joined)
        let none = try JSONDecoder().decode(EnqueueAnswer.self, from: Data(#"{"status":"ok","queued":0}"#.utf8))
        #expect(none.jobId == nil)
    }

    // MARK: the client

    @Test func theFourRoutesAreAskedAsTheServerDeclaresThem() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/store_state", 200,
                         #"{"downloading":null,"downloading_part":null,"held":{"path":"P/T","paths":["P/T"],"artist":"Portishead","album":"Third","edition":"","track_count":11,"expected_tracks":11,"formats":["flac"],"complete":true},"other_pressings":[]}"#)
        transport.answer("/deadwax/download/find_candidates", 200, #"{"query":"","queries":[],"response_count":0,"candidates":[],"downloading":null,"downloading_part":null,"held":null,"other_pressings":[]}"#)
        transport.answer("/deadwax/download/enqueue", 200, #"{"status":"ok","queued":2,"job_id":9}"#)
        transport.answer("/deadwax/me/preferences", 200,
                         #"{"get_mode":"pick","quality_floor":"lossless","format_preference":"any","stored":[],"seeded":true,"unseeded":[],"can_save":true}"#)
        let release = GetRelease.build(group: Self.group, release: Self.pressing)

        let store = try await deadwax.storeState(release)
        #expect(store.held?.complete == true)
        #expect(transport.last?.method == "POST" && transport.last?.timeout == 20)
        #expect(try sentJSON(transport.last)["release_mbid"] == .string("r-cd"))

        _ = try await deadwax.findCandidates(FindCandidatesBody(release: release, format: .preferLossless, queryOverride: "Third"))
        #expect(transport.last?.method == "POST" && transport.last?.timeout == 300)
        #expect(try sentJSON(transport.last)["query_override"] == .string("Third"))

        let queued = try await deadwax.enqueue(EnqueueBody(candidate: Self.candidate("bob", "Third"), release: release, shown: []))
        #expect(queued.jobId == 9 && transport.last?.timeout == 300 && transport.last?.url.path == "/deadwax/download/enqueue")

        let settings = try await deadwax.getSettings()
        #expect(settings == GetSettingsAnswer(settings: GetSettings(mode: .pick, floor: .lossless, format: .any), canSave: true))
        #expect(transport.last?.method == "GET" && transport.last?.body == nil)
        transport.answer("/deadwax/me/preferences", 200, #"{"get_mode":7,"quality_floor":"best"}"#)
        #expect(try await deadwax.getSettings() == GetSettingsAnswer(settings: .defaults, canSave: true))
        //? only false is a database that won't keep them (readGetSettings: `can_save !== false`)
        transport.answer("/deadwax/me/preferences", 200, #"{"can_save":false}"#)
        #expect(try await deadwax.getSettings().canSave == false)
        transport.answer("/deadwax/me/preferences", 200, #"{"can_save":"no"}"#)
        #expect(try await deadwax.getSettings().canSave == true)
    }

    @Test func aRefusedEnqueueIsThrownInDeadwaxsWords() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/enqueue", 409, #"{"detail":"Already downloading from bob"}"#)
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        do {
            _ = try await deadwax.enqueue(EnqueueBody(candidate: Self.candidate("bob", "Third"), release: release, shown: []))
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(ErrorWords.kind(of: error) == .refused)
        }
    }

    // MARK: the album page takes the store line's word

    @Test func theMetaLineTakesTheStoreLinesWordForThePressingShown() {
        let usual = ["Silence", "Hunter"]
        func release(_ id: String) -> PageRelease {
            PageRelease(id: id, title: "Third", status: "Official", date: "2008-04-28", country: "GB",
                        media: [MBMedium(position: 1, format: "CD", tracks: usual.enumerated().map {
                            MBTrack(number: String($0.offset + 1), position: $0.offset + 1, title: $0.element, length: 240_000)
                        })])
        }
        let answer = ReleaseGroupAnswer(id: Self.group.id, releases: [release("r-cd"), release("r-lp")])
        //? the library's kept answer says yours
        let index = OwnedIndex([OwnedAlbum(path: "Portishead/Third (2008)", artist: "Portishead", album: "Third",
                                           releaseMbid: "r-cd", releaseGroupMbid: Self.group.id, yours: true)])
        func page(_ store: (id: String, answer: StoreStateAnswer)?) -> GroupPage {
            GroupPage(id: Self.group.id, answer: answer, preview: Self.group, index: index, picked: nil, personal: true,
                      editors: false, store: store)
        }
        #expect(page(nil).meta.hasSuffix("in your library"))
        //? ...and the store line, asked as the page shows, says it isn't - an unstar read back since
        let said = StoreStateAnswer(held: HeldPressing(path: "Portishead/Third (2008)", paths: ["Portishead/Third (2008)"],
                                                       trackCount: 2, expectedTracks: 2, complete: true, yours: false))
        let shown = page(("r-cd", said))
        #expect(shown.chosenId == "r-cd")
        #expect(shown.meta.hasSuffix("in the collection"), "\(shown.meta)")
        //? another pressing's answer says nothing of the one shown
        #expect(page(("r-lp", said)).meta.hasSuffix("in your library"))
    }

    @Test func theSheetsSubtitleIsTheTitleAndThePressingEitherLeftOutWhenEmpty() {
        // ReleaseGroupPage.tsx: [header.title, pressingLabel(chosen)].filter(Boolean).join(' · ')
        #expect(SourcesWords.subtitle(title: "Third", pressing: "CD \u{00B7} 2008 \u{00B7} GB") == "Third \u{00B7} CD \u{00B7} 2008 \u{00B7} GB")
        #expect(SourcesWords.subtitle(title: "Third", pressing: "") == "Third")
        #expect(SourcesWords.subtitle(title: "", pressing: "CD") == "CD")
        #expect(SourcesWords.subtitle(title: "", pressing: "") == "")
    }

    @Test func aScoreIsDrawnAsTheWebDrawsIt() {
        #expect(SourcesWords.percent(92) == "92%")
        #expect(SourcesWords.match(7) == "7% match")
        #expect(SourcesWords.reasons(100) == "Why it's a 100% match")
    }

    // MARK: a Get whose answer never came - the phone's own (slice 2's review, finding 2)

    /// A Get for Third's CD from bob, asked with jobs 1 and 2 listed.
    static let asked = PendingDownload(key: "pending-1", artist: "Portishead", album: "Third", username: "bob",
                                       releaseMbid: "r-cd", directory: "Portishead\\Third (CD)", listedBefore: [1, 2])

    @Test func onlyAnAnswerThatNeverCameIsUnansweredRatherThanRefused() {
        let server = ServerAddress(base: URL(string: "http://deadwax.test:8080")!)
        let none = APIFailure.NoAnswer(server: server, method: "POST", path: "/download/enqueue", reason: "timed out")
        func answered(_ status: Int) -> APIFailure {
            .answered(.init(status: status, method: "POST", path: "/download/enqueue", detail: "already downloading from bob"))
        }
        #expect(RequestOverlays.unanswered(APIFailure.timeout(none)))
        #expect(RequestOverlays.unanswered(URLError(.timedOut)))
        //? a proxy between that gave up: deadwax may still be waiting on slskd
        #expect(RequestOverlays.unanswered(answered(504)))
        #expect(RequestOverlays.unanswered(answered(408)))
        //? never sent, or refused: no download started
        #expect(!RequestOverlays.unanswered(APIFailure.offline(none)))
        #expect(!RequestOverlays.unanswered(answered(409)))
        #expect(!RequestOverlays.unanswered(answered(502)))
        // and the phone waits for it as long as for a search (deadwax puts no bound on it)
        #expect(Routes.timeouts[Routes.enqueue] == Routes.timeouts[Routes.findCandidates])
    }

    @Test func aGetWhoseAnswerNeverCameStaysStartingAndIsLookedFor() {
        let waiting = RequestOverlays.none.withPending(Self.asked).stoppedWaiting("pending-1")
        #expect(waiting.pending.first?.unanswered == true && waiting.pending.first?.error == nil)
        #expect(waiting.looksForAJob)
        #expect(waiting.activeCount([]) == 1)
        let view: RequestsView = RequestsView.make(RequestsInput(pending: waiting.visiblePending([])), now: 0)
        let row = view.rows(.waiting).first
        #expect(row?.line == "Portishead \u{00B7} from bob \u{00B7} starting\u{2026}")
        #expect(view.rows(.attention).isEmpty)
        // an answer still in hand isn't looked for, nor given up on; a refused one isn't made to wait
        let asking = RequestOverlays.none.withPending(Self.asked)
        #expect(!asking.looksForAJob)
        #expect(asking.gaveUp("pending-1") == asking)
        let refused = RequestOverlays.none.withPending(Self.asked)
            .settlePending("pending-1", .refused(error: "It's already downloading.", detail: nil))
        #expect(refused.stoppedWaiting("pending-1") == refused)
        #expect(refused.gaveUp("pending-1") == refused)
    }

    @Test func aPollFindsTheJobOfAnUnansweredGetByItsPressingAndFolder() {
        let waiting = RequestOverlays.none.withPending(Self.asked).stoppedWaiting("pending-1")
        let before = DownloadJob(id: 2, status: "failed", username: "bob", directory: "Portishead\\Third (CD)",
                                 releaseMbid: "r-cd")
        let other = DownloadJob(id: 7, status: "queued", username: "bob", directory: "Portishead\\Dummy",
                                releaseMbid: "r-dummy")
        let joined = DownloadJob(id: 8, status: "downloading", username: "carol", directory: "Third [FLAC]",
                                 releaseMbid: "r-cd")
        let own = DownloadJob(id: 9, status: "queued", username: "bob", directory: "Portishead\\Third (CD)",
                              releaseMbid: "r-cd")
        //? listed before the tap, or another pressing: not its job
        #expect(waiting.claimed([before, other]) == waiting)
        // its own folder from its own peer first, then the row goes as an answer's would
        let found = waiting.claimed([before, other, joined, own])
        #expect(found.pending.first?.jobId == 9)
        #expect(found.visiblePending([before, other, joined, own]).isEmpty)
        #expect(found.reconcile([before, other, joined, own]).pending.isEmpty)
        #expect(!found.looksForAJob)
        // else a new download of the same pressing - with logins on, the one deadwax joined it to
        #expect(waiting.claimed([before, joined]).pending.first?.jobId == 8)
        // one job goes to one request
        var second = Self.asked
        second.key = "pending-2"
        let two = waiting.withPending(second).stoppedWaiting("pending-2").claimed([own])
        #expect(two.pending.compactMap(\.jobId) == [9])
        // a request still waiting for its answer, or with no pressing to go by, is left to its answer
        #expect(RequestOverlays.none.withPending(Self.asked).claimed([own]).pending.first?.jobId == nil)
        var unknown = Self.asked
        unknown.releaseMbid = nil
        #expect(RequestOverlays.none.withPending(unknown).stoppedWaiting("pending-1").claimed([own]).pending.first?.jobId == nil)
    }

    @Test func givenUpOnAnUnansweredGetSaysItMayHaveStarted() {
        let given = RequestOverlays.none.withPending(Self.asked).stoppedWaiting("pending-1").gaveUp("pending-1")
        #expect(given.pending.first?.mayHaveStarted == true)
        #expect(!given.looksForAJob)
        #expect(given.activeCount([]) == 0)
        let view: RequestsView = RequestsView.make(RequestsInput(pending: given.visiblePending([])), now: 0)
        let row = view.rows(.attention).first
        #expect(row?.line == "Portishead \u{00B7} from bob \u{00B7} no answer")
        #expect(row?.reason == RequestWords.mayHaveStarted)
        #expect(RequestWords.mayHaveStarted.contains("may have started"))
        #expect(view.clearable)
        #expect(given.withoutRefused().pending.isEmpty)
        // its job showing after all still takes the row away
        let own = DownloadJob(id: 9, status: "queued", username: "bob", directory: "Portishead\\Third (CD)",
                              releaseMbid: "r-cd")
        let late = given.claimed([own])
        #expect(late.pending.first?.jobId == 9 && late.pending.first?.error == nil)
        #expect(late.reconcile([own]).pending.isEmpty)
    }

    // MARK: slice 3 - the auto-pick, as the hook decides it (useCandidateSearch.ts `run`)

    @Test func aFreshGetSetToPickAsksForTheBestMatchThroughTheChips() {
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        let strong = Self.candidate("bob", "Third", score: 0.92)
        let weak = Self.candidate("alice", "Third (MP3)", score: 0.6)
        let answer = FindCandidatesAnswer(query: "Portishead Third", candidates: [strong, weak])
        let none = GetSettings.candidateFilters(.none)
        // When I tap Get shows the sources: nothing is picked, and nothing said
        #expect(Sources.autoPick(fresh: true, mode: .sources, answer: answer, release: release, filters: none) == .off)
        // a search again by hand never picks
        #expect(Sources.autoPick(fresh: false, mode: .pick, answer: answer, release: release, filters: none) == .off)
        // the best match through the chips, with the list it tops for its runners-up
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: answer, release: release, filters: none)
                == .picked(strong, list: [strong, weak]))
        // the chips decide what passes: the best of what passes is picked, at 75 or more only
        let starts = GetSettings.candidateFilters(SourceFilters(freeSlot: true))
        let busy = Candidate(username: "bob", directory: "Music\\Third", directoryName: "Third", score: 0.92, hasFreeSlot: false)
        let free = Candidate(username: "jo", directory: "Music\\Third 2", directoryName: "Third", score: 0.75, hasFreeSlot: true)
        let either = FindCandidatesAnswer(query: "q", candidates: [busy, free])
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: either, release: release, filters: starts)
                == .picked(free, list: [free]))
        let low = Candidate(username: "jo", directory: "Music\\Third 3", directoryName: "Third", score: 0.7449, hasFreeSlot: true)
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: FindCandidatesAnswer(query: "q", candidates: [busy, low]),
                                 release: release, filters: starts)
                == .notPicked("No close match that passes your filters - choose a source yourself."))
    }

    @Test func aPickIsNeverMadeForAPressingHeldOrOnItsWayOrUnjudgeable() {
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        let strong = Self.candidate("bob", "Third", score: 0.98)
        let none = GetSettings.candidateFilters(.none)
        let part = HeldPressing(path: "Portishead/Third", trackCount: 5, expectedTracks: 11, complete: false)
        let answer = FindCandidatesAnswer(query: "q", candidates: [strong], store: StoreStateAnswer(held: part))
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: answer, release: release, filters: none)
                == .notPicked("You already have part of it - choose a source yourself."))
        // the album as a whole (no pressing): no tracklist and no release id, so no score can be trusted
        let whole = GetRelease.build(group: Self.group, release: nil)
        #expect(whole.tracks.isEmpty && (whole.releaseMbid ?? "").isEmpty)
        let found = FindCandidatesAnswer(query: "q", candidates: [strong])
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: found, release: whole, filters: none)
                == .notPicked("This pressing has no tracklist to check the sources against - choose a source yourself."))
        // nothing found at all: nothing to choose, and the empty state says it
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: FindCandidatesAnswer(query: "q"), release: release,
                                 filters: none) == .notPicked(nil))
        // the overload reads the release as the web's does
        #expect(Sources.autoPickBlocked(found, release: whole) == "This pressing has no tracklist to check the sources against")
        #expect(Sources.autoPickBlocked(found, release: release) == nil)
        #expect(Sources.autoPickBlocked(nil, release: whole) == nil)
    }

    // MARK: slice 3 - You > Getting albums, chosen on the phone (useGetSettings.ts `shown`)

    @Test func aChoiceShowsAtOnceLaidOverDeadwaxsLastWord() {
        let said = GetSettingsAnswer(settings: GetSettings(mode: .sources, floor: .lossless, format: .any), canSave: true)
        // nothing known and nothing being saved: nothing is shown as chosen
        #expect(GetSettingsAnswer.shown(nil, pending: []) == nil)
        #expect(GetSettingsAnswer.shown(said, pending: []) == said)
        // choices still being saved, laid over in the order made - the newer wins
        let shown = GetSettingsAnswer.shown(said, pending: [GetChoice(mode: .pick), GetChoice(floor: .bit24),
                                                            GetChoice(mode: .sources)])
        #expect(shown?.settings == GetSettings(mode: .sources, floor: .bit24, format: .any))
        // a choice before deadwax ever answered is laid over the defaults
        #expect(GetSettingsAnswer.shown(nil, pending: [GetChoice(format: .losslessOnly)])?.settings
                == GetSettings(mode: .sources, floor: .any, format: .losslessOnly))
        // whether it can be kept is deadwax's word alone
        let unkept = GetSettingsAnswer(settings: .defaults, canSave: false)
        #expect(GetSettingsAnswer.shown(unkept, pending: [GetChoice(mode: .pick)])?.canSave == false)
    }

    @Test func aChoiceSendsOnlyWhatWasChosen() throws {
        func sent(_ choice: GetChoice) throws -> [String: String] {
            try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(choice))
        }
        #expect(try sent(GetChoice(mode: .pick)) == ["get_mode": "pick"])
        #expect(try sent(GetChoice(floor: .kbps320)) == ["quality_floor": "320"])
        #expect(try sent(GetChoice(format: .losslessOnly)) == ["format_preference": "lossless_only"])
        #expect(try sent(GetChoice(mode: .sources, floor: .bit24, format: .any))
                == ["get_mode": "sources", "quality_floor": "24bit", "format_preference": "any"])
        #expect(try sent(GetChoice()) == [:])
    }

    // MARK: slice 3 - the client's Join, save and Add

    @Test func joinSaveAndAddAreAskedAsTheServerDeclaresThem() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/jobs/41/join", 200, #"{"status":"ok","job_id":41,"joined":true}"#)
        let joined = try await deadwax.joinJob(41)
        #expect(joined == JoinAnswer(jobId: 41, joined: true))
        #expect(transport.last?.method == "POST" && transport.last?.body == nil && transport.last?.timeout == 60)
        transport.answer("/deadwax/download/jobs/41/join", 200, #"{"status":"ok","job_id":41,"joined":false}"#)
        #expect(try await deadwax.joinJob(41).joined == false)

        transport.answer("/deadwax/me/preferences", 200,
                         #"{"get_mode":"pick","quality_floor":"any","format_preference":"prefer_lossless","can_save":true}"#)
        let saved = try await deadwax.saveSettings(GetChoice(mode: .pick))
        #expect(saved.settings.mode == .pick && saved.canSave)
        #expect(transport.last?.method == "PUT" && transport.last?.url.path == "/deadwax/me/preferences")
        #expect(try sentJSON(transport.last) == ["get_mode": .string("pick")])

        transport.answer("/deadwax/me/library/add", 200, #"{"added":true,"already":false,"complete":true,"starred":true}"#)
        let release = GetRelease.build(group: Self.group, release: Self.pressing)
        let added = try await deadwax.addToLibrary(release)
        #expect(added.added && added.complete)
        #expect(transport.last?.method == "POST")
        // the line's Add sends the pressing a Get would download, as the web's does - its tracks and all
        let body = try sentJSON(transport.last)
        #expect(body["release_mbid"] == .string("r-cd") && body["album"] == .string("Third"))
        #expect(body["tracks"] != nil)
    }

    @Test func aRefusedJoinIsThrownInDeadwaxsWords() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/download/jobs/41/join", 409,
                         #"{"detail":"that download has been cleared from the list since - get it again"}"#)
        do {
            _ = try await deadwax.joinJob(41)
            Issue.record("expected a failure")
        } catch {
            #expect(ErrorWords.kind(of: error) == .refused)
            #expect(ErrorWords.of(error).said.contains("cleared from the list since"))
        }
    }
}
