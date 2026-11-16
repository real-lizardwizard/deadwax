import DeadwaxCore
import Observation
import SwiftUI
import UIKit

/// Library care's state, held by the app (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; the web's
/// app/useLibraryCare.ts, whose module keeps its runs for the page's life): the library's scan (`GET
/// /library/albums?tracks=false` with its ETag - LibraryScanModel - and Rescan's `POST /library/rescan?tracks=false`), the
/// words typed to narrow the runs, and the runs themselves - Get covers, Get CD art and Get lyrics, one album at a time
/// through the route a single Get uses (`getCover`, `getDiscArt`, `getLyrics`, each with its own wait), never a loop on
/// the server. Held by the app, so leaving the page doesn't stop a run, and each run's result stays until the next of its
/// kind.
///
/// Every decision is Core's CareRuns (library-care-vectors.json, LibraryCareTests): when the page reads the library,
/// when Rescan and Start may go, which albums a run takes, the next album or the run's end, what each album came to, when
/// Needs a look's count is told, and when the screen stays on. This only carries them out (`drive`, `reading`): asks,
/// keeps and hands on. Each album's request is held through the app going to the background (BackgroundHold), and the
/// run stops after it (CareRuns.suspended - the phone's own: iOS suspends the app soon after); deadwax going out of reach,
/// Edit albums going (/me says so, or deadwax refuses an album with a 403 - /me is then asked again) or the session
/// ending (the sign-in over the app) stops it the same way. Start carries on: it asks again which albums still lack one.
/// Nothing is read while the sign-in is over the app (its 401 would only be said as a failure); once it goes, the page
/// reads again.
///
/// Another person (`reset`): the run stops before its next album - the album out is let go, its answer dropped -
/// nothing of the last person's kept, the screen let sleep.
@MainActor
@Observable
final class CareRunModel {
    /// The library's scan - Library care's own.
    private(set) var scan = LibraryScanModel()
    /// The runs, Rescan and the scan's freshness (Core's CareRuns): every move decided there.
    private(set) var runs = CareRuns()
    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private weak var navigation: AppNavigation?
    /// One more each time the person changes: a run, a read or a rescan for the last one stops where it is.
    @ObservationIgnored private var generation = 0
    /// The page is on screen (between its onAppear and onDisappear), and has been at least once since the person
    /// changed.
    @ObservationIgnored private var onScreen = false
    @ObservationIgnored private var shownBefore = false
    /// The app is in front.
    @ObservationIgnored private var active = true
    /// deadwax could be reached, as last heard.
    @ObservationIgnored private var lastOnline = true

    init(server: ServerModel, reachability: Reachability, navigation: AppNavigation) {
        self.server = server
        self.reachability = reachability
        self.navigation = navigation
        lastOnline = reachability.online
    }

    // MARK: what the page draws

    /// Who sees which part (permissions.ts careParts).
    var parts: Managing.CareParts { Managing.careParts(server.access.permissions) }

    /// In nobody's library is drawn: logins on, and Look after the library.
    var heldShown: Bool { Managing.heldShown(loginsOn: server.access.on, parts: parts) }

    /// deadwax's own words, for whoever runs it (access.ts seesDetail).
    private var admin: Bool { server.access.seesDetail }

    /// The page shows and the app is in front.
    private var visible: Bool { onScreen && active }

    /// The words typed to narrow the runs.
    var narrow: String {
        get { runs.narrow }
        set { runs.narrow = newValue }
    }

    /// The page's state before its sections (the web's ladder: LIBRARY_PATH's problem, reading, a failed read with no
    /// albums to show, else the sections) - a read ended, answered or not, being the web's `loaded`.
    var state: NeedsLook.State {
        NeedsLook.state(problem: scan.answer?.problem, loaded: scan.ended, failed: scan.failed != nil,
                        albums: scan.albums.count)
    }

    /// The last read's failure in the page's words, as the web's ladder says it: READ_FAILED with no albums to show
    /// (nothing read yet, or a library read empty), REREAD_FAILED over the albums on screen - or deadwax's own words.
    var failure: String? {
        scan.failure(saying: scan.albums.isEmpty ? LibraryCare.readFailed : LibraryCare.rereadFailed)
    }

    /// The facts under Rescan, at `now` (milliseconds).
    func facts(now: Double) -> String {
        LibraryCare.facts(scan.albums, loaded: scan.loaded, loading: scan.reading, scannedAt: scan.answer?.scannedAt,
                          scanSeconds: scan.answer?.scanSeconds ?? 0, rescanning: runs.rescanning, now: now)
    }

    /// Rescan may be pressed.
    func rescanOpen(online: Bool) -> Bool {
        runs.rescanOpen(allowed: parts.rescan, online: online, problem: scan.answer?.problem != nil, reading: scan.reading)
    }

    /// The albums a kind's run would take now (nil: Checking the library…).
    func targets(_ kind: BulkTargets.Kind) -> [ScanAlbum]? {
        runs.targets(kind, scan.albums)
    }

    /// The scope's note under Narrow to.
    var scopeNote: String {
        LibraryCare.scopeNote(real: runs.real, inScope: LibraryCare.narrow(scan.albums, runs.narrow).count,
                              all: scan.albums.count, typed: runs.narrow)
    }

    /// Start may be pressed for `kind`.
    func startOpen(_ kind: BulkTargets.Kind, online: Bool) -> Bool {
        runs.startOpen(kind, scan.albums, allowed: parts.bulk, online: online)
    }

    // MARK: showing

    /// The page came on screen: read the first time, after a gap, for a kind behind - and once underneath as it shows
    /// again.
    func shows() {
        let again = shownBefore
        shownBefore = true
        onScreen = true
        screen()
        readIfNeeded(again: again)
    }

    /// The page went (another tab, popped, a page pushed over it).
    func hides() {
        onScreen = false
        screen()
    }

    /// The scene's phase: to the background, a run stops after the album out and the screen may sleep; back in front
    /// with the page up, it is shown again.
    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            active = false
            runs.suspended()
            screen()
        case .active:
            guard !active else { return }
            active = true
            screen()
            if onScreen { readIfNeeded(again: true) }
        default:
            break
        }
    }

    /// deadwax came into reach or went out of it (Reachability): out, a run stops after the album out and the scan on
    /// screen is how it was; back, it is read again before anything starts.
    func reachChanged() {
        let now = reachability.online
        guard now != lastOnline else { return }
        lastOnline = now
        runs.reach(now)
        if now { readIfNeeded(again: false) }
    }

    /// The sign-in over the app went (signed in again as the same person, or logins turned off): what failed while it
    /// was there is read again, as the page shown again would.
    func sessionBack() {
        readIfNeeded(again: true)
    }

    /// The screen stays on while a run goes and its page is in front - and only then.
    private func screen() {
        UIApplication.shared.isIdleTimerDisabled = runs.keepsScreenOn(visible: visible)
    }

    // MARK: reading

    /// The library read, when CareRuns says the page reads now - never under the sign-in over the app, where the page
    /// still counts as shown (nothing over it disappears it) and its 401 would only be said as a failure; `sessionBack`
    /// reads once it goes.
    private func readIfNeeded(again: Bool) {
        guard parts.shown, server.signInOver == nil,
              runs.readsNow(shown: visible, online: reachability.online, again: again, loaded: scan.loaded,
                            reading: scan.reading) else { return }
        Task { await read() }
    }

    /// The library read (its failure in the page's words - `failure`). Once it lands, CareRuns is asked again: a read
    /// already out as a run ended, or as deadwax came back into reach, began too early to trust - it isn't asked for
    /// then (one is out), so it is asked for now.
    func read() async {
        guard parts.shown, let client = server.client else { return }
        let ticket = runs.readBegan()
        let mine = generation
        let read = await scan.read(client: client, admin: admin)
        guard mine == generation, read == .landed else { return }
        runs.readLanded(ticket)
        readIfNeeded(again: false)
    }

    /// Try again (the first read's, or the line over the sections): never while a read or a rescan is out.
    func retry() {
        guard !scan.reading, !runs.rescanning, reachability.online else { return }
        Task { await read() }
    }

    /// Rescan pressed: every file read again; after it, Needs a look's count told (it reads the saved scan the rescan
    /// wrote) - or, never answered, said that it may have finished and the library read again first.
    func rescan() {
        guard let client = server.client,
              let ticket = runs.rescan(allowed: parts.rescan, online: reachability.online,
                                       problem: scan.answer?.problem != nil, reading: scan.reading) else { return }
        let mine = generation
        Task {
            let how = await scan.rescan(client: client, admin: admin)
            guard mine == generation else { return }
            let after = runs.rescanEnded(ticket, how)
            if after.mayHaveFinished { AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post() }
            if after.readAgain { await read() }
            guard mine == generation else { return }
            if after.tell { navigation?.managed() }
            readIfNeeded(again: false)
        }
    }

    // MARK: the runs

    /// Start pressed on `kind`: the run begun over the albums it takes now, and driven one album at a time.
    func start(_ kind: BulkTargets.Kind) {
        guard runs.start(kind, scan.albums, allowed: parts.bulk, online: reachability.online) else { return }
        screen()
        let mine = generation
        Task { await drive(mine) }
    }

    /// Stop pressed: the run ends after the album out.
    func stop(_ kind: BulkTargets.Kind) {
        runs.stop(kind)
    }

    /// The run, one album at a time, as CareRuns says: each album fetched (held through the background), counted, and
    /// Needs a look's count told after each that wrote or may have; a 403 stops it, and /me is asked again so the page
    /// draws what this person may do now; once over, its result announced, the screen let sleep, and the library read
    /// for the kind it left behind.
    private func drive(_ mine: Int) async {
        while mine == generation {
            // the session ended (the sign-in over the app), or there is none to ask with: every album after would be
            // refused
            let client = server.client
            if server.signInOver != nil || client == nil { runs.sessionEnded() }
            switch runs.next(allowed: parts.bulk, online: reachability.online) {
            case .album(let album):
                guard let kind = runs.under?.kind, let client else { return }
                let step = await fetch(kind, album, with: client)
                guard mine == generation else { return }
                if case .forbidden = step { Task { await server.refreshMe() } }
                if runs.finished(step) { navigation?.managed() }
            case .ended(let kind):
                AccessibilityNotification.Announcement(runs.result(kind)).post()
                screen()
                readIfNeeded(again: false)
                return
            case .nothing:
                return
            }
        }
    }

    /// One album's step: the route a single Get uses, its answer or its failure as CareRuns counts it.
    private func fetch(_ kind: BulkTargets.Kind, _ album: ScanAlbum,
                       with client: DeadwaxClient) async -> BulkTargets.Step {
        let hold = BackgroundHold(named: "Library care: \(LibraryCare.label(kind))")
        defer { hold.end() }
        do {
            switch kind {
            case .covers:
                _ = try await client.getCover(path: album.path)
                return .answered(BulkTargets.Outcome(written: 1))
            case .disc:
                _ = try await client.getDiscArt(album)
                return .answered(BulkTargets.Outcome(written: 1))
            case .lyrics:
                return .answered(BulkTargets.outcome(try await client.getLyrics(album)))
            }
        } catch {
            return BulkTargets.step(kind, album, failure: error)
        }
    }

    // MARK: another person

    /// The person changed: the run stops where it is (its album out let go), nothing of theirs kept, the screen let
    /// sleep.
    func reset() {
        generation += 1
        runs = CareRuns()
        scan = LibraryScanModel()
        shownBefore = false
        onScreen = false
        screen()
    }
}
