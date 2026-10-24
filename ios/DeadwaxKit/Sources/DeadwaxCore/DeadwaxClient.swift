import Foundation

/// The app's one way to deadwax: a typed function per route, each built on `Routes`. It talks only
/// to deadwax, never to Navidrome - Navidrome's answers come through deadwax's own routes.
public struct DeadwaxClient: Sendable {
    public let server: ServerAddress
    /// The `deadwax_session` value, when signed in (logins on). Sent as `Cookie:` on every request.
    public var session: String?
    let transport: any HTTPTransport

    public init(server: ServerAddress, session: String? = nil, transport: any HTTPTransport) {
        self.server = server
        self.session = session
        self.transport = transport
    }

    // MARK: building requests

    /// `endpoint`'s URL on this server, its path parameters filled in (each encoded as one path
    /// segment) and the query in the order given. Only names the endpoint declares are sent.
    public func url(_ endpoint: Endpoint, path parameters: [String: String] = [:],
                    query: [(String, String)] = []) -> URL {
        var path = endpoint.path
        for (name, value) in parameters {
            path = path.replacingOccurrences(of: "{\(name)}", with: Self.segment(value))
        }
        // from the base's own components: URL.host drops an IPv6 literal's brackets, and a host set
        // without them makes no URL at all
        var parts = URLComponents(url: server.base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.percentEncodedPath = path
        parts.percentEncodedQuery = nil
        parts.fragment = nil
        let sent = query.filter { endpoint.query.contains($0.0) }
        if !sent.isEmpty {
            parts.queryItems = sent.map { URLQueryItem(name: $0.0, value: $0.1) }
            // URLComponents leaves `+` alone, which a server reads as a space
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        // ServerAddress.parse only accepts an address a route's URL can be built on
        return parts.url ?? URL(string: server.base.absoluteString + path) ?? server.base
    }

    /// A request for `endpoint`, with the session's cookie when there is one.
    public func request(_ endpoint: Endpoint, path parameters: [String: String] = [:],
                        query: [(String, String)] = [], json body: Data? = nil) -> HTTPRequest {
        var headers = ["Accept": "application/json"]
        if let session { headers["Cookie"] = SessionCookie.header(session) }
        if body != nil { headers["Content-Type"] = "application/json" }
        return HTTPRequest(method: endpoint.method, url: url(endpoint, path: parameters, query: query),
                           headers: headers, body: body)
    }

    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: the routes

    /// Whether deadwax is there. A 503 is still deadwax answering (its poller stopped), so it is read.
    public func health() async throws -> Health {
        let response = try await send(request(Routes.health))
        if response.status == 200 || response.status == 503 {
            if let health = try? JSONDecoder().decode(Health.self, from: response.body) { return health }
            if response.status == 503 { throw failure(response) }
            if (try? JSONSerialization.jsonObject(with: response.body)) == nil {
                // an HTML page: another service on that port, or a proxy with deadwax down behind it
                throw DeadwaxError.unreadable("Something answered at \(server), but it isn't deadwax (or deadwax isn't"
                                              + " running behind it). Check the address and its port.")
            }
            return try decode(Health.self, response)
        }
        throw failure(response)
    }

    /// Who this phone is to deadwax. With logins on and no session, a `.signedOut`.
    public func me() async throws -> Me {
        let response = try await send(request(Routes.me))
        guard response.status == 200 else { throw failure(response) }
        return try decode(Me.self, response)
    }

    /// Signs in (logins on): who deadwax says this is, and the session to keep.
    public func signIn(username: String, password: String) async throws -> (me: Me, session: String) {
        let body = try JSONEncoder().encode(SignInBody(username: username, password: password))
        var unsigned = self
        unsigned.session = nil
        let response = try await send(unsigned.request(Routes.signIn, json: body))
        guard response.status == 200 else {
            // a wrong password is a 401 too, but it is words to show, not a session that ended
            throw DeadwaxError.refused(status: response.status, detail: detailWords(response.body, status: response.status))
        }
        let me = try decode(Me.self, response)
        guard let session = SessionCookie.value(fromSetCookie: response.header("Set-Cookie")) else {
            throw DeadwaxError.unreadable("deadwax said yes, but sent no session to keep.")
        }
        return (me, session)
    }

    /// Ends this phone's session on the server. Signing out of nothing is still signed out.
    public func signOut() async throws {
        let response = try await send(request(Routes.signOut, json: Data("{}".utf8)))
        guard response.status == 200 || response.status == 401 else { throw failure(response) }
    }

    /// search3 through deadwax. An empty `query` pages every song.
    public func search(_ query: String, songs: Int, songOffset: Int = 0, albums: Int = 0,
                       artists: Int = 0) async throws -> SearchResult {
        let response = try await send(request(Routes.search, query: [
            ("q", query), ("artistCount", String(artists)), ("albumCount", String(albums)),
            ("songCount", String(songs)), ("songOffset", String(songOffset)),
        ]))
        guard response.status == 200 else { throw failure(response) }
        return try decode(SearchResult.self, response)
    }

    /// The song's audio, as `format` says (`raw`: the file as it is - see `StreamFormat`). The app's
    /// own URLSession fetches it, so this is a request rather than a call.
    public func streamRequest(songID: String, format: String) -> HTTPRequest {
        var built = request(Routes.stream, path: ["song_id": songID], query: [("format", format)])
        built.headers["Accept"] = "*/*"
        return built
    }

    /// A cover at `size` pixels (the lock screen's).
    public func coverRequest(coverID: String, size: Int) -> HTTPRequest {
        var built = request(Routes.cover, path: ["cover_id": coverID], query: [("size", String(size))])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// Fetches a cover's bytes.
    public func cover(coverID: String, size: Int) async throws -> Data {
        let response = try await send(coverRequest(coverID: coverID, size: size))
        guard response.status == 200 else { throw failure(response) }
        return response.body
    }

    // MARK: answers

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as DeadwaxError {
            throw error
        } catch {
            throw DeadwaxError.unreachable(unreachableWords(server, reason: error.localizedDescription))
        }
    }

    func failure(_ response: HTTPResponse) -> DeadwaxError {
        let words = detailWords(response.body, status: response.status)
        if response.status == 401 { return .signedOut(words) }
        return .refused(status: response.status, detail: words)
    }

    func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw DeadwaxError.unreadable("deadwax's answer couldn't be read (\(type)\(Self.what(error))). Is the app"
                                          + " older or newer than the server?")
        }
    }

    /// What a decode tripped on, in a few words rather than DecodingError's dump.
    static func what(_ error: Error) -> String {
        func at(_ path: [any CodingKey]) -> String { path.map(\.stringValue).joined(separator: ".") }
        switch error as? DecodingError {
        case .keyNotFound(let key, let context)?:
            let field = at(context.codingPath + [key])
            return ": no \(field)"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            return context.codingPath.isEmpty ? "" : ": \(at(context.codingPath)) isn't what it should be"
        case .dataCorrupted?:
            return ": not JSON"
        default:
            return ""
        }
    }
}
