import Foundation

/// The fill (notes/ios-specs/phase3-autodownload.md 2.6): which albums of your library fit on this phone, in the order
/// they come onto it (LibraryFollow.ordered), whole albums only, after every hand download - and which albums here
/// must give way. Pure.
///
/// - **Hand downloads first**: their bytes (here, and to come for the units Phase 2's planner lets go) are taken from
///   the limit before any album of the library, and they never give way.
/// - **Two budgets**: the limit's - the limit less the hand downloads; and the phone's - its free space, plus the
///   library's bytes already here (they would be given back), less what hand downloads have yet to receive, less the
///   2 GB reserve. An album fits when its whole bytes fit what's left of both.
/// - An album that doesn't fit the limit's waits `room`, and the next is tried: a big album never holds up smaller
///   ones. One that fits the limit's but not the phone's waits `phoneFull` and keeps its room under the limit, so room
///   on the phone resumes it without moving anything else.
/// - **Giving way**: an album with bytes here that doesn't fit is given back whole - a lowered limit, or the phone under
///   its reserve, takes from the bottom. While the phone keeps its reserve, nothing here gives way for it.
/// - Albums whose songs aren't read yet, and albums kept off, are skipped - neither fitting nor holding room - and
///   counted among every album of the library ("N of M").
public enum LibraryFill {
    /// One album of the library, in the order.
    public struct AlbumFacts: Sendable, Equatable {
        public let id: String
        /// What its library songs take - the songs also wanted by hand left out (they are counted as hand downloads);
        /// nil until its songs are read.
        public let bytes: Int64?
        /// Of those, the bytes on this phone now.
        public let here: Int64
        /// Remove Download on it: left off this phone until downloaded again.
        public let keptOff: Bool

        public init(id: String, bytes: Int64?, here: Int64 = 0, keptOff: Bool = false) {
            self.id = id
            self.bytes = bytes
            self.here = here
            self.keptOff = keptOff
        }
    }

    /// What else the fill reads.
    public struct Facts: Sendable, Equatable {
        /// The hand downloads' bytes: here, plus to come for the units let go.
        public var handBytes: Int64
        /// Of those, what is still to arrive.
        public var handToCome: Int64
        /// The storage limit in bytes; nil for No limit.
        public var limit: Int64?
        /// The phone's free space (`volumeAvailableCapacityForImportantUsage`).
        public var freeSpace: Int64
        /// What the phone must keep free.
        public var reserve: Int64

        public init(handBytes: Int64 = 0, handToCome: Int64 = 0, limit: Int64?, freeSpace: Int64,
                    reserve: Int64 = DownloadPlan.reserve) {
            self.handBytes = handBytes
            self.handToCome = handToCome
            self.limit = limit
            self.freeSpace = freeSpace
            self.reserve = reserve
        }
    }

    /// Why an album of the library isn't on its way.
    public enum Wait: String, Sendable, CaseIterable {
        /// It doesn't fit the storage limit.
        case room
        /// It fits the limit, not the phone: it holds its place under the limit.
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

        /// The "N" of "N of M".
        public var fit: Int { fits.count }
        public var allFit: Bool { fits.count == of }
        public func count(_ wait: Wait) -> Int { waits.values.reduce(0) { $0 + ($1 == wait ? 1 : 0) } }
    }

    /// The fill's albums from the library in the order (LibraryFollow.ordered): each album's bytes its songs' less those
    /// wanted by hand (`hand`: song ids with another origin - counted in the hand bytes), `here` its library songs'
    /// bytes on the phone. A missing album stays in, as it was: it is in your library until two checks agree it isn't
    /// (2.3), so a star lost for a minute costs nothing.
    public static func albums(_ ordered: [FollowedAlbum], hand: Set<String> = [],
                              here: [String: Int64] = [:]) -> [AlbumFacts] {
        ordered.map { entry in
            let bytes = entry.songs.map { songs in
                songs.reduce(Int64(0)) { $0 + (hand.contains($1.id) ? 0 : $1.bytes) }
            }
            return AlbumFacts(id: entry.id, bytes: bytes, here: here[entry.id] ?? 0, keptOff: entry.keptOff != nil)
        }
    }

    /// The fill of `albums` (in the order) under `facts`.
    public static func plan(_ albums: [AlbumFacts], _ facts: Facts) -> Plan {
        // what the library could give back: an unread album's bytes here aren't (it is never given way while its songs
        // are read again)
        let libraryHere = albums.reduce(Int64(0)) { $0 + ($1.keptOff || $1.bytes != nil ? max($1.here, 0) : 0) }
        let limitLeft: Int64? = facts.limit.map { $0 - facts.handBytes }
        let phoneLeft = facts.freeSpace + libraryHere - facts.handToCome - facts.reserve
        var usedLimit: Int64 = 0
        var usedPhone: Int64 = 0
        var fits: [String] = []
        var waits: [String: Wait] = [:]
        var giveWay: [String] = []
        var bytes: Int64 = 0
        for album in albums {
            func wait(_ reason: Wait) {
                waits[album.id] = reason
                if album.here > 0 { giveWay.append(album.id) }
            }
            if album.keptOff {
                wait(.keptOff)
                continue
            }
            guard let need = album.bytes.map({ max($0, 0) }) else {
                // nothing is known of what it takes: neither fitting, nor given way
                waits[album.id] = .unread
                continue
            }
            if let left = limitLeft, usedLimit + need > left {
                wait(.room)
                continue
            }
            usedLimit += need
            if usedPhone + need <= phoneLeft {
                usedPhone += need
                bytes += need
                fits.append(album.id)
            } else {
                wait(.phoneFull)
            }
        }
        return Plan(fits: fits, waits: waits, giveWay: giveWay, bytes: bytes, of: albums.count)
    }
}
