import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/password/password-vectors.json: the web's lib/ownPassword.ts, lib/people.ts and lib/signIn.ts run as they
/// are, and app/ChangePassword.tsx's and api/me.ts's own read out of their source - replayed here through OwnPassword,
/// case for case (notes/ios-specs/phase8-managing.md 9). Every string is compared as JavaScript compares it, unit for
/// unit - the fixture's passwords include two alike but for their normalization, which Swift's `==` would call equal.
@Suite struct OwnPasswordVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("password/password-vectors.json"))

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-password-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/ownPassword.ts", "ui/src/lib/people.ts", "ui/src/lib/signIn.ts",
                                 "ui/src/app/ChangePassword.tsx the fields' labels",
                                 "ui/src/app/ChangePassword.tsx the button's words",
                                 "ui/src/app/ChangePassword.tsx the body sent",
                                 "ui/src/app/ChangePassword.tsx a wrong current password, emptied and focused",
                                 "ui/src/app/ChangePassword.tsx one change at a time, when ready",
                                 "ui/src/app/ChangePassword.tsx a change done: the fields emptied, then what is said",
                                 "ui/src/app/ChangePassword.tsx a failure keeps the fields",
                                 "ui/src/app/ChangePassword.tsx the plain-http note",
                                 "ui/src/app/ChangePassword.tsx the Amperfy line",
                                 "ui/src/api/me.ts the route, and a new session after it"])
        #expect(fixture["problems"].list.count == 293)
        #expect(fixture["forms"].list.count == 140)
        #expect(fixture["done"].list.count == 10)
        #expect(fixture["offered"].list.count == 11)
    }

    // MARK: the words, and the page's own

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        let diffs = ScreenDiffs()
        diffs.text("CHANGE_TITLE", OwnPassword.title, words["CHANGE_TITLE"])
        diffs.text("Account's row", ManagingWords.changePassword, words["CHANGE_TITLE"])
        diffs.text("SAME_PASSWORD", OwnPassword.samePassword, words["SAME_PASSWORD"])
        diffs.text("APPS_LINE", OwnPassword.appsLine, words["APPS_LINE"])
        diffs.text("HTTP_NOTE", OwnPassword.httpNoteWords, words["HTTP_NOTE"])
        diffs.number("PASSWORD_MIN", Double(OwnPassword.passwordMin), words["PASSWORD_MIN"])
        diffs.number("PASSWORD_MAX", Double(OwnPassword.passwordMax), words["PASSWORD_MAX"])
        diffs.text("BREAK_GLASS_USER", Access.breakGlassUser, words["BREAK_GLASS_USER"])
        diffs.done()
    }

    /// The page's labels: Current password and New password the web's own; the third the phone's (the web's "Again" sits
    /// under New password on a page you look at - read alone by VoiceOver it says nothing), and Change for Save. Pinned
    /// as departures: a web label changed fails here.
    @Test func theLabelsAreTheWebsButTwoDeparturesNamed() {
        let page = fixture["page"]
        let diffs = ScreenDiffs()
        diffs.text("Current password", OwnPassword.currentLabel, page["labels"][0])
        diffs.text("New password", OwnPassword.newLabel, page["labels"][1])
        diffs.text("the web's third label", "Again", page["labels"][2])
        diffs.text("the web's button", "Save", page["button"])
        diffs.text("the web's busy button", "Saving\u{2026}", page["busy"])
        diffs.done()
        #expect(OwnPassword.againLabel == "New password again" && OwnPassword.change == "Change")
        #expect(OwnPassword.changing == "Changing\u{2026}")
    }

    /// What the page does itself: a refusal of the current password (its kind) empties it and puts the focus there; the
    /// route is the one the phone asks, POST; after it the web starts a new session, as the phone re-keys.
    @Test func whatThePageDoesIsThePhones() {
        let page = fixture["page"]
        #expect(Screens.same(OwnPassword.notYourPassword, page["wrongCurrentKind"].string))
        #expect(Routes.ownPassword.path == "/deadwax" + (page["route"].string ?? "?"))
        #expect(Routes.ownPassword.method == "POST" && Routes.ownPassword.query.isEmpty)
        var flow = OwnPasswordFlow()
        flow.form = OwnPasswordForm(current: "wrong-one-here", password: "a-fresh-own-password", again: "a-fresh-own-password")
        let begun = flow.begin(user: "ethan", online: true, signInOver: false)
        guard let (ticket, _) = begun else {
            Issue.record("a ready form begins")
            return
        }
        _ = flow.ended(ticket, .refused(words: "That isn't your current password.", kind: page["wrongCurrentKind"].string,
                                        fix: nil), signInOver: false, device: .iPhone)
        #expect(flow.form.current.isEmpty && flow.form.password == "a-fresh-own-password" && flow.focusCurrent == 1)
    }

    // MARK: the rules

    @Test func eachPasswordsProblemIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["problems"].list.enumerated() {
            let password = row["password"].string!, again = row["again"].string!, name = row["name"].string!
            diffs.text("\(at): \(Screens.spelled(password)) / \(Screens.spelled(again)) as \(Screens.spelled(name))",
                       OwnPassword.passwordProblem(password, again: again, name: name), row["said"])
        }
        diffs.done()
    }

    /// Each form: what shows while typing, whether Change is on, and what it sends - every key and value as the web's
    /// page sends them.
    @Test func eachFormIsTheWebs() throws {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["forms"].list.enumerated() {
            let form = OwnPasswordForm(current: row["current"].string!, password: row["password"].string!,
                                       again: row["again"].string!)
            let user = row["user"].string!
            let label = "\(at): as \(Screens.spelled(user))"
            diffs.text("\(label), the problem", OwnPassword.formProblem(form, user: user), row["problem"])
            diffs.flag("\(label), ready", OwnPassword.formReady(form, user: user), row["ready"])
            let sent = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(OwnPasswordBody(form)))
            diffs.check("\(label), the body's keys", sent.keys.sorted(), row["body"].keys.sorted())
            for key in row["body"].keys {
                diffs.text("\(label), the body's \(key)", sent[key], row["body"][key])
            }
        }
        diffs.done()
    }

    @Test func whatIsSaidAfterIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["done"].list {
            let count = row["signedOut"].int!
            diffs.text("doneWords(\(count))", OwnPassword.doneWords(count), row["said"])
        }
        for row in fixture["lines"].list {
            let user = row["user"].string!
            diffs.text("changeLine(\(Screens.spelled(user)))", OwnPassword.changeLine(user), row["said"])
        }
        for row in fixture["notes"].list {
            let scheme = row["protocol"].string!
            diffs.text("httpNote(\(Screens.spelled(scheme)))", OwnPassword.httpNote(protocol: scheme), row["said"])
        }
        diffs.done()
    }

    @Test func whoIsOfferedItIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["offered"].list {
            let me = row["me"].isNull ? nil : Me(user: row["me"]["user"].string!, admin: false, auth: row["me"]["auth"].string!)
            diffs.flag("\(row["me"])", OwnPassword.changeOffered(me), row["offered"])
            diffs.flag("\(row["me"]), Manage's name for it", Managing.changeOffered(me), row["offered"])
        }
        diffs.done()
    }

    /// The phone's address says the note: none over https, the note over http.
    @Test func theNoteFollowsTheAddress() throws {
        let plain = try ServerAddress.parse("192.168.3.20:8090").get()
        let secure = try ServerAddress.parse("https://deadwax.example.org").get()
        #expect(OwnPassword.httpNote(at: plain) == OwnPassword.httpNoteWords)
        #expect(OwnPassword.httpNote(at: secure) == nil)
        #expect(OwnPassword.httpNote(at: nil) == OwnPassword.httpNoteWords)
    }
}
