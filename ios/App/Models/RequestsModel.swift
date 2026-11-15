import DeadwaxCore
import Foundation
import Observation

/// The Requests tab (Phase 6, slice 1 - notes/ios-specs/phase6-get-requests.md 2.1-2.7, 3.1-3.3; the web's
/// hooks/useDownloadJobs.ts and app/Requests.tsx): the one poll of `/download/jobs`, the overlays laid over its answer,
/// the four writes, the Done rows' albums looked for ahead, and what VoiceOver hears as the board changes. Every rule
/// is Core's (RequestsView, RequestOverlays, SpeedSamples, RequestsWatch, RequestsPolling, RequestChanges, DoneLooks);
/// this makes the requests, keeps their tasks and clocks, and redraws the board from what landed.
///
/// - What the app watches (`watching`, set by MainTabs: the scene, the tab, its pages, Now Playing over it) decides the
///   pace: every 0.5 s while Requests' root shows (or a failed look stalls with something on its way), 1 s while an
///   album is being filed, 5 s while anything is on its way, none otherwise - and none in the background, none while
///   deadwax can't be reached, each asked once on the way back (question 3). A turn of `open` asks at once, as an
///   answered write does.
/// - Each look is its own task: a look begun before a newer one, or before the person changed, lands nothing.
/// - Offline (question 4): nothing asked, the screen draws none of the last answer; back, what failed while deadwax was
///   away is forgotten, the last answer drawn again at once and a look asked.
/// - The overlays are set before a write goes out and dropped when a poll agrees, or after 15 s; a cancel or a clear
///   that fails is only rolled back, as the web's (its error goes to the console there).
/// - A look that sees an album newly filed asks Search's owned index again (question 8).
/// - The Done rows' albums are looked for only while Requests' root shows; leaving it lets every look go, and a tapped
///   row's album opens only while the root is still what shows when the answer comes.
///
/// `reset()` - a new person - lets everything go, and nothing asked before it lands after it.
@MainActor
@Observable
final class RequestsModel {
    /// The board as drawn: the last answer with the overlays over it.
    private(set) var board: RequestsView = .nothing
    /// deadwax has answered once, or failed to (App.tsx `answered`): until then the board knows nothing, empty or not.
    private(set) var answered = false
    /// deadwax can keep track of downloads (false: its database can't be written).
    private(set) var trackingEnabled = true
    /// Why the last look failed - nil once one answers, and once deadwax is back after being out of reach.
    private(set) var failure: (any Error)?
    /// Why a tapped Done row couldn't open, by release - gone once a later look finds its album.
    private(set) var notes: [String: String] = [:]
    /// The Done row whose album is being looked up for its tap, by key.
    private(set) var opening: String?
    /// What the app is looking at, as far as downloads go.
    private(set) var watching: Watching = .hidden

    private let server: ServerModel
    private let reachability: Reachability
    private let navigation: AppNavigation
    private let library: LibraryModel
    private let search: SearchModel

    /// One more at every reset: nothing begun for the person before lands after.
    @ObservationIgnored private var epoch = 0
    /// The last answer's jobs, as deadwax sent them.
    @ObservationIgnored private var polled: [DownloadJob] = []
    @ObservationIgnored private var overlays = RequestOverlays.none
    @ObservationIgnored private var retryingSame: Set<Int> = []
    @ObservationIgnored private var retryProblems: [Int: RetryProblem] = [:]
    @ObservationIgnored private var samples = SpeedSamples()
    @ObservationIgnored private var speeds: [Int: Double] = [:]
    /// Each job's status at the last look - nil before the first, so nothing filed before the app asked is news.
    @ObservationIgnored private var statuses: [Int: String]?
    /// The board VoiceOver last heard about (nil until the first answer: nothing is news then).
    @ObservationIgnored private var spoken: RequestsView?
    /// Whether the poll was open at the last look at it - a turn either way asks at once.
    @ObservationIgnored private var wasOpen = false
    @ObservationIgnored private var wasOnline = true

    /// The poll: one loop, one more `looks` at each start - a loop whose number isn't the newest lands nothing.
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var looks = 0
    /// The writes out (each its own), and the overlays' clocks.
    @ObservationIgnored private var writes: [UUID: Task<Void, Never>] = [:]

    // the Done rows' albums (Requests.tsx's)
    /// When each Done row first showed as done, by this phone's clock (ms) - 0 for one done in deadwax's first answer.
    @ObservationIgnored private var doneSince: [String: Double] = [:]
    @ObservationIgnored private var baseline = false
    /// Navidrome's album id for a release, once the id bridge found it.
    @ObservationIgnored private var albumIds: [String: String] = [:]
    /// An album's songs in hand, and when they were asked for - what a ▶ plays.
    @ObservationIgnored private var ready: [String: (album: Album, at: Double)] = [:]
    @ObservationIgnored private var misses: [String: DoneLooks.Miss] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    /// When Requests' root last came into view (ms).
    @ObservationIgnored private var activeSince: Double = 0
    /// One more each time Requests' root comes into view or leaves it: a look of an older period lands nothing.
    @ObservationIgnored private var period = 0
    @ObservationIgnored private var lookTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var dueClock: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Void, Never>?

    init(server: ServerModel, reachability: Reachability, navigation: AppNavigation, library: LibraryModel,
         search: SearchModel) {
        self.server = server
        self.reachability = reachability
        self.navigation = navigation
        self.library = library
        self.search = search
        wasOnline = reachability.online
    }

    /// The badge's count: none while deadwax can't be reached (3.1).
    var badgeCount: Int { reachability.online ? board.arriving.count : 0 }

    /// The poll is open: Requests' root shows, or the last look failed with something on its way (`stallsOn`).
    private var open: Bool {
        watching == .requests
            || RequestsWatch.stallsOn(watching, error: failure.map { _ in "failed" }, arriving: board.arriving.count)
    }

    /// A Done row's album with its songs in hand - what its ▶ plays in the tap; nil: the row's tap is done instead.
    func plays(_ row: RequestRow) -> (songs: [Song], album: Album)? {
        guard row.plays, let release = row.release, let held = ready[release], let songs = held.album.song,
              !songs.isEmpty else { return nil }
        return (songs, held.album)
    }

    // MARK: what the app watches

    /// What the app is looking at now (MainTabs): Requests' root coming into view starts a period of looking, leaving it
    /// lets every look go; the background asks nothing; a turn of `open` or `asksAgain` asks once.
    func watch(_ now: Watching) {
        let before = watching
        guard now != before else { return }
        watching = now
        if now == .requests {
            period += 1
            inFlight.removeAll()
            activeSince = Self.nowMs()
        } else if before == .requests {
            period += 1
            inFlight.removeAll()
            letLooksGo()
        }
        if now == .hidden {
            // nothing asked in the background - the look out let go too
            stopPolling()
        }
        let asked = RequestsWatch.asksAgain(before, now)
        if !checkOpen(), asked { kick() }
        if now == .requests { runLooks() }
    }

    /// deadwax came into reach, or went out of it (Reachability.whenChanged).
    func reachChanged() {
        let online = reachability.online
        guard online != wasOnline else { return }
        wasOnline = online
        if online {
            // what failed while deadwax was away says nothing now: the last answer drawn again, and a look asked
            failure = nil
            redraw()
            wasOpen = open
            kick()
        } else {
            stopPolling()
            letLooksGo()
        }
    }

    /// A new person: everything let go - and their first look asked once the new session is in hand.
    func reset() {
        epoch += 1
        stopPolling()
        letLooksGo()
        for task in writes.values { task.cancel() }
        writes.removeAll()
        polled = []
        overlays = .none
        retryingSame = []
        retryProblems = [:]
        samples = SpeedSamples()
        speeds = [:]
        statuses = nil
        spoken = nil
        answered = false
        trackingEnabled = true
        failure = nil
        doneSince = [:]
        baseline = false
        albumIds = [:]
        ready = [:]
        misses = [:]
        inFlight = []
        notes = [:]
        board = .nothing
        wasOpen = open
        let epoch = self.epoch
        Task { @MainActor [weak self] in
            guard let self, epoch == self.epoch else { return }
            self.kick()
        }
    }

    // MARK: the poll

    /// May a look go out now: deadwax in reach, the app on screen, someone signed in with nothing over the app.
    private var asks: Bool {
        RequestsPolling.asks(online: reachability.online, watching: watching)
            && server.launch == .ready && server.signInOver == nil && server.client != nil
    }

    /// A look now, the loop after it at the pace its answer says - the one before let go.
    private func kick() {
        stopPolling()
        guard asks else { return }
        let epoch = self.epoch
        let look = looks
        loop = Task { [weak self] in
            await self?.poll(epoch: epoch, look: look)
        }
    }

    private func stopPolling() {
        loop?.cancel()
        loop = nil
        looks += 1
    }

    private func poll(epoch: Int, look: Int) async {
        while !Task.isCancelled {
            guard epoch == self.epoch, look == looks, asks, let client = server.client else { return }
            var hasActive = false
            var filing = false
            do {
                let answer = try await client.jobs()
                guard !Task.isCancelled, epoch == self.epoch, look == looks else { return }
                hasActive = answer.jobs.contains { $0.isActive }
                filing = answer.jobs.contains { $0.status == "organizing" }
                land(answer)
            } catch {
                guard !Task.isCancelled, epoch == self.epoch, look == looks, !APIFailure.isCancellation(error) else { return }
                // keep asking rather than dying on one bad answer
                failure = error
                answered = true
                redraw()
            }
            // a turn of `open` asked again at once (this loop let go)
            if checkOpen() { return }
            guard !Task.isCancelled,
                  let delay = RequestsPolling.delay(open: open, hasActive: hasActive, filing: filing,
                                                    online: reachability.online, watching: watching) else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// The poll's openness looked at again: a turn asks at once (`kick`). Says whether it turned.
    @discardableResult
    private func checkOpen() -> Bool {
        let now = open
        guard now != wasOpen else { return false }
        wasOpen = now
        kick()
        return true
    }

    private func land(_ answer: JobsAnswer) {
        let jobs = answer.jobs
        speeds = samples.sample(jobs, now: Monotonic.seconds() * 1000)
        polled = jobs
        //? the album a look sees filed: Search's owned marks asked again, so the album you don't have says you have it
        let filed = RequestsWatch.newlyFiled(statuses, jobs)
        statuses = RequestsWatch.statuses(jobs)
        if !filed.isEmpty { search.refreshOwned() }
        overlays = overlays.reconcile(jobs)
        trackingEnabled = answer.trackingEnabled
        failure = nil
        answered = true
        redraw()
    }

    /// The board made again from the last answer and the overlays - and what changed said, while Requests' root shows.
    private func redraw() {
        let input = RequestsInput(
            jobs: overlays.visibleJobs(polled), pending: overlays.visiblePending(polled), speeds: speeds,
            cancelling: overlays.cancelling, retrying: overlays.retrying, retryingSame: retryingSame,
            retryProblems: retryProblems, personal: server.access.hasLibrary)
        let next = RequestsView.make(input, now: Int64(Self.nowMs()))
        if answered {
            if spoken != nil {
                let said = RequestChanges.changes(before: spoken, now: next).said
                if !said.isEmpty, watching == .requests { Notice.announce(said) }
            }
            spoken = next
        }
        // when each Done row first showed as done: 0 for those of the first answer
        let now = Self.nowMs()
        for row in next.rows(.done) where doneSince[row.key] == nil {
            doneSince[row.key] = answered && baseline ? now : 0
        }
        if answered { baseline = true }
        board = next
        runLooks()
    }

    // MARK: the writes

    /// The ✕ (or its question's answer): the overlay up before the request goes out, rolled back if it fails.
    func cancel(_ row: RequestRow) {
        guard let id = row.jobId, row.cancel == .ready, reachability.online, let client = server.client else { return }
        overlays.cancelling.insert(id)
        redraw()
        expire(cancelling: [id])
        write { [weak self] epoch in
            do {
                _ = try await client.cancelJob(id)
                guard let self, epoch == self.epoch else { return }
                self.kick()
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                //? rolled back, so the row stops claiming something that did not happen
                self.overlays.cancelling.remove(id)
                self.redraw()
            }
        }
    }

    /// Another source (`same` false) or Same source again: the row busy until a poll shows it moving, or its refusal
    /// said under its reason.
    func retry(_ row: RequestRow, same: Bool) {
        guard let id = row.jobId, !row.busy, reachability.online, let client = server.client else { return }
        overlays.retrying.insert(id)
        if same { retryingSame.insert(id) } else { retryingSame.remove(id) }
        retryProblems[id] = nil
        redraw()
        write { [weak self] epoch in
            var problem: RetryProblem?
            do {
                if same {
                    let outcome = try await client.retryJobSame(id)
                    if !outcome.retried { problem = .words(outcome.problem ?? RequestWords.sameRefused) }
                } else {
                    let outcome = try await client.retryJob(id)
                    if !outcome.moved { problem = .words(outcome.problem ?? RequestWords.nextRefused) }
                }
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                //? said in a listener's words, the error's own beside them for whoever runs deadwax
                let words = ErrorWords.of(error, admin: true, service: .downloads, failed: RequestWords.retryBroke)
                problem = .said(text: words.text, detail: words.detail)
            }
            guard let self, epoch == self.epoch else { return }
            if let problem {
                self.overlays.retrying.remove(id)
                self.retryProblems[id] = problem
                self.redraw()
            } else {
                self.kick()
            }
        }
    }

    /// Clear done: the finished jobs and the refused requests off the list at once, the jobs back if it fails.
    func clear() {
        guard reachability.online, let client = server.client else { return }
        let ids = RequestOverlays.finishedIds(polled)
        overlays = overlays.withoutRefused()
        guard !ids.isEmpty else {
            redraw()
            return
        }
        overlays.cleared.formUnion(ids)
        redraw()
        expire(cleared: ids)
        write { [weak self] epoch in
            do {
                _ = try await client.clearJobs()
                guard let self, epoch == self.epoch else { return }
                self.samples.clear()
                self.kick()
            } catch {
                guard let self, epoch == self.epoch, !APIFailure.isCancellation(error) else { return }
                self.overlays.cleared.subtract(ids)
                self.redraw()
            }
        }
    }

    /// A write's task, kept until it ends (a reset lets it go), given the epoch it began in.
    private func write(_ body: @escaping @MainActor (Int) async -> Void) {
        let key = UUID()
        let epoch = self.epoch
        writes[key] = Task { [weak self] in
            await body(epoch)
            guard let self, epoch == self.epoch else { return }
            self.writes[key] = nil
        }
    }

    /// An overlay the server never confirms, dropped after `RequestOverlays.ttlSeconds`.
    private func expire(cancelling: [Int] = [], cleared: [Int] = []) {
        write { [weak self] epoch in
            try? await Task.sleep(nanoseconds: UInt64(RequestOverlays.ttlSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, epoch == self.epoch else { return }
            self.overlays.cancelling.subtract(cancelling)
            self.overlays.cleared.subtract(cleared)
            self.redraw()
        }
    }

    // MARK: the Done rows' albums

    /// The first Done rows' albums looked for, and their songs asked for, as DoneLooks says - and looked at again when
    /// the soonest falls due. Only while Requests' root shows and deadwax can be reached.
    private func runLooks() {
        dueClock?.cancel()
        dueClock = nil
        guard watching == .requests, reachability.online, let client = server.client else { return }
        let ahead = board.rows(.done)
            .compactMap { (row: RequestRow) -> DoneLooks.Row? in
                guard row.plays, let release = row.release else { return nil }
                return DoneLooks.Row(release: release, since: doneSince[row.key] ?? 0)
            }
            .prefix(DoneLooks.prefetched)
        guard !ahead.isEmpty else { return }
        let held = DoneLooks.Held(ids: albumIds, asked: ready.mapValues { $0.at }, misses: misses, inFlight: inFlight,
                                  activeSince: activeSince)
        let due = DoneLooks.looks(Array(ahead), held: held, now: Self.nowMs())
        let epoch = self.epoch
        let period = self.period
        for release in due.look {
            inFlight.insert(release)
            lookTasks.append(Task { [weak self] in
                do {
                    let answer = try await client.storeAlbum(releaseMbid: release)
                    guard !Task.isCancelled, let self, self.live(epoch, period) else { return }
                    self.inFlight.remove(release)
                    guard let id = answer.navidromeId, !id.isEmpty else {
                        self.missed(release)
                        self.runLooks()
                        return
                    }
                    self.found(release, id)
                    self.askSongs(release, id, client, period: period)
                    self.runLooks()
                } catch {
                    guard !Task.isCancelled, let self, self.live(epoch, period) else { return }
                    self.inFlight.remove(release)
                    if !APIFailure.isCancellation(error) { self.missed(release) }
                    self.runLooks()
                }
            })
        }
        for release in due.songs {
            guard let id = albumIds[release] else { continue }
            askSongs(release, id, client, period: period)
        }
        if let wait = due.nextIn {
            dueClock = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Swift.max(0, wait) * 1_000_000))
                guard !Task.isCancelled, let self, self.live(epoch, period) else { return }
                self.runLooks()
            }
        }
    }

    /// The person and the period a look began in are still the ones now (`period` nil: the person alone - a tapped
    /// row's songs land wherever the app is).
    private func live(_ epoch: Int, _ period: Int?) -> Bool {
        epoch == self.epoch && (period == nil || period == self.period)
    }

    /// An album's songs asked for - a failure forgets its id (the album gone, or re-filed under another), so the next
    /// look asks the bridge again.
    private func askSongs(_ release: String, _ album: String, _ client: DeadwaxClient, period: Int?) {
        inFlight.insert(release)
        let at = Self.nowMs()
        let epoch = self.epoch
        lookTasks.append(Task { [weak self] in
            let answer = try? await client.album(id: album)
            guard !Task.isCancelled, let self, self.live(epoch, period) else { return }
            self.inFlight.remove(release)
            if let answer {
                self.ready[release] = (answer, at)
            } else {
                self.albumIds[release] = nil
                self.ready[release] = nil
                self.missed(release)
            }
            self.runLooks()
        })
    }

    private func found(_ release: String, _ album: String) {
        albumIds[release] = album
        misses[release] = nil
        notes[release] = nil
    }

    private func missed(_ release: String) {
        misses[release] = DoneLooks.Miss(count: (misses[release]?.count ?? 0) + 1, at: Self.nowMs())
    }

    private func letLooksGo() {
        for task in lookTasks { task.cancel() }
        lookTasks.removeAll()
        dueClock?.cancel()
        dueClock = nil
        openTask?.cancel()
        openTask = nil
        opening = nil
    }

    /// A Done row's tap: its album, on this tab - looked up now when it isn't known yet (its songs asked too when the
    /// row plays, so the next ▶ does), and opened only while Requests' root is still what shows. A second tap
    /// supersedes the first.
    func open(_ row: RequestRow) {
        guard let release = row.release else { return }
        let name = row.album.isEmpty ? row.title : row.album
        let artist: String? = row.artist.isEmpty ? nil : row.artist
        if let known = albumIds[release] {
            openTask?.cancel()
            openTask = nil
            opening = nil
            navigation.open(.album(AlbumRoute(id: known, name: name, artist: artist)))
            return
        }
        guard watching == .requests, reachability.online, let client = server.client else { return }
        openTask?.cancel()
        opening = row.key
        let epoch = self.epoch
        let period = self.period
        let key = row.key
        let plays = row.plays
        openTask = Task { [weak self] in
            do {
                let answer = try await client.storeAlbum(releaseMbid: release)
                guard !Task.isCancelled, let self, self.live(epoch, period), self.opening == key else { return }
                self.opening = nil
                guard let id = answer.navidromeId, !id.isEmpty else {
                    self.notes[release] = RequestWords.note(present: !answer.present.isEmpty,
                                                            navidromeProblem: RequestWords.cantOpen(self.library.navidrome))
                    return
                }
                self.found(release, id)
                if plays && !self.inFlight.contains(release) { self.askSongs(release, id, client, period: nil) }
                // only on the list it was tapped from: Requests' root, still shown
                guard self.watching == .requests else { return }
                self.navigation.open(.album(AlbumRoute(id: id, name: name, artist: artist)))
            } catch {
                guard !Task.isCancelled, let self, self.live(epoch, period), self.opening == key,
                      !APIFailure.isCancellation(error) else { return }
                self.opening = nil
                self.notes[release] = RequestWords.cantOpen(self.library.navidrome) ?? RequestWords.notLookedUp
            }
        }
    }

    /// This phone's clock in milliseconds since 1970 - the board's ages, the Done rows' times.
    private static func nowMs() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded(.down)
    }
}
