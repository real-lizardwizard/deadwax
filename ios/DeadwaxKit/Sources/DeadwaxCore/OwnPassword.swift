import Foundation

/// Change password on the phone (Phase 8, slice 10 - notes/ios-specs/phase8-managing.md 9; notes/ios.md "Change password
/// on the phone"): Settings > Account > Change password, the web's app/ChangePassword.tsx, its rules lib/ownPassword.ts
/// and lib/people.ts' password rules - held to them by Fixtures/password/password-vectors.json, which
/// ios/scripts/export-password-vectors.cjs makes by running the TypeScript as it is.
///
/// The SERVER decides (src/routes/own_password.py, `POST /deadwax/me/password`: a strict model, People's rules, the
/// current password checked first, then the change made in Navidrome as the person); these are what the form says while
/// typing, when Change can be pressed, what the answer means and what is said after it. A change ends every other
/// session of the person's and moves this one under a new id, its cookie set on the answer - so the answer is this
/// phone's new sign-in (`Outcome.changed`), which ServerModel keeps before anything else can ask with the old one.
///
/// Nothing here keeps a password: the form and the body say none of theirs when printed, dumped or logged.
public enum OwnPassword {
    // MARK: the web's words (ownPassword.ts, people.ts) - held by the fixture

    /// ownPassword.ts CHANGE_TITLE: Account's row and the page's title.
    public static let title = "Change password"
    /// ownPassword.ts SAME_PASSWORD (src/routes/own_password.py SAME_PASSWORD).
    public static let samePassword = "That's the password you have now - type a new one."
    /// ownPassword.ts APPS_LINE: the new password is Navidrome's, so every app that signs in to it needs it. The web
    /// says it once a change is done; the phone says it under the form from the start (check 374) - it's what to know
    /// before changing it as much as after.
    public static let appsLine = "Amperfy and any other app you use with Navidrome need the new password too."
    /// people.ts HTTP_NOTE: said under the fields when deadwax's address is plain http.
    public static let httpNoteWords = "This page isn't over HTTPS: a password typed here crosses your network readable, "
        + "as everyone's sign-in does. That's fine on your own network or over a VPN; anywhere else, put HTTPS in front "
        + "of deadwax first."
    /// people.ts PASSWORD_MIN and PASSWORD_MAX (src/people.py's), in UTF-16 units as JavaScript counts a length.
    public static let passwordMin = 8
    public static let passwordMax = 128

    // MARK: the labels - two of the three the web's (ChangePassword.tsx), the fixture holds which

    /// ChangePassword.tsx's own.
    public static let currentLabel = "Current password"
    /// ChangePassword.tsx's own.
    public static let newLabel = "New password"
    /// The phone's: the web's "Again" sits under "New password" on a page you look at; read alone by VoiceOver, or as a
    /// row's label in a Form, it says nothing of what it's for.
    public static let againLabel = "New password again"
    /// The phone's Change (the web's Save): the page's one button, named for what it does.
    public static let change = "Change"
    /// While the change is out (the web's "Saving…").
    public static let changing = "Changing…"

    // MARK: the phone's own words

    /// A 200 with no new cookie: the password changed, but this phone's sign-in wasn't renewed - a copy of its old cookie
    /// may still work (NOT_RENEWED), or the session ended meanwhile (signed out from elsewhere). Under it the answer's
    /// warning, or `signInAgain` when it sent none.
    public static let notRenewed = "Password changed, but deadwax sent this phone no new sign-in."
    public static let signInAgain = "Sign out and sign in again here with the new password."
    /// No answer, a timeout, or a 5xx with no words of deadwax's: the change may have gone through - the answer is what
    /// says so, and it never came. What to do next: a change that went through moved this phone's session under a new
    /// id, so deadwax asks it to sign in (the old cookie answers 401) - ServerModel asks /me at once to find out.
    public static let mayHaveChanged = "deadwax may have changed your password - its answer never came."
    public static let mayHaveChangedNext = "If deadwax asks you to sign in again, it did: sign in with the new password. "
        + "If it doesn't, try again."
    /// What a refusal with no words of deadwax's says it couldn't do (ErrorWords' `failed`).
    public static let failed = "Couldn't change your password."
    /// src/routes/own_password.py NOT_YOUR_PASSWORD's kind: Current is emptied and focused, as the web does.
    public static let notYourPassword = "not_your_password"

    // MARK: who is offered it

    /// Whether Account offers Change password (ownPassword.ts `changeOffered`): logins on and a Navidrome sign-in -
    /// never with logins off (no password of yours in deadwax), never break-glass (no Navidrome account behind it). The
    /// name compared as JavaScript compares it, unit for unit.
    public static func changeOffered(_ me: Me?) -> Bool {
        guard let me, me.auth == "on", !me.user.isEmpty else { return false }
        return !me.user.utf16.elementsEqual(Access.breakGlassUser.utf16)
    }

    /// ownPassword.ts `changeLine`: the line at the top of the form.
    public static func changeLine(_ user: String) -> String {
        "Your Navidrome password, \(user) - the one you sign in to deadwax, Navidrome and Amperfy with. deadwax changes "
            + "it in Navidrome as you, and doesn't keep it."
    }

    /// people.ts `httpNote(protocol)`: none over https, the note otherwise - `scheme` as `location.protocol` has it
    /// ("https:").
    public static func httpNote(protocol scheme: String) -> String? {
        scheme.utf16.elementsEqual("https:".utf16) ? nil : httpNoteWords
    }

    /// The note for deadwax's address as the phone has it (ServerAddress keeps its scheme lowercased).
    public static func httpNote(at server: ServerAddress?) -> String? {
        httpNote(protocol: (server?.base.scheme ?? "http") + ":")
    }

    // MARK: the rules (people.ts passwordProblem, ownPassword.ts formProblem, formReady)

    /// people.ts CONTROL: what Python calls Cc, Cf, Zl and Zp, near enough - tested unit by unit, as the regular
    /// expression (no `u` flag) tests a string's UTF-16 units. None of its ranges holds a surrogate, so a character
    /// outside the BMP never matches, as in JavaScript.
    static func isControl(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0000...0x001F, 0x007F...0x009F, 0x00AD, 0x200B...0x200F, 0x2028...0x202E, 0x2060...0x2064, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// people.ts `passwordProblem`: why a password won't do for the account `name` - or nil. Never trimmed. Lengths in
    /// UTF-16 units, the name compared as `toLowerCase()` folds both (JSText), the two passwords unit for unit.
    public static func passwordProblem(_ password: String, again: String, name: String) -> String? {
        let length = password.utf16.count
        if length < passwordMin { return "A password is at least \(passwordMin) characters." }
        if length > passwordMax { return "A password is at most \(passwordMax) characters." }
        if password.utf16.contains(where: isControl) { return "A password can't have control characters in it." }
        if !name.isEmpty, same(JSText.lowercase(password), JSText.lowercase(name)) {
            return "A password can't be the user name."
        }
        if !same(password, again) { return "The two passwords aren't the same." }
        return nil
    }

    /// ownPassword.ts `formProblem`: what shows while typing - nothing until both new fields have something in them,
    /// then the first problem with them, then the same password again.
    public static func formProblem(_ form: OwnPasswordForm, user: String) -> String? {
        if form.password.isEmpty || form.again.isEmpty { return nil }
        if let problem = passwordProblem(form.password, again: form.again, name: user) { return problem }
        if !form.current.isEmpty, same(form.password, form.current) { return samePassword }
        return nil
    }

    /// ownPassword.ts `formReady`: a current password, and a new one that meets every rule and isn't the current one.
    public static func formReady(_ form: OwnPasswordForm, user: String) -> Bool {
        !form.current.isEmpty && passwordProblem(form.password, again: form.again, name: user) == nil
            && !same(form.password, form.current)
    }

    /// ownPassword.ts `doneWords`: how many of your other devices were signed out, and that this one wasn't.
    public static func doneWords(_ signedOut: Int) -> String {
        if signedOut <= 0 { return "Password changed. You're still signed in here." }
        let devices = signedOut == 1 ? "your other device" : "your other \(signedOut) devices"
        return "Password changed. Signed out of \(devices) - \(signedOut == 1 ? "it signs" : "they sign") in again with "
            + "the new one. You're still signed in here."
    }

    static func same(_ one: String, _ other: String) -> Bool { one.utf16.elementsEqual(other.utf16) }

    // MARK: what an answer means

    /// What came of a change, as the page and ServerModel take it.
    public enum Outcome: Sendable, Equatable {
        /// A 200 with a new cookie: the change went through, and `session` is this phone's sign-in now - kept in the
        /// Keychain and handed to the client before anything else asks (the old one is signed out).
        case changed(signedOut: Int, warning: String?, session: String)
        /// A 200 with no new cookie: the password changed but this phone's sign-in wasn't renewed - nothing to keep;
        /// /me is asked, and says whether the session in hand still stands.
        case notRenewed(signedOut: Int, warning: String?)
        /// A 4xx other than 401 - deadwax refused before anything changed: its words as they came, its `kind` and `fix`.
        case refused(words: String, kind: String?, fix: String?)
        /// A 401: this phone's session has ended - the sign-in comes over the app, with deadwax's reason.
        case signedOut(reason: String?)
        /// A 5xx with deadwax's own words: those words say whether it changed (src/routes/own_password.py's TIMED_OUT,
        /// UNKNOWN_SAVED, NOT_KEPT, DIDNT_TAKE, UNREACHABLE...) - said as they came.
        case failed(words: String, fix: String?)
        /// No answer, none in time, a 5xx with no words of deadwax's, or an answer the phone can't read: it may have
        /// changed (`mayHaveChanged`). Never asked again by itself - /me is asked, which says if it went through.
        case unknown(words: String)
        /// Cancelled, or the person or the session changed while it was out: nothing is said.
        case cancelled
    }

    /// A 200 as what it means: the new cookie is the proof it went through, whatever its body says; with no cookie,
    /// deadwax's answer (`changed: true`) says the password changed but nothing was renewed - and with no cookie and an
    /// answer that isn't deadwax's, nothing is known.
    public static func outcome(of response: HTTPResponse) -> Outcome {
        let answer = (try? JSONDecoder().decode(OwnPasswordAnswer.self, from: response.body)) ?? OwnPasswordAnswer()
        if let session = SessionCookie.value(fromSetCookie: response.header("Set-Cookie")) {
            return .changed(signedOut: answer.signedOut, warning: answer.warning, session: session)
        }
        guard answer.changed else { return .unknown(words: unknownLine) }
        return .notRenewed(signedOut: answer.signedOut, warning: answer.warning)
    }

    /// A failure as what it means (RetagFlow.outcome's rule, with the 401 and the 5xx's words of its own): a 4xx is a
    /// refusal, nothing changed; a 401 the session ended; a 5xx with deadwax's words, those words; anything else may
    /// have changed it.
    public static func outcome(of error: any Error, admin: Bool) -> Outcome {
        if APIFailure.isCancellation(error) { return .cancelled }
        if let failure = error as? APIFailure, let answer = failure.answer {
            if failure.isSignedOut { return .signedOut(reason: answer.detail) }
            if (400..<500).contains(answer.status) {
                return .refused(words: said(error, admin: admin), kind: answer.kind, fix: fixWords(answer.fix))
            }
            if answer.status >= 500, !ErrorWords.trim(answer.detail ?? "").isEmpty {
                return .failed(words: said(error, admin: admin), fix: fixWords(answer.fix))
            }
        }
        return .unknown(words: unknownWords(error, admin: admin))
    }

    /// A refusal's words: deadwax's `detail` as it came, as the managing pages show it (with its `why` for whoever runs
    /// deadwax); with none, a listener's (ErrorWords.notice).
    static func said(_ error: any Error, admin: Bool) -> String {
        if let answer = (error as? APIFailure)?.answer {
            let detail = ErrorWords.trim(answer.detail ?? "")
            if !detail.isEmpty {
                let line = ErrorWords.asSentence(detail)
                let why = ErrorWords.trim(answer.why ?? "")
                return admin && !why.isEmpty && !ErrorWords.same(why, detail) ? "\(line) (\(why))" : line
            }
        }
        return ErrorWords.notice("", error, admin: admin, failed: failed)
    }

    static func fixWords(_ fix: String?) -> String? {
        let words = ErrorWords.trim(fix ?? "")
        return words.isEmpty ? nil : words
    }

    static let unknownLine = "\(mayHaveChanged) \(mayHaveChangedNext)"

    /// `mayHaveChanged` and what to do next; the transport's own words in brackets for whoever runs deadwax.
    static func unknownWords(_ error: any Error, admin: Bool) -> String {
        let raw = ErrorWords.trim(ErrorWords.rawWords(error))
        return admin && !raw.isEmpty ? "\(unknownLine) (\(raw))" : unknownLine
    }

    // MARK: what the page says

    /// What the page says under the form once a change has answered.
    public enum Said: Sendable, Equatable {
        /// It went through: doneWords, and the answer's warning in amber under them.
        case done(words: String, warning: String?)
        /// It didn't, or may not have: the words in red, deadwax's `fix` quietly under them.
        case problem(words: String, fix: String?)

        /// What VoiceOver is told, once: the words, and what's under them.
        public var announcement: String {
            switch self {
            case .done(let words, let warning): return [words, warning].compactMap { $0 }.joined(separator: " ")
            case .problem(let words, let fix): return [words, fix].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    // MARK: the page kept

    /// The pages a tab keeps when it is tapped again (AppNavigation.backToRoot, beside PlaylistEdit.pagesKept): none -
    /// or, while a change is out, every page up to Change password's, so the page its answer is said on (and which is
    /// cleared as it goes) stays until it has answered. `pages` is the tab's pages, each whether it is Change password.
    public static func pagesKept(_ pages: [Bool], changing: Bool) -> Int {
        guard changing, let at = pages.lastIndex(of: true) else { return 0 }
        return at + 1
    }
}

/// The three fields (ownPassword.ts OwnPasswordForm). Says none of them when printed, dumped or logged.
public struct OwnPasswordForm: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                               CustomReflectable {
    public var current: String
    public var password: String
    public var again: String

    public init(current: String = "", password: String = "", again: String = "") {
        self.current = current
        self.password = password
        self.again = again
    }

    /// Nothing typed in any of them.
    public var isEmpty: Bool { current.isEmpty && password.isEmpty && again.isEmpty }

    public var description: String { "OwnPasswordForm(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// What a change sends (src/routes/own_password.py OwnPasswordBody: `extra="forbid"`, so a field it doesn't declare is a
/// 422 - tests/test_ios_change_password.py holds these keys to its fields). Says none of them when printed or dumped.
public struct OwnPasswordBody: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                               CustomReflectable {
    public let current: String
    public let password: String
    public let passwordAgain: String

    enum CodingKeys: String, CodingKey {
        case current, password
        case passwordAgain = "password_again"
    }

    public init(current: String, password: String, again: String) {
        self.current = current
        self.password = password
        self.passwordAgain = again
    }

    public init(_ form: OwnPasswordForm) {
        self.init(current: form.current, password: form.password, again: form.again)
    }

    public var description: String { "OwnPasswordBody(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// A change's answer (`{"changed": true, "signed_out": n, "warning": ...}`), every field read loosely: one of another type
/// is its default, never the whole answer lost - the cookie beside it is what re-keys.
public struct OwnPasswordAnswer: Decodable, Sendable, Equatable {
    public let changed: Bool
    public let signedOut: Int
    public let warning: String?

    enum CodingKeys: String, CodingKey {
        case changed
        case signedOut = "signed_out"
        case warning
    }

    public init(changed: Bool = false, signedOut: Int = 0, warning: String? = nil) {
        self.changed = changed
        self.signedOut = signedOut
        self.warning = warning
    }

    public init(from decoder: any Decoder) throws {
        let body = try decoder.container(keyedBy: CodingKeys.self)
        changed = ((try? body.decodeIfPresent(Bool.self, forKey: .changed)) ?? nil) == true
        signedOut = max(0, ((try? body.decodeIfPresent(Int.self, forKey: .signedOut)) ?? nil) ?? 0)
        let said = ErrorWords.trim(((try? body.decodeIfPresent(String.self, forKey: .warning)) ?? nil) ?? "")
        warning = said.isEmpty ? nil : said
    }
}

/// The page's state (ChangePassword.tsx's): the fields, the change out, what was said, Current asked to take focus. One
/// change at a time: `begin` gives the body and its ticket synchronously, before the request's Task is made, so a
/// second tap in the same turn finds one out; an answer for an older ticket is dropped.
public struct OwnPasswordFlow: Sendable, Equatable {
    public var form = OwnPasswordForm()
    public private(set) var changing = false
    public private(set) var said: OwnPassword.Said?
    /// One more each time Current is to take focus (deadwax said it isn't your current password).
    public private(set) var focusCurrent = 0
    private var tickets = 0

    public init() {}

    public func problem(user: String) -> String? { OwnPassword.formProblem(form, user: user) }

    /// Change may be pressed: no change out, deadwax in reach, the form ready.
    public func canChange(user: String, online: Bool) -> Bool {
        !changing && online && OwnPassword.formReady(form, user: user)
    }

    /// Typing again clears what the last answer said - it was of the fields as they were.
    public mutating func typed() {
        if !changing { said = nil }
    }

    /// Change pressed: the body to send and the ticket its answer comes back with - nil when it isn't on.
    public mutating func begin(user: String, online: Bool) -> (ticket: Int, body: OwnPasswordBody)? {
        guard canChange(user: user, online: online) else { return nil }
        changing = true
        said = nil
        tickets += 1
        return (tickets, OwnPasswordBody(form))
    }

    /// The change answered, for `ticket` - the fields as the outcome leaves them: emptied once it changed (or the
    /// session ended), kept to correct after a refusal, Current emptied and focused when it was wrong. Returns what
    /// VoiceOver is told, once - nil for an older ticket, or nothing said.
    public mutating func ended(_ ticket: Int, _ outcome: OwnPassword.Outcome) -> String? {
        guard ticket == tickets, changing else { return nil }
        changing = false
        switch outcome {
        case .changed(let signedOut, let warning, _):
            form = OwnPasswordForm()
            said = .done(words: OwnPassword.doneWords(signedOut), warning: warning)
        case .notRenewed(_, let warning):
            form = OwnPasswordForm()
            said = .done(words: OwnPassword.notRenewed, warning: warning ?? OwnPassword.signInAgain)
        case .refused(let words, let kind, let fix):
            said = .problem(words: words, fix: fix)
            if let kind, OwnPassword.same(kind, OwnPassword.notYourPassword) {
                form.current = ""
                focusCurrent += 1
            }
        case .failed(let words, let fix):
            said = .problem(words: words, fix: fix)
        case .unknown(let words):
            said = .problem(words: words, fix: nil)
        case .signedOut:
            form = OwnPasswordForm()
            said = nil
        case .cancelled:
            said = nil
        }
        return said?.announcement
    }

    /// The page went (another tab, Now Playing over it), or the sign-in came over the app: every field emptied and
    /// nothing said kept. A change out stays out - its answer is still said when it comes, and no second one can go.
    public mutating func hidden() {
        form = OwnPasswordForm()
        said = nil
    }
}

/// The hold Change password keeps on the sign-in while its answer is out (ServerModel; the web's api/http.ts drops a 401
/// sent under an older session, but not one that answers BEFORE the change's own answer - this does). The server moves
/// this phone's session under a new id before it answers, so anything asked meanwhile under the old cookie is answered
/// 401 - which says nothing about the session the answer brings. So a 401 that would end the session in hand, heard
/// while a change is out, is held rather than acted on; at the end, the re-key drops it, and anything else brings the
/// sign-in with it.
public struct PasswordRekey: Sendable, Equatable {
    public enum After: Sendable, Equatable {
        case nothing
        /// The sign-in over the app, with this reason.
        case signIn(reason: String?)
        /// /me asked once: it says whether the session in hand still stands.
        case askMe
    }

    public private(set) var out = false
    private var heard = false
    private var reason: String?

    public init() {}

    /// A change goes out: false when one is out already (one at a time).
    public mutating func began() -> Bool {
        guard !out else { return false }
        out = true
        heard = false
        reason = nil
        return true
    }

    /// A 401 that would end the session in hand: true when it's held (a change is out) - the first one's reason kept.
    public mutating func holds(reason said: String?) -> Bool {
        guard out else { return false }
        if !heard {
            heard = true
            reason = said
        }
        return true
    }

    /// The person, the address or the session changed while the change was out: whatever was held was theirs, and is
    /// let go with them.
    public mutating func forgot() {
        out = false
        heard = false
        reason = nil
    }

    /// The change is over: what then. `rekeyed` - its new session kept and in hand - drops whatever was held: the
    /// old session's 401s were the move's. Its own 401 brings the sign-in with its reason; a 401 held, with the held
    /// reason; an answer that leaves it unsure whether the session in hand stands asks /me.
    public mutating func ended(_ outcome: OwnPassword.Outcome, rekeyed: Bool) -> After {
        defer {
            out = false
            heard = false
            reason = nil
        }
        if rekeyed { return .nothing }
        if case .signedOut(let said) = outcome { return .signIn(reason: said) }
        if heard { return .signIn(reason: reason) }
        switch outcome {
        case .notRenewed, .failed, .unknown, .changed: return .askMe
        case .refused, .signedOut, .cancelled: return .nothing
        }
    }
}

extension DeadwaxClient {
    /// `POST /deadwax/me/password` (Change password): what came of it. Never asked again by itself - a change that
    /// never answered may have gone through. A 401 tells the signed-out hook, as every route's does.
    public func changeOwnPassword(_ body: OwnPasswordBody, admin: Bool) async -> OwnPassword.Outcome {
        guard let json = try? JSONEncoder().encode(body) else {
            return .refused(words: OwnPassword.failed, kind: nil, fix: nil)
        }
        do {
            return OwnPassword.outcome(of: try await answer(request(Routes.ownPassword, json: json)))
        } catch {
            return OwnPassword.outcome(of: error, admin: admin)
        }
    }
}
