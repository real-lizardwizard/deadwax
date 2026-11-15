import Foundation
import Testing
@testable import DeadwaxCore

/// Managing by hand (notes/ios-specs/phase7-managing.md): what the vectors can't reach - the addresses on every kind
/// of base the phone may have, none without one, the rows for the readers the phone has, and the footer's words.
@Suite struct ManagingTests {
    private static func access(_ user: String, admin: Bool = false, auth: String = "on", _ permissions: [String]? = nil)
        -> Access {
        Access(me: Me(user: user, admin: admin, auth: auth, permissions: permissions))
    }

    /// Each tool at the web app's own address for it, on whatever base the phone was given: an IP, a name, https, a
    /// port or none, IPv6 with a zone - deadwax's routes and its web app are both at the server's root.
    @Test func everyToolOpensTheWebAppAtThePhonesServer() throws {
        let bases: [(typed: String, base: String)] = [
            ("192.168.3.20:8090", "http://192.168.3.20:8090"),
            ("bearded-dragon:8090", "http://bearded-dragon:8090"),
            ("http://deadwax.lan:8090/player/", "http://deadwax.lan:8090"),
            ("https://deadwax.example.org", "https://deadwax.example.org"),
            ("http://[fe80::1%25en0]:8090/player/", "http://[fe80::1%25en0]:8090"),
            ("[2001:db8::20]", "http://[2001:db8::20]"),
        ]
        let pages: [Managing.Tool: String] = [
            .edit: "#/library", .queue: "#/you/queue/all", .care: "#/you/care/library", .people: "#/you/people/all",
            .settings: "#/you/settings/server", .log: "#/you/log/all",
        ]
        for (typed, base) in bases {
            let server = try ServerAddress.parse(typed).get()
            for tool in Managing.Tool.allCases {
                let url = try #require(Managing.url(tool, at: server), "\(typed) \(tool)")
                #expect(url.absoluteString == base + "/player/" + pages[tool]!, "\(typed) \(tool)")
                let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
                #expect(parts?.percentEncodedPath == "/player/", "\(typed) \(tool): the page is the web app's")
                #expect(url.fragment.map { "#" + $0 } == pages[tool], "\(typed) \(tool): the route after the #")
                #expect(url.query == nil, "\(typed) \(tool): nothing after a ? - a query is nobody's instruction there")
            }
            #expect(Managing.youURL(at: server)?.absoluteString == base + "/player/#/you")
            #expect(Managing.albumURL(id: "a/b c", at: server)?.absoluteString == base + "/player/#/library/album/a%2Fb%20c")
        }
    }

    @Test func withNoAddressThereIsNothingToOpen() throws {
        for tool in Managing.Tool.allCases { #expect(Managing.url(tool, at: nil) == nil) }
        #expect(Managing.albumURL(id: "x", at: nil) == nil && Managing.youURL(at: nil) == nil)
        // nor an album with no id: the web app would open its Library's root, not the album
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        #expect(Managing.albumURL(id: "", at: server) == nil)
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

    @Test func theFooterSaysWhereTheyOpenAndHowSafariSignsIn() {
        #expect(ManagingWords.footer(loginsOn: true, online: true) == [ManagingWords.opens, ManagingWords.signIn])
        #expect(ManagingWords.footer(loginsOn: false, online: true) == [ManagingWords.opens])
        #expect(ManagingWords.footer(loginsOn: true, online: false) == [ManagingWords.offline, ManagingWords.signIn])
        #expect(ManagingWords.footer(loginsOn: false, online: false) == [ManagingWords.offline])
        // only the row that can't open its tool's own page says where it is once open
        for tool in Managing.Tool.allCases { #expect((ManagingWords.line(tool) != nil) == (tool == .edit), "\(tool)") }
        #expect(ManagingWords.editLine.contains(ManagingWords.editInWebApp))
        // the page is Safari's person's, not the app's: said wherever a row opens one
        #expect(ManagingWords.signIn.contains("whoever is signed in there"))
        #expect(ManagingWords.changePasswordLine.contains("whoever is signed in in Safari"))
    }

    /// A tap iOS refused (Safari turned off in Screen Time, no browser to open it) says so - in a listener's words,
    /// no address in them - and one the browser took says nothing.
    @Test func anOpenIOSRefusedSaysSoInAListenersWords() throws {
        #expect(Managing.notice(opened: true) == nil)
        let words = try #require(Managing.notice(opened: false))
        #expect(words == ManagingWords.notOpened)
        #expect(!ErrorWords.plumbing(words), "a listener's line: no address, setting or error in it")
        #expect(!words.contains("http") && !words.contains("/player/"))
        #expect(words.contains("Safari") && words.contains("Screen Time"))
    }
}
