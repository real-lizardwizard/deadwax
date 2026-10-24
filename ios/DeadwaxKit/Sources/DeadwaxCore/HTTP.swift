import Foundation

/// A request as the core builds it. Not URLRequest: on Linux that lives in FoundationNetworking, and
/// the core never needs a network - the app's URLSession transport turns this into a URLRequest, and
/// the tests answer it with a fake.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
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
/// answered; any HTTP status is an answer.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Why something didn't work, with the words the app shows.
public enum DeadwaxError: Error, Sendable, Equatable {
    /// What was typed isn't an address.
    case badAddress(String)
    /// Nothing answered at the address.
    case unreachable(String)
    /// deadwax said 401: logins are on and this phone isn't signed in (or its session ended).
    case signedOut(String)
    /// deadwax answered, and refused: its status and its own words (`detail`).
    case refused(status: Int, detail: String)
    /// deadwax answered with something the app couldn't read.
    case unreadable(String)

    public var words: String {
        switch self {
        case .badAddress(let words), .unreachable(let words), .signedOut(let words), .unreadable(let words):
            return words
        case .refused(_, let detail):
            return detail
        }
    }
}

/// FastAPI's error body is `{"detail": "..."}`, or for a refused form a list of `{msg}`. deadwax's own
/// words are shown as they are; anything else falls back to the status.
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
