import Foundation

/// The You tab's words (Phase 1, app 0.2): the web's ui/src/app/You.tsx and lib/permissions.ts where the phone shows
/// what the web does, and the phone's own where it doesn't (screens.md 8). Held to the TypeScript by
/// Tests/DeadwaxCoreTests/Fixtures/you/you.json, which ios/scripts/export-you-vectors.cjs reads out of You.tsx and
/// permissions.ts as written (ui/test/iosyou.sim.cjs runs it with --check).
public enum YouWords {
    /// The tab's name and title.
    public static let title = "You"
    /// The headline's line with logins off (You.tsx NO_SIGN_IN).
    public static let noSignIn = "No sign-in needed"
    /// About's value for what deadwax didn't answer (You.tsx NOT_KNOWN).
    public static let notKnown = "Not known"
    /// What a line says while /me hasn't answered.
    public static let asking = "\u{2026}"
    /// /me's permissions_unverified (lib/permissions.ts UNVERIFIED).
    public static let unverified = "Some things an admin let you do are off for now - sign out and in again to get them back."

    // MARK: Playback

    public static let playback = "Playback"
    /// The phone has no Gapless toggle (screens.md Open question 1): the engine joins every song end to end, so
    /// the row says it is on, as Info's Sound group does (D8), and the line under it says what that means.
    public static let gapless = "Gapless"
    public static let gaplessOn = "On"
    public static let gaplessLine = "Albums play straight through, with no gap between songs."
    /// Under Normalization's four choices: the web's (You.tsx app-normalization-note), word for word.
    public static let normalizationNote = "Evens out FLAC songs only - other files play as they are. The first time an album "
        + "is levelled, deadwax measures it, so its first song can take a few seconds to start."
    /// The web's footer is "These are kept on this device. Maximum quality changes from the next song, and
    /// Normalization from the next thing you play." The phone keeps one setting, and has no Maximum quality.
    public static let kept = "This is kept on this phone. Normalization changes from the next thing you play."

    // MARK: the rest

    public static let account = "Account"
    public static let about = "About"
    public static let version = "Version"
    public static let logins = "Logins"
    public static let loginsOn = "On"
    public static let loginsOff = "Off"
    /// The phone's own: where this phone finds deadwax.
    public static let thisPhone = "This phone"
    public static let server = "Server"
    public static let changeAddress = "Change address"
    /// Phase 0's test screen, for an admin (D1).
    public static let debug = "Debug"

    /// At the foot of You: the app's own version and build, from its bundle ("deadwax for iPhone 0.2 (2)").
    public static func app(version: String?, build: String?) -> String {
        "deadwax for iPhone \(version ?? "?") (\(build ?? "?"))"
    }
}

/// What You draws from what /me last said (You.tsx, the expressions held to it in you.json): the headline - the
/// avatar's letter, the name, the line under it - the UNVERIFIED line, whether Account (Sign out) is drawn, About's
/// Version and Logins, and whether Debug is offered.
///
/// The web keeps two answers, the session's /me (`sessionMe()`, until You's own answers) and You's own; the phone has
/// one (ServerModel.me), so the session's is always nil here and the vectors are made with it nil.
public struct YouLines: Sendable, Equatable {
    /// The avatar's letter: the signed-in user's first, a capital - else "d" (with logins off, or no name).
    public let avatar: String
    /// The headline: the user signed in (logins on), else "deadwax".
    public let name: String
    /// Under it: "No sign-in needed" with logins off; "…" while /me hasn't answered; nothing otherwise.
    public let identity: String?
    /// /me said permissions_unverified: some of what an admin gave is off until a new sign-in.
    public let unverified: String?
    /// Account - Sign out and its footnote - is drawn: logins on.
    public let account: Bool
    /// About's Version: what deadwax answered; else "Not known" when /me failed, "…" when it didn't - an answer with
    /// no version in it included, as the web writes it (every deadwax with a /me sends one: src/routes/me.py).
    public let version: String
    /// About's Logins, an admin's alone (nil: not drawn) - "On" or "Off", as Version for an answer not in hand.
    public let logins: String?
    /// The last ask of /me failed: its failure is said under About, in a listener's words.
    public let failed: Bool
    /// Debug is offered: an admin (D1) - a Navidrome admin, break-glass, or anyone with logins off.
    public let debug: Bool

    /// `me` what deadwax last answered (nil before it has), `failed` that the last ask failed and isn't being asked
    /// again (`failureStands`), `access` what the screens draw by (made from `me`).
    public init(me: Me?, failed: Bool, access: Access) {
        let signedIn: String? = me.flatMap { $0.auth == "on" ? $0.user : nil }
        name = signedIn ?? "deadwax"
        avatar = signedIn.flatMap(Self.initial) ?? SignInWords.avatar
        if let me {
            identity = me.auth == "off" ? YouWords.noSignIn : nil
        } else {
            identity = failed || signedIn != nil ? nil : YouWords.asking
        }
        unverified = access.unverified ? YouWords.unverified : nil
        account = me?.auth == "on"
        let unanswered = failed ? YouWords.notKnown : YouWords.asking
        version = me?.version ?? unanswered
        logins = access.admin ? (me.map { $0.auth == "off" ? YouWords.loginsOff : YouWords.loginsOn } ?? unanswered) : nil
        self.failed = failed
        debug = access.isAdmin
    }

    /// From ServerModel's own: its last failure, and whether /me is being asked again.
    public init(me: Me?, failure: (any Error)?, asking: Bool, access: Access) {
        self.init(me: me, failed: Self.failureStands(failure, asking: asking), access: access)
    }

    /// Whether a failure of /me is said: the web forgets one as the next ask begins (You.tsx askWho sets
    /// whoFailed to null), so a failure stands only while /me isn't being asked again.
    public static func failureStands(_ failure: (any Error)?, asking: Bool) -> Bool {
        failure != nil && !asking
    }

    /// `signedIn.charAt(0).toUpperCase()`, for a name that has one: its first character, as a capital (JS's full
    /// case mapping - "ß" is "SS"). The first Unicode scalar, which is JS's first UTF-16 unit for every name in the
    /// Basic Multilingual Plane; beyond it JS splits a surrogate pair and the phone takes the whole character.
    static func initial(_ name: String) -> String? {
        guard let first = name.unicodeScalars.first else { return nil }
        return String(Character(first)).uppercased()
    }
}

/// The can't-reach screen (D10, screens.md 2): /me failed at launch with no 401, so a sign-in form couldn't help.
/// Try again asks /me again; Change address goes back to the Server address screen.
public struct UnreachedLines: Sendable, Equatable {
    public static let tryAgain = "Try again"
    public static let changeAddress = YouWords.changeAddress

    /// The sentence: the web's for a launch that failed (signInGate.tsx's launch reason, ErrorWords.signInProblem) -
    /// UNREACHED when nothing answered, which is what this screen is for; deadwax's own words, or "Something went
    /// wrong on the server", when it did answer, so the screen never says deadwax can't be reached when it answered.
    public let text: String
    /// Under "For whoever runs deadwax": what failed, in the words of whoever set the phone up - deadwax's `why`, or
    /// Phase 0's words (the address, the system's reason, Wi-Fi or WireGuard, Local Network). Nil when there is
    /// nothing beyond the sentence, or for someone who isn't shown an error's own words.
    public let detail: String?

    /// `access` is what the last /me said, nil when nothing has answered on this launch. The detail goes to whoever
    /// runs deadwax (Access.seesDetail, D10) - and, while nobody is known yet, folded under its heading for anyone, as
    /// the sign-in screen folds its own (screens.md 2): on a first launch there is no /me to ask who this is.
    public init(_ failure: APIFailure, access: Access?) {
        let text = ErrorWords.signInProblem(failure)
        self.text = text
        guard access?.seesDetail ?? true else {
            detail = nil
            return
        }
        let more = ErrorWords.signInWhy(failure) ?? failure.words
        let trimmed = WebText.trim(more)
        detail = trimmed.isEmpty || WebText.same(trimmed, text) ? nil : more
    }
}
