import Foundation

/// The planner (spec 8.5): every song asked for and not yet here, the bytes here, the storage limit, the phone's free
/// space, whether deadwax can be reached and the network's facts, the setting, and the tasks out in; for each song, why
/// it waits and whether its task should be out. Pure; run at every ask, finish, failure, setting change, path change,
/// reachability change and coming to the front.
///
/// - **Units**: an album asked for as an album is planned whole - all of its songs not here fit, or it waits - so a
///   download never stops at half an album for room. A song asked for alone is a unit of its own.
/// - **Order**: by when each was asked (the unit's first), then disc and track. A unit that doesn't fit waits and the
///   next is tried - one big album never holds up small ones; when room comes, the oldest goes first.
/// - **Fits** when the bytes here, plus every unit let go, plus this one, are within the limit; and the phone's free
///   space, less what the units let go have yet to receive, less this one, leaves `reserve` free.
/// - **Started** units (a task out, bytes received, or resume data) go on whatever the limit: it was within it when
///   they began, and a download never stops at half an album for room. Nothing is ever evicted in Phase 2: hand
///   downloads never go by themselves (Choice 19) - a limit lowered below what's here makes new units wait `room`.
/// - **The waits**, in order: no network, deadwax unreachable, signed out, Wi-Fi only on mobile data, on a hotspot, in
///   Low Data Mode, then over the limit and under the reserve. A song let go is `queued` until its first byte.
/// - **Tasks under a network wait are still made** (no network, Wi-Fi only on mobile data, a hotspot, Low Data Mode),
///   with the request's own flags (`DownloadOver.access`): iOS holds them and starts them itself the moment the network
///   allows, the app running or not - the screens say the wait until the first byte. Not while deadwax can't be
///   reached, nor signed out: nothing would answer them.
public enum DownloadPlan {
    /// What the phone must keep free: 2 GB (the plan's reserve), as iOS's Storage counts.
    public static let reserve: Int64 = 2_000_000_000
    /// The most tasks out at once: an album's worth many times over, and no Up Next of thousands handed to iOS at once.
    public static let maxOut = 100

    /// One song asked for and not yet here.
    public struct Asked: Sendable, Equatable {
        public let id: String
        public let albumID: String
        public let disc: Int?
        public let track: Int?
        /// When it was asked for (ms), its earliest origin's.
        public let wantedAt: Int64
        public let origins: Set<DownloadOrigin>
        /// Its bytes expected (`DownloadRecord.expectedBytes`).
        public let expected: Int64
        /// Bytes its task has received so far.
        public let received: Int64
        /// A task is out for it.
        public let out: Bool
        /// Its interrupted fetch kept resume data.
        public let resumable: Bool

        public init(id: String, albumID: String, disc: Int? = nil, track: Int? = nil, wantedAt: Int64,
                    origins: Set<DownloadOrigin> = [.song], expected: Int64, received: Int64 = 0, out: Bool = false,
                    resumable: Bool = false) {
            self.id = id
            self.albumID = albumID
            self.disc = disc
            self.track = track
            self.wantedAt = wantedAt
            self.origins = origins
            self.expected = expected
            self.received = received
            self.out = out
            self.resumable = resumable
        }

        /// A record asked for and not here, with its task's bytes so far.
        public init(_ record: DownloadRecord, origins: Set<DownloadOrigin>, received: Int64 = 0) {
            self.init(id: record.id, albumID: record.albumID, disc: record.disc, track: record.track,
                      wantedAt: record.wantedAt, origins: origins, expected: record.expectedBytes, received: received,
                      out: record.state == .fetching, resumable: record.resume != nil)
        }

        /// The unit it is planned in: its album's when asked for with it, else its own.
        var unit: String {
            for origin in origins.sorted() {
                if case .album(let id) = origin { return "album:\(id)" }
            }
            return "song:\(id)"
        }

        var remaining: Int64 { max(expected - max(received, 0), 0) }
        var started: Bool { out || received > 0 || resumable }
    }

    /// Everything else the plan reads.
    public struct Facts: Sendable, Equatable {
        /// The songs here and the covers kept, in bytes.
        public var bytesHere: Int64
        /// The storage limit in bytes; nil for No limit.
        public var limit: Int64?
        /// The phone's free space (`volumeAvailableCapacityForImportantUsage`).
        public var freeSpace: Int64
        public var reach: Reach
        public var path: NetworkPath
        /// Someone is signed in (or logins are off): a 401 makes it false until they sign in again.
        public var signedIn: Bool
        public var over: DownloadOver

        public init(bytesHere: Int64, limit: Int64?, freeSpace: Int64, reach: Reach = .online,
                    path: NetworkPath = .wifiAtHome, signedIn: Bool = true, over: DownloadOver = .wifi) {
            self.bytesHere = bytesHere
            self.limit = limit
            self.freeSpace = freeSpace
            self.reach = reach
            self.path = path
            self.signedIn = signedIn
            self.over = over
        }
    }

    /// One song's part in the plan.
    public struct Decision: Sendable, Equatable {
        /// Why it waits - `queued` for a song let go (until its first byte).
        public let wait: DownloadWait
        /// Its task should be out: made now if it isn't, kept if it is. False with a task out: cancelled, its resume
        /// data kept.
        public let task: Bool

        public init(wait: DownloadWait, task: Bool) {
            self.wait = wait
            self.task = task
        }
    }

    /// The wait every song shares, from the network, deadwax and the setting - nil when nothing holds them all.
    public static func sharedWait(_ facts: Facts) -> DownloadWait? {
        switch facts.reach {
        case .noNetwork: return .connection
        case .unreachable: return .deadwax
        case .online: break
        }
        if !facts.path.satisfied { return .connection }
        if !facts.signedIn { return .signIn }
        guard facts.over == .wifi else { return nil }
        let path = facts.path
        if !path.wifi && (path.cellular || path.expensive) { return .wifi }
        if path.wifi && path.expensive { return .hotspot }
        if path.constrained { return .lowData }
        return nil
    }

    /// Each song's decision, by id.
    public static func plan(_ songs: [Asked], _ facts: Facts) -> [String: Decision] {
        let shared = sharedWait(facts)
        // a task is out, and stays out, under any wait but a sign-out's: a running task has its own answer
        let outsKept = shared != .signIn
        var units: [String: [Asked]] = [:]
        for song in songs { units[song.unit, default: []].append(song) }
        let order = units.keys.sorted { a, b in
            let x = units[a]!.map(\.wantedAt).min() ?? 0, y = units[b]!.map(\.wantedAt).min() ?? 0
            return x != y ? x < y : a < b
        }
        var committed = facts.bytesHere
        var pending: Int64 = 0
        var out = outsKept ? songs.filter(\.out).count : 0
        var made: [String: Decision] = [:]
        for key in order {
            let unit = units[key]!.sorted { a, b in
                if (a.disc ?? 0) != (b.disc ?? 0) { return (a.disc ?? 0) < (b.disc ?? 0) }
                if (a.track ?? 0) != (b.track ?? 0) { return (a.track ?? 0) < (b.track ?? 0) }
                return a.id < b.id
            }
            let need = unit.reduce(Int64(0)) { $0 + $1.remaining }
            var fitWait: DownloadWait?
            if !unit.contains(where: \.started) {
                if let limit = facts.limit, committed + need > limit {
                    fitWait = .room
                } else if facts.freeSpace - pending - need < reserve {
                    fitWait = .phoneFull
                }
            }
            if fitWait == nil {
                committed += need
                pending += need
            }
            for song in unit {
                if song.out {
                    made[song.id] = Decision(wait: shared ?? .queued, task: outsKept)
                    continue
                }
                guard fitWait == nil else {
                    made[song.id] = Decision(wait: shared ?? fitWait!, task: false)
                    continue
                }
                let mayMake = (shared == nil || shared!.isTheNetwork) && out < maxOut
                if mayMake { out += 1 }
                made[song.id] = Decision(wait: shared ?? .queued, task: mayMake)
            }
        }
        return made
    }
}
