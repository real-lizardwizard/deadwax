import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/signin.json: the web's sign-in screen (app/SignIn.tsx) driven a step at a time - typing, Sign in,
/// deadwax's answer - and what it drew after each; the gate's launch reason (signInGate.tsx, as written); which 401
/// ends the session (api/http.ts); Sign out (SignOutRow.tsx) driven; and the words. Replayed here through SignInForm,
/// SignInRules and SignOutRow, step for step.
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
    /// the sign-in's reason. The web's "signed in since" (its session count moved on) is the phone's cookie replaced.
    @Test func whichRefusalEndsTheSessionIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["sessions"].list {
            let path = row["path"].string!, status = row["status"].int!
            let since = row["signedInSince"].bool!
            let failure = APIFailure.answered(.init(status: status, method: "GET", path: path, detail: row["detail"].string))
            let label = "\(status) \(path) signed in since \(row["signedInSince"])"
            diffs.flag(label, SignInRules.endsSession(failure, sentUnder: "s.first", current: since ? "s.second" : "s.first"), row["ends"])
            //? logins just turned on: the request that failed went out with no cookie, and none is held yet - or one is now
            diffs.flag("\(label) (no cookie sent)", SignInRules.endsSession(failure, sentUnder: nil, current: since ? "s.first" : nil), row["ends"])
            if row["ends"].bool == true { diffs.text("\(label): the reason", failure.detail, row["said"]) }
        }
        diffs.done()
        let server = try! ServerAddress.parse("192.168.3.20:8090").get()
        #expect(!SignInRules.endsSession(.offline(.init(server: server, method: "GET", path: "/me", reason: "offline")),
                                         sentUnder: "s.1", current: "s.1"))
        #expect(!SignInRules.endsSession(.timeout(.init(server: server, method: "GET", path: "/me", reason: "timed out")),
                                         sentUnder: nil, current: nil))
        #expect(!SignInRules.endsSession(.other("unreadable"), sentUnder: "s.1", current: "s.1"))
    }

    /// The rule over what the client really tells: `onSignedOut` passes the cookie the request carried, and the app
    /// compares it with the one in hand when the 401 lands - a sign-in in between makes it an old session's 401.
    @Test func theClientsSignedOutHookFeedsTheRule() async throws {
        let heard = SignedOutHeard()
        let (made, transport) = client(session: "s.old")
        var old = made
        old.onSignedOut = { failure, session in heard.hear(failure, session) }
        transport.answer("/deadwax/me", 401, #"{"detail":"Your session has ended. Sign in again."}"#)
        _ = try? await old.me()
        //? someone signed in meanwhile: the app's client now carries the new cookie
        var new = old
        new.session = "s.new"
        _ = try? await new.me()
        let told = heard.all
        try #require(told.count == 2)
        #expect(told[0].1 == "s.old" && told[1].1 == "s.new")
        #expect(!SignInRules.endsSession(told[0].0, sentUnder: told[0].1, current: "s.new"), "the old session's 401 says nothing of the new one")
        #expect(SignInRules.endsSession(told[1].0, sentUnder: told[1].1, current: "s.new"))
        #expect(SignInRules.endsSession(told[0].0, sentUnder: told[0].1, current: "s.old"), "with no sign-in since, it ends the session")
        #expect(told[1].0.detail == "Your session has ended. Sign in again.")
    }

    /// The client's signOut throws only when nothing answered, or when its task was cancelled - which learned nothing,
    /// so the row is as it was and says nothing.
    @Test func aCancelledSignOutLeavesTheRowAsItWas() async {
        var row = SignOutRow()
        let rowAsks = row.press()
        #expect(rowAsks)
        let cancelled = row.answered(CancellationError())
        #expect(cancelled == .stay)
        #expect(!row.busy && row.problem == nil && row.label == "Sign out")
        let (deadwax, transport) = client(session: "s.1")
        transport.goAway()
        var unreached = SignOutRow()
        let unreachedAsks = unreached.press()
        #expect(unreachedAsks)
        do { try await deadwax.signOut(); Issue.record("nothing answered, and signOut didn't throw") } catch {
            let outcome = unreached.answered(error)
            #expect(outcome == .stay)
        }
        #expect(unreached.problem == SignOutRow.unreached && !unreached.busy)
        let (answering, answers) = client(session: "s.1")
        answers.answer("/deadwax/auth/logout", 503, #"{"detail":"couldn't forget it"}"#)
        var signedOut = SignOutRow()
        let signedOutAsks = signedOut.press()
        #expect(signedOutAsks)
        do {
            try await answering.signOut()
            let outcome = signedOut.answered(nil)
            #expect(outcome == .startAgain)
        } catch {
            Issue.record("deadwax answered, and signOut threw \(error)")
        }
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
