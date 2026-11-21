import DeadwaxCore
import Observation
import SwiftUI

/// People's state, held by the app (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10; the web's usePeople.ts,
/// with the state each of People.tsx's rows and forms keeps): the last answer of `GET /deadwax/people`, the write out,
/// what it said, the sheet up, and what is typed - shared by People's page and each person's, so a person's page pushed
/// from the list and the list under it are one state.
///
/// Every decision is Core's PeopleFlow: when a write may go, what its body is, what its answer does to the page, what is
/// emptied when. This carries them out: asks, waits and hands on. Each ask's ticket is taken by the flow as it is
/// decided, synchronously, before the Task that sends it - so only the newest read lands, and a write's answer is known
/// for the write it was.
///
/// READS. As People comes on screen (opened, or back from another tab after a moment, so a push between its own pages
/// asks nothing), when the app comes to the front with it up, when deadwax is back in reach, when the sign-in or Now
/// Playing goes from over it, when the session moves (Change password's re-key - the unlock was the old session's), on
/// a pull, after every write - and once the unlock has been left alone long enough to have run out on the server
/// (People.idleCheckSeconds after the last answer, on a clock that counts while the phone sleeps): that read finds it
/// gone and Unlock People comes back, as the web's next ask finds it - once per answer, so a read that fails arms no
/// other (the flow's `idleWait`). Nothing is asked under the sign-in, out of reach, in the background, with no page of
/// People showing, or without People's permission - nor anything a landing read would ask next (/me, Navidrome's
/// version, the idle check): a read landing after the sign-in came or the page went asks nothing more.
///
/// WRITES. One at a time, never sent again by itself, each held through the app going to the background
/// (BackgroundHold). While one is out the page can't be left by Back or a swipe, nor its tab tapped back past it
/// (AppNavigation.peopleWriting). After it, /me is asked again when the flow says (an admin role changed, or a 403),
/// a removed person's page is left, and the list is read again.
///
/// PASSWORDS. Typed into the flow alone - never logged, kept or put in an address; emptied by the flow as each is sent
/// or answered, and here when Now Playing comes over People, the sign-in over the app, or the person changes.
///
/// Another person (`reset`): everything of the last one's let go, and nothing still out drawn for anyone else.
@MainActor
@Observable
final class PeopleModel {
    /// The page's state machine (Core).
    private(set) var flow = PeopleFlow()
    /// Navidrome's version as `/deadwax/navidrome/status` names it - read once the list shows, for versionNote.
    private(set) var navidrome: String?

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private let navigation: AppNavigation
    /// One more each time the person changes: an answer for the last one is dropped.
    @ObservationIgnored private var generation = 0
    /// How many of People's pages show now (the list, a person's).
    @ObservationIgnored private var pagesShown = 0
    /// When the last of them went from view - a push between them hides one for a moment only.
    @ObservationIgnored private var hiddenAt: Double?
    /// The app is in front.
    @ObservationIgnored private var active = true
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var idle: Task<Void, Never>?
    @ObservationIgnored private var versionAsked = false
    /// The model's clock's zero: ContinuousClock goes on counting while the phone sleeps.
    @ObservationIgnored private let began = ContinuousClock.now

    init(server: ServerModel, reachability: Reachability, navigation: AppNavigation) {
        self.server = server
        self.reachability = reachability
        self.navigation = navigation
    }

    // MARK: what the pages draw

    /// People's permission (permissions.ts `opensPage`): without it the page says `People.peopleOnly`.
    var allowed: Bool { People.allowed(server.access) }
    var online: Bool { reachability.online }
    var signInOver: Bool { server.signInOver != nil }
    /// deadwax's own words, for whoever runs it (access.ts seesDetail).
    private var admin: Bool { server.access.seesDetail }

    /// Seconds on the model's clock.
    private var now: Double {
        let (seconds, attoseconds) = (ContinuousClock.now - began).components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    /// A read may be sent now.
    private var mayAsk: Bool {
        pagesShown > 0 && active && online && !signInOver && allowed && server.client != nil
    }

    /// A field's binding: what is typed goes into the flow - clipped to what its rule allows, by whole characters - and
    /// clears what the last write said where it is typed (it was of the fields as they were).
    func typing(_ field: WritableKeyPath<PeopleFlow, String>, at place: PeoplePlace, most: Int? = nil) -> Binding<String> {
        Binding(
            get: { self.flow[keyPath: field] },
            set: { (typed: String) -> Void in
                self.flow[keyPath: field] = most.map { People.clipped(typed, to: $0) } ?? typed
                self.flow.typed(at: place)
            }
        )
    }

    /// A permission's box on a person's page: what it shows, and a tick kept as a draft until Save.
    func ticked(_ person: PeoplePerson, _ category: Access.Permission) -> Binding<Bool> {
        Binding(
            get: { self.flow.checkboxes(for: person).first { $0.category == category }?.checked ?? false },
            set: { (on: Bool) -> Void in self.flow.tick(person, category, on) }
        )
    }

    // MARK: told

    /// One of People's pages came on screen: read when nothing has been, when what shows can't be trusted, when People
    /// was away a while (another tab - a push between its own pages hides one for a moment), or when the unlock may
    /// have run out.
    func shows() {
        let away = pagesShown == 0 && hiddenAt.map { now - $0 >= 1 } != false
        pagesShown += 1
        if flow.state == nil || !flow.real || away || flow.idleDue(now: now) {
            read()
        } else {
            // what a read landing between two of People's pages left unasked: the version, the idle check
            landed()
        }
    }

    /// One of People's pages went from view. None left on any tab: People left - nothing of it kept.
    func hides() {
        pagesShown = max(0, pagesShown - 1)
        if pagesShown == 0 { hiddenAt = now }
        leaveIfGone()
    }

    /// The scene's phase: back in front with People up, it reads again (the web's `live`).
    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            active = false
        case .active:
            guard !active else { return }
            active = true
            read()
        default:
            break
        }
    }

    /// deadwax went out of reach (nothing writes until a read lands again) or came back (read again).
    func reachChanged() {
        if online { read() } else { flow.outOfReach() }
    }

    /// The sign-in came over the app - every password emptied, the sheet put away - or went: read again.
    func signInChanged() {
        if signInOver { flow.signInCame() } else { read() }
    }

    /// (slice 10's review) The session in hand moved - Change password's re-key, a sign-in again: the unlock was the
    /// old session's, so People is read again under the new one.
    func sessionMoved() {
        read()
    }

    /// Now Playing came over the app (a full-screen cover, People's pages left shown under it): every password
    /// emptied; gone again, read again.
    func nowPlaying(_ shown: Bool) {
        if shown { flow.hidden() } else { read() }
    }

    /// A pull, or Try again: read now, and wait for it.
    func refresh() async {
        read()
        await reading?.value
    }

    // MARK: the sheets

    func open(_ sheet: PeopleSheet) {
        flow.open(sheet)
    }

    /// The sheet went - Close, Cancel, Done, a swipe: its passwords and typed name gone.
    func closed() {
        flow.closed()
    }

    /// A page went: every password emptied (the flow's own rules keep what else is typed).
    func pageGone() {
        flow.hidden()
    }

    // MARK: reading

    /// `GET /deadwax/people`, waited for by how many the last answer listed. The ticket is the flow's, taken here.
    private func read() {
        guard mayAsk, let client = server.client else { return }
        let ticket = flow.readBegan(now: now)
        // the last list's, kept through a lock: the read after Unlock brings it back
        let accounts = flow.accountsListed
        let admin = self.admin
        let mine = generation
        reading?.cancel()
        reading = Task {
            let result: PeopleRead
            do {
                result = .answered(try await client.people(accounts: accounts))
            } catch {
                result = People.readOutcome(of: error, admin: admin)
            }
            guard mine == generation else { return }
            let askMe = flow.readEnded(ticket, result, now: now)
            guard askMe != nil else { return }
            // drawn whenever it lands; asked after it only while People may ask (not under the sign-in, nor once gone)
            if askMe == true, mayAsk { Task { await server.refreshMe() } }
            landed()
        }
    }

    /// A read or a write landed (or a page of People came back): Navidrome's version asked once the list shows, the idle
    /// check set from the answer - only while People may ask.
    private func landed() {
        if flow.view != .list { versionAsked = false }
        guard mayAsk else { return }
        if flow.view == .list { askVersion() }
        armIdle()
    }

    /// Navidrome's status, for the note when it isn't the version People was checked with - asked once each time the
    /// list comes; a failure says nothing.
    private func askVersion() {
        guard mayAsk, !versionAsked, let client = server.client else { return }
        versionAsked = true
        let mine = generation
        Task {
            let status = try? await client.navidromeStatus()
            guard mine == generation, let status else { return }
            navidrome = status.server
        }
    }

    /// The idle check: once the unlock has been left alone long enough to have run out on the server, People is read
    /// again - only while it shows, so the read finds it gone; once per answer (the flow's `idleWait` arms none after a
    /// read sent for it, so one that fails - a 403, a proxy's 502 - never loops).
    private func armIdle() {
        idle?.cancel()
        idle = nil
        guard mayAsk, let wait = flow.idleWait(now: now) else { return }
        let mine = generation
        idle = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard mine == generation, !Task.isCancelled, flow.idleDue(now: now) else { return }
            read()
        }
    }

    /// No page of People left on any tab: left (the flow keeps all while a write is out - its end comes back here).
    private func leaveIfGone() {
        guard pagesShown == 0, !navigation.holdsPeople else { return }
        flow.left()
        guard flow.state == nil else { return }
        reading?.cancel()
        idle?.cancel()
        navidrome = nil
        versionAsked = false
    }

    // MARK: writes

    func unlock() {
        guard let client = server.client,
              let (ticket, body) = flow.beginUnlock(online: online, signInOver: signInOver) else { return }
        let admin = self.admin
        send(ticket, named: "Unlock People") { await client.unlockPeople(body, admin: admin) }
    }

    func lock() {
        guard let client = server.client, let ticket = flow.beginLock(online: online, signInOver: signInOver) else {
            return
        }
        let admin = self.admin
        send(ticket, named: "Lock People") { await client.lockPeople(admin: admin) }
    }

    func create() {
        guard let client = server.client,
              let (ticket, body) = flow.beginCreate(online: online, signInOver: signInOver) else { return }
        let admin = self.admin
        send(ticket, named: "Add a person") { await client.createPerson(body, admin: admin) }
    }

    func resetPassword(_ person: PeoplePerson) {
        guard let client = server.client,
              let (ticket, body) = flow.beginReset(person, online: online, signInOver: signInOver) else { return }
        let admin = self.admin, id = person.id
        send(ticket, named: "Reset password") { await client.resetPassword(id, body, admin: admin) }
    }

    func flip(_ person: PeoplePerson) {
        guard let client = server.client,
              let (ticket, body) = flow.beginFlip(person, online: online, signInOver: signInOver) else { return }
        let admin = self.admin, id = person.id
        send(ticket, named: "Admin role") { await client.setAdmin(id, body, admin: admin) }
    }

    func remove(_ person: PeoplePerson) {
        guard let client = server.client,
              let (ticket, body) = flow.beginRemove(person, online: online, signInOver: signInOver) else { return }
        let admin = self.admin, id = person.id
        send(ticket, named: "Remove a person") { await client.removePerson(id, body, admin: admin) }
    }

    func forget(_ entry: PeopleKnownOnly) {
        guard let client = server.client,
              let (ticket, body) = flow.beginForget(entry, online: online, signInOver: signInOver) else { return }
        let admin = self.admin
        send(ticket, named: "Forget") { await client.forgetPerson(body, admin: admin) }
    }

    func save(_ person: PeoplePerson) {
        guard let client = server.client,
              let (ticket, body) = flow.beginSave(person, online: online, signInOver: signInOver) else { return }
        let admin = self.admin, id = person.id
        send(ticket, named: "Save permissions") { await client.savePermissions(id, body, admin: admin) }
    }

    /// One write, its ticket already taken: sent, held through the background, and what came of it carried out - said
    /// once, /me asked again, a removed person's page left, the list read again.
    private func send(_ ticket: Int, named name: String, _ call: @escaping @MainActor () async -> PeopleOutcome) {
        navigation.peopleWriting(true)
        let mine = generation
        let hold = BackgroundHold(named: name)
        Task {
            defer { hold.end() }
            let outcome = await call()
            guard mine == generation else { return }
            let after = flow.ended(ticket, outcome, now: now, signInOver: signInOver,
                                   origin: People.origin(server.address), device: Platform.device)
            navigation.peopleWriting(flow.writing != nil)
            guard let after else { return }
            if let words = after.announce, !words.isEmpty { Notice.announce(words) }
            if let id = after.leave { navigation.leavePerson(id) }
            if after.askMe, !signInOver { Task { await server.refreshMe() } }
            if after.read { read() }
            armIdle()
            leaveIfGone()
        }
    }

    // MARK: another person

    /// The person changed: everything of the last one's let go - what is out called off, nothing it answers drawn.
    func reset() {
        generation += 1
        reading?.cancel()
        idle?.cancel()
        reading = nil
        idle = nil
        flow = PeopleFlow()
        navidrome = nil
        versionAsked = false
        pagesShown = 0
        hiddenAt = nil
    }
}
