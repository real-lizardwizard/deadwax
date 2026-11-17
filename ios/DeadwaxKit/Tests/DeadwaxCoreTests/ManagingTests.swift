import Foundation
import Testing
@testable import DeadwaxCore

/// Managing by hand (notes/ios-specs/phase7-managing.md): what the vectors can't reach - the rows for the readers the
/// phone has, and Change password's offer. (The web app's addresses, the footer's Safari words and what a refused open
/// said went in Phase 8's slice 12: nothing in the app opens the web app - tests/test_ios_no_web_app.py.)
@Suite struct ManagingTests {
    private static func access(_ user: String, admin: Bool = false, auth: String = "on", _ permissions: [String]? = nil)
        -> Access {
        Access(me: Me(user: user, admin: admin, auth: auth, permissions: permissions))
    }

    /// The readers the phone has: with logins off everyone is the admin, but there is nobody to manage; a Navidrome
    /// admin and break-glass have every row; an ordinary listener none; a permission each opens its own.
    @Test func eachReaderHasTheRowsTheirPermissionsGive() {
        #expect(Managing.tools(Self.access("local", admin: true, auth: "off")) == [.edit, .queue, .care, .settings, .log])
        let all: [Managing.Tool] = [.edit, .queue, .care, .people, .settings, .log]
        #expect(Managing.tools(Self.access("james", admin: true)) == all)
        // /me's list decides, an admin's included: only what it names (an admin's names every one)
        #expect(Managing.tools(Self.access("deadwax", admin: true, ["request"])).isEmpty)
        #expect(Managing.tools(Self.access("deadwax", admin: true, Access.Permission.allCases.map(\.rawValue))) == all)
        #expect(Managing.tools(Self.access("ethan", ["request"])).isEmpty)
        #expect(Managing.tools(Self.access("ethan", ["edit"])) == [.edit, .care])
        #expect(Managing.tools(Self.access("ethan", ["library"])) == [.edit, .queue, .care])
        #expect(Managing.tools(Self.access("sam", ["request", "server"])) == [.settings, .log])
        #expect(Managing.tools(Self.access("ethan", ["downloads"])).isEmpty, "Everyone's downloads is Requests', no tool")
        // an answer from before permissions: its admin flag says it all
        #expect(Managing.tools(Self.access("james", admin: true)) == all)
        #expect(Managing.tools(Self.access("ethan")).isEmpty)
    }

    @Test func changePasswordIsANavidromeSignInsAlone() {
        #expect(Managing.changeOffered(Me(user: "james", admin: true, auth: "on")))
        #expect(Managing.changeOffered(Me(user: "ethan", admin: false, auth: "on")))
        #expect(!Managing.changeOffered(Me(user: "deadwax", admin: true, auth: "on")), "break-glass has no Navidrome account")
        #expect(Managing.changeOffered(Me(user: "Deadwax", admin: false, auth: "on")), "the name as JavaScript compares it")
        #expect(!Managing.changeOffered(Me(user: "local", admin: true, auth: "off")), "logins off: no password of yours")
        #expect(!Managing.changeOffered(Me(user: "", admin: false, auth: "on")))
        #expect(!Managing.changeOffered(nil))
    }
}
