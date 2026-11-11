import DeadwaxCore
import Foundation
import Observation

/// Who this phone is to which deadwax: the address, the client every screen asks through, the session kept in the
/// Keychain, /me and what it lets this person see (Core's `Access`), and the launch's gates (screens.md 1, D10) - the
/// address, then can't-reach, then the sign-in, then the app - with the sign-in brought OVER the app when a session
/// ends mid-use (SignInRules.endsSession: the music plays on under it).
///
/// Every rule is Core's (SignInRules, SignOutRow, Access, ErrorWords, CheckReport); this only keeps the state and
/// makes the requests. Read `client` afresh at every call: a sign-in makes a new one with the new session, and a
/// request still out under the old one says nothing about the new session when it answers 401.
@MainActor
@Observable
final class ServerModel {
    /// What the app draws at launch (RootView), in the order screens.md 1 gives.
    enum Launch: Equatable {
        /// No address saved yet (first run), or Change address pressed: the Server address screen.
        case needsAddress
        /// /me asked with the saved address and the Keychain's session.
        case checking
        /// /me failed with no 401 (D10): the can't-reach screen, with what failed.
        case unreachable(APIFailure)
        /// A 401 at launch, or signed out: the sign-in screen alone, with why (SignInRules.launchReason - none after
        /// a sign-out).
        case signedOut(reason: String?, why: String?)
        /// /me answered: the app (MainTabs).
        case ready
    }

    /// The sign-in drawn over the app: a 401 ended this phone's session mid-use, with its words as the reason.
    struct SignInPrompt: Equatable {
        let reason: String?
        let why: String?
    }

    /// A sign-in that failed. The sign-in screen hands `error` to `SignInForm.failed(_:)`, which says it in the same
    /// words (`words` and `why` are ErrorWords.signInProblem and signInWhy).
    struct SignInProblem {
        let error: any Error
        var words: String { ErrorWords.signInProblem(error) }
        var why: String? { ErrorWords.signInWhy(error) }
    }

    /// Where the address is kept (Phase 0's key).
    static let addressKey = "address"
    /// RELOAD_AGAIN_MS (signInGate.tsx): with logins off, a 401 means they may have come on - /me is asked again, but
    /// no more than once a minute, so something else answering 401 can't set the app asking over and over.
    static let loginsAskAgainSeconds: Double = 60
    /// Who nobody is: no /me yet.
    static let nobody = Access(user: "", permissions: [], on: false, unverified: false, admin: false)

    // MARK: what the screens read

    private(set) var launch: Launch = .needsAddress
    /// The sign-in over the app (a mid-use 401), or nil. Only while `launch` is `.ready`.
    private(set) var signInOver: SignInPrompt?
    /// The Server address screen's field (the saved address, as Phase 0 kept it).
    var addressText: String = ""
    /// The address in use.
    private(set) var address: ServerAddress?
    /// The client every request goes through, with this phone's session. Nil only before an address is saved.
    private(set) var client: DeadwaxClient?
    /// What /me last said; nil before it has answered, and after a sign-out.
    private(set) var me: Me?
    /// What the screens draw by (Core's Access from `me`): isAdmin, seesDetail, hasLibrary, loginsOn, unverified.
    private(set) var access: Access = ServerModel.nobody
    /// /me is being asked again (You's "…").
    private(set) var askingMe = false
    /// /me's last failure (not a 401) after a good answer: You keeps the version and says it failed. Nil once it
    /// answers again.
    private(set) var meFailure: APIFailure?
    /// The Server address screen's Check is asking.
    private(set) var checkingAddress = false
    /// What that Check found when it couldn't go on (Phase 0's words: CheckReport.lines); nil otherwise.
    private(set) var addressReport: CheckReport?
    /// You's Sign out row (Core's SignOutRow): its label, busy and problem.
    private(set) var signOutRow = SignOutRow()
    /// One more each time the person changes - signed out, signed in as someone else, another server: everything
    /// kept for the person before is dropped (`whenPersonChanges`).
    private(set) var person = 0

    // MARK: kept

    private let transport: URLSessionTransport
    /// The session's cookie value in hand now (the Keychain's, for `address`).
    @ObservationIgnored private var session: String?
    @ObservationIgnored private var started = false
    /// Only the newest /me answer counts: each ask takes the next number, and an answer for an older one is dropped.
    @ObservationIgnored private var asks = 0
    @ObservationIgnored private var loginsAskedAt: Date?
    @ObservationIgnored private var personHandlers: [@MainActor () -> Void] = []

    init(transport: URLSessionTransport = URLSessionTransport()) {
        self.transport = transport
        let saved = UserDefaults.standard.string(forKey: Self.addressKey) ?? ""
        addressText = saved
        if !saved.isEmpty, case .success(let parsed) = ServerAddress.parse(saved) {
            address = parsed
            session = SessionKeychain.read(parsed.key)
            launch = .checking
            client = makeClient(parsed, session: session)
        }
    }

    // MARK: the launch

    /// The launch (RootView's first task): /me with the saved address, once.
    func start() async {
        guard !started else { return }
        started = true
        if address != nil { await check() }
    }

    /// Asks /me with the saved address and the session in hand: the app (200), the sign-in alone (401, its words as
    /// the reason), or can't-reach (anything else, D10). The can't-reach screen's Try again.
    func check() async {
        guard let address else {
            launch = .needsAddress
            return
        }
        let client = self.client ?? makeClient(address, session: session)
        self.client = client
        launch = .checking
        asks += 1
        let asked = asks
        do {
            let answer = try await client.me()
            guard asked == asks else { return }
            meFailure = nil
            accept(answer, before: nil)
            launch = .ready
        } catch {
            guard asked == asks, !APIFailure.isCancellation(error) else { return }
            if let failure = error as? APIFailure, failure.answer?.status == 401 {
                let said = SignInRules.launchReason(failure)
                launch = .signedOut(reason: said.reason, why: said.why)
            } else {
                launch = .unreachable(error as? APIFailure ?? .other(String(describing: error)))
            }
        }
    }

    /// The Server address screen's Check: the typed address read (`ServerAddress.parse`), then /health. When deadwax
    /// answered, the address is saved and the launch goes on from /me (step 2) - true; otherwise `addressReport` says
    /// why in Phase 0's words and nothing changes - false. The same server as in use, from You: /me asked again.
    /// Another server: the person before is let go (their queue stops); its own Keychain session is used.
    @discardableResult
    func checkAddress() async -> Bool {
        let parsed: ServerAddress
        switch ServerAddress.parse(addressText) {
        case .failure(let error):
            addressReport = CheckReport(health: .failure(error), who: nil)
            return false
        case .success(let typed):
            parsed = typed
        }
        addressText = parsed.base.absoluteString
        checkingAddress = true
        defer { checkingAddress = false }
        do {
            _ = try await makeClient(parsed, session: nil).health()
        } catch {
            if APIFailure.isCancellation(error) { return false }
            addressReport = CheckReport(health: .failure(error as? APIFailure ?? .other(String(describing: error))), who: nil)
            return false
        }
        addressReport = nil
        if parsed == address, launch == .ready {
            await refreshMe()
            return true
        }
        use(parsed)
        await check()
        return true
    }

    /// The can't-reach screen's Change address: the Server address screen, the saved address in its field.
    func changeAddress() {
        addressReport = nil
        if let address { addressText = address.base.absoluteString }
        launch = .needsAddress
    }

    // MARK: signing in and out

    /// Signs in (`SignInForm.submit()`'s body: the name trimmed, the password as typed). Nil when deadwax let them in:
    /// the session is kept in the Keychain for this server, /me's answer is the app's, and the sign-in goes - over
    /// the app, the same person carries on and someone else starts again (Access.afterSignIn). Otherwise what went
    /// wrong (hand its `error` to `SignInForm.failed`).
    func signIn(name: String, password: String) async -> SignInProblem? {
        guard let address else { return SignInProblem(error: APIFailure.other("There's no deadwax address to sign in to.")) }
        do {
            let (answer, cookie) = try await makeClient(address, session: nil).signIn(username: name, password: password)
            SessionKeychain.save(cookie, for: address.key)
            session = cookie
            client = makeClient(address, session: cookie)
            asks += 1
            let before = signInOver != nil ? me?.user : nil
            signInOver = nil
            meFailure = nil
            signOutRow = SignOutRow()
            accept(answer, before: before)
            launch = .ready
            return nil
        } catch {
            return SignInProblem(error: error)
        }
    }

    /// You's Sign out (SignOutRow): POST /auth/logout. Any answer from deadwax signs out - the player stops, the
    /// Keychain's session goes, every page pops, and the sign-in shows alone; no answer at all keeps you signed in and
    /// the row says so (`signOutRow.problem`).
    func signOut() async {
        guard let client, let address, signOutRow.press() else { return }
        var failure: (any Error)?
        do {
            try await client.signOut()
        } catch {
            failure = error
        }
        guard signOutRow.answered(failure) == .startAgain else { return }
        SessionKeychain.delete(address.key)
        session = nil
        self.client = makeClient(address, session: nil)
        asks += 1
        signInOver = nil
        meFailure = nil
        me = nil
        access = Self.nobody
        personChanged()
        signOutRow = SignOutRow()
        launch = .signedOut(reason: nil, why: nil)
    }

    // MARK: asking who again

    /// /me asked again - as the app comes to the front, and after a song fails to load (a stream's 401 included, D7) -
    /// so a session that ended while the phone slept shows the sign-in as it is picked up. Only the newest answer
    /// counts. A 401 under the session in hand brings the sign-in over the app; any other failure is `meFailure`; an
    /// answer naming someone else than before starts the app again; one answering while the sign-in shows takes it
    /// away (signed in elsewhere, or logins turned off).
    func refreshMe() async {
        guard launch == .ready, let client else { return }
        asks += 1
        let asked = asks
        askingMe = true
        do {
            let answer = try await client.me()
            guard asked == asks else { return }
            askingMe = false
            meFailure = nil
            let before = me?.user
            signInOver = nil
            accept(answer, before: before)
        } catch {
            guard asked == asks else { return }
            askingMe = false
            if APIFailure.isCancellation(error) { return }
            let failure = error as? APIFailure ?? .other(String(describing: error))
            if failure.isSignedOut {
                if SignInRules.endsSession(failure, sentUnder: client.session, current: session) {
                    bringSignIn(reason: failure.detail)
                }
            } else {
                meFailure = failure
            }
        }
    }

    /// The app came to the front (scenePhase .active): /me asked again; on the can't-reach screen, tried again; on
    /// the sign-in shown alone, asked quietly (signInGate.tsx asks while the sign-in shows too).
    func becameActive() {
        switch launch {
        case .ready: Task { await refreshMe() }
        case .unreachable: Task { await check() }
        case .signedOut: Task { await askWhileSignedOut() }
        default: break
        }
    }

    /// The sign-in shown alone (the launch's 401, or a sign-out), and the app back at the front: /me asked again,
    /// quietly. A 200 - logins turned off since, or this phone's session good again - takes the sign-in away as a
    /// sign-in would; anything else leaves it as it is, its form and its reason untouched (signInGate.tsx's ask():
    /// with the sign-in shown, only a 200 changes anything - showSignIn returns while it is up).
    private func askWhileSignedOut() async {
        guard case .signedOut = launch, let client else { return }
        asks += 1
        let asked = asks
        guard let answer = try? await client.me(), asked == asks, case .signedOut = launch else { return }
        meFailure = nil
        signOutRow = SignOutRow()
        accept(answer, before: nil)
        launch = .ready
    }

    /// `action` is run, on the main actor, each time the person changes - the player stops and forgets its queue, the
    /// pages pop to their roots, every list kept for the person before is dropped. Registered once, at the app's start.
    func whenPersonChanges(_ action: @escaping @MainActor () -> Void) {
        personHandlers.append(action)
    }

    // MARK: the rules' wiring

    private func makeClient(_ address: ServerAddress, session: String?) -> DeadwaxClient {
        DeadwaxClient(server: address, session: session, transport: transport) { [weak self] failure, sentUnder in
            Task { @MainActor in self?.noteSignedOut(failure, sentUnder: sentUnder) }
        }
    }

    /// A 401 from any route but /auth/'s (DeadwaxClient's onSignedOut), with the session it was sent under. With
    /// logins off, they may have come on: /me asked again (at most once a minute), and its 401 brings the sign-in.
    /// With them on, it ends the session in hand only when it was sent under it (SignInRules.endsSession): the
    /// sign-in comes over the app. At launch, check() reads its own 401.
    private func noteSignedOut(_ failure: APIFailure, sentUnder: String?) {
        guard launch == .ready else { return }
        if me?.loginsOn == false {
            loginsMayHaveComeOn()
            return
        }
        guard SignInRules.endsSession(failure, sentUnder: sentUnder, current: session) else { return }
        bringSignIn(reason: failure.detail)
    }

    private func loginsMayHaveComeOn() {
        let now = Date()
        if let at = loginsAskedAt, now.timeIntervalSince(at) >= 0, now.timeIntervalSince(at) < Self.loginsAskAgainSeconds {
            return
        }
        loginsAskedAt = now
        Task { await refreshMe() }
    }

    private func bringSignIn(reason: String?) {
        guard launch == .ready, signInOver == nil else { return }
        signInOver = SignInPrompt(reason: reason, why: nil)
    }

    /// /me's answer taken as the app's: who, and what they may see. `before` - the person whose app is in hand - and
    /// someone else now (Access.afterSignIn): the app starts again.
    private func accept(_ answer: Me, before: String?) {
        me = answer
        access = Access(me: answer)
        if let before, Access.afterSignIn(before: before, now: answer.user) == .startAgain {
            personChanged()
        }
    }

    /// `new` becomes the address in use (saved). Another server than before: its own Keychain session, nothing of
    /// the person before kept.
    private func use(_ new: ServerAddress) {
        UserDefaults.standard.set(new.base.absoluteString, forKey: Self.addressKey)
        guard new != address else { return }
        if me != nil { personChanged() }
        address = new
        session = SessionKeychain.read(new.key)
        client = makeClient(new, session: session)
        asks += 1
        me = nil
        access = Self.nobody
        meFailure = nil
        signInOver = nil
        signOutRow = SignOutRow()
    }

    private func personChanged() {
        person += 1
        for handler in personHandlers { handler() }
    }
}
