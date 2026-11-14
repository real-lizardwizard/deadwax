import Foundation

/// The fill (notes/ios-specs/phase3-autodownload.md 2.6): which albums of your library fit on this phone, in the order
/// they come onto it (LibraryFollow.ordered), whole albums only, after every hand download - and which albums here
/// must give way. Pure.
///
/// - **Hand downloads first**: their bytes (here, and to come for the units Phase 2's planner lets go) are taken from
///   the limit before any album of the library, and they never give way.
/// - **The limit's budget**: the limit less the hand downloads (and whatever here the library can't give back). An album
///   that doesn't fit it waits `room`, and the next is tried: a big album never holds up smaller ones. An album with
///   bytes here that no longer fits it - the limit lowered, a hand download - is given back whole, from the bottom.
/// - **Hysteresis** (after the review): an album new to the phone fits only with `margin` to spare - 50 MB, or 1% of
///   the limit if more; one already asked for or here (`held`) keeps its place while it fits at all. So an album at the
///   edge isn't asked and then given way the moment its own cover, lyrics or a byte of estimate arrives - and nothing
///   is ever over the limit.
/// - **The phone's budget**: what the phone has above its 2 GB reserve once the hand downloads arrive, less what the
///   held albums have yet to receive (their claim comes first) - new albums fit only into that, with the margin. An
///   album here never needs more of the phone, so a new star above it never pushes it out.
/// - **The deficit**: only when the phone itself is under its reserve once the hand downloads arrive
///   (`free - handToCome < reserve`) do albums here give way - from the bottom, only as much as the deficit, and only
///   once the deficit has been seen on plans minutes apart (`deficitConfirmed`, `deficitSince`): one bad or momentary
///   free-space reading never deletes anything.
/// - Albums whose songs aren't read yet, and albums kept off, are skipped - neither fitting nor holding room - and
///   counted among every album of the library ("N of M"). An unread album here is never given way.
public enum LibraryFill {
    /// One album of the library, in the order.
    public struct AlbumFacts: Sendable, Equatable {
        public let id: String
        /// What it takes: its library songs (those also wanted by hand left out - they are counted as hand downloads),
        /// and its cover when the album is the library's alone (the allowance until its answer is kept); nil until its
        /// songs are read.
        public let bytes: Int64?
        /// Of those, the bytes on this phone now - its library-only songs and their cover.
        public let here: Int64
        /// Of its songs, the bytes not here yet.
        public let toCome: Int64
        /// A song of it carries the library's origin - asked for or here: it keeps its place while it fits at all.
        public let held: Bool
        /// Remove Download on it: left off this phone until downloaded again.
        public let keptOff: Bool

        /// `toCome` defaults to what isn't here of `bytes`; `held` to having bytes here.
        public init(id: String, bytes: Int64?, here: Int64 = 0, toCome: Int64? = nil, held: Bool? = nil,
                    keptOff: Bool = false) {
            self.id = id
            self.bytes = bytes
            self.here = here
            self.toCome = toCome ?? max((bytes ?? 0) - here, 0)
            self.held = held ?? (here > 0)
            self.keptOff = keptOff
        }

        /// Its bytes here are the library's to give back: read (or kept off), so the fill can give it way.
        public var givable: Bool { keptOff || bytes != nil }
    }

    /// What else the fill reads.
    public struct Facts: Sendable, Equatable {
        /// The hand downloads' bytes: here, plus to come for the units let go - and whatever here the library can't give
        /// back now (LibraryDownloads.turn).
        public var handBytes: Int64
        /// Of those, what is still to arrive.
        public var handToCome: Int64
        /// The storage limit in bytes; nil for No limit.
        public var limit: Int64?
        /// The phone's free space (`volumeAvailableCapacityForImportantUsage`).
        public var freeSpace: Int64
        /// What the phone must keep free.
        public var reserve: Int64
        /// The phone has been under its reserve on plans `deficitConfirmMs` or more apart: albums here give way for it.
        public var deficitConfirmed: Bool

        public init(handBytes: Int64 = 0, handToCome: Int64 = 0, limit: Int64?, freeSpace: Int64,
                    reserve: Int64 = DownloadPlan.reserve, deficitConfirmed: Bool = false) {
            self.handBytes = handBytes
            self.handToCome = handToCome
            self.limit = limit
            self.freeSpace = freeSpace
            self.reserve = reserve
            self.deficitConfirmed = deficitConfirmed
        }

        /// The hysteresis: what a new album must leave spare.
        public var margin: Int64 { LibraryFill.margin(limit: limit) }
        /// How far under its reserve the phone is once the hand downloads arrive; 0 when it isn't.
        public var deficit: Int64 { LibraryFill.deficit(freeSpace: freeSpace, handToCome: handToCome, reserve: reserve) }
    }

    /// Why an album of the library isn't on its way.
    public enum Wait: String, Sendable, CaseIterable {
        /// It doesn't fit the storage limit.
        case room
        /// It fits the limit, not the phone.
        case phoneFull = "phone_full"
        /// Its songs aren't read yet.
        case unread
        /// Remove Download on it.
        case keptOff = "kept_off"
    }

    /// What fits, what waits, what gives way.
    public struct Plan: Sendable, Equatable {
        /// The albums that fit, in the order.
        public let fits: [String]
        /// Every other album's reason.
        public let waits: [String: Wait]
        /// Albums with bytes here that don't fit: given back whole, in the order (the bottom last).
        public let giveWay: [String]
        /// What the albums that fit take.
        public let bytes: Int64
        /// Every album of the library - the "M" of "N of M".
        public let of: Int
        /// How far under its reserve the phone is once the hand downloads arrive (0: it isn't).
        public let deficit: Int64

        public init(fits: [String], waits: [String: Wait], giveWay: [String], bytes: Int64, of: Int, deficit: Int64 = 0) {
            self.fits = fits
            self.waits = waits
            self.giveWay = giveWay
            self.bytes = bytes
            self.of = of
            self.deficit = deficit
        }

        /// The "N" of "N of M".
        public var fit: Int { fits.count }
        public var allFit: Bool { fits.count == of }
        public func count(_ wait: Wait) -> Int { waits.values.reduce(0) { $0 + ($1 == wait ? 1 : 0) } }
    }

    // MARK: the numbers

    /// A new album must leave this much spare (the hysteresis): 50 MB, or 1% of the limit if more.
    public static func margin(limit: Int64?) -> Int64 { max(50_000_000, (limit ?? 0) / 100) }
    /// What an album's cover is counted at until its answer is kept (its actual bytes after): a 1024-pixel cover.
    public static let albumAllowance: Int64 = 1_000_000
    /// The phone under its reserve gives way only once seen on plans this far apart.
    public static let deficitConfirmMs: Int64 = 3 * 60_000

    /// How far under `reserve` the phone is once the hand downloads arrive; 0 when it isn't.
    public static func deficit(freeSpace: Int64, handToCome: Int64, reserve: Int64) -> Int64 {
        max(reserve - (freeSpace - max(handToCome, 0)), 0)
    }

    /// When the deficit was first seen, after a plan at `now` (a monotonic clock, ms) that saw one or not: a plan that
    /// sees none forgets it, so a momentary reading never adds up.
    public static func deficitSince(_ since: Int64?, deficit: Bool, now: Int64) -> Int64? {
        deficit ? (since ?? now) : nil
    }

    /// The deficit has held on plans `deficitConfirmMs` or more apart.
    public static func deficitConfirmed(since: Int64?, now: Int64) -> Bool {
        guard let since else { return false }
        return now - since >= deficitConfirmMs
    }

    /// What the library could give back of what is here: the bytes here of every album the fill can give way (read, or
    /// kept off) - an album being read again is never given way, and a library song on no album of the library isn't
    /// the fill's. The one number the fill and Phase 2's planner both count (DownloadPlan.Facts.libraryHere).
    public static func givable(_ albums: [AlbumFacts]) -> Int64 {
        albums.reduce(Int64(0)) { $0 + ($1.givable ? max($1.here, 0) : 0) }
    }

    // MARK: building

    /// The fill's albums from the library in the order (LibraryFollow.ordered): each album's bytes its songs' less those
    /// wanted by hand (`hand`: song ids with another origin - counted in the hand bytes) plus `extras` (its cover),
    /// `here` its library songs' bytes on the phone, `done` the songs here (what isn't is to come), `held` the albums
    /// with a song asked for or here under the library. A missing album stays in, as it was: it is in your library until
    /// two checks agree it isn't (2.3), so a star lost for a minute costs nothing.
    public static func albums(_ ordered: [FollowedAlbum], hand: Set<String> = [], here: [String: Int64] = [:],
                              done: Set<String>? = nil, held: Set<String>? = nil,
                              extras: [String: Int64] = [:]) -> [AlbumFacts] {
        ordered.map { entry in
            let extra = max(extras[entry.id] ?? 0, 0)
            let bytes = entry.songs.map { songs in
                songs.reduce(extra) { $0 + (hand.contains($1.id) ? 0 : $1.bytes) }
            }
            let atHand = here[entry.id] ?? 0
            let toCome: Int64? = done.map { done in
                (entry.songs ?? []).reduce(Int64(0)) { $0 + (hand.contains($1.id) || done.contains($1.id) ? 0 : $1.bytes) }
            }
            return AlbumFacts(id: entry.id, bytes: bytes, here: atHand, toCome: toCome,
                              held: held.map { $0.contains(entry.id) }, keptOff: entry.keptOff != nil)
        }
    }

    // MARK: the fill

    /// The fill of `albums` (in the order) under `facts`.
    public static func plan(_ albums: [AlbumFacts], _ facts: Facts) -> Plan {
        let margin = facts.margin
        let limitLeft: Int64? = facts.limit.map { $0 - facts.handBytes }
        var waits: [String: Wait] = [:]
        var giveWay = Set<String>()
        func wait(_ album: AlbumFacts, _ reason: Wait) {
            waits[album.id] = reason
            if album.here > 0 { giveWay.insert(album.id) }
        }

        // the limit: in the order, a new album with the margin to spare, a held one while it fits at all
        var usedLimit: Int64 = 0
        var underLimit: [(album: AlbumFacts, need: Int64)] = []
        for album in albums {
            if album.keptOff {
                wait(album, .keptOff)
                continue
            }
            guard let need = album.bytes.map({ max($0, 0) }) else {
                // nothing is known of what it takes: neither fitting, nor given way
                waits[album.id] = .unread
                continue
            }
            if let left = limitLeft, usedLimit + need > (album.held ? left : left - margin) {
                wait(album, .room)
                continue
            }
            usedLimit += need
            underLimit.append((album: album, need: need))
        }

        // the phone: the held albums keep their place - what they have yet to receive is theirs first; a new album fits
        // only into what is left above the reserve, with the margin to spare
        let above = facts.freeSpace - max(facts.handToCome, 0) - facts.reserve
        var room = above - underLimit.reduce(Int64(0)) { $0 + ($1.album.held ? max($1.album.toCome, 0) : 0) }
        var fits: [(album: AlbumFacts, need: Int64)] = []
        for (album, need) in underLimit {
            if album.held {
                fits.append((album: album, need: need))
                continue
            }
            let toCome = max(album.toCome, 0)
            if toCome + margin <= room {
                room -= toCome
                fits.append((album: album, need: need))
            } else {
                wait(album, .phoneFull)
            }
        }

        // the deficit: the phone itself under its reserve, seen on plans minutes apart - albums here give way from the
        // bottom, only as much as it
        let deficit = facts.deficit
        if deficit > 0, facts.deficitConfirmed {
            var freed: Int64 = 0
            for index in fits.indices.reversed() where freed < deficit {
                let album = fits[index].album
                guard album.here > 0 else { continue }
                freed += album.here
                wait(album, .phoneFull)
                fits.remove(at: index)
            }
        }

        let order = albums.map(\.id).filter { giveWay.contains($0) }
        return Plan(fits: fits.map(\.album.id), waits: waits, giveWay: order,
                    bytes: fits.reduce(Int64(0)) { $0 + $1.need }, of: albums.count, deficit: deficit)
    }
}
