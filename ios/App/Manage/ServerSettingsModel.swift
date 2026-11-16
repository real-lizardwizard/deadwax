import DeadwaxCore
import Observation
import SwiftUI

/// Server settings' state, held by the app (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7; the web's
/// app/ServerSettings.tsx, whose module keeps `kept` beyond the page): the settings as last read (`GET /settings`), the
/// drafts made against them across every group's page, the one save (`PUT /settings`, every draft at once), MusicBrainz's
/// saved answers and their Clear, Re-time saved lyrics (one album at a time through the lyrics fetch with `retime`, kept
/// beyond the page as a Library care run is) and Connections' three rows.
///
/// Every decision is Core's (ServerSettings.swift: SettingsFlow, SavedAnswers, RetimeRun, ConnectionChecks - held to the
/// web's own code by server-vectors.json): when a page reads, when Save may go and what it sends, what an answer leaves
/// of the drafts, what a save that never answered keeps once the settings are read again, when Clear and Re-time may go,
/// the next album or the run's end, when the screen stays on. This only carries them out: asks, keeps and hands on.
///
/// A page tells it as it shows and goes (`shows`, `hides`): the settings are read the first time, again each time a
/// page shows with nothing drafted (the web reads each time its page shows), back in reach and once the sign-in over the
/// app goes - never while that sign-in is up (its 401 would only be said as a failure). A save is held through the app
/// going to the background (BackgroundHold); one that never answered, or answered a 5xx, may have landed - said, and the
/// settings read again, keeping only the drafts that still differ from them. After a save that carried one of
/// Navidrome's settings, the Library asks Navidrome again (the web's `onServerSettingsSaved`), so its gate opens by
/// itself; one that carried a Connections setting checks Connections again.
///
/// Another person (`reset`): everything of the last one's let go - the drafts with it, a run stopped where it is.
@MainActor
@Observable
final class ServerSettingsModel {
    /// A page of Server settings: its root, or a group's own.
    enum Page: Hashable {
        case root
        case group(String)
    }

    /// The settings, the drafts and the save (Core's SettingsFlow).
    private(set) var flow = SettingsFlow()
    /// MusicBrainz's saved answers, under their group's settings.
    private(set) var answers = SavedAnswers()
    /// Re-time saved lyrics, under the lead.
    private(set) var retime = RetimeRun()
    /// Connections' three rows.
    private(set) var checks = ConnectionChecks()

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private let library: LibraryModel
    /// One more each time the person changes: an answer for the last one is dropped.
    @ObservationIgnored private var generation = 0
    /// How many of its pages show now, in all - and those drawing the saved answers, Re-time and Connections.
    @ObservationIgnored private var pagesShown = 0
    @ObservationIgnored private var answersShown = 0
    @ObservationIgnored private var retimeShown = 0
    @ObservationIgnored private var connectionsShown = 0
    /// A page has shown since the person changed: the next is "shown again".
    @ObservationIgnored private var shownBefore = false
    /// The app is in front.
    @ObservationIgnored private var active = true
    /// deadwax could be reached, as last heard.
    @ObservationIgnored private var lastOnline = true

    init(server: ServerModel, reachability: Reachability, library: LibraryModel) {
        self.server = server
        self.reachability = reachability
        self.library = library
        lastOnline = reachability.online
    }

    // MARK: what the pages draw

    /// Who sees which part (ServerSettings.parts: the page by Settings and the log, Connections for whoever runs
    /// deadwax, Re-time with Edit albums too).
    var parts: ServerSettings.Parts { ServerSettings.parts(server.access) }

    /// deadwax's own words, for whoever runs it (access.ts seesDetail).
    private var admin: Bool { server.access.seesDetail }

    /// A page shows and the app is in front.
    private var visible: Bool { pagesShown > 0 && active }

    /// The lead has a draft: Re-time is refused, as it re-times to the lead that is SAVED.
    var leadUnsaved: Bool { flow.drafts.has(ServerSettings.leadKey) }

    /// MUSICBRAINZ_CACHE_PATH has a draft: Clear is refused, as it clears the file that is saved.
    var pathUnsaved: Bool { flow.drafts.has(ServerSettings.savedAnswersPath) }

    /// Save may be pressed.
    func saveOpen(online: Bool) -> Bool {
        flow.saveOpen(online: online, allowed: parts.page)
    }

    /// Re-time may be started.
    func retimeOpen(online: Bool) -> Bool {
        retime.startOpen(allowed: parts.retime, online: online, unsaved: leadUnsaved)
    }

    // MARK: showing

    /// A page came on screen: the settings read the first time, and again shown with nothing drafted; its saved
    /// answers read each time; Connections checked the first time.
    func shows(_ page: Page) {
        let again = shownBefore
        shownBefore = true
        pagesShown += 1
        if case .group(let id) = page {
            if id == ServerSettings.savedAnswersGroup { answersShown += 1 }
            if id == ServerSettings.lyricsGroup { retimeShown += 1 }
        }
        if draws(page) { connectionsShown += 1 }
        screen()
        readIfNeeded(again: again)
        if page == .group(ServerSettings.savedAnswersGroup) { answersIfNeeded() }
        checkIfNeeded()
    }

    /// A page went (another tab, popped, a page pushed over it, the sheet closed).
    func hides(_ page: Page) {
        pagesShown = max(0, pagesShown - 1)
        if case .group(let id) = page {
            if id == ServerSettings.savedAnswersGroup { answersShown = max(0, answersShown - 1) }
            if id == ServerSettings.lyricsGroup {
                retimeShown = max(0, retimeShown - 1)
                // the last page showing it gone: an ended run has been said, and the next visit says the prompt
                if retimeShown == 0 { retime.pageGone() }
            }
        }
        if draws(page) { connectionsShown = max(0, connectionsShown - 1) }
        screen()
    }

    /// Connections' rows are drawn on the root and on the Connections group's own page.
    private func draws(_ page: Page) -> Bool {
        page == .root || page == .group(ServerSettings.connectionsGroup)
    }

    /// The scene's phase: to the background, a Re-time run stops after the album out and the screen may sleep; back in
    /// front with a page up, it is shown again.
    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            active = false
            retime.suspended()
            screen()
        case .active:
            guard !active else { return }
            active = true
            screen()
            guard pagesShown > 0 else { return }
            readIfNeeded(again: true)
            answersIfNeeded()
            checkIfNeeded()
        default:
            break
        }
    }

    /// deadwax came into reach or went out of it (Reachability): out, a read from before isn't trusted, Save waits for
    /// one after, and a run stops after the album out; back, everything is asked again before Save comes back on.
    func reachChanged() {
        let now = reachability.online
        guard now != lastOnline else { return }
        lastOnline = now
        if now {
            checks.want()
            readIfNeeded(again: false)
            answersIfNeeded()
            checkIfNeeded()
        } else {
            flow.outOfReach()
            retime.outOfReach()
        }
    }

    /// The sign-in over the app went (signed in again as the same person, or logins turned off): what failed while it
    /// was there is asked again, as a page shown again would.
    func sessionBack() {
        checks.want()
        readIfNeeded(again: true)
        answersIfNeeded()
        checkIfNeeded()
    }

    /// Who may see which part changed while a page shows (/me answered again): what it may now draw is asked for.
    func accessChanged() {
        readIfNeeded(again: false)
        answersIfNeeded()
        checkIfNeeded()
    }

    /// The screen stays on while a Re-time run goes and its page is in front - and only then.
    private func screen() {
        ScreenAwake.keep(retime.keepsScreenOn(visible: retimeShown > 0 && active), for: .retime)
    }

    private func announce(_ words: String) {
        guard !words.isEmpty else { return }
        AccessibilityNotification.Announcement(words).post()
    }

    // MARK: the settings

    /// The settings read, when SettingsFlow says a page reads now - never under the sign-in over the app.
    private func readIfNeeded(again: Bool) {
        guard server.signInOver == nil,
              flow.readsNow(shown: visible, online: reachability.online, allowed: parts.page, again: again) else { return }
        Task { await read() }
    }

    /// The settings read: only the newest lands. Once it does, SettingsFlow is asked again (a read begun before deadwax
    /// was last out of reach isn't trusted), and the saved answers read afresh if the file they name changed.
    func read() async {
        guard let client = server.client else { return }
        let ticket = flow.readBegan()
        let mine = generation
        let checking = flow.checking != nil
        do {
            let found = try await client.serverSettings()
            guard mine == generation else { return }
            flow.readLanded(ticket, found)
            // a save that never answered, looked at again: said how it came out
            if checking, flow.checking == nil { announce(flow.barText) }
        } catch {
            guard mine == generation else { return }
            if APIFailure.isCancellation(error) {
                flow.readDropped(ticket)
                return
            }
            flow.readFailed(ticket, ServerSettings.readFailure(error, admin: admin, first: flow.answer == nil))
            if Self.forbidden(error) { Task { await server.refreshMe() } }
            return
        }
        readIfNeeded(again: false)
        if let group = flow.group(ServerSettings.savedAnswersGroup), answers.key != SavedAnswers.key(group) {
            answersIfNeeded()
        }
    }

    /// Try again (the first read's, or the line over the settings shown).
    func retry() {
        guard !flow.reading, !flow.saving, reachability.online, server.signInOver == nil else { return }
        Task { await read() }
    }

    // MARK: drafts and the save

    /// A value typed or chosen. A new lead lets go of how an earlier Re-time ended (it was at the old one).
    func edit(_ key: String, _ value: String) {
        flow.edit(key, value)
        if leadUnsaved { retime.leadDrafted() }
    }

    /// Revert to the environment.
    func revert(_ key: String) {
        flow.revert(key)
        if leadUnsaved { retime.leadDrafted() }
    }

    /// Discard: every draft gone.
    func discard() {
        flow.discard()
    }

    /// Save pressed: every draft at once (held through the background). Answered, the settings are what it says and
    /// "Saved." is said; refused (a 4xx), every draft stays and the bar says why; never answered (or a 5xx), it may
    /// have landed - said, and the settings read again.
    func save() {
        guard let client = server.client, server.signInOver == nil,
              let batch = flow.save(online: reachability.online, allowed: parts.page) else { return }
        let mine = generation
        let hold = BackgroundHold(named: "Server settings: save")
        Task {
            defer { hold.end() }
            do {
                let found = try await client.saveServerSettings(batch)
                guard mine == generation else { return }
                flow.saved(found)
                announce(flow.barText)
                saved(batch.keys)
            } catch {
                guard mine == generation else { return }
                if APIFailure.isCancellation(error) {
                    flow.saveDropped()
                } else if RetagFlow.outcome(of: error) == .refused {
                    flow.refused(ServerSettings.saveFailure(error, admin: admin))
                    announce(flow.barText)
                    if Self.forbidden(error) { Task { await server.refreshMe() } }
                } else {
                    flow.unanswered(ServerSettings.unansweredWords(error, admin: admin))
                    announce(EditWords.mayHaveFinished)
                    readIfNeeded(again: false)
                    saved(batch.keys)
                }
            }
        }
    }

    /// After a save that landed (or may have): the Library asks Navidrome again for one of its settings, Connections are
    /// checked again for one of theirs, and the saved answers read again for the file they may name now.
    private func saved(_ keys: [String]) {
        if ServerSettings.asksNavidromeAgain(keys) {
            Task { await library.checkNavidrome() }
        }
        if ServerSettings.checksConnectionsAgain(keys, flow.answer) {
            checks.want()
            checkIfNeeded()
        }
        answersIfNeeded()
    }

    // MARK: MusicBrainz's saved answers

    /// The file read, while its page shows: each time it shows, and afresh once it names another file.
    private func answersIfNeeded() {
        guard answersShown > 0, active, parts.answers, server.signInOver == nil,
              answers.readsNow(shown: true, online: reachability.online),
              let group = flow.group(ServerSettings.savedAnswersGroup) else { return }
        Task { await readAnswers(SavedAnswers.key(group)) }
    }

    private func readAnswers(_ key: String) async {
        guard let client = server.client else { return }
        let ticket = answers.readBegan(key: key)
        let mine = generation
        do {
            let stats = try await client.savedAnswers()
            guard mine == generation else { return }
            answers.readLanded(ticket, stats)
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return }
            answers.readFailed(ticket, SavedAnswers.readFailure(error, admin: admin))
            if Self.forbidden(error) { Task { await server.refreshMe() } }
        }
    }

    /// Clear, once asked and confirmed: every saved answer gone (held through the background). Refused (a 4xx), said;
    /// never answered (or a 5xx), it may have cleared - said, and the file read again.
    func clearAnswers() {
        guard let client = server.client, server.signInOver == nil,
              let ticket = answers.clearBegan(unsaved: pathUnsaved, online: reachability.online) else { return }
        let mine = generation
        let hold = BackgroundHold(named: "MusicBrainz's saved answers: clear")
        Task {
            defer { hold.end() }
            do {
                let stats = try await client.clearSavedAnswers()
                guard mine == generation else { return }
                answers.clearLanded(ticket, stats)
                announce(answers.line(unsaved: pathUnsaved))
            } catch {
                guard mine == generation else { return }
                if APIFailure.isCancellation(error) {
                    answers.clearDropped()
                } else if RetagFlow.outcome(of: error) == .refused {
                    answers.clearRefused(ticket, SavedAnswers.clearFailure(error, admin: admin))
                    announce(answers.line(unsaved: pathUnsaved))
                    if Self.forbidden(error) { Task { await server.refreshMe() } }
                } else if answers.clearUnanswered(ticket, SavedAnswers.clearUnansweredWords(error, admin: admin)) {
                    announce(EditWords.mayHaveFinished)
                    answersIfNeeded()
                }
            }
        }
    }

    // MARK: Connections

    /// Connections checked, as ConnectionChecks says: a page drawing them shows, never checked yet (or wanted again).
    private func checkIfNeeded() {
        guard connectionsShown > 0, active, server.signInOver == nil,
              checks.checksNow(shown: true, allowed: parts.connections, online: reachability.online) else { return }
        checkConnections()
    }

    /// Check again (or the first check): every row "Checking…", then each as its own answer comes - MusicBrainz and
    /// slskd by their pings, Navidrome by its status.
    func checkConnections() {
        guard let client = server.client, parts.connections, reachability.online, server.signInOver == nil else { return }
        let ticket = checks.began()
        let mine = generation
        Task {
            let check: Connections.Check
            do {
                check = Connections.fromPing(.musicbrainz, try await client.pingMusicBrainz())
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                check = Connections.unanswered(error)
            }
            guard mine == generation else { return }
            checks.settled(ticket, .musicbrainz, check)
        }
        Task {
            let check: Connections.Check
            do {
                check = Connections.fromPing(.slskd, try await client.pingSlskd())
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                check = Connections.unanswered(error)
            }
            guard mine == generation else { return }
            checks.settled(ticket, .slskd, check)
        }
        Task {
            let check: Connections.Check
            do {
                check = Connections.fromNavidrome(try await client.navidromeStatus())
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                check = Connections.unanswered(error)
            }
            guard mine == generation else { return }
            checks.settled(ticket, .navidrome, check)
        }
    }

    // MARK: Re-time saved lyrics

    /// Re-time pressed: the library read (the real scan - the saved one misses albums an earlier run touched), then
    /// each album with lyrics, one at a time.
    func startRetime() {
        guard let client = server.client, server.signInOver == nil,
              let ticket = retime.start(allowed: parts.retime, online: reachability.online, unsaved: leadUnsaved) else {
            return
        }
        screen()
        let mine = generation
        Task {
            let hold = BackgroundHold(named: "Re-time saved lyrics: the library")
            defer { hold.end() }
            do {
                let albums: [ScanAlbum]
                switch try await client.libraryScan(ifNoneMatch: nil) {
                case .fresh(let scan, _): albums = scan.albums
                case .unchanged: albums = []
                }
                guard mine == generation else { return }
                retime.read(ticket, albums)
            } catch {
                guard mine == generation else { return }
                retime.readFailed(ticket, RetimeRun.readFailure(error, admin: admin))
                if Self.forbidden(error) { Task { await server.refreshMe() } }
                ended()
                return
            }
            await driveRetime(mine)
        }
    }

    /// Stop pressed: the run ends after the album out.
    func stopRetime() {
        retime.stopPressed()
    }

    /// The run, one album at a time, as RetimeRun says: each album re-timed (held through the background) and counted;
    /// a 403 stops it, and /me is asked again so the page draws what this person may do now; once over, how it ended is
    /// said and the screen let sleep.
    private func driveRetime(_ mine: Int) async {
        while mine == generation {
            // the session ended (the sign-in over the app), or there is none to ask with: every album after would be
            // refused
            let client = server.client
            if server.signInOver != nil || client == nil { retime.sessionEnded() }
            switch retime.next(allowed: parts.retime, online: reachability.online) {
            case .album(let album):
                guard let client else { return }
                let hold = BackgroundHold(named: "Re-time saved lyrics")
                let step: RetimeRun.Step
                do {
                    step = .answered(try await client.retime(album))
                } catch {
                    step = RetimeRun.step(failure: error)
                }
                hold.end()
                guard mine == generation else { return }
                if case .forbidden = step { Task { await server.refreshMe() } }
                retime.finished(step)
            case .ended:
                ended()
                return
            case .nothing:
                return
            }
        }
    }

    /// A run over: how it ended said (unless a new lead let it go), the screen let sleep.
    private func ended() {
        if retime.phase == .ended { announce(retime.note(unsaved: leadUnsaved)) }
        screen()
    }

    private static func forbidden(_ error: any Error) -> Bool {
        if case .answered(let answer)? = error as? APIFailure { return answer.status == 403 }
        return false
    }

    // MARK: another person

    /// The person changed: nothing of the last one's kept - the drafts with it - a run stopped where it is, the screen
    /// let sleep.
    func reset() {
        generation += 1
        flow = SettingsFlow()
        answers = SavedAnswers()
        retime = RetimeRun()
        checks = ConnectionChecks()
        pagesShown = 0
        answersShown = 0
        retimeShown = 0
        connectionsShown = 0
        shownBefore = false
        screen()
    }
}
