import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/people/people-vectors.json: the web's lib/people.ts and lib/permissions.ts run as they are, and
/// app/People.tsx's, UnlockPeople.tsx's, AddPerson.tsx's, ResetPassword.tsx's, RemovePerson.tsx's, usePeople.ts's and
/// api/people.ts's own read out of their source - replayed here through People, case for case
/// (notes/ios-specs/phase8-managing.md 10). Every string is compared as JavaScript compares it, unit for unit; each
/// row is the server's shape, decoded by the phone's own model first.
@Suite struct PeopleVectorTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("people/people-vectors.json"))

    static func person(_ web: Web) -> PeoplePerson { EditVectorTests.decoded(PeoplePerson.self, web) }

    @Test func theFixtureIsThere() {
        #expect(fixture["made_by"].string == "ios/scripts/export-people-vectors.cjs")
        expectMadeFrom(fixture, ["ui/src/lib/people.ts", "ui/src/lib/permissions.ts",
                                 "ui/src/app/People.tsx only the actions not refused, drawn",
                                 "ui/src/app/People.tsx the flip's question",
                                 "ui/src/app/People.tsx who has Save permissions",
                                 "ui/src/app/People.tsx a fresh list puts the draft back",
                                 "ui/src/app/UnlockPeople.tsx the password emptied whatever the answer",
                                 "ui/src/app/AddPerson.tsx the body sent",
                                 "ui/src/app/AddPerson.tsx locked: the passwords emptied, the names kept",
                                 "ui/src/app/ResetPassword.tsx what shows while typing, and when Reset can be pressed",
                                 "ui/src/app/RemovePerson.tsx Enter never confirms",
                                 "ui/src/app/usePeople.ts a refusal's words, and the kind that locks",
                                 "ui/src/app/usePeople.ts locked again: nobody listed, then asked again",
                                 "ui/src/api/people.ts setAdmin's route"])
        #expect(fixture["made_from"].keys.count == 77)
        #expect(fixture["names"].list.count == 170)
        #expect(fixture["displays"].list.count == 168)
        #expect(fixture["forms"].list.count == 187)
        #expect(fixture["resets"].list.count == 114)
        #expect(fixture["people"].list.count == 124)
        #expect(fixture["known"].list.count == 52)
    }

    // MARK: the words, and the page's own

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        let diffs = ScreenDiffs()
        diffs.number("NAME_MAX", Double(People.nameMax), words["NAME_MAX"])
        diffs.number("DISPLAY_MAX", Double(People.displayMax), words["DISPLAY_MAX"])
        diffs.number("PASSWORD_MIN", Double(OwnPassword.passwordMin), words["PASSWORD_MIN"])
        diffs.number("PASSWORD_MAX", Double(OwnPassword.passwordMax), words["PASSWORD_MAX"])
        diffs.number("UNLOCK_IDLE_MINUTES", Double(People.unlockIdleMinutes), words["UNLOCK_IDLE_MINUTES"])
        diffs.number("the idle seconds", People.unlockIdleSeconds, .number(Double(People.unlockIdleMinutes * 60)))
        diffs.check("RESERVED", People.reserved, words["RESERVED"].list.compactMap(\.string))
        diffs.text("TESTED_NAVIDROME", People.testedNavidrome, words["TESTED_NAVIDROME"])
        diffs.text("UNLOCK_TITLE", People.unlockTitle, words["UNLOCK_TITLE"])
        diffs.text("UNLOCKED_LINE", People.unlockedLine, words["UNLOCKED_LINE"])
        diffs.text("HTTP_NOTE", OwnPassword.httpNoteWords, words["HTTP_NOTE"])
        diffs.text("SHARING_DOC", People.sharingDoc, words["SHARING_DOC"])
        diffs.text("KNOWN_ONLY_TITLE", People.knownOnlyTitle, words["KNOWN_ONLY_TITLE"])
        diffs.text("KNOWN_ONLY_LINE", People.knownOnlyLine, words["KNOWN_ONLY_LINE"])
        diffs.check("CATEGORIES", People.categories.map(\.rawValue), words["CATEGORIES"].list.compactMap(\.string))
        for permission in Access.Permission.allCases {
            diffs.text("LABELS.\(permission)", People.label(permission), words["LABELS"][permission.rawValue])
        }
        for category in People.categories {
            diffs.text("LINES.\(category)", People.line(category), words["LINES"][category.rawValue])
        }
        diffs.text("PEOPLE_LINE", People.peopleLine, words["PEOPLE_LINE"])
        diffs.text("ADMINS_EVERYTHING", People.adminsEverything, words["ADMINS_EVERYTHING"])
        diffs.text("WARN_SERVER", People.warnServer, words["WARN_SERVER"])
        diffs.text("WARN_LIBRARY", People.warnLibrary, words["WARN_LIBRARY"])
        diffs.text("WARN_NO_REQUEST", People.warnNoRequest, words["WARN_NO_REQUEST"])
        diffs.text("PEOPLE_ONLY", People.peopleOnly, words["PEOPLE_ONLY"])
        diffs.done()
    }

    /// The labels, buttons and titles the pages say, the web's own - but one departure, pinned: Reset's second field
    /// says "Again" under New password on a page you look at; read alone by VoiceOver, as a Form's row, it says nothing
    /// (Change password's own departure). A web label changed fails here.
    @Test func thePagesWordsAreTheWebs() {
        let page = fixture["page"]
        let diffs = ScreenDiffs()
        diffs.text("Lock", People.lock, page["lock"])
        diffs.text("the list's title", People.everyone, page["everyone"])
        diffs.text("Sharing deadwax", People.sharing, page["sharing"])
        diffs.text("the flip's Keep", People.keepAsItIs, page["flip"]["keep"])
        diffs.text("the flip's busy", People.changing, page["flip"]["busy"])
        diffs.text("Permissions", People.permissionsTitle, page["permissions"]["legend"])
        diffs.text("Save permissions", People.savePermissions, page["permissions"]["button"])
        diffs.text("Saving", People.saving, page["permissions"]["busy"])
        diffs.text("Forget", People.forget, page["forget"]["confirm"])
        diffs.text("Keep it", People.keepIt, page["forget"]["keep"])
        diffs.text("Forgetting", People.forgetting, page["forget"]["busy"])
        diffs.text("Forget…", People.forgetEllipsis, page["forget"]["button"])
        diffs.text("the unlock's label", People.unlockLabel, page["unlock"]["label"])
        diffs.text("Unlock", People.unlock, page["unlock"]["button"])
        diffs.text("Unlocking", People.unlocking, page["unlock"]["busy"])
        diffs.text("Add's title", People.addTitle, page["add"]["title"])
        diffs.text("Add's line", People.addLine, page["add"]["line"])
        let labels = [People.userLabel, People.displayLabel, People.passwordLabel, People.againLabel]
        for (at, label) in labels.enumerated() { diffs.text("Add's label \(at)", label, page["add"]["labels"][at]) }
        diffs.text("Make account", People.make, page["add"]["button"])
        diffs.text("Making", People.making, page["add"]["busy"])
        let fields = [People.userField - People.nameMax, People.displayField - People.displayMax,
                      People.passwordField - OwnPassword.passwordMax]
        for (at, room) in fields.enumerated() { diffs.number("a field's room \(at)", Double(room), page["add"]["fieldMax"][at]) }
        diffs.text("New password", People.newPasswordLabel, page["reset"]["labels"][0])
        diffs.text("the web's second label", "Again", page["reset"]["labels"][1])
        diffs.text("Reset password", People.resetButton, page["reset"]["button"])
        diffs.text("Resetting", People.resetting, page["reset"]["busy"])
        diffs.text("Reset's Cancel", People.cancel, page["reset"]["cancel"])
        diffs.text("Remove's label", People.typeTheName, page["remove"]["label"])
        diffs.text("Remove's Cancel", People.cancel, page["remove"]["cancel"])
        diffs.text("Removing", People.removing, page["remove"]["busy"])
        diffs.text("a read's failure", People.readFailed, page["readFailed"])
        diffs.text("the kind that locks", PeopleOutcome.lockedKind, page["lockedKind"])
        diffs.done()
        #expect(People.newAgainLabel == "New password again")
    }

    /// Each route the web calls is the phone's, by name: the method, and the path with `{person_id}` where the web puts
    /// the account's id.
    @Test func theRoutesAreTheWebs() {
        let phone: [String: Endpoint] = [
            "getPeople": Routes.people, "unlockPeople": Routes.unlockPeople, "lockPeople": Routes.lockPeople,
            "createPerson": Routes.createPerson, "resetPassword": Routes.resetPassword, "setAdmin": Routes.setAdmin,
            "removePerson": Routes.removePerson, "forgetPerson": Routes.forgetPerson,
            "savePermissions": Routes.savePermissions,
        ]
        let routes = fixture["page"]["routes"].list
        #expect(routes.count == phone.count)
        for route in routes {
            let name = route["name"].string ?? "?"
            guard let endpoint = phone[name] else {
                Issue.record("the web calls \(name), which the phone has no route for")
                continue
            }
            #expect(endpoint.method == route["method"].string && endpoint.path == route["path"].string, "\(name)")
            #expect(endpoint.query.isEmpty, "\(name)")
        }
    }

    // MARK: the rules

    @Test func eachNameIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["names"].list.enumerated() {
            let typed = row["typed"].string!
            let clean = People.cleanName(typed)
            diffs.text("\(at): cleanName(\(Screens.spelled(typed)))", clean, row["clean"])
            diffs.text("\(at): nameProblem(\(Screens.spelled(clean)))", People.nameProblem(clean), row["problem"])
        }
        diffs.done()
    }

    @Test func eachDisplayNameIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["displays"].list.enumerated() {
            let typed = row["typed"].string!
            diffs.text("\(at): displayProblem(\(Screens.spelled(typed)))", People.displayProblem(typed), row["problem"])
        }
        diffs.done()
    }

    /// Each new person's form: what shows while typing, whether Make account is on, and what it sends - every key and
    /// value as AddPerson.tsx sends them.
    @Test func eachFormIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["forms"].list.enumerated() {
            let form = PeopleAddForm(user: row["user"].string!, name: row["name"].string!, password: row["password"].string!,
                                     again: row["again"].string!)
            let label = "\(at): \(Screens.spelled(form.user))"
            diffs.text("\(label), the problem", People.formProblem(form), row["problem"])
            diffs.flag("\(label), ready", People.formReady(form), row["ready"])
            diffs.flag("\(label), the body", EditVectorTests.same(EditVectorTests.json(PeopleCreateBody(form)), row["body"]),
                       .bool(true))
        }
        diffs.done()
    }

    /// Each reset: what shows while typing, whether Reset password is on, the body, and the sheet's title.
    @Test func eachResetIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["resets"].list.enumerated() {
            let passwords = PeoplePasswords(password: row["password"].string!, again: row["again"].string!)
            let user = row["user"].string!
            let label = "\(at): as \(Screens.spelled(user))"
            diffs.text("\(label), wrong", People.resetProblem(passwords, user: user), row["wrong"])
            diffs.flag("\(label), ready", People.resetReady(passwords, user: user), row["ready"])
            diffs.flag("\(label), the body",
                       EditVectorTests.same(EditVectorTests.json(PeopleResetBody(user: user, passwords)), row["body"]), .bool(true))
            diffs.text("\(label), the title", People.resetTitle(user), row["title"])
        }
        diffs.done()
    }

    // MARK: the rows

    /// Each row, the server's shape decoded by the phone's model: what follows the name, the sign-in and library lines,
    /// the libraries warning, each action and which are drawn, the refusals said once each, Remove's lines and words, the
    /// flip's question, button and body, the boxes and what's over them, Save permissions and what it sends.
    @Test func eachRowIsTheWebs() {
        let now = fixture["now"].num!
        let diffs = ScreenDiffs()
        for (at, row) in fixture["people"].list.enumerated() {
            let person = Self.person(row["person"])
            let label = "\(at): \(Screens.spelled(person.user))"
            diffs.check("\(label), chips", People.chips(person), row["chips"].list.compactMap(\.string))
            diffs.text("\(label), signed in", People.signInWords(person, now: now), row["signIn"])
            diffs.text("\(label), library", People.libraryWords(person), row["library"])
            diffs.text("\(label), warning", People.librariesWarning(person), row["warning"])
            let actions = People.actions(person)
            diffs.number("\(label), actions", Double(actions.count), .number(Double(row["actions"].list.count)))
            for (index, action) in actions.enumerated() {
                let web = row["actions"][index]
                diffs.text("\(label), action \(index)", action.kind.rawValue, web["kind"])
                diffs.text("\(label), action \(index)'s label", action.label, web["label"])
                diffs.text("\(label), action \(index)'s refusal", action.refused, web["refused"])
            }
            diffs.check("\(label), drawn", actions.filter(\.offered).map(\.kind.rawValue), row["drawn"].list.compactMap(\.string))
            let refusals = People.refusals(person)
            diffs.number("\(label), refusals", Double(refusals.count), .number(Double(row["refusals"].list.count)))
            for (index, refusal) in refusals.enumerated() { diffs.text("\(label), refusal \(index)", refusal, row["refusals"][index]) }
            let lines = People.removeLines(person)
            diffs.text("\(label), Remove's Navidrome line", lines.navidrome, row["remove"]["navidrome"])
            diffs.text("\(label), Remove's deadwax line", lines.deadwax, row["remove"]["deadwax"])
            diffs.text("\(label), Remove's stays line", lines.stays, row["remove"]["stays"])
            diffs.text("\(label), Remove's undo line", lines.undo, row["remove"]["undo"])
            diffs.text("\(label), Remove's button", People.removeButton(person.user), row["removeButton"])
            diffs.text("\(label), removed", People.removed(person.user), row["removed"])
            diffs.check("\(label), ticked", People.tickedLabels(person), row["ticked"].list.compactMap(\.string))
            let question = People.flipWords(person)
            diffs.text("\(label), the flip's question", question.question, row["question"]["question"])
            diffs.text("\(label), the flip's body", question.body, row["question"]["body"])
            diffs.text("\(label), the flip's button", People.flipButton(person), row["confirm"])
            let flip = PeopleAdminBody(user: person.user, admin: !person.admin)
            diffs.flag("\(label), the flip's body sent", EditVectorTests.same(EditVectorTests.json(flip), row["adminBody"]),
                       .bool(true))
            let boxes = People.checkboxes(admin: person.admin, refused: person.can.permissions, ticked: person.permissions)
            diffs.number("\(label), boxes", Double(boxes.count), .number(Double(row["boxes"].list.count)))
            for (index, box) in boxes.enumerated() {
                let web = row["boxes"][index]
                diffs.text("\(label), box \(index)", box.category.rawValue, web["category"])
                diffs.text("\(label), box \(index)'s label", box.label, web["label"])
                diffs.text("\(label), box \(index)'s line", box.line, web["line"])
                diffs.flag("\(label), box \(index) checked", box.checked, web["checked"])
                diffs.flag("\(label), box \(index) locked", box.locked, web["locked"])
                diffs.text("\(label), box \(index)'s warning", box.warning, web["warning"])
            }
            diffs.text("\(label), the reason", People.lockedReason(admin: person.admin, refused: person.can.permissions),
                       row["reason"])
            diffs.flag("\(label), Save permissions", People.savesPermissions(person), row["saves"])
            if let ticks = person.permissions {
                let sent = EditVectorTests.json(PeoplePermissionsBody(user: person.user, ticks))
                diffs.flag("\(label), the permissions sent", EditVectorTests.same(sent, row["saveBody"]), .bool(true))
            } else {
                diffs.flag("\(label), no permissions to send", row["saveBody"].isNull, .bool(true))
            }
        }
        diffs.done()
    }

    @Test func eachAgeIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["agos"].list {
            let seconds = row["seconds"].num!
            diffs.text("ago(\(seconds))", People.ago(seconds), row["said"])
        }
        diffs.done()
    }

    @Test func eachKnownOnlyNameIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["known"].list.enumerated() {
            let entry = EditVectorTests.decoded(PeopleKnownOnly.self, row["entry"])
            diffs.text("\(at): knownWords", People.knownWords(entry), row["said"])
            diffs.text("\(at): Forget's question", People.forgetQuestion(entry.user), row["question"])
            diffs.text("\(at): forgot", People.forgot(entry.user), row["forgot"])
        }
        diffs.done()
    }

    @Test func removeIsReadyAsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["ready"].list {
            let typed = row["typed"].string!, user = row["user"].string!
            diffs.flag("removeReady(\(Screens.spelled(typed)), \(Screens.spelled(user)))", People.removeReady(typed, user: user),
                       row["ready"])
        }
        diffs.done()
    }

    @Test func aChangeIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["changes"].list.enumerated() {
            let saved = row["saved"].isNull ? nil : EditVectorTests.decoded(PeopleTicks.self, row["saved"])
            let draft = row["draft"].isNull ? nil : EditVectorTests.decoded(PeopleTicks.self, row["draft"])
            diffs.flag("\(at): changed", People.changed(saved: saved, draft: draft), row["changed"])
        }
        diffs.done()
    }

    @Test func whatIsSaidAfterIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["after"].list {
            let user = row["user"].string!, origin = row["origin"].string!, count = row["signedOut"].int!
            let label = "\(Screens.spelled(user)) at \(origin)"
            diffs.text("\(label), made", People.madeWords(user, origin: origin), row["made"])
            diffs.text("\(label), reset \(count)", People.resetWords(user, signedOut: count), row["reset"])
            diffs.text("\(label), saved", People.savedWords(user, device: .iPhone), row["saved"])
            diffs.text("\(label), flipped on", People.flipped(user: user, admin: true), row["flippedOn"])
            diffs.text("\(label), flipped off", People.flipped(user: user, admin: false), row["flippedOff"])
            diffs.text("\(label), the unlock's line", People.unlockLine(user), row["unlockLine"])
        }
        diffs.done()
    }

    @Test func eachVersionNoteIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["versions"].list {
            let server = row["server"].string
            diffs.text("versionNote(\(Screens.spelled(server)))", People.versionNote(server), row["said"])
        }
        diffs.done()
    }

    @Test func eachViewIsTheWebs() {
        let diffs = ScreenDiffs()
        for (at, row) in fixture["views"].list.enumerated() {
            let state = row["state"].isNull ? nil : EditVectorTests.decoded(PeopleState.self, row["state"])
            diffs.text("\(at): peopleView", People.view(state).rawValue, row["view"])
        }
        diffs.done()
    }

    /// deadwax's address as the web's `location.origin` names it, for Made's words: the scheme, the host and a port given.
    @Test func theOriginIsTheAddresss() throws {
        #expect(People.origin(try ServerAddress.parse("192.168.3.20:8090").get()) == "http://192.168.3.20:8090")
        #expect(People.origin(try ServerAddress.parse("https://deadwax.example.org").get()) == "https://deadwax.example.org")
        #expect(People.origin(nil) == "")
    }
}
