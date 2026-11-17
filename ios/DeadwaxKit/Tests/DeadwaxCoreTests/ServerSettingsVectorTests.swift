import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/server/server-vectors.json: the web's lib/serverSettings.ts, lib/musicbrainzAnswers.ts, lib/lyrics.ts,
/// lib/errorWords.ts and lib/permissions.ts run as they are, and app/ServerSettings.tsx's, components/SettingsView.tsx's,
/// components/RetimeLyrics.tsx's, components/MusicBrainzAnswers.tsx's, app/You.tsx's, app/App.tsx's and app/access.ts's
/// own rules and words read out of their source - replayed here through ServerSettings, SavedAnswers, RetimeRun and
/// Connections, case for case (notes/ios-specs/phase8-managing.md 7). Every answer is read as the phone reads deadwax's:
/// from its body, with ServerSettingsAnswer.read.
@Suite struct ServerSettingsVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("server/server-vectors.json"))

    static func same(_ a: String?, _ b: String?) -> Bool { Screens.same(a, b) }

    /// Each answer as deadwax sends it, read as the phone reads it.
    var answers: [ServerSettingsAnswer] {
        fixture["answers"].list.map { try! ServerSettingsAnswer.read(Data($0.string!.utf8)) }
    }

    /// Drafts as the web's object held them - its order kept, a revert its null.
    static func drafts(_ web: Web) -> ServerSettings.Drafts {
        ServerSettings.Drafts(web.list.map { pair in
            (pair[0].string!, pair[1].isNull ? ServerSettings.Drafts.Value.revert : .text(pair[1].string!))
        })
    }

    static func pairs(_ drafts: ServerSettings.Drafts) -> String {
        drafts.entries.map { entry in
            switch entry.value {
            case .text(let text): return "\(entry.key)=\(Screens.spelled(text))"
            case .revert: return "\(entry.key)=null"
            }
        }.joined(separator: ", ")
    }

    static func pairs(_ web: Web) -> String {
        pairs(drafts(web))
    }

    /// An error as the fixture describes it, made as the app meets it.
    static func failure(_ spec: Web) -> APIFailure {
        screenFailure(spec, path: spec["path"].string ?? "/settings", method: spec["method"].string ?? "PUT")
    }

    // MARK: the fixture, the words

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-server-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/serverSettings.ts", "ui/src/lib/musicbrainzAnswers.ts", "ui/src/lib/lyrics.ts",
                                 "ui/src/lib/errorWords.ts", "ui/src/lib/permissions.ts",
                                 "ui/src/app/ServerSettings.tsx a save's refusal", "ui/src/app/ServerSettings.tsx the bar's words",
                                 "ui/src/app/ServerSettings.tsx the page's line", "ui/src/app/App.tsx who opens the page",
                                 "ui/src/app/App.tsx a save asks Navidrome again", "ui/src/components/SettingsView.tsx a row's value",
                                 "ui/src/components/SettingsView.tsx a row's source", "ui/src/components/RetimeLyrics.tsx the note",
                                 "ui/src/components/RetimeLyrics.tsx the running words",
                                 "ui/src/components/MusicBrainzAnswers.tsx Clear's title", "ui/src/components/MusicBrainzAnswers.tsx the line",
                                 "ui/src/app/You.tsx a ping as a row", "ui/src/app/You.tsx Navidrome's status as a row",
                                 "ui/src/app/access.ts who runs deadwax"])
        #expect(fixture["answers"].list.count == 52)
        #expect(fixture["pages"].list.count == 41)
        #expect(fixture["runs"].list.count == 30)
        #expect(fixture["permissions"].list.count == 65)
    }

    @Test func thePageSaysWhatTheWebSays() {
        let words = fixture["words"]
        let diffs = ScreenDiffs()
        diffs.text("title", ServerSettings.title, words["title"])
        diffs.text("manage's row", ManagingWords.label(.settings), words["title"])
        diffs.text("reading", ServerSettings.reading, words["reading"])
        diffs.text("readFailed", ServerSettings.readFailed, words["readFailed"])
        diffs.text("rereadFailed", ServerSettings.rereadFailed, words["rereadFailed"])
        diffs.text("saveFailed", ServerSettings.saveFailed, words["saveFailed"])
        diffs.text("tryAgain", ServerSettings.tryAgain, words["tryAgain"])
        diffs.text("discard", ServerSettings.discard, words["discard"])
        diffs.text("save", ServerSettings.save, words["save"])
        diffs.text("saving", ServerSettings.saving, words["saving"])
        diffs.text("locked", ServerSettings.locked, words["locked"])
        diffs.text("unsaved", ServerSettings.unsavedBadge, words["unsaved"])
        diffs.text("needsAttention", ServerSettings.needsAttention, words["needsAttention"])
        diffs.text("setHere", ServerSettings.setHere, words["setHere"])
        diffs.text("revert", ServerSettings.revertLabel, words["revert"])
        diffs.text("willRevert", ServerSettings.willRevert, words["willRevert"])
        diffs.text("organizingOn", ServerSettings.organizingOn, words["organizingOn"])
        diffs.text("organizingOff", ServerSettings.organizingOff, words["organizingOff"])
        diffs.text("savedAnswersGroup", ServerSettings.savedAnswersGroup, words["savedAnswersGroup"])
        diffs.text("savedAnswersPath", ServerSettings.savedAnswersPath, words["savedAnswersPath"])
        for (at, tab) in ServerSettings.tabs.enumerated() {
            diffs.text("tab \(at)", tab.rawValue, words["tabs"][at]["id"])
            diffs.text("tab \(at) label", ServerSettings.label(tab), words["tabs"][at]["label"])
            diffs.text("tab \(at) hint", ServerSettings.hint(tab), words["tabs"][at]["hint"])
        }
        diffs.check("tabs", ServerSettings.tabs.count, words["tabs"].list.count)
        // Re-time saved lyrics
        diffs.text("retimeButton", RetimeRun.button, words["retimeButton"])
        diffs.text("retimeReading", RetimeRun.readingLibrary, words["retimeReading"])
        diffs.text("retimeSaveFirstHint", RetimeRun.saveFirstHint, words["retimeSaveFirstHint"])
        diffs.text("retimeHint", RetimeRun.hint, words["retimeHint"])
        diffs.text("retimeReadFailed", RetimeRun.readFailed, words["retimeReadFailed"])
        diffs.text("retimeSaveFirst", RetimeRun.saveFirst, words["retimeSaveFirst"])
        diffs.text("retimePrompt", RetimeRun.prompt, words["retimePrompt"])
        // MusicBrainz's saved answers
        diffs.text("clear", SavedAnswers.clear, words["clear"])
        diffs.text("clearing", SavedAnswers.clearingLabel, words["clearing"])
        diffs.text("answersReading", SavedAnswers.readingLine, words["answersReading"])
        diffs.text("answersSaveFirst", SavedAnswers.saveFirst, words["answersSaveFirst"])
        diffs.text("answersReadFailed", SavedAnswers.readFailed, words["answersReadFailed"])
        diffs.text("answersClearFailed", SavedAnswers.clearFailed, words["answersClearFailed"])
        diffs.text("clearSaveFirstHint", SavedAnswers.saveFirstHint, words["clearSaveFirstHint"])
        diffs.text("clearClearingHint", SavedAnswers.clearingHint, words["clearClearingHint"])
        diffs.text("clearEmptyHint", SavedAnswers.emptyHint, words["clearEmptyHint"])
        diffs.text("clearHint", SavedAnswers.clearHint, words["clearHint"])
        // Connections
        diffs.text("connections", Connections.title, words["connections"])
        diffs.text("checkAgain", Connections.checkAgain, words["checkAgain"])
        diffs.text("connected", Connections.connected, words["connected"])
        diffs.text("pingUnanswered", ErrorWords.pingUnanswered, words["pingUnanswered"])
        diffs.text("pending", Connections.pending.text, words["pending"]["text"])
        diffs.text("pending state", Connections.pending.state.rawValue, words["pending"]["state"])
        for (at, service) in Connections.Service.allCases.enumerated() {
            diffs.text("service \(at)", service.rawValue, words["services"][at]["id"])
            diffs.text("service \(at) label", service.label, words["services"][at]["label"])
        }
        diffs.done()
    }

    /// The page's line is the web's - your own choices in Settings on both since the web's 2.1.35 (the phone said
    /// Settings from 16 Nov while the web said You).
    @Test func thePagesLineIsTheWebs() throws {
        let web = try #require(fixture["words"]["pageLine"].string)
        #expect(Self.same(ServerSettings.pageLine, web))
    }

    // MARK: the answer, and its choices' order

    @Test func choicesAreInTheOrderObjectEntriesListsThem() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["orders"].list.enumerated() {
            let answer = try! ServerSettingsAnswer.read(Data(row["body"].string!.utf8))
            let choices = answer.groups.first?.settings.first?.choices ?? []
            diffs.check("order \(at) count", choices.count, row["choices"].list.count)
            for (place, (choice, web)) in zip(choices, row["choices"].list).enumerated() {
                diffs.text("order \(at).\(place) value", choice.value, web[0])
                diffs.text("order \(at).\(place) label", choice.label, web[1])
            }
        }
        diffs.done()
    }

    @Test func eachGroupSitsOnTheWebsTab() {
        let diffs = ScreenDiffs()
        for row in fixture["groupTabs"].list {
            diffs.text("group \(row["id"])", ServerSettings.tab(forGroup: row["id"].string!).rawValue, row["tab"])
        }
        diffs.done()
    }

    // MARK: the pages: marks, rows, keys, the verdict

    @Test func everyPagesMarksAndRowsAreTheWebs() {
        let answers = self.answers
        let diffs = ScreenDiffs()
        for (at, page) in fixture["pages"].list.enumerated() {
            let answer = page["answer"].int.map { answers[$0] }
            let drafts = Self.drafts(page["drafts"])
            let marks = ServerSettings.tabMarks(answer, drafts)
            for tab in ServerSettings.Tab.allCases {
                diffs.text("page \(at) mark \(tab)", marks[tab]?.rawValue, page["marks"][tab.rawValue])
            }
            diffs.check("page \(at) marked tabs", marks.count, page["marks"].keys.count)
            let settings = answer?.settings ?? []
            diffs.check("page \(at) rows", settings.count, page["rows"].list.count)
            for (setting, web) in zip(settings, page["rows"].list) {
                let row = ServerSettings.row(setting, answer, drafts)
                let label = "page \(at) \(setting.key)"
                diffs.text("\(label) key", row.key, web["key"])
                let control: String
                switch row.control {
                case .locked: control = "locked"
                case .choices: control = "choices"
                case .field(let secret): control = secret ? "secret" : "text"
                }
                diffs.text("\(label) control", control, web["control"])
                diffs.text("\(label) value", row.value, web["value"])
                diffs.text("\(label) placeholder", row.placeholder, web["placeholder"])
                diffs.text("\(label) source", row.source, web["source"])
                diffs.flag("\(label) unsaved", row.unsaved, web["unsaved"])
                diffs.flag("\(label) attention", row.attention, web["attention"])
                diffs.text("\(label) effect", row.effect, web["effect"])
                diffs.text("\(label) locked", row.locked, web["locked"])
                diffs.text("\(label) revert", row.revert, web["revert"])
                diffs.flag("\(label) reverting", row.reverting, web["reverting"])
                diffs.text("\(label) note", row.note, web["note"])
                diffs.text("\(label) detail", row.detail, web["detail"])
            }
            for (group, web) in zip(answer?.groups ?? [], page["groups"].list) {
                diffs.text("page \(at) group \(group.id)", ServerSettings.tab(forGroup: group.id).rawValue, web["tab"])
            }
            for (group, web) in zip(answer?.groups ?? [], page["savedKeys"].list) {
                diffs.text("page \(at) key \(group.id)", SavedAnswers.key(group), web)
            }
            if let answer {
                diffs.text("page \(at) verdict", ServerSettings.verdict(answer.organizing), page["verdict"])
            }
        }
        diffs.done()
    }

    @Test func theSecretsNoteIsTheWebs() {
        let answers = self.answers
        let diffs = ScreenDiffs()
        for (at, row) in fixture["retype"].list.enumerated() {
            let answer = answers[row["answer"].int!]
            diffs.text("note \(at) \(row["key"]) [\(Self.pairs(row["drafts"]))]",
                       ServerSettings.retypeNote(row["key"].string!, answer, Self.drafts(row["drafts"])), row["note"])
        }
        diffs.done()
    }

    // MARK: the drafts

    @Test func anEditIsTheWebsDraftInTheWebsOrder() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["edited"].list.enumerated() {
            let committed = row["committed"].isNull ? nil
                : ServerSetting(key: row["committed"]["key"].string!, value: row["committed"]["value"].string,
                                secret: row["committed"]["secret"].bool!)
            let after = ServerSettings.edited(Self.drafts(row["current"]), key: row["key"].string!,
                                              value: row["value"].string!, committed: committed)
            diffs.check("edit \(at)", Self.pairs(after), Self.pairs(row["result"]))
        }
        diffs.done()
    }

    @Test func aSaveLeavesWhatTheWebLeaves() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["afterSave"].list.enumerated() {
            let left = ServerSettings.afterSave(Self.drafts(row["current"]), sent: Self.drafts(row["sent"]))
            diffs.check("save \(at)", Self.pairs(left), Self.pairs(row["left"]))
        }
        diffs.done()
    }

    @Test func theBarAndASavesRefusalSayWhatTheWebSays() {
        let diffs = ScreenDiffs()
        for row in fixture["bars"].list {
            diffs.text("bar \(row["saveError"]) \(row["justSaved"]) \(row["dirty"])",
                       ServerSettings.barText(saveError: row["saveError"].string, justSaved: row["justSaved"].bool!,
                                              dirty: row["dirty"].int!), row["text"])
        }
        for row in fixture["saveErrors"].list {
            diffs.text("save failed \(row["error"]) admin \(row["admin"])",
                       ServerSettings.saveFailure(Self.failure(row["error"]), admin: row["admin"].bool!), row["said"])
        }
        for row in fixture["readErrors"].list {
            let error = Self.failure(row["error"])
            let admin = row["admin"].bool!
            diffs.text("read failed \(row["error"]) admin \(admin)", ServerSettings.readFailure(error, admin: admin, first: true), row["first"])
            diffs.text("read again failed \(row["error"]) admin \(admin)", ServerSettings.readFailure(error, admin: admin, first: false), row["again"])
        }
        for row in fixture["navidromeKeys"].list {
            diffs.flag("asks Navidrome \(row["keys"])", ServerSettings.asksNavidromeAgain(row["keys"].list.map { $0.string! }), row["asks"])
        }
        diffs.done()
        // the phone's own: a 403 is a Managing page's words
        let forbidden = APIFailure.answered(.init(status: 403, method: "PUT", path: "/settings", detail: "That needs Settings."))
        #expect(ServerSettings.saveFailure(forbidden, admin: true) == EditWords.noPermission)
    }

    // MARK: MusicBrainz's saved answers

    static func stats(_ web: Web) -> SavedAnswersStats? {
        web.isNull ? nil : EditVectorTests.decoded(SavedAnswersStats.self, web)
    }

    @Test func theSavedAnswersLineAndClearAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["bytes"].list {
            diffs.text("bytes \(row["bytes"])", SavedAnswers.describeBytes(row["bytes"].num!), row["words"])
        }
        for row in fixture["saved"].list {
            diffs.text("saved \(row["stats"]) cleared \(row["cleared"])",
                       SavedAnswers.describe(Self.stats(row["stats"])!, cleared: row["cleared"].bool!), row["words"])
        }
        for (at, row) in fixture["clears"].list.enumerated() {
            let unsaved = row["unsaved"].bool!
            let state = SavedAnswers(stats: Self.stats(row["stats"]), error: row["error"].string,
                                     clearing: row["clearing"].bool!, cleared: row["cleared"].bool!)
            diffs.flag("clear \(at) empty", state.empty, row["empty"])
            diffs.flag("clear \(at) refused", state.refused(unsaved: unsaved), row["refused"])
            diffs.text("clear \(at) hint", state.hint(unsaved: unsaved), row["hint"])
            diffs.text("clear \(at) label", state.label, row["label"])
            diffs.text("clear \(at) line", state.line(unsaved: unsaved), row["note"])
        }
        diffs.done()
    }

    // MARK: Re-time saved lyrics

    @Test func reTimesWordsAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["retimes"].list {
            let t = row["totals"]
            let totals = RetimeRun.Totals(retimed: t["retimed"].int!, unchanged: t["unchanged"].int!, custom: t["custom"].int!,
                                          failed: t["failed"].int!)
            diffs.text("retime \(t)", RetimeRun.describe(totals), row["words"])
        }
        for row in fixture["labels"].list {
            diffs.text("label \(row["done"]) of \(row["total"])",
                       RetimeRun.runningLabel(done: row["done"].int!, total: row["total"].int!), row["label"])
        }
        for row in fixture["notes"].list {
            let run = row["run"]
            let ended: (totals: RetimeRun.Totals, done: Int, total: Int)? = run.isNull || run["running"].bool == true ? nil
                : (RetimeRun.Totals(retimed: run["retimed"].int!, unchanged: run["unchanged"].int!, custom: run["custom"].int!,
                                    failed: run["failed"].int!), run["done"].int!, run["total"].int!)
            diffs.text("note \(row["unsaved"]) \(run)",
                       RetimeRun.note(unsaved: row["unsaved"].bool!, error: run["error"].string, ended: ended), row["note"])
        }
        diffs.done()
    }

    /// A run stepped album by album as the web's module steps it: Stop pressed before an album, an album that threw (a
    /// refusal - one that never answered is counted the same, and says more: RetimeRunTests), a new lead drafted while it
    /// ran.
    @Test func aRunStepsAndEndsAsTheWebsDoes() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["runs"].list.enumerated() {
            var run = RetimeRun()
            let ticket = run.start(allowed: true, online: true, unsaved: false)!
            let library = row["library"].list.map { album in
                ScanAlbum(path: album["path"].string!, lyricsCount: album["lyrics_count"].int!)
            }
            run.read(ticket, library)
            if row["leadMoved"].bool == true { run.leadDrafted() }
            var steps = row["steps"].list.makeIterator()
            loop: while true {
                if let stop = row["stopBefore"].int, stop == run.done { run.stopPressed() }
                switch run.next(allowed: true, online: true) {
                case .album:
                    let step = steps.next()!
                    if step.string == "threw" {
                        run.finished(.refused)
                    } else {
                        run.finished(.answered(RetimeSummary(retimed: step["retimed"].int!, unchanged: step["unchanged"].int!,
                                                             custom: step["custom"].int!, failed: step["failed"].int!)))
                    }
                case .ended, .nothing:
                    break loop
                }
            }
            let web = row["run"]
            if web.isNull {
                diffs.check("run \(at) let go", run.phase, .idle)
            } else {
                diffs.check("run \(at) ended", run.phase, .ended)
                diffs.check("run \(at) retimed", run.totals.retimed, web["retimed"].int!)
                diffs.check("run \(at) unchanged", run.totals.unchanged, web["unchanged"].int!)
                diffs.check("run \(at) custom", run.totals.custom, web["custom"].int!)
                diffs.check("run \(at) failed", run.totals.failed, web["failed"].int!)
                diffs.check("run \(at) done", run.done, web["done"].int!)
                diffs.check("run \(at) total", run.total, web["total"].int!)
            }
            diffs.text("run \(at) note", run.note(unsaved: false), row["note"])
        }
        diffs.done()
    }

    // MARK: Connections

    @Test func connectionsRowsAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["pings"].list {
            let service = ErrorWords.Ping(rawValue: row["service"].string!)!
            let answer = EditVectorTests.decoded(PingAnswer.self, row["answer"])
            let check = Connections.fromPing(service, answer)
            let label = "\(service) \(row["answer"])"
            diffs.text("\(label) state", check.state.rawValue, row["check"]["state"])
            diffs.text("\(label) text", check.text, row["check"]["text"])
            diffs.text("\(label) detail", check.detail, row["check"]["detail"])
        }
        for row in fixture["navidrome"].list {
            let check = Connections.fromNavidrome(EditVectorTests.decoded(NavidromeStatus.self, row["status"]))
            let label = "navidrome \(row["status"])"
            diffs.text("\(label) state", check.state.rawValue, row["check"]["state"])
            diffs.text("\(label) text", check.text, row["check"]["text"])
            diffs.text("\(label) detail", check.detail, row["check"]["detail"])
        }
        for row in fixture["unanswered"].list {
            let check = Connections.unanswered(Self.failure(row["error"]))
            diffs.text("unanswered \(row["error"]) state", check.state.rawValue, row["check"]["state"])
            diffs.text("unanswered \(row["error"]) text", check.text, row["check"]["text"])
            diffs.text("unanswered \(row["error"]) detail", check.detail, row["check"]["detail"])
        }
        diffs.done()
    }

    // MARK: who may

    @Test func whoSeesThePageAndConnectionsIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["permissions"].list {
            let named = Set(row["permissions"].list.compactMap { Access.Permission(rawValue: $0.string!) })
            let admin = row["admin"].bool!
            let access = Access(user: "ethan", permissions: named, on: true, unverified: false, admin: admin)
            let parts = ServerSettings.parts(access)
            let label = "\(row["permissions"]) admin \(admin)"
            diffs.flag("\(label) page", parts.page, row["allowed"])
            diffs.flag("\(label) seesDetail", access.seesDetail, row["seesDetail"])
            // Connections sit on the page: shown to whoever runs deadwax, which everyone the page opens for is
            diffs.check("\(label) connections", parts.connections, row["allowed"].bool! && row["seesDetail"].bool!)
            diffs.check("\(label) connections whenever the page", parts.connections, parts.page)
            diffs.check("\(label) answers", parts.answers, parts.page)
            // the phone's own: Re-time with Edit albums too, the permission of the route it asks
            diffs.check("\(label) retime", parts.retime, parts.page && named.contains(.edit))
        }
        diffs.done()
    }
}
