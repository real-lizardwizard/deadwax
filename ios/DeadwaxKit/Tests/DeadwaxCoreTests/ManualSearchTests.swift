import Foundation
import Testing
@testable import DeadwaxCore

/// Manual search, slice A1 (notes/ios.md "Manual search, slice A1"): Requests' Search Soulseek - an artist and an album
/// typed, the folders found ranked by how closely their names fit, Get one, filed by its own tags (server 2.1.37,
/// 2.1.38). The app's own: the web never asks a manual question, so nothing here is in its vectors - Fixtures/get and
/// Fixtures/requests stay the web's word for word (their sims check them against the web's TypeScript), and these hold
/// the phone's and the Mac's rules by hand, as GetTests holds the hook the exporter can't compile. The bodies and
/// answers are written as the routes take and send them (tests/test_ios_manual_search.py holds the same shapes on the
/// server's side).
@Suite struct ManualSearchTests {
    static let release = GetRelease.manual(artist: "  Radiohead ", album: "\tOK Computer  ")

    // MARK: the question

    @Test func aManualQuestionIsTheWordsTrimmedWithTheFlagAndNothingElse() throws {
        let release = Self.release
        #expect(release.artist == "Radiohead" && release.albumArtist == "Radiohead" && release.album == "OK Computer")
        #expect(release.manual && release.releaseMbid == nil && release.tracks.isEmpty && release.year == nil)
        #expect(release.originalYear == nil && release.releaseGroupMbid == nil && release.artistMbids.isEmpty)
        #expect(release.editionTags.isEmpty)
        let body = FindCandidatesBody(release: release, format: .preferLossless, queryOverride: "")
        let sent = try JSONDecoder().decode([String: SentValue].self, from: JSONEncoder().encode(body))
        // no pressing's four: there is no pressing
        #expect(Set(sent.keys) == ["artist", "album_artist", "artist_mbids", "album", "year", "original_year", "release_mbid",
                                   "edition_tags", "tracks", "release_group_mbid", "manual", "format_preference",
                                   "query_override"])
        #expect(sent["manual"] == .bool(true))
        #expect(sent["artist"] == .string("Radiohead") && sent["album_artist"] == .string("Radiohead"))
        #expect(sent["album"] == .string("OK Computer") && sent["release_mbid"] == .null && sent["year"] == .null)
        #expect(sent["tracks"] == .list([]) && sent["artist_mbids"] == .list([]) && sent["edition_tags"] == .list([]))
        // a Get from it carries the flag inside its release - what the server files by own tags
        let card = Candidate(username: "mellotron", directory: "@@x\\Radiohead\\OK Computer", directoryName: "OK Computer",
                             score: 0.92, files: [CandidateFile(filename: "@@x\\Radiohead\\OK Computer\\01.flac", size: 10)])
        let get = try JSONDecoder().decode([String: SentValue].self,
                                           from: JSONEncoder().encode(EnqueueBody(candidate: card, release: release, shown: [card])))
        guard case .object(let filed)? = get["release"] else { Issue.record("no release"); return }
        #expect(filed["manual"] == .bool(true) && filed["album"] == .string("OK Computer"))
        #expect(get["manual"] == nil, "inside the release, where EnqueueRelease declares it")
    }

    @Test func everyOtherQuestionIsSentWithoutTheFlag() throws {
        // a pressing and the album as a whole: byte for byte the web's (no `manual` key at all)
        let pressing = GetRelease.build(group: GetTests.group, release: GetTests.pressing)
        let whole = GetRelease.build(group: GetTests.group, release: nil)
        for release in [pressing, whole] {
            #expect(!release.manual)
            let text = String(decoding: try JSONEncoder().encode(release), as: UTF8.self)
            #expect(!text.contains("manual"), "\(text)")
        }
    }

    @Test func theAlbumsOwnWordsAskForTheirEdition() {
        // as a pressing's title does (EditionTags.detect): a typed "Deluxe" asks for deluxe
        #expect(GetRelease.manual(artist: "Kanye West", album: "Donda (Deluxe)").editionTags == ["DELUXE"])
        #expect(GetRelease.manual(artist: "Radiohead", album: "OK Computer OKNOTOK 1997 2017 Remastered").editionTags
                == ["REMASTER"])
        #expect(GetRelease.manual(artist: "Ten Years After", album: "Live at the Fillmore East").editionTags.isEmpty)
    }

    @Test func searchIsOnOnlyWithBothFieldsTyped() {
        #expect(ManualSearch.canSearch(artist: "Radiohead", album: "OK Computer"))
        #expect(ManualSearch.canSearch(artist: " Radiohead", album: "OK Computer\n"))
        #expect(!ManualSearch.canSearch(artist: "", album: "OK Computer"))
        #expect(!ManualSearch.canSearch(artist: "Radiohead", album: ""))
        #expect(!ManualSearch.canSearch(artist: " \t", album: "OK Computer"))
        #expect(!ManualSearch.canSearch(artist: "Radiohead", album: "   "))
        #expect(!ManualSearch.canSearch(artist: "", album: ""))
    }

    // MARK: the answer

    /// find_candidates' answer to a manual question, as the route sends it (2.1.38): echoed `manual`, every card's
    /// signals the folder name first and the three track signals null, nothing expected, the store's four null.
    static let answer = #"""
    {"query":"Radiohead OK Computer","queries":["Radiohead OK Computer"],"response_count":3,
     "candidates":[{"username":"mellotron","directory":"@@x\\Radiohead\\OK Computer","directory_name":"OK Computer",
      "score":0.92,"signals":{"name_match":1.0,"title_match":null,"track_count":null,"duration_match":null,"edition":1.0,
      "format":0.5,"peer":0.25},"matched_tracks":0,"expected_tracks":0,"audio_file_count":12,"detected_edition_tags":[],
      "disc_folders":[],"formats":["mp3"],"upload_speed":1000,"queue_length":40,"has_free_slot":false,"total_size":104857600,
      "bitrates":[320],"bit_depths":[],"sample_rates":[],"variable_bitrate":false,"missing_tracks":[],"missing_count":0,
      "audio_expected":0,"files":[{"filename":"@@x\\Radiohead\\OK Computer\\01 Airbag.mp3","size":8000000}]}],
     "held":null,"downloading":null,"downloading_part":null,"other_pressings":[],"manual":true}
    """#

    @Test func aManualAnswerIsReadWithTheFolderNameFirstAndNoTrackParts() throws {
        let answer = try JSONDecoder().decode(FindCandidatesAnswer.self, from: Data(Self.answer.utf8))
        #expect(answer.manual)
        let card = try #require(answer.candidates.first)
        let chips = Sources.signalChips(card)
        #expect(chips.map(\.label) == ["Folder name", "Edition", "Format", "Availability"])
        #expect(chips.first?.value == 100 && chips.first?.band == .good)
        #expect(chips.first?.meaning == "how closely the folder's name is the artist and album you typed")
        // no tracklist: its files counted, nothing missing
        #expect(Sources.tracksText(card) == "12 files" && Sources.missingLine(card) == nil)
        #expect(Sources.everyTrackPresent(card))
        // the store has nothing to say of a question without a release id
        #expect(StoreLine.drawn(answer.store, floor: .lossless, joins: true) == nil && StoreLine.notes(answer.store).isEmpty)
        #expect(!ManualSearch.needsNewer(Self.release, answer))
        #expect(ManualSearch.tooOldLine(Self.release, answer, runs: true) == nil)
        // the web's six are the web's still, word for word; the folder name is the app's own, read first
        #expect(Sources.signals.map(\.signal) == ["title_match", "track_count", "duration_match", "edition", "format", "peer"])
        #expect(Sources.named.map(\.signal).first == "name_match" && Array(Sources.named.dropFirst()).map(\.signal)
                == Sources.signals.map(\.signal))
    }

    @Test func aServerThatDroppedTheFlagHasEveryGetOffAndSaysWhy() throws {
        // before 2.1.38 there was no echo: the server would file the download by the typed words, over its own tags
        let older = Self.answer.replacingOccurrences(of: #","manual":true"#, with: "")
        #expect(older != Self.answer)
        let answer = try JSONDecoder().decode(FindCandidatesAnswer.self, from: Data(older.utf8))
        #expect(!answer.manual)
        #expect(ManualSearch.needsNewer(Self.release, answer))
        #expect(ManualSearch.tooOldLine(Self.release, answer, runs: false) == "This needs a newer deadwax - ask whoever runs it.")
        #expect(ManualSearch.tooOldLine(Self.release, answer, runs: true) == "This needs deadwax 2.1.38 or later on the server.")
        // only a manual question is gated - every other Get is as it was - and only once there is an answer
        let pressing = GetRelease.build(group: GetTests.group, release: GetTests.pressing)
        #expect(!ManualSearch.needsNewer(pressing, answer) && ManualSearch.tooOldLine(pressing, answer, runs: true) == nil)
        #expect(!ManualSearch.needsNewer(Self.release, nil))
        // anything but true is no echo
        let odd = Self.answer.replacingOccurrences(of: #""manual":true"#, with: #""manual":"yes""#)
        #expect(try !JSONDecoder().decode(FindCandidatesAnswer.self, from: Data(odd.utf8)).manual)
    }

    @Test func theChipsHaveNoCompleteAlbumsOnlyForAManualSearch() {
        for floor in QualityFloor.allCases {
            let usual = GetSettings.chips(floor, .none)
            let manual = GetSettings.chips(floor, .none, manual: true)
            #expect(usual.last?.key == .complete, "\(floor)")
            #expect(manual.map(\.key) == usual.dropLast().map(\.key), "\(floor)")
            #expect(GetSettings.chips(floor, .none, manual: false) == usual)
        }
        #expect(GetSettings.chips(.any, .none, manual: true).map(\.label) == ["Lossless", "24-bit", "Starts now"])
        #expect(GetSettings.chips(.kbps320, GetSettings.floorFilters(.kbps320), manual: true).map(\.label)
                == ["Lossless", "24-bit", "320 kbps", "Starts now"])
    }

    @Test func nothingIsPickedForAManualSearchAndNothingSaid() throws {
        let answer = try JSONDecoder().decode(FindCandidatesAnswer.self, from: Data(Self.answer.utf8))
        let strong = Candidate(username: "jo", directory: "@@y\\Radiohead\\OK Computer", directoryName: "OK Computer",
                               score: 0.98, formats: ["flac"], hasFreeSlot: true)
        let found = FindCandidatesAnswer(query: answer.query, candidates: [strong] + answer.candidates, manual: true)
        let none = GetSettings.candidateFilters(.none)
        // Pick the best source for me: the folder is yours to choose - not "no tracklist to check the sources against"
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: found, release: Self.release, filters: none) == .off)
        #expect(Sources.autoPick(fresh: true, mode: .sources, answer: found, release: Self.release, filters: none) == .off)
        // the album as a whole, as ever: the same answer says why it wasn't picked
        let whole = GetRelease.build(group: GetTests.group, release: nil)
        #expect(Sources.autoPick(fresh: true, mode: .pick, answer: found, release: whole, filters: none)
                == .notPicked("This pressing has no tracklist to check the sources against - choose a source yourself."))
    }

    @Test func theSheetSaysWhatItLooksForInTheTypedWords() throws {
        #expect(Sources.searchingLine(Self.release) == "Looking for \u{201C}OK Computer\u{201D} by Radiohead\u{2026}")
        #expect(ManualSearch.subtitle == "Your own search \u{00B7} filed by its own tags")
        // the outcome, and why the Gets are off, said together to VoiceOver
        let older = try JSONDecoder().decode(FindCandidatesAnswer.self,
                                              from: Data(Self.answer.replacingOccurrences(of: #","manual":true"#, with: "").utf8))
        let said = Sources.announcement(pending: false, release: Self.release, error: nil, status: nil, answer: older,
                                        shown: 1, notPicked: ManualSearch.tooOldLine(Self.release, older, runs: false),
                                        format: .preferLossless)
        #expect(said == "1 source. This needs a newer deadwax - ask whoever runs it.")
    }

    // MARK: Requests

    static func job(_ id: Int, _ status: String, outcome: String? = nil, manual: Bool? = true) -> DownloadJob {
        DownloadJob(id: id, status: status, artist: "radiohead", album: "ok computer", username: "mellotron",
                    updatedAt: "2026-11-24T10:00:00+00:00", edition: "1997 CD", outcome: outcome, progress: 0, manual: manual)
    }

    @Test func aManualDownloadIsMarkedUnderEveryHeading() throws {
        let jobs = [Self.job(1, "downloading"), Self.job(2, "queued"), Self.job(3, "failed", outcome: "failed"),
                    Self.job(4, "organized", outcome: "filed")]
        let board = RequestsView.make(RequestsInput(jobs: jobs), now: AlbumTime.ms("2026-11-24T10:12:00+00:00") ?? 0)
        for section in RequestSection.allCases {
            let row = board.rows(section).first
            // the typed words, as the job keeps them, and "manual search" where an edition would go
            #expect(row?.title == "ok computer \u{00B7} manual search", "\(section)")
            #expect(row?.manual == true && row?.cover == nil, "\(section)")
        }
        #expect(board.rows(.waiting).first?.line == "radiohead \u{00B7} from mellotron \u{00B7} starting")
        // done: as any other's line, and filed by its own tags; it doesn't open yet (no release id - slice A2's)
        let done = try #require(board.rows(.done).first)
        #expect(done.line == "In your library \u{00B7} 12 minutes ago" && done.ownTags && done.release == nil && !done.plays)
        #expect(ManualSearch.doneLine(done, edits: true) == "Filed by its own tags. Edit album > Release can match it to a pressing.")
        #expect(ManualSearch.doneLine(done, edits: false) == "Filed by its own tags, not matched to a pressing.")
    }

    @Test func onlyAManualDownloadThisFiledSaysItWasFiledByItsOwnTags() {
        func done(_ job: DownloadJob) -> RequestRow? { RequestsView.make(RequestsInput(jobs: [job]), now: 0).rows(.done).first }
        // filed, and filed in part: by its own tags
        for outcome in ["filed", "partly_filed"] {
            let row = done(Self.job(5, "organized", outcome: outcome))
            #expect(row?.ownTags == true && ManualSearch.doneLine(row!, edits: true) != nil, "\(outcome)")
        }
        // nothing filed by this download, or not filed at all
        for outcome in ["already_there", "interrupted"] {
            let row = done(Self.job(6, "organized", outcome: outcome))
            #expect(row?.ownTags == false && row.flatMap { ManualSearch.doneLine($0, edits: true) } == nil, "\(outcome)")
        }
        // any other download: its edition, and no such line
        let usual = done(DownloadJob(id: 7, status: "organized", album: "Dummy", releaseMbid: "r-1", edition: "1994 CD",
                                     outcome: "filed"))
        #expect(usual?.title == "Dummy \u{00B7} 1994 CD" && usual?.manual == false && usual?.ownTags == false)
        #expect(usual.flatMap { ManualSearch.doneLine($0, edits: true) } == nil)
        let unsaid = done(Self.job(8, "organized", outcome: "filed", manual: false))
        #expect(unsaid?.title == "ok computer \u{00B7} 1997 CD" && unsaid?.ownTags == false)
    }

    @Test func aManualGetIsMarkedFromTheTap() {
        let pending = PendingDownload(key: "pending-1", artist: "Radiohead", album: "OK Computer", username: "mellotron",
                                      directory: "@@x\\Radiohead\\OK Computer", listedBefore: [], manual: true)
        let row = RequestsView.make(RequestsInput(pending: [pending]), now: 0).rows(.waiting).first
        #expect(row?.title == "OK Computer \u{00B7} manual search" && row?.manual == true)
        #expect(row?.line == "Radiohead \u{00B7} from mellotron \u{00B7} starting\u{2026}")
        // refused, it still says what it was
        let refused = RequestOverlays(pending: [pending]).settlePending("pending-1", .refused(error: "It broke.", detail: nil))
        #expect(RequestsView.make(RequestsInput(pending: refused.pending), now: 0).rows(.attention).first?.title
                == "OK Computer \u{00B7} manual search")
        // any other Get's pending row is as it was
        let usual = PendingDownload(key: "pending-2", artist: "Portishead", album: "Dummy", username: "bob")
        #expect(RequestsView.make(RequestsInput(pending: [usual]), now: 0).rows(.waiting).first?.title == "Dummy")
    }

    @Test func aManualRowIsReadAsJobsSendsIt() throws {
        //? /download/jobs (2.1.38): `manual` only on a manual search's row, the artist and album the typed words
        let json = #"""
        {"jobs":[{"attempt":1,"id":12,"artist":"radiohead","album":"ok computer","year":null,"username":"mellotron",
        "directory":"@@x\\Radiohead\\OK Computer","status":"queued","error":null,"created_at":"2026-11-24T10:00:00+00:00",
        "updated_at":"2026-11-24T10:00:00+00:00","release_mbid":null,"release_group_mbid":null,"edition":null,
        "manual":true,"outcome":null,"queue_position":null,"files_total":12,"matched":false},
        {"id":13,"status":"queued","album":"Dummy","edition":"1994 CD"},
        {"id":14,"status":"queued","album":"Third","manual":"yes"}],"tracking_enabled":true}
        """#
        let answer = try JSONDecoder().decode(JobsAnswer.self, from: Data(json.utf8))
        #expect(answer.jobs.map(\.manual) == [true, nil, nil])
        let titles = RequestsView.make(RequestsInput(jobs: answer.jobs), now: 0).rows(.waiting).map(\.title)
        #expect(titles == ["ok computer \u{00B7} manual search", "Dummy \u{00B7} 1994 CD", "Third"])
    }
}
