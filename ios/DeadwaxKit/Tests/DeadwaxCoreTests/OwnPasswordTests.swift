import Foundation
import Testing
@testable import DeadwaxCore

/// Change password's own rules beside the web's (OwnPasswordVectorTests): what each answer means, the page's flow, the
/// hold on the sign-in while a change is out, the cookie a request carried, the body that says no password when
/// printed - and the client's call, through FakeTransport, with the answers src/routes/own_password.py sends
/// (tests/test_ios_change_password.py makes them from the real route).
@Suite struct OwnPasswordTests {
    static let route = "/deadwax/me/password"
    static let cookie = "deadwax_session=s.new-NEW_123; HttpOnly; Max-Age=2592000; Path=/; SameSite=strict"
    static let body = OwnPasswordBody(current: "ethan-navidrome-pw", password: "a-fresh-own-password",
                                      again: "a-fresh-own-password")

    static func refusal(_ status: Int, _ json: String) -> APIFailure {
        APIFailure.answered(HTTPResponse(status: status, body: Data(json.utf8)),
                            to: HTTPRequest(method: "POST", url: URL(string: "http://192.168.3.20:8090\(route)")!))
    }

    // MARK: a 200

    @Test func aNewCookieIsTheChangeAndItsSession() {
        let answered = HTTPResponse(status: 200, headers: ["Set-Cookie": Self.cookie],
                                    body: Data(#"{"changed":true,"signed_out":2,"warning":null}"#.utf8))
        #expect(OwnPassword.outcome(of: answered) == .changed(signedOut: 2, warning: nil, session: "s.new-NEW_123"))
        // the warning as it came; the cookie the proof whatever the body says
        let warned = HTTPResponse(status: 200, headers: ["set-cookie": Self.cookie],
                                  body: Data(#"{"changed":true,"signed_out":0,"warning":"deadwax couldn't check."}"#.utf8))
        #expect(OwnPassword.outcome(of: warned) == .changed(signedOut: 0, warning: "deadwax couldn't check.",
                                                             session: "s.new-NEW_123"))
        let unreadable = HTTPResponse(status: 200, headers: ["Set-Cookie": Self.cookie], body: Data("<html>".utf8))
        #expect(OwnPassword.outcome(of: unreadable) == .changed(signedOut: 0, warning: nil, session: "s.new-NEW_123"))
        // fields of another type are their defaults
        let odd = HTTPResponse(status: 200, headers: ["Set-Cookie": Self.cookie],
                               body: Data(#"{"changed":"yes","signed_out":"3","warning":7}"#.utf8))
        #expect(OwnPassword.outcome(of: odd) == .changed(signedOut: 0, warning: nil, session: "s.new-NEW_123"))
    }

    @Test func noNewCookieIsNotARekey() {
        // NOT_RENEWED: the session stands under its old id - nothing to keep
        let notRenewed = HTTPResponse(status: 200, body: Data(#"{"changed":true,"signed_out":1,"warning":"a copy of its old one would still work"}"#.utf8))
        #expect(OwnPassword.outcome(of: notRenewed) == .notRenewed(signedOut: 1, warning: "a copy of its old one would still work"))
        // a cookie being cleared is none
        let cleared = HTTPResponse(status: 200, headers: ["Set-Cookie": "deadwax_session=; Max-Age=0; Path=/"],
                                   body: Data(#"{"changed":true,"signed_out":0,"warning":null}"#.utf8))
        #expect(OwnPassword.outcome(of: cleared) == .notRenewed(signedOut: 0, warning: nil))
        // no cookie and not deadwax's answer: nothing is known
        let strange = HTTPResponse(status: 200, body: Data("<html>ok</html>".utf8))
        #expect(OwnPassword.outcome(of: strange) == .unknown(words: OwnPassword.unknownLine))
    }

    // MARK: a failure

    @Test func aRefusalIsSaidAsItCameWithItsKindAndFix() {
        let wrong = Self.refusal(409, #"{"detail":"That isn't your current password - the one you signed in to deadwax with. If you've changed it since, sign out and in again.","kind":"not_your_password","fix":null}"#)
        #expect(OwnPassword.outcome(of: wrong, admin: false) == .refused(
            words: "That isn't your current password - the one you signed in to deadwax with. If you've changed it since, sign out and in again.",
            kind: "not_your_password", fix: nil))
        // a 403 is the route's own words (EDITING_OFF), never the managing pages' NO_PERMISSION
        let editing = Self.refusal(403, #"{"detail":"Navidrome is set not to let people change their own details - an admin can change it in People, or turn on EnableUserEditing in Navidrome.","kind":"editing_off","fix":null}"#)
        if case .refused(let words, let kind, _) = OwnPassword.outcome(of: editing, admin: false) {
            #expect(words.hasPrefix("Navidrome is set not to let") && kind == "editing_off")
        } else {
            Issue.record("a 403 is a refusal")
        }
        // People's fix, kept
        let unset = Self.refusal(409, #"{"detail":"Navidrome isn't set up.","kind":"not_set_up","fix":"Server settings → Connections"}"#)
        #expect(OwnPassword.outcome(of: unset, admin: false) == .refused(words: "Navidrome isn't set up.", kind: "not_set_up",
                                                                         fix: "Server settings \u{2192} Connections"))
        // the form's 400, the limit's 429 (with no kind: auth.too_many), the strict model's 422 - each as it came
        for (status, json, words) in [
            (400, #"{"detail":"The two passwords aren't the same.","kind":"form","fix":null}"#, "The two passwords aren't the same."),
            (429, #"{"detail":"Too many tries - wait 20 seconds."}"#, "Too many tries - wait 20 seconds."),
            (422, #"{"detail":"deadwax couldn't read that form - reload the page and try again."}"#,
             "deadwax couldn't read that form - reload the page and try again."),
        ] {
            if case .refused(let said, _, nil) = OwnPassword.outcome(of: Self.refusal(status, json), admin: false) {
                #expect(said == words, "\(status)")
            } else {
                Issue.record("\(status) is a refusal")
            }
        }
        // a 4xx with no words of deadwax's: a listener's
        if case .refused(let said, nil, nil) = OwnPassword.outcome(of: Self.refusal(413, ""), admin: false) {
            #expect(!said.isEmpty)
        } else {
            Issue.record("a bare 413 is a refusal")
        }
    }

    @Test func whoeverRunsDeadwaxSeesItsWhy() {
        let explained = Self.refusal(409, #"{"detail":"Logins are off.","why":"AUTH_MODE is off.","kind":"off"}"#)
        #expect(OwnPassword.outcome(of: explained, admin: true) == .refused(words: "Logins are off. (AUTH_MODE is off.)",
                                                                            kind: "off", fix: nil))
        #expect(OwnPassword.outcome(of: explained, admin: false) == .refused(words: "Logins are off.", kind: "off", fix: nil))
    }

    @Test func a401IsTheSessionEnded() {
        let ended = Self.refusal(401, #"{"detail":"Your password was changed from another device - sign in with the new one."}"#)
        #expect(OwnPassword.outcome(of: ended, admin: false)
                == .signedOut(reason: "Your password was changed from another device - sign in with the new one."))
    }

    /// A 5xx with deadwax's words says whether it changed (TIMED_OUT, NOT_KEPT...): as it came. With none - a proxy's
    /// page - and no answer at all, it may have changed: the phone's words, the transport's in brackets for whoever
    /// runs deadwax.
    @Test func whatMayHaveChangedIsSaidSo() throws {
        let timedOut = Self.refusal(504, #"{"detail":"Navidrome didn't answer in time, so deadwax can't tell whether your password changed.","kind":"timed_out","fix":null}"#)
        #expect(OwnPassword.outcome(of: timedOut, admin: false) == .failed(
            words: "Navidrome didn't answer in time, so deadwax can't tell whether your password changed.", fix: nil))
        let notKept = Self.refusal(500, #"{"detail":"Navidrome changed your password, but deadwax couldn't keep the new one - sign out and sign in again with the new password.","kind":"not_kept"}"#)
        if case .failed(let words, nil) = OwnPassword.outcome(of: notKept, admin: false) {
            #expect(words.hasPrefix("Navidrome changed your password"))
        } else {
            Issue.record("NOT_KEPT is said as it came")
        }
        let proxy = Self.refusal(502, "<html>Bad Gateway</html>")
        #expect(OwnPassword.outcome(of: proxy, admin: false) == .unknown(words: OwnPassword.unknownLine))
        if case .unknown(let words) = OwnPassword.outcome(of: proxy, admin: true) {
            #expect(words.hasPrefix(OwnPassword.unknownLine + " (") && words.hasSuffix(")"))
        } else {
            Issue.record("a proxy's 502 may have changed it")
        }
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        let none = APIFailure.NoAnswer(server: server, method: "POST", path: "/me/password", reason: "The network connection was lost.", device: .iPhone)
        #expect(OwnPassword.outcome(of: APIFailure.offline(none), admin: false) == .unknown(words: OwnPassword.unknownLine))
        #expect(OwnPassword.outcome(of: APIFailure.timeout(none), admin: true)
                == .unknown(words: OwnPassword.unknownLine + " (The network connection was lost.)"))
        #expect(OwnPassword.unknownLine == "deadwax may have changed your password - its answer never came. If deadwax asks "
                + "you to sign in again, it did: sign in with the new password. If it doesn't, try again.")
        // a page left: nothing
        #expect(OwnPassword.outcome(of: CancellationError(), admin: false) == .cancelled)
        #expect(OwnPassword.outcome(of: URLError(.cancelled), admin: false) == .cancelled)
    }

    @Test func aFixIsReadFromAnyRefusal() {
        let fixed = Self.refusal(409, #"{"detail":"x","kind":"not_set_up","fix":"Server settings → Connections"}"#)
        #expect(fixed.fix == "Server settings \u{2192} Connections")
        #expect(Self.refusal(409, #"{"detail":"x","fix":7}"#).fix == nil)
        #expect(Self.refusal(409, #"{"detail":"x"}"#).fix == nil)
        #expect(Self.refusal(409, #"{"detail":"x","fix":"  "}"#).fix == "  ", "kept as it came; OwnPassword trims it")
        #expect(OwnPassword.outcome(of: Self.refusal(409, #"{"detail":"Navidrome isn't set up.","fix":"  "}"#), admin: false)
                == .refused(words: "Navidrome isn't set up.", kind: nil, fix: nil))
    }

    // MARK: the page's flow

    static let ready = OwnPasswordForm(current: "ethan-navidrome-pw", password: "a-fresh-own-password",
                                       again: "a-fresh-own-password")

    @Test func oneChangeAtATimeAndOnlyWhenReady() throws {
        var flow = OwnPasswordFlow()
        let none = flow.begin(user: "ethan", online: true, signInOver: false)
        #expect(none == nil, "nothing typed")
        flow.form = Self.ready
        let away = flow.begin(user: "ethan", online: false, signInOver: false)
        #expect(away == nil, "out of reach")
        #expect(!flow.canChange(user: "ethan", online: false, signInOver: false))
        // (review) the sign-in over the app: anything asked under it is a 401 for certain
        #expect(!flow.canChange(user: "ethan", online: true, signInOver: true))
        let under = flow.begin(user: "ethan", online: true, signInOver: true)
        #expect(under == nil && !flow.changing)
        #expect(flow.canChange(user: "ethan", online: true, signInOver: false))
        let begun = flow.begin(user: "ethan", online: true, signInOver: false)
        let (ticket, body) = try #require(begun)
        #expect(body == Self.body && flow.changing)
        // the ticket was taken before the Task: a second tap in the same turn finds one out
        let second = flow.begin(user: "ethan", online: true, signInOver: false)
        #expect(second == nil)
        #expect(!flow.canChange(user: "ethan", online: true, signInOver: false), "one out")
        // an older ticket's answer is dropped
        let older = flow.ended(ticket - 1, .changed(signedOut: 1, warning: nil, session: "s.x"), signInOver: false, device: .iPhone)
        #expect(older == nil && flow.changing)
        let told = flow.ended(ticket, .changed(signedOut: 1, warning: nil, session: "s.x"), signInOver: false, device: .iPhone)
        #expect(told == OwnPassword.doneWords(1))
        #expect(!flow.changing && flow.form.isEmpty)
        #expect(flow.said == .done(words: OwnPassword.doneWords(1), warning: nil))
        // and once over, the same ticket is nothing
        let late = flow.ended(ticket, .unknown(words: "late"), signInOver: false, device: .iPhone)
        #expect(late == nil)
    }

    @Test func eachOutcomeLeavesTheFieldsAsTheWebDoes() throws {
        func after(_ outcome: OwnPassword.Outcome) throws -> (OwnPasswordFlow, String?) {
            var flow = OwnPasswordFlow()
            flow.form = Self.ready
            let begun = flow.begin(user: "ethan", online: true, signInOver: false)
            let (ticket, _) = try #require(begun)
            let said = flow.ended(ticket, outcome, signInOver: false, device: .iPhone)
            return (flow, said)
        }
        // changed, with its warning: emptied, both said in one announcement
        let (changed, toldChanged) = try after(.changed(signedOut: 0, warning: "Couldn't check.", session: "s.y"))
        #expect(changed.form.isEmpty && toldChanged == OwnPassword.doneWords(0) + " Couldn't check.")
        // no new sign-in: emptied (the password changed), said with the warning or what to do
        let (renewed, _) = try after(.notRenewed(signedOut: 0, warning: nil))
        #expect(renewed.form.isEmpty && renewed.said == .done(words: OwnPassword.notRenewed(.iPhone), warning: OwnPassword.signInAgain))
        let (warned, _) = try after(.notRenewed(signedOut: 2, warning: "A copy would still work."))
        #expect(warned.said == .done(words: OwnPassword.notRenewed(.iPhone), warning: "A copy would still work."))
        // refused: kept to correct - the current one emptied and focused only when it was wrong
        let (wrong, _) = try after(.refused(words: "Not it.", kind: "not_your_password", fix: nil))
        #expect(wrong.form == OwnPasswordForm(current: "", password: Self.ready.password, again: Self.ready.again))
        #expect(wrong.focusCurrent == 1 && wrong.said == .problem(words: "Not it.", fix: nil))
        let (editing, toldEditing) = try after(.refused(words: "Editing is off.", kind: "editing_off", fix: "Turn it on."))
        #expect(editing.form == Self.ready && editing.focusCurrent == 0 && toldEditing == "Editing is off. Turn it on.")
        // a 5xx's words, and may-have-changed: kept (trying again is theirs)
        let (failed, _) = try after(.failed(words: "Timed out.", fix: nil))
        #expect(failed.form == Self.ready && failed.said == .problem(words: "Timed out.", fix: nil))
        let (unknown, toldUnknown) = try after(.unknown(words: OwnPassword.unknownLine))
        #expect(unknown.form == Self.ready && toldUnknown == OwnPassword.unknownLine)
        // the session ended: emptied, nothing said - the sign-in says it
        let (ended, toldEnded) = try after(.signedOut(reason: "Signed out."))
        #expect(ended.form.isEmpty && ended.said == nil && toldEnded == nil)
        let (cancelled, toldCancelled) = try after(.cancelled)
        #expect(cancelled.form == Self.ready && cancelled.said == nil && toldCancelled == nil && !cancelled.changing)
    }

    @Test func hiddenEmptiesTheFieldsButAChangeOutStaysOut() throws {
        var flow = OwnPasswordFlow()
        flow.form = Self.ready
        let begun = flow.begin(user: "ethan", online: true, signInOver: false)
        let (ticket, _) = try #require(begun)
        flow.hidden()
        #expect(flow.form.isEmpty && flow.changing)
        flow.form = Self.ready
        let second = flow.begin(user: "ethan", online: true, signInOver: false)
        #expect(second == nil, "no second change while one is out")
        let told = flow.ended(ticket, .changed(signedOut: 0, warning: nil, session: "s.z"), signInOver: false, device: .iPhone)
        #expect(told != nil)
        flow.hidden()
        #expect(flow.said == nil && flow.form.isEmpty)
    }

    @Test func typingAgainClearsWhatWasSaid() throws {
        var flow = OwnPasswordFlow()
        flow.form = Self.ready
        let begun = flow.begin(user: "ethan", online: true, signInOver: false)
        let (ticket, _) = try #require(begun)
        flow.typed()
        _ = flow.ended(ticket, .refused(words: "No.", kind: "form", fix: nil), signInOver: false, device: .iPhone)
        #expect(flow.said != nil)
        flow.typed()
        #expect(flow.said == nil)
    }

    /// (review) The sign-in come over the app as the change answered: the fields go as the outcome leaves them, and
    /// nothing is announced here - the sign-in says what happened, and two announcements would cut each other off.
    @Test func nothingIsAnnouncedUnderTheSignIn() throws {
        for outcome: OwnPassword.Outcome in [.changed(signedOut: 0, warning: nil, session: "s.n"),
                                             .refused(words: "No.", kind: "form", fix: nil),
                                             .unknown(words: OwnPassword.unknownLine)] {
            var flow = OwnPasswordFlow(), plain = OwnPasswordFlow()
            flow.form = Self.ready
            plain.form = Self.ready
            let begun = flow.begin(user: "ethan", online: true, signInOver: false)
            let begunPlain = plain.begin(user: "ethan", online: true, signInOver: false)
            let (ticket, _) = try #require(begun)
            let (ticketPlain, _) = try #require(begunPlain)
            let under = flow.ended(ticket, outcome, signInOver: true, device: .iPhone)
            let told = plain.ended(ticketPlain, outcome, signInOver: false, device: .iPhone)
            #expect(under == nil && told != nil, "\(outcome)")
            #expect(flow == plain, "the same fields and words either way: \(outcome)")
        }
    }

    // MARK: the hold on the sign-in

    @Test func aRekeyDropsWhatWasHeldAndAnythingElseSaysIt() {
        var rekey = PasswordRekey()
        let idle = rekey.holds(reason: "x", session: "s.old")
        #expect(!idle, "nothing out: a 401 is acted on")
        let first = rekey.began(under: "s.old"), again = rekey.began(under: "s.old")
        #expect(first && !again, "one at a time")
        #expect(rekey.under == .some("s.old"))
        let heldFirst = rekey.holds(reason: "first", session: "s.old")
        let heldSecond = rekey.holds(reason: "second", session: "s.old")
        #expect(heldFirst && heldSecond)
        let then = rekey.ended(.changed(signedOut: 0, warning: nil, session: "s.n"), device: .iPhone)
        #expect(then == .nothing)
        let after = rekey.holds(reason: "after", session: "s.n")
        #expect(!rekey.out && !after && rekey.under == nil)

        // the person or the address changed while it was out: let go, nothing held, the next one may go
        let again2 = rekey.began(under: "s.n")
        let held2 = rekey.holds(reason: "someone else's", session: "s.n")
        rekey.forgot()
        let afterForgot = rekey.holds(reason: "now", session: "s.n")
        #expect(again2 && held2 && !rekey.out && !afterForgot && rekey.under == nil)

        // the table: the outcome, a 401 held or not, what then - a change is re-keyed exactly when it changed, which
        // drops what was held; a held 401 after anything else but a refusal is said in the phone's words (the change
        // may have gone through: deadwax's would name another device); and an answer that leaves the session in doubt
        // asks /me, a cancelled request among them
        let ended = OwnPassword.endedWhileChanging(.iPhone)
        let cases: [(OwnPassword.Outcome, String??, PasswordRekey.After)] = [
            (.changed(signedOut: 0, warning: nil, session: "s"), nil, .nothing),
            (.changed(signedOut: 0, warning: nil, session: "s"), .some("the move's"), .nothing),
            (.notRenewed(signedOut: 0, warning: nil), nil, .askMe),
            (.notRenewed(signedOut: 0, warning: nil), .some("held"), .signIn(reason: ended)),
            (.refused(words: "No.", kind: "form", fix: nil), nil, .nothing),
            (.refused(words: "No.", kind: "form", fix: nil), .some("held"), .signIn(reason: "held")),
            (.refused(words: "No.", kind: "form", fix: nil), .some(nil), .signIn(reason: nil)),
            (.signedOut(reason: "its own"), nil, .signIn(reason: "its own")),
            (.signedOut(reason: "its own"), .some("held"), .signIn(reason: "its own")),
            (.failed(words: "Timed out.", fix: nil), nil, .askMe),
            (.failed(words: "Timed out.", fix: nil), .some("held"), .signIn(reason: ended)),
            (.unknown(words: "?"), nil, .askMe),
            (.unknown(words: "?"), .some("from another device"), .signIn(reason: ended)),
            (.cancelled, nil, .askMe),
            (.cancelled, .some("held"), .signIn(reason: ended)),
        ]
        for (outcome, held, then) in cases {
            var hold = PasswordRekey()
            _ = hold.began(under: "s.old")
            if let held { _ = hold.holds(reason: held, session: "s.old") }
            let after = hold.ended(outcome, device: .iPhone)
            #expect(after == then, "\(outcome), held \(String(describing: held))")
            #expect(!hold.out && hold.under == nil)
        }
    }

    /// (review) The hold is the session's it began under: a 401 that would end any other session - one signed in since,
    /// or none - is that session's own, and acted on.
    @Test func aHoldIsOnlyTheSessionsItBeganUnder() {
        let cases: [(began: String?, heard: String?, held: Bool)] = [
            ("s.old", "s.old", true),
            ("s.old", "s.new", false),
            ("s.old", nil, false),
            (nil, nil, true),
            (nil, "s.new", false),
        ]
        for (began, heard, held) in cases {
            var rekey = PasswordRekey()
            _ = rekey.began(under: began)
            let holds = rekey.holds(reason: "r", session: heard)
            #expect(holds == held, "began under \(String(describing: began)), heard under \(String(describing: heard))")
            // and one not held is not kept: the end says nothing of it
            let then = rekey.ended(.failed(words: "x", fix: nil), device: .iPhone)
            #expect(then == (held ? .signIn(reason: OwnPassword.endedWhileChanging(.iPhone)) : .askMe))
        }
    }

    /// (review) ServerModel's guard after the await: the answer is used only while the person, the address, the session
    /// and the open app all stand as the change was sent.
    @Test func anAnswerStandsOnlyWhileAllItWasSentUnderDoes() {
        let sent = PasswordRekey.Context(person: 3, address: "http://deadwax.test:8080", session: "s.old", ready: true)
        func now(person: Int = 3, address: String? = "http://deadwax.test:8080", session: String? = "s.old",
                 ready: Bool = true) -> PasswordRekey.Context {
            PasswordRekey.Context(person: person, address: address, session: session, ready: ready)
        }
        let cases: [(PasswordRekey.Context, Bool, String)] = [
            (now(), true, "all as sent"),
            (now(person: 4), false, "another person"),
            (now(address: "http://other.test:8080"), false, "another address"),
            (now(address: nil), false, "no address"),
            (now(session: "s.new"), false, "another session"),
            (now(session: nil), false, "signed out"),
            (now(ready: false), false, "the app not open"),
        ]
        for (at, stands, what) in cases {
            #expect(PasswordRekey.answerStands(sent: sent, now: at) == stands, "\(what)")
        }
        let unready = PasswordRekey.Context(person: 3, address: nil, session: nil, ready: false)
        #expect(!PasswordRekey.answerStands(sent: unready, now: unready), "never while the app isn't open")
    }

    @Test func aChangeOutKeepsTheSettingsPageThroughATabRetap() {
        // Settings > Account > Change password, and nothing over it
        #expect(OwnPassword.pagesKept([false, true], changing: true) == 2)
        #expect(OwnPassword.pagesKept([false, true], changing: false) == 0)
        #expect(OwnPassword.pagesKept([false, false], changing: true) == 0, "no Change password on the tab")
        #expect(OwnPassword.pagesKept([], changing: true) == 0)
        #expect(OwnPassword.pagesKept([false, true, false], changing: true) == 2, "a page over it still goes")
    }

    // MARK: the cookie a request carried

    @Test func theSessionARequestCarriedIsRead() {
        #expect(SessionCookie.value(fromCookie: "deadwax_session=s.abc") == "s.abc")
        #expect(SessionCookie.value(fromCookie: SessionCookie.header("s.x-Y_9")) == "s.x-Y_9")
        #expect(SessionCookie.value(fromCookie: "other=1; deadwax_session=s.two; more=3") == "s.two")
        #expect(SessionCookie.value(fromCookie: "not_deadwax_session=s.no") == nil)
        #expect(SessionCookie.value(fromCookie: "deadwax_session=") == nil)
        #expect(SessionCookie.value(fromCookie: "") == nil && SessionCookie.value(fromCookie: nil) == nil)
    }

    // MARK: no password said

    @Test func neitherTheFormNorTheBodySaysAPassword() {
        let form = Self.ready
        for said in [String(describing: form), String(reflecting: form), "\(form)", String(describing: Self.body),
                     String(reflecting: Self.body), "\(Self.body)"] {
            #expect(!said.contains("ethan-navidrome-pw") && !said.contains("a-fresh-own-password"), "\(said)")
        }
        var dumped = ""
        dump(form, to: &dumped)
        dump(Self.body, to: &dumped)
        #expect(!dumped.contains("navidrome-pw") && !dumped.contains("fresh-own"))
        #expect(Mirror(reflecting: Self.body).children.isEmpty && Mirror(reflecting: form).children.isEmpty)
    }

    /// Exactly the server model's three fields (OwnPasswordBody forbids any other: a 422).
    @Test func theBodyIsTheStrictModelsThreeFields() throws {
        let sent = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(Self.body))
        #expect(sent == ["current": "ethan-navidrome-pw", "password": "a-fresh-own-password",
                         "password_again": "a-fresh-own-password"])
    }

    // MARK: the client's call

    @Test func theChangeIsPostedWithTheSessionAndAnsweredWithTheNewOne() async throws {
        let (deadwax, transport) = client(session: "s.old")
        transport.answer(Self.route, 200, #"{"changed":true,"signed_out":1,"warning":null}"#,
                         headers: ["Set-Cookie": Self.cookie])
        let outcome = await deadwax.changeOwnPassword(Self.body, admin: false)
        #expect(outcome == .changed(signedOut: 1, warning: nil, session: "s.new-NEW_123"))
        let sent = try #require(transport.last)
        #expect(sent.method == "POST" && sent.url.path == Self.route && sent.url.query == nil)
        #expect(sent.headers["Cookie"] == "deadwax_session=s.old")
        #expect(sent.headers["Content-Type"] == "application/json")
        #expect(sent.timeout == Routes.timeouts[Routes.ownPassword] && sent.timeout == 240)
        let form = try JSONDecoder().decode([String: String].self, from: try #require(sent.body))
        #expect(form == ["current": "ethan-navidrome-pw", "password": "a-fresh-own-password",
                         "password_again": "a-fresh-own-password"])
        #expect(transport.sent.count == 1, "asked once")
    }

    @Test func aRefusalANoAnswerAndA401AreEachTheirOwn() async throws {
        let heard = SignedOutHeard()
        let (made, transport) = client(session: "s.old")
        var deadwax = made
        deadwax.onSignedOut = { failure, session in heard.hear(failure, session) }
        transport.answer(Self.route, 409, #"{"detail":"Navidrome says that isn't your current password - nothing changed.","kind":"wrong_current","fix":null}"#)
        #expect(await deadwax.changeOwnPassword(Self.body, admin: false)
                == .refused(words: "Navidrome says that isn't your current password - nothing changed.", kind: "wrong_current",
                            fix: nil))
        #expect(heard.all.isEmpty)
        transport.answer(Self.route, 401, #"{"detail":"Your session has ended. Sign in again."}"#)
        #expect(await deadwax.changeOwnPassword(Self.body, admin: false)
                == .signedOut(reason: "Your session has ended. Sign in again."))
        // the hook told, with the session it went out under - as every route's 401
        #expect(heard.all.count == 1 && heard.all.first?.1 == "s.old")
        transport.goAway()
        #expect(await deadwax.changeOwnPassword(Self.body, admin: false) == .unknown(words: OwnPassword.unknownLine))
        // never asked again by itself: one request each
        #expect(transport.sent.count == 3)
    }
}
