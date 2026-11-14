import Foundation

/// A song of the download store as the library's rules read it: why it is wanted, and whether it is here.
public struct StoreSong: Sendable, Equatable {
    public let id: String
    /// The album it was asked for with (DownloadRecord.albumID).
    public let albumID: String
    public let origins: Set<DownloadOrigin>
    public let state: StoredState
    /// Its bytes on the phone (once here).
    public let bytes: Int64

    public init(id: String, albumID: String, origins: Set<DownloadOrigin>, state: StoredState = .done, bytes: Int64 = 0) {
        self.id = id
        self.albumID = albumID
        self.origins = origins
        self.state = state
        self.bytes = bytes
    }

    /// The library wants it (perhaps among others).
    public var isLibrary: Bool { origins.contains(.library) }
    /// The library and nothing else wants it: the only kind of song the library's rules can ever cause to go.
    public var onlyLibrary: Bool { DownloadOrigin.onlyLibrary(origins) }
    /// Wanted by hand: a song's or an album's Download, a playlist's - anything but the library.
    public var byHand: Bool { !origins.subtracting([.library]).isEmpty }
}

/// Your library downloaded (notes/ios-specs/phase3-autodownload.md 2.6-2.7; slice 2): what the library asks of the
/// store and what it gives back, after each check and each fill. Pure.
///
/// The library's only way to make anything go is to **take its own origin** (`DownloadOrigin.library`) from songs -
/// through Phase 2's `removeOrigins` (DownloadRules.afterRemoving is its rule), which deletes a song only when it is
/// left with no origin at all. So a song downloaded by hand (`song`, `album:<id>`), one in a downloaded playlist
/// (`playlist:<id>`) or anything a later phase adds is never deleted by the library; plays, starts and the queue kept
/// are other tables, never touched.
///
/// It takes its origin only:
/// - from an album **removed** from your library - two checks at least 10 minutes apart agreed, or you removed it in
///   this app and deadwax's next list confirmed it (LibraryFollow.sync's `removed`, never a guess: an album the table
///   no longer has for any other reason keeps its songs) - by its album, and by the songs it was last read with
///   (`removedSongs`), so a song kept under another album id goes with it;
/// - from an album that **doesn't fit** - the limit lowered, the phone under its 2 GB on plans minutes apart, room made
///   for a hand download (LibraryFill's `room` and `phoneFull`): given way whole;
/// - from an album **kept off** (Remove Download on it);
/// - from a song **no longer on its album** - two reads of the album at least 10 minutes apart agreed it had left
///   (FollowedAlbum.leftAgreed); one read never takes anything;
/// - and, all of it, when the switch goes off (`switchedOff`).
/// An album whose songs are being read again keeps everything meanwhile.
public enum LibraryDownloads {
    /// Albums of your library on their way at once (songs asked for and not here): the next are asked as these arrive -
    /// so a library of thousands is never handed over at once (each album also has its answer, cover and loudness
    /// kept).
    public static let albumsAtOnce = 10

    /// Why an album's library songs were let go - for the downloads log.
    public enum Why: String, Sendable, CaseIterable {
        case removed
        /// Had songs here; doesn't fit now.
        case gaveWay = "gave_way"
        /// Asked for, nothing here yet; doesn't fit now.
        case waits
        case keptOff = "kept_off"
        case notOnAlbum = "not_on_album"
        case switchedOff = "switched_off"
    }

    /// An album's songs asked for under the library: those of its songs that don't carry the origin yet.
    public struct Ask: Sendable, Equatable {
        public let album: String
        public let songs: [FollowedSong]

        public init(album: String, songs: [FollowedSong]) {
            self.album = album
            self.songs = songs
        }
    }

    /// What the library does to the store now.
    public struct Actions: Sendable, Equatable {
        /// In the fill's order.
        public var ask: [Ask] = []
        /// Songs the library's origin is taken from (Phase 2's removeOrigins: deleted only when left with none).
        public var take: [String] = []
        /// Each album taken from, and why.
        public var why: [String: Why] = [:]

        public init(ask: [Ask] = [], take: [String] = [], why: [String: Why] = [:]) {
            self.ask = ask
            self.take = take
            self.why = why
        }

        public var isEmpty: Bool { ask.isEmpty && take.isEmpty }
    }

    /// The only origin the library ever takes from a song (through Phase 2's removeOrigins): its own.
    public static let gives: Set<DownloadOrigin> = [.library]

    // MARK: the store's songs

    /// The store's songs as the rules read them: each with its origins (none kept reads as asked for alone - never the
    /// library's), the album of your library it is read on (else one a read found it had left - until a second read
    /// agrees, it is that album's - else its record's), its state and bytes.
    public static func songs(_ records: [DownloadRecord], origins: [String: Set<DownloadOrigin>],
                             library: [FollowedAlbum]) -> [StoreSong] {
        var albumOf: [String: String] = [:]
        for entry in library {
            for song in entry.songs ?? [] where albumOf[song.id] == nil { albumOf[song.id] = entry.id }
        }
        for entry in library {
            for id in entry.left.keys.sorted() where albumOf[id] == nil { albumOf[id] = entry.id }
        }
        return records.map { record in
            let its = origins[record.id].flatMap { $0.isEmpty ? nil : $0 } ?? [.song]
            return StoreSong(id: record.id, albumID: albumOf[record.id] ?? record.albumID, origins: its,
                             state: record.state, bytes: record.state == .done ? max(record.bytes ?? 0, 0) : 0)
        }
    }

    /// The Library's Downloaded (3.3): every album of the store - but one your library alone wants only once a song of
    /// it is here or on its way, never while all of it only waits.
    public static func listed(_ songs: [StoreSong]) -> Set<String> {
        var out = Set<String>()
        for song in songs where song.byHand || song.state != .wanted { out.insert(song.albumID) }
        return out
    }

    // MARK: the fill's inputs

    /// What the fill reads of the store, worked out once per plan - and `givable`, the one number of what the library
    /// could give back, which Phase 2's planner credits a hand download with too (DownloadPlan.Facts.libraryHere).
    public struct Inputs: Sendable, Equatable {
        /// The fill's albums (LibraryFill.AlbumFacts), in the order.
        public let albums: [LibraryFill.AlbumFacts]
        /// The songs wanted by hand: their bytes are the hand downloads'.
        public let hand: Set<String>
        /// LibraryFill.givable of `albums`.
        public let givable: Int64
    }

    /// From the store: each album's library songs (those wanted by hand are the hand downloads'), what of them is here
    /// and to come, whether any is asked for or here (`held`) - and its cover: `covers` is each kept album answer's
    /// cover bytes (0 for one kept with none). An album the library's alone counts its cover as its own, here and in
    /// what it takes (`LibraryFill.albumAllowance` until its answer is kept); an album with a song wanted by hand
    /// leaves the cover to the hand download.
    public static func inputs(_ ordered: [FollowedAlbum], songs: [StoreSong], covers: [String: Int64] = [:]) -> Inputs {
        var hand = Set<String>()
        var handAlbums = Set<String>()
        var done = Set<String>()
        var held = Set<String>()
        var here: [String: Int64] = [:]
        for song in songs {
            if song.byHand {
                hand.insert(song.id)
                handAlbums.insert(song.albumID)
            }
            if song.state == .done { done.insert(song.id) }
            if song.isLibrary { held.insert(song.albumID) }
            guard song.onlyLibrary, song.state == .done else { continue }
            here[song.albumID, default: 0] += max(song.bytes, 0)
        }
        var extras: [String: Int64] = [:]
        for entry in ordered where !handAlbums.contains(entry.id) {
            if let cover = covers[entry.id] {
                extras[entry.id] = max(cover, 0)
                // kept with the library's songs, and gone with them
                if held.contains(entry.id) { here[entry.id, default: 0] += max(cover, 0) }
            } else {
                extras[entry.id] = LibraryFill.albumAllowance
            }
        }
        let albums = LibraryFill.albums(ordered, hand: hand, here: here, done: done, held: held, extras: extras)
        return Inputs(albums: albums, hand: hand, givable: LibraryFill.givable(albums))
    }

    // MARK: a turn

    /// The fill and what the library does, as DownloadModel works them out at every plan.
    public struct Turn: Sendable, Equatable {
        public let fill: LibraryFill.Plan
        public let actions: Actions
    }

    /// One turn: the fill of `ordered` (LibraryFollow.ordered) after the hand downloads - the store's `bytesHere` (songs
    /// and covers) less what the library could give back, and `handToCome` (DownloadPlan.handToCome) - under the limit
    /// and free space; then the actions, from `removed` (the albums the last checks removed and not yet acted on, and
    /// `removedSongs`, the songs they were last read with) and the store's songs. `deficitConfirmed`: the phone has been
    /// under its reserve on plans minutes apart (LibraryFill.deficitConfirmed) - only then does anything here give way
    /// for it.
    public static func turn(_ ordered: [FollowedAlbum], removed: Set<String>, removedSongs: Set<String> = [],
                            songs: [StoreSong], covers: [String: Int64] = [:], bytesHere: Int64, handToCome: Int64,
                            limit: Int64?, freeSpace: Int64, reserve: Int64 = DownloadPlan.reserve,
                            readsPending: Bool = false, deficitConfirmed: Bool = false) -> Turn {
        turn(ordered, inputs: inputs(ordered, songs: songs, covers: covers), removed: removed, removedSongs: removedSongs,
             songs: songs, bytesHere: bytesHere, handToCome: handToCome, limit: limit, freeSpace: freeSpace,
             reserve: reserve, readsPending: readsPending, deficitConfirmed: deficitConfirmed)
    }

    /// The same, from inputs already worked out (DownloadModel's, which credits the planner with their `givable`).
    public static func turn(_ ordered: [FollowedAlbum], inputs: Inputs, removed: Set<String>,
                            removedSongs: Set<String> = [], songs: [StoreSong], bytesHere: Int64, handToCome: Int64,
                            limit: Int64?, freeSpace: Int64, reserve: Int64 = DownloadPlan.reserve,
                            readsPending: Bool = false, deficitConfirmed: Bool = false) -> Turn {
        // what is here and not the library's to give back - the hand downloads, and library songs the fill can't give
        // way now (an album read again, a song on no album of the library) - counts against the limit as it is
        let fixed = max(bytesHere - inputs.givable, 0)
        let fill = LibraryFill.plan(inputs.albums,
                                    LibraryFill.Facts(handBytes: fixed + handToCome, handToCome: handToCome,
                                                      limit: limit, freeSpace: freeSpace, reserve: reserve,
                                                      deficitConfirmed: deficitConfirmed))
        return Turn(fill: fill, actions: actions(ordered, fill: fill, removed: removed, removedSongs: removedSongs,
                                                 songs: songs, readsPending: readsPending))
    }

    // MARK: the actions

    /// What the library asks for and gives back, from the library in the order (`ordered`, LibraryFollow.ordered), its
    /// fill, the albums the last check removed, and the store's songs. `readsPending`: albums' songs are still being
    /// read this check - nothing is asked below the first one still to read, so an album read late never makes one
    /// asked before it give way.
    public static func actions(_ ordered: [FollowedAlbum], fill: LibraryFill.Plan, removed: Set<String>,
                               removedSongs: Set<String> = [], songs: [StoreSong], readsPending: Bool = false) -> Actions {
        var out = Actions()
        var library: [String: FollowedAlbum] = [:]
        for entry in ordered where library[entry.id] == nil { library[entry.id] = entry }
        var byAlbum: [String: [StoreSong]] = [:]
        for song in songs { byAlbum[song.albumID, default: []].append(song) }

        // what is given back: only the library's own origin, only for the reasons above
        var taken = Set<String>()
        for song in songs where song.isLibrary {
            let albumID = song.albumID
            var why: Why?
            // a removed album's song by id too (kept under another album id) - unless an album still in the library has it
            if removed.contains(albumID) || (removedSongs.contains(song.id) && library[albumID] == nil) {
                why = .removed
            } else if let entry = library[albumID] {
                switch fill.waits[entry.id] {
                case .keptOff?:
                    why = .keptOff
                case .room?, .phoneFull?:
                    let anyHere = (byAlbum[albumID] ?? []).contains { $0.isLibrary && $0.state == .done }
                    why = anyHere ? .gaveWay : .waits
                case .unread?:
                    why = nil
                case nil:
                    // left its album: only when two reads at least 10 minutes apart agree (one read takes nothing)
                    if entry.leftAgreed.contains(song.id), let read = entry.songs,
                       !read.contains(where: { $0.id == song.id }) {
                        why = .notOnAlbum
                    }
                }
            }
            // an album neither in the library nor removed by a check keeps its songs: nothing goes on a guess
            guard let why else { continue }
            out.take.append(song.id)
            taken.insert(albumID)
            if out.why[albumID] == nil || why != .notOnAlbum { out.why[albumID] = why }
        }

        // what is asked for: the albums that fit, in order, a few at a time
        var store: [String: StoreSong] = [:]
        for song in songs { store[song.id] = song }
        let fits = Set(fill.fits)
        let onTheirWay = Set(songs.filter { $0.isLibrary && ($0.state == .wanted || $0.state == .fetching) }
            .map(\.albumID)).subtracting(taken)
        var slots = albumsAtOnce - onTheirWay.count
        for entry in ordered {
            if readsPending, entry.isListed, entry.songs == nil, entry.keptOff == nil { break }
            // nothing new for an album the last list didn't have, or one you removed here: it may be on its way out
            guard fits.contains(entry.id), entry.isListed, entry.removedHere == nil, let read = entry.songs else { continue }
            let missing = read.filter { store[$0.id]?.isLibrary != true }
            guard !missing.isEmpty else { continue }
            // a fetch is needed for a song the store hasn't got, or one that failed by hand (asking retries it)
            let fetches = missing.contains { song in
                guard let held = store[song.id] else { return true }
                return held.state == .failed
            }
            if fetches && !onTheirWay.contains(entry.id) {
                guard slots > 0 else { continue }
                slots -= 1
            }
            out.ask.append(Ask(album: entry.id, songs: missing))
        }
        return out
    }

    /// The switch turned off: the library's origin taken from every song that carries it.
    public static func switchedOff(_ songs: [StoreSong]) -> Actions {
        var out = Actions()
        for song in songs where song.isLibrary {
            out.take.append(song.id)
            out.why[song.albumID] = .switchedOff
        }
        return out
    }

    /// What turning the switch off deletes (its confirmation, 3.1 after the review): the albums with a library-only
    /// song here, and those songs' bytes.
    public static func switchOffLoses(_ songs: [StoreSong]) -> (albums: Int, bytes: Int64) {
        var albums = Set<String>()
        var bytes: Int64 = 0
        for song in songs where song.onlyLibrary && song.state == .done {
            albums.insert(song.albumID)
            bytes += max(song.bytes, 0)
        }
        return (albums.count, bytes)
    }

    /// What keeping `albumID` off deletes (Didn't download's swipe, after the review): its library-only songs here.
    public static func keptOffLoses(_ albumID: String, songs: [StoreSong]) -> Int {
        songs.reduce(0) { $0 + ($1.albumID == albumID && $1.onlyLibrary && $1.state == .done ? 1 : 0) }
    }

    /// The songs `actions` would delete: those its takes leave with no origin (Phase 2's rule, as removeOrigins runs
    /// it). Always among the library-only songs.
    public static func deleted(_ actions: Actions, songs: [StoreSong]) -> [String] {
        var origins: [String: Set<DownloadOrigin>] = [:]
        for song in songs { origins[song.id] = song.origins }
        let taken = Set(actions.take)
        let after = DownloadRules.afterRemoving([.library], from: origins.filter { taken.contains($0.key) })
        return after.deleted.sorted()
    }

    // MARK: what the screens show

    /// Downloading's one row for the library (3.3): the albums that fit and aren't all here yet, of all that fit, and
    /// the bytes still to come. An album whose songs not here all failed isn't on its way (Didn't download has it). Nil
    /// while no album is to come.
    public struct Progress: Sendable, Equatable {
        public let toGo: Int
        public let of: Int
        public let bytes: Int64

        public var fraction: Double { of > 0 ? Double(of - toGo) / Double(of) : 0 }
    }

    public static func progress(_ ordered: [FollowedAlbum], fill: LibraryFill.Plan, songs: [StoreSong]) -> Progress? {
        var here = Set<String>()
        var failed = Set<String>()
        for song in songs {
            if song.state == .done { here.insert(song.id) }
            if song.state == .failed { failed.insert(song.id) }
        }
        let fits = Set(fill.fits)
        var toGo = 0
        var bytes: Int64 = 0
        for entry in ordered where fits.contains(entry.id) {
            guard let read = entry.songs else { continue }
            let missing = read.filter { !here.contains($0.id) }
            guard missing.contains(where: { !failed.contains($0.id) }) else { continue }
            toGo += 1
            bytes += missing.reduce(Int64(0)) { $0 + $1.bytes }
        }
        guard toGo > 0 else { return nil }
        return Progress(toGo: toGo, of: fill.fit, bytes: bytes)
    }

    /// What an album's page says of it and your library (3.4).
    public enum AlbumMark: Sendable, Equatable {
        case none
        /// Downloaded (or coming) with your library.
        case withLibrary
        /// In your library; doesn't fit - it waits for room.
        case waitsForRoom
        /// You removed its download: the library leaves it off.
        case keptOff
    }

    public static func mark(_ albumID: String, following: Bool, library: FollowedAlbum?, fill: LibraryFill.Plan?,
                            songs: [StoreSong]) -> AlbumMark {
        guard following, let library else { return .none }
        if library.keptOff != nil { return .keptOff }
        if songs.contains(where: { $0.albumID == albumID && $0.isLibrary }) { return .withLibrary }
        switch fill?.waits[albumID] {
        case .room?, .phoneFull?: return .waitsForRoom
        default: return .none
        }
    }
}

/// The switches kept per phone (phase3-autodownload.md 6.2, open question 13): applying to whoever is signed in, as
/// Download over and the storage limit do.
public enum AutoDownload {
    /// Download your library (or the collection): off until chosen.
    public static let libraryKey = "autoDownloadLibrary"
    /// Only while charging (slice 3's): off by default.
    public static let onlyWhileChargingKey = "autoDownloadOnlyWhileCharging"
    /// The first ask answered (3.2): either answer puts it away for good.
    public static let askedKey = "autoDownloadAsked"
}
