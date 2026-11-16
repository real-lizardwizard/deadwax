import Foundation
import Testing
@testable import DeadwaxCore

/// Needs a look (Phase 8, slice 6 - phase8-managing.md 5): what the vectors can't reach - the two routes as the web asks
/// them, the scan's fields the page reads, the count's one request in flight, a session told as a person works through
/// it, and the phone's own words (a menu where the web has chips, a toolbar where it has the editor's footer).
@Suite struct NeedsLookTests {
    static func album(_ path: String, issues: [String] = [], ignored: [String] = [], imported: Bool = false,
                      reviewed: Bool = false, severity: Int = 0, artist: String = "Tame Impala", name: String = "Currents")
        -> ScanAlbum {
        let outstanding = issues.filter { !ignored.contains($0) }
        return ScanAlbum(path: path, artist: artist, album: name, issues: issues, ignoredIssues: ignored,
                         needsAttention: !outstanding.isEmpty, imported: imported, reviewed: reviewed, severity: severity)
    }

    // MARK: the routes

    @Test func theCountAndALookAreAskedAsTheWebAsksThem() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/library/queue/summary", 200,
                         #"{"known": true, "needs_attention": 2, "new_imports": 1, "total": 3, "unscanned_imports": 0, "tracking_enabled": true}"#)
        let summary = try await deadwax.queueSummary()
        #expect(summary == QueueSummary(known: true, needsAttention: 2, newImports: 1, total: 3))
        #expect(transport.last?.method == "GET" && transport.last?.url.query == nil)
        #expect(transport.last?.timeout == 30)

        transport.answer("/deadwax/library/queue/reviewed", 200, #"{"reviewed": true, "album_path": "Tame Impala/Currents"}"#)
        let noted = try await deadwax.markReviewed(path: "Tame Impala/Currents")
        #expect(noted == QueueReviewed(reviewed: true, albumPath: "Tame Impala/Currents"))
        #expect(transport.last?.method == "POST")
        #expect(try sentJSON(transport.last) == ["album_path": .string("Tame Impala/Currents")], "no issues: a look isn't an ignore")
        #expect(transport.last?.timeout == 20)
        #expect(transport.last?.headers["Origin"] == nil && transport.last?.headers["Referer"] == nil)

        // with no job store deadwax refuses to note it - a 5xx, which the page leaves unsaid, as the web's does
        transport.answer("/deadwax/library/queue/reviewed", 503, #"{"detail": "the job store isn't available"}"#)
        await #expect(throws: APIFailure.self) { try await deadwax.markReviewed(path: "A/B") }
        // without Look after the library the count is a 403 - which is why it is never asked without it
        transport.answer("/deadwax/library/queue/summary", 403, #"{"detail": "needs Look after the library"}"#)
        do {
            _ = try await deadwax.queueSummary()
            Issue.record("a 403 is thrown")
        } catch {
            #expect(EditWords.said(error, failed: "", admin: false) == EditWords.noPermission)
        }
    }

    @Test func theCountsAnswerIsReadLoosely() throws {
        let read = { (json: String) in try JSONDecoder().decode(QueueSummary.self, from: Data(json.utf8)) }
        // no LIBRARY_PATH, or no store: zeros, known false - still an answer
        #expect(try read(#"{"known": false, "needs_attention": 0, "new_imports": 0, "total": 0, "unscanned_imports": 0, "tracking_enabled": false}"#)
                == QueueSummary(known: false, total: 0, trackingEnabled: false))
        // an older deadwax without tracking_enabled can keep them (the web's `!== false`)
        #expect(try read(#"{"total": 4}"#).trackingEnabled)
        #expect(try read(#"{"total": "four", "tracking_enabled": "no"}"#) == QueueSummary(known: false, total: 0))
    }

    @Test func theScanCarriesWhatThePageReads() throws {
        let answer = try JSONDecoder().decode(ScanAnswer.self, from: Data(#"""
        {"albums": [{"path": "Tame Impala/Currents", "artist": "Tame Impala", "album": "Currents", "severity": 3,
                     "disc_label": "Disc 2", "issues": ["no_release"], "ignored_issues": [], "needs_attention": true,
                     "imported": true, "reviewed": false},
                    {"path": "A/B", "severity": "high", "disc_label": 7}],
         "issue_types": {"no_release": {"label": "Not matched to MusicBrainz", "hint": "Find it.", "severity": 3}},
         "review_tracking_enabled": false,
         "navidrome_check": {"state": "failed", "problem": "Navidrome answered 401"}}
        """#.utf8))
        #expect(answer.albums.map(\.severity) == [3, 0] && answer.albums.map(\.discLabel) == ["Disc 2", ""])
        #expect(!answer.reviewTracking)
        #expect(answer.navidromeCheck == NavidromeCheck(state: "failed", problem: "Navidrome answered 401"))
        let older = try JSONDecoder().decode(ScanAnswer.self, from: Data(#"{"albums": [], "navidrome_check": 3}"#.utf8))
        #expect(older.reviewTracking && older.navidromeCheck == nil, "an answer without them: tracked, nothing to say")
        #expect(NeedsLook.navidromeNote(answer.navidromeCheck, detail: true) == "Couldn't ask Navidrome which albums it has: Navidrome answered 401")
        #expect(NeedsLook.navidromeNote(answer.navidromeCheck, detail: false)
                == "Couldn't ask Navidrome which albums it has - try again in a minute.", "deadwax's own words only for whoever runs it")
    }

    // MARK: the count

    @Test func theCountAsksOneAtATimeAndKeepsItsLastNumber() {
        var count = QueueCount()
        #expect(count.server == nil && count.value == "" && count.spoken == "Needs a look", "nothing drawn over a count nobody knows")
        var went = count.ask(allowed: false)
        #expect(!went && !count.asking, "never asked without Look after the library")
        went = count.ask(allowed: true)
        #expect(went && count.asking)
        went = count.ask(allowed: true)
        #expect(!went && count.again, "asked again while one is out: one more, after it")
        went = count.ask(allowed: true)
        #expect(!went, "and only one more")
        went = count.answered(QueueSummary(total: 3))
        #expect(went, "the one asked meanwhile goes now")
        #expect(count.server == 3 && count.value == "3" && count.spoken == "Needs a look, 3 albums")
        #expect(count.asking && !count.again)
        went = count.failed()
        #expect(!went, "a failure: nothing more to ask")
        #expect(count.server == 3 && !count.asking, "a failure keeps the last number")
        for (summary, value, spoken) in [(QueueSummary(total: 1, trackingEnabled: false), "1", "Needs a look, 1 album"),
                                         (QueueSummary(total: 0), "", "Needs a look"),
                                         (QueueSummary(total: 140), "99+", "Needs a look, 140 albums")] {
            went = count.ask(allowed: true)
            #expect(went)
            went = count.answered(summary)
            #expect(!went)
            #expect(count.value == value && count.spoken == spoken, "\(summary.total): none draws nothing, past 99 99+")
            #expect(count.tracking == summary.trackingEnabled)
        }
    }

    // MARK: a session, as a person works through it

    @Test func aSessionHoldsItsRowsStillAndMarksWhatBecameOfThem() throws {
        let albums = [
            Self.album("Tame Impala/Currents", issues: ["no_art"], severity: 1),
            Self.album("Beach House/Bloom", imported: true, artist: "Beach House", name: "Bloom"),
            Self.album("ABBA/Arrival", issues: ["no_release", "no_year"], severity: 3, artist: "ABBA", name: "Arrival"),
            Self.album("Nobody/Quiet", issues: ["no_art"], ignored: ["no_art"], artist: "Nobody", name: "Quiet"),
        ]
        let list = NeedsLook.facetAlbums(albums, nil)
        #expect(list.map(\.path) == ["Beach House/Bloom", "ABBA/Arrival", "Tame Impala/Currents"],
                "new first, worst next; an album marked fine is out")
        var session = try #require(NeedsLook.startSession(list, path: "ABBA/Arrival", facet: nil))
        var nav = NeedsLook.Nav(session)
        #expect(nav.place == "2 of 3" && nav.back && nav.on && nav.forward == "Skip \u{203A}")

        // Apply renamed it and fixed it: the row follows the folder, keeps its key, says Fixed - and Skip becomes Next
        let fixed = Self.album("ABBA/Arrival (1976)", artist: "ABBA", name: "Arrival")
        session = NeedsLook.rowChanged(session, .init(from: "ABBA/Arrival", album: fixed))
        #expect(session.current?.path == "ABBA/Arrival (1976)" && session.current?.mark == .fixed)
        nav = NeedsLook.Nav(session)
        #expect(nav.nextAlbum && nav.forward == "Next album \u{203A}" && nav.forwardSpoken == "Next album")
        let rows = NeedsLook.sessionRows(session)
        #expect(rows.map(\.key) == list.map(\.path), "keyed as listed: nothing moves under the finger")
        #expect(NeedsLook.chipWords(rows[1], pressed: nil, issueTypes: [:]) == ["Fixed"])
        #expect(NeedsLookWords.row(rows[1], chips: ["Fixed"], current: true) == "Arrival, ABBA, Fixed, Open")

        // Next: the album left is the renamed one, marked reviewed by its new path
        guard case .step(let next, let leaving) = NeedsLook.stepTarget(session, to: 2, present: { _ in true }) else {
            Issue.record("a step")
            return
        }
        #expect(leaving == "ABBA/Arrival (1976)")
        session = next
        #expect(NeedsLook.Nav(session).place == "3 of 3" && !NeedsLook.Nav(session).on)
        // deleted here: it stays in its row saying so, and stepping off it marks nothing
        session = NeedsLook.rowChanged(session, .init(from: "Tame Impala/Currents", album: nil, deleted: true))
        #expect(session.current?.mark == .deleted)
        #expect(!NeedsLook.Nav(session).nextAlbum, "the last keeps Skip, off")
        guard case .step(let back, let left) = NeedsLook.stepTarget(session, to: 1, present: { _ in true }) else {
            Issue.record("a step back")
            return
        }
        #expect(left == nil, "a deleted album is never marked reviewed")
        // to an album gone from the scan (deleted outside): the session ends, the one left marked
        let gone = NeedsLook.stepTarget(back, to: 0, present: { $0 != "Beach House/Bloom" })
        #expect(gone == .end(leaving: "ABBA/Arrival (1976)"))
        // a step to the row it is on, or past either end, does nothing
        #expect(NeedsLook.stepTarget(back, to: 1, present: { _ in true }) == .stay)
        #expect(NeedsLook.stepTarget(back, to: 3, present: { _ in true }) == .stay)
        #expect(NeedsLook.stepTarget(back, to: -1, present: { _ in true }) == .stay)
        #expect(NeedsLook.leavingAtEnd(back) == "ABBA/Arrival (1976)")

        // the end: its rows held, as they were, until a fresh read lands
        let ending = NeedsLook.ending(back, held: nil, live: NeedsLook.facets(albums, [:]))
        #expect(ending.rows.map(\.mark) == [nil, .fixed, .deleted] && !ending.read)
        #expect(!NeedsLook.released(ending, reading: false), "its own read hasn't answered")
        var read = ending
        read.read = true
        #expect(!NeedsLook.released(read, reading: true) && NeedsLook.released(read, reading: false))
    }

    // MARK: the phone's own words

    @Test func theShowMenuAndTheToolbarSayItPlainly() {
        let all = NeedsLook.Facet(id: nil, label: "All", count: 12)
        let new = NeedsLook.Facet(id: NeedsLook.newFacet, label: "Newly added", count: 1)
        #expect(NeedsLookWords.facet(all) == "All 12" && NeedsLookWords.facet(new) == "Newly added 1")
        #expect(NeedsLookWords.facetSpoken(all) == "All, 12 albums" && NeedsLookWords.facetSpoken(new) == "Newly added, 1 album")
        #expect(NeedsLookWords.header(new) == "Newly added \u{b7} 1" && NeedsLookWords.header(nil) == "Show")
        #expect(NeedsLookWords.showSpoken(nil) == "Show, All" && NeedsLookWords.showSpoken(new) == "Show, Newly added")
        #expect(NeedsLookWords.showSymbol(narrowed: false) == "line.3.horizontal.decrease.circle")
        #expect(NeedsLookWords.showSymbol(narrowed: true) == "line.3.horizontal.decrease.circle.fill")
        let session = NeedsLook.Session(rows: [Self.album("A/1"), Self.album("A/2")].map {
            NeedsLook.SessionRow(path: $0.path, album: $0, listed: $0)
        }, index: 1, facet: nil)
        #expect(NeedsLookWords.stepped(NeedsLook.Nav(session), album: "Currents") == "2 of 2: Currents")
        #expect(NeedsLook.folder(session) == "A/2")
        // a row with no album name reads its folder; with no artist, its edition alone
        let bare = ScanAlbum(path: "Untitled/[1]", edition: "Deluxe")
        #expect(NeedsLook.title(bare) == "Untitled/[1]" && NeedsLook.byline(bare) == "Deluxe")
        #expect(NeedsLookWords.row(NeedsLook.DrawnRow(key: bare.path, album: bare, mark: nil), chips: [], current: false)
                == "Untitled/[1], Deluxe")
        // the header's chip: the one pressed, All's for none, nothing for a facet not among them
        #expect(NeedsLook.chip([all, new], pressed: nil) == all && NeedsLook.chip([all, new], pressed: "new") == new)
        #expect(NeedsLook.chip([all], pressed: "missing_cover") == nil && NeedsLook.chip([new], pressed: nil) == nil)
    }

    @Test func aStepFindsItsAlbumCodeUnitByCodeUnit() {
        // the web's Set.has: "Beyonc\u{e9}" precomposed isn't the same path as "Beyonce\u{301}" decomposed, though a
        // Swift String's == says it is
        let lists = NeedsLook.lists([Self.album("Beyonc\u{e9}/Lemonade")])
        #expect(lists("Beyonc\u{e9}/Lemonade"))
        #expect(!lists("Beyonce\u{301}/Lemonade"))
        #expect(!lists("Beyonc\u{e9}/Lemonade/"))
    }

    @Test func thePageIsLookAfterTheLibrarysAndFixingItEditAlbums() {
        // every set of permissions: the page and the count with Look after the library, fixing with Edit albums
        for bits in 0..<64 {
            let permissions = Set(Access.Permission.allCases.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
            let page = Managing.needsLook(permissions)
            #expect(page.allowed == permissions.contains(.library))
            #expect(page.canEdit == permissions.contains(.edit))
            #expect(Managing.asksQueueSummary(permissions) == page.allowed)
            #expect(Managing.parts(permissions).queue == page.allowed, "the row and the page agree")
            #expect(NeedsLook.lead(canEdit: page.canEdit) == (page.canEdit ? NeedsLook.line : NeedsLook.lineNoEdit))
        }
    }
}
