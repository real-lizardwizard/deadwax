import DeadwaxCore
import Observation
import SwiftUI

/// The event log's state, held by the app (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; the web's
/// app/EventLog.tsx, whose module keeps `kept` beyond the page): the lines held, the history read and the stream, and
/// where the stream stands.
///
/// Every decision is Core's (EventStream.Feed, over EventLog.State - held to the web's own code by log-vectors.json):
/// when the history is read, when the stream opens and from which line, what an answer or a frame does to the lines, when
/// a stream lost is asked again and from where, what a refusal stops. This only carries them out: asks, waits and hands
/// on. Each ask's number is taken by Feed as the ask is decided, before the Task that sends it - so an answer for any
/// ask but the newest (one a stop, a page gone or a Try again made stale) is dropped.
///
/// The stream is held only while it is wanted (`wanted`): the page shows, the app is in front, deadwax is in reach, this
/// person has Settings and the log, and neither the sign-in nor Now Playing is over the app (the web's `managingLive`,
/// whose `!sheetOpen` is Now Playing). Anything else calls it off - the page gone, the app to the background (so a stream
/// that never ends never keeps the app running there: no BackgroundHold, no idle timer), deadwax out of reach, a session
/// ended (the 401 that brings the sign-in), Now Playing opened over the page (a full-screen cover, which leaves the page
/// shown under it). Wanted again, the history is read again and the stream rejoined from the last line held, nothing twice
/// and nothing cleared back.
///
/// Another person (`reset`): everything of the last one's let go - a stream opened for them never draws for anyone else.
@MainActor
@Observable
final class EventLogModel {
    /// The lines, the stream's state, what went wrong (Core's Feed).
    private(set) var feed = EventStream.Feed()

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    /// Whether Now Playing is over the app.
    @ObservationIgnored private let navigation: AppNavigation
    /// One more each time the person changes: an answer for the last one is dropped.
    @ObservationIgnored private var generation = 0
    /// How many copies of the page show now.
    @ObservationIgnored private var pagesShown = 0
    /// The app is in front.
    @ObservationIgnored private var active = true
    /// What is out: the history read, the stream, or the wait after a loss - called off by a stop.
    @ObservationIgnored private var asking: Task<Void, Never>?

    init(server: ServerModel, reachability: Reachability, navigation: AppNavigation) {
        self.server = server
        self.reachability = reachability
        self.navigation = navigation
    }

    // MARK: what the page draws

    /// Settings and the log (EventLog.allowed).
    var allowed: Bool { EventLog.allowed(server.access) }

    /// deadwax's own words, for whoever runs it (access.ts seesDetail).
    private var admin: Bool { server.access.seesDetail }

    /// The stream is wanted now.
    private var wanted: Bool {
        pagesShown > 0 && active && reachability.online && allowed && server.signInOver == nil && server.client != nil
            && !navigation.nowPlayingShown
    }

    // MARK: told

    /// The page came on screen.
    func shows() {
        pagesShown += 1
        recheck()
    }

    /// The page went (another tab, popped, a page pushed over it).
    func hides() {
        pagesShown = max(0, pagesShown - 1)
        recheck()
    }

    /// The scene's phase: to the background the stream is called off; back in front with the page up, the history and
    /// the stream asked again from the last line held.
    func scene(_ phase: ScenePhase) {
        switch phase {
        case .background:
            active = false
            recheck()
        case .active:
            guard !active else { return }
            active = true
            recheck()
        default:
            break
        }
    }

    /// Anything the stream's being wanted turns on changed - deadwax in reach or out of it, the sign-in or Now Playing
    /// over the app come or gone, /me answered again - or an answer landed: Feed asked again, and what it says carried out.
    func recheck() {
        carry(feed.update(wanted: wanted, online: reachability.online))
        announce()
    }

    /// Try again (beside the history's failure, or a refused stream's).
    func tryAgain() {
        carry(feed.tryAgain(wanted: wanted))
        announce()
    }

    /// Clear: this view emptied, nothing on the server.
    func clear() {
        feed.clear()
    }

    // MARK: carrying out

    private func carry(_ action: EventStream.Feed.Action) {
        switch action {
        case .none:
            return
        case .stop:
            asking?.cancel()
            asking = nil
        case .read(let ask):
            read(ask)
        case .open(let ask, let after, let boot):
            open(ask, after: after, boot: boot)
        case .wait(let ask, let seconds):
            wait(ask, seconds)
        case .askMe:
            Task { await server.refreshMe() }
        }
    }

    /// The history (`GET /recent`).
    private func read(_ ask: Int) {
        // none to ask with (signed out): not wanted, so Feed is told and nothing waits on an ask never sent
        guard let client = server.client else { return recheck() }
        let mine = generation
        asking?.cancel()
        asking = Task {
            let result: Result<RecentLog, any Error>
            do {
                result = .success(try await client.recentLog())
            } catch {
                result = .failure(error)
            }
            guard mine == generation, !Task.isCancelled else { return }
            switch result {
            case .success(let recent):
                carry(feed.historyLanded(ask, recent))
            case .failure(let error):
                carry(feed.historyFailed(ask, error, admin: admin))
            }
            announce()
            recheck()
        }
    }

    /// The stream, from the line after `after` of run `boot` (or from now): Live once it opens, each frame handed to Feed
    /// as it comes, and how it ended told to Feed - unless it was called off, which is no ending at all.
    private func open(_ ask: Int, after: Int?, boot: String?) {
        guard let client = server.client else { return recheck() }
        let mine = generation
        asking?.cancel()
        asking = Task {
            var ended: (any Error)?
            do {
                let frames = try await client.logStream(after: after, boot: boot)
                guard mine == generation, !Task.isCancelled else { return }
                feed.opened(ask)
                announce()
                for try await frame in frames {
                    guard mine == generation, !Task.isCancelled else { return }
                    feed.frame(ask, frame)
                }
            } catch {
                ended = error
            }
            // called off: the page's own stop, which Feed already knows of
            guard mine == generation, !Task.isCancelled else { return }
            carry(feed.streamEnded(ask, ended, admin: admin))
            announce()
            recheck()
        }
    }

    /// The wait after a loss (STREAM_RETRY_MS), then the stream again from the last line held.
    private func wait(_ ask: Int, _ seconds: Double) {
        let mine = generation
        asking?.cancel()
        asking = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard mine == generation, !Task.isCancelled else { return }
            carry(feed.retryDue(ask))
        }
    }

    // MARK: VoiceOver

    /// What changed said, once it's carried out - Feed.announcement decides what, if anything: one announcement for it
    /// (a refusal and its words together, never one cutting the other off), and nothing out of reach, where the app's
    /// banner speaks at that very moment (Reachability's own announcement).
    private func announce() {
        guard let words = feed.announcement(inReach: reachability.online), !words.isEmpty else { return }
        AccessibilityNotification.Announcement(words).post()
    }

    // MARK: another person

    /// The person changed: the lines and the stream of the last one's let go - what is out called off, and nothing it
    /// answers drawn.
    func reset() {
        generation += 1
        asking?.cancel()
        asking = nil
        feed = EventStream.Feed()
        pagesShown = 0
    }
}
