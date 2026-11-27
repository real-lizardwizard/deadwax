import DeadwaxCore
import Foundation

/// The core's HTTPTransport over URLSession, with cookies off: deadwax's session is kept in the
/// Keychain and sent by DeadwaxClient as `Cookie:`, so HTTPCookieStorage never holds or sends one.
///
/// No cache of its own either (`urlCache` nil): a request sent with If-None-Match gets deadwax's 304 back as it
/// came, for DeadwaxClient.fetch to say "unchanged" - the app keeps the answers worth keeping itself.
///
/// (Speed A, fix 1 - notes/ios.md "Speed A: what's asked again") Covers - a request Core's CoverDisk takes: Navidrome's
/// and the Cover Art Archive's fronts, never the viewer's full size nor a download's - go through a session of their
/// own (its own connections), as uncached as every other, and are kept on disk BY HAND (`cover`): looked up and stored
/// in `coverCache` under CoverDisk.key, the address alone, so no request header - deadwax's session above all - is ever
/// written beside one. URLSession itself never stores anything (after review: URLCache storing on its own keeps each
/// request with its headers). Drawn from disk while CoverDisk.ask says it stands (its max-age, a day at most), else
/// asked again with its validators - a 304 is the copy kept. A cover the disk answered without asking is not deadwax
/// answering: Reachability hears of a cover only when deadwax was asked.
///
/// One URLSession per time to answer: 8 seconds for every route but the few `Routes.timeouts` gives longer (the
/// album index, 30). The request's own timeoutInterval says the same, so whichever of the two URLSession heeds,
/// the route gets its time.
final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    static let standardTimeout: Double = 8

    /// (Speed A) The covers' cache on disk, in the app's Caches - nil only with no Caches to put it in (the covers are
    /// then kept in memory alone, as before). Only `cover` stores in it, and only under CoverDisk.key. The first
    /// build's folder, where URLCache stored on its own, requests' headers and all, is removed as this one is made.
    static let coverCache: URLCache? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent(CoverDisk.oldFolder, isDirectory: true))
        let folder = caches.appendingPathComponent(CoverDisk.folder, isDirectory: true)
        return URLCache(memoryCapacity: 0, diskCapacity: CoverDisk.diskBytes, directory: folder)
    }()

    /// The request a cover is kept and looked up under (CoverDisk.key): its address alone, no header.
    static func coverKey(_ request: HTTPRequest) -> URLRequest {
        URLRequest(CoverDisk.key(request))
    }

    /// A session's kind: its time to answer, and whether it is the covers' (their own connections) or every other route's.
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

    /// (Speed A) The covers' session is a URLSession of its own - its own connections, so a page's JSON never holds a
    /// cover back - made from the same configuration as every other: ephemeral, no cache. `cover` keeps them on disk.
    private func session(waiting timeout: Double, covers: Bool = false) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        let kind = Kind(timeout: timeout, covers: covers)
        if let session = sessions[kind] { return session }
        let session = URLSession(configuration: Self.configuration(waiting: timeout), delegate: SameOriginRedirects.shared,
                                 delegateQueue: nil)
        sessions[kind] = session
        return session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let timeout = request.timeout ?? Self.standardTimeout
        var sent = URLRequest(request)
        sent.timeoutInterval = timeout
        let data: Data
        let response: URLResponse
        // (Speed A) whether deadwax answered: always - but a cover the disk answered without asking
        var answered = true
        do {
            if let most = request.mostBytes {
                (data, response) = try await CappedRead.read(sent, most: most,
                                                             configuration: Self.configuration(waiting: timeout))
            } else if CoverDisk.takes(request), let cache = Self.coverCache {
                (data, response, answered) = try await cover(request, sent: sent, cache: cache, timeout: timeout)
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

    /// (Speed A, after review) A cover, kept on disk by hand: the copy under CoverDisk.key drawn while it stands (nothing
    /// asked - not deadwax answering), else deadwax asked - with the copy's validators, a 304 being the copy kept again
    /// - and a 200 kept in its place, only CoverDisk.kept's headers and never the request: the key has none. An answer
    /// that may not be kept (no-store, not a 200) takes the copy away.
    private func cover(_ request: HTTPRequest, sent: URLRequest, cache: URLCache,
                       timeout: Double) async throws -> (Data, URLResponse, Bool) {
        let key = Self.coverKey(request)
        let held = cache.cachedResponse(for: key)
        let heldHeaders = (held?.response as? HTTPURLResponse).map(Self.headers)
        var asked = sent
        var revalidating = false
        switch CoverDisk.ask(held: heldHeaders, now: Date().timeIntervalSince1970) {
        case .kept:
            if let held { return (held.data, held.response, false) }
        case .revalidate(let validators):
            for (name, value) in validators { asked.setValue(value, forHTTPHeaderField: name) }
            revalidating = true
        case .fetch:
            break
        }
        let (data, response) = try await session(waiting: timeout, covers: true).data(for: asked)
        guard let http = response as? HTTPURLResponse else { return (data, response, true) }
        let now = Date().timeIntervalSince1970
        if http.statusCode == 304, revalidating, let held, let heldHeaders {
            if let again = CoverDisk.revalidated(heldHeaders, by: Self.headers(http), now: now) {
                Self.store(held.data, headers: again, under: key, in: cache)
            } else {
                cache.removeCachedResponse(for: key)
            }
            return (held.data, held.response, true)
        }
        if let kept = CoverDisk.kept(status: http.statusCode, headers: Self.headers(http), now: now) {
            Self.store(data, headers: kept, under: key, in: cache)
        } else if held != nil {
            cache.removeCachedResponse(for: key)
        }
        return (data, response, true)
    }

    /// A cover written to disk: a 200 with `headers` alone (CoverDisk.kept's), under `key` (CoverDisk.key's, no header).
    private static func store(_ data: Data, headers: [String: String], under key: URLRequest, in cache: URLCache) {
        guard let url = key.url,
              let answer = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return
        }
        cache.storeCachedResponse(CachedURLResponse(response: answer, data: data, storagePolicy: .allowed), for: key)
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
