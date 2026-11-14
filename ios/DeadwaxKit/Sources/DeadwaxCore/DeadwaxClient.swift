import Foundation

/// The app's one way to deadwax: a typed function per route, each built on `Routes`, and a generic `call` (and
/// `fetch`, for a route answered with an ETag) for a model declared elsewhere. It talks only to deadwax, never to
/// Navidrome - Navidrome's answers come through deadwax's own routes.
///
/// Every failure is an `APIFailure`, kept whole - status, route, deadwax's `detail`, `why`, `kind` and `busy`, or
/// that nothing answered (offline) or not in time (timeout) - for `ErrorWords` to say in a listener's words. A task
/// cancelled while it waited is a CancellationError, never a failure.
public struct DeadwaxClient: Sendable {
    public let server: ServerAddress
    /// The `deadwax_session` value, when signed in (logins on). Sent as `Cookie:` on every request.
    public var session: String?
    let transport: any HTTPTransport
    /// Told when deadwax says this phone's session has ended - a 401 from any route but the sign-in's own
    /// (api/http.ts noteSignedOut) - with the session the request went out under: one sent under a session a
    /// sign-in has since replaced says nothing about the new one.
    public var onSignedOut: (@Sendable (_ failure: APIFailure, _ sentUnder: String?) -> Void)?

    public init(server: ServerAddress, session: String? = nil, transport: any HTTPTransport,
                onSignedOut: (@Sendable (_ failure: APIFailure, _ sentUnder: String?) -> Void)? = nil) {
        self.server = server
        self.session = session
        self.transport = transport
        self.onSignedOut = onSignedOut
    }

    /// An answer that may be "what you have is still current": a 304 to a request sent with the ETag of the last
    /// answer kept (If-None-Match).
    public enum Fetched<Value: Sendable>: Sendable {
        /// A new answer, with its ETag to send next time (nil when deadwax sent none).
        case fresh(Value, etag: String?)
        /// The answer kept is still the answer.
        case unchanged
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

    /// A request for `endpoint`, with the session's cookie when there is one, and the route's own time to answer
    /// when it has one (`Routes.timeouts`).
    public func request(_ endpoint: Endpoint, path parameters: [String: String] = [:],
                        query: [(String, String)] = [], json body: Data? = nil) -> HTTPRequest {
        var headers = ["Accept": "application/json"]
        if let session { headers["Cookie"] = SessionCookie.header(session) }
        if body != nil { headers["Content-Type"] = "application/json" }
        return HTTPRequest(method: endpoint.method, url: url(endpoint, path: parameters, query: query),
                           headers: headers, body: body, timeout: Routes.timeouts[endpoint])
    }

    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: calling any route

    /// `request`'s answer when its status is one of `accept`; any other is thrown as the APIFailure it is.
    public func answer(_ request: HTTPRequest, accept: Set<Int> = [200]) async throws -> HTTPResponse {
        let response = try await send(request)
        guard accept.contains(response.status) else { throw failure(response, to: request) }
        return response
    }

    /// Calls `endpoint` and reads its answer as `Value` - the one call every typed one below is, for a model
    /// declared anywhere.
    public func call<Value: Decodable>(_ endpoint: Endpoint, as type: Value.Type = Value.self,
                                       path parameters: [String: String] = [:], query: [(String, String)] = [],
                                       json body: Data? = nil, accept: Set<Int> = [200]) async throws -> Value {
        let response = try await answer(request(endpoint, path: parameters, query: query, json: body), accept: accept)
        return try decode(type, response)
    }

    /// `call`, sending `body` as JSON.
    public func call<Value: Decodable, Body: Encodable>(_ endpoint: Endpoint, as type: Value.Type = Value.self,
                                                        path parameters: [String: String] = [:],
                                                        query: [(String, String)] = [], sending body: Body,
                                                        accept: Set<Int> = [200]) async throws -> Value {
        let json: Data
        do {
            json = try JSONEncoder().encode(body)
        } catch {
            throw APIFailure.other("The app couldn't write what it meant to send (\(Body.self)).")
        }
        return try await call(endpoint, as: type, path: parameters, query: query, json: json, accept: accept)
    }

    /// Calls `endpoint` with the ETag of the answer kept (`ifNoneMatch`, nil for none): `.unchanged` when deadwax
    /// says it is still the answer (a 304), else the new one and its ETag.
    public func fetch<Value: Decodable & Sendable>(_ endpoint: Endpoint, as type: Value.Type = Value.self,
                                                   path parameters: [String: String] = [:],
                                                   query: [(String, String)] = [],
                                                   ifNoneMatch etag: String?) async throws -> Fetched<Value> {
        var built = request(endpoint, path: parameters, query: query)
        if let etag, !etag.isEmpty { built.headers["If-None-Match"] = etag }
        let response = try await answer(built, accept: built.headers["If-None-Match"] == nil ? [200] : [200, 304])
        if response.status == 304 { return .unchanged }
        return .fresh(try decode(type, response), etag: response.header("ETag"))
    }

    // MARK: Phase 0's routes

    /// Whether deadwax is there. A 503 is still deadwax answering (its poller stopped), so it is read.
    public func health() async throws -> Health {
        let sent = request(Routes.health)
        let response = try await send(sent)
        if response.status == 200 || response.status == 503 {
            if let health = try? JSONDecoder().decode(Health.self, from: response.body) { return health }
            if response.status == 503 { throw failure(response, to: sent) }
            if (try? JSONSerialization.jsonObject(with: response.body)) == nil {
                // an HTML page: another service on that port, or a proxy with deadwax down behind it
                throw APIFailure.other("Something answered at \(server), but it isn't deadwax (or deadwax isn't"
                                       + " running behind it). Check the address and its port.")
            }
            return try decode(Health.self, response)
        }
        throw failure(response, to: sent)
    }

    /// Who this phone is to deadwax. With logins on and no session, a 401 (`isSignedOut`).
    public func me() async throws -> Me {
        try await call(Routes.me)
    }

    /// Signs in (logins on): who deadwax says this is, and the session to keep. A refusal - a wrong password is a
    /// 401 here, words to show rather than a session that ended - is the answer as it came (`ErrorWords.signInProblem`).
    public func signIn(username: String, password: String) async throws -> (me: Me, session: String) {
        let body = try JSONEncoder().encode(SignInBody(username: username, password: password))
        var unsigned = self
        unsigned.session = nil
        let response = try await unsigned.answer(unsigned.request(Routes.signIn, json: body))
        let me = try decode(Me.self, response)
        guard let session = SessionCookie.value(fromSetCookie: response.header("Set-Cookie")) else {
            throw APIFailure.other("deadwax said yes, but sent no session to keep.")
        }
        return (me, session)
    }

    /// Ends this phone's session on the server. Signing out of nothing is still signed out, and any answer at all
    /// means the phone can forget its session: only nothing answering is thrown.
    public func signOut() async throws {
        _ = try await send(request(Routes.signOut, json: Data("{}".utf8)))
    }

    /// search3 through deadwax. An empty `query` pages every song.
    public func search(_ query: String, songs: Int, songOffset: Int = 0, albums: Int = 0,
                       artists: Int = 0) async throws -> SearchResult {
        try await call(Routes.search, query: [
            ("q", query), ("artistCount", String(artists)), ("albumCount", String(albums)),
            ("songCount", String(songs)), ("songOffset", String(songOffset)),
        ])
    }

    /// The song's audio, as `format` says (`raw`: the file as it is - see `StreamFormat`). The app's
    /// own URLSession fetches it, so this is a request rather than a call.
    public func streamRequest(songID: String, format: String) -> HTTPRequest {
        var built = request(Routes.stream, path: ["song_id": songID], query: [("format", format)])
        built.headers["Accept"] = "*/*"
        return built
    }

    /// A cover at `size` pixels (`CoverSize`).
    public func coverRequest(coverID: String, size: Int) -> HTTPRequest {
        var built = request(Routes.cover, path: ["cover_id": coverID], query: [("size", String(size))])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// Fetches a cover's bytes.
    public func cover(coverID: String, size: Int) async throws -> Data {
        try await answer(coverRequest(coverID: coverID, size: size)).body
    }

    /// A cover's bytes, or `.unchanged` when the copy kept (its ETag `ifNoneMatch`) is still the cover - deadwax
    /// passes Navidrome's revalidation on as a 304 with no body.
    public func cover(coverID: String, size: Int, ifNoneMatch etag: String?) async throws -> Fetched<Data> {
        var built = coverRequest(coverID: coverID, size: size)
        if let etag, !etag.isEmpty { built.headers["If-None-Match"] = etag }
        let response = try await answer(built, accept: built.headers["If-None-Match"] == nil ? [200] : [200, 304])
        if response.status == 304 { return .unchanged }
        return .fresh(response.body, etag: response.header("ETag"))
    }

    /// The CD art for a disc of an album (turntable.md 2.3: `TurntableGeometry.playingDisc`'s disc).
    public func discArtRequest(albumID: String, disc: Int) -> HTTPRequest {
        var built = request(Routes.discArt, query: [("album", albumID), ("disc", String(max(disc, 1)))])
        built.headers["Accept"] = "image/*"
        return built
    }

    /// A disc's CD art, or nil when the album has none (deadwax's 404) - the plain record with the cover as its label.
    public func discArt(albumID: String, disc: Int) async throws -> Data? {
        let response = try await answer(discArtRequest(albumID: albumID, disc: disc), accept: [200, 404])
        return response.status == 404 ? nil : response.body
    }

    // MARK: Phase 1's routes

    /// One album with its songs; nil when Navidrome has none by that id (deadwax answers `{}`). A 404 is thrown,
    /// for `ErrorWords`' gone sentence.
    public func album(id: String) async throws -> Album? {
        try await albumAnswered(id: id).album
    }

    /// The same, with the body as deadwax sent it - an album page keeps it for an album with songs on this phone, so
    /// the copy kept is the answer, not a re-encoding of it (phase2-downloads.md 8.2).
    public func albumAnswered(id: String) async throws -> (album: Album?, body: Data) {
        let response = try await answer(request(Routes.album, path: ["album_id": id]))
        if Self.isEmptyObject(response.body) { return (nil, response.body) }
        return (try decode(Album.self, response), response.body)
    }

    /// One song as Navidrome has it now - its play count and credits; nil when Navidrome has none by that id.
    public func song(id: String) async throws -> Song? {
        let response = try await answer(request(Routes.song, path: ["song_id": id]))
        if Self.isEmptyObject(response.body) { return nil }
        return try decode(Song.self, response)
    }

    /// Tells Navidrome what is playing (`submission` false) or that it was played (true) - the second counts the
    /// play, and passes it on to Last.fm or ListenBrainz. `time`: when it was played, in milliseconds since 1970.
    public func scrobble(songID: String, submission: Bool, time: Int64? = nil) async throws {
        var query = [("submission", submission ? "true" : "false")]
        if let time { query.append(("time", String(time))) }
        _ = try await answer(request(Routes.scrobble, path: ["song_id": songID], query: query))
    }

    /// "This album is about to be played": deadwax measures its songs not yet measured, in the background. The
    /// state it said (`measuring`, `measured`, `busy`, `not_levelled`...), never waited for.
    public func warmLevels(albumID: String) async throws -> String {
        try await call(Routes.levelAlbum, as: LevelWarmed.self, path: ["album_id": albumID], accept: [200, 202])
            .state ?? ""
    }

    /// The id bridge: the album, by Navidrome's id, across the store's ids - asked only when there is a library
    /// (Access.hasLibrary).
    public func storeAlbum(navidromeID: String) async throws -> StoreAlbum {
        try await call(Routes.storeAlbum, query: [("navidrome_id", navidromeID)])
    }

    /// Add to my library: the pressing the store holds (`AddRelease.from`). A 409 in words when there is nothing
    /// to add.
    public func addToLibrary(_ release: AddRelease) async throws -> AddedToLibrary {
        try await call(Routes.libraryAdd, sending: release)
    }

    /// Remove from my library: unstarred as you, out of your library - nothing deleted.
    public func removeFromLibrary(navidromeID: String) async throws -> RemovedFromLibrary {
        try await call(Routes.libraryRemove, sending: LibraryRemoveBody(navidromeId: navidromeID))
    }

    // MARK: app 0.4's routes

    /// A song's lyrics (`Routes.lyrics`, server 2.1.5) with the body as deadwax sent it - kept with a downloaded song -
    /// or `.unchanged` when the answer kept (its ETag `ifNoneMatch`) is still the answer: deadwax sends an ETag with
    /// every answer and a 304 with no body for one unchanged. None for the song is an answer (`lines` empty), never a
    /// failure; a 404 is a song Navidrome won't give the asker, thrown for ErrorWords' gone sentence.
    public func lyrics(songID: String, ifNoneMatch etag: String?) async throws -> Fetched<LyricsAnswer> {
        var built = request(Routes.lyrics, path: ["song_id": songID])
        if let etag, !etag.isEmpty { built.headers["If-None-Match"] = etag }
        let response = try await answer(built, accept: built.headers["If-None-Match"] == nil ? [200] : [200, 304])
        if response.status == 304 { return .unchanged }
        return .fresh(LyricsAnswer(lyrics: try decode(SongLyrics.self, response), body: response.body),
                      etag: response.header("ETag"))
    }

    // MARK: app 0.10's playlists (Phase 4)

    /// The asker's playlists and everyone's shared ones, in Navidrome's order (by name) - as the person signed in.
    public func playlists() async throws -> [Playlist] {
        try await call(Routes.playlists, as: PlaylistList.self).playlists
    }

    /// One playlist with its songs, as Navidrome has it now. A 404 - not the asker's and not shared, or deleted - is
    /// thrown, for the page's gone line.
    public func playlist(id: String) async throws -> PlaylistWithSongs {
        try await call(Routes.playlist, path: ["playlist_id": id])
    }

    /// A new playlist of the asker's, private, with `songIDs` in their order (none: an empty one) - answered whole.
    /// A blank name, or one too long, is refused in the server's words (a 422).
    public func createPlaylist(name: String, songIDs: [String]) async throws -> PlaylistWithSongs {
        try await call(Routes.createPlaylist, sending: NewPlaylistBody(name: name, songIds: songIDs))
    }

    /// `songIDs` added at the playlist's end. With `.ask`, some there already writes nothing (`done` false).
    public func addToPlaylist(id: String, songIDs: [String], duplicates: PlaylistDuplicates) async throws
        -> PlaylistAddAnswer {
        try await call(Routes.addToPlaylist, path: ["playlist_id": id],
                       sending: PlaylistAddBody(songIds: songIDs, duplicates: duplicates))
    }

    /// Edit's Done: the playlist as Navidrome has it after the write. A 409 is a change made in another app since Edit
    /// began (nothing written); a 404, gone; a 403, not the asker's to change.
    public func editPlaylist(id: String, body: PlaylistEditBody) async throws -> PlaylistWithSongs {
        try await call(Routes.editPlaylist, path: ["playlist_id": id], sending: body)
    }

    /// The asker's playlist deleted, for good - Navidrome has no undo.
    public func deletePlaylist(id: String) async throws {
        _ = try await call(Routes.deletePlaylist, as: PlaylistDeleted.self, path: ["playlist_id": id])
    }

    // MARK: app 0.8's play history (server 2.1.14)

    /// A page of the person's plays, newest first: the newest (`before` nil), or the one before a page's last.
    public func historyPage(before: HistoryCursor? = nil, limit: Int = PlayHistory.page) async throws -> HistoryPage {
        var query = [("limit", String(limit))]
        if let before {
            query.append(("before_at", String(before.at)))
            query.append(("before_id", before.id))
        }
        return try await call(Routes.history, query: query)
    }

    /// Starts sent to be kept (at most `PlayHistory.postMax`): how many deadwax took, and how many it skipped - nil when
    /// its answer doesn't say. Any 2xx is taken, whatever its body: the starts are deadwax's then, and an answer the app
    /// can't read must never keep them waiting to be sent again for ever (KeptSender forgets a batch only when this
    /// returns).
    @discardableResult
    public func recordStarts(_ starts: [Played]) async throws -> HistoryTaken? {
        let json: Data
        do {
            json = try JSONEncoder().encode(HistoryPost(starts: starts))
        } catch {
            throw APIFailure.other("The app couldn't write what it meant to send (HistoryPost).")
        }
        let response = try await answer(request(Routes.recordHistory, json: json), accept: Set(200..<300))
        return try? JSONDecoder().decode(HistoryTaken.self, from: response.body)
    }

    // MARK: the turntable's window (turntable.md 4.5)

    /// `/scrub`'s request: `at` and `seconds` (`DeckScrub.ask`) and nothing else.
    public func scrubRequest(songID: String, at: Double, seconds: Double) -> HTTPRequest {
        var built = request(Routes.scrub, path: ["song_id": songID], query: DeckScrub.query(at: at, seconds: seconds))
        built.headers["Accept"] = "audio/flac"
        return built
    }

    /// A window's FLAC from deadwax and where it sits in the song (`X-Deadwax-Window`) - or why there is none, as the
    /// deck's rules take it (`DeckScrub.failure`): nil for a 204, deadwax's answer to a request it saw go away. Not
    /// reaching deadwax at all is thrown (APIFailure), as every route's is; a cancel is thrown as CancellationError.
    public func scrub(songID: String, at: Double, seconds: Double) async throws
        -> Result<(flac: Data, header: DeckScrub.Header), DeckWindowError>? {
        let sent = scrubRequest(songID: songID, at: at, seconds: seconds)
        let response = try await send(sent)
        if response.status == 200 {
            guard let header = DeckScrub.Header.parse(response.header("X-Deadwax-Window")) else {
                return .failure(.failed("its answer didn't say where it is in the song"))
            }
            return .success((response.body, header))
        }
        let words = failure(response, to: sent).words
        let detail = response.status == 415 ? detailWords(response.body, status: 415) : nil
        return DeckScrub.failure(status: response.status,
                                 detail: detail?.hasPrefix("deadwax answered") == true ? nil : detail,
                                 words: words).map { .failure($0) }
    }

    // MARK: answers

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch {
            if APIFailure.isCancellation(error) { throw CancellationError() }
            throw APIFailure.noAnswer(error, to: request, server: server)
        }
    }

    /// `response` as the failure it is, the signed-out hook told of a session that ended.
    func failure(_ response: HTTPResponse, to request: HTTPRequest) -> APIFailure {
        let failure = APIFailure.answered(response, to: request)
        if failure.isSignedOut { onSignedOut?(failure, session) }
        return failure
    }

    /// Reads an answer as `type`; one that can't be read is said in words, naming the field it tripped on.
    public func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw APIFailure.other("deadwax's answer couldn't be read (\(type)\(Self.what(error))). Is the app"
                                   + " older or newer than the server?")
        }
    }

    static func isEmptyObject(_ body: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?.isEmpty == true
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

extension DeadwaxClient.Fetched: Equatable where Value: Equatable {}

/// The album warm's answer (`{state}`).
private struct LevelWarmed: Decodable {
    let state: String?
}
