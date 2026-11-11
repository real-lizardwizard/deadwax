import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/you/you.json: the expressions the web's You (app/You.tsx) draws its headline, About and Account by, read
/// out of its source and evaluated as written over every kind of /me answer, failed or not, an admin or not, unverified
/// or not - and the words the phone's You shares with it. Replayed here through YouLines, case for case.
@Suite struct ScreenYouTests {
    let fixture = try! JSONDecoder().decode(Web.self, from: Fixtures.data("you/you.json"))

    @Test func theFixtureIsThere() {
        #expect(fixture["cases"].list.count == 136)
        #expect(fixture["made_by"].string == "ios/scripts/export-you-vectors.cjs")
        for piece in ["ui/src/app/You.tsx signedIn", "ui/src/app/You.tsx headline", "ui/src/app/You.tsx identity",
                      "ui/src/app/You.tsx the avatar", "ui/src/app/You.tsx Version", "ui/src/app/You.tsx Logins",
                      "ui/src/app/You.tsx Account drawn", "ui/src/app/You.tsx UNVERIFIED drawn",
                      "ui/src/app/You.tsx the failure under About", "ui/src/app/You.tsx the notes under Normalization",
                      "ui/src/lib/permissions.ts UNVERIFIED"] {
            #expect(fixture["made_from"][piece].string?.utf8.count == 64, "made_from names \(piece)")
        }
    }

    @Test func theWordsAreTheWebs() {
        let words = fixture["words"]
        #expect(Screens.same(YouWords.noSignIn, words["NO_SIGN_IN"].string))
        #expect(Screens.same(YouWords.notKnown, words["NOT_KNOWN"].string))
        #expect(Screens.same(YouWords.unverified, words["UNVERIFIED"].string))
        #expect(Screens.same(YouWords.playback, words["titles"]["playback"].string))
        #expect(Screens.same(YouWords.account, words["titles"]["account"].string))
        #expect(Screens.same(YouWords.about, words["titles"]["about"].string))
        #expect(Screens.same(Normalization.title, words["normalization"].string))
        #expect(Screens.same(YouWords.normalizationNote, words["normalizationNote"].string))
    }

    /// The phone's footer says the web's of Normalization - it changes from the next thing played - and leaves out
    /// what the phone hasn't got: Maximum quality, and settings in the plural.
    @Test func theFooterKeepsTheWebsClaimAndDropsMaximumQuality() throws {
        let web = try #require(fixture["words"]["webFooter"].string)
        #expect(web.hasSuffix("Normalization from the next thing you play."))
        #expect(web.contains("Maximum quality"))
        #expect(YouWords.kept.hasSuffix("Normalization changes from the next thing you play."))
        #expect(!YouWords.kept.contains("Maximum quality"))
        #expect(!YouWords.normalizationNote.contains("Maximum quality"))
    }

    @Test func everyCaseDrawsAsTheWebs() {
        let diffs = ScreenDiffs()
        for (index, row) in fixture["cases"].list.enumerated() {
            let who = row["who"]
            let me: Me? = who.isNull ? nil : Me(user: who["user"].string!, admin: who["admin"].bool!, auth: who["auth"].string!,
                                               version: who["version"].string)
            let access = Access(user: me?.user ?? "", permissions: [], on: me?.loginsOn ?? false,
                                unverified: row["access"]["unverified"].bool!, admin: row["access"]["admin"].bool!)
            let lines = YouLines(me: me, failed: row["failed"].bool!, access: access)
            let drawn = row["drawn"]
            let label = "case \(index) (who \(who), failed \(row["failed"]), access \(row["access"]))"
            diffs.text("\(label): avatar", lines.avatar, drawn["avatar"])
            diffs.text("\(label): name", lines.name, drawn["name"])
            diffs.text("\(label): identity", lines.identity, drawn["identity"])
            diffs.text("\(label): unverified", lines.unverified, drawn["unverified"])
            diffs.flag("\(label): account", lines.account, drawn["account"])
            diffs.text("\(label): version", lines.version, drawn["version"])
            diffs.text("\(label): logins", lines.logins, drawn["logins"])
            diffs.flag("\(label): failed", lines.failed, drawn["failed"])
        }
        diffs.done()
    }

    // MARK: the phone's own

    @Test func debugIsAnAdminsAlone() {
        let ethan = Me(user: "ethan", admin: false, auth: "on", version: "2.1.0")
        let james = Me(user: "james", admin: true, auth: "on", version: "2.1.0")
        let glass = Me(user: "deadwax", admin: true, auth: "on", version: "2.1.0")
        let off = Me(user: "local", admin: false, auth: "off", version: "2.1.0")
        #expect(!YouLines(me: ethan, failed: false, access: Access(me: ethan)).debug)
        #expect(YouLines(me: james, failed: false, access: Access(me: james)).debug)
        #expect(YouLines(me: glass, failed: false, access: Access(me: glass)).debug)
        // logins off: everyone is the admin (access.ts accessOf), whatever /me's own `admin` said
        #expect(YouLines(me: off, failed: false, access: Access(me: off)).debug)
        // someone given Settings and the log sees an error's own words, but isn't an admin: no Debug
        let server = Me(user: "ethan", admin: false, auth: "on", version: "2.1.0", permissions: ["server"])
        #expect(!YouLines(me: server, failed: false, access: Access(me: server)).debug)
    }

    @Test func aFailureStandsUntilTheNextAskBegins() {
        let failure = APIFailure.answered(.init(status: 500, method: "GET", path: "/me"))
        #expect(YouLines.failureStands(failure, asking: false))
        #expect(!YouLines.failureStands(failure, asking: true))
        #expect(!YouLines.failureStands(nil, asking: false))
        let me = Me(user: "james", admin: true, auth: "on", version: "2.1.0")
        let asking = YouLines(me: me, failure: failure, asking: true, access: Access(me: me))
        #expect(!asking.failed && asking.version == "2.1.0" && asking.logins == "On")
        let failed = YouLines(me: nil, failure: failure, asking: false, access: ServerModelNobody.access)
        #expect(failed.failed && failed.version == YouWords.notKnown && failed.identity == nil && failed.logins == nil)
    }

    @Test func theAppsVersionRow() {
        #expect(YouWords.app == "App")
        #expect(YouWords.app(version: "0.2", build: "2") == "0.2 (2)")
        #expect(YouWords.app(version: nil, build: nil) == "? (?)")
    }
}

/// ServerModel's `nobody`, as the app makes it (no /me yet).
private enum ServerModelNobody {
    static let access = Access(user: "", permissions: [], on: false, unverified: false, admin: false)
}

/// The can't-reach screen's two lines: the web's launch sentence, and what whoever runs deadwax needs under it.
@Suite struct UnreachedLinesTests {
    let server = try! ServerAddress.parse("192.168.1.20:8090").get()
    let admin = Access(me: Me(user: "james", admin: true, auth: "on"))
    let listener = Access(me: Me(user: "ethan", admin: false, auth: "on"))

    @Test func nothingAnsweredSaysUnreachedWithPhaseZerosWordsFolded() {
        let failure = APIFailure.offline(.init(server: server, method: "GET", path: "/me", reason: "The Internet connection appears to be offline."))
        let nobody = UnreachedLines(failure, access: nil)
        #expect(nobody.text == ErrorWords.unreached)
        #expect(nobody.detail == unreachableWords(server, reason: "The Internet connection appears to be offline."))
        #expect(nobody.detail?.contains("WireGuard") == true && nobody.detail?.contains("Local Network") == true)
        #expect(UnreachedLines(failure, access: admin).detail == nobody.detail)
        // someone known, who isn't shown an error's own words: the sentence alone
        #expect(said(UnreachedLines(failure, access: listener)) == [ErrorWords.unreached, nil])
        let timeout = APIFailure.timeout(.init(server: server, method: "GET", path: "/me", reason: "The request timed out."))
        #expect(UnreachedLines(timeout, access: nil).text == ErrorWords.unreached)
        // an answer the app couldn't read, a TLS failure: nothing deadwax said, so not reached either
        #expect(said(UnreachedLines(.other("Something answered at http://192.168.1.20:8090, but it isn't deadwax."), access: nil))
            == [ErrorWords.unreached, "Something answered at http://192.168.1.20:8090, but it isn't deadwax."])
    }

    @Test func deadwaxAnsweringIsNeverCalledUnreached() {
        let bare = APIFailure.answered(.init(status: 500, method: "GET", path: "/me"))
        #expect(said(UnreachedLines(bare, access: nil)) == [ErrorWords.serverFailed, "deadwax answered 500 and said nothing more."])
        let explained = APIFailure.answered(.init(status: 503, method: "GET", path: "/me",
                                                  detail: "deadwax isn't ready for signing in, so nobody can use it just now.",
                                                  why: "DEADWAX_SECRET_KEY isn't set."))
        #expect(said(UnreachedLines(explained, access: nil))
            == ["deadwax isn't ready for signing in, so nobody can use it just now. Tell whoever runs deadwax.",
                "DEADWAX_SECRET_KEY isn't set."])
        #expect(UnreachedLines(explained, access: listener).detail == nil)
        // deadwax's own words, fit to show: said once, never folded under themselves
        let fit = APIFailure.answered(.init(status: 503, method: "GET", path: "/me",
                                            detail: "Navidrome isn't answering, so deadwax can't check your password right now - try again in a moment."))
        #expect(UnreachedLines(fit, access: nil).detail == nil)
        #expect(UnreachedLines(fit, access: nil).text == fit.detail)
        // plumbing: the plain sentence, the words folded for whoever runs it
        let plumbing = APIFailure.answered(.init(status: 502, method: "GET", path: "/me", detail: "HTTPConnectionPool(host='navidrome', port=4533): Max retries exceeded"))
        #expect(said(UnreachedLines(plumbing, access: nil))
            == [ErrorWords.serverFailed, "HTTPConnectionPool(host='navidrome', port=4533): Max retries exceeded"])
    }
}

/// The two lines, to compare with what a case expects.
private func said(_ lines: UnreachedLines) -> [String?] { [lines.text, lines.detail] }
