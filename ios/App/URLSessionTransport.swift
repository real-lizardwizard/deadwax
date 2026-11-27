import DeadwaxCore
import Foundation

/// The core's HTTPTransport over URLSession, with cookies off: deadwax's session is kept in the
/// Keychain and sent by DeadwaxClient as `Cookie:`, so HTTPCookieStorage never holds or sends one.
///
/// No cache of its own either (`urlCache` nil): a request sent with If-None-Match gets deadwax's 304 back as it
/// came, for DeadwaxClient.fetch to say "unchanged" - the app keeps the answers worth keeping itself.
///
/// (Speed A, fix 1 - notes/ios.md "Speed A: what's asked again") Except covers: a request Core's CoverDisk takes
/// (Navidrome's covers and the Cover Art Archive's fronts, never the viewer's full size) goes through a session of its
/// own whose cache is on disk - Caches/deadwax-covers, CoverDisk.diskBytes at most - kept and asked again as deadwax's
/// headers say (Cache-Control's max-age, then revalidated with the ETag the cache holds). The JSON and the audio stay
/// exactly as they were: ephemeral and uncached. A cover the cache answered without asking is not deadwax answering:
/// Reachability hears of a cover only when it came over the network (`NetworkUsed`).
///
/// One URLSession per time to answer: 8 seconds for every route but the few `Routes.timeouts` gives longer (the
/// album index, 30). The request's own timeoutInterval says the same, so whichever of the two URLSession heeds,
/// the route gets its time.
final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    static let standardTimeout: Double = 8

    /// (Speed A) The covers' cache on disk, in the app's Caches - nil only with no Caches to put it in (the covers are
    /// then kept in memory alone, as before).
    static let coverCache: URLCache? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent(CoverDisk.folder, isDirectory: true)
        return URLCache(memoryCapacity: 0, diskCapacity: CoverDisk.diskBytes, directory: folder)
    }()

    /// A session's kind: its time to answer, and whether it is the covers' (kept on disk) or every other route's.
    private struct Kind: Hashable {
        let timeout: Double
        let covers: Bool
    }

    private let lock = NSLock()
    private var sessions: [Kind: URLSession] = [:]
    private var listener: (@Sendable (_ answered: Bool) -> Void)?

    init() {}

    /// `listener` hears every request's end: deadwax answered (any status), or nothing did - not a request called off
    /// (Reachability, phase2-downloads.md 7.1).
    func listen(_ listener: @escaping @Sendable (_ answered: Bool) -> Void) {
        lock.withLock { self.listener = listener }
    }

    private func heard(_ answered: Bool) {
        lock.withLock { listener }?(answered)
    }

    private static func configuration(waiting timeout: Double) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        return configuration
    }

    /// (Speed A) The covers' session: cookies off as every other's, its cache the one on disk, used as each answer's
    /// headers say (`.useProtocolCachePolicy`: fresh within max-age, else asked again with the ETag held - a 304 is the
    /// cover kept). Not ephemeral: an ephemeral session keeps nothing on disk.
    private static func coverConfiguration(waiting timeout: Double) -> URLSessionConfiguration {
        guard let cache = coverCache else { return configuration(waiting: timeout) }
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = cache
        configuration.timeoutIntervalForRequest = timeout
        return configuration
    }

    private func session(waiting timeout: Double, covers: Bool = false) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        let kind = Kind(timeout: timeout, covers: covers)
        if let session = sessions[kind] { return session }
        let configuration = covers ? Self.coverConfiguration(waiting: timeout) : Self.configuration(waiting: timeout)
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects.shared, delegateQueue: nil)
        sessions[kind] = session
        return session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let timeout = request.timeout ?? Self.standardTimeout
        var sent = URLRequest(request)
        sent.timeoutInterval = timeout
        let data: Data
        let response: URLResponse
        // (Speed A) whether deadwax answered: always - but a cover the disk cache answered without asking
        var answered = true
        do {
            if let most = request.mostBytes {
                (data, response) = try await CappedRead.read(sent, most: most,
                                                             configuration: Self.configuration(waiting: timeout))
            } else if CoverDisk.takes(request) {
                let used = NetworkUsed()
                (data, response) = try await session(waiting: timeout, covers: true).data(for: sent, delegate: used)
                answered = used.overNetwork
            } else {
                (data, response) = try await session(waiting: timeout).data(for: sent)
            }
        } catch let error as URLError where error.code != .cancelled {
            heard(false)
            throw error
        } catch let error as HTTPTooLarge {
            // deadwax answered, with more than the request reads
            heard(true)
            throw error
        }
        if answered { heard(true) }
        guard let http = response as? HTTPURLResponse else {
            throw APIFailure.other("The answer wasn't http.")
        }
        return HTTPResponse(status: http.statusCode, headers: Self.headers(http), body: data)
    }

    private static func headers(_ http: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        if let cookie = http.value(forHTTPHeaderField: "Set-Cookie") { headers["Set-Cookie"] = cookie }
        return headers
    }

    // MARK: an answer read as it comes (the event log's stream)

    /// The most of a refusal's body read, to say why: deadwax's are a line of JSON.
    private static let refusalMost = 64 * 1024

    /// Streams' own URLSession - a stream holds its connection for as long as it's open, so it never takes one of the
    /// other requests' - made once, cookies off and no cache as theirs are. Its wait is the most a stream may say
    /// nothing between two bytes (EventStream.silence, the request's own). Its wait over all is URLSession's own default,
    /// a week, left as it is: the stream is held only while the page shows with the app in front, so it never comes near
    /// it (and an infinite one is a value CFNetwork may not take as meant).
    private var streams: URLSession?

    private func streamSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let streams { return streams }
        let configuration = Self.configuration(waiting: EventStream.silence)
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects.shared, delegateQueue: nil)
        streams = session
        return session
    }
}

extension URLSessionTransport: HTTPLineTransport {
    /// The answer read as it comes (`URLSession.bytes(for:)`): its status and headers once they arrive, then its body as
    /// lines (EventStream.Lines) until it ends, fails, or whoever reads it stops - which calls the request off. The
    /// session's cookie goes as every request's does, set by DeadwaxClient as `Cookie:` (HTTPCookieStorage is off). A
    /// stream that says nothing for the request's wait fails as a timeout. An answer other than 200 is read, up to 64 KB,
    /// to say why, with no lines.
    func lines(for request: HTTPRequest) async throws -> HTTPLines {
        var sent = URLRequest(request)
        sent.timeoutInterval = request.timeout ?? EventStream.silence
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await streamSession().bytes(for: sent)
        } catch let error as URLError where error.code != .cancelled {
            heard(false)
            throw error
        }
        heard(true)
        let task = bytes.task
        guard let http = response as? HTTPURLResponse else {
            task.cancel()
            throw APIFailure.other("The answer wasn't http.")
        }
        let headers = Self.headers(http)
        guard http.statusCode == 200 else {
            var body = Data()
            do {
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= Self.refusalMost { break }
                }
            } catch {
                // what came of it says enough, or nothing - the status is the answer
            }
            task.cancel()
            let none = AsyncThrowingStream<String, any Error> { $0.finish() }
            return HTTPLines(response: HTTPResponse(status: http.statusCode, headers: headers, body: body), lines: none)
        }
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let reading = Task { [weak self] in
                var splitter = EventStream.Lines()
                do {
                    for try await byte in bytes {
                        if let line = splitter.feed(byte) { continuation.yield(line) }
                    }
                    continuation.finish()
                } catch {
                    // the connection gone (not called off): deadwax out of reach, as any request failing says
                    if let failure = error as? URLError, failure.code != .cancelled { self?.heard(false) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reading.cancel()
                task.cancel()
            }
        }
        return HTTPLines(response: HTTPResponse(status: http.statusCode, headers: headers), lines: lines)
    }
}

extension URLRequest {
    init(_ request: HTTPRequest) {
        self.init(url: request.url)
        httpMethod = request.method
        for (name, value) in request.headers { setValue(value, forHTTPHeaderField: name) }
        httpBody = request.body
        if let timeout = request.timeout { timeoutInterval = timeout }
    }
}

/// (Phase 8, slice 10's review) The app's sessions follow a redirect only within the address they asked - the same scheme,
/// host and port (Core's Redirects.follows): every request carries deadwax's session by hand as `Cookie:`, and a sign-in
/// or Change password a password in its body, which URLSession would send on to wherever a 307 or 308 named. One
/// elsewhere is refused, and its 3xx is the answer. URLSessionTransport's sessions (every route, and the event log's
/// stream) and the reachability probe take this; a capped read and the player's StreamFetch are their own delegates and
/// ask the same rule; the downloads' background session can't be asked (DownloadSession).
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = SameOriginRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Redirects.follows(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}

/// (Speed A) A cover's task's own delegate: whether its answer came over the network (a transaction loaded from it - a
/// 304 revalidating the copy kept is one) or from the disk cache alone. URLSession hands a task its metrics before it
/// completes; metrics that never came say the cache, so a cover never tells Reachability that deadwax answered when it
/// may not have. A redirect is the session's own rule, asked here as the session's delegate would be.
private final class NetworkUsed: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var network = false

    var overNetwork: Bool { lock.withLock { network } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let loaded = metrics.transactionMetrics.contains { (each: URLSessionTaskTransactionMetrics) -> Bool in
            each.resourceFetchType == .networkLoad
        }
        lock.withLock { network = loaded }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        SameOriginRedirects.shared.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                              newRequest: request, completionHandler: completionHandler)
    }
}

/// A body read as it comes and called off past `most` bytes - at once when the answer's Content-Length says it will
/// be - so a file too big to hold is never held whole: the cover viewer's full size, past CoverZoom.fullMostBytes
/// (notes/ios.md "The cover, full screen"). Its own URLSession, for the delegate, let go as the read ends; a task
/// cancelled calls the read off too.
private final class CappedRead: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let most: Int
    private let lock = NSLock()
    private var body = Data()
    private var answer: URLResponse?
    private var over = false
    private var waiting: CheckedContinuation<(Data, URLResponse), Error>?
    /// The read's end, when it came before anything waited for it (a task cancelled before it began).
    private var ended: Result<(Data, URLResponse), Error>?

    private init(most: Int) {
        self.most = most
    }

    static func read(_ request: URLRequest, most: Int,
                     configuration: URLSessionConfiguration) async throws -> (Data, URLResponse) {
        let reader = CappedRead(most: most)
        let session = URLSession(configuration: configuration, delegate: reader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let early: Result<(Data, URLResponse), Error>? = reader.lock.withLock {
                    if let ended = reader.ended { return ended }
                    reader.waiting = continuation
                    return nil
                }
                if let early {
                    continuation.resume(with: early)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let past = response.expectedContentLength > Int64(most)
        lock.withLock {
            answer = response
            if past { over = true }
        }
        completionHandler(past ? .cancel : .allow)
    }

    /// Only within the address asked, as every session's (SameOriginRedirects).
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Redirects.follows(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let past: Bool = lock.withLock {
            guard !over else { return false }
            body.append(data)
            guard body.count > most else { return false }
            over = true
            body = Data()
            return true
        }
        if past { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, result) = lock.withLock {
            () -> (CheckedContinuation<(Data, URLResponse), Error>?, Result<(Data, URLResponse), Error>) in
            let result: Result<(Data, URLResponse), Error>
            if over {
                result = .failure(HTTPTooLarge(most: most))
            } else if let error {
                result = .failure(error)
            } else if let answer {
                result = .success((body, answer))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            let continuation = waiting
            waiting = nil
            if continuation == nil { ended = result }
            return (continuation, result)
        }
        continuation?.resume(with: result)
    }
}
