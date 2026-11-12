import Foundation

/// Whether deadwax can be reached (spec 7.1): the phone's path, the requests' answers and a probe of `/deadwax/health`
/// in; the state and when to probe out. Pure - the monitor, the probe and its timer are the App's (Reachability).
///
/// - The path unsatisfied is `noNetwork` at once: nothing is tried.
/// - A request that gets no HTTP answer (an `APIFailure` offline or timeout) sets off a probe, with `probeTimeout`.
///   Two failures in a row - the request and its probe - make deadwax `unreachable`; so does one failed probe made
///   while deadwax already wasn't online (the network back, a path change, a pull). Then the probe runs every
///   `probeEvery` seconds, and at once whenever the path changes or someone asks (a pull, the banner's Try again).
/// - Any HTTP answer is deadwax reached - a 503 from a stopped poller included - and makes it `online` again.
/// - While `online`, a path change that leaves a network asks nothing: a request that fails says so, so a WireGuard
///   blip moves nothing at all.
public struct OfflineRule: Sendable, Equatable {
    /// The probe's time to answer, in seconds.
    public static let probeTimeout: Double = 3
    /// The probe's interval while deadwax is unreachable.
    public static let probeEvery: Double = 30

    public private(set) var reach: Reach = .online
    /// The path as the monitor last said - nil before its first.
    public private(set) var path: NetworkPath?
    /// A probe is out.
    public private(set) var probing = false
    /// When the next probe is due (seconds on the App's monotonic clock), while unreachable.
    public private(set) var nextProbe: Double?
    /// When deadwax last answered anything - a download's failure is a try only when deadwax answered since its task
    /// began (spec 8.3).
    public private(set) var lastAnswer: Double?
    /// Requests and probes without an answer since the last answer.
    private var failures = 0

    public init() {}

    /// What the App should do now.
    public enum Action: Sendable, Equatable {
        case nothing
        /// Ask `/deadwax/health` now, with `probeTimeout`.
        case probe
    }

    /// The monitor's path.
    public mutating func pathChanged(_ new: NetworkPath, now: Double) -> Action {
        path = new
        guard new.satisfied else {
            reach = .noNetwork
            failures = 0
            nextProbe = nil
            return .nothing
        }
        if reach == .online { return .nothing }
        return startProbe()
    }

    /// A request deadwax answered - any status at all.
    public mutating func answered(now: Double) {
        lastAnswer = now
        failures = 0
        nextProbe = nil
        if path?.satisfied != false { reach = .online }
    }

    /// A request nothing answered (not the probe's own).
    public mutating func noAnswer(now: Double) -> Action {
        guard path?.satisfied != false else { return .nothing }
        failures += 1
        return startProbe()
    }

    /// The probe answered.
    public mutating func probeAnswered(now: Double) {
        probing = false
        answered(now: now)
    }

    /// The probe got no answer.
    public mutating func probeFailed(now: Double) {
        probing = false
        guard path?.satisfied != false else { return }
        failures += 1
        if failures >= 2 || reach != .online { reach = .unreachable }
        nextProbe = reach == .unreachable ? now + Self.probeEvery : nil
    }

    /// The timer's tick: whether the 30 s probe is due.
    public mutating func tick(now: Double) -> Action {
        guard reach == .unreachable, let next = nextProbe, now >= next else { return .nothing }
        return startProbe()
    }

    /// Someone asked: a pull to refresh, the banner's Try again - a probe at once while deadwax isn't online.
    public mutating func askNow(now: Double) -> Action {
        guard path?.satisfied != false, reach != .online else { return .nothing }
        return startProbe()
    }

    /// Whether deadwax answered anything since `since`.
    public func answeredSince(_ since: Double) -> Bool { (lastAnswer ?? -.infinity) >= since }

    private mutating func startProbe() -> Action {
        guard !probing else { return .nothing }
        probing = true
        return .probe
    }
}

/// Plays kept while deadwax couldn't be reached, sent later (spec 7.6): only a play (`submission=true`, with its time) is
/// kept - "now playing" would be stale. Sent oldest first, one at a time, each forgotten on a 200.
public enum PendingPlays {
    /// What a send's answer means for the run.
    public enum After: Sendable, Equatable {
        /// Sent: forget it, send the next.
        case sent
        /// A 401: keep it and every one after, until the same person signs in again.
        case held
        /// Another 4xx (a song gone, a time refused): forget this one, send the next.
        case dropped
        /// A 5xx or no answer (nil): keep it, stop the run until the next.
        case stopped
    }

    public static func after(status: Int?) -> After {
        guard let status else { return .stopped }
        if (200..<300).contains(status) { return .sent }
        if status == 401 { return .held }
        if (400..<500).contains(status) { return .dropped }
        return .stopped
    }

    /// Whether a report that couldn't be sent is kept: a play, never "now playing".
    public static func keeps(_ report: PlayReport) -> Bool {
        if case .played = report { return true }
        return false
    }
}

/// Which list the Library's root shows (spec 5.4): your albums (or All albums) while deadwax answers, Downloaded while it
/// can't be reached - changed only while the root isn't on screen, so it never swaps under a finger.
public enum LibraryRootList: String, Sendable, Equatable {
    case albums
    case downloaded
}

public struct LibraryRoot: Sendable, Equatable {
    /// The list shown; nil before the first look.
    public private(set) var shown: LibraryRootList?

    public init() {}

    /// The list to draw, given whether deadwax can be reached and whether the root is on screen now. The first look
    /// (the app opening) takes the list it should; after that it changes only while the root isn't on screen - another
    /// tab, a page pushed over it, the app in the background.
    public mutating func look(online: Bool, onScreen: Bool) -> LibraryRootList {
        let wanted: LibraryRootList = online ? .albums : .downloaded
        if shown == nil || !onScreen { shown = wanted }
        return shown ?? wanted
    }
}

/// The Library's lists (spec 5.1): one of deadwax's scopes, or what is on this phone - which is never asked of deadwax,
/// so `AlbumScope` (which names kept files) is left alone.
public enum AlbumList: Sendable, Equatable, Hashable {
    case scope(AlbumScope)
    case downloaded

    /// Whose Recently added it is.
    public var addedBy: AddedBy {
        switch self {
        case .scope(let scope): return scope.addedBy
        case .downloaded: return .phone
        }
    }
}

/// The albums with a song on this phone, as the Library's lists draw them (spec 5.1): each album's kept answer made into
/// an `IndexAlbum`, its `created` the moment its first song arrived - so Recently added means downloaded to this phone.
public enum DownloadedAlbums {
    /// `albums` (the kept answers) with `arrived` (each album's first song's `done_at`, ms) - those with a song here.
    public static func index(_ albums: [Album], arrived: [String: Int64]) -> [IndexAlbum] {
        albums.compactMap { album in
            guard let at = arrived[album.id] else { return nil }
            return IndexAlbum(id: album.id, name: album.name, artist: album.artist, artistId: album.artistId,
                              coverArt: album.coverArt, year: album.year, genre: album.genre,
                              created: iso(ms: at), played: album.played, playCount: album.playCount,
                              starred: album.starred, musicBrainzId: album.musicBrainzId, songCount: album.songCount,
                              duration: album.duration)
        }
    }

    /// `ms` since 1970 as ISO 8601 in UTC, to the millisecond ("2026-11-12T09:30:00.250Z") - what AlbumTime.ms reads.
    public static func iso(ms: Int64) -> String {
        let day = Int64((Double(ms) / 86_400_000).rounded(.down))
        let inDay = ms - day * 86_400_000
        // days to a civil date (Howard Hinnant's days_from_civil, undone)
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        func two(_ n: Int64) -> String { String(n).zeroPadded(to: 2) }
        let seconds = inDay / 1000
        return "\(String(y).zeroPadded(to: 4))-\(two(m))-\(two(d))T\(two(seconds / 3600)):\(two(seconds / 60 % 60)):"
            + "\(two(seconds % 60)).\(String(inDay % 1000).zeroPadded(to: 3))Z"
    }
}

extension NavidromeGate {
    /// Whether the gate is consulted (spec 5.4): not while deadwax can't be reached - the Library's root is what is on
    /// this phone then, and the check runs again when deadwax answers.
    public static func consulted(_ reach: Reach) -> Bool { reach == .online }

    /// The gate closed while deadwax answers: its screen gains the Downloaded row whenever anything is on this phone -
    /// Navidrome being down is no reason to hide what plays from the phone.
    public static func showsDownloaded(_ shown: Shown, anythingHere: Bool) -> Bool {
        if case .closed = shown { return anythingHere }
        return false
    }
}
