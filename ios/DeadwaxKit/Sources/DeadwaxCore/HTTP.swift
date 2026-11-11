import Foundation

/// A request as the core builds it. Not URLRequest: on Linux that lives in FoundationNetworking, and
/// the core never needs a network - the app's URLSession transport turns this into a URLRequest, and
/// the tests answer it with a fake.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// Seconds to wait for an answer, when the route needs other than the transport's own (album_index's 30 -
    /// `Routes.timeouts`); nil for the transport's.
    public var timeout: Double?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: Double? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// An answer. Header names are kept lowercased, so `header("Set-Cookie")` finds `set-cookie`.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        var lowered: [String: String] = [:]
        for (name, value) in headers { lowered[name.lowercased()] = value }
        self.headers = lowered
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// How requests reach deadwax. The app's is URLSession with cookies handled by hand (no
/// HTTPCookieStorage: the session is kept in the Keychain and sent as `Cookie:`, so a background
/// download, which runs outside the app, can send it too). A transport throws only when nothing
/// answered; any HTTP status is an answer - a 304 included, passed on as it came (never answered from a
/// cache of the transport's own), so `DeadwaxClient.fetch` can say "unchanged".
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// FastAPI's error body is `{"detail": "..."}`, or for a refused form a list of `{msg}`. deadwax's own
/// words are shown as they are; anything else falls back to the status. Phase 0's words (APIFailure.words reads
/// the same); a listener's are ErrorWords'.
public func detailWords(_ body: Data, status: Int) -> String {
    if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let list = object["detail"] as? [[String: Any]] {
            let messages = list.compactMap { $0["msg"] as? String }
            if !messages.isEmpty { return messages.joined(separator: " ") }
        }
    }
    return "deadwax answered \(status) and said nothing more."
}

/// The words for an address that didn't answer, with the two things that cause it on a phone.
public func unreachableWords(_ address: ServerAddress, reason: String?) -> String {
    var words = "Couldn't reach deadwax at \(address)."
    if let reason, !reason.isEmpty { words += " (\(reason))" }
    words += " Is the phone on your home Wi-Fi, or on WireGuard? If you said no when asked about the local"
    words += " network, turn deadwax on in Settings > Privacy & Security > Local Network."
    return words
}
