import Foundation

/// The sign-in screen, Sign out and the 401 that ends a session - the web app's ui/src/app/SignIn.tsx,
/// app/SignOutRow.tsx, app/signInGate.tsx's launch and api/http.ts's noteSignedOut, with lib/signIn.ts's sentences
/// (already in ErrorWords: signInProblem, signInWhy, reasonShown; Access.afterSignIn), ported as state a SwiftUI view
/// draws and nothing else. Held to what the TypeScript answers: Tests/DeadwaxCoreTests/Fixtures/screens/signin.json,
/// written by ios/scripts/export-screen-vectors.cjs, which drives the web's own components step by step - typing,
/// Sign in, deadwax's answer - and records what they draw after each.
public enum SignInWords {
    /// The avatar's letter, over the title.
    public static let avatar = "d"
    public static let title = "deadwax"
    public static let lede = "Sign in with your music server (Navidrome) account."
    public static let userName = "User name"
    public static let password = "Password"
    public static let signIn = "Sign in"
    public static let signingIn = "Signing in…"
    /// A field left empty (the name once trimmed) - nothing is sent. The server says the same 400.
    public static let empty = "Type your user name and your password."
}

/// The sign-in form: what was typed, whether a sign-in is on its way, and what went wrong (SignIn.tsx's state).
/// The view binds `username` and `password` to its fields, calls `submit()` on Sign in (and Return in the password)
/// and sends the body it returns; then `signedIn()` or `failed(_:)` with the answer. The password is held only until
/// the sign-in it was sent with has answered.
public struct SignInForm: Sendable, Equatable {
    public var username: String
    public var password: String
    /// A sign-in is on its way: the button says "Signing in…" and does nothing.
    public private(set) var busy: Bool
    /// What went wrong, for everyone (announced).
    public private(set) var problem: String?
    /// What whoever runs deadwax needs beside it, folded under "For whoever runs deadwax".
    public private(set) var problemWhy: String?

    public init(username: String = "", password: String = "") {
        self.username = username
        self.password = password
        busy = false
        problem = nil
        problemWhy = nil
    }

    /// Sign in pressed: the body to send - the name trimmed (JS's trim), the password as typed - or nil when one is
    /// already on its way, or a field is empty (the problem then says so, and nothing is sent).
    public mutating func submit() -> SignInBody? {
        if busy { return nil }
        let name = WebText.trim(username)
        if name.isEmpty || password.isEmpty {
            problem = SignInWords.empty
            problemWhy = nil
            return nil
        }
        busy = true
        problem = nil
        problemWhy = nil
        return SignInBody(username: name, password: password)
    }

    /// deadwax let them in: the password forgotten. The app goes on with the /me it answered (`Access.afterSignIn`).
    public mutating func signedIn() {
        password = ""
        busy = false
    }

    /// The sign-in failed: the password forgotten, and why it failed said in deadwax's words where it sent some fit
    /// to show (ErrorWords.signInProblem), with what whoever runs deadwax needs folded under it (signInWhy).
    public mutating func failed(_ error: any Error) {
        password = ""
        busy = false
        problem = ErrorWords.signInProblem(error)
        problemWhy = ErrorWords.signInWhy(error)
    }

    /// What the screen draws, shown over `reason` (why it is showing - a 401's words, or the launch's) with its
    /// `reasonWhy`. The reason is never said twice: one the same as the problem is said once, as the problem.
    public func lines(reason: String?, reasonWhy: String? = nil) -> SignInLines {
        let shown = ErrorWords.reasonShown(reason)
        let why: String? = {
            guard let shown else { return nil }
            if let problem, WebText.same(shown, problem) { return nil }
            return shown
        }()
        let saidProblem = problem.flatMap { $0.isEmpty ? nil : $0 }
        return SignInLines(
            reason: why,
            reasonWhy: why != nil ? reasonWhy.flatMap { $0.isEmpty ? nil : $0 } : nil,
            problem: saidProblem,
            problemWhy: saidProblem != nil ? problemWhy.flatMap { $0.isEmpty ? nil : $0 } : nil,
            button: busy ? SignInWords.signingIn : SignInWords.signIn,
            disabled: busy)
    }
}

/// What the sign-in screen draws.
public struct SignInLines: Sendable, Equatable {
    /// Why it is showing, above the form - and the screen's accessibility description - or nil.
    public let reason: String?
    /// Folded under the reason, for whoever runs deadwax.
    public let reasonWhy: String?
    /// What went wrong, under the fields (announced).
    public let problem: String?
    /// Folded under the problem, for whoever runs deadwax.
    public let problemWhy: String?
    /// "Sign in", or "Signing in…" while one is on its way.
    public let button: String
    public let disabled: Bool

    public init(reason: String?, reasonWhy: String?, problem: String?, problemWhy: String?, button: String, disabled: Bool) {
        self.reason = reason
        self.reasonWhy = reasonWhy
        self.problem = problem
        self.problemWhy = problemWhy
        self.button = button
        self.disabled = disabled
    }
}

public enum SignInRules {
    /// Why the sign-in screen comes up at launch, when /me failed (signInGate.tsx): a 401's own words (none is the
    /// plain "sign in", which `lines` doesn't repeat), or for anything else what kind of failure it was, with what
    /// whoever runs deadwax needs - deadwax not reached, its logins unable to run.
    public static func launchReason(_ error: any Error) -> (reason: String?, why: String?) {
        if let answer = (error as? APIFailure)?.answer, answer.status == 401 { return (answer.detail, nil) }
        return (ErrorWords.signInProblem(error), ErrorWords.signInWhy(error))
    }

    /// Whether a refusal ends the session the app holds now (http.ts noteSignedOut): a 401 from any route but /auth/'s
    /// (`APIFailure.isSignedOut`), to a request sent under the session cookie the app holds now. The web counts its
    /// sessions (`newSession` at each sign-in) and compares the count a request went out under; the phone compares the
    /// cookies themselves, since every sign-in brings a new one: `sentUnder` is the cookie the client's `onSignedOut`
    /// passes (the one that request carried), `current` the one in hand when it answered. A 401 to a request sent
    /// before the latest sign-in is that old session's, and says nothing about this one - else a poll that left just
    /// before a sign-in, answered just after, brought the sign-in straight back. When this is true the sign-in comes
    /// up over the app with the 401's `detail` as its reason; the app, and the music, stay as they were under it.
    public static func endsSession(_ failure: APIFailure, sentUnder: String?, current: String?) -> Bool {
        failure.isSignedOut && sentUnder == current
    }
}

/// You's Sign out (SignOutRow.tsx), drawn only with logins on. It ends this phone's session and starts the app
/// again at the sign-in: what was playing stops. deadwax answering at all - with a failure too - forgot the session,
/// so that starts again as well; only no answer at all keeps you signed in, and is said.
public struct SignOutRow: Sendable, Equatable {
    /// Asking deadwax: the row says "Signing out…" and does nothing.
    public private(set) var busy: Bool
    /// Why you're still signed in (announced).
    public private(set) var problem: String?

    public static let unreached = "Couldn't reach deadwax, so you're still signed in - try again."

    public init() {
        busy = false
        problem = nil
    }

    /// The row pressed: true when the app asks deadwax to sign out now (POST /auth/logout); false while it asks.
    public mutating func press() -> Bool {
        if busy { return false }
        busy = true
        problem = nil
        return true
    }

    /// What signing out comes to.
    public enum Outcome: String, Sendable {
        /// stop the player, forget the session, and start again at the sign-in
        case startAgain
        /// still signed in: the row says so
        case stay
    }

    /// deadwax's answer - nil for a 200 - or no answer at all. Any answer of deadwax's starts again. With the app's
    /// client that is nil or a throw: `DeadwaxClient.signOut()` already takes any answer as signed out, and throws only
    /// when nothing answered (`.offline`, `.timeout`) or the task asking was cancelled. A cancelled ask learned nothing
    /// (the web's can't be cancelled): the row is as it was before it was pressed, and says nothing - never "Couldn't
    /// reach deadwax", which it may well have.
    public mutating func answered(_ error: (any Error)?) -> Outcome {
        guard let error else { return .startAgain }
        if (error as? APIFailure)?.answer != nil { return .startAgain }
        busy = false
        if error is CancellationError { return .stay }
        problem = Self.unreached
        return .stay
    }

    /// The row's label.
    public var label: String { busy ? "Signing out…" : "Sign out" }

    /// Under the row: who is signed in, and how - the break-glass admin told its sign-in lasts 12 hours.
    public static func footnote(user: String) -> String {
        let who = WebText.same(user, Access.breakGlassUser)
            ? "Signed in as \(Access.breakGlassUser), with the emergency admin password - this sign-in lasts 12 hours. "
            : "Signed in as \(user), with your music server (Navidrome) account. "
        return who + "Signing out ends this device's session and stops what's playing."
    }
}
