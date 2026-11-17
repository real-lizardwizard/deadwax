import Foundation
import Testing
@testable import DeadwaxCore

// (Phase 8, slice 10's review) Which redirects the app follows: only within the address it asked - the same scheme, host
// and port - since every request carries deadwax's session as `Cookie:`, and a sign-in or Change password a password.

@Suite struct RedirectsTests {
    @Test func aRedirectIsFollowedOnlyWithinTheAddressAsked() {
        let asked = "http://deadwax.test:8080/deadwax/me/password"
        let cases: [(String?, String?, Bool, String)] = [
            (asked, "http://deadwax.test:8080/deadwax/me/password/", true, "the same address, another path"),
            (asked, "http://DEADWAX.test:8080/other", true, "a host's case is no difference"),
            (asked, "HTTP://deadwax.test:8080/other", true, "nor a scheme's"),
            ("http://deadwax.test/a", "http://deadwax.test:80/b", true, "http's own port, said or not"),
            ("https://deadwax.test/a", "https://deadwax.test:443/b", true, "https's own port, said or not"),
            (asked, "https://deadwax.test:8080/deadwax/me/password", false, "another scheme"),
            ("http://deadwax.test/a", "https://deadwax.test/a", false, "http to https: another scheme and port"),
            (asked, "http://elsewhere.test:8080/deadwax/me/password", false, "another host"),
            (asked, "http://deadwax.test:8081/deadwax/me/password", false, "another port"),
            (asked, "http://deadwax.test/deadwax/me/password", false, "8080 to http's own"),
            (asked, nil, false, "nowhere"),
            (nil, asked, false, "asked from nowhere"),
            (asked, "ftp://deadwax.test/x", false, "a scheme with no port of its own"),
            (asked, "file:///etc/hosts", false, "no host"),
        ]
        for (from, to, follows, what) in cases {
            let followed = Redirects.follows(from: from.flatMap(URL.init(string:)), to: to.flatMap(URL.init(string:)))
            #expect(followed == follows, "\(what)")
        }
    }

    @Test func anOriginIsItsSchemeHostAndPort() {
        let origin = Redirects.origin(URL(string: "HTTP://Deadwax.Test/deadwax/me?x=1"))
        #expect(origin == Redirects.Origin(scheme: "http", host: "deadwax.test", port: 80))
        #expect(Redirects.origin(URL(string: "https://10.0.0.2:8443/")) == Redirects.Origin(scheme: "https",
                                                                                           host: "10.0.0.2", port: 8443))
        #expect(Redirects.origin(URL(string: "/deadwax/me")) == nil, "a relative address has none")
        #expect(Redirects.origin(nil) == nil)
    }
}
