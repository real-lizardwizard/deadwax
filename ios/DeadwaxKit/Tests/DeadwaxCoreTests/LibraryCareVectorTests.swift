import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/care/library-care-vectors.json: the web's lib/libraryCare.ts, lib/bulkTargets.ts, lib/myLibrary.ts,
/// lib/permissions.ts and lib/format.ts run as they are, and app/LibraryCare.tsx's, app/useLibraryCare.ts's and
/// app/HeldByNobody.tsx's own rules and words read out of their source - replayed here through BulkTargets, LibraryCare,
/// CareRuns, Managing.careParts and Held, case for case (notes/ios-specs/phase8-managing.md 6).
@Suite struct LibraryCareVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("care/library-care-vectors.json"))

    static func same(_ a: String?, _ b: String?) -> Bool { Screens.same(a, b) }

    static func same(_ a: [String], _ b: [Web]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { Screens.same($0, $1.string) }
    }

    var libraries: [[ScanAlbum]] {
        fixture["libraries"].list.map { $0.list.map(EditVectorTests.scanAlbum) }
    }

    static func kind(_ web: Web) -> BulkTargets.Kind { BulkTargets.Kind(rawValue: web.string!)! }

    static func run(_ web: Web) -> BulkTargets.Run { EditVectorTests.decoded(BulkTargets.Run.self, web) }

    static func outcome(_ web: Web) -> BulkTargets.Outcome { EditVectorTests.decoded(BulkTargets.Outcome.self, web) }

    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    static let noAnswer = APIFailure.offline(.init(server: server, method: "POST", path: "/library/art/fetch", reason: "offline"))

    static func refusal(_ status: Int) -> APIFailure {
        .answered(.init(status: status, method: "POST", path: "/library/art/fetch"))
    }

    // MARK: the fixture, the words

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-library-care-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/libraryCare.ts", "ui/src/lib/bulkTargets.ts", "ui/src/lib/myLibrary.ts",
                                 "ui/src/lib/permissions.ts", "ui/src/lib/format.ts", "ui/src/lib/groupAlbums.ts",
                                 "ui/src/lib/typedMatch.ts", "ui/src/app/LibraryCare.tsx a scan to trust",
                                 "ui/src/app/LibraryCare.tsx a kind's albums", "ui/src/app/LibraryCare.tsx Stop, its words",
                                 "ui/src/app/LibraryCare.tsx the facts", "ui/src/app/LibraryCare.tsx the state",
                                 "ui/src/app/useLibraryCare.ts a picture's step, failed", "ui/src/app/useLibraryCare.ts lyrics' step",
                                 "ui/src/app/useLibraryCare.ts a run that wrote, behind",
                                 "ui/src/app/HeldByNobody.tsx what a write says", "ui/src/app/HeldByNobody.tsx a flag's name"])
        #expect(fixture["libraries"].list.count == 12)
        #expect(fixture["runs"].list.count == 30)
        #expect(fixture["pages"].list.count == 60)
        #expect(fixture["permissions"].list.count == 64)
    }

    @Test func thePageSaysWhatTheWebSays() {
        let words = fixture["words"]
        #expect(Self.same(LibraryCare.title, words["title"].string))
        #expect(Self.same(ManagingWords.label(.care), words["title"].string))
        #expect(Self.same(LibraryCare.reading, words["reading"].string))
        #expect(Self.same(LibraryCare.tryAgain, words["tryAgain"].string))
        #expect(Self.same(LibraryCare.rescanTitle, words["rescanTitle"].string))
        #expect(Self.same(LibraryCare.rescan, words["rescan"].string))
        #expect(Self.same(LibraryCare.rescanning, words["rescanning"].string))
        #expect(Self.same(LibraryCare.runsTitle, words["runsTitle"].string))
        #expect(Self.same(LibraryCare.narrowTo, words["narrowTo"].string))
        #expect(Self.same(LibraryCare.narrowPrompt, words["narrowPrompt"].string))
        #expect(Self.same(LibraryCare.checking, words["checking"].string))
        #expect(Self.same(LibraryCare.readFailed, words["readFailed"].string))
        #expect(Self.same(LibraryCare.checkFailed, words["checkFailed"].string))
        #expect(Self.same(LibraryCare.rereadFailed, words["rereadFailed"].string))
        #expect(Self.same(LibraryCare.careLineAll, words["careLine"].string))
        #expect(Self.same(LibraryCare.rescanWords, words["rescanWords"].string))
        #expect(Self.same(EditWords.noPermission, words["noPermission"].string))
        #expect(BulkTargets.kinds.map(\.rawValue) == words["kinds"].list.compactMap(\.string))
        for kind in BulkTargets.kinds {
            #expect(Self.same(LibraryCare.label(kind), words["labels"][kind.rawValue].string))
            #expect(Self.same(LibraryCare.heading(kind), words["titles"][kind.rawValue].string))
        }
        #expect(Self.same(Held.title, words["heldTitle"].string))
        #expect(Self.same(Held.loading, words["heldLoading"].string))
        #expect(Self.same(Held.readFailed, words["heldFailed"].string))
        #expect(Self.same(Held.flagged, words["flagged"].string))
        #expect(Self.same(Held.addForThem, words["addForThem"].string))
        #expect(Self.same(Held.dismiss, words["dismiss"].string))
        #expect(Self.same(Held.addFailed, words["addFailed"].string))
        #expect(Self.same(Held.dismissFailed, words["dismissFailed"].string))
        #expect(Held.shown == words["heldShown"].int)
        // NeedsLook's READ_FAILED and CHECK_FAILED are libraryCare.ts's too
        #expect(Self.same(NeedsLook.readFailed, words["readFailed"].string))
        #expect(Self.same(NeedsLook.checkFailed, words["checkFailed"].string))
    }

    // MARK: narrowing, plans, targets

    @Test func narrowingAndTheScopeAreTheWebs() {
        let libraries = libraries
        for each in fixture["narrows"].list {
            let albums = libraries[each["library"].int!]
            let typed = each["typed"].string!
            let inScope = LibraryCare.narrow(albums, typed)
            #expect(Self.same(inScope.map(\.path), each["inScope"].list), "narrow \(Screens.spelled(typed))")
            #expect(Self.same(LibraryCare.scopeWords(typed), each["scopeWords"].string), "scopeWords \(Screens.spelled(typed))")
            #expect(Self.same(LibraryCare.scopeLine(inScope: inScope.count, all: albums.count, typed: typed),
                              each["scopeLine"].string), "scopeLine \(Screens.spelled(typed))")
        }
    }

    @Test func plansAreTheWebs() {
        for each in fixture["plans"].list {
            let words = LibraryCare.planWords(Self.kind(each["kind"]), count: each["count"].int!, typed: each["typed"].string!)
            #expect(Self.same(words, each["words"].string), "\(each)")
        }
    }

    @Test func eachKindTakesTheAlbumsTheWebsTakes() {
        let libraries = libraries
        for each in fixture["targets"].list {
            let albums = libraries[each["library"].int!]
            for kind in BulkTargets.kinds {
                #expect(Self.same(BulkTargets.targets(kind, albums).map(\.path), each[kind.rawValue].list),
                        "\(kind) of library \(each["library"])")
            }
        }
        for each in fixture["ownDisc"].list {
            let names = each["names"].list.compactMap(\.string)
            #expect(BulkTargets.hasOwnDiscArt(names) == each["own"].bool, "\(each["names"])")
        }
    }

    // MARK: the scan's facts

    @Test func theTotalsAndTheAgeAreTheWebs() {
        let libraries = libraries
        for each in fixture["totals"].list {
            #expect(Self.same(LibraryCare.scanTotals(libraries[each["library"].int!]), each["words"].string), "\(each)")
        }
        for each in fixture["ages"].list {
            let scan = each["scan"]
            let words = LibraryCare.scanAge(loaded: scan["loaded"].bool!, stale: scan["stale"].bool!, loading: scan["loading"].bool!,
                                            scannedAt: scan["scannedAt"].num, scanSeconds: scan["scanSeconds"].num!,
                                            rescanning: each["rescanning"].bool!, now: each["now"].num!)
            #expect(Self.same(words, each["words"].string), "\(each)")
        }
        for each in fixture["formatAges"].list {
            #expect(Self.same(LibraryCare.formatAge(each["unix"].num, now: each["now"].num!), each["words"].string), "\(each)")
        }
        for each in fixture["sizes"].list {
            #expect(Self.same(Sources.size(each["bytes"].num!), each["words"].string), "\(each)")
        }
        for each in fixture["careLines"].list {
            #expect(Self.same(LibraryCare.careLine(rescan: each["rescan"].bool!, bulk: each["bulk"].bool!), each["words"].string))
        }
    }

    // MARK: runs

    @Test func summariesAreTheWebs() {
        for each in fixture["summaries"].list {
            let words = BulkTargets.summary(Self.kind(each["kind"]), Self.run(each["run"]))
            #expect(Self.same(words, each["words"].string), "\(each)")
        }
    }

    /// Each run through runBulk replayed through CareRuns: started over albums every kind takes, Stop pressed before the
    /// album runBulk was stopped before, each album's outcome told - a throw as an album that never answered (the web
    /// counts it failed, `failedAs`; the phone counts it so too, and holds the kind behind: it may have written).
    @Test func runsGoAsTheWebsGo() {
        for each in fixture["runs"].list {
            let kind = Self.kind(each["kind"])
            let albums = each["tracks"].list.enumerated().map { (at: Int, tracks: Web) -> ScanAlbum in
                ScanAlbum(path: "album \(at)", releaseMbid: "mbid", trackCount: tracks.int!)
            }
            let outcomes = each["outcomes"].list
            let progress = each["progress"].list
            let stopBefore = each["stopBefore"].int
            var runs = CareRuns()
            runs.readLanded(runs.readBegan())
            let got1 = runs.start(kind, albums, allowed: true, online: true)
            #expect(got1, "\(each)")
            #expect(runs.run(kind) == Self.run(progress[0]))
            var asked = 0
            var threw = false
            loop: while true {
                if asked == stopBefore { runs.stop(kind) }
                asked += 1
                switch runs.next(allowed: true, online: true) {
                case .album(let album):
                    let at = albums.firstIndex(of: album)!
                    let step: BulkTargets.Step
                    if outcomes[at].string == "throw" {
                        step = BulkTargets.step(kind, album, failure: Self.noAnswer)
                        threw = true
                    } else {
                        step = .answered(Self.outcome(outcomes[at]))
                    }
                    let told = runs.finished(step)
                    if case .answered(let outcome) = step { #expect(told == (outcome.written > 0)) } else { #expect(told) }
                    #expect(runs.run(kind) == Self.run(progress[at + 1]), "\(each) after \(at)")
                case .ended(let ended):
                    #expect(ended == kind)
                    break loop
                case .nothing:
                    Issue.record("a run under way always has an album or an end")
                    break loop
                }
            }
            #expect(runs.under == nil)
            #expect(runs.run(kind) == Self.run(each["final"]), "\(each)")
            #expect(runs.run(kind) == Self.run(progress[progress.count - 1]))
            #expect(Self.same(runs.result(kind), each["summary"].string), "\(each)")
            #expect(Self.same(runs.result(kind), each["result"].string))
            #expect((runs.behind[kind] != nil) == (each["behind"].bool! || threw), "\(each)")
        }
    }

    @Test func eachStepCountsAsTheWebsCounts() {
        let album = ScanAlbum(path: "Björk/Post (1995)", releaseMbid: "mbid", trackCount: 11)
        for each in fixture["steps"].list {
            if each["kind"].string == "picture" {
                let failure = each["status"].int.map(Self.refusal) ?? Self.noAnswer
                let expected = Self.outcome(each["outcome"])
                for kind in [BulkTargets.Kind.covers, .disc] {
                    let step = BulkTargets.step(kind, album, failure: failure)
                    // counted as the web counts it; a 403 the phone's own step (it stops the run), the count the same
                    if each["status"].int == 403 {
                        #expect(step == .forbidden(expected), "\(each)")
                    } else if let status = each["status"].int, status < 500 {
                        #expect(step == .answered(expected), "\(each)")
                    } else {
                        #expect(step == .unanswered(expected), "\(each)")
                    }
                }
            } else {
                let summary = EditVectorTests.decoded(LyricsSummary.self, each["summary"])
                #expect(BulkTargets.outcome(summary) == Self.outcome(each["outcome"]), "\(each)")
            }
        }
        for each in fixture["failedAs"].list {
            let tracks = each["tracks"].int!
            #expect(BulkTargets.failedAs(Self.kind(each["kind"]), ScanAlbum(path: "a", trackCount: tracks)) == each["failed"].int)
            // lyrics that never answered: every track failed, as runBulk's failedAs counts it
            if each["kind"].string == "lyrics" {
                #expect(BulkTargets.step(.lyrics, ScanAlbum(path: "a", trackCount: tracks), failure: Self.refusal(404))
                        == .answered(BulkTargets.Outcome(failed: tracks)))
            }
        }
    }

    // MARK: the page

    @Test func thePageDrawsWhatTheWebsDraws() {
        let libraries = libraries
        for each in fixture["pages"].list {
            let library = each["library"]
            let albums = libraries[library["albums"].int!]
            let loaded = library["loaded"].bool!, stale = library["stale"].bool!, loading = library["loading"].bool!
            let rescanning = each["rescanning"].bool!
            let typed = each["care"]["narrow"].string!
            let real = LibraryCare.real(loaded: loaded, stale: stale)
            #expect(real == each["real"].bool, "\(each)")
            #expect(LibraryCare.busy(rescanning: rescanning, reading: loading, stale: stale) == each["busy"].bool)
            let state = NeedsLook.state(problem: library["problem"].string, loaded: loaded, failed: !library["error"].isNull,
                                        albums: albums.count)
            let named: String
            switch state {
            case .problem: named = "problem"
            case .reading: named = "reading"
            case .failed: named = "failed"
            case .list: named = "list"
            }
            #expect(named == each["state"].string, "\(each)")
            let facts = LibraryCare.facts(albums, loaded: loaded, stale: stale, loading: loading,
                                          scannedAt: library["scannedAt"].num, scanSeconds: library["scanSeconds"].num!,
                                          rescanning: rescanning, now: each["now"].num!)
            #expect(Self.same(facts, each["facts"].string), "\(each)")
            let inScope = LibraryCare.narrow(albums, typed)
            #expect(Self.same(inScope.map(\.path), each["inScope"].list))
            #expect(Self.same(LibraryCare.scopeNote(real: real, inScope: inScope.count, all: albums.count, typed: typed),
                              each["scopeNote"].string))
            for kind in BulkTargets.kinds {
                let drawn = each["kinds"][kind.rawValue]
                let targets = LibraryCare.targets(kind, real: real, behind: each["care"]["behind"][kind.rawValue].bool!,
                                                  inScope: inScope)
                if drawn["targets"].isNull {
                    #expect(targets == nil, "\(kind) of \(each)")
                } else {
                    #expect(Self.same(targets?.map(\.path) ?? [], drawn["targets"].list), "\(kind) of \(each)")
                }
                #expect(Self.same(LibraryCare.note(kind, targets: targets, typed: typed), drawn["note"].string))
                let run = drawn["run"].isNull ? nil : Self.run(drawn["run"])
                let stop = run.flatMap { $0.running ? LibraryCare.stopLabel($0, stopping: drawn["stopping"].bool!) : nil }
                #expect(Self.same(stop, drawn["stop"].string), "\(kind) of \(each)")
                let start = run?.running != true ? targets.flatMap { $0.isEmpty ? nil : LibraryCare.startLabel(kind, count: $0.count) } : nil
                #expect(Self.same(start, drawn["start"].string), "\(kind) of \(each)")
                let result = run.map { $0.running ? "" : BulkTargets.summary(kind, $0) } ?? ""
                #expect(Self.same(result, drawn["result"].string))
            }
        }
    }

    @Test func eachPersonSeesTheirParts() {
        for each in fixture["permissions"].list {
            let permissions = Set(each["permissions"].list.compactMap(\.string).compactMap(Access.Permission.init(rawValue:)))
            #expect(permissions.count == each["permissions"].list.count)
            let parts = Managing.careParts(permissions)
            #expect(parts == EditVectorTests.decoded(Managing.CareParts.self, each["parts"]), "\(each)")
            #expect(parts.shown == each["shown"].bool)
            #expect(Managing.parts(permissions).care == each["care"].bool)
            #expect(Managing.heldShown(loginsOn: true, parts: parts) == each["heldOn"].bool)
            #expect(Managing.heldShown(loginsOn: false, parts: parts) == each["heldOff"].bool)
            #expect(each["heldNone"].bool == false)
        }
    }

    // MARK: In nobody's library

    @Test func inNobodysLibrarySaysWhatTheWebSays() {
        let held = fixture["held"][0]
        for each in held["lines"].list {
            #expect(Self.same(Held.line(each["count"].int!), each["words"].string))
        }
        for each in held["flags"].list {
            if each["flag"].isNull {
                #expect(Self.same(Held.saidName(nil), each["said"].string))
                continue
            }
            let flag = EditVectorTests.decoded(Held.Flag.self, each["flag"])
            #expect(Self.same(Held.flagWords(flag), each["words"].string), "\(each)")
            #expect(Self.same(Held.flagName(flag), each["name"].string), "\(each)")
            #expect(Self.same(Held.saidName(flag), each["said"].string))
        }
        for each in held["albums"].list {
            let album = Held.UnheldAlbum(id: 1, path: "a", artist: each["artist"].string!, album: each["album"].string!)
            #expect(Self.same(Held.albumName(album), each["name"].string))
        }
        for each in held["said"].list {
            let users = each["users"].list.compactMap(\.string)
            let name = each["name"].string!
            let words = each["how"].string == "add" ? Held.added(name, users: users) : Held.dismissed(name)
            #expect(Self.same(words, each["words"].string), "\(each)")
        }
        for each in held["show"].list {
            #expect(Self.same(Held.showLabel(all: each["all"].bool!, count: each["count"].int!), each["words"].string))
        }
    }
}
