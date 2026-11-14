import BackgroundTasks
import DeadwaxCore
import UIKit

/// Your library in the background (Phase 3, slice 3, notes/ios-specs/phase3-autodownload.md 2.9): the two tasks iOS
/// may run with the app suspended - the refresh (`BGAppRefreshTask`, UIBackgroundModes `fetch`) and the charger's
/// (`BGProcessingTask` with requiresExternalPower, `processing`) - registered at launch by the app delegate, asked for
/// as DownloadModel says (LibraryBackground.asks), and each run as DownloadModel.backgroundRun: the same check and the
/// same plan as in front.
///
/// Both identifiers are in Info.plist's BGTaskSchedulerPermittedIdentifiers (check_project.py checks they are Core's).
/// iOS decides when either runs, possibly rarely: nothing depends on one running.
///
/// After the review: a run asks for the next as it begins (a run iOS ends early still leaves one asked for), has its own
/// deadline inside iOS's ~30 s, and a launch that couldn't read the phone's settings (before its first unlock) changes
/// no request but putting back the one it used up.
@MainActor
final class BackgroundWork {
    static let shared = BackgroundWork()

    /// The downloads, set as the app is made (DeadwaxApp.init) - before any task can run.
    var downloads: DownloadModel? {
        didSet {
            downloads?.askBackground = { [weak self] asks in self?.ask(asks) }
        }
    }

    private var registered = false

    private init() {}

    /// Both identifiers given their run - before the launch ends, as BGTaskScheduler requires (the app delegate's
    /// didFinishLaunching). And whether this launch read the settings, now UIApplication can say whether the phone is
    /// unlocked.
    func register() {
        guard !registered else { return }
        registered = true
        downloads?.settleReadable(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        for identifier in LibraryBackground.identifiers {
            let done = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) {
                (task: BGTask) -> Void in
                MainActor.assumeIsolated { BackgroundWork.shared.run(task) }
            }
            if !done { downloads?.noteBackground("couldn't register \(identifier)") }
        }
    }

    /// Each request as `asks` says (LibraryBackground.asks): asked for (one already asked for is replaced: the refresh's
    /// earliest begin moves 15 minutes on), cancelled, or left as it is.
    func ask(_ asks: [String: LibraryBackground.Ask]) {
        let scheduler = BGTaskScheduler.shared
        for identifier in LibraryBackground.identifiers where asks[identifier] == .cancel {
            scheduler.cancel(taskRequestWithIdentifier: identifier)
        }
        if asks[LibraryBackground.refreshID] == .ask {
            let request = BGAppRefreshTaskRequest(identifier: LibraryBackground.refreshID)
            request.earliestBeginDate = Date(timeIntervalSinceNow: Double(LibraryBackground.refreshAfterMs) / 1000)
            submit(request)
        }
        if asks[LibraryBackground.chargingID] == .ask {
            let request = BGProcessingTaskRequest(identifier: LibraryBackground.chargingID)
            request.requiresExternalPower = true
            request.requiresNetworkConnectivity = true
            submit(request)
        }
    }

    /// A relaunch for the background session's events (DeadwaxApp's `.backgroundTask(.urlSession)`), begun at `began`,
    /// its events in: the next batch handed over before the app is suspended again - the events and the plan within
    /// one budget (`LibraryBackground.eventsMs`).
    func eventsHandled(began: ContinuousClock.Instant) async {
        let clock = ContinuousClock()
        let parts = (clock.now - began).components
        let elapsed = parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
        let left = LibraryBackground.left(LibraryBackground.eventsMs, elapsedMs: elapsed)
        await downloads?.eventsHandled(until: clock.now + .milliseconds(left))
    }

    private func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            downloads?.noteBackground("couldn't ask for \(request.identifier): \(error)")
        }
    }

    /// One run: DownloadModel's, ended when it ends or when iOS ends it (its expiration cancels the run, which keeps
    /// "ended by iOS" for Debug) - the task told it is complete exactly once.
    private func run(_ task: BGTask) {
        let completion = Completion(task)
        guard let downloads else {
            completion.finish(success: false)
            return
        }
        let identifier = task.identifier
        // the next asked for first: this one's request is used up, and iOS may end this run before it ends
        downloads.askBackgroundTasks(always: true, ran: identifier)
        let work = Task { @MainActor () -> Void in
            await downloads.backgroundRun(task: identifier)
            completion.finish(success: !Task.isCancelled)
        }
        task.expirationHandler = { () -> Void in
            work.cancel()
            completion.finish(success: false)
        }
    }
}

/// A BGTask's setTaskCompleted, called once - by the run's end or by iOS's expiration, whichever is first.
private final class Completion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: BGTask?

    init(_ task: BGTask) { self.task = task }

    func finish(success: Bool) {
        let task: BGTask? = lock.withLock {
            let task = self.task
            self.task = nil
            return task
        }
        task?.setTaskCompleted(success: success)
    }
}
