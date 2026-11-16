import Foundation
import Testing
@testable import DeadwaxCore

/// Server settings' own rules on the phone (notes/ios-specs/phase8-managing.md 7; notes/ios.md "Server settings on the
/// phone") - what the web has no counterpart for, or what its vectors can't reach: each group's mark, a menu's value
/// that isn't a choice, the batch as it is sent, a save that never answered, the page's reads and Save's gate, Clear's
/// tickets, Re-time's stops, the waits and who may. The web's own rules are ServerSettingsVectorTests'.
@Suite struct ServerSettingsTests {
    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()

    static func setting(_ key: String, _ value: String? = nil, status: String = "ok", secret: Bool = false,
                        overridden: Bool = false, choices: [ServerSettings.Choice]? = nil) -> ServerSetting {
        ServerSetting(key: key, value: value, status: status, secret: secret, overridden: overridden, choices: choices)
    }

    static func answer(organizing: Organizing = Organizing(enabled: true), _ groups: [(String, [ServerSetting])])
        -> ServerSettingsAnswer {
        ServerSettingsAnswer(groups: groups.map { ServerSettingGroup(id: $0.0, settings: $0.1) }, organizing: organizing)
    }

    static let sample = answer([
        ("connections", [setting("NAVIDROME_URL", "http://navidrome:4533"), setting("NAVIDROME_PASSWORD", "set", secret: true)]),
        ("paths", [setting("LIBRARY_PATH", "/music")]),
        ("organizing", [setting("ALBUM_FOLDER_TEMPLATE", "{album}")]),
        ("lyrics", [setting("LYRICS_LEAD_MS", "250", overridden: true)]),
    ])

    static let refused = APIFailure.answered(.init(status: 400, method: "PUT", path: "/settings",
                                                   detail: "LIBRARY_PATH: not a directory"))
    static let unreached = APIFailure.offline(.init(server: server, method: "PUT", path: "/settings", reason: "offline"))

    // MARK: the marks

    @Test func eachGroupIsMarkedByTheWebsRuleTakenPerGroup() {
        var drafts = ServerSettings.Drafts()
        #expect(ServerSettings.groupMarks(Self.sample, drafts).isEmpty)
        drafts.set("LIBRARY_PATH", .text("/x"))
        drafts.set("NOT_A_SETTING", .text("y"))
        #expect(ServerSettings.groupMarks(Self.sample, drafts) == ["paths": .unsaved], "a draft of no setting marks no group")
        let broken = Self.answer(organizing: Organizing(enabled: false, blockers: ["LIBRARY_PATH is not set"]), [
            ("connections", [Self.setting("SLSKD_URL", status: "error")]),
            ("paths", [Self.setting("LIBRARY_PATH")]),
            ("organizing", [Self.setting("ALBUM_FOLDER_TEMPLATE")]),
        ])
        var both = ServerSettings.Drafts()
        both.set("SLSKD_URL", .text("http://x"))
        both.set("ALBUM_FOLDER_TEMPLATE", .revert)
        both.set("LIBRARY_PATH", .text("/y"))
        // attention wins over unsaved; organizing blocked marks the verdict's own group
        #expect(ServerSettings.groupMarks(broken, both)
                == ["connections": .attention, "organizing": .attention, "paths": .unsaved])
        // organizing blocked with no blockers to say: no mark (the web's tabMarks needs both)
        let quiet = Self.answer(organizing: Organizing(enabled: false), [("organizing", [Self.setting("A")])])
        #expect(ServerSettings.groupMarks(quiet, .init()).isEmpty)
        #expect(ServerSettings.markWords(.attention) == "Needs attention" && ServerSettings.markWords(.unsaved) == "Unsaved")
    }

    @Test func theRootsSectionsAreTheTabsInOrderEachWithItsGroups() {
        let answer = Self.answer([("lyrics", []), ("connections", []), ("soulseek", []), ("experiments", []),
                                  ("musicbrainz-cache", []), ("logins", [])])
        let sections = ServerSettings.sections(answer)
        #expect(sections.map(\.tab) == [.library, .downloads, .connections])
        #expect(sections[0].groups.map(\.id) == ["lyrics", "experiments"])
        #expect(sections[2].groups.map(\.id) == ["connections", "musicbrainz-cache", "logins"])
        #expect(ServerSettings.sections(Self.answer([("paths", [])])).map(\.tab) == [.library])
    }

    // MARK: a row's menu

    @Test func aMenuKeepsAValueThatIsntAChoice() {
        let choices = [ServerSettings.Choice(value: "on", label: "On"), ServerSettings.Choice(value: "off", label: "Off")]
        let setting = Self.setting("FETCH_LYRICS", "sometimes", choices: choices)
        #expect(ServerSettings.pickerChoices(setting, value: "on") == choices)
        #expect(ServerSettings.pickerChoices(setting, value: "sometimes").map(\.value) == ["sometimes", "on", "off"])
        #expect(ServerSettings.pickerChoices(setting, value: "").first == .init(value: "", label: ServerSettings.notSetChoice))
    }

    // MARK: the batch

    @Test func theBatchIsEveryDraftInOrderARevertSentAsNull() throws {
        var drafts = ServerSettings.Drafts()
        drafts.set("B", .text("2"))
        drafts.set("A", .revert)
        drafts.set("B", .text("3"))
        #expect(drafts.keys == ["B", "A"], "a key edited again keeps its place")
        drafts.remove("B")
        drafts.set("B", .text(""))
        #expect(drafts.keys == ["A", "B"], "one dropped and edited again goes last")
        let body = try DeadwaxClient.json(drafts.updates)
        // the encoder's key order inside each update is its own; the order of the updates and each value are the point
        let sentUpdates = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(sentUpdates.count == 2 && sentUpdates.allSatisfy { $0.count == 2 })
        #expect(sentUpdates.map { $0["key"] as? String } == ["A", "B"])
        #expect(sentUpdates.first?["value"] is NSNull, "a revert is a null, as SettingUpdate takes it")
        #expect(sentUpdates.last?["value"] as? String == "")
        let retime = try DeadwaxClient.json(RetimeBody(albumPath: "A/B (2020)"))
        let fields = try #require(try JSONSerialization.jsonObject(with: retime) as? [String: Any])
        #expect(fields["album_path"] as? String == "A/B (2020)" && fields["retime"] as? Bool == true
                && fields["replace"] as? Bool == false && fields.count == 3)
    }

    @Test func aSaveThatNeverAnsweredKeepsOnlyWhatStillDiffers() {
        var sent = ServerSettings.Drafts()
        sent.set("LIBRARY_PATH", .text("/music"))          // landed: the settings hold it
        sent.set("ALBUM_FOLDER_TEMPLATE", .text("{year}")) // didn't
        sent.set("LYRICS_LEAD_MS", .revert)                // still overridden: didn't
        sent.set("NAVIDROME_PASSWORD", .text("hunter2"))   // a secret: never known, kept
        var current = sent
        current.set("NAVIDROME_URL", .text("http://other"))  // never sent
        let left = ServerSettings.stillDiffering(current, sent: sent, now: Self.sample)
        #expect(left.keys == ["ALBUM_FOLDER_TEMPLATE", "LYRICS_LEAD_MS", "NAVIDROME_PASSWORD", "NAVIDROME_URL"])
        // a revert that landed: no longer overridden
        let reverted = Self.answer([("lyrics", [Self.setting("LYRICS_LEAD_MS", "0")])])
        var revert = ServerSettings.Drafts()
        revert.set("LYRICS_LEAD_MS", .revert)
        #expect(ServerSettings.stillDiffering(revert, sent: revert, now: reverted).isEmpty)
        // typed again since it was sent: kept
        var typed = revert
        typed.set("LYRICS_LEAD_MS", .text("100"))
        #expect(ServerSettings.stillDiffering(typed, sent: revert, now: reverted).keys == ["LYRICS_LEAD_MS"])
    }

    // MARK: the page's flow

    @Test func thePageReadsFirstShownAgainBackInReachAndNeverOverADraft() {
        var flow = SettingsFlow()
        #expect(!flow.readsNow(shown: true, online: false, allowed: true, again: false))
        #expect(!flow.readsNow(shown: true, online: true, allowed: false, again: false))
        #expect(flow.readsNow(shown: true, online: true, allowed: true, again: false))
        let first = flow.readBegan()
        #expect(!flow.readsNow(shown: true, online: true, allowed: true, again: true), "one read at a time")
        flow.readLanded(first, Self.sample)
        #expect(flow.real)
        // a landing asks again: nothing more wanted
        #expect(!flow.readsNow(shown: true, online: true, allowed: true, again: false))
        // shown again with no draft: read, as the web's does
        #expect(flow.readsNow(shown: true, online: true, allowed: true, again: true))
        flow.edit("LIBRARY_PATH", "/x")
        #expect(!flow.readsNow(shown: true, online: true, allowed: true, again: true), "never over a draft")
        // out of reach: a read from before isn't trusted, and Save waits for one after
        flow.outOfReach()
        #expect(!flow.saveOpen(online: true, allowed: true))
        #expect(flow.readsNow(shown: true, online: true, allowed: true, again: false))
        // a read begun before the gap lands too early: still not trusted, read again
        var early = SettingsFlow()
        let out = early.readBegan()
        early.outOfReach()
        early.readLanded(out, Self.sample)
        #expect(!early.real && early.readsNow(shown: true, online: true, allowed: true, again: false))
    }

    @Test func aFirstReadThatFailedSaysSoAndAsksNothingMoreByItself() {
        var flow = SettingsFlow()
        let ticket = flow.readBegan()
        flow.readFailed(ticket, ServerSettings.readFailure(Self.unreached, admin: false, first: true))
        #expect(flow.readError == ServerSettings.readFailure(Self.unreached, admin: false, first: true))
        #expect(!flow.reading && flow.answer == nil)
        // the page only re-asks after a landing, a show, reach or the sign-in going - Try again asks at once
        #expect(flow.readsNow(shown: true, online: true, allowed: true, again: false))
        // an older read landing late is dropped
        let older = flow.readBegan()
        let newer = flow.readBegan()
        flow.readLanded(older, Self.sample)
        #expect(flow.answer == nil && flow.reading)
        flow.readLanded(newer, Self.sample)
        #expect(flow.answer == Self.sample && flow.readError == nil)
    }

    @Test func aSaveSendsEveryDraftAndLeavesWhatWasTypedMeanwhile() {
        var flow = SettingsFlow()
        flow.readLanded(flow.readBegan(), Self.sample)
        #expect(!flow.saveOpen(online: true, allowed: true), "nothing to save")
        flow.edit("LIBRARY_PATH", "/x")
        flow.edit("ALBUM_FOLDER_TEMPLATE", "{album}")  // back to what is saved: no change
        flow.revert("LYRICS_LEAD_MS")
        #expect(flow.drafts.keys == ["LIBRARY_PATH", "LYRICS_LEAD_MS"] && flow.barText == "2 unsaved changes")
        #expect(!flow.saveOpen(online: false, allowed: true) && !flow.saveOpen(online: true, allowed: false))
        let reading = flow.readBegan()
        let sent = flow.save(online: true, allowed: true)
        #expect(sent?.keys == ["LIBRARY_PATH", "LYRICS_LEAD_MS"] && flow.saving && !flow.reading)
        #expect(flow.save(online: true, allowed: true) == nil, "one save at a time")
        flow.readLanded(reading, ServerSettingsAnswer())
        #expect(flow.answer == Self.sample, "a read out as the save went lands nowhere")
        flow.edit("LIBRARY_PATH", "/y")  // typed while it is out
        flow.saved(Self.sample)
        #expect(!flow.saving && flow.drafts.keys == ["LIBRARY_PATH"] && !flow.justSaved && flow.barText == "1 unsaved change")
        _ = flow.save(online: true, allowed: true)
        flow.saved(Self.sample)
        #expect(flow.drafts.isEmpty && flow.justSaved && flow.barText == "Saved.")
        // typing after "Saved." takes it away
        flow.edit("LIBRARY_PATH", "/z")
        #expect(!flow.justSaved && flow.barText == "1 unsaved change")
    }

    @Test func aRefusedSaveKeepsEveryDraftAndSaysDeadwaxsWords() {
        var flow = SettingsFlow()
        flow.readLanded(flow.readBegan(), Self.sample)
        flow.edit("LIBRARY_PATH", "/nope")
        _ = flow.save(online: true, allowed: true)
        flow.refused(ServerSettings.saveFailure(Self.refused, admin: false))
        #expect(flow.drafts.keys == ["LIBRARY_PATH"] && flow.barText == "Not saved: LIBRARY_PATH: not a directory")
        #expect(flow.saveOpen(online: true, allowed: true), "Save again")
        flow.discard()
        #expect(flow.drafts.isEmpty && flow.saveError == nil && flow.barText.isEmpty)
    }

    @Test func aSaveThatNeverAnsweredMayHaveLandedAndIsReadAgain() {
        var flow = SettingsFlow()
        flow.readLanded(flow.readBegan(), Self.sample)
        flow.edit("LIBRARY_PATH", "/new")
        flow.edit("ALBUM_FOLDER_TEMPLATE", "{year}")
        _ = flow.save(online: true, allowed: true)
        flow.unanswered(nil)
        #expect(!flow.saving && flow.checking != nil && flow.barText == EditWords.mayHaveFinished)
        #expect(!flow.saveOpen(online: true, allowed: true), "not again until read")
        #expect(flow.readsNow(shown: true, online: true, allowed: true, again: false))
        // the settings now hold one of the two: the other stays a draft
        let now = Self.answer([("paths", [Self.setting("LIBRARY_PATH", "/new")]),
                               ("organizing", [Self.setting("ALBUM_FOLDER_TEMPLATE", "{album}")])])
        flow.readLanded(flow.readBegan(), now)
        #expect(flow.checking == nil && flow.drafts.keys == ["ALBUM_FOLDER_TEMPLATE"] && !flow.justSaved)
        // a second that never answered, and every draft landed: "Saved."
        _ = flow.save(online: true, allowed: true)
        flow.unanswered("deadwax answered 502 and said nothing more.")
        let all = Self.answer([("organizing", [Self.setting("ALBUM_FOLDER_TEMPLATE", "{year}")])])
        flow.readLanded(flow.readBegan(), all)
        #expect(flow.drafts.isEmpty && flow.justSaved && flow.barText == "Saved.")
        // a save called off: nothing known came of it, the drafts as they were
        flow.edit("ALBUM_FOLDER_TEMPLATE", "{album}")
        _ = flow.save(online: true, allowed: true)
        flow.saveDropped()
        #expect(!flow.saving && flow.drafts.count == 1 && flow.checking == nil && flow.saveError == nil)
    }

    // MARK: MusicBrainz's saved answers

    @Test func clearReadsAfreshForAnotherFileAndSaysAnUnansweredClearMayHaveCleared() {
        var answers = SavedAnswers()
        let stats = SavedAnswersStats(enabled: true, path: "/config/mb.db", bytes: 1_572_864, answers: 1234, limitMb: 256)
        #expect(answers.readsNow(shown: true, online: true) && !answers.readsNow(shown: false, online: true))
        let first = answers.readBegan(key: "MUSICBRAINZ_CACHE_PATH=/config/mb.db|MUSICBRAINZ_CACHE_MB=256")
        answers.readLanded(first, stats)
        #expect(answers.line(unsaved: false) == "1,234 answers in 1.5 MB saved, of 256 MB.")
        #expect(answers.clearBegan(unsaved: true, online: true) == nil, "the path a draft")
        #expect(answers.clearBegan(unsaved: false, online: false) == nil, "out of reach")
        let clear = answers.clearBegan(unsaved: false, online: true)!
        #expect(answers.clearing && answers.label == SavedAnswers.clearingLabel && !answers.readsNow(shown: true, online: true))
        #expect(answers.clearBegan(unsaved: false, online: true) == nil, "once")
        answers.clearLanded(clear, SavedAnswersStats(enabled: true, path: "/config/mb.db", bytes: 12288, limitMb: 256))
        #expect(answers.line(unsaved: false) == "Cleared. The next answers are asked of MusicBrainz again.")
        // the same file read again: "Cleared." goes
        answers.readLanded(answers.readBegan(key: "MUSICBRAINZ_CACHE_PATH=/config/mb.db|MUSICBRAINZ_CACHE_MB=256"),
                           SavedAnswersStats(enabled: true, bytes: 12288, limitMb: 256))
        #expect(answers.line(unsaved: false) == "Nothing saved yet.")
        // another file: what was said of the last goes at once
        _ = answers.readBegan(key: "MUSICBRAINZ_CACHE_PATH=/data/mb.db|MUSICBRAINZ_CACHE_MB=256")
        #expect(answers.stats == nil && answers.line(unsaved: false) == SavedAnswers.readingLine)
        // a Clear that never answered may have cleared: said, and read again
        var unsure = SavedAnswers()
        unsure.readLanded(unsure.readBegan(key: "k"), stats)
        let out = unsure.clearBegan(unsaved: false, online: true)!
        let readAgain = unsure.clearUnanswered(out, nil)
        #expect(readAgain)
        #expect(unsure.line(unsaved: false) == EditWords.mayHaveFinished && unsure.readsNow(shown: true, online: true))
        unsure.readLanded(unsure.readBegan(key: "k"), SavedAnswersStats(enabled: true, limitMb: 256))
        #expect(unsure.line(unsaved: false) == "Nothing saved yet.")
        // refused: its words; called off: nothing
        var refusedOne = SavedAnswers()
        refusedOne.readLanded(refusedOne.readBegan(key: "k"), stats)
        refusedOne.clearRefused(refusedOne.clearBegan(unsaved: false, online: true)!, SavedAnswers.clearFailed)
        #expect(!refusedOne.clearing && refusedOne.line(unsaved: false) == SavedAnswers.clearFailed)
        _ = refusedOne.clearBegan(unsaved: false, online: true)
        refusedOne.clearDropped()
        #expect(!refusedOne.clearing)
    }

    // MARK: Re-time saved lyrics

    static let library = [ScanAlbum(path: "A/One", lyricsCount: 3), ScanAlbum(path: "A/None"),
                          ScanAlbum(path: "B/Two", lyricsCount: 5), ScanAlbum(path: "C/Three", lyricsCount: 1)]

    @Test func reTimeStartsOnlyWithEditAlbumsInReachAndTheLeadSaved() {
        var run = RetimeRun()
        #expect(run.start(allowed: false, online: true, unsaved: false) == nil)
        #expect(run.start(allowed: true, online: false, unsaved: false) == nil)
        #expect(run.start(allowed: true, online: true, unsaved: true) == nil)
        let ticket = run.start(allowed: true, online: true, unsaved: false)!
        #expect(run.running && run.runningLabel == RetimeRun.readingLibrary)
        #expect(run.start(allowed: true, online: true, unsaved: false) == nil, "one run at a time")
        run.read(ticket, Self.library)
        #expect(run.total == 3 && run.runningLabel == "Re-timing 1 of 3 albums · Stop after this album")
        #expect(run.keepsScreenOn(visible: true) && !run.keepsScreenOn(visible: false))
        // an older run's read lands nowhere
        run.read(ticket - 1, [])
        #expect(run.total == 3)
    }

    @Test func eachStopEndsTheRunAfterTheAlbumOutAndSaysWhy() {
        for (stop, words) in [(RetimeRun.Stop.background, RetimeRun.stopped(.background)!),
                              (.outOfReach, RetimeRun.stopped(.outOfReach)!),
                              (.sessionEnded, RetimeRun.stopped(.sessionEnded)!)] {
            var run = RetimeRun()
            run.read(run.start(allowed: true, online: true, unsaved: false)!, Self.library)
            guard case .album(let album) = run.next(allowed: true, online: true) else {
                Issue.record("no album")
                continue
            }
            #expect(album.path == "A/One")
            switch stop {
            case .background: run.suspended()
            case .outOfReach: run.outOfReach()
            case .sessionEnded: run.sessionEnded()
            default: break
            }
            #expect(run.next(allowed: true, online: true) == .nothing, "the album out finishes first")
            run.finished(.answered(RetimeSummary(retimed: 2, unchanged: 1)))
            #expect(run.next(allowed: true, online: true) == .ended)
            #expect(run.phase == .ended && run.stop == stop && !run.keepsScreenOn(visible: true))
            #expect(run.note(unsaved: false) == "Re-timed 2 tracks, 1 already at this lead. Stopped at 1 of 3 albums. \(words)")
        }
        // deadwax out of reach as the next album is asked for, and Edit albums gone: the same, by next's own check
        var gone = RetimeRun()
        gone.read(gone.start(allowed: true, online: true, unsaved: false)!, Self.library)
        #expect(gone.next(allowed: true, online: false) == .ended && gone.stop == .outOfReach)
        var taken = RetimeRun()
        taken.read(taken.start(allowed: true, online: true, unsaved: false)!, Self.library)
        #expect(taken.next(allowed: false, online: true) == .ended && taken.stop == .notAllowed)
        // Stop pressed: the web's words alone
        var pressed = RetimeRun()
        pressed.read(pressed.start(allowed: true, online: true, unsaved: false)!, Self.library)
        _ = pressed.next(allowed: true, online: true)
        #expect(pressed.stopPressed() && !pressed.stopPressed(), "once")
        pressed.finished(.answered(RetimeSummary(retimed: 3)))
        #expect(pressed.next(allowed: true, online: true) == .ended)
        #expect(pressed.note(unsaved: false) == "Re-timed 3 tracks. Stopped at 1 of 3 albums.")
        // stopped before the library answered: over as it lands, no album asked
        var early = RetimeRun()
        let ticket = early.start(allowed: true, online: true, unsaved: false)!
        early.suspended()
        early.read(ticket, Self.library)
        #expect(early.next(allowed: true, online: true) == .ended && early.done == 0)
    }

    @Test func aForbiddenAlbumStopsTheRunAndAnUnansweredOneMayHaveRetimed() {
        var run = RetimeRun()
        run.read(run.start(allowed: true, online: true, unsaved: false)!, Self.library)
        _ = run.next(allowed: true, online: true)
        run.finished(RetimeRun.step(failure: Self.unreached))
        #expect(run.totals.failed == 3 && run.maybe)
        _ = run.next(allowed: true, online: true)
        let forbidden = APIFailure.answered(.init(status: 403, method: "POST", path: "/library/lyrics/fetch"))
        #expect(RetimeRun.step(failure: forbidden) == .forbidden)
        run.finished(.forbidden)
        #expect(run.next(allowed: true, online: true) == .ended && run.stop == .notAllowed && run.totals.failed == 8)
        #expect(run.note(unsaved: false) == "Re-timed 0 tracks, 8 failed - try again. Stopped at 2 of 3 albums. "
                + "\(RetimeRun.stopped(.notAllowed)!) \(RetimeRun.mayHaveRetimed)")
        let refusal = APIFailure.answered(.init(status: 400, method: "POST", path: "/library/lyrics/fetch", detail: "no"))
        #expect(RetimeRun.step(failure: refusal) == .refused)
        let broke = APIFailure.answered(.init(status: 500, method: "POST", path: "/library/lyrics/fetch"))
        #expect(RetimeRun.step(failure: broke) == .unanswered)
    }

    @Test func howARunEndedIsSaidOnceAndLetGoForANewLead() {
        var run = RetimeRun()
        run.read(run.start(allowed: true, online: true, unsaved: false)!, [ScanAlbum(path: "A", lyricsCount: 2)])
        _ = run.next(allowed: true, online: true)
        run.finished(.answered(RetimeSummary(retimed: 2)))
        #expect(run.next(allowed: true, online: true) == .ended && run.note(unsaved: false) == "Re-timed 2 tracks.")
        #expect(run.note(unsaved: true) == RetimeRun.saveFirst)
        run.pageGone()
        #expect(run.phase == .idle && run.note(unsaved: false) == RetimeRun.prompt)
        // a new lead drafted once it ended lets it go at once; while it runs, as it ends
        var ended = RetimeRun()
        ended.read(ended.start(allowed: true, online: true, unsaved: false)!, [])
        #expect(ended.next(allowed: true, online: true) == .ended && ended.note(unsaved: false) == "Re-timed 0 tracks.")
        ended.leadDrafted()
        #expect(ended.phase == .idle)
        var moving = RetimeRun()
        moving.read(moving.start(allowed: true, online: true, unsaved: false)!, [ScanAlbum(path: "A", lyricsCount: 2)])
        moving.leadDrafted()
        #expect(moving.running)
        _ = moving.next(allowed: true, online: true)
        moving.finished(.answered(RetimeSummary(retimed: 2)))
        #expect(moving.next(allowed: true, online: true) == .ended && moving.phase == .idle)
        // the library unread: its words, until let go
        var failed = RetimeRun()
        failed.readFailed(failed.start(allowed: true, online: true, unsaved: false)!, RetimeRun.readFailed)
        #expect(failed.phase == .ended && failed.note(unsaved: false) == RetimeRun.readFailed)
    }

    // MARK: Connections

    @Test func aPingsCodeIsReadAsItsDigitsAndARowIsReadOnce() throws {
        let numbered = try JSONDecoder().decode(PingAnswer.self, from: Data(#"{"status":"failed","code":401,"error":"x"}"#.utf8))
        #expect(numbered.code == "401")
        let missing = try JSONDecoder().decode(PingAnswer.self, from: Data("{}".utf8))
        #expect(missing.status == "undefined" && Connections.fromPing(.slskd, missing).state == .failed)
        let check = Connections.Check(state: .failed, text: "Key refused", detail: "slskd answered 401.")
        #expect(check.spoken(.slskd) == "slskd, Key refused, slskd answered 401.")
        #expect(Connections.pending.spoken(.musicbrainz) == "MusicBrainz, Checking…")
    }

    @Test func aSaveOfConnectionsChecksThemAgainAndOfNavidromesAsksIt() {
        #expect(ServerSettings.checksConnectionsAgain(["NAVIDROME_URL"], Self.sample))
        #expect(!ServerSettings.checksConnectionsAgain(["LIBRARY_PATH"], Self.sample))
        #expect(!ServerSettings.checksConnectionsAgain(["NAVIDROME_URL"], nil))
        #expect(ServerSettings.asksNavidromeAgain(["LIBRARY_PATH", "NAVIDROME_PASSWORD"]))
    }

    // MARK: the answer, read leniently

    @Test func anAnswerIsReadLenientlyAndItsChoicesInTheWebsOrder() throws {
        let body = #"""
        {"version":"2.1.33","editable":false,"organizing":{"enabled":false,"blockers":["LIBRARY_PATH is not set"]},
         "groups":[{"id":"cover-art","label":"Cover art","note":"","settings":[
           {"key":"COVER_ART_SIZE","value":"1200","status":"ok","effect":"e","editable":true,
            "choices":{"full":"Full size","500":"500 px","250":"250 px","bad":7}},
           {"key":7},
           {"key":"COVER_SECRET","value":"set","secret":true,"env_set":true,"overridden":"yes"}]},
          {"label":"no id"}]}
        """#
        let answer = try ServerSettingsAnswer.read(Data(body.utf8))
        #expect(answer.groups.map(\.id) == ["cover-art"], "a group without an id left out")
        #expect(answer.settings.map(\.key) == ["COVER_ART_SIZE", "COVER_SECRET"], "a setting without a key left out")
        #expect(answer.settings[0].choices?.map(\.value) == ["250", "500", "full"], "a value that isn't words left out")
        #expect(answer.settings[1].secret && answer.settings[1].envSet == true && !answer.settings[1].overridden)
        #expect(!answer.organizing.enabled && answer.organizing.blockers == ["LIBRARY_PATH is not set"])
        #expect(ServerSettings.jsOrder(["b", "10", "2", "01", "4294967295", "4294967294"])
                == ["2", "10", "4294967294", "b", "01", "4294967295"])
    }

    @Test func aChoiceWrittenTwiceKeepsItsFirstPlaceAndItsLastWords() throws {
        // JSON.parse's rule, whatever JSONDecoder picks between the two: the first place, the last value - and a last
        // value that isn't words leaves the choice out, as one written once would be
        let body = #"""
        {"groups":[{"id":"g","settings":[{"key":"K","value":"x","effect":"",
          "choices":{"x":"first","y":"second","x":"again","z":"words","z":7,"w":7,"w":"now words"}}]}],
         "organizing":{"enabled":true,"blockers":[]}}
        """#
        let choices = try ServerSettingsAnswer.read(Data(body.utf8)).settings[0].choices ?? []
        #expect(choices == [.init(value: "x", label: "again"), .init(value: "y", label: "second"),
                            .init(value: "w", label: "now words")])
    }

    // MARK: Connections' rows

    @Test func connectionsAreCheckedOnceShownAndAgainOnlyWhenWanted() {
        var checks = ConnectionChecks()
        #expect(checks.rows == nil && checks.check(.slskd) == Connections.pending && !checks.againOpen(online: true))
        #expect(!checks.checksNow(shown: true, allowed: false, online: true), "only whoever runs deadwax")
        #expect(!checks.checksNow(shown: true, allowed: true, online: false))
        #expect(!checks.checksNow(shown: false, allowed: true, online: true))
        #expect(checks.checksNow(shown: true, allowed: true, online: true))
        let first = checks.began()
        #expect(Connections.Service.allCases.allSatisfy { checks.check($0) == Connections.pending })
        #expect(checks.againOpen(online: true) && !checks.againOpen(online: false), "Check again even while one is out")
        #expect(!checks.checksNow(shown: true, allowed: true, online: true), "shown again: not checked again by itself")
        checks.settled(first, .slskd, Connections.Check(state: .ok, text: Connections.connected))
        #expect(checks.check(.slskd).state == .ok && checks.check(.musicbrainz) == Connections.pending)
        // Check again: every row Checking… again, and the first check's late answer dropped
        let second = checks.began()
        checks.settled(first, .musicbrainz, Connections.Check(state: .ok, text: Connections.connected))
        #expect(checks.check(.musicbrainz) == Connections.pending && checks.check(.slskd) == Connections.pending)
        checks.settled(second, .navidrome, Connections.unanswered(Self.unreached))
        #expect(checks.check(.navidrome).text == ErrorWords.pingUnanswered)
        // back in reach (or after a save of a connection, or the sign-in going): checked as a page shows
        checks.want()
        #expect(checks.checksNow(shown: true, allowed: true, online: true))
        _ = checks.began()
        #expect(!checks.wanted)
    }

    // MARK: failures, as each part says them

    @Test func eachPartSaysItsOwnFailure() {
        let forbidden = APIFailure.answered(.init(status: 403, method: "POST", path: "/settings/musicbrainz_cache/clear",
                                                  detail: "Not allowed"))
        let crashed = APIFailure.answered(.init(status: 500, method: "POST", path: "/settings/musicbrainz_cache/clear",
                                                detail: "database is locked"))
        let silent = APIFailure.answered(.init(status: 502, method: "PUT", path: "/settings"))
        #expect(SavedAnswers.readFailure(Self.unreached, admin: false)
                == ErrorWords.notice("", Self.unreached, failed: SavedAnswers.readFailed))
        #expect(SavedAnswers.clearFailure(forbidden, admin: true)
                == ErrorWords.notice("", forbidden, admin: true, failed: SavedAnswers.clearFailed))
        #expect(SavedAnswers.clearUnansweredWords(Self.unreached, admin: true) == nil, "nothing of deadwax's to say")
        #expect(SavedAnswers.clearUnansweredWords(crashed, admin: false) == "Database is locked.", "deadwax's own, as a sentence")
        #expect(RetimeRun.readFailure(Self.unreached, admin: false)
                == ErrorWords.notice("", Self.unreached, failed: RetimeRun.readFailed, retry: true))
        #expect(ServerSettings.unansweredWords(silent, admin: true) == nil)
        #expect(ServerSettings.unansweredWords(Self.unreached, admin: true) == nil)
    }

    // MARK: the waits

    @Test func theWaitsAreTheRoutesAndASaveGrowsWithItsBatch() {
        #expect(Routes.timeouts[Routes.serverSettings] == 30)
        #expect(Routes.timeouts[Routes.saveServerSettings] == 60)
        #expect(Routes.timeouts[Routes.savedAnswers] == 30 && Routes.timeouts[Routes.clearSavedAnswers] == 120)
        #expect(Routes.timeouts[Routes.pingMusicBrainz]! > ArtistWaits.musicBrainz)
        #expect(Routes.timeouts[Routes.pingSlskd] == 30)
        // one setting: its row and the overrides read back, 10 s each, and the settings' read - under the route's own
        #expect(ServerSettings.saveWait(1) == 60)
        // twelve: 30 + 130, to the minute
        #expect(ServerSettings.saveWait(12) == 180)
        // Re-time: two tracks at a time, each up to two names by two requests - and never less than the route's
        #expect(EditWaits.retime(ScanAlbum(path: "A", lyricsCount: 1)) == 600)
        #expect(EditWaits.retime(ScanAlbum(path: "A", trackCount: 30, lyricsCount: 12)) == 1380)
        #expect(EditWaits.retime(ScanAlbum(path: "A", trackCount: 30, lyricsCount: 12))
                == EditWaits.lyrics(ScanAlbum(path: "A", trackCount: 12)))
    }

    // MARK: who may

    @Test func reTimeAsksForEditAlbumsTooAndConnectionsComeWithThePage() {
        let server = Access(user: "ethan", permissions: [.server], on: true, unverified: false, admin: false)
        #expect(ServerSettings.parts(server) == .init(page: true, connections: true, retime: false, answers: true))
        let both = Access(user: "ethan", permissions: [.server, .edit], on: true, unverified: false, admin: false)
        #expect(ServerSettings.parts(both).retime)
        let edit = Access(user: "ethan", permissions: [.edit], on: true, unverified: false, admin: false)
        #expect(ServerSettings.parts(edit) == .init(page: false, connections: false, retime: false, answers: false))
        let off = Access(me: Me(user: "local", admin: true, auth: "off"))
        #expect(ServerSettings.parts(off) == .init(page: true, connections: true, retime: true, answers: true))
    }
}
