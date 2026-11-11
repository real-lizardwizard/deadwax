import DeadwaxCore
import Foundation
import UIKit

// Resume what was playing (D5, resume.md 6-8): Core's ResumeController, reached the player, deadwax and the clock
// through these. The model makes one per signed-in person (logins off: one) once /me has answered, observes it at
// every change of the queue or of playing, tells it each position while playing and each seek, and as the app goes
// to the back and comes to the front.

/// The player as resume reads it: the engine's position now (a queue put back answers its parked second), and its
/// one action, the queue put back paused (QueueController.restoreQueue).
final class ResumePlayerLink: ResumePlayer {
    private let read: () -> Double
    private let put: (UpNextQueue, Double) -> UpNextQueue?

    init(position: @escaping () -> Double, restore: @escaping (UpNextQueue, Double) -> UpNextQueue?) {
        read = position
        put = restore
    }

    func position() -> Double { read() }

    func restoreQueue(_ queue: UpNextQueue, position: Double) -> UpNextQueue? { put(queue, position) }
}

/// deadwax's three queue routes. Each answer is handed back on the main thread; a request cancelled (the app let it
/// go) is never answered. The saves are kept alive in the background (beginBackgroundTask): going to the back sends
/// what is due at once, and the phone may lock straight after. The songs of a queue fetched are given to the player
/// (`shelve`), as the app has them - Info reads them, and their sizes check the stream cache.
final class ResumeRoutes: ResumeServer {
    private let client: @MainActor () -> DeadwaxClient?
    private let shelve: @MainActor ([Song]) -> Void

    init(client: @escaping @MainActor () -> DeadwaxClient?, shelve: @escaping @MainActor ([Song]) -> Void) {
        self.client = client
        self.shelve = shelve
    }

    func queue(_ done: @escaping (Result<QueueAnswer, ResumeFailure>) -> Void) {
        Task { @MainActor in
            guard let client = self.client() else { return }
            do {
                let answer = try await client.call(Routes.queue, as: QueueAnswer.self)
                self.shelve(answer.tracks)
                done(.success(answer))
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                done(.failure(Self.failure(error)))
            }
        }
    }

    func save(_ body: QueueSaveBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) {
        // begun now, as the call is made (going to the back sends at once, and iOS may suspend the app straight after)
        let task = MainActor.assumeIsolated { BackgroundTask("deadwax: saving what's playing") }
        Task { @MainActor in
            defer { task.end() }
            guard let client = self.client() else { return }
            do {
                done(.success(try await client.call(Routes.saveQueue, as: SavedQueue.self, sending: body)))
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                done(.failure(Self.failure(error)))
            }
        }
    }

    func saveAt(_ body: QueueAtBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) {
        // begun now, as the call is made (going to the back sends at once, and iOS may suspend the app straight after)
        let task = MainActor.assumeIsolated { BackgroundTask("deadwax: saving where it is") }
        Task { @MainActor in
            defer { task.end() }
            guard let client = self.client() else { return }
            do {
                done(.success(try await client.call(Routes.saveQueueAt, as: SavedQueue.self, sending: body)))
            } catch {
                guard !APIFailure.isCancellation(error) else { return }
                done(.failure(Self.failure(error)))
            }
        }
    }

    /// deadwax's status where it answered one; nothing that answered (offline, timed out, an answer that couldn't be
    /// read) otherwise.
    static func failure(_ error: any Error) -> ResumeFailure {
        ResumeFailure(status: (error as? APIFailure)?.status)
    }
}

/// Time as resume reads it, on the main queue: milliseconds on the monotonic clock, a wait, and "soon" (the main
/// queue's next turn).
final class MainQueueClock: ResumeClock {
    var now: Int64 { Int64((Monotonic.seconds() * 1000).rounded(.down)) }

    func after(_ ms: Int64, _ work: @escaping () -> Void) -> ResumeWait {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(max(ms, 0))), execute: item)
        return MainQueueWait(item)
    }

    func soon(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }
}

final class MainQueueWait: ResumeWait {
    private let item: DispatchWorkItem

    init(_ item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item.cancel()
    }
}

/// A request kept alive while the app is in the background, ended once it is answered (or when iOS says time is up).
@MainActor
final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
