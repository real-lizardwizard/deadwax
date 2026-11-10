import DeadwaxCore
import Foundation

/// The core's HTTPTransport over URLSession, with cookies off: deadwax's session is kept in the
/// Keychain and sent by DeadwaxClient as `Cookie:`, so HTTPCookieStorage never holds or sends one.
///
/// No cache of its own either (`urlCache` nil): a request sent with If-None-Match gets deadwax's 304 back as it
/// came, for DeadwaxClient.fetch to say "unchanged" - the app keeps the answers worth keeping itself.
///
/// One URLSession per time to answer: 8 seconds for every route but the few `Routes.timeouts` gives longer (the
/// album index, 30). The request's own timeoutInterval says the same, so whichever of the two URLSession heeds,
/// the route gets its time.
final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    static let standardTimeout: Double = 8

    private let lock = NSLock()
    private var sessions: [Double: URLSession] = [:]

    init() {}

    private func session(waiting timeout: Double) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session = sessions[timeout] { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration)
        sessions[timeout] = session
        return session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let timeout = request.timeout ?? Self.standardTimeout
        var sent = URLRequest(request)
        sent.timeoutInterval = timeout
        let (data, response) = try await session(waiting: timeout).data(for: sent)
        guard let http = response as? HTTPURLResponse else {
            throw APIFailure.other("The answer wasn't http.")
        }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        if let cookie = http.value(forHTTPHeaderField: "Set-Cookie") { headers["Set-Cookie"] = cookie }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
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
