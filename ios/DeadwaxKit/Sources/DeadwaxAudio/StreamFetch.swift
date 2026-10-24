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
    var failure: String? { get }
}

/// A song fetched over http into a file, a chunk at a time, while it is decoded and played.
///
/// One URLSession of its own with cookies off: the request carries deadwax's session as `Cookie:`
/// already (DeadwaxClient builds it). The file is the cache's: when complete it is a whole copy of
/// the song, which plays from then on as a FileSource (seekable to the sample).
public final class StreamFetch: NSObject, ByteSource, URLSessionDataDelegate {
    public let fileURL: URL
    private let request: URLRequest
    private let lock = NSLock()
    private var session: URLSession?
    private var writer: FileHandle?
    private var reader: FileHandle?
    private var written = 0
    private var complete = false
    private var failed: String?
    /// The length the server said (Content-Length), when it did.
    public private(set) var expectedLength: Int64?

    /// Called on the fetch's own queue when the last byte is written or the fetch fails.
    public var onFinish: ((StreamFetch) -> Void)?

    public init(request: URLRequest, fileURL: URL) {
        self.request = request
        self.fileURL = fileURL
        super.init()
    }

    public func start() {
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        writer = try? FileHandle(forWritingTo: fileURL)
        reader = try? FileHandle(forReadingFrom: fileURL)
        guard writer != nil, reader != nil else {
            fail("The phone couldn't make a file to stream into (\(fileURL.lastPathComponent)).")
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
    }

    public func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    public var bytesWritten: Int { lock.lock(); defer { lock.unlock() }; return written }
    public var isComplete: Bool { lock.lock(); defer { lock.unlock() }; return complete }
    public var failure: String? { lock.lock(); defer { lock.unlock() }; return failed }

    public func bytes(at offset: Int, count: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard offset < written, let reader else { return Data() }
        let wanted = min(count, written - offset)
        do {
            try reader.seek(toOffset: UInt64(offset))
            return try reader.read(upToCount: wanted) ?? Data()
        } catch {
            return Data()
        }
    }

    private func fail(_ words: String) {
        lock.lock()
        if failed == nil, !complete { failed = words }
        lock.unlock()
        onFinish?(self)
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            completionHandler(.cancel)
            fail(status == 401
                 ? "deadwax says this phone isn't signed in (401). Check again, and sign in."
                 : "deadwax answered \(status) for this song.")
            return
        }
        if response.expectedContentLength > 0 { expectedLength = response.expectedContentLength }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, failed == nil else { return }
        do {
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: data)
            written += data.count
        } catch {
            failed = "The phone couldn't write the stream to its disk: \(error.localizedDescription)"
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            session.finishTasksAndInvalidate()
            // cancelled by cancel(), or by didReceive's refusal (which said why already)
            if (error as? URLError)?.code == .cancelled, failure != nil || self.session == nil { return }
            fail("The song stopped arriving: \(error.localizedDescription)")
            return
        }
        lock.lock()
        if failed == nil {
            try? writer?.synchronize()
            complete = true
        }
        lock.unlock()
        session.finishTasksAndInvalidate()
        onFinish?(self)
    }
}
#endif
