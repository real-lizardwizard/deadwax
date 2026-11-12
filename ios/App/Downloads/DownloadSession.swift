import DeadwaxCore
import Foundation

/// The one background URLSession downloads go through (notes/ios-specs/phase2-downloads.md 8.3), made at every launch so
/// iOS can hand it what its tasks did while the app was gone - the app relaunched in the background for it, by
/// `.backgroundTask(.urlSession(...))` on the WindowGroup (no app delegate).
///
/// Download tasks only, three at a time to deadwax, cookies off: each request carries its own `Cookie:` as every request
/// does. Each task's `taskDescription` is its `DownloadTaskName` (server, person, song, suffix), so a finished file is
/// moved into the right person's folder before the delegate returns - the system deletes it after - whoever is signed in.
///
/// Everything a task does is told to `handler` on the main thread, synchronously and in order, so the store has it
/// before iOS is told the events are done. Progress is never told: it is read from the tasks (`progress()`), never kept.
final class DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "net.lizardlounge.deadwax.downloads"

    /// What a task did.
    enum Event {
        /// It finished: `status` is deadwax's (0 when there was none); `part` the file moved into place when it was the
        /// song; `unsaved` the system's words when the move failed (`full` when for want of room).
        case finished(task: Int, name: DownloadTaskName, status: Int, part: URL?, unsaved: String?, full: Bool)
        /// It ended without a file: the system's error, its resume data when it can carry on, and whether iOS ended it
        /// because the app was force quit. `ours` when the app cancelled it itself.
        case failed(task: Int, name: DownloadTaskName, error: NSError, resume: Data?, forceQuit: Bool, ours: Bool)
    }

    /// A task out, as the session has it.
    struct Out {
        let task: Int
        let name: DownloadTaskName
        let running: Bool
        /// Bytes received so far, and the bytes this answer is to bring (-1 when deadwax didn't say) - a resumed task's
        /// answer brings only the rest.
        let received: Int64
        let expected: Int64
    }

    private let lock = NSLock()
    private var handler: (@MainActor (Event) -> Void)?
    private var made: URLSession?
    /// Tasks the app cancelled: their ends are said as `ours`.
    private var cancelledByUs: Set<Int> = []
    /// Tasks whose file was told: their completion (with no error) says nothing more.
    private var told: Set<Int> = []
    private var eventsWaiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var eventsDone = false

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "deadwax.downloads"
        return queue
    }()

    /// The session, made once `connect` has given it somewhere to tell.
    private var session: URLSession? { lock.withLock { made } }

    /// Starts the session, telling `handler` everything its tasks do - those that ran while the app was gone first.
    func connect(_ handler: @escaping @MainActor (Event) -> Void) {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        lock.withLock {
            self.handler = handler
            if made == nil { made = URLSession(configuration: configuration, delegate: self, delegateQueue: queue) }
        }
    }

    // MARK: tasks

    /// A task for `name`: from `resume` when there is some (the request inside it - its cookie and its network flags -
    /// is the one it was made with), else from `request`. `priority` steps down through an album, so it fills from the top.
    @discardableResult
    func make(_ request: URLRequest, name: DownloadTaskName, resume: Data?, priority: Float) -> Int? {
        guard let session else { return nil }
        let task = resume.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
        task.taskDescription = name.description
        task.priority = min(max(priority, 0), 1)
        task.resume()
        return task.taskIdentifier
    }

    /// Every task out, as the session has it now.
    func tasks() async -> [Out] {
        guard let session else { return [] }
        return await session.allTasks.compactMap { task in
            guard let name = task.taskDescription.flatMap(DownloadTaskName.init(description:)),
                  task.state == .running || task.state == .suspended else { return nil }
            return Out(task: task.taskIdentifier, name: name, running: task.state == .running,
                       received: task.countOfBytesReceived, expected: task.countOfBytesExpectedToReceive)
        }
    }

    /// The tasks with these ids cancelled; with `resume`, each hands back its resume data (nil when it can't).
    func cancel(_ ids: Set<Int>, resume: Bool) async -> [Int: Data] {
        guard let session, !ids.isEmpty else { return [:] }
        lock.withLock { cancelledByUs.formUnion(ids) }
        var kept: [Int: Data] = [:]
        for task in await session.allTasks where ids.contains(task.taskIdentifier) {
            guard resume, let download = task as? URLSessionDownloadTask else {
                task.cancel()
                continue
            }
            if let data = await download.cancelByProducingResumeData() { kept[task.taskIdentifier] = data }
        }
        return kept
    }

    // MARK: the relaunch

    /// Returns once iOS has handed over every event of a background relaunch (or after 25 s at most) - the
    /// `.backgroundTask(.urlSession(...))` closure's body, so iOS keeps the app up until the store has them.
    func eventsDelivered() async {
        let key = UUID()
        let cap = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            self?.release(key)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now: Bool = lock.withLock {
                if eventsDone {
                    eventsDone = false
                    return true
                }
                eventsWaiting[key] = continuation
                return false
            }
            if now { continuation.resume() }
        }
        cap.cancel()
    }

    private func release(_ key: UUID) {
        let continuation = lock.withLock { eventsWaiting.removeValue(forKey: key) }
        continuation?.resume()
    }

    private func finishEvents() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            let waiting = Array(eventsWaiting.values)
            eventsWaiting = [:]
            if waiting.isEmpty { eventsDone = true }
            return waiting
        }
        for continuation in waiting { continuation.resume() }
    }

    // MARK: the delegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let name = downloadTask.taskDescription.flatMap(DownloadTaskName.init(description:)) else { return }
        let id = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        var part: URL?
        var unsaved: String?
        var full = false
        // a status other than the song's is a failure whatever its body: a background download "succeeds" with an
        // error page, which the system deletes as this returns
        if DownloadRules.isTheSong(status: status), let target = DownloadStore.partURL(for: name) {
            let manager = FileManager.default
            do {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? manager.removeItem(at: target)
                try manager.moveItem(at: location, to: target)
                DownloadStore.protect(target)
                part = target
            } catch {
                let error = error as NSError
                unsaved = error.localizedDescription
                full = error.code == NSFileWriteOutOfSpaceError
                    || (error.underlyingErrors.first as NSError?)?.code == Int(ENOSPC)
            }
        }
        lock.withLock { _ = told.insert(id) }
        tell(.finished(task: id, name: name, status: status, part: part, unsaved: unsaved, full: full))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let (wasTold, ours) = lock.withLock { (told.remove(id) != nil, cancelledByUs.remove(id) != nil) }
        guard let name = task.taskDescription.flatMap(DownloadTaskName.init(description:)) else { return }
        guard let error else {
            // finished with no file told: nothing came at all - said as a failure with no answer
            if !wasTold {
                tell(.failed(task: id, name: name, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorZeroByteResource),
                             resume: nil, forceQuit: false, ours: ours))
            }
            return
        }
        let ns = error as NSError
        let reason = ns.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? Int
        tell(.failed(task: id, name: name, error: ns, resume: ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                     forceQuit: reason == NSURLErrorCancelledReasonUserForceQuitApplication, ours: ours))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // after every event above, each told on the main thread already
        DispatchQueue.main.async { self.finishEvents() }
    }

    /// On the main thread, before the delegate returns: the store has it before the next event, and before iOS hears
    /// the events are done.
    private func tell(_ event: Event) {
        guard let handler = lock.withLock({ self.handler }) else { return }
        DispatchQueue.main.sync {
            MainActor.assumeIsolated { handler(event) }
        }
    }
}
