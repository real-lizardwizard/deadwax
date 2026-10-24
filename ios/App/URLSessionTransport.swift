import DeadwaxCore
import Foundation

/// The core's HTTPTransport over URLSession, with cookies off: deadwax's session is kept in the
/// Keychain and sent by DeadwaxClient as `Cookie:`, so HTTPCookieStorage never holds or sends one.
final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: URLRequest(request))
        guard let http = response as? HTTPURLResponse else {
            throw DeadwaxError.unreadable("The answer wasn't http.")
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
    }
}
