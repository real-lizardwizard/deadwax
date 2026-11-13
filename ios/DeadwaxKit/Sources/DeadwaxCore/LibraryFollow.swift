import Foundation

// Your library followed from deadwax and kept on this phone (notes/ios-specs/phase3-autodownload.md 2.1-2.5): the
// phone's own copy of the list, what a check makes of each answer, when a check is due, the order albums come onto the
// phone in, and which albums' songs are still to be read. Pure - tested on Linux with the rest of Core.

/// One song of an album of your library, as the fill reads it (2.1, 2.4): what it takes on the phone and how it would
/// be fetched - about a hundred bytes, where the album's whole answer is twenty times that.
public struct FollowedSong: Codable, Sendable, Equatable {
    public let id: String
    public let disc: Int?
    public let track: Int?
    /// Navidrome's size of the file.
    public let size: Int64?
    public let suffix: String?
    public let contentType: String?
    /// Seconds: a transcode's estimate is made from it.
    public let duration: Double?

    public init(id: String, disc: Int? = nil, track: Int? = nil, size: Int64? = nil, suffix: String? = nil,
                contentType: String? = nil, duration: Double? = nil) {
        self.id = id
        self.disc = disc
        self.track = track
        self.size = size
        self.suffix = suffix
        self.contentType = contentType
        self.duration = duration
    }

    /// The facts kept of a song of `GET /navidrome/albums/{id}`.
    public init(_ song: Song) {
        self.init(id: song.id, disc: song.discNumber, track: song.track, size: song.size, suffix: song.suffix,
                  contentType: song.contentType, duration: song.duration)
    }

    /// The song as a download is asked for it (DownloadRecord(song:albumID:now:)): only the facts kept.
    public var song: Song {
        Song(id: id, track: track, discNumber: disc, duration: duration, suffix: suffix, contentType: contentType, size: size)
    }

    /// `raw`, or `mp3` for what iOS can't decode - as its stream is fetched (StreamFormat).
    public var format: String { StreamFormat.format(suffix: suffix, contentType: contentType) }

    /// What it takes on the phone, as the planner counts a song asked for: Navidrome's size, or a transcode's estimate.
    public var bytes: Int64 {
        DownloadRules.expectedBytes(size: size, transcode: format != "raw", duration: duration)
    }
}

/// One album of your library as this phone follows it - a row of the store's `library` table (2.1, 5.1).
public struct FollowedAlbum: Sendable, Equatable, Identifiable {
    /// The list's entry for it, as deadwax last listed it.
    public var album: IndexAlbum
    /// Its place in deadwax's last list (Navidrome's order); missing ones after the listed.
    public var position: Int
    /// Its songs as last read; nil until read, or after a change cleared them.
    public var songs: [FollowedSong]?
    /// When they were read (ms).
    public var readAt: Int64?
    /// When the first believed list without it was asked for (ms) - nil while listed.
    public var missingSince: Int64?
    /// Remove from my library in this app, answered (ms): the next list without it removes it at once.
    public var removedHere: Int64?
    /// Remove Download on it (slice 2): left off this phone until downloaded again (ms).
    public var keptOff: Int64?

    public init(album: IndexAlbum, position: Int, songs: [FollowedSong]? = nil, readAt: Int64? = nil,
                missingSince: Int64? = nil, removedHere: Int64? = nil, keptOff: Int64? = nil) {
        self.album = album
        self.position = position
        self.songs = songs
        self.readAt = readAt
        self.missingSince = missingSince
        self.removedHere = removedHere
        self.keptOff = keptOff
    }

    public var id: String { album.id }

    /// Deadwax's last list had it.
    public var isListed: Bool { missingSince == nil }

    /// What its songs take on the phone; nil until they are read.
    public var bytes: Int64? { songs?.reduce(Int64(0)) { $0 + $1.bytes } }
}

/// Why the app checks your library with deadwax (2.2).
public enum LibraryCheck: String, Sendable, CaseIterable {
    /// A store opened: launch, a sign-in, another person.
    case opened
    /// The app came to the front.
    case front
    /// A minute passed with the app alive (in front, or playing).
    case timer
    /// Add to or Remove from my library answered, in this app.
    case changedHere
    /// Debug's Check now; a pull on You > Downloads.
    case byHand
    /// iOS ran the app's refresh in the background.
    case background
    /// deadwax answers again after it couldn't be reached.
    case back
}

public enum LibraryFollow {
    /// Two checks agree on a removal only this far apart (2.3) - past deadwax's own five-minute re-star of a star lost
    /// mid-retag (src/stars.py SYNC_SECONDS).
    public static let confirmAfterMs: Int64 = 10 * 60_000
    /// The plan's every 15 minutes while the app is alive.
    public static let everyMs: Int64 = 15 * 60_000
    /// Coming to the front (or deadwax back) checks only when the last check began this long ago or more.
    public static let frontAfterMs: Int64 = 60_000
    /// A play moves an album up only this long after it (the plan's 30 days).
    public static let playedWindowMs: Int64 = 30 * 24 * 3_600_000
    /// A list that newly misses more than this many albums, and more than half, is held back (2.3).
    public static let dropAtLeast = 10
    /// Albums' songs read at once (2.4).
    public static let readsAtOnce = 4

    /// What deadwax answered: a list (a 200), or the last list again (a 304). A check that failed changes nothing, so
    /// it never comes here.
    public enum Answer: Sendable, Equatable {
        case listed(AlbumIndexAnswer)
        case unchanged
    }

    /// Why a list's absences weren't believed (2.3) - kept with the list, so a 304 of it is held back too.
    public enum Held: Sendable, Equatable {
        /// The list was empty while the phone followed `kept` albums.
        case empty(kept: Int)
        /// It newly missed `gone` of the `of` albums the last list had.
        case drop(gone: Int, of: Int)
        /// It stopped at deadwax's cap: what it left out can't be told from what was removed.
        case truncated

        /// Whether the person is asked about it (slice 2): the empty list and the drop.
        public var isQuestion: Bool { self != .truncated }

        /// As the store's meta keeps it.
        public var raw: String {
            switch self {
            case .empty(let kept): return "empty:\(kept)"
            case .drop(let gone, let of): return "drop:\(gone):\(of)"
            case .truncated: return "truncated"
            }
        }

        public init?(raw: String?) {
            guard let raw else { return nil }
            let parts = raw.split(separator: ":").map(String.init)
            switch parts.first {
            case "empty" where parts.count == 2:
                guard let kept = Int(parts[1]) else { return nil }
                self = .empty(kept: kept)
            case "drop" where parts.count == 3:
                guard let gone = Int(parts[1]), let of = Int(parts[2]) else { return nil }
                self = .drop(gone: gone, of: of)
            case "truncated" where parts.count == 1:
                self = .truncated
            default:
                return nil
            }
        }
    }

    /// What a check made of an answer.
    public struct Outcome: Sendable, Equatable {
        /// The library after it: the listed albums in the list's order, then those still missing, in their old order.
        public var albums: [FollowedAlbum]
        /// New in the list, in its order (newest first): their songs are to be read.
        public var added: [String] = []
        /// Listed before and now, with another song count or length: their songs are read again.
        public var changed: [String] = []
        /// Newly absent from a believed list: missing from now.
        public var missing: [String] = []
        /// Missing before, listed again.
        public var back: [String] = []
        /// Gone from your library: two checks at least 10 minutes apart agreed, or it was removed here.
        public var removed: [String] = []
        /// Why this list's absences weren't believed; nil when they were.
        public var held: Held?
        /// They were believed only because you said Remove to the question (`believing`): the list would have been held.
        public var believed = false

        public init(albums: [FollowedAlbum], added: [String] = [], changed: [String] = [], missing: [String] = [],
                    back: [String] = [], removed: [String] = [], held: Held? = nil, believed: Bool = false) {
            self.albums = albums
            self.added = added
            self.changed = changed
            self.missing = missing
            self.back = back
            self.removed = removed
            self.held = held
            self.believed = believed
        }
    }

    /// The library after `answer` (2.3). `kept`: the library before it; `held`: why the last list's absences weren't
    /// believed (the store's meta); `at`: when the request was sent (ms) - the moment the list describes, which a
    /// missing mark is dated by and a `removedHere` mark set after it survives. `believing`: you answered Remove to an
    /// empty list's or a large drop's question (slice 2) - such a list's absences are believed, and go by the same rule
    /// as any: missing first, removed only when a check ten minutes or more on agrees. A truncated list is never
    /// believed.
    public static func sync(_ kept: [FollowedAlbum], answer: Answer, held: Held?, at: Int64,
                            believing: Bool = false) -> Outcome {
        let before = kept.sorted { a, b in a.position != b.position ? a.position < b.position : a.id < b.id }
        switch answer {
        case .unchanged:
            return unchanged(before, held: held, at: at)
        case .listed(let list):
            return listed(before, list: list, at: at, believing: believing)
        }
    }

    /// Whether a Remove answered to the question (`believing`) still stands after `out`: a list that wasn't held on its
    /// own (`listed` and not `believed`) ends it - so does a check that leaves nothing missing (what it let go is gone).
    /// So it is spent on the list it was answered for, and a later empty list is asked about again.
    public static func keepsBelieving(_ out: Outcome, listed: Bool) -> Bool {
        if listed && !out.believed { return false }
        return out.albums.contains { !$0.isListed }
    }

    /// Whether the person is asked about a held list (3.1's question): an empty list or a large drop, not yet answered
    /// Keep Them.
    public static func asks(_ held: Held?, keptThem: Bool) -> Bool {
        guard let held, held.isQuestion else { return false }
        return !keptThem
    }

    /// A 304: the last list again, read afresh. It confirms what has been missing long enough, and nothing else -
    /// unless that list was held back, when it is held back again.
    static func unchanged(_ kept: [FollowedAlbum], held: Held?, at: Int64) -> Outcome {
        guard held == nil else { return Outcome(albums: kept, held: held) }
        var out = Outcome(albums: [])
        for var entry in kept {
            if entry.isListed {
                // listed in the list this answer repeats: a Remove made before it was asked didn't take
                if let removed = entry.removedHere, removed <= at { entry.removedHere = nil }
            } else if entry.removedHere != nil || at - (entry.missingSince ?? at) >= confirmAfterMs {
                out.removed.append(entry.id)
                continue
            }
            entry.position = out.albums.count
            out.albums.append(entry)
        }
        return out
    }

    /// A 200: added, changed, back - and the absences, when the list is whole and plausible.
    static func listed(_ kept: [FollowedAlbum], list: AlbumIndexAnswer, at: Int64, believing: Bool = false) -> Outcome {
        var ids = Set<String>()
        var albums: [IndexAlbum] = []
        for album in list.albums where ids.insert(album.id).inserted { albums.append(album) }
        var keptByID: [String: FollowedAlbum] = [:]
        for entry in kept where keptByID[entry.id] == nil { keptByID[entry.id] = entry }

        let wasListed = kept.filter(\.isListed)
        let newlyGone = wasListed.filter { !ids.contains($0.id) && $0.removedHere == nil }.count
        var held: Held?
        var believed = false
        if list.truncated {
            held = .truncated
        } else if albums.isEmpty && !kept.isEmpty {
            held = .empty(kept: kept.count)
        } else if newlyGone > dropAtLeast && newlyGone * 2 > wasListed.count {
            held = .drop(gone: newlyGone, of: wasListed.count)
        }
        if believing, let reason = held, reason.isQuestion {
            held = nil
            believed = true
        }

        var out = Outcome(albums: [], held: held, believed: believed)
        for (place, album) in albums.enumerated() {
            guard var entry = keptByID[album.id] else {
                out.albums.append(FollowedAlbum(album: album, position: place))
                out.added.append(album.id)
                continue
            }
            if entry.missingSince != nil {
                entry.missingSince = nil
                out.back.append(album.id)
            }
            if let removed = entry.removedHere, removed <= at { entry.removedHere = nil }
            if songsChanged(entry.album, album) {
                entry.songs = nil
                entry.readAt = nil
                out.changed.append(album.id)
            }
            entry.album = album
            entry.position = place
            out.albums.append(entry)
        }
        for var entry in kept where !ids.contains(entry.id) {
            if held == nil {
                if entry.removedHere != nil {
                    out.removed.append(entry.id)
                    continue
                }
                if let since = entry.missingSince {
                    if at - since >= confirmAfterMs {
                        out.removed.append(entry.id)
                        continue
                    }
                } else {
                    entry.missingSince = at
                    out.missing.append(entry.id)
                }
            }
            entry.position = out.albums.count
            out.albums.append(entry)
        }
        return out
    }

    /// Whether the list's entry says the album's songs are no longer what was read: another song count, or a length
    /// more than half a second off (either known on one side only counts too).
    public static func songsChanged(_ old: IndexAlbum, _ new: IndexAlbum) -> Bool {
        if old.songCount != new.songCount { return true }
        switch (old.duration, new.duration) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a - b) > 0.5
        default: return true
        }
    }

    // MARK: when

    /// Whether a check for `reason` is due, the last one having begun at `lastBegan` (ms; nil for none yet).
    public static func due(_ reason: LibraryCheck, lastBegan: Int64?, now: Int64) -> Bool {
        guard let last = lastBegan else { return true }
        switch reason {
        case .opened, .changedHere, .byHand, .background:
            return true
        case .front, .back:
            return now - last >= frontAfterMs
        case .timer:
            return now - last >= everyMs
        }
    }

    // MARK: the order (2.5)

    /// Where an album goes in the order: the later of when it entered your library - its star (`created` when
    /// Navidrome gave none), or for the collection when the collection got it - and when you last played it, a play
    /// counting only within the last 30 days (one dated ahead of `now` counts as now). Nil: no date at all.
    public static func placedAt(_ album: IndexAlbum, scope: AlbumScope, now: Int64, zone: TimeZone = .current) -> Int64? {
        let created = AlbumTime.ms(album.created, zone: zone)
        let entered = scope == .yours ? (AlbumTime.ms(album.starred, zone: zone) ?? created) : created
        var played = AlbumTime.ms(album.played, zone: zone).map { min($0, now) }
        if let at = played, now - at > playedWindowMs { played = nil }
        switch (entered, played) {
        case let (e?, p?): return max(e, p)
        case let (e?, nil): return e
        case let (nil, p?): return p
        default: return nil
        }
    }

    /// The library in the order its albums come onto the phone: newest first by `placedAt`, ties in deadwax's order,
    /// albums with no date last (in deadwax's order).
    public static func ordered(_ albums: [FollowedAlbum], scope: AlbumScope, now: Int64,
                               zone: TimeZone = .current) -> [FollowedAlbum] {
        let keyed = albums.map { (entry: $0, at: placedAt($0.album, scope: scope, now: now, zone: zone)) }
        return keyed.sorted { a, b in
            switch (a.at, b.at) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return a.entry.position != b.entry.position ? a.entry.position < b.entry.position : a.entry.id < b.entry.id
            }
        }.map(\.entry)
    }

    /// The albums whose songs are still to be read, in `ordered`'s order: listed, not read, and not among `failed`
    /// (asked this check and refused - asked again at the next).
    public static func toRead(_ ordered: [FollowedAlbum], failed: Set<String> = []) -> [String] {
        ordered.filter { $0.songs == nil && $0.isListed && !failed.contains($0.id) }.map(\.id)
    }
}
