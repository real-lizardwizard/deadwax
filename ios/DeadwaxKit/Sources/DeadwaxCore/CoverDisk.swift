import Foundation

/// (Speed A, fix 1 - notes/ios.md "Speed A: what's asked again") Covers kept on disk, as deadwax's headers say.
///
/// Until now every request the app made went through sessions that keep nothing (URLSessionTransport: ephemeral, no
/// cache), and covers lived only in memory (CoverCache's 96 MB), so a cold launch fetched every cover scrolled past
/// again - though deadwax marks Navidrome's covers as Navidrome does (a year for an id carrying the picture's hash,
/// revalidated otherwise, never a placeholder) and the Cover Art Archive's fronts for a week.
///
/// Decided here, so it is tested on Linux: which requests are covers - and only those go through the transport's cover
/// session, whose cache is on disk in Caches/`folder`, `diskBytes` at most. Everything else - the JSON, the audio, the
/// full-size cover the viewer reads - stays as it was: ephemeral and uncached.
public enum CoverDisk {
    /// The cache's folder, inside the app's Caches.
    public static let folder = "deadwax-covers"
    /// The most the cache keeps on disk, in bytes (a 400 px cover is 30-60 KB, so several thousand).
    public static let diskBytes = 256 * 1024 * 1024

    /// The routes whose answers are covers: Navidrome's, through deadwax (`Routes.cover`), and the Cover Art Archive's
    /// fronts through its relay (`Routes.archiveCover`).
    public static let routes: [Endpoint] = [Routes.cover, Routes.archiveCover]

    /// Whether `request` is a cover kept on disk: a GET of one of `routes`, read whole - never the viewer's full size
    /// (`mostBytes`, CoverZoom.fullMostBytes: up to 30 MB, read by its own capped session).
    public static func takes(_ request: HTTPRequest) -> Bool {
        guard request.method == "GET", request.mostBytes == nil else { return false }
        let path = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedPath
            ?? request.url.path
        return routes.contains { (route: Endpoint) -> Bool in route.method == "GET" && matches(path, route.path) }
    }

    /// `path` is the endpoint's template with each `{name}` one segment, none empty (DeadwaxClient.url encodes each as
    /// one segment, so a "/" in an id is `%2F` and never splits it).
    static func matches(_ path: String, _ template: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let wanted = template.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == wanted.count else { return false }
        for (part, want) in zip(parts, wanted) {
            if want.hasPrefix("{") && want.hasSuffix("}") {
                if part.isEmpty { return false }
            } else if part != want {
                return false
            }
        }
        return true
    }
}
