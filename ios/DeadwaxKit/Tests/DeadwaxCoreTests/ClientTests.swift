import Foundation
import Testing
@testable import DeadwaxCore

/// A transport that answers from a table and remembers what was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: HTTPResponse] = [:]
    private var unreachable = false
    private(set) var sent: [HTTPRequest] = []

    func answer(_ path: String, _ status: Int, _ json: String, headers: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        answers[path] = HTTPResponse(status: status, headers: headers, body: Data(json.utf8))
    }

    func goAway() {
        lock.lock(); defer { lock.unlock() }
        unreachable = true
    }

    var last: HTTPRequest? {
        lock.lock(); defer { lock.unlock() }
        return sent.last
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            sent.append(request)
            if unreachable { throw URLError(.cannotConnectToHost) }
            return answers[request.url.path] ?? HTTPResponse(status: 404, body: Data(#"{"detail":"Not Found"}"#.utf8))
        }
    }
}

func client(session: String? = nil) -> (DeadwaxClient, FakeTransport) {
    let transport = FakeTransport()
    let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    return (DeadwaxClient(server: server, session: session, transport: transport), transport)
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
        #expect(transport.last?.headers["Cookie"] == nil)
    }

    @Test func a401IsSignedOutWithDeadwaxsWords() async throws {
        let (deadwax, transport) = client(session: "s.old")
        transport.answer("/deadwax/me", 401, #"{"detail":"Your session has ended. Sign in again."}"#)
        await #expect(throws: DeadwaxError.signedOut("Your session has ended. Sign in again.")) {
            try await deadwax.me()
        }
        #expect(transport.last?.headers["Cookie"] == "deadwax_session=s.old")
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
        let (deadwax, transport) = client()
        transport.answer("/deadwax/auth/login", 401, #"{"detail":"That user name and password don't match."}"#)
        await #expect(throws: DeadwaxError.refused(status: 401, detail: "That user name and password don't match.")) {
            _ = try await deadwax.signIn(username: "james", password: "wrong")
        }
    }

    @Test func aSignInWithNoCookieIsSaid() async throws {
        let (deadwax, transport) = client()
        transport.answer("/deadwax/auth/login", 200, #"{"user":"james","admin":false,"auth":"on"}"#)
        await #expect(throws: DeadwaxError.self) { _ = try await deadwax.signIn(username: "james", password: "x") }
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

    @Test func theStreamIsTheFileAsItIsWithTheSession() throws {
        let (deadwax, _) = client(session: "s.xyz")
        let request = deadwax.streamRequest(songID: "a/b?c", format: "raw")
        #expect(request.url.absoluteString == "http://192.168.3.20:8090/deadwax/navidrome/stream/a%2Fb%3Fc?format=raw")
        #expect(request.headers["Cookie"] == "deadwax_session=s.xyz")
        #expect(request.method == "GET")
    }

    @Test func onlyDeclaredQueryNamesAreSent() {
        let (deadwax, _) = client()
        let url = deadwax.url(Routes.stream, path: ["song_id": "x"], query: [("format", "raw"), ("u", "forged")])
        #expect(url.query == "format=raw")
    }

    @Test func nothingAnsweringIsUnreachableWithWhatToCheck() async {
        let (deadwax, transport) = client()
        transport.goAway()
        do {
            _ = try await deadwax.health()
            Issue.record("expected a failure")
        } catch let error as DeadwaxError {
            guard case .unreachable(let words) = error else {
                Issue.record("not unreachable: \(error)")
                return
            }
            #expect(words.hasPrefix("Couldn't reach deadwax at http://192.168.3.20:8090."))
            #expect(words.contains("Local Network"))
        } catch {
            Issue.record("not a DeadwaxError: \(error)")
        }
    }

    @Test func detailIsDeadwaxsOwnWordsOrTheStatus() {
        #expect(detailWords(Data(#"{"detail":"Logins are off."}"#.utf8), status: 409) == "Logins are off.")
        #expect(detailWords(Data(#"{"detail":[{"msg":"field required"},{"msg":"too long"}]}"#.utf8), status: 422)
                == "field required too long")
        #expect(detailWords(Data("<html>".utf8), status: 502) == "deadwax answered 502 and said nothing more.")
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
        } catch let error as DeadwaxError {
            guard case .unreadable(let words) = error else {
                Issue.record("not unreadable: \(error)")
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
        await #expect(throws: DeadwaxError.refused(status: 503, detail: "deadwax answered 503 and said nothing more.")) {
            try await deadwax.health()
        }
    }

    @Test func everyRouteIsDeadwaxsOwn() {
        #expect(Routes.all.count == 7)
        for endpoint in Routes.all {
            #expect(endpoint.path.hasPrefix("/deadwax/"))
            #expect(["GET", "POST"].contains(endpoint.method))
        }
    }
}
