import Foundation

/// Phase 0's name for what went wrong. Phase 0's screen (the address, Check, Sign in) reads it by this name and
/// its `words`; new code says APIFailure.
public typealias DeadwaxError = APIFailure

/// Why a request to deadwax didn't give the app what it asked for, kept whole - what the web app's api/http.ts
/// keeps of a failure (its ApiError, or fetch's own TypeError) and lib/errorWords.ts reads to say it in a
/// listener's words (`ErrorWords`).
///
/// Phase 0's DeadwaxError kept only words: a refusal's status and `detail`, with words invented when deadwax sent
/// none, and dropped deadwax's `why` (src/auth.py Explained: `detail` for anyone, `why` for whoever runs it), a
/// refusal's `kind` (People's, Change password's), `busy` and the route. All of it is here, as it came.
public enum APIFailure: Error, Sendable, Equatable {
    /// deadwax - or whatever is at the address - answered, with a status the route doesn't succeed with.
    case answered(Answer)
    /// Nothing answered: the phone off the network, the VPN down, deadwax restarting (the web's fetch TypeError).
    case offline(NoAnswer)
    /// Nothing answered in the time allowed (the web's TimeoutError).
    case timeout(NoAnswer)
    /// Anything else, in words: an answer the app couldn't read, an address that isn't one, a connection that
    /// failed in a way that isn't the network's (a TLS error, say).
    case other(String)

    /// An answer's status and route, and what deadwax said in its body.
    public struct Answer: Sendable, Equatable {
        public let status: Int
        public let method: String
        /// The route under /deadwax, with its query, as it was sent - the web's ApiError.path (`/navidrome/albums/al-1`).
        public let path: String
        /// deadwax's `detail` when it is a string - nil for FastAPI's list (see `problems`), as the web reads it.
        public let detail: String?
        /// What whoever runs deadwax needs beside `detail`, when deadwax split its answer in two.
        public let why: String?
        /// What kind of refusal a route named it (src/routes/people.py Refused, own_password's).
        public let kind: String?
        /// The body said `busy: true` (MusicBrainz shedding searches).
        public let busy: Bool
        /// FastAPI's list of `msg` for a form it refused (a 422) - Phase 0's words join them; ErrorWords never reads them.
        public let problems: [String]

        public init(status: Int, method: String, path: String, detail: String? = nil, why: String? = nil,
                    kind: String? = nil, busy: Bool = false, problems: [String] = []) {
            self.status = status
            self.method = method
            self.path = path
            self.detail = detail
            self.why = why
            self.kind = kind
            self.busy = busy
            self.problems = problems
        }

        /// The web's ApiError message when deadwax sent no words: `GET /navidrome/albums failed`.
        public var fallback: String { "\(method) \(path) failed" }
    }

    /// A request nothing answered: where it was going, and the system's own words for why.
    public struct NoAnswer: Sendable, Equatable {
        public let server: ServerAddress
        public let method: String
        /// The route under /deadwax, as `Answer.path`.
        public let path: String
        /// The system's words (URLError's description) - the web's "Load failed".
        public let reason: String

        public init(server: ServerAddress, method: String, path: String, reason: String) {
            self.server = server
            self.method = method
            self.path = path
            self.reason = reason
        }
    }
}

// MARK: reading one

extension APIFailure {
    /// The answer, when deadwax answered.
    public var answer: Answer? {
        if case .answered(let answer) = self { return answer }
        return nil
    }

    public var status: Int? { answer?.status }
    public var detail: String? { answer?.detail }
    public var why: String? { answer?.why }
    public var kind: String? { answer?.kind }
    public var busy: Bool { answer?.busy ?? false }

    /// The route under /deadwax, answered or not; nil for `.other`.
    public var path: String? {
        switch self {
        case .answered(let answer): return answer.path
        case .offline(let none), .timeout(let none): return none.path
        case .other: return nil
        }
    }

    /// deadwax said this phone's session has ended (or there is none): a 401 from any route but the sign-in's own,
    /// where a 401 is a wrong password (api/http.ts noteSignedOut).
    public var isSignedOut: Bool {
        guard let answer, answer.status == 401 else { return false }
        return !answer.path.hasPrefix("/auth/")
    }

    /// Phase 0's words, for the address screen and Check (whoever set the phone up reads them): deadwax's own
    /// words, or FastAPI's list of them, or the status; the long "Couldn't reach deadwax at ..." with what to check
    /// when nothing answered. A listener's words are `ErrorWords.of(_:)`.
    public var words: String {
        switch self {
        case .answered(let answer):
            if let detail = answer.detail, !detail.isEmpty { return detail }
            if !answer.problems.isEmpty { return answer.problems.joined(separator: " ") }
            return "deadwax answered \(answer.status) and said nothing more."
        case .offline(let none), .timeout(let none):
            return unreachableWords(none.server, reason: none.reason)
        case .other(let words):
            return words
        }
    }

    // Phase 0's two other names, kept so its screen reads as it did: both are words.

    /// What was typed isn't an address (ServerAddress.parse).
    public static func badAddress(_ words: String) -> APIFailure { .other(words) }
    /// deadwax answered with something the app couldn't read.
    public static func unreadable(_ words: String) -> APIFailure { .other(words) }
}

extension APIFailure: LocalizedError {
    public var errorDescription: String? { words }
}

// MARK: making one

extension APIFailure {
    /// `response`, a status its route doesn't succeed with, read as api/http.ts reads one: `detail` when a string,
    /// `why` and `kind` when strings, `busy` only when exactly `true`; a body that isn't JSON says nothing.
    public static func answered(_ response: HTTPResponse, to request: HTTPRequest) -> APIFailure {
        let body = (try? JSONDecoder().decode(ErrorBody.self, from: response.body)) ?? ErrorBody()
        return .answered(Answer(status: response.status, method: request.method, path: route(of: request.url),
                                detail: body.detail, why: body.why, kind: body.kind, busy: body.busy,
                                problems: body.problems))
    }

    /// A transport's error, said as what it means: no network (offline), no answer in time (timeout), or anything
    /// else (`other`, in Phase 0's words for an address that didn't answer, the system's reason in them).
    /// A cancellation is no failure: check `isCancellation` first.
    public static func noAnswer(_ error: any Error, to request: HTTPRequest, server: ServerAddress) -> APIFailure {
        if let failure = error as? APIFailure { return failure }
        let reason = (error as? URLError)?.localizedDescription ?? error.localizedDescription
        let none = NoAnswer(server: server, method: request.method, path: route(of: request.url), reason: reason)
        guard let code = (error as? URLError)?.code else { return .other(unreachableWords(server, reason: reason)) }
        if code == .timedOut { return .timeout(none) }
        if isOffline(code) { return .offline(none) }
        return .other(unreachableWords(server, reason: reason))
    }

    /// The task was cancelled (Swift's own, or URLSession's) - a page left before its answer, never a failure.
    public static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    /// What URLSession says when the phone can't get to the network or the server at all.
    static func isOffline(_ code: URLError.Code) -> Bool {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
            .dataNotAllowed, .internationalRoamingOff,
        ]
        return codes.contains(code)
    }

    /// A URL's route under /deadwax, percent-encoded as sent, with its query.
    public static func route(of url: URL) -> String {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = parts?.percentEncodedPath ?? url.path
        if path == "/deadwax" {
            path = ""
        } else if path.hasPrefix("/deadwax/") {
            path.removeFirst("/deadwax".count)
        }
        if let query = parts?.percentEncodedQuery, !query.isEmpty { path += "?" + query }
        return path
    }
}

/// deadwax's error body, every field read on its own: one of another type is left out, never the whole body.
private struct ErrorBody: Decodable {
    var detail: String?
    var problems: [String] = []
    var why: String?
    var kind: String?
    var busy = false

    init() {}

    private enum Keys: String, CodingKey { case detail, why, kind, busy }
    private struct Problem: Decodable { let msg: String? }

    init(from decoder: any Decoder) throws {
        let body = try decoder.container(keyedBy: Keys.self)
        if let words = try? body.decodeIfPresent(String.self, forKey: .detail) {
            detail = words
        } else if let list = try? body.decodeIfPresent([Problem].self, forKey: .detail) {
            problems = list.compactMap(\.msg)
        }
        why = (try? body.decodeIfPresent(String.self, forKey: .why)) ?? nil
        kind = (try? body.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        busy = ((try? body.decodeIfPresent(Bool.self, forKey: .busy)) ?? nil) == true
    }
}
