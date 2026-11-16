import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/care/care-vectors.json: the web's lib/needsLook.ts, lib/metadataQueue.ts and lib/permissions.ts run as they
/// are, and app/NeedsALook.tsx's, components/MetadataEditor.tsx's queue buttons', app/You.tsx's Manage row's,
/// app/useQueueSummary.ts's and app/App.tsx's own rules and words read out of their source - replayed here through
/// NeedsLook, MetadataQueue, NeedsLookWords, QueueCount and Managing, case for case
/// (notes/ios-specs/phase8-managing.md 5).
@Suite struct CareVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("care/care-vectors.json"))

    // MARK: reading the fixture

    static func albums(_ web: Web) -> [ScanAlbum] { web.list.map(EditVectorTests.scanAlbum) }
    static func strings(_ web: Web) -> [String] { web.list.compactMap(\.string) }

    /// Two lists of words the same, unit for unit (JavaScript's ===, not Swift's canonical equivalence).
    static func same(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { Screens.same($0, $1) }
    }

    static func same(_ a: String?, _ b: String?) -> Bool { Screens.same(a, b) }

    func types(_ name: Web) -> [String: MetadataIssueType] {
        EditVectorTests.decoded([String: MetadataIssueType].self, fixture["issueTypes"][name.string!])
    }

    static func facet(_ chip: NeedsLook.Facet, _ web: Web) -> Bool {
        same(chip.id, web["id"].string) && web["id"].isNull == (chip.id == nil) && same(chip.label, web["label"].string)
            && chip.count == web["count"].int && same(chip.hint, web["hint"].string)
    }

    /// A session as the fixture holds it: where it is, its facet, each row's path, album, listing, mark and whether a
    /// write was told of it.
    static func expect(_ session: NeedsLook.Session, _ web: Web, _ what: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(session.index == web["index"].int, "\(what): index", sourceLocation: sourceLocation)
        #expect(same(session.facet, web["facet"].string), "\(what): facet", sourceLocation: sourceLocation)
        let rows = web["rows"].list
        #expect(session.rows.count == rows.count, "\(what): rows", sourceLocation: sourceLocation)
        for (row, want) in zip(session.rows, rows) {
            #expect(same(row.path, want["path"].string), "\(what): a row's path", sourceLocation: sourceLocation)
            #expect(same(row.album.path, want["album"].string), "\(what): a row's album", sourceLocation: sourceLocation)
            #expect(same(row.listed.path, want["listed"].string), "\(what): a row's listing", sourceLocation: sourceLocation)
            #expect(row.mark?.rawValue == want["mark"].string, "\(what): \(row.path)'s mark", sourceLocation: sourceLocation)
            #expect(row.heard == want["heard"].bool, "\(what): \(row.path) heard", sourceLocation: sourceLocation)
        }
    }

    static func expect(_ ending: NeedsLook.Ending, _ web: Web, _ what: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let rows = web["rows"].list
        #expect(ending.rows.count == rows.count, "\(what): rows held", sourceLocation: sourceLocation)
        for (row, want) in zip(ending.rows, rows) {
            #expect(same(row.key, want["key"].string) && same(row.album.path, want["album"].string)
                    && row.mark?.rawValue == want["mark"].string, "\(what): a row held", sourceLocation: sourceLocation)
        }
        #expect(ending.chips.count == web["chips"].list.count
                && zip(ending.chips, web["chips"].list).allSatisfy { same($0.id, $1.string) }, "\(what): the facets held",
                sourceLocation: sourceLocation)
        #expect(same(ending.facet, web["facet"].string), "\(what): its facet", sourceLocation: sourceLocation)
        #expect(ending.read == web["read"].bool, "\(what): read", sourceLocation: sourceLocation)
    }

    // MARK: the fixture, the words

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-care-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/needsLook.ts", "ui/src/lib/metadataQueue.ts", "ui/src/lib/permissions.ts",
                                 "ui/src/app/NeedsALook.tsx the facets held", "ui/src/app/NeedsALook.tsx the rows",
                                 "ui/src/app/NeedsALook.tsx the ending held", "ui/src/app/NeedsALook.tsx a facet given up",
                                 "ui/src/components/MetadataEditor.tsx next album, when", "ui/src/app/You.tsx the count spoken",
                                 "ui/src/app/useQueueSummary.ts tracking", "ui/src/app/App.tsx who the page is for",
                                 "ui/src/lib/requestsView.ts badgeText", "ui/src/lib/libraryCare.ts READ_FAILED"])
        #expect(fixture["lists"].list.count == 77)
        #expect(fixture["sessions"].list.count == 90)
        #expect(fixture["pages"].list.count == 60)
        #expect(fixture["permissions"].list.count == 64)
        // the runs reach every kind of step and write
        let ops = fixture["sessions"].list.flatMap { $0["ops"].list }
        for kind in ["stay", "step", "end"] {
            #expect(ops.contains { $0["result"]["kind"].string == kind }, "a step that comes to \(kind)")
        }
        for kind in ["fix", "ignore", "partial", "unignore", "rename", "merge", "deleted", "lost", "review"] {
            #expect(ops.contains { $0["change"]["kind"].string == kind }, "a write: \(kind)")
        }
        #expect(ops.contains { $0["op"].string == "end" })
    }

    @Test func thePagesWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(Self.same(NeedsLook.title, words["title"].string))
        #expect(Self.same(NeedsLook.nothing, words["nothing"].string))
        #expect(Self.same(NeedsLook.reading, words["reading"].string))
        #expect(Self.same(NeedsLook.tryAgain, words["tryAgain"].string))
        #expect(Self.same(NeedsLook.show, words["show"].string))
        #expect(Self.same(NeedsLook.checking, words["checking"].string))
        #expect(Self.same(NeedsLook.newWord, words["newWord"].string))
        #expect(Self.same(NeedsLook.readFailed, words["readFailed"].string))
        #expect(Self.same(NeedsLook.checkFailed, words["checkFailed"].string))
        #expect(Self.same(NeedsLook.line, words["line"].string))
        #expect(Self.same(NeedsLook.lineNoEdit, words["lineNoEdit"].string))
        #expect(Self.same(NeedsLook.needsEdit, words["needsEdit"].string))
        #expect(Self.same(NeedsLook.ignoresUnsavedWords, words["ignoresUnsaved"].string))
        #expect(Self.same(NeedsLook.markedFine, words["markedFine"].string))
        #expect(Self.same(NeedsLook.RowMark.fixed.words, words["marks"]["fixed"].string))
        #expect(Self.same(NeedsLook.RowMark.ignored.words, words["marks"]["ignored"].string))
        #expect(Self.same(NeedsLook.RowMark.deleted.words, words["marks"]["deleted"].string))
        #expect(Self.same(NeedsLook.newFacet, words["newFacet"].string))
        #expect(Self.same(NeedsLook.ignoredFacet, words["ignoredFacet"].string))
        #expect(Self.same(NeedsLook.navidromeUnset, words["navidromeUnset"].string))
        #expect(Self.same(NeedsLook.navidromeScanning, words["navidromeScanning"].string))
        #expect(Self.same(NeedsLook.navidromeWaiting, words["navidromeWaiting"].string))
        #expect(Self.same(EditWords.noPermission, words["noPermission"].string))
        #expect(Self.same(ManagingWords.label(.queue), words["row"].string))
        // the editor's queue buttons: the web's words, its ▷ the phone's › (the bar's chevron, as Back's)
        #expect(Self.same(NeedsLookWords.previous, words["previous"].string))
        #expect(Self.same(NeedsLookWords.skipHint, words["skipHint"].string))
        let chevron = { (web: String?) in web?.replacingOccurrences(of: "\u{25B7}", with: "\u{203A}") }
        #expect(Self.same(NeedsLookWords.skip, chevron(words["skip"].string)))
        #expect(Self.same(NeedsLookWords.nextAlbum, chevron(words["nextAlbum"].string)))
        #expect(NeedsLookWords.skip.hasPrefix(NeedsLookWords.skipSpoken + " "))
        #expect(NeedsLookWords.nextAlbum.hasPrefix(NeedsLookWords.nextAlbumSpoken + " "))
    }

    // MARK: the list, its facets, its rows

    @Test func theListsAndTheirFacetsAreTheWebs() {
        for list in fixture["lists"].list {
            let name = list["name"].string!
            let albums = Self.albums(list["albums"])
            let issueTypes = types(list["types"])
            #expect(Self.same(MetadataQueue.queueAlbums(albums, nil).map(\.path), Self.strings(list["queue"])), "\(name): the queue")
            #expect(NeedsLook.summaryTotal(albums) == list["total"].int, "\(name): the total")
            let chips = NeedsLook.facets(albums, issueTypes)
            #expect(chips.count == list["chips"].list.count
                    && zip(chips, list["chips"].list).allSatisfy { Self.facet($0, $1) }, "\(name): the facets \(chips)")
            let drawn = NeedsLook.drawn(chips)
            #expect(drawn.count == list["drawn"].list.count
                    && zip(drawn, list["drawn"].list).allSatisfy { Self.same($0.id, $1.string) }, "\(name): the facets drawn")
            for each in list["facets"].list {
                let facet = each["facet"].string
                #expect(Self.same(NeedsLook.facetAlbums(albums, facet).map(\.path), Self.strings(each["albums"])),
                        "\(name): \(facet ?? "All")'s albums")
                #expect(Self.same(NeedsLook.facetShown(chips, facet), each["shown"].string), "\(name): \(facet ?? "All") shown")
            }
            for (album, row) in zip(albums, list["rows"].list) {
                #expect(Self.same(album.path, row["path"].string))
                #expect(MetadataQueue.isNewImport(album) == row["newImport"].bool, "\(album.path) new")
                #expect(NeedsLook.isIgnoredOnly(album) == row["ignoredOnly"].bool, "\(album.path) marked fine alone")
                #expect(Self.same(NeedsLook.title(album), row["title"].string), "\(album.path)'s title")
                #expect(Self.same(NeedsLook.byline(album), row["byline"].string), "\(album.path)'s byline")
                let drawnRow = NeedsLook.DrawnRow(key: album.path, album: album, mark: nil)
                for (key, pressed) in [("all", nil), ("ignored", NeedsLook.ignoredFacet), ("new", NeedsLook.newFacet)] as [(String, String?)] {
                    #expect(Self.same(NeedsLook.chipWords(drawnRow, pressed: pressed, issueTypes: issueTypes),
                                      Self.strings(row["chips"][key])), "\(album.path)'s words under \(key)")
                }
                #expect(Self.same(NeedsLook.markedFineTitle(album, issueTypes: issueTypes), row["markedFineTitle"].string),
                        "\(album.path)'s Marked fine title")
            }
        }
    }

    @Test func aRowsMarkIsTheWebs() {
        for pair in fixture["markPairs"].list {
            let listed = EditVectorTests.scanAlbum(pair["listed"]), after = EditVectorTests.scanAlbum(pair["after"])
            #expect(NeedsLook.markFor(listed: listed, after: after)?.rawValue == pair["mark"].string,
                    "\(listed.issues)/\(listed.ignoredIssues) -> \(after.issues)/\(after.ignoredIssues)")
        }
    }

    // MARK: sessions, step by step

    @Test func eachSessionRunsAsTheWebs() {
        for (number, run) in fixture["sessions"].list.enumerated() {
            let albums = Self.albums(run["albums"])
            let issueTypes = types(run["types"])
            let chips = NeedsLook.facets(albums, issueTypes)
            let facet = run["facet"].string
            let list = NeedsLook.facetAlbums(albums, facet)
            #expect(Self.same(list.map(\.path), Self.strings(run["list"])), "run \(number): the list")
            let begun = NeedsLook.startSession(list, path: run["start"].string!, facet: facet)
            guard var session = begun else {
                #expect(run["begun"].isNull, "run \(number): a session begun")
                continue
            }
            Self.expect(session, run["begun"], "run \(number) begun")
            for (at, op) in run["ops"].list.enumerated() {
                let what = "run \(number), op \(at) (\(op["op"].string ?? ""))"
                switch op["op"].string {
                case "change":
                    let change = op["change"]
                    let album = change["album"].isNull ? nil : EditVectorTests.scanAlbum(change["album"])
                    session = NeedsLook.rowChanged(session, NeedsLook.FolderChange(from: change["from"].string!, album: album,
                                                                                   deleted: change["deleted"].bool == true))
                    Self.expect(session, op["after"], "\(what) \(change["kind"].string ?? "")")
                case "step":
                    let absent = Self.strings(op["absent"])
                    let target = NeedsLook.stepTarget(session, to: op["index"].int!) { path in
                        !absent.contains { Screens.same($0, path) }
                    }
                    let result = op["result"]
                    switch target {
                    case .stay:
                        #expect(result["kind"].string == "stay", "\(what): stays")
                    case .end(let leaving):
                        #expect(result["kind"].string == "end", "\(what): ends")
                        #expect(Self.same(leaving, result["leaving"].string), "\(what): the album left")
                    case .step(let next, let leaving):
                        #expect(result["kind"].string == "step", "\(what): steps")
                        #expect(Self.same(leaving, result["leaving"].string), "\(what): the album left")
                        Self.expect(next, op["after"], what)
                        session = next
                    }
                case "ending", "end":
                    if op["op"].string == "end" {
                        #expect(Self.same(NeedsLook.leavingAtEnd(session), op["leaving"].string), "\(what): the album left")
                    }
                    let ending = NeedsLook.ending(session, held: op["held"].bool == true ? chips : nil,
                                                  live: NeedsLook.facets([], issueTypes))
                    Self.expect(ending, op["ending"], what)
                default:
                    Issue.record("\(what): an op the fixture doesn't know")
                }
            }
        }
    }

    // MARK: the page

    @Test func whatThePageHoldsShowsAndDrawsIsTheWebs() {
        for (number, page) in fixture["pages"].list.enumerated() {
            let what = "page \(number)"
            let albums = Self.albums(page["albums"]), other = Self.albums(page["other"])
            let issueTypes = types(page["types"])
            let liveChips = NeedsLook.facets(albums, issueTypes)
            let otherChips = NeedsLook.facets(other, issueTypes)
            let sessionList = NeedsLook.facetAlbums(other, nil)
            let session = page["session"].isNull ? nil
                : NeedsLook.startSession(sessionList, path: page["session"]["start"].string!, facet: page["session"]["facet"].string)
            #expect(page["session"].isNull == (session == nil), "\(what): the session")
            let held = page["held"].bool == true ? otherChips : nil
            let ending = page["ending"].isNull ? nil
                : NeedsLook.startSession(sessionList, path: sessionList[0].path, facet: page["ending"]["facet"].string)
                    .map { NeedsLook.ending($0, held: held, live: liveChips) }
            let chips = NeedsLook.chips(session: session, held: held, ending: ending, live: liveChips)
            #expect(chips.count == page["chips"].list.count && zip(chips, page["chips"].list).allSatisfy {
                Self.same($0.id, $1["id"].string) && $0.count == $1["count"].int
            }, "\(what): the facets")
            #expect(NeedsLook.drawn(chips).map(\.id).count == page["drawn"].list.count
                    && zip(NeedsLook.drawn(chips), page["drawn"].list).allSatisfy { Self.same($0.id, $1.string) },
                    "\(what): the facets drawn")
            let showing = NeedsLook.showing(session: session, live: liveChips, facet: page["facet"].string)
            #expect(Self.same(showing, page["showing"].string), "\(what): the facet shown")
            let listed = NeedsLook.facetAlbums(albums, showing)
            #expect(Self.same(listed.map(\.path), Self.strings(page["albumsListed"])), "\(what): the albums listed")
            let pressed = NeedsLook.pressed(session: session, ending: ending, showing: showing)
            #expect(Self.same(pressed, page["pressed"].string), "\(what): the facet pressed")
            let rows = NeedsLook.rows(session: session, ending: ending, albums: listed)
            #expect(rows.count == page["rows"].list.count, "\(what): the rows")
            for (row, want) in zip(rows, page["rows"].list) {
                #expect(Self.same(row.key, want["key"].string) && Self.same(row.album.path, want["album"].string)
                        && row.mark?.rawValue == want["mark"].string, "\(what): a row")
                #expect(Self.same(NeedsLook.chipWords(row, pressed: pressed, issueTypes: issueTypes), Self.strings(want["chips"])),
                        "\(what): \(row.key)'s words")
            }
        }
    }

    @Test func thePagesSmallRulesAreTheWebs() {
        for read in fixture["reads"].list {
            let (loaded, stale, loading, error) = (read["loaded"].bool!, read["stale"].bool!, read["loading"].bool!, read["error"].bool!)
            #expect(NeedsLook.real(loaded: loaded, stale: stale, failed: error) == read["real"].bool, "real \(read)")
            let checking = NeedsLook.status(failed: false, loaded: loaded, stale: stale, reading: loading, navidrome: nil) == .checking
            #expect(checking == read["checking"].bool, "checking \(read)")
        }
        for each in fixture["released"].list {
            let ending = each["ending"].isNull ? nil : NeedsLook.Ending(rows: [], chips: [], facet: nil, read: each["ending"].bool!)
            #expect(NeedsLook.released(ending, reading: each["loading"].bool!) == each["released"].bool, "released \(each)")
        }
        for each in fixture["givenUp"].list {
            #expect(NeedsLook.facetGivenUp(allowed: each["allowed"].bool!, shown: each["shown"].bool!, real: each["real"].bool!,
                                           session: each["session"].bool!, ending: each["ending"].bool!,
                                           facet: each["facet"].string, showing: each["showing"].string)
                    == each["givenUp"].bool, "given up \(each)")
        }
        for each in fixture["again"].list {
            #expect(NeedsLook.readsAgain(allowed: each["allowed"].bool!, shown: each["shown"].bool!, wasShown: each["wasShown"].bool!,
                                         loaded: each["loaded"].bool!, session: each["session"].bool!, ending: each["ending"].bool!)
                    == each["again"].bool, "again \(each)")
        }
        for each in fixture["states"].list {
            let state = NeedsLook.state(problem: each["problem"].string, loaded: each["loaded"].bool!, failed: each["error"].bool!,
                                        albums: each["albums"].int!)
            let name: String
            switch state {
            case .problem(let words):
                name = "problem"
                #expect(Self.same(words, each["problem"].string))
            case .reading: name = "reading"
            case .failed: name = "failed"
            case .list: name = "list"
            }
            #expect(name == each["state"].string, "state \(each)")
        }
        for each in fixture["statuses"].list {
            let status = NeedsLook.status(failed: each["error"].bool!, loaded: each["loaded"].bool!, stale: each["stale"].bool!,
                                          reading: each["loading"].bool!, navidrome: each["navidrome"].string)
            let name: String?
            switch status {
            case .failed: name = "failed"
            case .checking: name = "checking"
            case .navidrome(let words):
                name = "navidrome"
                #expect(Self.same(words, each["navidrome"].string))
            case nil: name = nil
            }
            #expect(name == each["status"].string, "status \(each)")
        }
        for each in fixture["leads"].list {
            let canEdit = each["canEdit"].bool!
            #expect(Self.same(NeedsLook.lead(canEdit: canEdit), each["line"].string))
            #expect(!canEdit == each["needsEdit"].bool, "NEEDS_EDIT said without Edit albums")
        }
        for each in fixture["unsaved"].list {
            #expect(NeedsLook.ignoresUnsaved(loaded: each["loaded"].bool!, reviewTracking: each["reviewTracking"].bool!,
                                             summaryTracking: each["summaryTracking"].bool) == each["warn"].bool, "unsaved \(each)")
        }
        for each in fixture["navidrome"].list {
            let check = each["check"].isNull ? nil : EditVectorTests.decoded(NavidromeCheck.self, each["check"])
            #expect(Self.same(NeedsLook.navidromeNote(check, detail: each["detail"].bool!), each["note"].string), "note \(each)")
        }
        for each in fixture["labels"].list {
            #expect(Self.same(NeedsLook.label(each["label"].string!, count: each["count"].int), each["text"].string), "label \(each)")
        }
    }

    // MARK: the editor in queue mode, the count, who

    @Test func theEditorsQueueButtonsAreTheWebs() {
        let album = ScanAlbum(path: "A/B")
        for nav in fixture["navs"].list {
            let total = nav["total"].int!, position = nav["position"].int!
            var rows = (0..<total).map { NeedsLook.SessionRow(path: "A/\($0)", album: album, listed: album) }
            rows[position - 1].heard = nav["applied"].bool!
            let made = NeedsLook.Nav(NeedsLook.Session(rows: rows, index: position - 1, facet: nil))
            #expect(made.position == position && made.total == total)
            #expect(made.place == "\(position) of \(total)")
            #expect(made.back == nav["back"].bool, "back \(nav)")
            #expect(made.on == nav["on"].bool, "on \(nav)")
            #expect(made.nextAlbum == nav["nextAlbum"].bool, "next album \(nav)")
            #expect(made.forward == (made.nextAlbum ? NeedsLookWords.nextAlbum : NeedsLookWords.skip))
        }
    }

    @Test func theCountIsTheWebs() {
        for each in fixture["counts"].list {
            let summary = EditVectorTests.decoded(QueueSummary.self, each["answer"])
            var count = QueueCount()
            let asked = count.ask(allowed: true)
            let more = count.answered(summary)
            #expect(asked && !more)
            if let total = each["total"].int { #expect(count.server == total, "total \(each)") }
            #expect(count.tracking == each["tracking"].bool, "tracking \(each)")
            #expect(Self.same(count.value, each["value"].string), "value \(each)")
            #expect(Self.same(count.spoken, each["spoken"].string), "spoken \(each)")
        }
        let unknown = QueueCount()
        #expect(Self.same(unknown.value, fixture["unknown"]["value"].string))
        #expect(Self.same(unknown.spoken, fixture["unknown"]["spoken"].string))
    }

    @Test func whoThePageAndTheCountAreForIsTheWebs() {
        for each in fixture["permissions"].list {
            let permissions = Set(Self.strings(each["permissions"]).compactMap(Access.Permission.init(rawValue:)))
            #expect(permissions.count == each["permissions"].list.count)
            #expect(Managing.asksQueueSummary(permissions) == each["asks"].bool, "asks \(each)")
            #expect(Managing.parts(permissions).queue == each["queue"].bool, "the row \(each)")
            let page = Managing.needsLook(permissions)
            #expect(page.allowed == each["allowed"].bool && page.canEdit == each["canEdit"].bool, "the page \(each)")
        }
    }
}
