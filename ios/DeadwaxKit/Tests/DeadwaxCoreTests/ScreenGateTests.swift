import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/gate/navidrome.json: the web's Navidrome gate (app/NeedsNavidrome.tsx) run as it is over every status a
/// check can find, for every kind of reader - and what its check (lib/navidromeCheck.ts) makes of one that failed.
/// Replayed here through NavidromeGate, case for case.
@Suite struct ScreenGateTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("gate/navidrome.json"))

    @Test func theFixtureIsThere() {
        #expect(fixture["cases"].list.count == 35)
        #expect(fixture["made_by"].string == "ios/scripts/export-gate-vectors.cjs")
        for source in ["ui/src/app/NeedsNavidrome.tsx", "ui/src/app/access.ts", "ui/src/lib/errorWords.ts",
                       "ui/src/lib/navidromeCheck.ts"] {
            #expect(fixture["made_from"][source].string?.utf8.count == 64, "made_from names \(source)")
        }
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(Screens.same(NavidromeGate.musicUnavailable, words["MUSIC_UNAVAILABLE"].string))
        #expect(Screens.same(NavidromeGate.musicNotYet, words["MUSIC_NOT_YET"].string))
        #expect(Screens.same(NavidromeGate.musicUnreached, words["MUSIC_UNREACHED"].string))
        #expect(Screens.same(NavidromeGate.deadwaxUnreached, words["DEADWAX_UNREACHED"].string))
        #expect(Screens.same(NavidromeGate.musicUnset, words["MUSIC_UNSET"].string))
        #expect(Screens.same(NavidromeGate.adminSetsUp, words["ADMIN_SETS_UP"].string))
        #expect(Screens.same(NavidromeGate.navidromeRequired, words["NAVIDROME_REQUIRED"].string))
        #expect(Screens.same(NavidromeGate.navidromeUnreached, words["NAVIDROME_UNREACHED"].string))
    }

    @Test func everyCaseDrawsAsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["cases"].list {
            let who = row["me"]
            let me = Me(user: who["user"].string!, admin: who["admin"].bool!, auth: who["auth"].string!,
                        permissions: who["permissions"].isNull ? nil : who["permissions"].list.compactMap(\.string))
            let access = Access(me: me)
            let status = fixture["statuses"][row["status"].string!]
            let checked = status.isNull ? nil : NavidromeGate.Checked(
                status: NavidromeStatus(configured: status["configured"].bool!, ok: status["ok"].bool!,
                                        server: status["server"].string, problem: status["problem"].string),
                offline: status["offline"].bool ?? false)
            let label = "\(row["reader"].string!) / \(row["status"].string!)"
            let shown = NavidromeGate.shown(checked, access: access)
            let drawn = row["drawn"]
            if drawn.string == "open" {
                diffs.check("\(label): open", shown, .open)
            } else if let spinner = drawn["spinner"].string {
                diffs.check("\(label): the spinner", shown, .connecting)
                diffs.check("\(label): the spinner's name", NavidromeGate.connecting, spinner)
            } else if case .closed(let closed) = shown {
                diffs.text("\(label): the heading", closed.title, drawn["title"])
                diffs.check("\(label): the lines", closed.lines, drawn["lines"].list.compactMap(\.string).filter { !$0.isEmpty })
                let buttons = (closed.tryAgain ? [NavidromeGate.tryAgain] : []) + (closed.setUp ? [NavidromeGate.setUp] : [])
                diffs.check("\(label): the buttons", buttons, drawn["buttons"].list.compactMap(\.string))
            } else {
                diffs.check("\(label): closed", "\(shown)", "closed")
            }
        }
        #expect(diffs.checked >= 35)
        #expect(diffs.lines.isEmpty, "\(diffs.lines.joined(separator: "\n"))")
    }

    /// A check that failed: deadwax not answering is offline (its listener told to check their connection); deadwax
    /// answering an error, or the check timing out, is the music server's (navidromeChecks' TypeError test).
    @Test func aFailedCheckIsOfflineOnlyWhenNothingAnswered() throws {
        let server = try ServerAddress.parse("http://192.168.1.20:8090").get()
        let unreached = APIFailure.offline(.init(server: server, method: "GET", path: "/navidrome/status",
                                                 reason: "The Internet connection appears to be offline."))
        let refused = APIFailure.answered(.init(status: 502, method: "GET", path: "/navidrome/status",
                                                detail: "Navidrome couldn't be reached"))
        let timedOut = APIFailure.timeout(.init(server: server, method: "GET", path: "/navidrome/status",
                                                reason: "The request timed out."))
        let checks = fixture["checks"]
        for (name, error) in [("deadwaxUnreached", unreached), ("navidromeRefused", refused), ("timedOut", timedOut)] {
            let checked = NavidromeGate.Checked.failed(error, problem: error.words)
            #expect(checked.offline == checks[name]["offline"].bool, "\(name)")
            #expect(checked.status.configured == checks[name]["configured"].bool, "\(name)")
            #expect(checked.status.ok == checks[name]["ok"].bool, "\(name)")
            #expect(checked.status.server == nil && checks[name]["server"].isNull, "\(name)")
            #expect(checked.status.problem == error.words)
        }
    }

    /// The phone's own: before anything is found the Library draws (its kept list at once), and what is found is the
    /// web's rule.
    @Test func thePhoneDrawsTheLibraryUntilACheckFindsNavidromeMissing() {
        let listener = Access(me: Me(user: "ethan", admin: false, auth: "on", permissions: ["request"]))
        #expect(NavidromeGate.shownOnPhone(nil, access: listener) == .open)
        let down = NavidromeGate.Checked(status: NavidromeStatus(configured: true, ok: false, problem: "x"))
        #expect(NavidromeGate.shownOnPhone(down, access: listener) == NavidromeGate.shown(down, access: listener))
        let reached = NavidromeGate.Checked(status: NavidromeStatus(configured: true, ok: true, server: "Navidrome 0.64.2"))
        #expect(NavidromeGate.shownOnPhone(reached, access: listener) == .open)
        #expect(NavidromeGate.setUpPath == "/player/")
    }

    @Test func setUpOpensDeadwaxsOwnAppAtThePhonesServer() throws {
        let server = try ServerAddress.parse("192.168.1.20:8090").get()
        #expect(NavidromeGate.setUpURL(server)?.absoluteString == "http://192.168.1.20:8090/player/")
        let pasted = try ServerAddress.parse("http://deadwax.lan:8090/player/").get()
        #expect(NavidromeGate.setUpURL(pasted)?.absoluteString == "http://deadwax.lan:8090/player/")
    }
}
