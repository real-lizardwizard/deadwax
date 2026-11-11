import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/signin.json: the web's sign-in screen (app/SignIn.tsx) driven a step at a time - typing, Sign in,
/// deadwax's answer - and what it drew after each; the gate's launch reason (signInGate.tsx, as written); which 401
/// ends the session (api/http.ts); Sign out (SignOutRow.tsx) driven; and the words. Replayed here through SignInForm,
/// SignInRules, SessionCount and SignOutRow, step for step.
@Suite struct ScreenSignInTests {
    let fixture = try! Web.load("signin")

    @Test func theFixtureIsThere() {
        #expect(fixture["form"].list.count == 73)
        #expect(fixture["sessions"].list.count == 80 && fixture["launch"].list.count > 20)
        expectMadeFrom(fixture, ["ui/src/lib/signIn.ts", "ui/src/app/SignIn.tsx", "ui/src/app/SignOutRow.tsx",
                                 "ui/src/app/signInGate.tsx the launch reason", "ui/src/api/http.ts noteSignedOut"])
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(SignInWords.avatar == words["avatar"].string)
        #expect(SignInWords.title == words["title"].string)
        #expect(SignInWords.lede == words["lede"].string)
        #expect([SignInWords.userName, SignInWords.password] == words["labels"].list.compactMap(\.string))
        #expect(SignInWords.signIn == words["button"].string)
        #expect(SignInWords.empty == words["empty"].string)
        #expect(ErrorWords.plainSignIn == words["PLAIN_SIGN_IN"].string)
        #expect(ErrorWords.unreached == words["UNREACHED"].string)
        #expect(ErrorWords.serverFailed == words["SERVER_FAILED"].string)
        #expect(ErrorWords.forWhoever == words["FOR_WHOEVER"].string)
        #expect(Access.breakGlassUser == words["BREAK_GLASS_USER"].string)
    }

    @Test func reasonShownAndAfterSignInAreTheWebs() {
        for row in fixture["reasonShown"].list {
            #expect(Screens.same(ErrorWords.reasonShown(row["detail"].string), row["shown"].string), "reasonShown(\(row["detail"]))")
        }
        for row in fixture["afterSignIn"].list {
            #expect(Access.afterSignIn(before: row["before"].string, now: row["now"].string!).rawValue == row["result"].string,
                    "afterSignIn(\(row["before"]), \(row["now"]))")
        }
    }

    /// Every trace of the screen: the web's named ones (signin.sim.cjs's checks - the empty fields, the trimmed name,
    /// the password cleared, the problem not said twice, busy) and seeded ones, step for step.
    @Test func theScreenDrivenIsTheWebs() {
        let diffs = ScreenDiffs()
        for trace in fixture["form"].list {
            let name = trace["name"].string ?? "?"
            var form = SignInForm()
            var signedIn = 0
            for (index, step) in trace["steps"].list.enumerated() {
                let label = "\(name) step \(index) (\(step["step"]["op"].string ?? "?"))"
                var sent: SignInBody?
                switch step["step"]["op"].string {
                case "type":
                    if step["step"]["field"].string == "username" { form.username = step["step"]["value"].string! }
                    else { form.password = step["step"]["value"].string! }
                case "submit":
                    sent = form.submit()
                default:
                    let answer = step["step"]["answer"]
                    if answer["me"].isNull { form.failed(screenFailure(answer)) } else { form.signedIn(); signedIn += 1 }
                }
                diffs.text("\(label): sent name", sent?.username, step["sent"][0])
                diffs.text("\(label): sent password", sent?.password, step["sent"][1])
                diffs.check("\(label): signed in", signedIn, step["signedIn"].int ?? -1)
                let drawn = step["drawn"]
                let lines = form.lines(reason: trace["reason"].string, reasonWhy: trace["reasonWhy"].string)
                diffs.text("\(label): reason", lines.reason, drawn["reason"])
                diffs.text("\(label): reason's fold", lines.reasonWhy, drawn["reasonWhy"])
                diffs.text("\(label): problem", lines.problem, drawn["problem"])
                diffs.text("\(label): problem's fold", lines.problemWhy, drawn["problemWhy"])
                diffs.text("\(label): button", lines.button, drawn["button"])
                diffs.flag("\(label): disabled", lines.disabled, drawn["disabled"])
                diffs.text("\(label): described by the reason", lines.reason != nil ? "app-signin-reason" : nil, drawn["describedBy"])
                diffs.text("\(label): name field", form.username, drawn["username"])
                diffs.text("\(label): password field", form.password, drawn["password"])
            }
        }
        diffs.done()
    }

    @Test("the name trimmed, the password as typed; the password gone after the answer")
    func theNameTrimmed() {
        var form = SignInForm(username: " Ethan ", password: " the-password ")
        #expect(form.submit() == SignInBody(username: "Ethan", password: " the-password "))
        #expect(form.submit() == nil, "busy: a second Sign in sends nothing")
        form.failed(screenFailure(.object(["status": .number(401)])))
        #expect(form.password.isEmpty && form.problem == "That user name and password didn't work." && !form.busy)
        var empty = SignInForm(username: "\u{00A0}\u{FEFF}", password: "pw")
        #expect(empty.submit() == nil && empty.problem == SignInWords.empty)
    }

    @Test func theLaunchReasonIsTheGates() {
        let diffs = ScreenDiffs()
        for row in fixture["launch"].list {
            let said = SignInRules.launchReason(screenFailure(row["error"], path: "/me", method: "GET"))
            diffs.text("launch(\(row["error"])): reason", said.reason, row["reason"])
            diffs.text("launch(\(row["error"])): why", said.why, row["why"])
        }
        diffs.done()
    }

    /// A 401 from any route but /auth/'s, to a request sent under the session held now, ends it - with its detail as
    /// the sign-in's reason.
    @Test func whichRefusalEndsTheSessionIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["sessions"].list {
            let path = row["path"].string!, status = row["status"].int!
            var sessions = SessionCount()
            let sentUnder = sessions.current
            if row["signedInSince"].bool! { sessions.newSession() }
            let label = "\(status) \(path) signed in since \(row["signedInSince"])"
            diffs.flag(label, sessions.ends(status: status, path: path, sentUnder: sentUnder), row["ends"])
            let failure = APIFailure.answered(.init(status: status, method: "GET", path: path, detail: row["detail"].string))
            diffs.flag("\(label) (thrown)", SignInRules.endsSession(failure, sentUnder: sentUnder, session: sessions.current), row["ends"])
            if row["ends"].bool == true { diffs.text("\(label): the reason", failure.detail, row["said"]) }
        }
        diffs.done()
        #expect(!SignInRules.endsSession(.offline(.init(server: try! ServerAddress.parse("192.168.3.20:8090").get(), method: "GET", path: "/me",
                                                        reason: "offline")), sentUnder: 0, session: 0))
    }

    @Test func signOutIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["signOut"]["footnotes"].list {
            diffs.text("footnote(\(row["user"]))", SignOutRow.footnote(user: row["user"].string!), row["footnote"])
        }
        for trace in fixture["signOut"]["traces"].list {
            let name = trace["name"].string ?? "?"
            var row = SignOutRow()
            var asks = 0, reloads = 0
            for (index, step) in trace["steps"].list.enumerated() {
                let label = "\(name) step \(index)"
                if step["step"]["op"].string == "click" {
                    if row.press() { asks += 1 }
                } else {
                    let answer = step["step"]["answer"]
                    let error: APIFailure? = answer["ok"].bool == true ? nil : screenFailure(answer, path: "/auth/logout")
                    if row.answered(error) == .startAgain { reloads += 1 }
                }
                diffs.check("\(label): asks", asks, step["asks"].int ?? -1)
                diffs.check("\(label): started again", reloads, step["reloads"].int ?? -1)
                diffs.text("\(label): row", row.label, step["row"])
                diffs.flag("\(label): disabled", row.busy, step["disabled"])
                diffs.text("\(label): problem", row.problem, step["problem"])
            }
        }
        diffs.done()
    }
}
