import Foundation
import Testing
@testable import DeadwaxCore

/// People's page as Core decides it (Phase 8, slice 11): who is offered it, the idle unlock, the read tickets, each
/// write from its tap to its re-read, a refusal of kind "locked", what a failure means, what is sent, and that no
/// password is ever said when printed or dumped.
@Suite struct PeopleFlowTests {
    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()

    static func answered(_ status: Int, _ detail: String? = nil, kind: String? = nil, fix: String? = nil,
                         path: String = "/people/create") -> APIFailure {
        .answered(.init(status: status, method: "POST", path: path, detail: detail, kind: kind, fix: fix))
    }

    static func ethan(admin: Bool = false, ticks: PeopleTicks? = PeopleTicks(request: true),
                      can: PeopleCan = PeopleCan()) -> PeoplePerson {
        PeoplePerson(id: "nd-ethan", user: "ethan", name: "Ethan", admin: admin, libraries: 1,
                     permissions: admin ? nil : ticks, can: can)
    }

    static let you = PeoplePerson(id: "nd-james", user: "james", name: "James", admin: true, you: true,
                                  can: PeopleCan(reset: "That's you - change your own password in You → Account → Change password.",
                                                 remove: "deadwax doesn't remove the account you're signed in with.",
                                                 admin: "You can't take away your own admin role.",
                                                 permissions: "That's you - an admin has every permission."))

    static func list(_ people: [PeoplePerson] = [you, ethan()], known: [PeopleKnownOnly] = []) -> PeopleState {
        PeopleState(on: true, available: true, locked: false, you: "james", account: "demo", people: people, knownOnly: known)
    }

    static let locked = PeopleState(on: true, available: true, locked: true, you: "james", account: "demo")

    /// A flow with the list read and landed.
    static func listed(_ state: PeopleState = list(), now: Double = 100) -> PeopleFlow {
        var flow = PeopleFlow()
        let ticket = flow.readBegan()
        _ = flow.readEnded(ticket, .answered(state), now: now)
        return flow
    }

    // MARK: who is offered it

    /// Manage's row: a Navidrome admin's with logins on (permissions.ts `managing().people`); the page itself opens on
    /// the permission alone, and says why it can't work with logins off.
    @Test func whoIsOfferedPeople() {
        let cases: [(Access, offered: Bool, allowed: Bool)] = [
            (Access(user: "james", permissions: Access.all, on: true, unverified: false, admin: true), true, true),
            (Access(user: "local", permissions: Access.all, on: false, unverified: false, admin: true), false, true),
            (Access(user: "ethan", permissions: [.request, .edit], on: true, unverified: false, admin: false), false, false),
            (Access(user: "ethan", permissions: [], on: true, unverified: false, admin: false), false, false),
            (Access(user: "deadwax", permissions: Access.all, on: true, unverified: false, admin: true), true, true),
            (Access(user: "maya", permissions: [.people], on: true, unverified: false, admin: false), true, true),
            (Access(user: "maya", permissions: [.people], on: false, unverified: false, admin: false), false, true),
        ]
        for (access, offered, allowed) in cases {
            #expect(People.offered(access) == offered, "\(access.user), on \(access.on): offered")
            #expect(People.allowed(access) == allowed, "\(access.user), on \(access.on): allowed")
            #expect(Managing.tools(access).contains(.people) == offered, "\(access.user): Manage's row")
        }
        let native = Managing.Tool.allCases.filter(\.native)
        #expect(native == Managing.Tool.allCases, "nothing in Manage opens Safari")
        #expect(ManagingWords.footer(loginsOn: true, online: true).isEmpty)
        #expect(ManagingWords.footer(loginsOn: true, online: false).isEmpty)
    }

    // MARK: the idle unlock

    @Test func theIdleCheckComesAfterTheServersUnlockRunsOut() {
        #expect(People.unlockIdleSeconds == Double(People.unlockIdleMinutes * 60))
        #expect(People.idleCheckSeconds > People.unlockIdleSeconds)
        #expect(!People.idleDue(answeredAt: nil, now: 10_000))
        #expect(!People.idleDue(answeredAt: 100, now: 100 + People.idleCheckSeconds - 0.001))
        #expect(People.idleDue(answeredAt: 100, now: 100 + People.idleCheckSeconds))
        var flow = Self.listed(now: 100)
        #expect(flow.answeredAt == 100 && flow.idleDue(now: 100 + People.idleCheckSeconds))
        // a write's answer is a use of the unlock: the clock starts again
        let (ticket, _) = flow.beginForget(PeopleKnownOnly(user: "gone"), online: true, signInOver: false)!
        _ = flow.ended(ticket, .done(.forgot), now: 500, signInOver: false, origin: "")
        #expect(flow.answeredAt == 500 && !flow.idleDue(now: 100 + People.idleCheckSeconds))
        // locked: nothing to check
        var locked = PeopleFlow()
        let read = locked.readBegan()
        _ = locked.readEnded(read, .answered(Self.locked), now: 100)
        #expect(locked.answeredAt == nil && !locked.idleDue(now: 100_000))
    }

    // MARK: reads

    @Test func onlyTheNewestReadLandsAndNothingWritesBeforeOne() {
        var flow = PeopleFlow()
        #expect(flow.view == .asking && !flow.canWrite(online: true, signInOver: false))
        let first = flow.readBegan(), second = flow.readBegan()
        #expect(flow.readEnded(first, .answered(Self.list()), now: 1) == nil, "an older read is dropped")
        #expect(flow.view == .asking)
        #expect(flow.readEnded(second, .answered(Self.list()), now: 1) == false)
        #expect(flow.view == .list && flow.real && flow.canWrite(online: true, signInOver: false))
        #expect(!flow.canWrite(online: false, signInOver: false) && !flow.canWrite(online: true, signInOver: true))
        _ = flow.readBegan()
        #expect(!flow.canWrite(online: true, signInOver: false), "nothing writes while a read is out")
        var gone = Self.listed()
        gone.outOfReach()
        #expect(!gone.real && !gone.canWrite(online: true, signInOver: false), "out of reach: a read must land again")
    }

    @Test func aFailedReadSaysSoAndA403AsksMeAgain() {
        var flow = PeopleFlow()
        let ticket = flow.readBegan()
        let read = People.readOutcome(of: Self.answered(500, nil, path: "/people"), admin: false)
        guard case .failed(let words, false) = read else {
            Issue.record("a 500 is a failed read: \(read)")
            return
        }
        #expect(words.hasPrefix(People.readFailed))
        #expect(flow.readEnded(ticket, read, now: 1) == false && flow.readProblem == words && flow.view == .asking)
        let refused = People.readOutcome(of: Self.answered(403, "That's People.", path: "/people"), admin: false)
        #expect(refused == .failed(words: People.peopleOnly, askMe: true))
        #expect(People.readOutcome(of: Self.answered(401, nil, path: "/people"), admin: false) == .signedOut)
        #expect(People.readOutcome(of: CancellationError(), admin: false) == .cancelled)
        // Navidrome saying they aren't one of its admins any more: /me asked again
        var notAdmin = PeopleFlow()
        let asked = notAdmin.readBegan()
        let answer = PeopleState(on: true, available: false, locked: false, problem: "Navidrome says you aren't its admin.",
                                 you: "james")
        #expect(notAdmin.readEnded(asked, .answered(answer), now: 1) == true && notAdmin.view == .unavailable)
    }

    // MARK: unlock

    @Test func unlockSendsThePasswordAndKeepsNone() {
        var flow = PeopleFlow()
        let read = flow.readBegan()
        _ = flow.readEnded(read, .answered(Self.locked), now: 1)
        #expect(flow.view == .locked && !flow.canUnlock(online: true, signInOver: false), "nothing typed, no Unlock")
        flow.unlockPassword = "james-navidrome-pw"
        #expect(flow.canUnlock(online: true, signInOver: false) && !flow.canUnlock(online: true, signInOver: true))
        let (ticket, body) = flow.beginUnlock(online: true, signInOver: false)!
        #expect(body.password == "james-navidrome-pw" && flow.unlockPassword.isEmpty, "emptied as it is sent")
        #expect(flow.beginUnlock(online: true, signInOver: false) == nil, "one at a time")
        let after = flow.ended(ticket, .refused(words: "That isn't the password you signed in with.", kind: "not_your_password",
                                                fix: nil, askMe: false), now: 2, signInOver: false, origin: "")
        #expect(after == PeopleAfter(announce: "That isn't the password you signed in with.", askMe: false, read: true))
        #expect(flow.focusUnlock == 1 && flow.said(at: .unlock)?.problem == true && flow.view == .locked)
        flow.typed(at: .unlock)
        #expect(flow.said == nil, "typing again clears what was said of the last try")
        flow.unlockPassword = "right-one-now"
        let (again, _) = flow.beginUnlock(online: true, signInOver: false)!
        let done = flow.ended(again, .done(.unlocked), now: 3, signInOver: false, origin: "")
        #expect(done?.read == true && done?.announce == nil && flow.said == nil, "the list read again says it")
        #expect(flow.ended(again, .done(.unlocked), now: 3, signInOver: false, origin: "") == nil, "once")
    }

    @Test func lockShowsUnlockPeopleAtOnce() {
        var flow = Self.listed()
        flow.add = PeopleAddForm(user: "maya", name: "Maya", password: "maya-pass-1", again: "maya-pass-1")
        let ticket = flow.beginLock(online: true, signInOver: false)!
        _ = flow.ended(ticket, .done(.locked), now: 2, signInOver: false, origin: "")
        #expect(flow.view == .locked && flow.state?.people.isEmpty == true)
        #expect(flow.add.user == "maya" && flow.add.password.isEmpty && flow.add.again.isEmpty)
    }

    // MARK: a refusal of kind "locked"

    /// The unlock ran out (or Navidrome asked for the password again): Unlock People back at once, nobody listed, every
    /// password emptied - and what's safe to keep kept: a new person's names, the name typed to remove someone, each
    /// person's unsaved ticks.
    @Test func lockedAgainKeepsWhatsSafeAndNoPassword() {
        var flow = Self.listed()
        let ethan = Self.ethan()
        flow.tick(ethan, .edit, true)
        flow.open(.add)
        flow.add = PeopleAddForm(user: "maya", name: "Maya", password: "maya-pass-1", again: "maya-pass-1")
        let (ticket, body) = flow.beginCreate(online: true, signInOver: false)!
        #expect(body.user == "maya" && body.password == "maya-pass-1")
        let words = "Unlock People with your Navidrome password."
        let after = flow.ended(ticket, People.outcome(of: Self.answered(409, words, kind: "locked"), failed: People.createFailed,
                                                      admin: true),
                               now: 2, signInOver: false, origin: "")
        #expect(after?.read == true && after?.announce == words)
        #expect(flow.view == .locked && flow.state?.people.isEmpty == true && flow.state?.knownOnly.isEmpty == true)
        #expect(flow.add.user == "maya" && flow.add.name == "Maya")
        #expect(flow.add.password.isEmpty && flow.add.again.isEmpty && flow.unlockPassword.isEmpty)
        #expect(flow.sheet == .add && flow.said(at: .add)?.words == words)
        #expect(flow.drafts["nd-ethan"]?.ticks.edit == true, "the ticks wait for the list")
        #expect(!flow.canCreate(online: true, signInOver: false), "nothing writes until it is unlocked again")
        // unlocked again, the same list: the ticks are still there to save
        let read = flow.readBegan()
        _ = flow.readEnded(read, .answered(Self.list()), now: 3)
        #expect(flow.dirty(ethan) && flow.ticks(for: ethan)?.edit == true)
    }

    // MARK: each write, and its re-read

    @Test func makeAccountSaysWhatToTellThemAndEmptiesTheForm() {
        var flow = Self.listed()
        flow.open(.add)
        flow.add = PeopleAddForm(user: " Maya ", name: " Maya Long ", password: "maya-pass-1", again: "maya-pass-1")
        #expect(flow.canCreate(online: true, signInOver: false))
        let (ticket, body) = flow.beginCreate(online: true, signInOver: false)!
        #expect(body.user == "maya" && body.name == "Maya Long" && body.passwordAgain == "maya-pass-1")
        #expect(flow.writing(.create) && !flow.canWrite(online: true, signInOver: false))
        let origin = People.origin(Self.server)
        let after = flow.ended(ticket, .done(.made(user: "maya", warning: "Navidrome gives them no library.")), now: 2,
                               signInOver: false, origin: origin)!
        let said = flow.said(at: .add)!
        #expect(said.words == People.madeWords("maya", origin: "http://192.168.3.20:8090") && !said.problem)
        #expect(said.warning == "Navidrome gives them no library.")
        #expect(after.announce == said.words + " Navidrome gives them no library." && after.read && !after.askMe)
        #expect(flow.add.isEmpty && flow.sheet == .add && !flow.real, "the form emptied; the list is read again first")
        // an answer naming nobody says the name sent
        var unnamed = Self.listed()
        unnamed.add = PeopleAddForm(user: "zoe", password: "zoe-pass-12", again: "zoe-pass-12")
        let (again, _) = unnamed.beginCreate(online: true, signInOver: false)!
        _ = unnamed.ended(again, .done(.made(user: "", warning: nil)), now: 2, signInOver: false, origin: "http://x")
        #expect(unnamed.said?.words == People.madeWords("zoe", origin: "http://x"))
    }

    @Test func resetSaysWhoWasSignedOutAndKeepsNoPassword() {
        var flow = Self.listed()
        let ethan = Self.ethan()
        flow.open(.reset(ethan.id))
        flow.resetPasswords = PeoplePasswords(password: "ethan-new-pw", again: "ethan-new-pw")
        #expect(flow.canReset(ethan, online: true, signInOver: false))
        #expect(!flow.canReset(Self.you, online: true, signInOver: false), "refused for you, and not your sheet")
        let (ticket, body) = flow.beginReset(ethan, online: true, signInOver: false)!
        #expect(body.user == "ethan" && body.password == "ethan-new-pw" && body.passwordAgain == "ethan-new-pw")
        _ = flow.ended(ticket, .done(.reset(user: "ethan", signedOut: 2)), now: 2, signInOver: false, origin: "")
        #expect(flow.resetPasswords.isEmpty && flow.sheet == nil)
        #expect(flow.said(at: .person(ethan.id))?.words == People.resetWords("ethan", signedOut: 2))
    }

    @Test func theFlipAsksMeAgainWhateverCameOfIt() {
        var flow = Self.listed()
        let ethan = Self.ethan()
        let (ticket, body) = flow.beginFlip(ethan, online: true, signInOver: false)!
        #expect(body == PeopleAdminBody(user: "ethan", admin: true))
        let after = flow.ended(ticket, .done(.admin(user: "ethan", admin: true)), now: 2, signInOver: false, origin: "")
        #expect(after?.askMe == true && flow.said(at: .person(ethan.id))?.words == "ethan is an admin now.")
        var failed = Self.listed()
        let (again, _) = failed.beginFlip(ethan, online: true, signInOver: false)!
        let unknown = failed.ended(again, .unknown(words: EditWords.mayHaveFinished), now: 2, signInOver: false, origin: "")
        #expect(unknown?.askMe == true && unknown?.read == true)
        var yours = Self.listed()
        #expect(yours.beginFlip(Self.you, online: true, signInOver: false) == nil, "you can't flip yourself")
    }

    @Test func removeLeavesTheirPage() {
        var flow = Self.listed()
        let ethan = Self.ethan()
        flow.tick(ethan, .server, true)
        flow.open(.remove(ethan.id))
        flow.removeTyped = "Ethan"
        #expect(!flow.canRemove(ethan, online: true, signInOver: false), "another case isn't their name")
        flow.removeTyped = "ethan"
        var yours = Self.listed()
        yours.open(.remove(Self.you.id))
        yours.removeTyped = "james"
        #expect(yours.beginRemove(Self.you, online: true, signInOver: false) == nil, "nor can you remove yourself")
        let (ticket, body) = flow.beginRemove(ethan, online: true, signInOver: false)!
        #expect(body == PeopleRemoveBody(user: "ethan", confirm: "ethan"))
        let after = flow.ended(ticket, .done(.removed), now: 2, signInOver: false, origin: "")
        #expect(after?.leave == ethan.id && flow.sheet == nil && flow.removeTyped.isEmpty && flow.drafts.isEmpty)
        #expect(flow.said(at: .list)?.words == People.removed("ethan"))
    }

    @Test func forgetAndSaveSayWhatTheWebSays() {
        var flow = Self.listed(Self.list(known: [PeopleKnownOnly(user: "gone", library: 3)]))
        let (ticket, body) = flow.beginForget(flow.state!.knownOnly[0], online: true, signInOver: false)!
        #expect(body == PeopleForgetBody(user: "gone"))
        let refused = People.outcome(of: Self.answered(404, "deadwax keeps nothing for gone.", kind: "not_found"),
                                     failed: People.forgetFailed, admin: false)
        _ = flow.ended(ticket, refused, now: 2, signInOver: false, origin: "")
        #expect(flow.said(at: .known("gone"))?.words == "deadwax keeps nothing for gone." && flow.view == .list)
        // Save: only a change, all five sent
        var save = Self.listed()
        let ethan = Self.ethan()
        #expect(!save.canSave(ethan, online: true, signInOver: false), "nothing changed")
        save.tick(ethan, .library, true)
        #expect(save.canSave(ethan, online: true, signInOver: false))
        let (saved, sent) = save.beginSave(ethan, online: true, signInOver: false)!
        #expect(sent == PeoplePermissionsBody(user: "ethan", PeopleTicks(request: true, library: true)))
        _ = save.ended(saved, .done(.saved), now: 2, signInOver: false, origin: "")
        #expect(save.said(at: .person(ethan.id))?.words == People.savedWords("ethan"))
        // the list read again with the saved ticks: the draft goes
        let read = save.readBegan()
        _ = save.readEnded(read, .answered(Self.list([Self.you, Self.ethan(ticks: PeopleTicks(request: true, library: true))])),
                           now: 3)
        #expect(save.drafts.isEmpty)
        // an admin's boxes and a refused row's can't be ticked
        var admin = Self.listed()
        admin.tick(Self.you, .edit, true)
        #expect(admin.drafts.isEmpty && !People.savesPermissions(Self.you))
    }

    @Test func aWriteEndingUnderTheSignInSaysNothingAndA401ReadsNothing() {
        var flow = Self.listed()
        let (ticket, _) = flow.beginForget(PeopleKnownOnly(user: "gone"), online: true, signInOver: false)!
        let after = flow.ended(ticket, .done(.forgot), now: 2, signInOver: true, origin: "")
        #expect(after?.announce == nil && after?.read == true, "the sign-in says what happened")
        var signedOut = Self.listed()
        signedOut.open(.add)
        signedOut.add = PeopleAddForm(user: "maya", password: "maya-pass-1", again: "maya-pass-1")
        let (create, _) = signedOut.beginCreate(online: true, signInOver: false)!
        let ended = signedOut.ended(create, People.outcome(of: Self.answered(401, "Signed out."), failed: "", admin: false),
                                    now: 2, signInOver: false, origin: "")
        #expect(ended?.read == false && ended?.announce == nil && signedOut.add.password.isEmpty)
        #expect(signedOut.sheet == nil, "a sheet would stand over the sign-in")
        #expect(signedOut.add.user == "maya", "the names are safe to keep")
        var cancelled = Self.listed()
        let lock = cancelled.beginLock(online: true, signInOver: false)!
        #expect(cancelled.ended(lock, .cancelled, now: 2, signInOver: false, origin: "")?.read == true)
    }

    @Test func theSignInComingPutsTheSheetAwayButNotUnderAWrite() {
        var flow = Self.listed()
        flow.tick(Self.ethan(), .edit, true)
        flow.open(.remove(Self.ethan().id))
        flow.removeTyped = "eth"
        flow.unlockPassword = "typed"
        flow.signInCame()
        #expect(flow.sheet == nil && flow.removeTyped.isEmpty && flow.unlockPassword.isEmpty)
        #expect(flow.drafts[Self.ethan().id] != nil, "each person's ticks are safe to keep")
        var writing = Self.listed()
        writing.open(.add)
        writing.add = PeopleAddForm(user: "maya", password: "maya-pass-1", again: "maya-pass-1")
        _ = writing.beginCreate(online: true, signInOver: false)!
        writing.signInCame()
        #expect(writing.sheet == .add, "the write out says what came of it there")
        #expect(writing.add.password.isEmpty && writing.add.again.isEmpty)
    }

    // MARK: what a failure means

    @Test func eachFailureIsWhatItMeans() throws {
        let offline = APIFailure.offline(.init(server: Self.server, method: "POST", path: "/people/create", reason: "The network connection was lost."))
        let timeout = APIFailure.timeout(.init(server: Self.server, method: "POST", path: "/people/create", reason: "timed out"))
        let cases: [(any Error, PeopleOutcome)] = [
            (Self.answered(409, "Unlock People with your Navidrome password.", kind: "locked"),
             .refused(words: "Unlock People with your Navidrome password.", kind: "locked", fix: nil, askMe: false)),
            (Self.answered(403, "That's People, which only Navidrome's admins can use."),
             .refused(words: People.peopleOnly, kind: nil, fix: nil, askMe: true)),
            (Self.answered(403, "Navidrome says you aren't its admin.", kind: "not_admin", fix: "Ask an admin."),
             .refused(words: "Navidrome says you aren't its admin.", kind: "not_admin", fix: "Ask an admin.", askMe: true)),
            (Self.answered(400, "That's you - change your own password in You → Account → Change password.", kind: "yourself"),
             .refused(words: "That's you - change your own password in Settings → Account → Change password.",
                      kind: "yourself", fix: nil, askMe: false)),
            (Self.answered(429, "That's a lot of changes at once - wait a minute.", kind: "busy"),
             .refused(words: "That's a lot of changes at once - wait a minute.", kind: "busy", fix: nil, askMe: false)),
            (Self.answered(504, "Navidrome didn't answer in time - it may have made the account.", kind: "timed_out"),
             .failed(words: "Navidrome didn't answer in time - it may have made the account.", fix: nil)),
            (Self.answered(500, "deadwax couldn't forget them.", kind: nil),
             .failed(words: "deadwax couldn't forget them.", fix: nil)),
            (Self.answered(502), .unknown(words: EditWords.mayHaveFinished)),
            (offline, .unknown(words: EditWords.mayHaveFinished)),
            (timeout, .unknown(words: EditWords.mayHaveFinished)),
            (Self.answered(401, "Signed out."), .signedOut),
            (CancellationError(), .cancelled),
        ]
        for (error, expected) in cases {
            #expect(People.outcome(of: error, failed: People.createFailed, admin: false) == expected, "\(error)")
        }
        // whoever runs deadwax reads the transport's own words in brackets
        guard case .unknown(let words) = People.outcome(of: offline, failed: People.createFailed, admin: true) else {
            Issue.record("offline is unknown")
            return
        }
        #expect(words.hasPrefix(EditWords.mayHaveFinished + " (") && words.hasSuffix(")"))
        // a refusal with no kind of People's: deadwax's words in a sentence, the web's sayError
        let plain = People.outcome(of: Self.answered(400, "Type a user name"), failed: People.createFailed, admin: false)
        #expect(plain == .refused(words: "Type a user name.", kind: nil, fix: nil, askMe: false))
    }

    @Test func thePhonesPlaceForChangePassword() {
        #expect(People.onPhone("change it in You → Account → Change password.") == "change it in Settings → Account → Change password.")
        #expect(People.onPhone("nothing to change") == "nothing to change")
        #expect(People.onPhone(nil as String?) == nil)
        let you = Self.you
        #expect(People.refusals(you).map(People.onPhone).first == "That's you - change your own password in Settings → Account → Change password.")
    }

    // MARK: what is sent

    @Test func eachBodyIsWhatTheServerTakes() throws {
        func keys(_ value: some Encodable) throws -> [String] {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
            return (object ?? [:]).keys.sorted()
        }
        #expect(try keys(PeopleUnlockBody(password: "p")) == ["password"])
        #expect(String(decoding: try JSONEncoder().encode(PeopleLockBody()), as: UTF8.self) == "{}")
        #expect(try keys(PeopleCreateBody(PeopleAddForm(user: "a", name: "b", password: "c", again: "d")))
                == ["name", "password", "password_again", "user"])
        #expect(try keys(PeopleResetBody(user: "a", PeoplePasswords(password: "b", again: "c")))
                == ["password", "password_again", "user"])
        #expect(try keys(PeopleAdminBody(user: "a", admin: true)) == ["admin", "user"])
        #expect(try keys(PeopleRemoveBody(user: "a", confirm: "a")) == ["confirm", "user"])
        #expect(try keys(PeopleForgetBody(user: "a")) == ["user"])
        #expect(try keys(PeoplePermissionsBody(user: "a", PeopleTicks())) == ["downloads", "edit", "library", "request",
                                                                           "server", "user"])
    }

    /// No password in what the flow, a form or a body says when printed, dumped or reflected.
    @Test func noPasswordIsEverSaid() {
        var flow = Self.listed()
        flow.unlockPassword = "secret-unlock-pw"
        flow.add = PeopleAddForm(user: "maya", name: "Maya", password: "secret-new-pw", again: "secret-new-pw")
        flow.resetPasswords = PeoplePasswords(password: "secret-reset-pw", again: "secret-reset-pw")
        let things: [Any] = [flow, flow.add, flow.resetPasswords, PeopleUnlockBody(password: "secret-unlock-pw"),
                             PeopleCreateBody(flow.add), PeopleResetBody(user: "ethan", flow.resetPasswords)]
        for thing in things {
            var dumped = ""
            dump(thing, to: &dumped)
            for said in [String(describing: thing), String(reflecting: thing), dumped] {
                #expect(!said.contains("secret"), "\(type(of: thing)) says a password")
            }
            #expect(Mirror(reflecting: thing).children.isEmpty, "\(type(of: thing)) reflects its fields")
        }
    }

    @Test func passwordsGoWhenThePageGoes() {
        var flow = Self.listed()
        flow.unlockPassword = "a"
        flow.add = PeopleAddForm(user: "maya", name: "Maya", password: "b", again: "c")
        flow.resetPasswords = PeoplePasswords(password: "d", again: "e")
        flow.hidden()
        #expect(flow.unlockPassword.isEmpty && flow.add.password.isEmpty && flow.add.again.isEmpty && flow.resetPasswords.isEmpty)
        #expect(flow.add.user == "maya", "Now Playing over it keeps the names")
        flow.open(.remove("nd-ethan"))
        flow.removeTyped = "eth"
        flow.closed()
        #expect(flow.sheet == nil && flow.removeTyped.isEmpty)
        let old = flow.readBegan()
        flow.left()
        #expect(flow.state == nil && flow.add.isEmpty && flow.drafts.isEmpty && flow.view == .asking)
        #expect(flow.readEnded(old, .answered(Self.list()), now: 1) == nil, "a read from before is dropped")
    }

    // MARK: the list

    @Test func theListIsKeyedByIdAndFailsClosed() throws {
        let json = #"""
        {"on": true, "available": true, "you": "james", "people": [
          {"id": "nd-1", "user": "ethan", "name": ""},
          {"id": "nd-1", "user": "ethan-again"},
          {"id": "", "user": "nobody"},
          {"user": "no-id"},
          {"id": "nd-2", "user": "maya", "admin": true, "can": {"reset": null, "remove": 7}}
        ], "known_only": [{"user": "gone"}, {"user": "gone"}, {"user": ""}]}
        """#
        let state = try JSONDecoder().decode(PeopleState.self, from: Data(json.utf8))
        #expect(state.locked, "an answer that doesn't say it is unlocked is locked")
        #expect(state.people.map(\.id) == ["nd-1", "nd-2"] && state.people[0].name == "ethan")
        #expect(state.people[1].can == PeopleCan() && state.knownOnly.map(\.user) == ["gone"])
        #expect(People.view(state) == .locked && state.lockedAgain.people.isEmpty)
    }

    // MARK: the waits

    @Test func eachWaitIsTheServersWorstCaseRoundedUp() {
        let writes: [(PeopleWrite.Kind, Endpoint)] = [(.create, Routes.createPerson), (.reset, Routes.resetPassword),
                                                       (.admin, Routes.setAdmin), (.remove, Routes.removePerson),
                                                       (.forget, Routes.forgetPerson), (.permissions, Routes.savePermissions)]
        for (kind, endpoint) in writes {
            #expect(Routes.timeouts[endpoint] == PeopleWaits.write(kind), "\(kind)")
        }
        #expect(PeopleWaits.longestWrite == PeopleWaits.work(.reset) && PeopleWaits.longestWrite == 130)
        #expect(Routes.timeouts[Routes.unlockPeople] == EditWaits.wait(PeopleWaits.unlock, floor: nil))
        #expect(Routes.timeouts[Routes.lockPeople] == nil)
        #expect(PeopleWaits.read(accounts: 0) == 120 && PeopleWaits.read(accounts: 2) == 120)
        #expect(PeopleWaits.read(accounts: 4) == 180 && PeopleWaits.read(accounts: 20) == 660)
    }

    @Test func theTabKeepsPeoplesPagesOnlyWhileAWriteIsOut() {
        #expect(People.pagesKept([true, true], writing: false) == 0)
        #expect(People.pagesKept([true, true], writing: true) == 2)
        #expect(People.pagesKept([false, true, false], writing: true) == 2)
        #expect(People.pagesKept([false], writing: true) == 0)
    }

    @Test func aFieldKeepsWholeCharactersThatFit() {
        #expect(People.clipped("ethan", to: 40) == "ethan")
        #expect(People.clipped(String(repeating: "a", count: 41), to: 40).utf16.count == 40)
        #expect(People.clipped("ab\u{1F642}", to: 3) == "ab", "never half a character")
        #expect(People.userField == 40 && People.displayField == 72 && People.passwordField == 136)
    }
}
