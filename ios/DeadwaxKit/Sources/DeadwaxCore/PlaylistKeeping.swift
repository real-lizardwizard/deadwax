import Foundation

// The downloaded playlists as the keeper holds them, and the order each change reaches the store in (slice 3's review):
// PlaylistKeeper's (App) every moment, without its I/O, so the order is tested here. Each moment gives a Change - the one
// write to the store's `playlist` table it makes, then what it does to the songs - and `run` makes it: the write first;
// only once it holds is the change taken into memory and the songs touched, a take that fails stopping the asks after
// it. So a row is written before its songs are asked for, and deleted before its origin is taken: a quit between the
// two leaves at worst an origin with no row, an orphan's, taken as the store opens (`opened`).

/// The downloaded playlists kept in memory, and each answer's serial.
public struct PlaylistKeeping: Sendable, Equatable {
    /// The downloaded playlists, in the order they were downloaded.
    public private(set) var kept: [KeptPlaylist]
    /// Moves on each answer taken in for a playlist: a read answered after a newer one was taken in - this phone's
    /// Edit's, a page's - is older than what is kept, and dropped (else what the Edit took out would come back).
    public private(set) var serials: [String: Int] = [:]

    public init(kept: [KeptPlaylist] = []) {
        self.kept = kept
    }

    /// The one write a change makes to the store.
    public enum Write: Sendable, Equatable {
        case put(KeptPlaylist)
        case delete(String)
    }

    /// What a change does to the songs, in order: a playlist's origin taken from songs (deleted with none left), or
    /// songs asked for under it.
    public enum Effect: Sendable, Equatable {
        case take([String], from: String)
        case ask([Song], for: String)
    }

    /// One moment's change: its write (none for the orphans' takes and a store's opening acts), what it does to the songs
    /// once that holds, and whether it takes an answer in (its playlist's serial moves).
    public struct Change: Sendable, Equatable {
        public let write: Write?
        public let effects: [Effect]
        public let takesIn: String?

        public init(write: Write?, effects: [Effect], takesIn: String? = nil) {
            self.write = write
            self.effects = effects
            self.takesIn = takesIn
        }
    }

    public func entry(_ id: String) -> KeptPlaylist? { kept.first { (entry: KeptPlaylist) -> Bool in entry.id == id } }

    /// The playlist's serial now - captured as a read goes out, handed back with its answer.
    public func serial(_ id: String) -> Int { serials[id] ?? 0 }

    // MARK: the moments

    /// A store opened: the songs of each playlist no longer kept let go (an orphan's origin), by playlist id, then each
    /// playlist's asks and takes.
    public func opened(origins: [String: Set<DownloadOrigin>], carrying: (String) -> Set<String>) -> [Change] {
        let orphans = PlaylistDownloads.orphans(origins, kept: Set(kept.map(\.id)))
        var out = orphans.keys.sorted().map { (id: String) -> Change in
            Change(write: nil, effects: [.take(orphans[id]!, from: id)])
        }
        for entry in kept {
            let effects = Self.effects(entry, carrying: carrying(entry.id))
            if !effects.isEmpty { out.append(Change(write: nil, effects: effects)) }
        }
        return out
    }

    /// Download on a playlist: kept as it is in hand, its songs asked for - nil when it is kept already, or smart.
    public func download(_ answer: PlaylistWithSongs, body: Data, at: Int64, carrying: Set<String>) -> Change? {
        guard entry(answer.playlist.id) == nil, PlaylistDownloads.downloadable(answer.playlist) else { return nil }
        let started = PlaylistDownloads.started(answer, body: body, at: at)
        return Change(write: .put(started), effects: Self.effects(started, carrying: carrying))
    }

    /// Remove Download, or a playlist let go (deleted here, gone from two lists): its row deleted, then its origin taken
    /// from every song carrying it - nil when it isn't kept.
    public func remove(_ id: String, carrying: Set<String>) -> Change? {
        guard entry(id) != nil else { return nil }
        let songs = carrying.sorted()
        return Change(write: .delete(id), effects: songs.isEmpty ? [] : [.take(songs, from: id)])
    }

    /// An answer in hand for a kept playlist - a page's, or this phone's Edit's (`edited`: the songs it took out) - taken
    /// in as a read's is, then acted on. Nil when it isn't kept.
    public func took(_ answer: PlaylistWithSongs, body: Data, at: Int64, edited: Set<String> = [],
                     carrying: Set<String>) -> Change? {
        guard let entry = entry(answer.playlist.id) else { return nil }
        let read = PlaylistDownloads.read(entry, answer: answer, body: body, carrying: carrying, at: at, edited: edited)
        return Change(write: .put(read), effects: Self.effects(read, carrying: carrying), takesIn: entry.id)
    }

    /// A read's answer, the read asked for at `at` with the serial then (`since`): taken in as `took`'s - or nil when a
    /// newer answer was taken in meanwhile, or it is no longer kept.
    public func answered(_ answer: PlaylistWithSongs, body: Data, at: Int64, since: Int, carrying: Set<String>) -> Change? {
        guard serial(answer.playlist.id) == since else { return nil }
        return took(answer, body: body, at: at, carrying: carrying)
    }

    /// A read answered 404 at `at`: a list without it (PlaylistDownloads.missing) - marked, or let go when that was
    /// ten minutes ago. Nil when a newer answer was taken in meanwhile, or it is no longer kept.
    public func gone(_ id: String, at: Int64, since: Int, carrying: Set<String>) -> Change? {
        guard serial(id) == since, let entry = entry(id) else { return nil }
        let marked = PlaylistDownloads.missing(entry, at: at)
        return marked.gone ? remove(id, carrying: carrying) : Change(write: .put(marked.entry), effects: [])
    }

    /// The list asked for at `at`: each playlist whose marks moved written, each gone let go - and those to read.
    public func listed(_ list: [Playlist], at: Int64, carrying: (String) -> Set<String>)
        -> (changes: [Change], toRead: [String]) {
        let out = PlaylistDownloads.listed(kept, list: list, at: at)
        var changes: [Change] = []
        for entry in out.kept where self.entry(entry.id) != entry {
            changes.append(Change(write: .put(entry), effects: []))
        }
        for id in out.letGo {
            if let change = remove(id, carrying: carrying(id)) { changes.append(change) }
        }
        return (changes, out.toRead)
    }

    /// Its asks and takes, in Actions' order: the takes first.
    static func effects(_ entry: KeptPlaylist, carrying: Set<String>) -> [Effect] {
        let actions = PlaylistDownloads.actions(entry, carrying: carrying)
        var out: [Effect] = []
        if !actions.take.isEmpty { out.append(.take(actions.take, from: entry.id)) }
        if !actions.ask.isEmpty { out.append(.ask(actions.ask, for: entry.id)) }
        return out
    }

    // MARK: making one

    /// A change whose write held, taken into memory: the row put (in its place, or last) or deleted, the serial moved.
    public mutating func apply(_ change: Change) {
        switch change.write {
        case .put(let entry):
            if let index = kept.firstIndex(where: { (kept: KeptPlaylist) -> Bool in kept.id == entry.id }) {
                kept[index] = entry
            } else {
                kept.append(entry)
            }
        case .delete(let id):
            kept.removeAll { (kept: KeptPlaylist) -> Bool in kept.id == id }
        case nil:
            break
        }
        if let id = change.takesIn { serials[id, default: 0] += 1 }
    }

    /// Everything kept let go (Remove All emptied the store, the store closed).
    public mutating func clear() {
        kept = []
        serials = [:]
    }

    /// A change made: `write` first - if it throws, nothing else happens and false is answered - then `apply`, then the
    /// effects in order, a `take` answered false (the store couldn't be written) stopping the rest. `apply` is handed in
    /// (the keeper's own short mutation) rather than this being a mutating call, so the takes and asks run with nothing
    /// of the keeper held.
    public static func run(_ change: Change, write: (Write) throws -> Void, apply: (Change) -> Void,
                           take: ([String], String) -> Bool, ask: ([Song], String) -> Void) -> Bool {
        if let made = change.write {
            do {
                try write(made)
            } catch {
                return false
            }
        }
        apply(change)
        for effect in change.effects {
            switch effect {
            case .take(let songs, let id):
                guard take(songs, id) else { return true }
            case .ask(let songs, let id):
                ask(songs, id)
            }
        }
        return true
    }
}
