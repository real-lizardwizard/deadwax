#if canImport(AVFAudio)
import Foundation

/// Bytes that arrive over time - a song being streamed into a cache file. A StreamSource reads
/// them at its own offset, so a second reader (a seek before the song has all arrived) can start
/// again from the top while the fetch goes on.
public protocol ByteSource: AnyObject {
    /// Up to `count` bytes from `offset`, or empty when none have arrived there yet.
    func bytes(at offset: Int, count: Int) -> Data
    /// Every byte has arrived.
    var isComplete: Bool { get }
    /// The fetch failed; no more bytes will come.
    var failure: AudioFailure? { get }
}

/// A song fetched over http into the streaming cache, a chunk at a time, while it is decoded and
/// played (the cache's rules are Core's StreamCache).
///
/// One URLSession of its own with cookies off: the request carries deadwax's session as `Cookie:`
/// already (DeadwaxClient builds it). The bytes go into `<name>.part`; once the last has arrived and
/// their count is what the server said (Content-Length), the part is renamed to `<name>` - so a file
/// under the song's own name is always whole - and from then on it plays as a FileSource (seekable to
/// the sample). Readers keep reading through the fetch's own file handle across the rename (the same
/// file). A fetch that fails or is cancelled deletes its part: the next ask streams from the top.
public final class StreamFetch: NSObject, ByteSource, URLSessionDataDelegate {
    /// The complete song's file, once `isComplete`.
    public let fileURL: URL
    /// Where the bytes go while they arrive.
    public let partURL: URL
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var written = 0
    private var complete = false
    private var failed: AudioFailure?
    private var cancelled = false
    /// The length the server said (Content-Length), when it did.
    public private(set) var expectedLength: Int64?

    /// Called on the fetch's own queue when the last byte is written or the fetch fails (not when
    /// it is cancelled).
    public var onFinish: ((StreamFetch) -> Void)?

    /// How long the request may go without a byte before it fails (URLSession's timeoutIntervalForRequest):
    /// 20 s. Tests: a test holding a fetch open gives it longer, so a test held off its thread that long
    /// doesn't see the fetch end under it (notes/ios.md "The engine's tests under load"). Set before `start`.
    var idleTimeout: TimeInterval = 20

    /// `configuration`: the session's, for tests (a URLProtocol stub); by default an ephemeral one.
    /// Cookies are turned off on it either way.
    public init(request: URLRequest, fileURL: URL, configuration: URLSessionConfiguration? = nil) {
        self.request = request
        self.fileURL = fileURL
        partURL = fileURL.appendingPathExtension("part")
        self.configuration = configuration ?? .ephemeral
        super.init()
    }

    /// Makes the part and starts the request. Nothing, when the fetch was let go before it started:
    /// the app hands a fetch out under its own lock and starts it after, so a skip on the main thread
    /// can cancel it in between - and then no part is made and nothing is asked of the server.
    public func start() {
        enum Begun {
            case letGo
            case unwritable
            case running(URLSessionDataTask)
        }
        // all under the lock, so a cancel() lands either before (nothing starts) or after (it sees the
        // session, and stops it and deletes the part)
        let begun: Begun = lock.withLock {
            guard !cancelled, failed == nil, !complete, session == nil else { return .letGo }
            let manager = FileManager.default
            try? manager.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var attributes: [FileAttributeKey: Any]?
            #if !os(macOS)
            // readable and writable while the phone is locked after its first unlock, so a locked phone
            // goes on fetching the next song (iOS's default class today; said, so a new default can't
            // take it away)
            attributes = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            #endif
            _ = manager.createFile(atPath: partURL.path, contents: nil, attributes: attributes)
            writer = try? FileHandle(forWritingTo: partURL)
            reader = try? FileHandle(forReadingFrom: partURL)
            guard writer != nil, reader != nil else { return .unwritable }
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = idleTimeout
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            return .running(session.dataTask(with: request))
        }
        switch begun {
        case .letGo:
            return
        case .unwritable:
            fail(AudioFailure("The phone couldn't make a file to stream into (\(partURL.lastPathComponent))."))
        case .running(let task):
            // a cancel() since has cancelled the task with its session: it ends at once, unheard
            task.resume()
        }
    }

    /// Stops the fetch and deletes its part - a song skipped past. A reader still holding it sees it
    /// fail. A complete fetch keeps its file (it is the cache's now).
    public func cancel() {
        let session: URLSession? = lock.withLock {
            let running = self.session
            self.session = nil
            if !complete {
                cancelled = true
                if failed == nil { failed = AudioFailure("The song's fetch was let go.", kind: .network) }
                closeWriter()
                try? FileManager.default.removeItem(at: partURL)
            }
            return running
        }
        session?.invalidateAndCancel()
    }

    public var bytesWritten: Int { lock.withLock { written } }
    public var isComplete: Bool { lock.withLock { complete } }
    public var failure: AudioFailure? { lock.withLock { failed } }
    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func bytes(at offset: Int, count: Int) -> Data {
        lock.withLock {
            guard offset < written, let reader else { return Data() }
            let wanted = min(count, written - offset)
            do {
                try reader.seek(toOffset: UInt64(offset))
                return try reader.read(upToCount: wanted) ?? Data()
            } catch {
                return Data()
            }
        }
    }

    /// Called with the lock held.
    private func closeWriter() {
        try? writer?.close()
        writer = nil
    }

    private func fail(_ failure: AudioFailure) {
        let first: Bool = lock.withLock {
            guard failed == nil, !complete else { return false }
            failed = failure
            closeWriter()
            try? FileManager.default.removeItem(at: partURL)
            return true
        }
        if first { onFinish?(self) }
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            completionHandler(.cancel)
            fail(status == 401
                 ? AudioFailure("deadwax says this phone isn't signed in (401). Sign in again.", kind: .signedOut, status: 401)
                 : AudioFailure("deadwax answered \(status) for this song.", kind: .unsupported, status: status))
            return
        }
        if response.expectedContentLength > 0 { expectedLength = response.expectedContentLength }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let refused: Bool = lock.withLock {
            guard let writer, failed == nil else { return false }
            do {
                _ = try writer.seekToEnd()
                try writer.write(contentsOf: data)
                written += data.count
                return false
            } catch {
                return true
            }
        }
        if refused {
            dataTask.cancel()
            fail(AudioFailure("The phone couldn't write the stream to its disk."))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error {
            // cancelled by cancel(), or by a refusal that said why already
            if (error as? URLError)?.code == .cancelled, failure != nil || isCancelled { return }
            fail(AudioFailure("The song stopped arriving: \(error.localizedDescription)", kind: .network))
            return
        }
        let count = bytesWritten
        if let expected = expectedLength, Int64(count) != expected {
            fail(AudioFailure(Int64(count) < expected
                              ? "The song arrived cut short (\(count) of \(expected) bytes)."
                              : "The song arrived longer than deadwax said (\(count) of \(expected) bytes).",
                              kind: .network))
            return
        }
        let finished: Bool = lock.withLock {
            guard failed == nil, !cancelled else { return false }
            try? writer?.synchronize()
            closeWriter()
            // the part becomes the song's file: a rename, so a reader's handle reads on unchanged
            let manager = FileManager.default
            try? manager.removeItem(at: fileURL)
            do {
                try manager.moveItem(at: partURL, to: fileURL)
            } catch {
                failed = AudioFailure("The phone couldn't keep the song it streamed: \(error.localizedDescription)")
                try? manager.removeItem(at: partURL)
                return true
            }
            complete = true
            return true
        }
        if finished { onFinish?(self) }
    }
}
#endif
