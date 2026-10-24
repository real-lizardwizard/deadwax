import Foundation

/// One deadwax route the app calls: its method, its path as the server declares it (path
/// parameters in braces, named as in src/), and the query parameters the app may send.
///
/// tests/test_ios_contract.py reads the `Endpoint(...)` lines below from this file and checks each
/// against the server's own routes, so a route renamed or a parameter dropped on the server fails
/// in the Python suite, where the server is changed. Keep each on one line, in this exact form.
public struct Endpoint: Sendable, Equatable {
    public let method: String
    public let path: String
    public let query: [String]

    public init(method: String, path: String, query: [String]) {
        self.method = method
        self.path = path
        self.query = query
    }
}

public enum Routes {
    public static let health = Endpoint(method: "GET", path: "/deadwax/health", query: [])
    public static let me = Endpoint(method: "GET", path: "/deadwax/me", query: [])
    public static let signIn = Endpoint(method: "POST", path: "/deadwax/auth/login", query: [])
    public static let signOut = Endpoint(method: "POST", path: "/deadwax/auth/logout", query: [])
    public static let search = Endpoint(method: "GET", path: "/deadwax/navidrome/search", query: ["q", "artistCount", "albumCount", "songCount", "songOffset"])
    public static let stream = Endpoint(method: "GET", path: "/deadwax/navidrome/stream/{song_id}", query: ["format"])
    public static let cover = Endpoint(method: "GET", path: "/deadwax/navidrome/cover/{cover_id}", query: ["size"])

    /// Every route the app calls - what the contract test checks.
    public static let all: [Endpoint] = [health, me, signIn, signOut, search, stream, cover]
}

/// The cover size the lock screen asks for (`Routes.cover`'s `size`) - the contract test checks it is
/// within the server's bounds, as it does the search's page sizes (`TestSounds`, `HiRes`).
public enum CoverSize {
    public static let lockScreen = 1024
}

/// The fields a sign-in sends (src/routes/auth.py `SignIn`). The contract test checks them too.
public struct SignInBody: Codable, Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}
