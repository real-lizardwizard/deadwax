import Foundation

/// Which redirects the app follows (Phase 8, slice 10's review): only to the very address it asked - the same scheme, host
/// and port. Every request carries deadwax's session by hand as `Cookie:`, and a sign-in or Change password a password in
/// its body; URLSession following a 307 or 308 elsewhere would send both to whoever the redirect names. So one to another
/// scheme, host or port is refused, and its 3xx is the answer; one within deadwax's own address is followed as before.
///
/// The app's sessions ask this as each redirect comes (URLSessionTransport's, its streams', a capped read's, the probe's,
/// the player's StreamFetch). The downloads' background session can't be asked - iOS follows a background task's
/// redirects itself - so a download whose answer came from another origin is refused when it finishes (DownloadSession).
public enum Redirects {
    /// A URL's origin as a redirect is judged by: its scheme and host, lowercased, and its port - the scheme's own where
    /// it names none. Nil for one without a scheme or host, or an unknown scheme naming no port: never followed.
    public struct Origin: Sendable, Equatable {
        public let scheme: String
        public let host: String
        public let port: Int
    }

    public static func origin(_ url: URL?) -> Origin? {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard let port = parts.port ?? defaultPort(scheme) else { return nil }
        return Origin(scheme: scheme, host: host, port: port)
    }

    private static func defaultPort(_ scheme: String) -> Int? {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    /// Whether a redirect from a request to `asked` on to `next` is followed: both have an origin, and it is the same.
    public static func follows(from asked: URL?, to next: URL?) -> Bool {
        guard let from = origin(asked), let to = origin(next) else { return false }
        return from == to
    }
}
