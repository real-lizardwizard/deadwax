import Foundation

/// The planner (spec 8.5): every song asked for and not yet here, the bytes here, the storage limit, the phone's free
/// space, whether deadwax can be reached and the network's facts, the setting, and the tasks out in; for each song, why
/// it waits and whether its task should be out. Pure; run at every ask, finish, failure, setting change, path change,
/// reachability change and coming to the front.
///
/// - **Units**: an album asked for as an album is planned whole - all of its songs not here fit, or it waits - so a
///   download never stops at half an album for room. A downloaded playlist's songs (Phase 4, slice 3) are planned
///   whole the same way, the storage limit and the reserve checked for all of them at once (phase4-library.md question
///   14) - those not yet started: one started goes on as itself (slice 3's review, `Asked.unit`). A song asked for
///   alone is a unit of its own.
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
/// - **Your library's units** (Phase 3, phase3-autodownload.md 2.7): a song wanted by the library alone is planned
///   with its album in a unit of the library's, after every hand unit, in the fill's order (`libraryRank`). Its room
///   under the limit is the fill's (LibraryFill) - only the phone's reserve is checked here. A hand unit's fit counts
///   the hand downloads alone: what the library could give back (`libraryHere` - LibraryFill.givable, the fill's own
///   number) is credited to it, so a hand download on a full phone is taken on (counted in `handToCome`) and the fill
///   makes the library give way for it - but its tasks are made only once the phone has the room as it is (after the
///   review), so a hand download never takes the phone under its reserve waiting for the library.
/// - **Tasks out** (after the review): at most `maxOut`, the hand units' first; the library's at most `libraryMaxOut`
///   and never more than the hand units leave - a library task beyond that is let go, its resume data kept, so a hand
///   download never queues behind the library's.
/// - **Only while charging** (Phase 3, slice 3, phase3-autodownload.md 2.8; open question 11, literal): on, the
///   library's units wait `charging` while the phone isn't - after the shared waits, before the room - their tasks out
///   let go with their resume data kept (an unplug cancels what the app can). Hand units never wait for it. And while
///   it is on, the library's tasks come from **one album at a time** (its first in the fill's order with a task out,
///   else the first that may have one, within the library's 20): iOS may run them with the app suspended, when an
///   unplug can't reach them - so an unplug overnight overruns by one album at most.
/// - **A stalled task doesn't hold the batch** (slice 3's review): a task out that has brought nothing for `stallMs`
///   (30 minutes - a background task can hang for days before it times out) is let go, its resume data kept, and made
///   again at the next plan; an album whose every task out has stalled isn't the batch, so the library moves on.
public enum DownloadPlan {
    /// What the phone must keep free: 2 GB (the plan's reserve), as iOS's Storage counts.
    public static let reserve: Int64 = 2_000_000_000
    /// The most tasks out at once: an album's worth many times over, and no Up Next of thousands handed to iOS at once.
    public static let maxOut = 100
    /// Of those, the most your library's may have: the hand downloads always have slots.
    public static let libraryMaxOut = 20
    /// (slice 3's review) A library task out that has brought nothing for this long is stalled: with Only while charging
    /// on it is let go, its resume data kept, and the batch doesn't wait for it.
    public static let stallMs: Int64 = 30 * 60_000

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
        /// Its album's place in the fill's order, for a song the library alone wants.
        public let libraryRank: Int?
        /// (slice 3's review) How long its task out has brought nothing, as far as this launch has seen (ms) - nil when
        /// not known.
        public let idleMs: Int64?

        public init(id: String, albumID: String, disc: Int? = nil, track: Int? = nil, wantedAt: Int64,
                    origins: Set<DownloadOrigin> = [.song], expected: Int64, received: Int64 = 0, out: Bool = false,
                    resumable: Bool = false, libraryRank: Int? = nil, idleMs: Int64? = nil) {
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
            self.libraryRank = libraryRank
            self.idleMs = idleMs
        }

        /// A record asked for and not here, with its task's bytes so far.
        public init(_ record: DownloadRecord, origins: Set<DownloadOrigin>, received: Int64 = 0, libraryRank: Int? = nil,
                    idleMs: Int64? = nil) {
            self.init(id: record.id, albumID: record.albumID, disc: record.disc, track: record.track,
                      wantedAt: record.wantedAt, origins: origins, expected: record.expectedBytes, received: received,
                      out: record.state == .fetching, resumable: record.resume != nil, libraryRank: libraryRank,
                      idleMs: idleMs)
        }

        /// Its task is out and has brought nothing for `stallMs`.
        public var stalled: Bool { out && (idleMs ?? 0) >= DownloadPlan.stallMs }

        /// The library alone wants it.
        public var isLibrary: Bool { DownloadOrigin.onlyLibrary(origins) }

        /// The unit it is planned in: the library's album for a song only the library wants; else its album's when
        /// asked for with it; else (Phase 4, slice 3) its downloaded playlist's - the first by id - planned whole, as an
        /// album is; else its own.
        ///
        /// (slice 3's review) A playlist's song already started - a task out, bytes in, resume data - goes on as a unit
        /// of its own, so the playlist's unit is only its songs not yet started, the limit and the reserve checked for
        /// them as one. A started song never makes the whole playlist "started": a song downloaded by hand, or the
        /// library's, still fetching as its playlist is downloaded would have let every song of it past the limit and
        /// the 2 GB the phone keeps - and so would one mid-fetch shared with another downloaded playlist, or a song
        /// added to a playlist already downloading.
        var unit: String {
            if isLibrary { return "library:\(albumID)" }
            for origin in origins.sorted() {
                if case .album(let id) = origin { return "album:\(id)" }
            }
            if let playlist = DownloadOrigin.playlists(origins).first {
                return started ? "song:\(id)" : "playlist:\(playlist)"
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
        /// Of those, the songs the library alone wants (Phase 3): the library's to give back.
        public var libraryHere: Int64
        /// The storage limit in bytes; nil for No limit.
        public var limit: Int64?
        /// The phone's free space (`volumeAvailableCapacityForImportantUsage`).
        public var freeSpace: Int64
        public var reach: Reach
        public var path: NetworkPath
        /// Someone is signed in (or logins are off): a 401 makes it false until they sign in again.
        public var signedIn: Bool
        public var over: DownloadOver
        /// (Phase 3, slice 3) Only while charging is on.
        public var onlyWhileCharging: Bool
        /// The phone is charging, or full on the charger (PowerState.charging).
        public var charging: Bool

        public init(bytesHere: Int64, libraryHere: Int64 = 0, limit: Int64?, freeSpace: Int64, reach: Reach = .online,
                    path: NetworkPath = .wifiAtHome, signedIn: Bool = true, over: DownloadOver = .wifi,
                    onlyWhileCharging: Bool = false, charging: Bool = false) {
            self.bytesHere = bytesHere
            self.libraryHere = libraryHere
            self.limit = limit
            self.freeSpace = freeSpace
            self.reach = reach
            self.path = path
            self.signedIn = signedIn
            self.over = over
            self.onlyWhileCharging = onlyWhileCharging
            self.charging = charging
        }

        /// Only while charging holds the library's songs now: on, and the phone isn't charging.
        public var libraryWaitsToCharge: Bool { onlyWhileCharging && !charging }
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

    /// The units in the order they are planned, why each that doesn't fit waits - the room and the phone's reserve,
    /// before any shared wait - and the hand units taken on (`taken`: they fit, the library's bytes here credited),
    /// some of which may still wait for the phone's room as it is.
    static func walk(_ songs: [Asked], _ facts: Facts)
        -> (order: [String], units: [String: [Asked]], waits: [String: DownloadWait], taken: Set<String>) {
        var units: [String: [Asked]] = [:]
        for song in songs { units[song.unit, default: []].append(song) }
        func rank(_ key: String) -> Int { units[key]!.compactMap(\.libraryRank).min() ?? Int.max }
        let order = units.keys.sorted { a, b in
            let libraryA = a.hasPrefix("library:"), libraryB = b.hasPrefix("library:")
            // every hand unit before the library's
            if libraryA != libraryB { return !libraryA }
            if libraryA {
                let x = rank(a), y = rank(b)
                return x != y ? x < y : a < b
            }
            let x = units[a]!.map(\.wantedAt).min() ?? 0, y = units[b]!.map(\.wantedAt).min() ?? 0
            return x != y ? x < y : a < b
        }
        // the hand downloads' room: what the library could give back is the library's to give
        let credit = max(facts.libraryHere, 0)
        var committed = facts.bytesHere - credit
        var pending: Int64 = 0
        var waits: [String: DownloadWait] = [:]
        var taken = Set<String>()
        for key in order {
            let unit = units[key]!
            let library = key.hasPrefix("library:")
            let need = unit.reduce(Int64(0)) { $0 + $1.remaining }
            let started = unit.contains(where: \.started)
            // the library's, unplugged with Only while charging on: it waits for the charger, started or not, and holds
            // no room meanwhile
            if library, facts.libraryWaitsToCharge {
                waits[key] = .charging
                continue
            }
            var fitWait: DownloadWait?
            if !started {
                if library {
                    // its room under the limit is the fill's: only the phone, as it is now
                    if facts.freeSpace - pending - need < reserve { fitWait = .phoneFull }
                } else if let limit = facts.limit, committed + need > limit {
                    fitWait = .room
                } else if facts.freeSpace + credit - pending - need < reserve {
                    fitWait = .phoneFull
                }
            }
            if let fitWait {
                waits[key] = fitWait
                continue
            }
            if !library {
                committed += need
                taken.insert(key)
                // taken on with the library's bytes credited: its tasks wait until the phone has the room as it is
                if !started, facts.freeSpace - pending - need < reserve { waits[key] = .phoneFull }
            }
            pending += need
        }
        return (order, units, waits, taken)
    }

    /// What the hand downloads that fit have yet to receive - the fill's `handToCome` (LibraryFill.Facts).
    public static func handToCome(_ songs: [Asked], _ facts: Facts) -> Int64 {
        let walked = walk(songs, facts)
        var total: Int64 = 0
        for key in walked.order where walked.taken.contains(key) {
            total += walked.units[key]!.reduce(Int64(0)) { $0 + $1.remaining }
        }
        return total
    }

    /// Each song's decision, by id.
    public static func plan(_ songs: [Asked], _ facts: Facts) -> [String: Decision] {
        let shared = sharedWait(facts)
        // a task is out, and stays out, under any wait but a sign-out's: a running task has its own answer
        let outsKept = shared != .signIn
        let walked = walk(songs, facts)
        let canMake = shared == nil || shared!.isTheNetwork
        // the hand units' tasks first (they come first in the order) - those out counted from the start, as Phase 2
        // counts them - then the library's, in what they leave
        var handOut = outsKept ? songs.filter { (song: Asked) -> Bool in song.out && !song.isLibrary }.count : 0
        var libraryOut = 0
        var libraryCap: Int?
        // the library's tasks out that stay: the first of them in its order, within its slots - kept before any new
        // one is made, so a running task isn't let go for another
        var libraryKept = Set<String>()
        // Only while charging on: the one album whose tasks may be out - its first with a task out, else the first that
        // may make one (set as it is reached)
        var batch: String?
        var made: [String: Decision] = [:]
        for key in walked.order {
            let library = key.hasPrefix("library:")
            if library, libraryCap == nil {
                let cap = max(min(libraryMaxOut, maxOut - handOut), 0)
                libraryCap = cap
                if outsKept {
                    var units = walked.order.filter { (unit: String) -> Bool in
                        unit.hasPrefix("library:") && walked.waits[unit] != .charging
                    }
                    if facts.onlyWhileCharging {
                        // the batch: an album with a task out that hasn't stalled - one whose every task has, isn't
                        batch = units.first { (unit: String) -> Bool in
                            walked.units[unit]!.contains { (song: Asked) -> Bool in song.out && !song.stalled }
                        }
                        units = batch.map { [$0] } ?? []
                    }
                    let outs = units.flatMap { (unit: String) -> [Asked] in
                        walked.units[unit]!.filter { (song: Asked) -> Bool in
                            song.out && !(facts.onlyWhileCharging && song.stalled)
                        }.sorted { a, b in a.id < b.id }
                    }
                    libraryKept = Set(outs.prefix(cap).map(\.id))
                }
                libraryOut = libraryKept.count
            }
            let unit = walked.units[key]!.sorted { a, b in
                if (a.disc ?? 0) != (b.disc ?? 0) { return (a.disc ?? 0) < (b.disc ?? 0) }
                if (a.track ?? 0) != (b.track ?? 0) { return (a.track ?? 0) < (b.track ?? 0) }
                return a.id < b.id
            }
            let fitWait = walked.waits[key]
            for song in unit {
                if song.out, fitWait == .charging {
                    // unplugged with Only while charging on: let go, its resume data kept
                    made[song.id] = Decision(wait: shared ?? .charging, task: false)
                    continue
                }
                if song.out {
                    // a task out stays out (but a sign-out's) - a library task only within the library's slots
                    let keep = outsKept && (!library || libraryKept.contains(song.id))
                    made[song.id] = Decision(wait: shared ?? .queued, task: keep)
                    continue
                }
                if let fitWait {
                    made[song.id] = Decision(wait: shared ?? fitWait, task: false)
                    continue
                }
                var mayMake = canMake && (library ? libraryOut < libraryCap! : handOut < maxOut)
                // Only while charging on: one album at a time - the first reached that may make a task is the batch
                if mayMake, library, facts.onlyWhileCharging {
                    if batch == nil { batch = key }
                    mayMake = batch == key
                }
                if mayMake {
                    if library { libraryOut += 1 } else { handOut += 1 }
                }
                made[song.id] = Decision(wait: shared ?? .queued, task: mayMake)
            }
        }
        return made
    }
}
