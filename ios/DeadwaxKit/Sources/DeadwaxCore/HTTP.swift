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
    /// The most of an answer's body to read (bytes), when the route needs a limit (the cover viewer's full size,
    /// `CoverZoom.fullMostBytes`); past it the transport calls the request off and throws `HTTPTooLarge`. nil: all of it.
    public var mostBytes: Int?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: Double? = nil,
                mostBytes: Int? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.mostBytes = mostBytes
    }
}

/// An answer past its request's `mostBytes`, called off before more of it was read: deadwax answered, with too much.
public struct HTTPTooLarge: Error, Sendable, Equatable {
    /// The request's most, in bytes.
    public let most: Int

    public init(most: Int) {
        self.most = most
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

/// An answer read as it comes (Phase 8, slice 9 - the event log's stream): its status and headers at once, then its
/// body's lines (EventStream.Lines: LF, CR or CRLF, blank lines kept) as they arrive, until it ends, fails, or the task
/// reading them is cancelled - which calls the request off. An answer other than 200 has its body whole in `response`
/// (to say why) and no lines.
public struct HTTPLines: Sendable {
    public let response: HTTPResponse
    public let lines: AsyncThrowingStream<String, any Error>

    public init(response: HTTPResponse, lines: AsyncThrowingStream<String, any Error>) {
        self.response = response
        self.lines = lines
    }
}

/// A transport that can read an answer as it comes. The app's is URLSession's `bytes(for:)`, its cookie sent by hand as
/// every request's is; the request's `timeout` is the most the answer may say nothing - between any two bytes - never a
/// limit over all.
public protocol HTTPLineTransport: HTTPTransport {
    func lines(for request: HTTPRequest) async throws -> HTTPLines
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

/// The words for an address that didn't answer, with the two things that cause it on `device`: not on the network
/// (a Mac may be on a cable, so its is the home network), and Local Network refused - in the iPhone's Settings, or the
/// Mac's System Settings (notes/ios.md "The Mac app, slice 4: the Mac's words"). The Mac's asking began with macOS 15
/// (Apple's TN3179), and the app opens from macOS 14, where nothing asks: its words say so rather than check.
public func unreachableWords(_ address: ServerAddress, reason: String?, device: Device) -> String {
    var words = "Couldn't reach deadwax at \(address)."
    if let reason, !reason.isEmpty { words += " (\(reason))" }
    switch device {
    case .iPhone:
        words += " Is the phone on your home Wi-Fi, or on WireGuard? If you said no when asked about the local"
        words += " network, turn deadwax on in the iPhone's Settings > Privacy & Security > Local Network."
    case .mac:
        words += " Is the Mac on your home network, or on WireGuard? On macOS 15 or later, if you said no when asked"
        words += " about the local network, turn deadwax on in System Settings > Privacy & Security > Local Network."
    }
    return words
}
