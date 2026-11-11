import Foundation
import Testing
@testable import DeadwaxCore

/// Access: what /me says this person may see - app/access.ts accessOf and seesDetail, lib/permissions.ts
/// permissionsOf, useMyLibrary.ts hasLibrary, as the web reads them.
@Suite struct AccessTests {
    @Test func loginsOffIsEverythingForEveryone() {
        let access = Access(me: Me(user: "local", admin: false, auth: "off", permissions: []))
        #expect(access.permissions == Access.all && access.isAdmin && !access.loginsOn)
        #expect(access.seesDetail && !access.hasLibrary && !access.isBreakGlass)
    }

    @Test func anAdminSignedInHasALibrary() {
        let access = Access(me: Me(user: "james", admin: true, auth: "on",
                                   permissions: ["request", "edit", "library", "downloads", "server", "people"]))
        #expect(access.isAdmin && access.loginsOn && access.seesDetail && access.hasLibrary && !access.isBreakGlass)
        #expect(access.can(.people) && access.permissions.count == 6)
    }

    @Test func onlyNamesItKnowsAreGranted() {
        let access = Access(me: Me(user: "ethan", admin: false, auth: "on", permissions: ["request", "everything", "Server"],
                                   permissionsUnverified: true))
        #expect(access.permissions == [.request])
        #expect(!access.seesDetail && access.unverified && access.hasLibrary && !access.can(.server))
    }

    @Test func settingsAndTheLogIsEnoughToSeeTheDetail() {
        let access = Access(me: Me(user: "sam", admin: false, auth: "on", permissions: ["request", "server"]))
        #expect(access.seesDetail && !access.isAdmin)
    }

    @Test func anAnswerFromBeforePermissionsIsAllOrNothingByAdmin() {
        #expect(Access(me: Me(user: "james", admin: true, auth: "on")).permissions == Access.all)
        #expect(Access(me: Me(user: "ethan", admin: false, auth: "on")).permissions.isEmpty)
        #expect(!Access(me: Me(user: "ethan", admin: false, auth: "on")).unverified)
    }

    @Test func breakGlassHasNoLibrary() {
        let access = Access(me: Me(user: "deadwax", admin: true, auth: "on", permissions: ["request"]))
        #expect(access.isBreakGlass && !access.hasLibrary && access.isAdmin && access.seesDetail)
        // logins off, the shared account is never break-glass, whatever it's called
        #expect(!Access(me: Me(user: "deadwax", admin: true, auth: "off")).isBreakGlass)
    }

    @Test func permissionsAreTheServersInItsOrder() {
        #expect(Access.Permission.allCases.map(\.rawValue) == ["request", "edit", "library", "downloads", "server", "people"])
    }

    @Test func aSignInOverTheAppCarriesOnForTheSamePerson() {
        #expect(Access.afterSignIn(before: nil, now: "james") == .carryOn)
        #expect(Access.afterSignIn(before: "james", now: "james") == .carryOn)
        #expect(Access.afterSignIn(before: "james", now: "ethan") == .startAgain)
    }
}
