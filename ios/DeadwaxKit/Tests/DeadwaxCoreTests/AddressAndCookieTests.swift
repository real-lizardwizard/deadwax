import Foundation
import Testing
@testable import DeadwaxCore

@Suite struct ServerAddressTests {
    func base(_ typed: String) -> String? {
        try? ServerAddress.parse(typed).get().base.absoluteString
    }

    @Test func anIpAndPortIsHttp() {
        #expect(base("192.168.3.20:8090") == "http://192.168.3.20:8090")
        #expect(base("  192.168.3.20:8090 \n") == "http://192.168.3.20:8090")
    }

    @Test func aShortNameAndADottedNameAreKept() {
        #expect(base("bearded-dragon:8090") == "http://bearded-dragon:8090")
        #expect(base("deadwax.lan") == "http://deadwax.lan")
    }

    @Test func aPastedWebAppLinkIsTheSameServer() {
        #expect(base("http://192.168.3.20:8090/player/") == "http://192.168.3.20:8090")
        #expect(base("HTTP://Deadwax.Lan:8090/") == "http://Deadwax.Lan:8090")
    }

    @Test func httpsIsKeptWhenTyped() {
        #expect(base("https://music.example.org") == "https://music.example.org")
    }

    @Test func whatIsntAnAddressIsSaid() {
        for typed in ["", "   ", "ftp://x", "http://", "two words", "host:99999"] {
            guard case .failure(.badAddress(let words)) = ServerAddress.parse(typed) else {
                Issue.record("\(typed) was read as an address")
                continue
            }
            #expect(!words.isEmpty)
        }
    }

    @Test func theKeyIgnoresCase() throws {
        let a = try ServerAddress.parse("http://Deadwax.Lan:8090").get()
        let b = try ServerAddress.parse("deadwax.lan:8090").get()
        #expect(a.key == b.key)
    }
}

@Suite struct SessionCookieTests {
    @Test func theValueIsReadFromASignInsHeader() {
        #expect(SessionCookie.value(fromSetCookie: "deadwax_session=s.abc; HttpOnly; Max-Age=2592000; Path=/; SameSite=strict") == "s.abc")
    }

    @Test func severalHeadersJoinedWithCommas() {
        let joined = "other=1; Path=/, deadwax_session=s.Zz-9_x; HttpOnly; Path=/; SameSite=strict"
        #expect(SessionCookie.value(fromSetCookie: joined) == "s.Zz-9_x")
    }

    @Test func aCookieWhoseNameOnlyEndsTheSameIsNotIt() {
        #expect(SessionCookie.value(fromSetCookie: "old_deadwax_session=nope; Path=/") == nil)
    }

    @Test func aQuotedValueIsUnquoted() {
        #expect(SessionCookie.value(fromSetCookie: #"deadwax_session="a.b=="; Path=/"#) == "a.b==")
    }

    @Test func aSignOutsClearingIsNoSession() {
        #expect(SessionCookie.value(fromSetCookie: #"deadwax_session=""; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/"#) == nil)
        #expect(SessionCookie.value(fromSetCookie: nil) == nil)
        #expect(SessionCookie.value(fromSetCookie: "theme=dark") == nil)
    }

    @Test func theHeaderSent() {
        #expect(SessionCookie.header("s.abc") == "deadwax_session=s.abc")
    }
}
