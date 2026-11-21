import Foundation

/// People's page as a state machine (Phase 8, slice 11 - the web's usePeople.ts, People.tsx's rows and the four forms):
/// every decision the pages make, the App carrying them out (PeopleModel). Pure, so the table tests walk it.
///
/// READS. Each read takes the next ticket as it is decided (`readBegan`, before the Task that sends it); only the newest
/// lands (latestOnly), a cancelled one is neither an answer nor a failure. A read to trust is one begun since deadwax was
/// last out of reach and since the last write ended (`real`): nothing writes before one has landed.
///
/// WRITES. One at a time (the web's `sending`): each `begin…` gives its body and ticket synchronously, in the tap, and
/// is refused while another is out, out of reach, before a read to trust, while a read is out, under the sign-in, or
/// unless the list shows (Unlock: unless Unlock People shows). After each, whatever came of it, the list is read again
/// (`PeopleAfter.read`) - never the write sent again. A refusal (a 4xx) is said as it came, with its fix; a 5xx with
/// deadwax's words says them; anything else may have happened, and says so. A refusal of kind "locked" (the unlock ran
/// out, or Navidrome asked for the password again) brings Unlock People back at once, as usePeople.ts's `locked` does:
/// nobody listed, every password emptied - and nothing else typed lost (a new person's names, the name typed to remove
/// someone, each person's unsaved ticks).
///
/// THE IDLE UNLOCK. The server holds an unlock UNLOCK_IDLE_SECONDS since it last used it, and the web learns it ran out
/// at its next ask. The phone notes when it last heard a People answer (`answeredAt`, on a clock that counts while the
/// phone sleeps) and, `People.idleCheckSeconds` after it, reads the list again (`People.idleDue`) - always after the
/// server's unlock has run out, so that read finds it gone and never keeps it alive. Once per answer (`idleAskedFor`):
/// a read sent while the check is due that fails - a 403, a proxy's 502, no answer - arms no other until a read or a
/// write answers again, so a failure never loops.
///
/// Nothing here keeps a password longer than it must: the unlock's is sent and emptied as Unlock is pressed; a new
/// person's and a reset's go when the account is made or the password reset, as a sheet closes, when People locks
/// again, and when the App says the page went (`hidden`: Now Playing over it, the sign-in over the app, the page gone).
/// None is in what the flow says when printed or dumped.
public struct PeopleFlow: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    // MARK: the answer and the reads

    /// The last answer that landed - nil before the first, and after People was left.
    public private(set) var state: PeopleState?
    /// Why the list couldn't be read: drawn with Try again when nothing has been read yet, under the list otherwise.
    public private(set) var readProblem: String?
    public private(set) var reads = 0
    public private(set) var landed = 0
    public private(set) var gap = 0
    public private(set) var reading = false
    /// When the phone last heard a People answer while the list showed, on the App's clock (seconds).
    public private(set) var answeredAt: Double?
    /// The `answeredAt` a read was sent for while the idle check was due: none other is armed for that answer.
    public private(set) var idleAskedFor: Double?
    /// How many accounts the last list had - kept through a lock (and People left), so the read after Unlock is waited
    /// for by the list it will bring (PeopleWaits.read), not the floor.
    public private(set) var accountsListed = 0

    // MARK: the writes

    /// The write out - nil while none is.
    public private(set) var writing: PeopleWrite?
    private var writes = 0
    /// What the last write said, and where.
    public private(set) var said: PeopleSaid?
    /// The sheet up (Add a person, a reset, a removal) - only ever one.
    public private(set) var sheet: PeopleSheet?
    /// One more each time the unlock's field is to take focus again (a refusal).
    public private(set) var focusUnlock = 0

    // MARK: what's typed

    /// Unlock People's field.
    public var unlockPassword = ""
    /// Add a person's fields - the names kept across a lock, the passwords never.
    public var add = PeopleAddForm()
    /// Reset password…'s two fields, for `sheet`'s person.
    public var resetPasswords = PeoplePasswords()
    /// Remove…'s typed name, for `sheet`'s person.
    public var removeTyped = ""
    /// Each person's unsaved ticks, by their id - with what was saved when the first tick was made.
    public private(set) var drafts: [String: PeopleDraft] = [:]

    public init() {}

    // MARK: what the page draws

    public var view: People.View { People.view(state) }

    /// A read to trust has landed since the last gap or write.
    public var real: Bool { landed > gap }

    /// A person of the list, by id (unit for unit).
    public func person(_ id: String) -> PeoplePerson? {
        state?.people.first { People.same($0.id, id) }
    }

    /// What a person's boxes show: their unsaved ticks, else what was saved.
    public func ticks(for person: PeoplePerson) -> PeopleTicks? {
        drafts[person.id]?.ticks ?? person.permissions
    }

    /// Their checkboxes (permissions.ts `checkboxes`, with the draft).
    public func checkboxes(for person: PeoplePerson) -> [People.Checkbox] {
        People.checkboxes(admin: person.admin, refused: person.can.permissions, ticked: ticks(for: person))
    }

    /// Their ticks differ from what was saved - Save permissions is on only then (permissions.ts `changed`).
    public func dirty(_ person: PeoplePerson) -> Bool {
        People.changed(saved: person.permissions, draft: ticks(for: person))
    }

    /// What was said, if it is said here.
    public func said(at place: PeoplePlace) -> PeopleSaid? {
        said?.place == place ? said : nil
    }

    /// The write out is this one's (its button says it is busy).
    public func writing(_ kind: PeopleWrite.Kind, for id: String? = nil) -> Bool {
        guard let writing, writing.kind == kind else { return false }
        return id == nil || writing.id.map { People.same($0, id ?? "") } == true
    }

    // MARK: may it go

    /// A change may be sent now.
    public func canWrite(online: Bool, signInOver: Bool) -> Bool {
        online && real && !reading && writing == nil && !signInOver && view == .list
    }

    /// Unlock may be pressed: Unlock People shows, a password typed, nothing out, deadwax in reach, no sign-in over the
    /// app.
    public func canUnlock(online: Bool, signInOver: Bool) -> Bool {
        online && writing == nil && !signInOver && view == .locked && !unlockPassword.isEmpty
    }

    /// Lock may be pressed: the list shows, nothing out.
    public func canLock(online: Bool, signInOver: Bool) -> Bool {
        online && writing == nil && !signInOver && view == .list
    }

    /// Make account may be pressed (people.ts `formReady`).
    public func canCreate(online: Bool, signInOver: Bool) -> Bool {
        canWrite(online: online, signInOver: signInOver) && People.formReady(add)
    }

    /// Reset password may be pressed, in `person`'s sheet.
    public func canReset(_ person: PeoplePerson, online: Bool, signInOver: Bool) -> Bool {
        canWrite(online: online, signInOver: signInOver) && offers(.reset, person)
            && sheet == .reset(person.id) && People.resetReady(resetPasswords, user: person.user)
    }

    /// Remove may be pressed, in `person`'s sheet: their name typed exactly (people.ts `removeReady`).
    public func canRemove(_ person: PeoplePerson, online: Bool, signInOver: Bool) -> Bool {
        canWrite(online: online, signInOver: signInOver) && offers(.remove, person)
            && sheet == .remove(person.id) && People.removeReady(removeTyped, user: person.user)
    }

    /// Make admin / No longer admin may be confirmed.
    public func canFlip(_ person: PeoplePerson, online: Bool, signInOver: Bool) -> Bool {
        canWrite(online: online, signInOver: signInOver) && offers(.admin, person)
    }

    /// Save permissions may be pressed.
    public func canSave(_ person: PeoplePerson, online: Bool, signInOver: Bool) -> Bool {
        canWrite(online: online, signInOver: signInOver) && People.savesPermissions(person) && dirty(person)
    }

    func offers(_ kind: People.Action.Kind, _ person: PeoplePerson) -> Bool {
        People.actions(person).first { $0.kind == kind }?.offered == true
    }

    // MARK: reads

    /// A read decided - `now` on the App's clock: one sent while the idle check is due is that check's, for this
    /// answer alone.
    public mutating func readBegan(now: Double? = nil) -> Int {
        if let now, idleDue(now: now) { idleAskedFor = answeredAt }
        reads += 1
        reading = true
        return reads
    }

    /// A read came back for `ticket`, at `now` on the App's clock: nil for an older one (dropped). True when /me is to be
    /// asked again - Navidrome or deadwax says they aren't one of its admins any more.
    public mutating func readEnded(_ ticket: Int, _ result: PeopleRead, now: Double) -> Bool? {
        guard ticket == reads else { return nil }
        reading = false
        switch result {
        case .answered(let answer):
            let was = view
            state = answer
            readProblem = nil
            landed = max(landed, ticket)
            let shown = view
            if shown == .list {
                answeredAt = now
                accountsListed = answer.people.count
            }
            if was == .list, shown != .list { forgetSheetPasswords() }
            if was == .locked, shown != .locked { unlockPassword = "" }
            keepDrafts()
            return People.saysNotAdmin(answer)
        case .failed(let words, let askMe):
            readProblem = words
            return askMe
        case .signedOut, .cancelled:
            return false
        }
    }

    /// deadwax went out of reach: what is on screen is how it was, and nothing writes until a read lands again.
    public mutating func outOfReach() {
        gap = reads
    }

    /// The idle unlock: the list shows and has been left alone long enough to have run out on the server - and no read
    /// has been sent for that yet since this answer.
    public func idleDue(now: Double) -> Bool {
        view == .list && answeredAt != idleAskedFor && People.idleDue(answeredAt: answeredAt, now: now)
    }

    /// How long until the idle check, at `now`: nil when there is none to arm - nothing listed, or a read already sent
    /// for it since this answer (it failed, or is out: only a new answer arms another, so a failure never loops).
    public func idleWait(now: Double) -> Double? {
        guard view == .list, let answeredAt, answeredAt != idleAskedFor else { return nil }
        return max(0, People.idleCheckSeconds - (now - answeredAt))
    }

    /// A fresh list puts a person's ticks back to what was saved when that changed (People.tsx's effect on
    /// `person.permissions`); a person gone, or made an admin, has no draft. While locked, nobody is listed: kept.
    private mutating func keepDrafts() {
        guard view == .list else { return }
        drafts = drafts.filter { id, draft in
            guard let saved = person(id)?.permissions else { return false }
            return saved == draft.base
        }
    }

    // MARK: what's typed

    /// A box ticked or unticked on `person`'s page (only an ordinary person's, never while a write is out).
    public mutating func tick(_ person: PeoplePerson, _ category: Access.Permission, _ on: Bool) {
        guard writing == nil, People.savesPermissions(person), let saved = person.permissions,
              People.categories.contains(category) else { return }
        var draft = drafts[person.id] ?? PeopleDraft(base: saved, ticks: saved)
        draft.ticks[category] = on
        drafts[person.id] = draft
        typed(at: .person(person.id))
    }

    /// Something typed (or ticked) where a write's words were said: they were of what was typed before.
    public mutating func typed(at place: PeoplePlace) {
        if writing == nil, said?.place == place { said = nil }
    }

    /// A sheet opened - its fields fresh but Add's names, kept across a lock.
    public mutating func open(_ shown: PeopleSheet) {
        guard writing == nil else { return }
        switch shown {
        case .add:
            add.forgetPasswords()
        case .reset:
            resetPasswords = PeoplePasswords()
        case .remove:
            removeTyped = ""
        }
        if let place = said?.place, place == shown.place { said = nil }
        sheet = shown
    }

    /// The sheet went (Close, Cancel, Done): its passwords and its typed name gone, and what it said.
    public mutating func closed() {
        guard writing == nil else { return }
        if let place = sheet?.place, said?.place == place { said = nil }
        sheet = nil
        forgetSheetPasswords()
        removeTyped = ""
    }

    /// The page went from view - Now Playing over it, the sign-in over the app, the page gone: every password emptied.
    public mutating func hidden() {
        unlockPassword = ""
        forgetSheetPasswords()
    }

    /// The sign-in came over the app (or a write's 401 brought it): every password emptied, and the sheet put away - a
    /// sheet stands over everything, the sign-in too. What's safe to keep stays (Add's names, each person's ticks); a
    /// write still out keeps its sheet, to say what came of it.
    public mutating func signInCame() {
        hidden()
        guard writing == nil else { return }
        if let place = sheet?.place, said?.place == place { said = nil }
        sheet = nil
        removeTyped = ""
    }

    /// People left (no page of it on the tab): nothing of it kept - the next opening reads afresh - but how many
    /// accounts the last list had, for that read's wait. The tickets go on, so an answer still out is dropped.
    public mutating func left() {
        guard writing == nil else { return }
        reads += 1
        reading = false
        gap = reads
        state = nil
        readProblem = nil
        answeredAt = nil
        idleAskedFor = nil
        said = nil
        sheet = nil
        drafts = [:]
        add = PeopleAddForm()
        removeTyped = ""
        hidden()
    }

    private mutating func forgetSheetPasswords() {
        add.forgetPasswords()
        resetPasswords = PeoplePasswords()
    }

    /// Locked again (usePeople.ts `locked`): Unlock People back at once, nobody listed, every password emptied.
    private mutating func lockedAgain() {
        state = state?.lockedAgain
        answeredAt = nil
        hidden()
    }

    // MARK: writes

    private mutating func begin(_ write: PeopleWrite) -> Int {
        writing = write
        writes += 1
        said = nil
        return writes
    }

    /// Unlock pressed: the password goes into the body and out of the field at once.
    public mutating func beginUnlock(online: Bool, signInOver: Bool) -> (ticket: Int, body: PeopleUnlockBody)? {
        guard canUnlock(online: online, signInOver: signInOver) else { return nil }
        let body = PeopleUnlockBody(password: unlockPassword)
        unlockPassword = ""
        return (begin(.unlock), body)
    }

    public mutating func beginLock(online: Bool, signInOver: Bool) -> Int? {
        guard canLock(online: online, signInOver: signInOver) else { return nil }
        return begin(.lock)
    }

    /// Make account pressed: the body AddPerson.tsx sends (the name cleaned, the display name trimmed).
    public mutating func beginCreate(online: Bool, signInOver: Bool) -> (ticket: Int, body: PeopleCreateBody)? {
        guard canCreate(online: online, signInOver: signInOver) else { return nil }
        let body = PeopleCreateBody(add)
        return (begin(.create(user: body.user)), body)
    }

    public mutating func beginReset(_ person: PeoplePerson, online: Bool,
                                    signInOver: Bool) -> (ticket: Int, body: PeopleResetBody)? {
        guard canReset(person, online: online, signInOver: signInOver) else { return nil }
        let body = PeopleResetBody(user: person.user, resetPasswords)
        return (begin(.reset(id: person.id, user: person.user)), body)
    }

    /// The flip confirmed: what they are to be is the opposite of what the list says they are.
    public mutating func beginFlip(_ person: PeoplePerson, online: Bool,
                                   signInOver: Bool) -> (ticket: Int, body: PeopleAdminBody)? {
        guard canFlip(person, online: online, signInOver: signInOver) else { return nil }
        let body = PeopleAdminBody(user: person.user, admin: !person.admin)
        return (begin(.admin(id: person.id, user: person.user, admin: body.admin)), body)
    }

    public mutating func beginRemove(_ person: PeoplePerson, online: Bool,
                                     signInOver: Bool) -> (ticket: Int, body: PeopleRemoveBody)? {
        guard canRemove(person, online: online, signInOver: signInOver) else { return nil }
        let body = PeopleRemoveBody(user: person.user, confirm: removeTyped)
        return (begin(.remove(id: person.id, user: person.user)), body)
    }

    public mutating func beginForget(_ entry: PeopleKnownOnly, online: Bool,
                                     signInOver: Bool) -> (ticket: Int, body: PeopleForgetBody)? {
        guard canWrite(online: online, signInOver: signInOver) else { return nil }
        return (begin(.forget(user: entry.user)), PeopleForgetBody(user: entry.user))
    }

    /// Save permissions pressed: all five, as the boxes show them.
    public mutating func beginSave(_ person: PeoplePerson, online: Bool,
                                   signInOver: Bool) -> (ticket: Int, body: PeoplePermissionsBody)? {
        guard canSave(person, online: online, signInOver: signInOver), let ticks = ticks(for: person) else { return nil }
        return (begin(.permissions(id: person.id, user: person.user)), PeoplePermissionsBody(user: person.user, ticks))
    }

    /// The write answered, failed or never answered, for `ticket` - at `now` on the App's clock; `origin` is deadwax's
    /// address for Made's words. What then: what VoiceOver is told (once - nothing while the sign-in is over the app,
    /// which says what happened itself, and the sheet the write kept put away as `signInCame` puts one), whether /me is
    /// asked again, the person's page to leave, and whether the list is read again (always, but after a 401). Nil for an
    /// older ticket.
    public mutating func ended(_ ticket: Int, _ outcome: PeopleOutcome, now: Double, signInOver: Bool,
                               origin: String, device: Device) -> PeopleAfter? {
        guard ticket == writes, let write = writing else { return nil }
        writing = nil
        // nothing writes again until a read begun after this one lands
        gap = reads
        var after = PeopleAfter()
        switch outcome {
        case .done(let done):
            if view == .list { answeredAt = now }
            said = saidAfter(write, done, origin: origin, device: device)
            switch write {
            case .lock:
                // Unlock People at once - the list read again says the same
                lockedAgain()
            case .create:
                add = PeopleAddForm()
            case .reset:
                resetPasswords = PeoplePasswords()
                sheet = nil
            case .remove(let id, _):
                removeTyped = ""
                sheet = nil
                drafts[id] = nil
                after.leave = id
            default:
                break
            }
        case .refused(let words, let kind, let fix, let askMe):
            if view == .list { answeredAt = now }
            said = PeopleSaid(place: write.place, words: words, fix: fix, problem: true)
            if let kind, People.same(kind, PeopleOutcome.lockedKind) { lockedAgain() }
            if write == .unlock { focusUnlock += 1 }
            after.askMe = askMe
        case .failed(let words, let fix):
            said = PeopleSaid(place: write.place, words: words, fix: fix, problem: true)
        case .unknown(let words):
            said = PeopleSaid(place: write.place, words: words, problem: true)
        case .signedOut:
            said = nil
            // the sign-in comes over the app: the sheet put away with the passwords
            signInCame()
            after.read = false
        case .cancelled:
            said = nil
        }
        // (the task) the admin role changed, or may have: /me asked again, whatever came of it
        if case .admin = write, outcome != .signedOut { after.askMe = true }
        after.announce = signInOver ? nil : said?.announcement
        // (review) it ended under the sign-in: the sheet it kept goes now, with any password still typed in it - what was
        // said in it goes too (the list read once the sign-in goes says what came of it)
        if signInOver, outcome != .signedOut { signInCame() }
        return after
    }

    private func saidAfter(_ write: PeopleWrite, _ done: PeopleDone, origin: String, device: Device) -> PeopleSaid? {
        switch (write, done) {
        case (.create(let sent), .made(let user, let warning)):
            return PeopleSaid(place: .add, words: People.madeWords(user.isEmpty ? sent : user, origin: origin),
                              warning: warning)
        case (.reset(let id, let sent), .reset(let user, let signedOut)):
            return PeopleSaid(place: .person(id), words: People.resetWords(user.isEmpty ? sent : user, signedOut: signedOut))
        case (.admin(let id, let sent, let wanted), .admin(let user, let admin)):
            return PeopleSaid(place: .person(id), words: People.flipped(user: user.isEmpty ? sent : user,
                                                                        admin: admin ?? wanted))
        case (.remove(_, let user), _):
            return PeopleSaid(place: .list, words: People.removed(user))
        case (.forget(let user), _):
            return PeopleSaid(place: .list, words: People.forgot(user))
        case (.permissions(let id, let user), _):
            return PeopleSaid(place: .person(id), words: People.savedWords(user, device: device))
        default:
            // unlocked or locked: the list read again says it
            return nil
        }
    }

    // MARK: said of it

    public var description: String { "PeopleFlow(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// A person's unsaved ticks, and what was saved when the first was made (a fresh list saying otherwise drops them).
public struct PeopleDraft: Sendable, Equatable {
    public let base: PeopleTicks
    public var ticks: PeopleTicks

    public init(base: PeopleTicks, ticks: PeopleTicks) {
        self.base = base
        self.ticks = ticks
    }
}

/// Where something said is drawn.
public enum PeoplePlace: Sendable, Hashable {
    /// People's own page, over the list.
    case list
    /// Under Unlock People.
    case unlock
    /// Add a person's sheet.
    case add
    /// A person's page.
    case person(String)
    /// Reset password…'s sheet, for that person.
    case reset(String)
    /// Remove…'s sheet, for that person.
    case remove(String)
    /// A Known only to deadwax row.
    case known(String)
}

/// What a write said: deadwax's words or the phone's, a warning beside them (Made's), and what to do about it.
public struct PeopleSaid: Sendable, Equatable {
    public let place: PeoplePlace
    public let words: String
    public let warning: String?
    public let fix: String?
    /// It went wrong, or may have: drawn in red.
    public let problem: Bool

    public init(place: PeoplePlace, words: String, warning: String? = nil, fix: String? = nil, problem: Bool = false) {
        self.place = place
        self.words = words
        self.warning = warning
        self.fix = fix
        self.problem = problem
    }

    /// What VoiceOver is told, once: the words, and what's under them.
    public var announcement: String { [words, warning, fix].compactMap { $0 }.joined(separator: " ") }
}

/// The sheet up: only ever one.
public enum PeopleSheet: Sendable, Hashable, Identifiable {
    case add
    case reset(String)
    case remove(String)

    public var id: String {
        switch self {
        case .add: return "add"
        case .reset(let person): return "reset " + person
        case .remove(let person): return "remove " + person
        }
    }

    /// Where its writes say what came of them.
    public var place: PeoplePlace {
        switch self {
        case .add: return .add
        case .reset(let person): return .reset(person)
        case .remove(let person): return .remove(person)
        }
    }
}

/// A People write (src/routes/people.py's eight POSTs): whose it is, by the id and name the page drew.
public enum PeopleWrite: Sendable, Equatable {
    case unlock
    case lock
    /// The name cleaned, as sent.
    case create(user: String)
    case reset(id: String, user: String)
    /// `admin`: what they are to be.
    case admin(id: String, user: String, admin: Bool)
    case remove(id: String, user: String)
    case forget(user: String)
    case permissions(id: String, user: String)

    public enum Kind: Sendable, Equatable { case unlock, lock, create, reset, admin, remove, forget, permissions }

    public var kind: Kind {
        switch self {
        case .unlock: return .unlock
        case .lock: return .lock
        case .create: return .create
        case .reset: return .reset
        case .admin: return .admin
        case .remove: return .remove
        case .forget: return .forget
        case .permissions: return .permissions
        }
    }

    /// The person's id, for the writes to one.
    public var id: String? {
        switch self {
        case .reset(let id, _), .admin(let id, _, _), .remove(let id, _), .permissions(let id, _): return id
        case .forget(let user): return user
        case .unlock, .lock, .create: return nil
        }
    }

    /// Where what went wrong is said: where it was asked from.
    public var place: PeoplePlace {
        switch self {
        case .unlock: return .unlock
        case .lock: return .list
        case .create: return .add
        case .reset(let id, _): return .reset(id)
        case .admin(let id, _, _), .permissions(let id, _): return .person(id)
        case .remove(let id, _): return .remove(id)
        case .forget(let user): return .known(user)
        }
    }

    /// What didn't work, said when deadwax gave no words of its own.
    public var failed: String {
        switch self {
        case .unlock: return People.unlockFailed
        case .lock: return People.lockFailed
        case .create: return People.createFailed
        case .reset: return People.resetFailed
        case .admin: return People.adminFailed
        case .remove: return People.removeFailed
        case .forget: return People.forgetFailed
        case .permissions: return People.saveFailed
        }
    }
}

/// What a write's answer said it did (the answer's own fields, where the words take them).
public enum PeopleDone: Sendable, Equatable {
    case unlocked
    case locked
    /// `user` as the answer names it - empty when it named none (the name sent is said).
    case made(user: String, warning: String?)
    case reset(user: String, signedOut: Int)
    case admin(user: String, admin: Bool?)
    case removed
    case forgot
    case saved
}

/// What came of a write, as the page takes it.
public enum PeopleOutcome: Sendable, Equatable {
    case done(PeopleDone)
    /// A 4xx other than 401: deadwax refused before anything changed - its words as they came, its kind and fix; `askMe`
    /// for a 403 (not one of Navidrome's admins any more, or People's permission gone).
    case refused(words: String, kind: String?, fix: String?, askMe: Bool)
    /// A 5xx with deadwax's own words: they say what happened (People's TIMED_OUT, DIDNT_TAKE, FORGET_FAILED...).
    case failed(words: String, fix: String?)
    /// No answer, none in time, a 5xx with no words of deadwax's, or an answer the phone can't read: it may have gone
    /// through - said, and the list read again to see. Never sent again by itself.
    case unknown(words: String)
    /// A 401: the session ended - the client's hook brings the sign-in; nothing is said here.
    case signedOut
    /// Cancelled: nothing is said.
    case cancelled

    /// src/routes/people.py's `locked` kind: the unlock ran out.
    public static let lockedKind = "locked"
}

/// What a read came back with.
public enum PeopleRead: Sendable, Equatable {
    case answered(PeopleState)
    /// What to say; `askMe` for a 403 (`peopleOnly`).
    case failed(words: String, askMe: Bool)
    case signedOut
    case cancelled
}

/// What the App does once a write is over.
public struct PeopleAfter: Sendable, Equatable {
    /// What VoiceOver is told, once.
    public var announce: String?
    /// /me asked again.
    public var askMe = false
    /// The person's page to leave (they were removed).
    public var leave: String?
    /// The list read again.
    public var read = true

    public init(announce: String? = nil, askMe: Bool = false, leave: String? = nil, read: Bool = true) {
        self.announce = announce
        self.askMe = askMe
        self.leave = leave
        self.read = read
    }
}

// MARK: - what a failure means

extension People {
    /// A write's failure as what it means (RetagFlow.outcome's rule, with the 401 and People's 403 of its own): a 4xx is
    /// a refusal, nothing changed; a 401 the session ended; a 5xx with deadwax's words, those words; anything else may
    /// have gone through.
    public static func outcome(of error: any Error, failed: String, admin: Bool) -> PeopleOutcome {
        if APIFailure.isCancellation(error) { return .cancelled }
        if let failure = error as? APIFailure, let answer = failure.answer {
            if failure.isSignedOut { return .signedOut }
            let kind = given(answer.kind)
            if (400..<500).contains(answer.status) {
                // require("people")'s 403 has no kind: People's permission is gone - said as the page says it
                if answer.status == 403, kind == nil { return .refused(words: peopleOnly, kind: nil, fix: nil, askMe: true) }
                return .refused(words: onPhone(refusalWords(error, failed: failed, admin: admin)), kind: kind,
                                fix: onPhone(given(answer.fix)), askMe: answer.status == 403)
            }
            if answer.status >= 500, given(answer.detail) != nil {
                return .failed(words: onPhone(refusalWords(error, failed: failed, admin: admin)),
                               fix: onPhone(given(answer.fix)))
            }
        }
        return .unknown(words: unknownWords(error, admin: admin))
    }

    /// A read's failure (usePeople.ts: `sayError(reason, '', { failed: "Couldn't read Navidrome's accounts." })`), but a
    /// 403 - People's permission gone - said as the page says it, and /me asked again.
    public static func readOutcome(of error: any Error, admin: Bool) -> PeopleRead {
        if APIFailure.isCancellation(error) { return .cancelled }
        if let failure = error as? APIFailure, let answer = failure.answer {
            if failure.isSignedOut { return .signedOut }
            if answer.status == 403 { return .failed(words: peopleOnly, askMe: true) }
        }
        return .failed(words: onPhone(EditWords.said(error, failed: readFailed, admin: admin)), askMe: false)
    }

    /// usePeople.ts `refusalOf`: People's own refusals - a kind and words - as written; anything else in a sentence,
    /// deadwax's own words in brackets for whoever runs it.
    static func refusalWords(_ error: any Error, failed: String, admin: Bool) -> String {
        if let answer = (error as? APIFailure)?.answer, given(answer.kind) != nil, let detail = answer.detail,
           !detail.isEmpty {
            return detail
        }
        return EditWords.said(error, failed: failed, admin: admin)
    }

    /// A write that never answered: it may have gone through (EditWords' line), the transport's own words in brackets
    /// for whoever runs deadwax.
    static func unknownWords(_ error: any Error, admin: Bool) -> String {
        let raw = ErrorWords.trim(ErrorWords.rawWords(error))
        return admin && !raw.isEmpty ? "\(EditWords.mayHaveFinished) (\(raw))" : EditWords.mayHaveFinished
    }

    static func given(_ text: String?) -> String? {
        let words = ErrorWords.trim(text ?? "")
        return words.isEmpty ? nil : words
    }
}

// MARK: - how long each waits

/// How long the phone waits for People's routes (src/routes/people.py), worked out from what each handler does at its
/// worst and rounded up to the minute (EditWaits.wait) - a wait that still runs out is said as maybe done and the list
/// read again, never sent again. tests/test_ios_people.py reads every figure from the server's source.
public enum PeopleWaits {
    /// One SQLite connection's busy timeout (store._connect's `timeout=10`): every store call may wait it out first.
    public static let store: Double = 10
    /// One call to Navidrome's native API: its connection and its read (navidrome_admin TIMEOUT_SECONDS, 10 s each).
    public static let native: Double = 20
    /// One native write - a POST, PUT or DELETE (WRITE_TIMEOUT_SECONDS, 30 s each).
    public static let nativeWrite: Double = 60
    /// The proof a password took, or a sign-in's check: Subsonic's getUser through deadwax's login client
    /// (`httpx.Timeout(10.0)`, twice).
    public static let subsonic: Double = 20
    /// The session read every route begins with (current_user).
    public static var session: Double { store }

    /// The read's own: the session, Navidrome's list, the facts and the names deadwax keeps - and for each account its
    /// sessions healed, other accounts' grants dropped and its ticks read.
    public static var readBase: Double { session + native + 2 * store }
    public static var readPerAccount: Double { 3 * store }

    /// GET /people, with `accounts` listed by the last answer (none before the first): never less than Routes.timeouts.
    public static func read(accounts: Int) -> Double {
        EditWaits.wait(readBase + readPerAccount * Double(max(0, accounts)), floor: Routes.timeouts[Routes.people])
    }

    /// Unlock: the session, the name's sign-in throttle (another unlock holding it: its login and a store call), the
    /// login, and the role kept (or the session ended) - assumed: no change of their own password holding it at once.
    public static var unlock: Double { session + (native + store) + native + store }

    /// Each write's own work at its worst, inside the write lock (a refusal's role kept included where it is longer).
    public static func work(_ kind: PeopleWrite.Kind) -> Double {
        switch kind {
        case .unlock: return unlock - session
        case .lock: return 0
        // anything kept under the name, the account made, read back, the password's proof
        case .create: return store + nativeWrite + native + subsonic
        // the account read, saved, the proof, their sessions ended (two calls) and the credential marked
        case .reset: return native + nativeWrite + subsonic + 3 * store
        // the account read, the list, saved, the role kept
        case .admin: return native + native + nativeWrite + store
        // the account read, the list, deleted, their sessions' keys and everything kept forgotten
        case .remove: return native + native + nativeWrite + 2 * store
        // the list, the names kept, their sessions' keys and everything kept forgotten
        case .forget: return native + 3 * store
        // the account read, the ticks read and written, read again
        case .permissions: return native + 3 * store
        }
    }

    /// The longest a write holds the one write lock: what any other waits on before its own.
    public static var longestWrite: Double {
        [PeopleWrite.Kind.create, .reset, .admin, .remove, .forget, .permissions].map(work).max() ?? 0
    }

    /// A write's wait: the session, one other write ahead of it, then its own.
    public static func write(_ kind: PeopleWrite.Kind) -> Double {
        EditWaits.wait(session + longestWrite + work(kind), floor: nil)
    }
}

// MARK: - the routes

extension DeadwaxClient {
    /// People's state (`GET /deadwax/people`) - and, unlocked, Navidrome's accounts, read fresh: waited for by how many
    /// the last answer listed (PeopleWaits.read).
    public func people(accounts: Int = 0) async throws -> PeopleState {
        var built = request(Routes.people)
        built.timeout = PeopleWaits.read(accounts: accounts)
        return try decode(PeopleState.self, try await answer(built))
    }

    /// Unlock (`POST /people/unlock`): checked against the login this session keeps before Navidrome is asked.
    public func unlockPeople(_ body: PeopleUnlockBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.unlockPeople, body: body, as: PeopleAnswered.self, failed: People.unlockFailed,
                          admin: admin) { _ in .unlocked }
    }

    /// Lock (`POST /people/lock`).
    public func lockPeople(admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.lockPeople, body: PeopleLockBody(), as: PeopleAnswered.self, failed: People.lockFailed,
                          admin: admin) { _ in .locked }
    }

    /// Make account (`POST /people/create`).
    public func createPerson(_ body: PeopleCreateBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.createPerson, body: body, as: PeopleMade.self, failed: People.createFailed,
                          admin: admin) { .made(user: $0.made.user, warning: $0.warning) }
    }

    /// Reset password (`POST /people/{person_id}/password`).
    public func resetPassword(_ id: String, _ body: PeopleResetBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.resetPassword, path: ["person_id": id], body: body, as: PeopleReset.self,
                          failed: People.resetFailed, admin: admin) { .reset(user: $0.reset, signedOut: $0.signedOut) }
    }

    /// Make admin / No longer admin (`POST /people/{person_id}/admin`).
    public func setAdmin(_ id: String, _ body: PeopleAdminBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.setAdmin, path: ["person_id": id], body: body, as: PeopleAdminAnswer.self,
                          failed: People.adminFailed, admin: admin) { .admin(user: $0.user, admin: $0.admin) }
    }

    /// Remove (`POST /people/{person_id}/remove`).
    public func removePerson(_ id: String, _ body: PeopleRemoveBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.removePerson, path: ["person_id": id], body: body, as: PeopleAnswered.self,
                          failed: People.removeFailed, admin: admin) { _ in .removed }
    }

    /// Forget (`POST /people/forget`).
    public func forgetPerson(_ body: PeopleForgetBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.forgetPerson, body: body, as: PeopleAnswered.self, failed: People.forgetFailed,
                          admin: admin) { _ in .forgot }
    }

    /// Save permissions (`POST /people/{person_id}/permissions`).
    public func savePermissions(_ id: String, _ body: PeoplePermissionsBody, admin: Bool) async -> PeopleOutcome {
        await peopleWrite(Routes.savePermissions, path: ["person_id": id], body: body, as: PeopleAnswered.self,
                          failed: People.saveFailed, admin: admin) { _ in .saved }
    }

    /// One People write: its body sent as JSON, its answer read loosely - what came of it, never sent again. A 401
    /// tells the signed-out hook, as every route's does.
    private func peopleWrite<Body: Encodable, Answer: Decodable>(
        _ endpoint: Endpoint, path parameters: [String: String] = [:], body: Body, as type: Answer.Type, failed: String,
        admin: Bool, done: (Answer) -> PeopleDone
    ) async -> PeopleOutcome {
        guard let json = try? JSONEncoder().encode(body) else {
            return .refused(words: failed, kind: nil, fix: nil, askMe: false)
        }
        do {
            return .done(done(try await call(endpoint, as: type, path: parameters, json: json)))
        } catch {
            return People.outcome(of: error, failed: failed, admin: admin)
        }
    }
}
