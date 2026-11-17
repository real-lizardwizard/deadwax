import Foundation

/// People on the phone (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10; notes/ios.md "People on the phone"):
/// Settings > Manage > People, the web's app/People.tsx with UnlockPeople, AddPerson, ResetPassword, RemovePerson and
/// usePeople, its rules lib/people.ts and lib/permissions.ts' People parts - held to them by
/// Fixtures/people/people-vectors.json, which ios/scripts/export-people-vectors.cjs makes by running the TypeScript as it
/// is (ui/test/iospeople.sim.cjs checks it is current).
///
/// The SERVER decides (src/routes/people.py, src/people.py, src/api/navidrome_admin.py): every write is made in Navidrome
/// as the signed-in admin, with their own Navidrome password typed once to unlock People for this session - held there
/// for UNLOCK_IDLE_SECONDS since it was last used. These are what the page says while typing, which changes a row offers
/// (the server's `can`), what each answer means and what is said after it. Strings are compared and measured as
/// JavaScript does - UTF-16 units, `toLowerCase()` as JSText folds it, `trim()` as JSText trims.
///
/// Nothing here keeps a password: the forms and the bodies holding one say none of it when printed, dumped or logged.
public enum People {
    // MARK: the numbers (people.ts, src/people.py, navidrome_admin.py)

    /// people.ts NAME_MAX, DISPLAY_MAX (src/people.py's), in UTF-16 units as JavaScript counts a length.
    public static let nameMax = 32
    public static let displayMax = 64
    /// people.ts UNLOCK_IDLE_MINUTES: how long an unlock lasts unused - src/api/navidrome_admin.py UNLOCK_IDLE_SECONDS.
    public static let unlockIdleMinutes = 15
    public static let unlockIdleSeconds: Double = 900
    /// The phone's own: how long after its last People answer it asks again whether the unlock still stands - two
    /// seconds past the server's 900, so the ask always comes after the server's unlock has run out (every answer the
    /// phone hears was made after the server last used the unlock) and never keeps it alive. See `idleDue`.
    public static let idleCheckSeconds: Double = unlockIdleSeconds + 2
    /// people.ts RESERVED (src/auth.py RESERVED_NAMES).
    public static let reserved = ["local", "deadwax"]
    /// people.ts TESTED_NAVIDROME: another minor version gets a note, never a block.
    public static let testedNavidrome = "0.64"
    /// src/routes/people.py WRITES_PER_MINUTE: a write past them is refused (429, kind "busy") with nothing sent.
    public static let writesPerMinute = 10
    /// AddPerson.tsx's and ResetPassword.tsx's fields take this many UTF-16 units past each rule's most (`maxLength=
    /// {NAME_MAX + 8}`), so a name or password typed a little long is said too long rather than cut short unseen.
    public static let fieldRoom = 8
    public static var userField: Int { nameMax + fieldRoom }
    public static var displayField: Int { displayMax + fieldRoom }
    public static var passwordField: Int { OwnPassword.passwordMax + fieldRoom }

    /// What a field keeps of what was typed or pasted: whole characters, while they fit in `most` UTF-16 units (an HTML
    /// field's `maxLength` counts units; the phone never splits a character to fit).
    public static func clipped(_ typed: String, to most: Int) -> String {
        guard typed.utf16.count > most else { return typed }
        var kept = "", units = 0
        for character in typed {
            let size = character.utf16.count
            guard units + size <= most else { break }
            kept.append(character)
            units += size
        }
        return kept
    }

    // MARK: the web's words (people.ts, permissions.ts) - held by the fixture

    /// The page's title (People.tsx's `<h1>`, You.tsx's row).
    public static let title = "People"
    public static let unlockTitle = "Unlock People"
    public static func unlockLine(_ user: String) -> String {
        "People changes Navidrome's accounts as you, \(user). Navidrome needs your password for that; deadwax uses it "
            + "once and doesn't keep it."
    }

    public static let unlockedLine = "Unlocked on this device until it's left alone for \(unlockIdleMinutes) minutes. "
        + "Lock ends it now."
    public static let sharingDoc = "https://github.com/real-lizardwizard/deadwax/blob/main/docs/sharing.md"
    public static let knownOnlyTitle = "Known only to deadwax"
    public static let knownOnlyLine = "People deadwax still keeps things for who no longer have a Navidrome account - "
        + "deleted in Navidrome's own Users page, or a removal deadwax couldn't finish."
    /// permissions.ts PEOPLE_ONLY: the page's words for someone who isn't a Navidrome admin, and for a 403.
    public static let peopleOnly = "Only an admin can open People - it comes with being a Navidrome admin."
    /// permissions.ts PEOPLE_LINE and ADMINS_EVERYTHING.
    public static let peopleLine = "People - Navidrome admins only"
    public static let adminsEverything = "Admins can do everything."
    /// permissions.ts WARN_SERVER, WARN_LIBRARY, WARN_NO_REQUEST.
    public static let warnServer = "Settings can point deadwax at other folders and change how it downloads and files - "
        + "give it only to someone you'd trust as an admin."
    public static let warnLibrary = "This includes deleting albums from disk, which can't be undone."
    public static let warnNoRequest = "They can still play, look through and add what the collection has."

    /// The five an admin can tick for an ordinary person, in People's order (permissions.ts CATEGORIES).
    public static let categories: [Access.Permission] = [.request, .edit, .library, .downloads, .server]

    /// permissions.ts LABELS.
    public static func label(_ permission: Access.Permission) -> String {
        switch permission {
        case .request: return "Get albums"
        case .edit: return "Edit albums"
        case .library: return "Look after the library"
        case .downloads: return "Everyone's downloads"
        case .server: return "Settings and the log"
        case .people: return "People"
        }
    }

    /// permissions.ts LINES: what each opens, under its box (People's has none - `peopleLine` says it).
    public static func line(_ permission: Access.Permission) -> String {
        switch permission {
        case .request: return "Search Soulseek and download - Get, Sources, Another source, Same source again."
        case .edit: return "Tags, covers, CD art, lyrics, artist pictures, applying a release - one album or Library "
            + "care's runs."
        case .library: return "Delete albums, move an artist's albums, Needs a look, Rescan, In nobody's library."
        case .downloads: return "See who asked for what, cancel or retry anyone's, clear everyone's finished."
        case .server: return "The server settings and the event log."
        case .people: return peopleLine
        }
    }

    // MARK: the page's own words (People.tsx, UnlockPeople.tsx, AddPerson.tsx, ResetPassword.tsx, RemovePerson.tsx,
    // usePeople.ts) - held by the fixture where the web says them

    public static let lock = "Lock"
    public static let everyone = "Everyone in Navidrome"
    public static let permissionsTitle = "Permissions"
    public static let savePermissions = "Save permissions"
    public static let saving = "Saving…"
    public static let unlockLabel = "Your Navidrome password"
    public static let unlock = "Unlock"
    public static let unlocking = "Unlocking…"
    public static let addTitle = "Add a person"
    public static let addLine = "Makes a Navidrome account for an ordinary listener. You can make them an admin afterwards."
    public static let userLabel = "User name"
    public static let displayLabel = "Display name (optional)"
    public static let passwordLabel = "Password"
    public static let againLabel = "Password again"
    public static let make = "Make account"
    public static let making = "Making…"
    public static let newPasswordLabel = "New password"
    /// The phone's: the web's Reset says "Again" under New password - read alone by VoiceOver, or as a Form's row, it
    /// says nothing of what it's for (Change password's departure, OwnPassword.againLabel).
    public static let newAgainLabel = "New password again"
    public static let resetButton = "Reset password"
    public static let resetting = "Resetting…"
    public static let cancel = "Cancel"
    public static let typeTheName = "Type their user name to remove them"
    public static let removing = "Removing…"
    public static let keepAsItIs = "Keep as it is"
    public static let changing = "Changing…"
    public static let forget = "Forget"
    public static let forgetting = "Forgetting…"
    public static let keepIt = "Keep it"
    /// The Known only row's button (People.tsx `Forget…`).
    public static let forgetEllipsis = "Forget…"
    /// usePeople.ts: the list couldn't be read.
    public static let readFailed = "Couldn't read Navidrome's accounts."

    /// Reset password…'s name for its form (ResetPassword.tsx's aria-label) - the phone's sheet's title.
    public static func resetTitle(_ user: String) -> String { "Reset \(user)'s password" }
    /// Remove's title and its button.
    public static func removeTitle(_ user: String) -> String { "Remove \(user)?" }
    public static func removeButton(_ user: String) -> String { "Remove \(user)" }
    /// What an admin flip says once it is done (People.tsx's flip).
    public static func flipped(user: String, admin: Bool) -> String {
        admin ? "\(user) is an admin now." : "\(user) is no longer an admin."
    }

    public static func removed(_ user: String) -> String { "Removed \(user) from Navidrome and deadwax." }
    public static func forgot(_ user: String) -> String { "deadwax forgot what it kept for \(user)." }
    public static func forgetQuestion(_ user: String) -> String {
        "Forget what deadwax keeps for \(user)? Their library list, pins, settings and permissions go - the albums stay "
            + "in the collection."
    }

    // MARK: the phone's own words

    /// A row whose account the list no longer has (removed elsewhere, or by this phone): navidrome_admin's not_found.
    public static let gone = "That account isn't in Navidrome any more."
    /// The first read's spinner (People.tsx's `aria-label`).
    public static let loading = "Loading"
    /// A sheet still up when People locked again (the unlock ran out, or a write was refused `locked`): the passwords
    /// typed in it are gone (Add's names stay, for when it opens again).
    public static let lockedNote = "People locked again - close this and unlock it with your Navidrome password. The "
        + "passwords typed here are gone."
    /// A sheet's Close, and Add's once a person is made.
    public static let close = "Close"
    public static let done = "Done"
    /// The Sharing deadwax link's words (People.tsx's), shown with logins off.
    public static let sharing = "Sharing deadwax"
    /// The Add button's name in the bar, for VoiceOver (its symbol is `addSymbol`).
    public static let addSymbol = "plus"
    /// What a write said when deadwax gave no words of its own (ErrorWords' `failed`).
    public static let unlockFailed = "Couldn't unlock People."
    public static let lockFailed = "Couldn't lock People."
    public static let createFailed = "Couldn't make the account."
    public static let resetFailed = "Couldn't reset the password."
    public static let adminFailed = "Couldn't change the admin role."
    public static let removeFailed = "Couldn't remove them."
    public static let forgetFailed = "Couldn't forget them."
    public static let saveFailed = "Couldn't save the permissions."

    /// The server's words name the web app's path to Change password (src/people.py YOUR_PASSWORD); on the phone it is
    /// under Settings - said as the phone has it, wherever People shows them.
    public static let webPasswordPlace = "You → Account → Change password"
    public static let phonePasswordPlace = "Settings → Account → Change password"

    public static func onPhone(_ words: String) -> String {
        words.replacingOccurrences(of: webPasswordPlace, with: phonePasswordPlace, options: .literal)
    }

    public static func onPhone(_ words: String?) -> String? {
        words.map { onPhone($0) }
    }

    // MARK: who is offered it

    /// Whether Manage offers People (permissions.ts `managing(perms, loginsOn).people`): a Navidrome admin's, with
    /// logins on - with them off, anyone who can reach deadwax is its admin, and there is nobody to manage.
    public static func offered(_ access: Access) -> Bool {
        Managing.parts(access.permissions, loginsOn: access.on).people
    }

    /// Whether the page opens for this person (permissions.ts `opensPage(perms, 'people')`): on the permission alone -
    /// with logins off the page itself says why it can't work (`NEEDS_LOGINS`). Without it the page says `peopleOnly`.
    public static func allowed(_ access: Access) -> Bool {
        access.permissions.contains(.people)
    }

    // MARK: the rules (people.ts) - for typing; the server decides

    /// people.ts `cleanName`: trimmed and lowercased, as JavaScript does both.
    public static func cleanName(_ typed: String) -> String {
        JSText.lowercase(JSText.trim(typed))
    }

    /// people.ts NAME_PATTERN `^[a-z0-9][a-z0-9._-]{0,31}$`, unit by unit (JavaScript's `$` with no `m` flag is the end
    /// alone, never before a last newline).
    static func namePattern(_ name: String) -> Bool {
        let units = Array(name.utf16)
        guard (1...nameMax).contains(units.count) else { return false }
        func letterOrDigit(_ unit: UInt16) -> Bool { (0x61...0x7A).contains(unit) || (0x30...0x39).contains(unit) }
        return letterOrDigit(units[0])
            && units.dropFirst().allSatisfy { letterOrDigit($0) || $0 == 0x2E || $0 == 0x5F || $0 == 0x2D }
    }

    /// people.ts `nameProblem`: why `name` (cleaned) can't be a new account's - or nil.
    public static func nameProblem(_ name: String) -> String? {
        if name.isEmpty { return "Type a user name." }
        if name.utf16.count > nameMax { return "A user name is at most \(nameMax) characters." }
        if !namePattern(name) {
            return "A user name is lowercase letters, digits, dots, underscores and hyphens, starting with a letter or a "
                + "digit."
        }
        if reserved.contains(where: { same($0, name) }) {
            return "'\(name)' is a name deadwax keeps for itself - choose another."
        }
        return nil
    }

    /// people.ts `displayProblem`: the display name trimmed, then measured and its control characters looked for.
    public static func displayProblem(_ display: String) -> String? {
        let shown = JSText.trim(display)
        if shown.utf16.count > displayMax { return "A display name is at most \(displayMax) characters." }
        if shown.utf16.contains(where: OwnPassword.isControl) { return "A display name can't have control characters in it." }
        return nil
    }

    /// people.ts `passwordProblem` - Change password's own (OwnPassword), the same rules.
    public static func passwordProblem(_ password: String, again: String, name: String) -> String? {
        OwnPassword.passwordProblem(password, again: again, name: name)
    }

    /// people.ts `formProblem`: the first problem of a field once there is something in it - never a scold for a field
    /// not yet reached.
    public static func formProblem(_ form: PeopleAddForm) -> String? {
        let name = cleanName(form.user)
        if !form.user.isEmpty, let problem = nameProblem(name) { return problem }
        if let problem = displayProblem(form.name) { return problem }
        if !form.password.isEmpty, !form.again.isEmpty,
           let problem = passwordProblem(form.password, again: form.again, name: name) {
            return problem
        }
        return nil
    }

    /// people.ts `formReady`: every rule met.
    public static func formReady(_ form: PeopleAddForm) -> Bool {
        let name = cleanName(form.user)
        return nameProblem(name) == nil && displayProblem(form.name) == nil
            && passwordProblem(form.password, again: form.again, name: name) == nil
    }

    /// ResetPassword.tsx's `wrong`: the problem shown once both fields have something in them.
    public static func resetProblem(_ passwords: PeoplePasswords, user: String) -> String? {
        guard !passwords.password.isEmpty, !passwords.again.isEmpty else { return nil }
        return passwordProblem(passwords.password, again: passwords.again, name: user)
    }

    /// ResetPassword.tsx's `ready`.
    public static func resetReady(_ passwords: PeoplePasswords, user: String) -> Bool {
        passwordProblem(passwords.password, again: passwords.again, name: user) == nil
    }

    // MARK: a row (people.ts)

    /// people.ts `chips`: what follows a person's name.
    public static func chips(_ person: PeoplePerson) -> [String] {
        (person.you ? ["You"] : []) + (person.admin ? ["Admin"] : [])
            + (person.sharedAccount ? ["deadwax's own account"] : []) + (person.reserved ? ["Can't sign in to deadwax"] : [])
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    /// people.ts `ago`: "just now", "5 minutes ago", "3 days ago", "4 months ago" - each step floored.
    public static func ago(_ seconds: Double) -> String {
        if seconds < 60 { return "just now" }
        let minutes = (seconds / 60).rounded(.down)
        if minutes < 60 { return "\(plural(Int(minutes), "minute", "minutes")) ago" }
        let hours = (minutes / 60).rounded(.down)
        if hours < 24 { return "\(plural(Int(hours), "hour", "hours")) ago" }
        let days = (hours / 24).rounded(.down)
        if days < 60 { return "\(plural(Int(days), "day", "days")) ago" }
        return "\(plural(Int((days / 30).rounded(.down)), "month", "months")) ago"
    }

    /// people.ts `signInWords`: their deadwax sign-ins now, or the last one, or none - `now` in epoch seconds.
    public static func signInWords(_ person: PeoplePerson, now: Double) -> String {
        if person.signedIn > 0 { return "Signed in on \(plural(person.signedIn, "device", "devices"))" }
        if let last = person.lastSignIn { return "Last signed in \(ago(max(0, now - last)))" }
        return "Never signed in to deadwax"
    }

    /// people.ts `libraryWords`.
    public static func libraryWords(_ person: PeoplePerson) -> String {
        "\(plural(person.library, "album", "albums")) in their library"
    }

    /// people.ts `librariesWarning`: only when a non-admin has no Navidrome library at all.
    public static func librariesWarning(_ person: PeoplePerson) -> String? {
        guard !person.admin, person.libraries == 0 else { return nil }
        return "Navidrome gives them no library - they'll see nothing. Choose one for them in Navidrome's Users page."
    }

    /// A change a row offers (people.ts `Action`): its kind, its label, and why it isn't offered - the server's words -
    /// or nil.
    public struct Action: Sendable, Equatable, Hashable {
        public enum Kind: String, Sendable, Hashable { case reset, admin, remove }
        public let kind: Kind
        public let label: String
        public let refused: String?

        public init(kind: Kind, label: String, refused: String?) {
            self.kind = kind
            self.label = label
            self.refused = refused
        }

        /// Offered: no reason given (an empty one is no reason, as JavaScript reads `!action.refused`).
        public var offered: Bool { !People.says(refused) }
    }

    /// people.ts `actions`: Reset password…, Make admin or No longer admin, Remove…, each with the server's reason.
    public static func actions(_ person: PeoplePerson) -> [Action] {
        [Action(kind: .reset, label: "Reset password…", refused: person.can.reset),
         Action(kind: .admin, label: person.admin ? "No longer admin" : "Make admin", refused: person.can.admin),
         Action(kind: .remove, label: "Remove…", refused: person.can.remove)]
    }

    /// people.ts `refusals`: the reasons a row shows, once each, in their order.
    public static func refusals(_ person: PeoplePerson) -> [String] {
        var seen: [String] = []
        for action in actions(person) {
            guard let refused = action.refused, says(refused), !seen.contains(where: { same($0, refused) }) else { continue }
            seen.append(refused)
        }
        return seen
    }

    /// people.ts `removeReady`: exactly their user name - not another case, not with a space.
    public static func removeReady(_ typed: String, user: String) -> Bool {
        same(typed, user) && !user.isEmpty
    }

    /// Make admin's question and what it gives (people.ts `makeAdminWords`).
    public struct Question: Sendable, Equatable {
        public let question: String
        public let body: String

        public init(question: String, body: String) {
            self.question = question
            self.body = body
        }
    }

    public static func makeAdminWords(_ user: String) -> Question {
        Question(question: "Make \(user) an admin?",
                 body: "In deadwax they'll edit and delete albums, see everyone's downloads, Needs a look, Library care, "
                    + "Server settings, the event log and People. In Navidrome they become an admin too: its Users, "
                    + "libraries and settings, every library, and - in their other music apps too - everyone's "
                    + "playlists, private ones included.")
    }

    /// people.ts `unmakeAdminWords`: what they keep (Navidrome's libraries; what was ticked before).
    public static func unmakeAdminWords(_ user: String, ticked: [String]) -> Question {
        let before = ticked.isEmpty ? "" : " They keep what they were given before: \(ticked.joined(separator: ", "))."
        return Question(question: "\(user) no longer an admin?",
                        body: "\(user) keeps every library Navidrome gave them as an admin - narrow them in Navidrome's "
                            + "Users page if they shouldn't see them all.\(before)")
    }

    /// People.tsx's `ticked`: the labels of what an admin ticked for them, in People's order - none for an admin.
    public static func tickedLabels(_ person: PeoplePerson) -> [String] {
        guard let ticks = person.permissions else { return [] }
        return categories.filter { ticks[$0] }.map(label)
    }

    /// The flip's go-ahead button (People.tsx's ConfirmLine `confirm`): the row's own action label.
    public static func flipButton(_ person: PeoplePerson) -> String {
        person.admin ? "No longer admin" : "Make admin"
    }

    /// The flip's question for this row: People.tsx's `words`.
    public static func flipWords(_ person: PeoplePerson) -> Question {
        person.admin ? unmakeAdminWords(person.user, ticked: tickedLabels(person)) : makeAdminWords(person.user)
    }

    /// Remove's lines (people.ts `removeLines`), from the server's numbers.
    public struct RemoveLines: Sendable, Equatable {
        public let navidrome: String
        public let deadwax: String
        public let stays: String
        public let undo: String
    }

    public static func removeLines(_ person: PeoplePerson) -> RemoveLines {
        let role = person.admin ? ", and their admin role" : ""
        let waitingCount = person.waitingAlone, one = waitingCount == 1
        let waiting = waitingCount != 0
            ? " \(plural(waitingCount, "download", "downloads")) only they are waiting for carr\(one ? "ies" : "y") on and "
                + "\(one ? "is" : "are") filed for nobody - cancel \(one ? "it" : "them") in Requests first if nobody "
                + "wants \(one ? "it" : "them")."
            : ""
        let favourites = person.library != 0 ? " (the \(plural(person.library, "album", "albums")) in their library)" : ""
        let devices = person.signedIn != 0 ? " (\(plural(person.signedIn, "device", "devices")))" : ""
        return RemoveLines(
            navidrome: "In Navidrome, for good: \(person.user)'s account, their play counts and play history, their "
                + "favourites\(favourites), all their playlists - shared ones too - and their Last.fm or ListenBrainz "
                + "link\(role).",
            deadwax: "In deadwax: their sign-ins\(devices), their library list, their pins, their play queue and the songs "
                + "they played, Getting albums settings and permissions.",
            stays: "Stays: every album in the collection.\(waiting)",
            undo: "There's no undo. If they might come back, reset their password instead.")
    }

    /// people.ts `knownWords`: what a name known only to deadwax keeps.
    public static func knownWords(_ entry: PeopleKnownOnly) -> String {
        var parts: [String] = []
        if entry.sessions != 0 { parts.append(plural(entry.sessions, "sign-in", "sign-ins")) }
        if entry.credential { parts.append("a kept login") }
        if entry.library != 0 { parts.append(plural(entry.library, "album in their library", "albums in their library")) }
        if entry.pins != 0 { parts.append(plural(entry.pins, "pin", "pins")) }
        if entry.preferences { parts.append("Getting albums settings") }
        if entry.requests != 0 { parts.append(plural(entry.requests, "request", "requests")) }
        if entry.permissions != 0 { parts.append(plural(entry.permissions, "permission", "permissions")) }
        if entry.queue { parts.append("a play queue") }
        if let history = entry.history, history != 0 {
            parts.append("\(grouped(history)) \(history == 1 ? "song they played" : "songs they played")")
        }
        return parts.isEmpty ? "deadwax keeps a little history for them." : "deadwax keeps \(parts.joined(separator: ", "))."
    }

    /// A whole number as `toLocaleString('en-US')` writes it: its thousands grouped with commas.
    static func grouped(_ number: Int) -> String {
        let digits = String(number.magnitude)
        var out = ""
        for (at, digit) in digits.enumerated() {
            if at > 0, (digits.count - at) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return number < 0 ? "-" + out : out
    }

    // MARK: after a change (people.ts)

    /// people.ts `madeWords`: what to tell them - `origin` deadwax's address as the phone has it (scheme, host, port).
    public static func madeWords(_ user: String, origin: String) -> String {
        "Made \(user). Tell them their user name, the password you chose and deadwax's address (\(origin)/player/) - "
            + "their other music apps sign in with the same user name and password."
    }

    /// deadwax's address as the web's `location.origin` names it: the phone's base, which has no path.
    public static func origin(_ server: ServerAddress?) -> String {
        server?.base.absoluteString ?? ""
    }

    /// people.ts `resetWords`.
    public static func resetWords(_ user: String, signedOut: Int) -> String {
        "Done. \(user) is signed out of deadwax on \(plural(signedOut, "device", "devices")) and signs in with the new "
            + "password - their other music apps need it too."
    }

    /// permissions.ts `savedWords`.
    public static func savedWords(_ user: String) -> String {
        "Saved - \(user) has them from their next tap."
    }

    // MARK: the page (people.ts)

    /// people.ts `httpNote`, for deadwax's address as the phone has it (OwnPassword's).
    public static func httpNote(at server: ServerAddress?) -> String? {
        OwnPassword.httpNote(at: server)
    }

    /// people.ts `versionNote`: a note when Navidrome's status names another minor version than People was checked with
    /// - `server` is /deadwax/navidrome/status's ("Navidrome 0.65.0 (abc)"). Read as `/(\d+)\.(\d+)(?:\.(\d+))?/`
    /// finds it: the first run of ASCII digits followed by a dot and a digit, then that run of digits, then a dot and
    /// a third run if there is one.
    public static func versionNote(_ server: String?) -> String? {
        guard let found = version(in: server ?? "") else { return nil }
        if same("\(found.major).\(found.minor)", testedNavidrome) { return nil }
        return "Your Navidrome (\(found.whole)) isn't the one People was checked with (\(testedNavidrome)). If something "
            + "here doesn't work, use Navidrome's own Users page."
    }

    static func version(in text: String) -> (whole: String, major: String, minor: String)? {
        let units = Array(text.utf16)
        func digit(_ at: Int) -> Bool { at < units.count && (0x30...0x39).contains(units[at]) }
        func run(from at: Int) -> Int {
            var end = at
            while digit(end) { end += 1 }
            return end
        }
        func string(_ from: Int, _ to: Int) -> String { String(decoding: units[from..<to], as: UTF16.self) }
        var start = 0
        while start < units.count {
            guard digit(start) else {
                start += 1
                continue
            }
            let majorEnd = run(from: start)
            if majorEnd < units.count, units[majorEnd] == 0x2E, digit(majorEnd + 1) {
                let minorEnd = run(from: majorEnd + 1)
                var end = minorEnd
                if minorEnd < units.count, units[minorEnd] == 0x2E, digit(minorEnd + 1) {
                    end = run(from: minorEnd + 1)
                }
                return (string(start, end), string(start, majorEnd), string(majorEnd + 1, minorEnd))
            }
            // every start inside this run of digits ends at the same place, so none of them can match either
            start = majorEnd
        }
        return nil
    }

    /// What the page draws (people.ts `PeopleView`): asked and not yet answered, People can't work here (the problem
    /// alone), Unlock People, or the list.
    public enum View: String, Sendable, Equatable {
        case asking, unavailable, locked, list
    }

    /// people.ts `peopleView`.
    public static func view(_ state: PeopleState?) -> View {
        guard let state else { return .asking }
        if !state.available { return .unavailable }
        return state.locked ? .locked : .list
    }

    /// An answer that says Navidrome refused the person as one of its admins (`not_admin` from the list's read: not
    /// available and not locked - every other way People can't work says it locked): /me is asked again, so the
    /// permission goes and the page says `peopleOnly`.
    public static func saysNotAdmin(_ state: PeopleState) -> Bool {
        !state.available && !state.locked
    }

    // MARK: Permissions (permissions.ts)

    /// One checkbox of a person's Permissions (permissions.ts `Checkbox`).
    public struct Checkbox: Sendable, Equatable, Hashable {
        public let category: Access.Permission
        public let label: String
        public let line: String
        public let checked: Bool
        public let locked: Bool
        public let warning: String?
    }

    /// permissions.ts `checkboxes(admin, refused, ticked)`: an admin's all ticked and locked; a row People refuses
    /// permissions for locked as they are; anyone else's as `ticked` says, each tick adding its warning.
    public static func checkboxes(admin: Bool, refused: String?, ticked: PeopleTicks?) -> [Checkbox] {
        let refusing = says(refused)
        return categories.map { category in
            let checked = admin ? true : (ticked?[category] ?? false)
            let warning: String?
            if admin || refusing {
                warning = nil
            } else if category == .server && checked {
                warning = warnServer
            } else if category == .library && checked {
                warning = warnLibrary
            } else if category == .request && !checked {
                warning = warnNoRequest
            } else {
                warning = nil
            }
            return Checkbox(category: category, label: label(category), line: line(category), checked: checked,
                            locked: admin || refusing, warning: warning)
        }
    }

    /// permissions.ts `lockedReason`: what the Permissions say above the boxes when they can't be changed - the
    /// server's words as they came (an empty one included, which the page draws as nothing).
    public static func lockedReason(admin: Bool, refused: String?) -> String? {
        admin ? adminsEverything : refused
    }

    /// permissions.ts `changed`: whether a draft differs from what was saved - Save permissions is on only then.
    public static func changed(saved: PeopleTicks?, draft: PeopleTicks?) -> Bool {
        guard let saved, let draft else { return false }
        return categories.contains { saved[$0] != draft[$0] }
    }

    /// Save permissions is drawn (People.tsx): not for an admin, nor a row People refuses permissions for.
    public static func savesPermissions(_ person: PeoplePerson) -> Bool {
        !person.admin && !says(person.can.permissions)
    }

    // MARK: the pages kept

    /// The pages the Settings tab keeps when it is tapped again (AppNavigation.backToRoot, beside Change password's): none
    /// - or, while a People write is out, every page up to the last of People's, where its answer is said. `pages` is
    /// the tab's pages, each whether it is one of People's.
    public static func pagesKept(_ pages: [Bool], writing: Bool) -> Int {
        guard writing, let at = pages.lastIndex(of: true) else { return 0 }
        return at + 1
    }

    // MARK: the idle unlock

    /// Whether the unlock has been left alone long enough to have run out on the server: `idleCheckSeconds` since the
    /// phone last heard a People answer while the list showed (`answeredAt`, on the phone's own clock - one that goes on
    /// counting while the phone sleeps). The server counts its 900 from when it last used the unlock, which is always
    /// before deadwax answered, so this is never early: the read it brings finds the unlock gone rather than using it -
    /// and Unlock People comes back, as the web's does at its next ask.
    public static func idleDue(answeredAt: Double?, now: Double) -> Bool {
        guard let answeredAt else { return false }
        return now - answeredAt >= idleCheckSeconds
    }

    // MARK: JavaScript's comparisons

    static func same(_ one: String, _ other: String) -> Bool { one.utf16.elementsEqual(other.utf16) }

    /// A reason the server gave, as JavaScript reads it: present and not empty.
    static func says(_ reason: String?) -> Bool { !(reason ?? "").isEmpty }
}

// MARK: - what the list says (src/routes/people.py, ui/src/api/people.ts)

/// What an admin ticked for an ordinary person (people.ts' `Record<Category, boolean>`), one box per category - a box
/// the answer leaves out (or sends as another type) reads unticked, as the web's `!!ticked?.[category]` does.
public struct PeopleTicks: Codable, Sendable, Equatable, Hashable {
    public var request: Bool
    public var edit: Bool
    public var library: Bool
    public var downloads: Bool
    public var server: Bool

    enum CodingKeys: String, CodingKey { case request, edit, library, downloads, server }

    public init(request: Bool = false, edit: Bool = false, library: Bool = false, downloads: Bool = false,
                server: Bool = false) {
        self.request = request
        self.edit = edit
        self.library = library
        self.downloads = downloads
        self.server = server
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        request = fields.looseField(Bool.self, .request) ?? false
        edit = fields.looseField(Bool.self, .edit) ?? false
        library = fields.looseField(Bool.self, .library) ?? false
        downloads = fields.looseField(Bool.self, .downloads) ?? false
        server = fields.looseField(Bool.self, .server) ?? false
    }

    /// A category's box; People, which nobody ticks, is never.
    public subscript(_ category: Access.Permission) -> Bool {
        get {
            switch category {
            case .request: return request
            case .edit: return edit
            case .library: return library
            case .downloads: return downloads
            case .server: return server
            case .people: return false
            }
        }
        set {
            switch category {
            case .request: request = newValue
            case .edit: edit = newValue
            case .library: library = newValue
            case .downloads: downloads = newValue
            case .server: server = newValue
            case .people: break
            }
        }
    }
}

/// For each change, why People refuses it - nil when it is allowed (src/people.py `refusals`). A field left out reads
/// as nil: the server, which decides every write again, refuses it if it must.
public struct PeopleCan: Decodable, Sendable, Equatable, Hashable {
    public let reset: String?
    public let remove: String?
    public let admin: String?
    public let permissions: String?

    enum CodingKeys: String, CodingKey { case reset, remove, admin, permissions }

    public init(reset: String? = nil, remove: String? = nil, admin: String? = nil, permissions: String? = nil) {
        self.reset = reset
        self.remove = remove
        self.admin = admin
        self.permissions = permissions
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        reset = fields.looseField(String.self, .reset)
        remove = fields.looseField(String.self, .remove)
        admin = fields.looseField(String.self, .admin)
        permissions = fields.looseField(String.self, .permissions)
    }
}

/// One Navidrome account, joined with what deadwax knows of it (src/people.py `person`). Known by its id - an answer's
/// row without one is left out.
public struct PeoplePerson: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let user: String
    public let name: String
    public let admin: Bool
    /// It is NAVIDROME_USER - deadwax's own account.
    public let sharedAccount: Bool
    /// `local` or `deadwax`: nobody signs in to deadwax as it.
    public let reserved: Bool
    public let you: Bool
    /// Live deadwax sessions.
    public let signedIn: Int
    /// When they last signed in to deadwax, epoch seconds - nil never.
    public let lastSignIn: Double?
    /// Albums in their library.
    public let library: Int
    /// Downloads still coming that only they are waiting for.
    public let waitingAlone: Int
    /// How many Navidrome libraries they may see - nil when Navidrome didn't say.
    public let libraries: Int?
    /// What an admin ticked for them - nil for an admin, who has everything.
    public let permissions: PeopleTicks?
    public let can: PeopleCan

    enum CodingKeys: String, CodingKey {
        case id, user, name, admin, reserved, you, library, libraries, permissions, can
        case sharedAccount = "shared_account"
        case signedIn = "signed_in"
        case lastSignIn = "last_sign_in"
        case waitingAlone = "waiting_alone"
    }

    public init(id: String, user: String, name: String = "", admin: Bool = false, sharedAccount: Bool = false,
                reserved: Bool = false, you: Bool = false, signedIn: Int = 0, lastSignIn: Double? = nil, library: Int = 0,
                waitingAlone: Int = 0, libraries: Int? = nil, permissions: PeopleTicks? = nil, can: PeopleCan = PeopleCan()) {
        self.id = id
        self.user = user
        self.name = name
        self.admin = admin
        self.sharedAccount = sharedAccount
        self.reserved = reserved
        self.you = you
        self.signedIn = signedIn
        self.lastSignIn = lastSignIn
        self.library = library
        self.waitingAlone = waitingAlone
        self.libraries = libraries
        self.permissions = permissions
        self.can = can
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: fields, debugDescription: "an account with no id")
        }
        user = fields.looseField(String.self, .user) ?? ""
        let named = fields.looseField(String.self, .name) ?? ""
        name = named.isEmpty ? user : named
        admin = fields.looseField(Bool.self, .admin) ?? false
        sharedAccount = fields.looseField(Bool.self, .sharedAccount) ?? false
        reserved = fields.looseField(Bool.self, .reserved) ?? false
        you = fields.looseField(Bool.self, .you) ?? false
        signedIn = fields.looseField(Int.self, .signedIn) ?? 0
        lastSignIn = fields.looseField(Double.self, .lastSignIn)
        library = fields.looseField(Int.self, .library) ?? 0
        waitingAlone = fields.looseField(Int.self, .waitingAlone) ?? 0
        libraries = fields.looseField(Int.self, .libraries)
        permissions = fields.looseField(PeopleTicks.self, .permissions)
        can = fields.looseField(PeopleCan.self, .can) ?? PeopleCan()
    }
}

/// A name deadwax keeps things for that Navidrome has no account for (src/people.py `known_only`, store.known_users'
/// counts). Known by its name.
public struct PeopleKnownOnly: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let user: String
    public let sessions: Int
    public let credential: Bool
    public let library: Int
    public let pins: Int
    public let preferences: Bool
    public let requests: Int
    public let permissions: Int
    /// (2.0.0-player.64) the play queue deadwax keeps beside Navidrome's.
    public let queue: Bool
    /// (2.1.14) how many songs they played that deadwax keeps.
    public let history: Int?

    public var id: String { user }

    enum CodingKeys: String, CodingKey {
        case user, sessions, credential, library, pins, preferences, requests, permissions, queue, history
    }

    public init(user: String, sessions: Int = 0, credential: Bool = false, library: Int = 0, pins: Int = 0,
                preferences: Bool = false, requests: Int = 0, permissions: Int = 0, queue: Bool = false,
                history: Int? = nil) {
        self.user = user
        self.sessions = sessions
        self.credential = credential
        self.library = library
        self.pins = pins
        self.preferences = preferences
        self.requests = requests
        self.permissions = permissions
        self.queue = queue
        self.history = history
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        user = try fields.decode(String.self, forKey: .user)
        guard !user.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .user, in: fields, debugDescription: "a name with no name")
        }
        sessions = fields.looseField(Int.self, .sessions) ?? 0
        credential = fields.looseField(Bool.self, .credential) ?? false
        library = fields.looseField(Int.self, .library) ?? 0
        pins = fields.looseField(Int.self, .pins) ?? 0
        preferences = fields.looseField(Bool.self, .preferences) ?? false
        requests = fields.looseField(Int.self, .requests) ?? 0
        permissions = fields.looseField(Int.self, .permissions) ?? 0
        queue = fields.looseField(Bool.self, .queue) ?? false
        history = fields.looseField(Int.self, .history)
    }
}

/// `GET /deadwax/people`: People's state - and, unlocked, Navidrome's accounts and the names known only to deadwax.
/// Read fresh each time. Fail closed: an answer that doesn't say it is unlocked is locked. The rows are known by their
/// ids (names, for the known-only): a second row with an id already listed is left out, so the page's lists, keyed
/// by them, draw each once.
public struct PeopleState: Decodable, Sendable, Equatable {
    /// Logins are on.
    public let on: Bool
    /// People can work here: logins on, a Navidrome sign-in, NAVIDROME_URL usable.
    public let available: Bool
    public let locked: Bool
    public let problem: String?
    public let fix: String?
    public let you: String
    /// NAVIDROME_USER, lowercased.
    public let account: String?
    public let people: [PeoplePerson]
    public let knownOnly: [PeopleKnownOnly]

    enum CodingKeys: String, CodingKey {
        case on, available, locked, problem, fix, you, account, people
        case knownOnly = "known_only"
    }

    public init(on: Bool = true, available: Bool = true, locked: Bool = true, problem: String? = nil, fix: String? = nil,
                you: String = "", account: String? = nil, people: [PeoplePerson] = [], knownOnly: [PeopleKnownOnly] = []) {
        self.on = on
        self.available = available
        self.locked = locked
        self.problem = problem
        self.fix = fix
        self.you = you
        self.account = account
        self.people = Self.once(people, by: \.id)
        self.knownOnly = Self.once(knownOnly, by: \.user)
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        self.init(on: fields.looseField(Bool.self, .on) ?? false,
                  available: fields.looseField(Bool.self, .available) ?? false,
                  locked: fields.looseField(Bool.self, .locked) ?? true,
                  problem: fields.looseField(String.self, .problem),
                  fix: fields.looseField(String.self, .fix),
                  you: fields.looseField(String.self, .you) ?? "",
                  account: fields.looseField(String.self, .account),
                  people: fields.looseList(PeoplePerson.self, .people) ?? [],
                  knownOnly: fields.looseList(PeopleKnownOnly.self, .knownOnly) ?? [])
    }

    /// The state locked again (usePeople.ts `locked`): the unlock form back at once, nobody listed.
    public var lockedAgain: PeopleState {
        PeopleState(on: on, available: available, locked: true, problem: problem, fix: fix, you: you, account: account)
    }

    static func once<Row>(_ rows: [Row], by key: KeyPath<Row, String>) -> [Row] {
        var seen = Set<[UInt16]>()
        return rows.filter { seen.insert(Array($0[keyPath: key].utf16)).inserted }
    }
}

// MARK: - the forms (redacted)

/// Add a person's fields (AddPerson.tsx's form). Says none of them when printed, dumped or logged.
public struct PeopleAddForm: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var user: String
    public var name: String
    public var password: String
    public var again: String

    public init(user: String = "", name: String = "", password: String = "", again: String = "") {
        self.user = user
        self.name = name
        self.password = password
        self.again = again
    }

    public var isEmpty: Bool { user.isEmpty && name.isEmpty && password.isEmpty && again.isEmpty }

    /// The passwords emptied, the names kept.
    public mutating func forgetPasswords() {
        password = ""
        again = ""
    }

    public var description: String { "PeopleAddForm(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// A new password typed twice (Reset password…'s two fields). Says neither when printed, dumped or logged.
public struct PeoplePasswords: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var password: String
    public var again: String

    public init(password: String = "", again: String = "") {
        self.password = password
        self.again = again
    }

    public var isEmpty: Bool { password.isEmpty && again.isEmpty }

    public var description: String { "PeoplePasswords(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

// MARK: - the bodies (src/routes/people.py's strict models: a field they don't declare is a 422)

/// `POST /people/unlock` (UnlockBody). Says nothing of the password when printed or dumped.
public struct PeopleUnlockBody: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                CustomReflectable {
    public let password: String

    enum CodingKeys: String, CodingKey { case password }

    public init(password: String) { self.password = password }

    public var description: String { "PeopleUnlockBody(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// `POST /people/lock` (LockBody, which declares no field): `{}`.
public struct PeopleLockBody: Encodable, Sendable, Equatable {
    public init() {}

    public func encode(to encoder: any Encoder) throws {
        var body = encoder.singleValueContainer()
        try body.encode([String: String]())
    }
}

/// `POST /people/create` (CreateBody): the name cleaned and the display name trimmed, as AddPerson.tsx sends them; the
/// passwords as typed. Says none of it when printed or dumped.
public struct PeopleCreateBody: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                CustomReflectable {
    public let user: String
    public let name: String
    public let password: String
    public let passwordAgain: String

    enum CodingKeys: String, CodingKey {
        case user, name, password
        case passwordAgain = "password_again"
    }

    public init(_ form: PeopleAddForm) {
        user = People.cleanName(form.user)
        name = JSText.trim(form.name)
        password = form.password
        passwordAgain = form.again
    }

    public var description: String { "PeopleCreateBody(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// `POST /people/{person_id}/password` (ResetBody): the name the page drew, and the new password twice.
public struct PeopleResetBody: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                               CustomReflectable {
    public let user: String
    public let password: String
    public let passwordAgain: String

    enum CodingKeys: String, CodingKey {
        case user, password
        case passwordAgain = "password_again"
    }

    public init(user: String, _ passwords: PeoplePasswords) {
        self.user = user
        password = passwords.password
        passwordAgain = passwords.again
    }

    public var description: String { "PeopleResetBody(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// `POST /people/{person_id}/admin` (AdminBody): the name the page drew, and what they are to be.
public struct PeopleAdminBody: Encodable, Sendable, Equatable {
    public let user: String
    public let admin: Bool

    enum CodingKeys: String, CodingKey { case user, admin }

    public init(user: String, admin: Bool) {
        self.user = user
        self.admin = admin
    }
}

/// `POST /people/{person_id}/remove` (RemoveBody): the name the page drew, and the name typed.
public struct PeopleRemoveBody: Encodable, Sendable, Equatable {
    public let user: String
    public let confirm: String

    enum CodingKeys: String, CodingKey { case user, confirm }

    public init(user: String, confirm: String) {
        self.user = user
        self.confirm = confirm
    }
}

/// `POST /people/forget` (ForgetBody).
public struct PeopleForgetBody: Encodable, Sendable, Equatable {
    public let user: String

    enum CodingKeys: String, CodingKey { case user }

    public init(user: String) { self.user = user }
}

/// `POST /people/{person_id}/permissions` (PermissionsBody): the name the page drew and all five - the server answers
/// a body leaving one out with its 422 (PEOPLE_FORM), never saving it as taken away.
public struct PeoplePermissionsBody: Encodable, Sendable, Equatable {
    public let user: String
    public let request: Bool
    public let edit: Bool
    public let library: Bool
    public let downloads: Bool
    public let server: Bool

    enum CodingKeys: String, CodingKey { case user, request, edit, library, downloads, server }

    public init(user: String, _ ticks: PeopleTicks) {
        self.user = user
        request = ticks.request
        edit = ticks.edit
        library = ticks.library
        downloads = ticks.downloads
        server = ticks.server
    }
}

// MARK: - the answers, read loosely: one field of another type is its default, never the whole answer lost

/// `POST /people/create`'s `made`.
public struct PeopleMadeAccount: Decodable, Sendable, Equatable {
    public let id: String
    public let user: String
    public let name: String

    enum CodingKeys: String, CodingKey { case id, user, name }

    public init(id: String = "", user: String = "", name: String = "") {
        self.id = id
        self.user = user
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = fields.looseField(String.self, .id) ?? ""
        user = fields.looseField(String.self, .user) ?? ""
        name = fields.looseField(String.self, .name) ?? ""
    }
}

/// `POST /people/create`: the account made, and a warning beside it (no library, the password's check unanswered).
public struct PeopleMade: Decodable, Sendable, Equatable {
    public let made: PeopleMadeAccount
    public let warning: String?

    enum CodingKeys: String, CodingKey { case made, warning }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        made = fields.looseField(PeopleMadeAccount.self, .made) ?? PeopleMadeAccount()
        let said = ErrorWords.trim(fields.looseField(String.self, .warning) ?? "")
        warning = said.isEmpty ? nil : said
    }
}

/// `POST /people/{id}/password`: whose, and how many of their devices were signed out.
public struct PeopleReset: Decodable, Sendable, Equatable {
    public let reset: String
    public let signedOut: Int

    enum CodingKeys: String, CodingKey {
        case reset
        case signedOut = "signed_out"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        reset = fields.looseField(String.self, .reset) ?? ""
        signedOut = fields.looseField(Int.self, .signedOut) ?? 0
    }
}

/// `POST /people/{id}/admin`: whose, what they are now, and whether that changed.
public struct PeopleAdminAnswer: Decodable, Sendable, Equatable {
    public let user: String
    public let admin: Bool?
    public let changed: Bool

    enum CodingKeys: String, CodingKey { case user, admin, changed }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        user = fields.looseField(String.self, .user) ?? ""
        admin = fields.looseField(Bool.self, .admin)
        changed = fields.looseField(Bool.self, .changed) ?? false
    }
}

/// Any other People answer - unlock's, lock's, remove's, forget's, permissions' - read for nothing but that it came:
/// what is said is the page's own words, and the list read again says what is so.
public struct PeopleAnswered: Decodable, Sendable, Equatable {
    public init() {}

    public init(from decoder: any Decoder) throws {}
}
