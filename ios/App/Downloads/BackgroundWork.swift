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
    /// didFinishLaunching).
    func register() {
        guard !registered else { return }
        registered = true
        for identifier in LibraryBackground.identifiers {
            let done = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) {
                (task: BGTask) -> Void in
                MainActor.assumeIsolated { BackgroundWork.shared.run(task) }
            }
            if !done { downloads?.noteBackground("couldn't register \(identifier)") }
        }
    }

    /// The tasks `asks` names asked for (a request already asked for is replaced: the refresh's earliest begin moves 15
    /// minutes on); the others' requests cancelled.
    func ask(_ asks: Set<String>) {
        let scheduler = BGTaskScheduler.shared
        for identifier in LibraryBackground.identifiers where !asks.contains(identifier) {
            scheduler.cancel(taskRequestWithIdentifier: identifier)
        }
        if asks.contains(LibraryBackground.refreshID) {
            let request = BGAppRefreshTaskRequest(identifier: LibraryBackground.refreshID)
            request.earliestBeginDate = Date(timeIntervalSinceNow: Double(LibraryBackground.refreshAfterMs) / 1000)
            submit(request)
        }
        if asks.contains(LibraryBackground.chargingID) {
            let request = BGProcessingTaskRequest(identifier: LibraryBackground.chargingID)
            request.requiresExternalPower = true
            request.requiresNetworkConnectivity = true
            submit(request)
        }
    }

    /// A relaunch for the background session's events, its events in (DeadwaxApp's `.backgroundTask(.urlSession)`):
    /// the next batch handed over before the app is suspended again.
    func eventsHandled() async {
        await downloads?.eventsHandled()
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
