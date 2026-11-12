import DeadwaxCore
import Foundation
import Network
import Observation
import UIKit

/// Whether deadwax can be reached (notes/ios-specs/phase2-downloads.md 7.1): the phone's network from NWPathMonitor,
/// every request's answer or silence from the transport, and a probe of `/deadwax/health` (3 s) when a request goes
/// unanswered - every rule Core's OfflineRule, this only the monitor, the probe and its timer.
///
/// Three states: `online`, `noNetwork` (no request is tried), `unreachable` (two failures in a row; the probe then runs
/// every 30 s, and at once when the path changes or someone pulls a list or presses Try again). The downloads' planner
/// reads the path's facts too: Wi-Fi only waits out mobile data, a hotspot and Low Data Mode.
///
/// VoiceOver hears the offline banner's line as deadwax goes out of reach, and "Back online" as it comes back - said here,
/// once, since every page draws its own banner (7.2).
@MainActor
@Observable
final class Reachability {
    private(set) var reach: Reach = .online
    /// The path as the monitor last said (a home Wi-Fi until its first word).
    private(set) var path: NetworkPath = .wifiAtHome
    /// A probe is out (the banner's "Trying…").
    private(set) var probing = false
    /// The last probe: when, and whether deadwax answered it (Debug's).
    private(set) var lastProbe: (at: Date, answered: Bool)?
    /// The monitor has said the phone's path once: until then `reach` is an assumption (the Library's root waits for it
    /// to choose between your albums and Downloaded as the app opens).
    private(set) var pathKnown = false

    var online: Bool { reach == .online }

    @ObservationIgnored private var rule = OfflineRule()
    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var handlers: [@MainActor () -> Void] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = OfflineRule.probeTimeout
        configuration.timeoutIntervalForResource = OfflineRule.probeTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(server: ServerModel) {
        self.server = server
    }

    /// The monitor and the timer started, once (the app's start).
    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] update in
            let path = NetworkPath(satisfied: update.status == .satisfied, wifi: update.usesInterfaceType(.wifi),
                                   cellular: update.usesInterfaceType(.cellular), expensive: update.isExpensive,
                                   constrained: update.isConstrained)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.pathChanged(path) } }
        }
        monitor.start(queue: DispatchQueue(label: "deadwax.reachability"))
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// `action` runs whenever the state or the path changes.
    func whenChanged(_ action: @escaping @MainActor () -> Void) {
        handlers.append(action)
    }

    /// A request deadwax answered (any status), or one nothing answered - from the transport.
    nonisolated func heard(answered: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let now = Monotonic.seconds()
                if answered {
                    self.rule.answered(now: now)
                    self.publish()
                } else {
                    self.act(self.rule.noAnswer(now: now))
                }
            }
        }
    }

    /// Someone asked: a pull to refresh, the banner's Try again - a probe at once while deadwax isn't online.
    func tryNow() {
        act(rule.askNow(now: Monotonic.seconds()))
    }

    /// Whether deadwax answered anything since `since` (seconds on the monotonic clock) - a download's failure is a try
    /// only then.
    func answeredSince(_ since: Double) -> Bool { rule.answeredSince(since) }

    // MARK: the rule's wiring

    private func pathChanged(_ new: NetworkPath) {
        if !pathKnown { pathKnown = true }
        act(rule.pathChanged(new, now: Monotonic.seconds()))
    }

    private func tick() {
        act(rule.tick(now: Monotonic.seconds()))
    }

    private func act(_ action: OfflineRule.Action) {
        publish()
        guard action == .probe else { return }
        guard let url = server.client?.url(Routes.health) else {
            rule.probeFailed(now: Monotonic.seconds())
            publish()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = OfflineRule.probeTimeout
        Task {
            let answered: Bool
            do {
                _ = try await probeSession.data(for: request)
                answered = true
            } catch {
                answered = false
            }
            let now = Monotonic.seconds()
            lastProbe = (Date(), answered)
            if answered { rule.probeAnswered(now: now) } else { rule.probeFailed(now: now) }
            publish()
        }
    }

    private func publish() {
        let changed = reach != rule.reach || (rule.path.map { $0 != path } ?? false)
        if probing != rule.probing { probing = rule.probing }
        guard changed else { return }
        let was = reach
        reach = rule.reach
        if let new = rule.path { path = new }
        if was != reach, pathKnown { announce(from: was) }
        for handler in handlers { handler() }
    }

    /// The banner's coming and going, for VoiceOver - its line as it comes (or changes), "Back online" as it goes.
    private func announce(from was: Reach) {
        let words = reach == .online ? DownloadWords.backOnline : DownloadWords.banner(reach)?.line
        guard let words else { return }
        UIAccessibility.post(notification: .announcement, argument: words)
    }
}
