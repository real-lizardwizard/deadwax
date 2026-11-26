import Foundation

// Radio and Autoplay (deadwax-plans/lastfm.md 3.5; notes/ios.md "Last.fm, slice A3"): a station - Start Radio's, begun
// from a song, or Autoplay's, begun at the queue's end from its last entry - with the answer deadwax gave for it
// (`GET /deadwax/lastfm/radio`, LastfmRadio), the songs it hands the queue ten at a time, when the queue wants more,
// and which of the Queue's rows are Autoplay's. Pure: the app (PlayerModel+Station.swift) asks, appends through
// QueueController.appendStation (UpNext's withStation) and draws. A station belongs to its queue (UpNextState.id) and
// lives in memory only: a new queue drops it, and nothing of it is saved - after a relaunch its songs are plain rows.

/// One station: what it is, the song it was begun from, the queue it belongs to, and how far it has got.
public struct Station: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// Start Radio's: a new queue of the song, and the station's songs after it - the list itself
        case radio
        /// Autoplay's: begun when a queue nears its end, from its last entry - its songs drawn under "Autoplay"
        case autoplay
    }

    /// What the queue's end may come down to before a station's songs are wanted: 2 or fewer entries after the one
    /// playing, this time round, Repeat One's copies not counted.
    public static let lowWater = 2
    /// The songs a top-up takes.
    public static let batch = 10
    /// The most of an answer a station holds.
    public static let most = 100
    /// The most times a station's answer is asked for.
    public static let tries = 3
    /// After a failed ask, how long before it is asked again while the same entry plays (another entry asks at once).
    public static let againSeconds: Double = 30

    public let kind: Kind
    /// The song it was begun from (Start Radio's song; Autoplay's, the queue's last entry).
    public let seed: QueueTrack
    /// The queue it belongs to (UpNextState.id).
    public let queueId: String
    /// The answer's songs, at most `most`, once one came; nil until then.
    public private(set) var songs: [Song]?
    /// Where `take` stopped in `songs`: every song before it has been looked at once, taken, passed over or kept for
    /// later.
    public private(set) var next = 0
    /// (A3's review) The songs passed over only for not being on the device while deadwax couldn't be reached, in their
    /// order: the next take looks at them first, so back online they are taken - one offline top-up never uses the
    /// whole answer up.
    public private(set) var later: [Song] = []
    /// The asks made.
    public private(set) var asks = 0
    /// An ask is out.
    public private(set) var asking = false
    /// The last ask's failure: the entry playing as it failed, and when.
    public private(set) var failure: Failure?
    /// Autoplay's: the songs it gave the queue, and the queue's next key as it first gave any - so its rows are the
    /// list's entries from that key on whose songs these are (`isAutoplay`). A change held for the song's join (D4) is
    /// made later, against the queue as it is then, so a key can't be known as the songs are taken.
    public private(set) var added: Set<String> = []
    public private(set) var floor: Int?
    /// (A3's review) Autoplay's: the list's source count as it first gave songs - its songs are the source from here on
    /// (withStation appends them there, and nothing else grows the source of a queue that isn't a library's shuffle),
    /// what turning Autoplay off takes out (withoutStation).
    public private(set) var start: Int?

    public struct Failure: Sendable, Equatable {
        public let entry: Int?
        public let at: Double
    }

    /// What `answered` made of an answer.
    public enum Outcome: Sendable, Equatable {
        /// songs to take
        case songs
        /// a definite nothing (`[]`): nothing in the library is similar
        case nothing
        /// no answer, or one that couldn't be made just now (`songs` null): asked again by the top-up's rule
        case failed
    }

    public init(kind: Kind, seed: QueueTrack, queueId: String) {
        self.kind = kind
        self.seed = seed
        self.queueId = queueId
    }

    /// Start Radio's station for the queue just started from its song: seeded by the song playing.
    public static func radio(_ queue: UpNextQueue) -> Station? {
        guard let id = queue.upNext?.id, let seed = queue.current else { return nil }
        return Station(kind: .radio, seed: seed, queueId: id)
    }

    /// Autoplay's first top-up: a station seeded by the queue's last entry.
    public static func autoplay(_ queue: UpNextQueue) -> Station? {
        guard let id = queue.upNext?.id, let seed = queue.tracks.last else { return nil }
        return Station(kind: .autoplay, seed: seed, queueId: id)
    }

    // MARK: the ask

    /// What the radio route is asked with: the song's id, its title and its artist, trimmed - nil for a song without
    /// one of them, or with one longer than the route takes (deadwax would answer 422: such a song has no station).
    public struct Ask: Sendable, Equatable {
        public let songId: String
        public let title: String
        public let artist: String

        /// The route's longest id (src/routes/navidrome.py ID_MAX) and longest title or artist (lastfm.py WORDS_MAX).
        public static let idMost = 256
        public static let wordsMost = 500

        public init?(songId: String, title: String, artist: String) {
            let title = PyText.strip(title)
            let artist = PyText.strip(artist)
            guard !songId.isEmpty, songId.unicodeScalars.count <= Self.idMost, !title.isEmpty, !artist.isEmpty,
                  title.unicodeScalars.count <= Self.wordsMost, artist.unicodeScalars.count <= Self.wordsMost
            else { return nil }
            self.songId = songId
            self.title = title
            self.artist = artist
        }
    }

    /// The seed's ask - nil when the seed can't be asked about, which is a station with nothing (`answered(nil)` is
    /// never made of it: the app answers it `[]`).
    public var ask: Ask? { Ask(songId: seed.id, title: seed.title, artist: seed.artist) }

    /// Whether the answer is to be asked for now, with the entry `entry` playing: none yet, none out, fewer than
    /// `tries` made - and after a failure, another entry playing, or `againSeconds` gone by.
    public func mayAsk(playing entry: Int?, now: Double) -> Bool {
        guard songs == nil, !asking, asks < Self.tries, ask != nil else { return false }
        guard let failure else { return true }
        return failure.entry != entry || now - failure.at >= Self.againSeconds
    }

    /// When the ask after a failure is due while the same entry plays - nil when none is.
    public var againAt: Double? {
        guard songs == nil, !asking, asks < Self.tries, let failure else { return nil }
        return failure.at + Self.againSeconds
    }

    /// An ask sent.
    public mutating func began() {
        asks += 1
        asking = true
    }

    /// The ask's answer (nil: it failed), with the entry `entry` playing at `now`.
    @discardableResult
    public mutating func answered(_ answer: LastfmRadio?, playing entry: Int?, now: Double) -> Outcome {
        asking = false
        guard let songs = answer?.songs else {
            failure = Failure(entry: entry, at: now)
            return .failed
        }
        self.songs = Array(songs.prefix(Self.most))
        failure = nil
        return songs.isEmpty ? .nothing : .songs
    }

    /// Nothing more will come of it: its songs all looked at, none kept for later - or none ever, every ask made and
    /// failed.
    public var exhausted: Bool {
        if let songs { return next >= songs.count && later.isEmpty }
        return !asking && (asks >= Self.tries || ask == nil)
    }

    /// (A3's review) Whether the queue's list holds the station's songs: a radio's always (its list is the song and its
    /// station's), Autoplay's once it has given some. Shuffle can't be turned on then - shuffling would mix them into
    /// the album - though one already on can be turned off.
    public var inList: Bool {
        kind == .radio || !added.isEmpty
    }

    // MARK: the songs

    /// A song as songs are told apart here: its title as songs.ts's titleKey folds it, and its artist folded.
    struct SongKey: Hashable {
        let title: String
        let artist: String

        init?(title: String?, artist: String?) {
            let title = SongTitle.key(title)
            //? a song with no title can't be told from another by its words: its id alone tells it
            guard !title.isEmpty else { return nil }
            self.title = title
            self.artist = Fold.key(artist)
        }
    }

    /// The next `batch` songs of the answer - those kept for later first, then from where the last take stopped - none
    /// the queue holds already (by id, History's songs included, or by title and artist), never the seed, and while
    /// deadwax can't be reached (`here` given) only songs on the device. A song looked at is passed for good - a song
    /// taken out of the Queue isn't added back - but one passed only for not being on the device is kept for later
    /// (`later`), looked at first by the next take. Autoplay's songs are noted (`added`, `floor`, `start`) for the
    /// Queue's heading and for turning Autoplay off.
    public mutating func take(_ queue: UpNextQueue, here: ((String) -> Bool)? = nil) -> [Song] {
        guard let songs else { return [] }
        var ids = Set(queue.tracks.map(\.id))
        ids.insert(seed.id)
        var keys = Set(queue.tracks.compactMap { SongKey(title: $0.title, artist: $0.artist) })
        if let key = SongKey(title: seed.title, artist: seed.artist) { keys.insert(key) }
        var taken: [Song] = []
        var waiting = later[...]
        var still: [Song] = []
        while taken.count < Self.batch {
            let song: Song
            if let first = waiting.first {
                song = first
                waiting.removeFirst()
            } else if next < songs.count {
                song = songs[next]
                next += 1
            } else {
                break
            }
            let key = SongKey(title: song.title, artist: song.artist)
            if ids.contains(song.id) || key.map({ keys.contains($0) }) == true { continue }
            if let here, !here(song.id) {
                still.append(song)
                continue
            }
            ids.insert(song.id)
            if let key { keys.insert(key) }
            taken.append(song)
        }
        later = still + waiting
        if kind == .autoplay && !taken.isEmpty {
            added.formUnion(taken.map(\.id))
            if floor == nil {
                floor = queue.upNext?.nextKey
                start = queue.upNext?.source.count
            }
        }
        return taken
    }

    // MARK: the queue

    /// Whether the queue wants a station's songs now (the top-up): Last.fm on, Repeat Off, not a library's shuffle, a
    /// station of this queue's or Autoplay on, and `lowWater` or fewer entries after the one playing (`following`) -
    /// two left after it: on the queue's third-to-last song.
    public static func wantsMore(_ queue: UpNextQueue, mode: Repeat, lastfm: Bool, station: Station?,
                                 autoplay: Bool) -> Bool {
        guard lastfm, mode == .off, let state = queue.upNext, state.paged == nil, queue.current != nil else { return false }
        guard autoplay || station?.queueId == state.id else { return false }
        return following(queue) <= lowWater
    }

    /// The entries after the one playing, Repeat One's copies not counted. (A3's review) Every other entry plays: the
    /// top-up is asked only under Repeat Off, where a later time round's songs after the one playing are a roll-back's,
    /// moved back down to play again - counted, so the top-up doesn't add twice what it should.
    public static func following(_ queue: UpNextQueue) -> Int {
        guard let state = queue.upNext else { return 0 }
        return state.marks.dropFirst(queue.index + 1).filter { $0.from != .one }.count
    }

    /// Whether the entry `mark`, of `id`'s song, is one Autoplay gave this queue.
    func isAutoplay(_ mark: Mark, id: String) -> Bool {
        guard kind == .autoplay, let floor else { return false }
        return mark.from == .source && mark.key >= floor && added.contains(id)
    }

    /// The Queue's list split for Autoplay's heading: the list's own rows, under its own title (its songs' - "From
    /// Currents" while the rest is Autoplay's), and Autoplay's rows, the list's tail - the longest run at its end that
    /// Autoplay gave. A row moved up out of that run is drawn in the list. Nothing is split for a radio (its songs are
    /// the list itself), a station of another queue, or a list with more than is drawn (its tail isn't drawn). A list
    /// that is all Autoplay's is nil, its rows all Autoplay's.
    public static func split(_ list: UpNextList?, _ queue: UpNextQueue, _ station: Station?)
        -> (list: UpNextList?, autoplay: [UpNextRow]) {
        guard let list, let station, station.kind == .autoplay, let state = queue.upNext, state.id == station.queueId,
              state.paged == nil, list.more == 0 else { return (list, []) }
        var marks: [Int: Mark] = [:]
        for mark in state.marks where marks[mark.key] == nil { marks[mark.key] = mark }
        var start = list.rows.count
        while start > 0, let mark = marks[list.rows[start - 1].key],
              station.isAutoplay(mark, id: list.rows[start - 1].track.id) {
            start -= 1
        }
        guard start < list.rows.count else { return (list, []) }
        let own = Array(list.rows[..<start])
        let again = shownPass(queue) > passPlaying(state.marks, queue.index)
        let title = listTitle(state.source.filter { !station.added.contains($0.id) }, again: again)
        return (own.isEmpty ? nil : UpNextList(title: title, rows: own, more: 0), Array(list.rows[start...]))
    }
}

/// Autoplay, the device's own setting (never saved with the queue): off by default (James, 24 Nov - lastfm.md 8.1).
public enum Autoplay {
    /// Where the device keeps it, in UserDefaults.
    public static let storageKey = "deadwax-player-autoplay"

    /// What was stored, read with care: "on" is on; anything else - nothing, "On", "true", a word - is off.
    public static func read(_ stored: String?) -> Bool {
        stored == "on"
    }

    /// What is stored for it.
    public static func stored(_ on: Bool) -> String {
        on ? "on" : "off"
    }
}
