import Foundation
import Testing
@testable import DeadwaxCore

/// A transport that answers from a table (or a route's own handler) and remembers what was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: HTTPResponse] = [:]
    private var handlers: [String: @Sendable (HTTPRequest) -> HTTPResponse] = [:]
    private var thrown: URLError.Code?
    private(set) var sent: [HTTPRequest] = []

    func answer(_ path: String, _ status: Int, _ json: String, headers: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        answers[path] = HTTPResponse(status: status, headers: headers, body: Data(json.utf8))
    }

    /// `path` answered by `handler`, from what was sent.
    func handle(_ path: String, _ handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) {
        lock.lock(); defer { lock.unlock() }
        handlers[path] = handler
    }

    func goAway() { fail(.cannotConnectToHost) }

    /// Every request throws a URLError of `code`, as URLSession does when nothing answered.
    func fail(_ code: URLError.Code) {
        lock.lock(); defer { lock.unlock() }
        thrown = code
    }

    var last: HTTPRequest? {
        lock.lock(); defer { lock.unlock() }
        return sent.last
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            sent.append(request)
            if let thrown { throw URLError(thrown) }
            if let handler = handlers[request.url.path] { return handler(request) }
            return answers[request.url.path] ?? HTTPResponse(status: 404, body: Data(#"{"detail":"Not Found"}"#.utf8))
        }
    }
}

func client(session: String? = nil) -> (DeadwaxClient, FakeTransport) {
    let transport = FakeTransport()
    let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    return (DeadwaxClient(server: server, session: session, transport: transport), transport)
}

/// What a client's signed-out hook was told.
final class SignedOutHeard: @unchecked Sendable {
    private let lock = NSLock()
    private var heard: [(APIFailure, String?)] = []

    var all: [(APIFailure, String?)] { lock.withLock { heard } }

    func hear(_ failure: APIFailure, _ session: String?) { lock.withLock { heard.append((failure, session)) } }
}

/// A JSON value as sent - read with JSONDecoder, which reads alike on Linux and on Apple's systems.
enum SentValue: Decodable, Equatable {
    case string(String), number(Double), bool(Bool), null, list([SentValue]), object([String: SentValue])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let list = try? value.decode([SentValue].self) { self = .list(list) }
        else { self = .object(try value.decode([String: SentValue].self)) }
    }
}

/// The JSON object a request sent.
func sentJSON(_ request: HTTPRequest?) throws -> [String: SentValue] {
    let body = try #require(request?.body)
    return try JSONDecoder().decode([String: SentValue].self, from: body)
}

@Suite struct ClientTests {
    @Test func healthIsReadWhenOkAndWhenThePollerStopped() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/health", 200, #"{"status":"ok","version":"2.0.0","poller":"running"}"#)
        #expect(try await deadwax.health() == Health(status: "ok", version: "2.0.0", poller: "running"))
        transport.answer("/deadwax/health", 503, #"{"status":"unhealthy","version":"2.0.0","poller":"stopped"}"#)
        #expect(try await deadwax.health().status == "unhealthy")
        #expect(transport.last?.url.absoluteString == "http://192.168.3.20:8090/deadwax/health")
        #expect(transport.last?.method == "GET")
    }

    @Test func meWithLoginsOffIsTheSharedAccount() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/me", 200,
                         #"{"user":"local","admin":true,"auth":"off","version":"2.0.0","permissions":["request"],"permissions_unverified":false}"#)
        let me = try await deadwax.me()
        #expect(me.user == "local" && me.admin && !me.loginsOn)
        #expect(me.version == "2.0.0" && me.permissions == ["request"] && me.permissionsUnverified == false)
        #expect(transport.last?.headers["Cookie"] == nil)
    }

    @Test func meFromAServerBeforePermissionsStillReads() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/me", 200, #"{"user":"james","admin":true,"auth":"on"}"#)
        let me = try await deadwax.me()
        #expect(me.permissions == nil && me.permissionsUnverified == nil && me.version == nil)
    }

    @Test func a401IsSignedOutWithDeadwaxsWords() async throws {
        let heard = SignedOutHeard()
        let (made, transport) = client(session: "s.old")
        var deadwax = made
        deadwax.onSignedOut = { failure, session in heard.hear(failure, session) }
        transport.answer("/deadwax/me", 401, #"{"detail":"Your session has ended. Sign in again."}"#)
        let expected = APIFailure.answered(.init(status: 401, method: "GET", path: "/me",
                                                 detail: "Your session has ended. Sign in again."))
        await #expect(throws: expected) { try await deadwax.me() }
        #expect(expected.isSignedOut && expected.words == "Your session has ended. Sign in again.")
        #expect(transport.last?.headers["Cookie"] == "deadwax_session=s.old")
        #expect(heard.all.count == 1)
        #expect(heard.all.first?.0 == expected && heard.all.first?.1 == "s.old")
    }

    @Test func signingInSendsTheFormAndKeepsTheSession() async throws {
        let (deadwax, transport) = client(session: "s.stale")
        transport.answer("/deadwax/auth/login", 200, #"{"user":"james","admin":true,"auth":"on","version":"2.0.0"}"#,
                         headers: ["Set-Cookie": "deadwax_session=s.abc-DEF_123; HttpOnly; Max-Age=2592000; Path=/; SameSite=strict"])
        let (me, session) = try await deadwax.signIn(username: "james", password: "pw \"quoted\"")
        #expect(me.user == "james" && me.loginsOn)
        #expect(session == "s.abc-DEF_123")
        let sent = try #require(transport.last)
        #expect(sent.method == "POST")
        #expect(sent.headers["Cookie"] == nil)
        #expect(sent.headers["Content-Type"] == "application/json")
        let form = try JSONDecoder().decode(SignInBody.self, from: try #require(sent.body))
        #expect(form == SignInBody(username: "james", password: "pw \"quoted\""))
    }

    @Test func aWrongPasswordIsWordsNotASignOut() async throws {
        let heard = SignedOutHeard()
        let (made, transport) = client()
        var deadwax = made
        deadwax.onSignedOut = { failure, session in heard.hear(failure, session) }
        transport.answer("/deadwax/auth/login", 401, #"{"detail":"That user name and password don't match."}"#)
        let expected = APIFailure.answered(.init(status: 401, method: "POST", path: "/auth/login",
                                                 detail: "That user name and password don't match."))
        await #expect(throws: expected) { _ = try await deadwax.signIn(username: "james", password: "wrong") }
        #expect(!expected.isSignedOut)
        #expect(heard.all.isEmpty)
        #expect(ErrorWords.signInProblem(expected) == "That user name and password don't match.")
    }

    @Test func aSignInWithNoCookieIsSaid() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/auth/login", 200, #"{"user":"james","admin":false,"auth":"on"}"#)
        await #expect(throws: APIFailure.other("deadwax said yes, but sent no session to keep.")) {
            _ = try await deadwax.signIn(username: "james", password: "x")
        }
    }

    @Test func signingOutTakesAnyAnswer() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/auth/logout", 500, "")
        try await deadwax.signOut()
        transport.goAway()
        await #expect(throws: APIFailure.self) { try await deadwax.signOut() }
    }

    @Test func searchAsksForWhatItSays() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/navidrome/search", 200,
                         #"{"artists":[{"id":"ar"}],"albums":[{"id":"al","name":"Start test"}],"songs":[{"id":"so","title":"Three beeps","samplingRate":192000,"bitDepth":24,"size":804602,"duration":4.0,"extra":"ignored"}]}"#)
        let found = try await deadwax.search("Start test & more+", songs: 100, songOffset: 200)
        #expect(found.albums == [AlbumSummary(id: "al", name: "Start test")])
        #expect(found.songs.first?.samplingRate == 192_000)
        #expect(found.songs.first?.size == 804_602)
        let url = try #require(transport.last?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.map(\.name) == ["q", "artistCount", "albumCount", "songCount", "songOffset"])
        #expect(items.first?.value == "Start test & more+")
        #expect(url.absoluteString.contains("q=Start%20test%20%26%20more%2B"))
    }

    /// (slice 5) Songs' page: librarySongs' own ask - every song (an empty q), no artists or albums, 100 from the offset.
    @Test func songsAskForEverySong() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/navidrome/search", 200, #"{"artists":[],"albums":[],"songs":[{"id":"so","title":"Roads"}]}"#)
        let found = try await deadwax.search(SongsList.query("   "), songs: SongsPaging.pageSize, songOffset: 200)
        #expect(found.songs.map(\.id) == ["so"])
        let url = try #require(transport.last?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.map(\.name) == ["q", "artistCount", "albumCount", "songCount", "songOffset"])
        #expect(items.map { (item: URLQueryItem) -> String in item.value ?? "-" } == ["", "0", "0", "100", "200"])
    }

    @Test func theStreamIsTheFileAsItIsWithTheSession() throws {
        let (deadwax, _) = client(session: "s.xyz")
        let request = deadwax.streamRequest(songID: "a/b?c", format: "raw")
        #expect(request.url.absoluteString == "http://192.168.3.20:8090/deadwax/navidrome/stream/a%2Fb%3Fc?format=raw")
        #expect(request.headers["Cookie"] == "deadwax_session=s.xyz")
        #expect(request.method == "GET")
        #expect(request.timeout == nil)
    }

    @Test func onlyDeclaredQueryNamesAreSent() {
        let (deadwax, _) = client()
        let url = deadwax.url(Routes.stream, path: ["song_id": "x"], query: [("format", "raw"), ("u", "forged")])
        #expect(url.query == "format=raw")
    }

    @Test func nothingAnsweringIsOfflineWithWhatToCheck() async {
        let (deadwax, transport) = client()
        transport.goAway()
        do {
            _ = try await deadwax.health()
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            guard case .offline(let none) = error else {
                Issue.record("not offline: \(error)")
                return
            }
            #expect(none.method == "GET" && none.path == "/health" && none.server == deadwax.server)
            #expect(error.words.hasPrefix("Couldn't reach deadwax at http://192.168.3.20:8090."))
            #expect(error.words.contains("Local Network"))
            #expect(ErrorWords.kind(of: error) == .offline)
            #expect(ErrorWords.signInProblem(error) == ErrorWords.unreached)
        } catch {
            Issue.record("not an APIFailure: \(error)")
        }
    }

    @Test func noAnswerInTimeIsATimeoutAndALeftPageIsNoFailure() async throws {
        let (deadwax, transport) = client()
        transport.fail(.timedOut)
        do {
            _ = try await deadwax.me()
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            guard case .timeout(let none) = error else {
                Issue.record("not a timeout: \(error)")
                return
            }
            #expect(none.path == "/me")
            #expect(ErrorWords.of(error).said == "That took too long. Try again.")
        }
        transport.fail(.cancelled)
        await #expect(throws: CancellationError.self) { try await deadwax.me() }
        // a TLS failure, say: nothing to do with the network being there - said as Phase 0 said it
        transport.fail(.secureConnectionFailed)
        do {
            _ = try await deadwax.me()
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            guard case .other(let words) = error else {
                Issue.record("not other: \(error)")
                return
            }
            #expect(words.hasPrefix("Couldn't reach deadwax at http://192.168.3.20:8090."))
        }
    }

    /// Every code APIFailure.isOffline names is "Can't connect to deadwax." - WireGuard dropping mid-request (-1005),
    /// a DNS miss - from the client and from a bare URLError alike; dropping one would make it read "Something went
    /// wrong ... tell whoever runs deadwax". And the codes the web would also call offline (its fetch can't tell a TLS
    /// failure or a garbled answer from no network) but the phone says as `other` - a deliberate difference: checking
    /// the connection can't fix a certificate or a proxy, only whoever runs deadwax can.
    @Test func whichTransportFailuresAreOffline() async {
        let offline: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
            .dataNotAllowed, .internationalRoamingOff,
        ]
        let other: [URLError.Code] = [.secureConnectionFailed, .serverCertificateUntrusted, .badServerResponse,
                                      .cannotParseResponse]
        for code in offline + other {
            let expected: ErrorWords.Kind = offline.contains(code) ? .offline : .other
            #expect(APIFailure.isOffline(code) == (expected == .offline), "URLError \(code.rawValue)")
            #expect(ErrorWords.kind(of: URLError(code)) == expected, "URLError \(code.rawValue)")
            let (deadwax, transport) = client()
            transport.fail(code)
            do {
                _ = try await deadwax.me()
                Issue.record("URLError \(code.rawValue): expected a failure")
            } catch let error as APIFailure {
                switch (error, expected) {
                case (.offline(let none), .offline):
                    #expect(none.path == "/me", "URLError \(code.rawValue)")
                    #expect(ErrorWords.of(error).said == "Can't connect to deadwax. Check your connection, then try again.")
                case (.other(let words), .other):
                    #expect(words.hasPrefix("Couldn't reach deadwax at http://192.168.3.20:8090."), "URLError \(code.rawValue)")
                    #expect(ErrorWords.of(error).said
                            == "Something went wrong. Try again - if it keeps happening, tell whoever runs deadwax.")
                default:
                    Issue.record("URLError \(code.rawValue): \(error), expected \(expected)")
                }
            } catch {
                Issue.record("URLError \(code.rawValue): not an APIFailure: \(error)")
            }
        }
    }

    @Test func detailIsDeadwaxsOwnWordsOrTheStatus() {
        #expect(detailWords(Data(#"{"detail":"Logins are off."}"#.utf8), status: 409) == "Logins are off.")
        #expect(detailWords(Data(#"{"detail":[{"msg":"field required"},{"msg":"too long"}]}"#.utf8), status: 422)
                == "field required too long")
        #expect(detailWords(Data("<html>".utf8), status: 502) == "deadwax answered 502 and said nothing more.")
    }

    @Test func aFailureKeepsEverythingDeadwaxSaid() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/navidrome/albums/al 1", 503,
                         #"{"detail":"deadwax can't read its database just now.","why":"Check DB_PATH.","kind":"locked","busy":true}"#)
        await #expect(throws: APIFailure.answered(.init(status: 503, method: "GET", path: "/navidrome/albums/al%201",
                                                        detail: "deadwax can't read its database just now.",
                                                        why: "Check DB_PATH.", kind: "locked", busy: true))) {
            _ = try await deadwax.album(id: "al 1")
        }
        // the route under /deadwax with its query, as the web's ApiError.path
        transport.answer("/deadwax/store/album", 422, #"{"detail":[{"msg":"field required"},{"msg":"too long"}],"busy":"yes"}"#)
        do {
            _ = try await deadwax.storeAlbum(navidromeID: "x+y")
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            let answer = try #require(error.answer)
            #expect(answer.path == "/store/album?navidrome_id=x%2By")
            #expect(answer.detail == nil && answer.problems == ["field required", "too long"] && !answer.busy)
            #expect(error.words == "field required too long")
            #expect(answer.fallback == "GET /store/album?navidrome_id=x%2By failed")
            #expect(ErrorWords.rawWords(error) == "GET /store/album?navidrome_id=x%2By failed")
        }
    }

    @Test func anIPv6AddressKeepsItsPathAndQuery() throws {
        for typed in ["[::1]:8090", "http://[fe80::1%25en0]:8090/player/", "[2001:db8::20]"] {
            let server = try ServerAddress.parse(typed).get()
            let deadwax = DeadwaxClient(server: server, transport: FakeTransport())
            let url = deadwax.url(Routes.search, query: [("q", "x"), ("songCount", "1")])
            #expect(url.path == "/deadwax/navidrome/search", "\(typed) -> \(url)")
            #expect(url.query == "q=x&songCount=1", "\(typed) -> \(url)")
            #expect(url.absoluteString.hasPrefix(server.base.absoluteString + "/deadwax/"), "\(typed) -> \(url)")
        }
    }

    @Test func somethingElseAtTheAddressIsSaidInWords() async throws {
        let (deadwax, transport) = client()
        // another service on the port, or a proxy's page with deadwax down behind it
        transport.answer("/deadwax/health", 200, "<html><body>Welcome to nginx!</body></html>")
        do {
            _ = try await deadwax.health()
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            guard case .other(let words) = error else {
                Issue.record("not other: \(error)")
                return
            }
            #expect(words.contains("isn't deadwax") && words.contains("port"))
            #expect(!words.contains("DecodingError") && !words.contains("dataCorrupted"))
        }
        // deadwax's JSON without what the app needs: which field, not DecodingError's dump
        transport.answer("/deadwax/health", 200, #"{"version":"9.0.0"}"#)
        await #expect(throws: DeadwaxError.unreadable("deadwax's answer couldn't be read (Health: no status). Is the app older or newer than the server?")) {
            try await deadwax.health()
        }
        transport.answer("/deadwax/health", 503, "<html>503 Service Unavailable</html>")
        do {
            _ = try await deadwax.health()
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(error == .answered(.init(status: 503, method: "GET", path: "/health")))
            #expect(error.words == "deadwax answered 503 and said nothing more.")
        }
    }

    @Test func everyRouteIsDeadwaxsOwn() {
        #expect(Routes.all.count == 110)
        #expect(Set(Routes.all).count == Routes.all.count)
        for endpoint in Routes.all {
            #expect(endpoint.path.hasPrefix("/deadwax/"))
            #expect(["GET", "POST"].contains(endpoint.method) || endpoint == Routes.savePreferences
                    || endpoint == Routes.saveServerSettings)
        }
        // (Phase 6, slice 3) a PUT: You > Getting albums changed, as the route takes it; (Phase 8, slice 8) the other,
        // Server settings' drafts saved in one batch
        #expect(Routes.savePreferences.method == "PUT")
        #expect(Routes.saveServerSettings.method == "PUT")
        #expect(Routes.warmLevels == Routes.levelAlbum)
    }

    // MARK: Phase 1's

    @Test func theAlbumIndexAndAutoEqAreGivenLongerAndEveryOtherRouteTheTransports() {
        let (deadwax, _) = client()
        let index = deadwax.request(Routes.albumIndex, query: [("scope", "yours")])
        #expect(index.timeout == 30)
        #expect(index.url.query == "scope=yours")
        // AutoEq's two, 20 s: deadwax may wait 15 s for AutoEq's list or a file (test_ios_contract.py holds it there)
        // (Phase 5) /library/owned, 30 s: it walks the library when the saved scan is behind (src/routes/library.py)
        // (Phase 5, slice 2) /fully_search, 20 s: a quick search's patience and the rate limiter's turns; /release_group,
        // 60 s: several pages of MusicBrainz's browse (test_ios_contract.py holds both above deadwax's own waits)
        // (slice 3) /artists and /songs, 20 s, quick searches as /fully_search is; /artist, 60 s, one request with
        // MusicBrainz's ten attempts; /discography, 60 s, a browse of up to five pages
        // (Phase 6, slice 1) /download/jobs, 20 s, slskd asked for every open download and each queued one's place;
        // a cancel and a clear, 30 s, slskd's transfers each stopped or tidied; Another source, 60 s, up to three
        // runners-up asked in turn; Same source again, 30 s, one peer asked again
        // (Phase 6, slice 2) the store's word, 20 s, its look may ask slskd how far a download has got; a search, 300 s,
        // two rounds of slskd's search behind deadwax's gate and the former names' lookup (test_ios_contract.py holds
        // it above deadwax's own worst case); an enqueue the same, as deadwax puts no bound on it. The preferences: the
        // transport's, read and saved (Phase 6, slice 3); a Join, 60 s, as Another source - it waits for the same
        // release's lock. (Album info) a folder's files read from the disk, 30 s: every file opened as it is asked.
        // (Phase 8, slice 1: Edit album) the scan, 120 s, a walk of the library when the saved scan is behind; a
        // release's pressings and a pressing, 60 s, MusicBrainz's browse and its retries; Changes, 60 s, every file
        // read; Apply, 480 s, two cover fetches, Navidrome asked twice and 300 s before the rename; a cover, 120 s,
        // the Cover Art Archive's and the files'; the cover drawn, 30 s; the queue's marks, 20 s
        // (slice 2: Tags) a tag edit's preview, 60 s, every file named read; its apply, 120 s, read and written again;
        // a picture inside a track, 30 s
        // (slice 3: Artwork and Lyrics) Get lyrics, 600 s, LRCLIB asked for each track two at a time; Get CD art, 360 s,
        // the Archive's listing (or fanart.tv's) and each disc's picture; a CD art picture, 30 s
        // (slice 4: Delete) what deleting it takes, 60 s, the folder walked; the delete, 120 s, the folder removed and
        // the saved scan and the store written
        // (slice 5: the artist tools) a name's summary, 120 s, the scan's; a picture in their folder, 30 s; Artist
        // images' preview, 660 s at least, the scan, a search and a lookup (111.5 s each at worst: ten attempts, each
        // the rate limiter's turn and its longest pause), three sources and five Commons widths; its Save, 600 s at
        // least; the search and an artist's facts, 120 s, one MusicBrainz request at worst; Move albums' preview, 480 s,
        // the scan,
        // who they are and every file read; its apply, 600 s at least - and the relay's pictures the transport's own
        // 8 s, over its 7 s deadline
        // (slice 6: Needs a look) the count, 30 s, the saved scan read and Navidrome's first listing waited for (3 s at
        // most); an album looked at, 20 s, one row written, as the marks
        // (slice 7: Library care) a rescan, 300 s, every file read with no bound of the server's; In nobody's library,
        // 30 s, and Add for them, 60 s, and Dismiss, 30 s: SQLite alone, 10 s of busy timeout for each store call
        // (slice 8: Server settings) the settings read, 30 s; their save, 60 s at least (more for a long batch: one
        // store call per setting); MusicBrainz's saved answers, 30 s, and Clear, 120 s, the cache file's own; the
        // MusicBrainz ping, 120 s, one request with its ten attempts (111.5 s at worst); slskd's, 30 s
        // (slice 9: the event log) the history, the transport's own 8 s, held in memory; the stream, 45 s - the most
        // it may say nothing between two bytes (three of its 15 s keepalives), never a wait over all
        // (slice 10: Change password) 240 s: four calls to Navidrome, the store's and the throttle's lock (180 at worst)
        // (slice 11: People) the list, 120 s at least (more for each account the last list named); Unlock, 120 s, the
        // name's sign-in throttle and Navidrome's login; Make account, Reset, the admin flip and Remove, 300 s, and
        // Forget and the permissions, 240 s - each after the one write lock, which another write may hold for a reset's
        // 130 s (PeopleWaits); Lock the transport's own 8 s, the unlock forgotten in memory
        let longer: [Endpoint: Double] = [Routes.albumIndex: 30, Routes.autoEqSearch: 20, Routes.autoEqProfile: 20,
                                          Routes.libraryOwned: 30, Routes.fullySearch: 20, Routes.releaseGroup: 60,
                                          Routes.searchArtists: 20, Routes.searchSongs: 20, Routes.artistFacts: 120,
                                          Routes.discography: 60, Routes.jobs: 20, Routes.cancelJob: 30,
                                          Routes.retryJob: 60, Routes.retryJobSame: 30, Routes.clearJobs: 30,
                                          Routes.storeState: 20, Routes.findCandidates: 300, Routes.enqueue: 300,
                                          Routes.joinJob: 60, Routes.libraryAdd: 60, Routes.libraryTracks: 30,
                                          Routes.libraryAlbums: 120, Routes.releases: 60, Routes.release: 60,
                                          Routes.retagPreview: 60, Routes.retagApply: 480, Routes.artFetch: 120,
                                          Routes.libraryArt: 30, Routes.queueIgnore: 20, Routes.queueUnignore: 20,
                                          Routes.tagsPreview: 60, Routes.tagsApply: 120, Routes.trackPicture: 30,
                                          Routes.lyricsFetch: 600, Routes.discArtFetch: 360, Routes.libraryDiscArt: 30,
                                          Routes.deletionSummary: 60, Routes.deleteAlbum: 120,
                                          Routes.libraryArtist: 120, Routes.artistArt: 30,
                                          Routes.artistImagesPreview: 660, Routes.artistImagesApply: 600,
                                          Routes.artistSearch: 120, Routes.refilePreview: 480, Routes.refileApply: 600,
                                          Routes.queueSummary: 30, Routes.queueReviewed: 20, Routes.rescan: 300,
                                          Routes.held: 30, Routes.heldAdd: 60, Routes.heldDismiss: 30,
                                          Routes.serverSettings: 30, Routes.saveServerSettings: 60,
                                          Routes.savedAnswers: 30, Routes.clearSavedAnswers: 120,
                                          Routes.pingMusicBrainz: 120, Routes.pingSlskd: 30, Routes.logStream: 45,
                                          Routes.ownPassword: 240, Routes.people: 120, Routes.unlockPeople: 120,
                                          Routes.createPerson: 300, Routes.resetPassword: 300, Routes.setAdmin: 300,
                                          Routes.removePerson: 300, Routes.forgetPerson: 240, Routes.savePermissions: 240]
        #expect(Routes.timeouts == longer)
        for endpoint in Routes.all {
            // each path parameter filled in: a brace left in a path is no URL
            let names = endpoint.path.split(separator: "{").dropFirst().map { String($0.prefix { $0 != "}" }) }
            let filled = Dictionary(uniqueKeysWithValues: names.map { ($0, "x") })
            #expect(deadwax.request(endpoint, path: filled).timeout == longer[endpoint], "\(endpoint.path)")
        }
    }

    @Test func anETagIsSentAndA304IsUnchanged() async throws {
        struct Index: Decodable, Sendable, Equatable { let albums: [String]; let truncated: Bool }
        let (deadwax, transport) = client()
        transport.handle("/deadwax/navidrome/album_index") { request in
            if request.headers["If-None-Match"] == #""v1""# { return HTTPResponse(status: 304, headers: ["ETag": #""v1""#]) }
            return HTTPResponse(status: 200, headers: ["ETag": #""v1""#], body: Data(#"{"albums":["a"],"truncated":false}"#.utf8))
        }
        let first = try await deadwax.fetch(Routes.albumIndex, as: Index.self, query: [("scope", "store")], ifNoneMatch: nil)
        #expect(first == .fresh(Index(albums: ["a"], truncated: false), etag: #""v1""#))
        #expect(transport.last?.headers["If-None-Match"] == nil)
        #expect(transport.last?.timeout == 30)
        let again = try await deadwax.fetch(Routes.albumIndex, as: Index.self, query: [("scope", "store")], ifNoneMatch: #""v1""#)
        #expect(again == .unchanged)
        #expect(transport.last?.headers["If-None-Match"] == #""v1""#)
        // a 304 nobody asked for is no answer to keep
        transport.handle("/deadwax/navidrome/album_index") { _ in HTTPResponse(status: 304) }
        await #expect(throws: APIFailure.answered(.init(status: 304, method: "GET", path: "/navidrome/album_index?scope=store"))) {
            _ = try await deadwax.fetch(Routes.albumIndex, as: Index.self, query: [("scope", "store")], ifNoneMatch: nil)
        }
    }

    @Test func aCoverCanBeAskedAgainWithItsETag() async throws {
        let (deadwax, transport) = client()
        transport.handle("/deadwax/navidrome/cover/al-1") { request in
            if request.headers["If-None-Match"] == "W/\"c1\"" { return HTTPResponse(status: 304) }
            return HTTPResponse(status: 200, headers: ["etag": "W/\"c1\"", "Content-Type": "image/jpeg"], body: Data([0xFF, 0xD8]))
        }
        #expect(try await deadwax.cover(coverID: "al-1", size: CoverSize.tile, ifNoneMatch: nil) == .fresh(Data([0xFF, 0xD8]), etag: "W/\"c1\""))
        #expect(transport.last?.url.query == "size=400")
        #expect(transport.last?.headers["Accept"] == "image/*")
        #expect(try await deadwax.cover(coverID: "al-1", size: CoverSize.tile, ifNoneMatch: "W/\"c1\"") == .unchanged)
        #expect(try await deadwax.cover(coverID: "al-1", size: CoverSize.lockScreen) == Data([0xFF, 0xD8]))
    }

    // MARK: app 0.4's

    @Test func aSongsLyricsAreAskedWithTheirETagAndKeptAsTheyCame() async throws {
        let (deadwax, transport) = client()
        let body = #"{"synced":true,"lines":[{"time":18.7,"text":"The first line we sing"},{"time":22.701,"text":""}]}"#
        transport.handle("/deadwax/navidrome/lyrics/so 1") { request in
            if request.headers["If-None-Match"] == #""l1""# { return HTTPResponse(status: 304, headers: ["ETag": #""l1""#]) }
            return HTTPResponse(status: 200, headers: ["etag": #""l1""#], body: Data(body.utf8))
        }
        let first = try await deadwax.lyrics(songID: "so 1", ifNoneMatch: nil)
        let lyrics = SongLyrics(synced: true, lines: [LyricLine(time: 18.7, text: "The first line we sing"), LyricLine(time: 22.701, text: "")])
        #expect(first == .fresh(LyricsAnswer(lyrics: lyrics, body: Data(body.utf8)), etag: #""l1""#))
        #expect(transport.last?.method == "GET")
        #expect(transport.last?.url.absoluteString == "http://192.168.3.20:8090/deadwax/navidrome/lyrics/so%201")
        #expect(transport.last?.headers["If-None-Match"] == nil)
        #expect(transport.last?.timeout == nil)
        #expect(try await deadwax.lyrics(songID: "so 1", ifNoneMatch: #""l1""#) == .unchanged)
        #expect(transport.last?.headers["If-None-Match"] == #""l1""#)
        // an empty ETag is none sent
        _ = try await deadwax.lyrics(songID: "so 1", ifNoneMatch: "")
        #expect(transport.last?.headers["If-None-Match"] == nil)
        // none for the song is an answer
        transport.answer("/deadwax/navidrome/lyrics/so-2", 200, #"{"synced":false,"lines":[]}"#)
        let none = try await deadwax.lyrics(songID: "so-2", ifNoneMatch: nil)
        #expect(none == .fresh(LyricsAnswer(lyrics: SongLyrics(synced: false, lines: []), body: Data(#"{"synced":false,"lines":[]}"#.utf8)), etag: nil))
        // a song Navidrome won't give the asker is thrown, for the gone sentence
        transport.answer("/deadwax/navidrome/lyrics/so-3", 404, #"{"detail":"Navidrome has nothing by that id"}"#)
        await #expect(throws: APIFailure.answered(.init(status: 404, method: "GET", path: "/navidrome/lyrics/so-3",
                                                        detail: "Navidrome has nothing by that id"))) {
            _ = try await deadwax.lyrics(songID: "so-3", ifNoneMatch: nil)
        }
        // and a 304 nobody asked for is no answer
        transport.handle("/deadwax/navidrome/lyrics/so-4") { _ in HTTPResponse(status: 304) }
        await #expect(throws: APIFailure.answered(.init(status: 304, method: "GET", path: "/navidrome/lyrics/so-4"))) {
            _ = try await deadwax.lyrics(songID: "so-4", ifNoneMatch: nil)
        }
    }

    @Test func coverSizesAreAFewSteps() {
        #expect(CoverSize.steps == [128, 400, 1024])
        #expect([1, 128, 129, 400, 401, 1024, 3000].map(CoverSize.step(for:)) == [128, 128, 400, 400, 1024, 1024, 1024])
    }

    @Test func anAlbumIsReadLenientlyAndNoneIsNil() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/navidrome/albums/al-1", 200, #"""
        {"id":"al-1","name":"Dummy","artist":"Portishead","artistId":"ar-1","coverArt":"al-1_0","songCount":3,
         "duration":2940.5,"year":1994,"genre":"Trip-Hop","musicBrainzId":"","starred":"2026-01-02T03:04:05Z",
         "created":1767312000.25,"playCount":"seven","recordLabels":[{"name":"Go! Beat"},{"name":7}],
         "discTitles":[{"disc":1,"title":"One"},{"disc":"2","title":"Two"},{"disc":2.5,"title":"Half"}],
         "song":[{"id":"so-1","title":"Mysterons","track":1,"discNumber":1,"duration":306,"suffix":"flac",
                  "artistId":"ar-1","year":1994,"playCount":4,"displayComposer":"Barrow, Gibbons",
                  "contributors":[{"role":"composer","artist":{"name":"Geoff Barrow"}},{"role":3}]},
                 {"title":"no id"},
                 {"id":"so-3","title":"Strangers","track":"2"}]}
        """#)
        let album = try #require(try await deadwax.album(id: "al-1"))
        #expect(album.name == "Dummy" && album.year == 1994 && album.duration == 2940.5 && album.isStarred)
        #expect(album.created == nil && album.playCount == nil)
        #expect(album.recordLabels == [Album.RecordLabel(name: "Go! Beat"), Album.RecordLabel(name: nil)])
        #expect(album.discTitles == [DiscTitle(disc: 1, title: "One"), DiscTitle(disc: 2, title: "Two"),
                                     DiscTitle(disc: nil, title: "Half")])
        let songs = try #require(album.song)
        #expect(songs.map(\.id) == ["so-1", "so-3"])
        #expect(songs[0].playCount == 4 && songs[0].displayComposer == "Barrow, Gibbons" && songs[0].artistId == "ar-1")
        #expect(songs[0].contributors == [Song.Contributor(role: "composer", artist: "Geoff Barrow"),
                                          Song.Contributor(role: nil, artist: nil)])
        #expect(songs[1].track == nil && songs[1].title == "Strangers")

        transport.answer("/deadwax/navidrome/albums/gone", 200, "{}")
        #expect(try await deadwax.album(id: "gone") == nil)
        transport.answer("/deadwax/navidrome/albums/missing", 404, #"{"detail":"Navidrome has nothing by that id"}"#)
        do {
            _ = try await deadwax.album(id: "missing")
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(ErrorWords.of(error, gone: ErrorWords.albumGone).text == ErrorWords.albumGone)
        }
    }

    @Test func aSongIsAskedByItsID() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/navidrome/songs/so-1", 200, #"{"id":"so-1","title":"Mysterons","playCount":9}"#)
        #expect(try await deadwax.song(id: "so-1")?.playCount == 9)
        transport.answer("/deadwax/navidrome/songs/none", 200, "{}")
        #expect(try await deadwax.song(id: "none") == nil)
    }

    @Test func theIDBridgeIsReadAsDeadwaxSendsIt() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/store/album", 200, #"""
        {"release_mbid":"3f1b-x","release_group_mbid":"rg-1","navidrome_id":"al-1",
         "present":[{"id":7,"path":"Portishead/Dummy (1994)","release_mbid":"3f1b-x","artist":"Portishead","album":"Dummy",
                     "edition":"","year":"1994","formats":["FLAC"],"track_count":11,"size":412345678,"original_year":"",
                     "first_seen":"2026-01-01T00:00:00","imported":true},
                    {"path":"no id"}],
         "other_pressings":[{"id":9,"path":"Portishead/Dummy (1994) [Deluxe]","release_mbid":"9a","artist":"Portishead",
                             "album":"Dummy","edition":"Deluxe","year":"2014","formats":["MP3"],"track_count":14,
                             "navidrome_id":null,"yours":false}],
         "yours":true}
        """#)
        let store = try await deadwax.storeAlbum(navidromeID: "al-1")
        #expect(transport.last?.url.query == "navidrome_id=al-1")
        #expect(store.releaseMbid == "3f1b-x" && store.releaseGroupMbid == "rg-1" && store.navidromeId == "al-1")
        #expect(store.yours == true)
        #expect(store.present.map(\.id) == [7])
        #expect(store.present.first?.trackCount == 11 && store.present.first?.size == 412_345_678)
        #expect(store.present.first?.imported == true && store.present.first?.originalYear == "")
        #expect(store.otherPressings.first?.edition == "Deluxe" && store.otherPressings.first?.yours == false)
        #expect(store.otherPressings.first?.navidromeId == nil)
    }

    @Test func addingSendsWhatTheAlbumPageSends() async throws {
        let store = StoreAlbum(releaseMbid: "3f1b-x", releaseGroupMbid: "rg-1", navidromeId: "al-1",
                               present: [StoreRow(id: 7, path: "p", artist: "Portishead", album: "", year: "")])
        let release = AddRelease.from(store: store, artistName: "Portishead (album)", albumName: "Dummy")
        // the store's first folder's artist; its album empty, so the album's own; an empty year none
        #expect(release == AddRelease(artist: "Portishead", albumArtist: "Portishead", album: "Dummy", year: nil,
                                      releaseMbid: "3f1b-x", releaseGroupMbid: "rg-1"))
        let none = AddRelease.from(store: nil, artistName: "Someone", albumName: nil)
        #expect(none.artist == "Someone" && none.album == "" && none.releaseMbid == nil)

        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/me/library/add", 200, #"{"added":true,"already":false,"complete":true,"starred":true}"#)
        let added = try await deadwax.addToLibrary(release)
        #expect(added == AddedToLibrary(added: true, already: false, complete: true, starred: true))
        let json = try sentJSON(transport.last)
        #expect(json == [
            "artist": .string("Portishead"), "album_artist": .string("Portishead"), "artist_mbids": .list([]),
            "album": .string("Dummy"), "year": .null, "original_year": .null, "release_mbid": .string("3f1b-x"),
            "release_group_mbid": .string("rg-1"), "edition_tags": .list([]), "tracks": .list([]),
        ])
        #expect(transport.last?.headers["Content-Type"] == "application/json")
    }

    @Test func removingSendsNavidromesID() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/me/library/remove", 200,
                         #"{"removed":true,"entries":2,"words":"Removed from your library - it's still in the collection, and nothing was deleted."}"#)
        let removed = try await deadwax.removeFromLibrary(navidromeID: "al-1")
        #expect(removed.removed && removed.entries == 2 && removed.words.hasPrefix("Removed from your library"))
        #expect(try sentJSON(transport.last) == ["navidrome_id": .string("al-1")])
        // a refusal in words: kept for ErrorWords
        transport.answer("/deadwax/me/library/remove", 409, #"{"detail":"Logins are off, so there's no library of yours to change."}"#)
        do {
            _ = try await deadwax.removeFromLibrary(navidromeID: "al-1")
            Issue.record("expected a failure")
        } catch let error as APIFailure {
            #expect(ErrorWords.kind(of: error) == .refused)
            #expect(ErrorWords.of(error).text == "Logins are off, so there's no library of yours to change.")
        }
    }

    @Test func warmingAnAlbumsLevelsIsA202() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/navidrome/level/album/al-1", 202, #"{"state":"measuring"}"#)
        #expect(try await deadwax.warmLevels(albumID: "al-1") == "measuring")
        #expect(transport.last?.method == "POST" && transport.last?.body == nil)
    }

    @Test func aScrobbleSaysWhenInMilliseconds() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/navidrome/scrobble/so-1", 200, #"{"ok":true}"#)
        try await deadwax.scrobble(songID: "so-1", submission: true, time: 1_767_312_000_123)
        #expect(transport.last?.url.query == "submission=true&time=1767312000123")
        try await deadwax.scrobble(songID: "so-1", submission: false)
        #expect(transport.last?.url.query == "submission=false")
    }

    @Test func anyModelCanBeCalledForWithItsBody() async throws {
        struct Seen: Encodable { let album_ids: [Int] }
        struct Cleared: Decodable { let cleared: Int }
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/me/library/seen", 200, #"{"cleared":3}"#)
        let cleared = try await deadwax.call(Routes.librarySeen, as: Cleared.self, sending: Seen(album_ids: [1, 2]))
        #expect(cleared.cleared == 3)
        #expect(try sentJSON(transport.last) == ["album_ids": .list([.number(1), .number(2)])])
        transport.answer("/deadwax/navidrome/status", 200, #"{"configured":true,"ok":false,"server":null,"problem":"x"}"#)
        let status = try await deadwax.call(Routes.navidromeStatus, as: NavidromeStatus.self)
        #expect(status == NavidromeStatus(configured: true, ok: false, problem: "x"))
    }

    @Test func theNavidromeStatusIsReadInEachOfItsShapes() async throws {
        // src/routes/navidrome.py status's three answers: not set up, its ping failed, and ok
        let (deadwax, transport) = client()
        let shapes: [(String, NavidromeStatus)] = [
            (#"{"configured":false,"ok":false,"server":null,"problem":"Navidrome isn't set up (NAVIDROME_URL)"}"#,
             NavidromeStatus(configured: false, ok: false, problem: "Navidrome isn't set up (NAVIDROME_URL)")),
            (#"{"configured":true,"ok":false,"server":null,"problem":"Navidrome unreached at http://navidrome:4533"}"#,
             NavidromeStatus(configured: true, ok: false, problem: "Navidrome unreached at http://navidrome:4533")),
            (#"{"configured":true,"ok":true,"server":"Navidrome 0.64.2","problem":null}"#,
             NavidromeStatus(configured: true, ok: true, server: "Navidrome 0.64.2")),
        ]
        for (json, status) in shapes {
            transport.answer("/deadwax/navidrome/status", 200, json)
            #expect(try await deadwax.call(Routes.navidromeStatus, as: NavidromeStatus.self) == status)
        }
    }
}
