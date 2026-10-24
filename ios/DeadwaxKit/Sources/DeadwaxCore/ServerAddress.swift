import Foundation

/// The address of a deadwax, as typed once on the phone - `192.168.3.20:8090`, `bearded-dragon:8090`,
/// `http://deadwax.lan:8090/player/` - made into the one base URL every route is built on.
///
/// deadwax's routes are absolute (`/deadwax/...`), so only the scheme, host and port are kept: a
/// pasted web-app link (`.../player/`) is the same server. No scheme means http, since that is how
/// deadwax is reached on a home network and over WireGuard; https is kept when typed.
public struct ServerAddress: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// `http://host:port`, with no path and no trailing slash.
    public let base: URL

    public init(base: URL) { self.base = base }

    public var description: String { base.absoluteString }

    /// What was typed, read as an address - or the reason it can't be one, in words.
    public static func parse(_ typed: String) -> Result<ServerAddress, DeadwaxError> {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return .failure(.badAddress("Type deadwax's address, for example http://192.168.1.20:8090."))
        }
        if text.contains(where: { $0.isWhitespace }) {
            return .failure(.badAddress("An address has no spaces in it: \(text)"))
        }
        let withScheme = text.contains("://") ? text : "http://" + text
        guard let parts = URLComponents(string: withScheme), let scheme = parts.scheme?.lowercased() else {
            return .failure(.badAddress("That isn't an address deadwax can be reached at: \(text)"))
        }
        guard scheme == "http" || scheme == "https" else {
            return .failure(.badAddress("deadwax is reached over http (or https), not \(scheme)."))
        }
        guard let host = parts.host, !host.isEmpty else {
            return .failure(.badAddress("That address has no server name or IP in it: \(text)"))
        }
        if let port = parts.port, !(1...65535).contains(port) {
            return .failure(.badAddress("\(port) isn't a port number (1 to 65535)."))
        }
        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = parts.port
        // and a route's URL must be buildable on it (DeadwaxClient.url), or every request would miss
        var route = base
        route.percentEncodedPath = "/deadwax/health"
        guard let url = base.url, route.url != nil else {
            return .failure(.badAddress("That isn't an address deadwax can be reached at: \(text)"))
        }
        return .success(ServerAddress(base: url))
    }

    /// A key for what is kept per server (the session in the Keychain): the base, lowercased.
    public var key: String { base.absoluteString.lowercased() }
}
