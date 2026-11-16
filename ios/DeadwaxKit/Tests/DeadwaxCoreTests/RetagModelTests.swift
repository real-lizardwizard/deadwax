import Foundation
import Testing
@testable import DeadwaxCore

/// The Release page's rules (RetagFlow, phase8-managing.md 2 and 3.3) - only the newest answer draws, the preview waits
/// out the debounce and a tracklist on its way, Apply is on only for a current preview that changes something, and an
/// apply that never answered is said as maybe finished and read again before anything is offered - and Edit album's
/// routes as the phone asks them.
@Suite struct RetagModelTests {
    static let plan = RetagPlan(albumPath: "A/B", changedFileCount: 2, fileCount: 2)
    static let empty = RetagPlan(albumPath: "A/B", fileCount: 2, empty: true)

    /// A mutating rule's answer, outside #expect (which can't call one).
    static func take(_ flow: inout RetagFlow, _ call: (inout RetagFlow) -> Bool) -> Bool { call(&flow) }

    /// A flow with the preview of what the page shows in hand.
    static func previewed() -> RetagFlow {
        var flow = RetagFlow()
        let edit = flow.changed()
        #expect(flow.due(edit))
        #expect(Self.take(&flow) { $0.answered(edit) })
        return flow
    }

    // MARK: newest answer

    @Test func onlyTheNewestSearchDraws() {
        var flow = RetagFlow()
        let first = flow.beginSearch()
        let second = flow.beginSearch()
        #expect(!flow.isNewest(search: first))
        #expect(flow.isNewest(search: second))
        flow.searchEnded(first)
        #expect(flow.searching, "an older search ending leaves the newer one's spinner")
        flow.searchEnded(second)
        #expect(!flow.searching)
    }

    @Test func onlyTheNewestPickLands() {
        var flow = Self.previewed()
        let first = flow.beginLoad()
        #expect(flow.loadingRelease && flow.planning)
        #expect(!flow.canApply(Self.plan), "no Apply while a tracklist is on its way")
        let second = flow.beginLoad()
        #expect(!Self.take(&flow) { $0.loadEnded(first) }, "a pick since then owns the selection")
        #expect(flow.loadingRelease)
        #expect(Self.take(&flow) { $0.loadEnded(second) })
        #expect(!flow.loadingRelease)
    }

    @Test func onlyThePreviewOfTheNewestEditDraws() {
        var flow = RetagFlow()
        let first = flow.changed()
        let second = flow.changed()
        #expect(!flow.due(first), "the debounce: a change since stops the older preview going out")
        #expect(flow.due(second))
        #expect(!Self.take(&flow) { $0.answered(first) }, "a preview sent before the fields changed again doesn't land")
        #expect(flow.planning)
        #expect(Self.take(&flow) { $0.answered(second) })
        #expect(!flow.planning && flow.current)
        // a failure of an old edit says nothing over the newer one
        let third = flow.changed()
        #expect(!Self.take(&flow) { $0.failed(second) })
        #expect(Self.take(&flow) { $0.failed(third) })
        #expect(!flow.planning, "a failed preview is said, not waited on")
        #expect(!flow.canApply(Self.plan))
    }

    @Test func noPreviewWhileATracklistLoadsOrOutOfReach() {
        var flow = RetagFlow()
        _ = flow.beginLoad()
        let edit = flow.changed()
        #expect(!flow.due(edit), "a preview of a release with no tracklist would say the opposite of Apply")
        #expect(Self.take(&flow) { $0.loadEnded($0.loads) })
        let landed = flow.changed()
        #expect(flow.due(landed))
        flow.wentAway()
        #expect(!flow.due(landed))
        #expect(!flow.planning, "out of reach: no spinner for a preview that can't go")
    }

    @Test func theDebounceIsTheWebs() {
        #expect(Retag.previewDebounceMs == 400)
    }

    // MARK: Apply's guard

    @Test func applyIsOnOnlyForACurrentPreviewThatChangesSomething() {
        var flow = Self.previewed()
        #expect(flow.canApply(Self.plan))
        #expect(!flow.canApply(nil))
        #expect(!flow.canApply(Self.empty), "Nothing to change: no Apply")
        // a warning is drawn, never a refusal - as the web's Apply
        let warned = RetagPlan(albumPath: "A/B", changedFileCount: 1, fileCount: 2, problems: ["2 files didn't match"])
        #expect(flow.canApply(warned))
        // a change since the preview
        flow.changed()
        #expect(!flow.canApply(Self.plan))
        #expect(Self.take(&flow) { $0.answered($0.edits) })
        #expect(Self.take(&flow) { $0.beginApply(Self.plan) })
        #expect(!flow.canApply(Self.plan), "nothing twice")
        #expect(!Self.take(&flow) { $0.beginApply(Self.plan) })
    }

    @Test func aRefusalKeepsThePreviewAndAnAnswerReadsTheFolderAgain() {
        var flow = Self.previewed()
        #expect(Self.take(&flow) { $0.beginApply(Self.plan) })
        flow.applyEnded(.refused)
        #expect(flow.canApply(Self.plan), "nothing was written: the preview still describes the folder")

        #expect(Self.take(&flow) { $0.beginApply(Self.plan) })
        flow.applyEnded(.applied)
        #expect(flow.needsRead && !flow.mayHaveFinished)
        #expect(!flow.canApply(Self.plan), "the preview before the apply no longer describes the folder")
        #expect(!flow.due(flow.edits), "no preview of the folder as it was before it is read again")
        flow.read()
        #expect(flow.due(flow.edits))
        #expect(!flow.canApply(Self.plan), "read again: Apply waits for the new preview")
        #expect(Self.take(&flow) { $0.answered($0.edits) })
        #expect(flow.canApply(Self.plan))
    }

    // MARK: the long wait

    @Test func anApplyThatNeverAnsweredIsSaidAndReadAgain() throws {
        var flow = Self.previewed()
        #expect(Self.take(&flow) { $0.beginApply(Self.plan) })
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        let none = APIFailure.NoAnswer(server: server, method: "POST", path: "/library/retag/apply", reason: "The request timed out.")
        #expect(RetagFlow.outcome(of: APIFailure.timeout(none)) == .unanswered)
        #expect(RetagFlow.outcome(of: APIFailure.offline(none)) == .unanswered)
        #expect(RetagFlow.outcome(of: APIFailure.other("lost")) == .unanswered)
        #expect(RetagFlow.outcome(of: URLError(.networkConnectionLost)) == .unanswered)
        let refused = APIFailure.answered(.init(status: 400, method: "POST", path: "/library/retag/apply",
                                                detail: "the folder has moved"))
        #expect(RetagFlow.outcome(of: refused) == .refused)

        flow.applyEnded(.unanswered)
        #expect(flow.mayHaveFinished && flow.needsRead)
        #expect(!flow.canApply(Self.plan), "never the same Apply on the old preview")
        #expect(Self.take(&flow) { $0.answered($0.edits) })
        #expect(!flow.canApply(Self.plan), "not before the folder is read again")
        flow.read()
        #expect(!flow.mayHaveFinished)
        #expect(Self.take(&flow) { $0.answered($0.edits) })
        #expect(flow.canApply(Self.plan))
        #expect(EditWords.mayHaveFinished == "deadwax may have finished this - looking again")
    }

    @Test func theAlbumIsFoundWhereTheApplyLeftIt() {
        let scan = ScanAnswer(albums: [ScanAlbum(path: "A/B [Deluxe]"), ScanAlbum(path: "C/D")])
        #expect(RetagFlow.whereAfter(scan, was: "C/D", target: "C/D [Deluxe]") == "C/D", "not moved: where it was")
        #expect(RetagFlow.whereAfter(scan, was: "A/B", target: "A/B [Deluxe]") == "A/B [Deluxe]", "the rename went through")
        #expect(RetagFlow.whereAfter(scan, was: "A/B", target: nil) == "A/B")
        #expect(RetagFlow.whereAfter(scan, was: "A/B", target: "E/F") == "A/B", "listed nowhere: said as not listed yet")
        let response = RetagResponse(plan: RetagPlan(targetPath: "A/B [Deluxe]"), results: RetagResults(movedTo: "/music/A/B [Deluxe]"))
        #expect(response.pathAfter("A/B", preview: nil) == "A/B [Deluxe]")
        #expect(RetagResponse(plan: RetagPlan(targetPath: "X"), results: RetagResults()).pathAfter("A/B", preview: nil) == "A/B")
    }

    @Test func theLongWaitIsSaidOnTheButton() {
        #expect(RetagWords.applying(nil) == "Applying")
        #expect(RetagWords.applying(RetagPlan(renameWait: 90, renameBy: "navidrome")) == "Applying, waiting for Navidrome")
        #expect(RetagWords.applying(RetagPlan(renameWait: 30, renameBy: "timer")) == "Applying, renaming in 30s")
        #expect(Routes.timeouts[Routes.retagApply] == 420, "past RENAME_WAIT_RANGE's 300 s and the cover's 45 s read")
    }

    // MARK: in and out of reach

    @Test func backInReachEverythingIsAskedAgainFirst() {
        var flow = Self.previewed()
        flow.wentAway()
        #expect(!flow.canApply(Self.plan), "out of reach: every write off")
        flow.cameBack()
        #expect(flow.needsRead)
        #expect(!flow.canApply(Self.plan), "never a write against an answer from before the gap")
        flow.read()
        #expect(Self.take(&flow) { $0.answered($0.edits) })
        #expect(flow.canApply(Self.plan))
        // coming back twice is once
        let edits = flow.edits
        flow.cameBack()
        #expect(flow.edits == edits && !flow.needsRead)
    }

    // MARK: the routes as the phone asks them

    @Test func theScanIsAskedWithoutItsTracksAndReadWithItsHeaders() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/albums", 200, #"""
            {"albums": [{"path": "A/B", "artist": "Portishead", "album": "Third", "year": "2008", "track_count": 11,
                         "issues": ["no_art"], "ignored_issues": [], "needs_attention": true, "tracks": [{"x": 1}]},
                        {"artist": "no path"}],
             "issue_types": {"no_art": {"label": "No cover", "hint": "Get one.", "severity": 1}, "odd": 3},
             "problem": null, "queue": {"count": 1}}
            """#, headers: ["ETag": "\"abc\"", "X-Scanned-At": "1763251200.5", "X-Scan-Stale": "0"])
        guard case .fresh(let answer, let etag) = try await deadwax.libraryScan(ifNoneMatch: nil) else {
            Issue.record("no answer"); return
        }
        #expect(transport.last?.url.query == "tracks=false")
        #expect(etag == "\"abc\"")
        #expect(answer.albums.map(\.path) == ["A/B"], "an album with no path is left out")
        #expect(answer.albums.first?.trackCount == 11)
        #expect(answer.issueTypes["no_art"]?.label == "No cover" && answer.issueTypes["odd"] == nil)
        #expect(answer.scannedAt == 1_763_251_200.5 && !answer.stale)
        #expect(Routes.timeouts[Routes.libraryAlbums] == 120)
        // the ETag sent back: a 304 is the answer kept
        transport.answer("/deadwax/library/albums", 304, "")
        guard case .unchanged = try await deadwax.libraryScan(ifNoneMatch: "\"abc\"") else {
            Issue.record("not unchanged"); return
        }
        #expect(transport.last?.headers["If-None-Match"] == "\"abc\"")
    }

    @Test func theSearchIsTheEditorsAndTheRetagIsOneBody() async throws {
        let (deadwax, transport) = client(session: "s")
        transport.answer("/deadwax/search_musicbrainz/fully_search", 200, #"{"release-groups": [{"id": "g", "title": "Third", "score": 100}]}"#)
        let found = try await deadwax.editorSearch(#"releasegroup:"Third" AND (artist:"Portishead" OR artistname:"Portishead")"#)
        #expect(found.releaseGroups.first?.score == 100)
        let asked = try #require(transport.last)
        let query = try #require(URLComponents(url: asked.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.map(\.name) == ["query", "limit", "releases"], "no `quick`: MusicBrainz's ten attempts, as the web's editor")
        #expect(query.first { $0.name == "limit" }?.value == "25")
        #expect(asked.timeout == Routes.editorSearchTimeout)

        transport.answer("/deadwax/search_musicbrainz/releases", 200, #"{"id": "g", "releases": [{"id": "r", "media": [{"track-count": 11}]}], "problem": null}"#)
        let pressings = try await deadwax.pressings(groupMbid: "g")
        #expect(transport.last?.url.query == "release_group_mbid=g&tracks=false")
        #expect(Retag.trackCount(pressings.releases[0]) == 11)

        let body = RetagRequestBody(albumPath: "A/B", release: Retag.payload(
            selected: nil, album: ScanAlbum(path: "A/B", artist: "Portishead", album: "Third"),
            fields: RetagFields(artist: "Portishead", album: "Third", year: "", originalYear: "", editionLabel: " ")), fetchArt: true)
        transport.answer("/deadwax/library/retag/preview", 200, #"""
            {"album_path": "A/B", "files": [{"filename": "01.flac", "matched": true, "track_title": "Silence",
             "changes": {"title": {"from": "", "to": "Silence"}, "album": {"from": "3", "to": "Third"}}}],
             "changed_file_count": 1, "file_count": 1, "art": {"action": "download", "reason": "", "existing": null},
             "problems": [], "empty": false, "rename_wait": 0, "rename_by": null, "moves": false}
            """#)
        let plan = try await deadwax.retagPreview(body)
        #expect(plan.files[0].changes.map(\.tag) == ["title", "album"], "the server's order, not sorted")
        let previewSent = try #require(transport.last)
        #expect(previewSent.headers["Origin"] == nil && previewSent.headers["Referer"] == nil, "the same-origin guard lets it by")
        let sent = try sentJSON(previewSent)
        #expect(Set(sent.keys) == ["album_path", "release", "fetch_art"])
        guard case .object(let release)? = sent["release"] else { Issue.record("no release"); return }
        #expect(Set(release.keys) == ["artist", "album", "year", "original_year", "release_mbid", "tracks", "edition_label"])
        #expect(release["edition_label"] == .null, "trimmed to nothing: null")

        transport.answer("/deadwax/library/retag/apply", 200, #"""
            {"plan": {"album_path": "A/B", "files": [{"filename": "01.flac", "changes": {"z": {"from": "", "to": "1"}, "a": {"from": "", "to": "2"}}}]},
             "results": {"tagged": 1, "failed": 0, "moved_to": null, "art_written": "cover.jpg", "problems": []}}
            """#)
        let applied = try await deadwax.retagApply(body)
        #expect(applied.plan.files[0].changes.map(\.tag) == ["z", "a"])
        #expect(RetagWords.applied(applied.results) == "Updated the tags in 1 file, saved cover.jpg.")
        #expect(try sentJSON(transport.last) == sent, "Apply sends the preview's very body; the server works it out again")
        #expect(transport.last?.timeout == 420)
    }

    @Test func theCoverAndTheMarksSendOnlyWhatTheServerDeclares() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/art/fetch", 200, #"{"written": "cover.jpg", "replaced": "cover.png"}"#)
        let fetched = try await deadwax.fetchCover(CoverFetchBody(albumPath: "A/B", replace: true, releaseMbid: nil))
        #expect(RetagWords.coverSaved(fetched) == "Saved cover.jpg, replacing cover.png.")
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B"), "replace": .bool(true), "release_mbid": .null])

        transport.answer("/deadwax/library/queue/ignore", 200, #"{"ignored": true, "album_path": "A/B", "issues": ["no_art"]}"#)
        #expect(try await deadwax.markFine(path: "A/B", issues: ["no_art"]).ignored)
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B"), "issues": .list([.string("no_art")])])
        transport.answer("/deadwax/library/queue/unignore", 200, #"{"ignored": false, "album_path": "A/B"}"#)
        #expect(try await !deadwax.askAgain(path: "A/B").ignored)
        #expect(try sentJSON(transport.last) == ["album_path": .string("A/B")])

        transport.answer("/deadwax/library/art", 404, #"{"detail": "no art for this album"}"#)
        #expect(try await deadwax.libraryArt(path: "A/B") == nil)
        #expect(transport.last?.url.query == "album=A/B")
    }

    // MARK: failures, as a managing page says them

    /// A refusal deadwax wrote words for is said as it came (the managing pages show deadwax's words), its why only
    /// for whoever runs deadwax; a 403 is NO_PERMISSION; nothing answering is a listener's line, the transport's
    /// words in brackets for whoever runs deadwax; MusicBrainz away is the editor's own sentence.
    @Test func failuresAreSaidAsAManagingPageSaysThem() throws {
        let refused = APIFailure.answered(.init(status: 400, method: "POST", path: "/library/retag/apply",
                                                detail: "the folder /music/A/B has moved", why: "renamed since the scan"))
        #expect(EditWords.said(refused, failed: RetagWords.applyFailed, admin: false) == "The folder /music/A/B has moved.")
        #expect(EditWords.said(refused, failed: RetagWords.applyFailed, admin: true)
                == "The folder /music/A/B has moved. (renamed since the scan)")
        let forbidden = APIFailure.answered(.init(status: 403, method: "POST", path: "/library/retag/apply",
                                                  detail: "This needs the edit permission"))
        #expect(EditWords.said(forbidden, failed: RetagWords.applyFailed, admin: true) == EditWords.noPermission)
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        let none = APIFailure.NoAnswer(server: server, method: "POST", path: "/library/retag/preview",
                                       reason: "The request timed out.")
        let listener = EditWords.said(APIFailure.timeout(none), failed: RetagWords.previewFailed, admin: false)
        #expect(!listener.contains("timed out.") && !listener.isEmpty, "a listener's words, not the transport's")
        #expect(EditWords.said(APIFailure.timeout(none), failed: RetagWords.previewFailed, admin: true)
                    .hasSuffix("(The request timed out.)"))
        let silent = APIFailure.answered(.init(status: 500, method: "POST", path: "/library/retag/preview"))
        #expect(!EditWords.said(silent, failed: RetagWords.previewFailed, admin: false).contains("500"))

        let away = APIFailure.answered(.init(status: 503, method: "GET", path: "/search_musicbrainz/fully_search",
                                             detail: "MusicBrainz is unreachable"))
        #expect(RetagWords.searchError(away, admin: true) == RetagWords.searchAway)
        #expect(RetagWords.tracklistError(away, admin: false) == RetagWords.tracklistAway)
        let bad = APIFailure.answered(.init(status: 400, method: "GET", path: "/search_musicbrainz/release",
                                            detail: "that isn't a MusicBrainz release id"))
        #expect(RetagWords.tracklistError(bad, admin: false) == "That isn't a MusicBrainz release id.")
        #expect(RetagWords.searchError(APIFailure.offline(none), admin: false).hasPrefix(ErrorWords.offline))
    }

    // MARK: the root's rows

    @Test func theRootsRowsSayWhatTheFolderHolds() {
        let full = ScanAlbum(path: "A/B", artist: "Portishead", album: "Dummy", edition: "Deluxe", art: "cover.jpg",
                             trackCount: 12, discCount: 2, formats: ["FLAC"], lyricsCount: 8, discArt: ["disc.png"])
        #expect(EditWords.artworkValue(full) == "Cover, CD art")
        #expect(EditWords.lyricsValue(full) == "8 of 12")
        #expect(EditWords.tracks(full.trackCount) == "12 tracks" && EditWords.tracks(1) == "1 track")
        #expect(EditWords.byline(full) == "Portishead · Deluxe")
        #expect(EditWords.facts(full) == "FLAC · 12 tracks · 2 discs")
        let bare = ScanAlbum(path: "C/D", trackCount: 1)
        #expect(EditWords.artworkValue(bare) == "No cover")
        #expect(EditWords.artworkValue(ScanAlbum(path: "E", discArt: ["disc1.jpg"])) == "CD art")
        #expect(EditWords.byline(bare).isEmpty && EditWords.facts(bare) == "1 track")
        #expect(EditWords.releaseValue(bare, pressing: nil) == EditWords.notMatched)
        #expect(EditWords.folderRow(full) == "Dummy, Portishead, A/B")
    }
}
