import Foundation

/// (Speed A, fix 1 - notes/ios.md "Speed A: what's asked again") Covers kept on disk, as deadwax's headers say - a day
/// at most.
///
/// Until now every request the app made went through sessions that keep nothing (URLSessionTransport: ephemeral, no
/// cache), and covers lived only in memory (CoverCache's 96 MB), so a cold launch fetched every cover scrolled past
/// again - though deadwax marks Navidrome's covers as Navidrome does (a year for an id carrying the picture's hash,
/// revalidated otherwise, never a placeholder) and the Cover Art Archive's fronts for a week.
///
/// Decided here, so it is tested on Linux: which requests are covers (`takes`), the request each is kept under (`key`: its
/// address alone, never a header - so deadwax's session, sent by hand as `Cookie:`, is never written to disk beside it),
/// what is kept of an answer (`kept`: a 200's `keptHeaders` and when, never Set-Cookie), and what a kept cover asks
/// (`ask`: nothing while fresh, a day at most, else deadwax with its validators). The app's transport does the reading
/// and writing, by hand: URLSession itself never stores anything (after review - URLCache storing on its own kept each
/// request with its headers, the cookie among them). Everything else - the JSON, the audio, the full-size cover the
/// viewer reads, a downloaded album's cover - stays as it was: ephemeral and uncached.
public enum CoverDisk {
    /// The cache's folder, inside the app's Caches.
    public static let folder = "deadwax-cover-disk"
    /// The first build's folder, where URLCache stored covers on its own - each with the request it answered, headers
    /// and all: removed wherever it is found, the session's cookie with it.
    public static let oldFolder = "deadwax-covers"
    /// The most the cache keeps on disk, in bytes (a 400 px cover is 30-60 KB, so several thousand).
    public static let diskBytes = 256 * 1024 * 1024
    /// The longest a kept cover is drawn without asking deadwax, in seconds: a day, whatever the answer said. Navidrome's
    /// year (`immutable`, for an id carrying the picture's hash) is trusted no further, so a cover replaced under an id
    /// that didn't move is right again within a day.
    public static let freshMost = 24 * 60 * 60
    /// The header a kept answer carries saying when it was kept (seconds since 1970) - the copy's own, never sent.
    public static let keptAtHeader = "X-Deadwax-Kept-At"
    /// The headers of an answer kept with it: what it is and how long it stands. Nothing else - never Set-Cookie.
    public static let keptHeaders = ["Content-Type", "Cache-Control", "ETag", "Last-Modified"]

    /// The routes whose answers are covers: Navidrome's, through deadwax (`Routes.cover`), and the Cover Art Archive's
    /// fronts through its relay (`Routes.archiveCover`).
    public static let routes: [Endpoint] = [Routes.cover, Routes.archiveCover]

    /// Whether `request` is a cover kept on disk: a GET of one of `routes`, read whole - never the viewer's full size
    /// (`mostBytes`, CoverZoom.fullMostBytes: up to 30 MB, read by its own capped session) - that may be kept
    /// (`mayKeepOnDisk`: not a download's) and isn't a revalidation of a copy its caller keeps (that is the caller's).
    public static func takes(_ request: HTTPRequest) -> Bool {
        guard request.method == "GET", request.mostBytes == nil, request.mayKeepOnDisk,
              header("If-None-Match", in: request.headers) == nil,
              header("If-Modified-Since", in: request.headers) == nil else { return false }
        let path = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedPath
            ?? request.url.path
        return routes.contains { (route: Endpoint) -> Bool in route.method == "GET" && matches(path, route.path) }
    }

    /// The request a cover is kept and looked up under: its address alone - a GET with no header at all, so nothing
    /// sent with the cover (deadwax's session as `Cookie:`, an Accept) is ever written to disk beside it.
    public static func key(_ request: HTTPRequest) -> HTTPRequest {
        HTTPRequest(method: "GET", url: request.url)
    }

    /// What a cover kept on disk asks.
    public enum Ask: Equatable, Sendable {
        /// the copy kept is the answer: nothing asked
        case kept
        /// deadwax asked with these headers added - the copy's validators; a 304 is the copy kept
        case revalidate([String: String])
        /// deadwax asked as the request is
        case fetch
    }

    /// What a cover asks, `held` the headers of the copy kept (nil for none): nothing while it stands - kept less than
    /// its max-age ago, a day at most (`freshSeconds`) - else deadwax, with its ETag and Last-Modified to answer a 304
    /// by. A copy kept "later" than now (the clock moved back) has stopped standing.
    public static func ask(held: [String: String]?, now: Double) -> Ask {
        guard let held else { return .fetch }
        if let at = header(keptAtHeader, in: held).flatMap({ (text: String) -> Double? in Double(text) }),
           let fresh = freshSeconds(header("Cache-Control", in: held)),
           now >= at, now - at < Double(fresh) {
            return .kept
        }
        var validators: [String: String] = [:]
        if let etag = header("ETag", in: held), !etag.isEmpty { validators["If-None-Match"] = etag }
        if let modified = header("Last-Modified", in: held), !modified.isEmpty { validators["If-Modified-Since"] = modified }
        return validators.isEmpty ? .fetch : .revalidate(validators)
    }

    /// What is kept of an answer: its `keptHeaders` and when it was kept - nil when it isn't kept: anything but a 200,
    /// or one whose Cache-Control says no-store (Navidrome's placeholder for art it hasn't resolved yet).
    public static func kept(status: Int, headers: [String: String], now: Double) -> [String: String]? {
        guard status == 200, freshSeconds(header("Cache-Control", in: headers)) != nil else { return nil }
        return stamped(keptHeaders.compactMap { (name: String) -> (String, String)? in
            header(name, in: headers).map { (name, $0) }
        }, now: now)
    }

    /// A copy deadwax said still stands (its 304): kept again as of now, the 304's own Cache-Control and validators over
    /// the copy's - nil when the 304 says no-store, and the copy goes.
    public static func revalidated(_ held: [String: String], by answer: [String: String], now: Double) -> [String: String]? {
        let merged = keptHeaders.compactMap { (name: String) -> (String, String)? in
            // a 304's Content-Type, if it sends one, says nothing of the body it didn't send
            let theirs = name == "Content-Type" ? nil : header(name, in: answer)
            return (theirs ?? header(name, in: held)).map { (name, $0) }
        }
        guard freshSeconds(merged.first { $0.0 == "Cache-Control" }?.1) != nil else { return nil }
        return stamped(merged, now: now)
    }

    /// How long an answer stands, in seconds, by its Cache-Control: its max-age, a day at most (`freshMost`); 0 - asked
    /// again, with its validators, each time it is drawn - for no-cache or none said; nil for no-store, never kept.
    public static func freshSeconds(_ cacheControl: String?) -> Int? {
        guard let cacheControl else { return 0 }
        var seconds = 0
        var revalidate = false
        for part in cacheControl.split(separator: ",") {
            let directive = part.trimmingCharacters(in: .whitespaces).lowercased()
            if directive == "no-store" { return nil }
            if directive == "no-cache" || directive.hasPrefix("no-cache=") { revalidate = true }
            if directive.hasPrefix("max-age=") {
                let value = directive.dropFirst("max-age=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                seconds = max(Int(value) ?? 0, 0)
            }
        }
        return revalidate ? 0 : min(seconds, freshMost)
    }

    private static func stamped(_ headers: [(String, String)], now: Double) -> [String: String] {
        var kept = Dictionary(headers, uniquingKeysWith: { (first: String, _: String) -> String in first })
        kept[keptAtHeader] = String(now)
        return kept
    }

    /// A header by its name, whatever its case.
    static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { (each: (key: String, value: String)) -> Bool in
            each.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
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
