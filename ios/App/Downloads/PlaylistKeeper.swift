import DeadwaxCore
import Foundation
import Observation

/// The downloaded playlists (Phase 4, slice 3; phase4-library.md 2.5): kept on this phone with their last answers (the
/// store's `playlist` table), and kept in step with deadwax - every rule Core's (PlaylistDownloads). DownloadModel owns
/// it beside the library's follower, opened and closed with the store; what it asks for and lets go goes through
/// DownloadModel's own `want` and `removeOrigins` (`ask`, `take`), so a song another origin keeps always stays.
///
/// **When it looks** - the library follower's cadence (LibraryFollow.due): a store opened, the app back in front (a
/// minute since the last look), deadwax back, and every 15 minutes while the app is alive - and, on the minute, when a
/// second read or a missing playlist's confirmation is due (PlaylistDownloads.nextLook). A look lists the playlists,
/// then reads each one the list says to (its `changed` moved, or the list was empty) and each due its second read. Only
/// while something is downloaded, and only while deadwax can be asked.
///
/// **Changes here** - an add (the picker), or a write answered gone, reads the playlist now; this phone's Edit takes in
/// the answer its Done was given with `here`, so the songs the Edit took out go at once; a delete here lets it go at
/// once; and every answer a playlist's page is given (or its 404) is taken in as a read's is - so opening it twice ten
/// minutes apart agrees on a song gone. A read answered after a newer answer was taken in is dropped (`takenIn`): it
/// would bring back what an Edit here took out.
@MainActor
@Observable
final class PlaylistKeeper {
    /// The downloaded playlists, in the order they were downloaded.
    private(set) var kept: [KeptPlaylist] = []
    /// The last look or read failed: why, in the system's words (Debug's).
    private(set) var problem: String?

    /// The downloads log (DownloadModel.note).
    @ObservationIgnored var note: (String) -> Void = { _ in }
    /// The songs the store has under a playlist's origin.
    @ObservationIgnored var carrying: (String) -> Set<String> = { _ in [] }
    /// Every song's origins - the orphans' (PlaylistDownloads.orphans).
    @ObservationIgnored var origins: () -> [String: Set<DownloadOrigin>] = { [:] }
    /// Songs asked for under a playlist's origin (DownloadModel's want).
    @ObservationIgnored var ask: ([Song], String) -> Void = { _, _ in }
    /// A playlist's origin taken from songs (DownloadModel's removeOrigins) - false when the store couldn't be written.
    @ObservationIgnored var take: ([String], String) -> Bool = { _, _ in true }

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private var store: DownloadStore?
    /// When the last look began (ms) - `due`'s.
    @ObservationIgnored private var lastBegan: Int64?
    /// A look asked for and not yet made.
    @ObservationIgnored private var pending: LibraryCheck?
    /// Reads asked for, by playlist id: whether each follows this phone's own Edit.
    @ObservationIgnored private var reads: [String: Bool] = [:]
    /// Moves on each answer taken in for a playlist: a read answered after a newer answer was taken in - this phone's
    /// Edit's, a page's - is older than what is kept, and dropped (else what the Edit took out would come back).
    @ObservationIgnored private var takenIn: [String: Int] = [:]
    @ObservationIgnored private var running = false
    /// Bumped as the store opens and closes: a run of an older one stops, its answers dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var wasOnline = true

    init(server: ServerModel, reachability: Reachability) {
        self.server = server
        self.reachability = reachability
        wasOnline = reachability.online
    }

    // MARK: reading

    /// The playlist is downloaded.
    func isKept(_ id: String) -> Bool { kept.contains { $0.id == id } }

    /// The downloaded playlist's kept entry.
    func entry(_ id: String) -> KeptPlaylist? { kept.first { $0.id == id } }

    // MARK: the moments

    /// A store opened: its playlists read back, the songs of a playlist no longer kept let go (an orphan's origin -
    /// the app gone between a row's delete and the take), each playlist's asks and takes made, and a look.
    func opened(_ opened: DownloadStore) {
        store = opened
        generation += 1
        reads = [:]
        pending = nil
        do {
            kept = try opened.database.playlists()
        } catch {
            kept = []
            say("couldn't read the downloaded playlists: \(error)")
            return
        }
        let orphans = PlaylistDownloads.orphans(origins(), kept: Set(kept.map(\.id)))
        for (id, songs) in orphans.sorted(by: { (a: (key: String, value: [String]), b: (key: String, value: [String])) -> Bool in a.key < b.key }) {
            note("playlists: \(id) no longer downloaded - \(songs.count) songs let go")
            _ = take(songs, id)
        }
        for entry in kept { act(entry) }
        startTimer()
        look(.opened)
    }

    /// The store closed (signed out, another person): nothing of theirs stays in memory.
    func closed() {
        store = nil
        generation += 1
        timer?.cancel()
        timer = nil
        kept = []
        reads = [:]
        takenIn = [:]
        pending = nil
        problem = nil
        lastBegan = nil
    }

    /// The app came to the front: a look when due.
    func cameToFront() { look(.front) }

    /// deadwax answers again after it couldn't be reached: a look.
    func reachabilityChanged() {
        let online = reachability.online
        defer { wasOnline = online }
        if online && !wasOnline { look(.back) }
    }

    /// Remove All Downloads emptied the store, the playlists with it: nothing kept in memory either.
    func removedAll() {
        kept = []
        reads = [:]
    }

    // MARK: the actions

    /// Download on a playlist (its page's control, its •••): kept as it is in hand, its songs asked for at once under its
    /// origin - then read again, so the answer kept is deadwax's own. Nothing if it is downloaded already.
    func download(_ answer: PlaylistWithSongs) {
        guard let store, !isKept(answer.playlist.id) else { return }
        let body = (try? JSONEncoder().encode(answer)) ?? Data()
        let entry = PlaylistDownloads.started(answer, body: body, at: ListenTracker.wallMs())
        do {
            try store.database.putPlaylist(entry)
        } catch {
            say("couldn't keep \(answer.playlist.id): \(error)")
            return
        }
        kept.append(entry)
        note("playlists: \(entry.id) downloaded (\(entry.songIDs.count) songs)")
        act(entry)
        read(entry.id, here: false)
    }

    /// Remove Download on a playlist: its row first, then its origin taken from every song carrying it - a song kept
    /// any other way stays. (A quit between the two leaves an orphan's origin, taken as the store opens.)
    func remove(_ id: String) {
        guard let store else { return }
        do {
            try store.database.deletePlaylist(id)
        } catch {
            say("couldn't remove \(id): \(error)")
            return
        }
        kept.removeAll { $0.id == id }
        reads[id] = nil
        note("playlists: \(id) removed")
        _ = take(carrying(id).sorted(), id)
    }

    /// A write here changed the playlist (PlaylistsModel's): an add, or a write answered gone, reads it now; this phone's
    /// Edit takes in the answer its Done was given with `here` (what it took out goes at once); a delete lets it go at
    /// once.
    func written(_ id: String, _ kind: PlaylistsModel.Wrote) {
        guard isKept(id) else { return }
        switch kind {
        case .deleted:
            note("playlists: \(id) deleted here - let go")
            remove(id)
        case .edited(let answer):
            took(answer, here: true)
        case .added, .gone:
            read(id, here: false)
        }
    }

    /// An answer for a downloaded playlist in hand - its page's, or the one this phone's Edit was answered with
    /// (`here`) - taken in as a read's is (PlaylistDownloads.read), kept, and acted on.
    func took(_ answer: PlaylistWithSongs, here: Bool) {
        let id = answer.playlist.id
        guard let store, let index = kept.firstIndex(where: { $0.id == id }) else { return }
        let body = (try? JSONEncoder().encode(answer)) ?? Data()
        let entry = PlaylistDownloads.read(kept[index], answer: answer, body: body, carrying: carrying(id),
                                           at: ListenTracker.wallMs(), here: here)
        try? store.database.putPlaylist(entry)
        kept[index] = entry
        takenIn[id, default: 0] += 1
        act(entry)
    }

    /// The playlist read now (after the look under way, if any) - `here` after this phone's own Edit.
    func read(_ id: String, here: Bool) {
        guard store != nil, isKept(id) else { return }
        reads[id] = (reads[id] ?? false) || here
        if !running { Task { await run() } }
    }

    /// A look for `reason`, when due (PlaylistDownloads.due): made now, or once the one under way ends.
    func look(_ reason: LibraryCheck) {
        guard store != nil, !kept.isEmpty else { return }
        if PlaylistDownloads.due(reason, lastBegan: lastBegan, now: ListenTracker.wallMs(), kept: kept), pending == nil {
            pending = reason
        }
        // a read asked for while deadwax couldn't be asked is made at the next look, due or not
        guard pending != nil || !reads.isEmpty else { return }
        if !running { Task { await run() } }
    }

    // MARK: the run

    private var canAsk: Bool {
        reachability.online && server.launch == .ready && server.signInOver == nil && server.client != nil
    }

    /// A look asked for, then the reads asked for and due, until nothing is left that can be done now - each read once
    /// a run, so one that fails waits for the next.
    private func run() async {
        guard !running else { return }
        running = true
        let mine = generation
        var tried = Set<String>()
        defer {
            running = false
            // asked for while a stopping run was ending: made by a run of its own
            if mine != generation, store != nil, pending != nil || !reads.isEmpty { Task { await run() } }
        }
        while mine == generation, store != nil {
            guard canAsk, let client = server.client else { return }
            if pending != nil {
                pending = nil
                lastBegan = ListenTracker.wallMs()
                await list(client, generation: mine)
                continue
            }
            let now = ListenTracker.wallMs()
            for id in PlaylistDownloads.dueReads(kept, now: now) where reads[id] == nil && !tried.contains(id) {
                reads[id] = false
            }
            guard let id = reads.keys.sorted().first(where: { (id: String) -> Bool in !tried.contains(id) }) else {
                return
            }
            let here = reads.removeValue(forKey: id) ?? false
            tried.insert(id)
            await readOne(id, here: here, client: client, generation: mine)
        }
    }

    /// The list asked for: each downloaded playlist marked, read, or let go (PlaylistDownloads.listed).
    private func list(_ client: DeadwaxClient, generation mine: Int) async {
        let at = ListenTracker.wallMs()
        do {
            let list = try await client.playlists()
            guard mine == generation, let store else { return }
            let before = kept
            let out = PlaylistDownloads.listed(kept, list: list, at: at)
            for entry in out.kept where before.first(where: { $0.id == entry.id }) != entry {
                try? store.database.putPlaylist(entry)
            }
            kept = out.kept
            for id in out.letGo {
                note("playlists: \(id) missing from two lists ten minutes apart - let go")
                letGo(id)
            }
            for id in out.toRead where reads[id] == nil { reads[id] = false }
            problem = nil
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return }
            say("couldn't list the playlists: \(error)")
        }
    }

    /// One playlist read: its answer taken in by PlaylistDownloads.read, kept, and acted on - a 404 a list without it.
    private func readOne(_ id: String, here: Bool, client: DeadwaxClient, generation mine: Int) async {
        let at = ListenTracker.wallMs()
        let before = takenIn[id, default: 0]
        do {
            let answered = try await client.playlistAnswered(id: id)
            guard mine == generation, let store, let index = kept.firstIndex(where: { $0.id == id }) else { return }
            // a newer answer was taken in while this one was out: this one is older than what is kept
            guard takenIn[id, default: 0] == before else { return }
            let entry = PlaylistDownloads.read(kept[index], answer: answered.playlist, body: answered.body,
                                               carrying: carrying(id), at: at, here: here)
            try? store.database.putPlaylist(entry)
            kept[index] = entry
            takenIn[id, default: 0] += 1
            problem = nil
            act(entry)
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error), takenIn[id, default: 0] == before,
                  let index = kept.firstIndex(where: { $0.id == id }) else { return }
            guard ErrorWords.kind(of: error) == .notFound else {
                say("couldn't read \(id): \(error)")
                return
            }
            let marked = PlaylistDownloads.missing(kept[index], at: at)
            if marked.gone {
                note("playlists: \(id) answered gone ten minutes apart - let go")
                letGo(id)
            } else {
                try? store?.database.putPlaylist(marked.entry)
                kept[index] = marked.entry
                note("playlists: \(id) answered gone - marked")
            }
        }
    }

    /// What the playlist asks of the store now: its songs not carrying its origin asked for, its agreed-left songs'
    /// origin taken.
    private func act(_ entry: KeptPlaylist) {
        let actions = PlaylistDownloads.actions(entry, carrying: carrying(entry.id))
        if !actions.take.isEmpty {
            note("playlists: \(entry.id) - \(actions.take.count) songs no longer in it")
            guard take(actions.take, entry.id) else { return }
        }
        if !actions.ask.isEmpty {
            note("playlists: \(entry.id) - asked \(actions.ask.count) songs")
            ask(actions.ask, entry.id)
        }
    }

    /// A playlist gone: its row and its origin let go.
    private func letGo(_ id: String) {
        guard let store else { return }
        try? store.database.deletePlaylist(id)
        kept.removeAll { $0.id == id }
        reads[id] = nil
        _ = take(carrying(id).sorted(), id)
    }

    /// A look every minute while the app is alive: due every 15 minutes, or when a second read or a missing playlist's
    /// confirmation is.
    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.look(.timer)
            }
        }
    }

    private func say(_ words: String) {
        problem = words
        note("playlists: \(words)")
    }
}
