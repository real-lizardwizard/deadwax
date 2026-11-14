import DeadwaxCore
import Foundation
import Observation

/// The downloaded playlists (Phase 4, slice 3; phase4-library.md 2.5): kept on this phone with their last answers (the
/// store's `playlist` table), and kept in step with deadwax - every rule Core's (PlaylistDownloads), and every change's
/// order too (PlaylistKeeping, slice 3's review): its one write to the store first, then - only once that holds - into
/// memory, then what it does to the songs, a take that fails stopping the asks after it. DownloadModel owns it beside the
/// library's follower, opened and closed with the store; what it asks for and lets go goes through DownloadModel's own
/// `want` and `removeOrigins` (`ask`, `take`), so a song another origin keeps always stays.
///
/// **When it looks** - the library follower's cadence (LibraryFollow.due): a store opened, the app back in front (a
/// minute since the last look), deadwax back, and every 15 minutes while the app is alive - and, on the minute, when a
/// second read or a missing playlist's confirmation is due (PlaylistDownloads.nextLook). A look lists the playlists,
/// then reads each one the list says to (its `changed` moved, or the list was empty) and each due its second read. Only
/// while something is downloaded, and only while deadwax can be asked. A list that fails leaves the last look's time as
/// it was, so the next minute's timer looks again (the follower's rule).
///
/// **Changes here** - an add (the picker), or a write answered gone, reads the playlist now; this phone's Edit takes in
/// the answer its Done was given, the songs it took out going at once (and only those: PlaylistEditBody.removed); a
/// delete here lets it go at once; and every answer a playlist's page is given (or its 404) is taken in as a read's is -
/// so opening it twice ten minutes apart agrees on a song gone. A read answered after a newer answer was taken in is
/// dropped (PlaylistKeeping's serial): it would bring back what an Edit here took out.
///
/// **Smart playlists** (slice 3's review, James: "No Download for them") are never downloaded; one downloaded before
/// deadwax said it was smart is kept as it was, never read again, until its Remove Download.
@MainActor
@Observable
final class PlaylistKeeper {
    /// The downloaded playlists and their answers' serials.
    private(set) var keeping = PlaylistKeeping()
    /// The last look or read failed: why, in the system's words (Debug's).
    private(set) var problem: String?

    /// The downloaded playlists, in the order they were downloaded.
    var kept: [KeptPlaylist] { keeping.kept }

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
    /// Reads asked for, by playlist id.
    @ObservationIgnored private var reads = Set<String>()
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
    func isKept(_ id: String) -> Bool { keeping.entry(id) != nil }

    /// The downloaded playlist's kept entry.
    func entry(_ id: String) -> KeptPlaylist? { keeping.entry(id) }

    // MARK: the moments

    /// A store opened: its playlists read back, the songs of a playlist no longer kept let go (an orphan's origin -
    /// the app gone between a row's delete and the take), each playlist's asks and takes made, and a look.
    func opened(_ opened: DownloadStore) {
        store = opened
        generation += 1
        reads = []
        pending = nil
        do {
            keeping = PlaylistKeeping(kept: try opened.database.playlists())
        } catch {
            keeping = PlaylistKeeping()
            say("couldn't read the downloaded playlists: \(error)")
            return
        }
        for change in keeping.opened(origins: origins(), carrying: carrying) { perform(change, "act at opening") }
        startTimer()
        look(.opened)
    }

    /// The store closed (signed out, another person): nothing of theirs stays in memory.
    func closed() {
        store = nil
        generation += 1
        timer?.cancel()
        timer = nil
        keeping.clear()
        reads = []
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
        keeping.clear()
        reads = []
    }

    // MARK: the actions

    /// Download on a playlist (its page's control, its •••): kept as it is in hand, its songs asked for at once under its
    /// origin - then read again, so the answer kept is deadwax's own. Nothing if it is downloaded already, or smart.
    func download(_ answer: PlaylistWithSongs) {
        let id = answer.playlist.id
        guard store != nil else { return }
        let body = (try? JSONEncoder().encode(answer)) ?? Data()
        guard let change = keeping.download(answer, body: body, at: ListenTracker.wallMs(), carrying: carrying(id)),
              perform(change, "keep \(id)") else { return }
        note("playlists: \(id) downloaded (\(entry(id)?.songIDs.count ?? 0) songs)")
        read(id)
    }

    /// Remove Download on a playlist: its row first, then its origin taken from every song carrying it - a song kept
    /// any other way stays. (A quit between the two leaves an orphan's origin, taken as the store opens.)
    func remove(_ id: String) {
        guard let change = keeping.remove(id, carrying: carrying(id)), perform(change, "remove \(id)") else { return }
        reads.remove(id)
        note("playlists: \(id) removed")
    }

    /// A write here changed the playlist (PlaylistsModel's): an add, or a write answered gone, reads it now; this phone's
    /// Edit takes in the answer its Done was given, the songs it took out going at once, and reads it
    /// again; a delete lets it go at once.
    func written(_ id: String, _ kind: PlaylistsModel.Wrote) {
        guard isKept(id) else { return }
        switch kind {
        case .deleted:
            note("playlists: \(id) deleted here - let go")
            remove(id)
        case .edited(let answer, let removed):
            took(answer, edited: removed)
            read(id)
        case .added, .gone:
            read(id)
        }
    }

    /// An answer for a downloaded playlist in hand - its page's, or the one this phone's Edit was answered with
    /// (`edited`: the songs it took out) - taken in as a read's is (PlaylistDownloads.read), kept, and acted on.
    func took(_ answer: PlaylistWithSongs, edited: Set<String> = []) {
        let id = answer.playlist.id
        guard store != nil else { return }
        let body = (try? JSONEncoder().encode(answer)) ?? Data()
        guard let change = keeping.took(answer, body: body, at: ListenTracker.wallMs(), edited: edited,
                                        carrying: carrying(id)) else { return }
        perform(change, "keep \(id)'s answer")
    }

    /// The playlist read now (after the look under way, if any).
    func read(_ id: String) {
        guard store != nil, isKept(id) else { return }
        reads.insert(id)
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
    /// a run, so one that fails waits for the next. A read asked for again while this run was out (one it had tried
    /// already) gets a run of its own once this ends.
    private func run() async {
        guard !running else { return }
        running = true
        let mine = generation
        var tried = Set<String>()
        defer {
            running = false
            // asked for while a stopping run was ending, or asked again after this run had tried it: a run of its own -
            // only while deadwax can be asked (else the next look makes it)
            if store != nil, pending != nil || !reads.isEmpty, mine != generation || canAsk { Task { await run() } }
        }
        while mine == generation, store != nil {
            guard canAsk, let client = server.client else { return }
            if pending != nil {
                pending = nil
                // set as it goes out, so a moment while it is out doesn't ask another; put back if it fails
                let began = ListenTracker.wallMs()
                let beganBefore = lastBegan
                lastBegan = began
                if !(await list(client, generation: mine)), lastBegan == began { lastBegan = beganBefore }
                continue
            }
            let now = ListenTracker.wallMs()
            for id in PlaylistDownloads.dueReads(kept, now: now) where !tried.contains(id) { reads.insert(id) }
            guard let id = reads.sorted().first(where: { (id: String) -> Bool in !tried.contains(id) }) else { return }
            reads.remove(id)
            tried.insert(id)
            await readOne(id, client: client, generation: mine)
        }
    }

    /// The list asked for: each downloaded playlist marked, read, or let go (PlaylistKeeping.listed) - false when it
    /// failed or the store changed while it was out.
    private func list(_ client: DeadwaxClient, generation mine: Int) async -> Bool {
        let at = ListenTracker.wallMs()
        do {
            let list = try await client.playlists()
            guard mine == generation, store != nil else { return false }
            let out = keeping.listed(list, at: at, carrying: carrying)
            for change in out.changes {
                if case .delete(let id) = change.write {
                    note("playlists: \(id) missing from two lists ten minutes apart - let go")
                    reads.remove(id)
                }
                perform(change, "keep the list's marks")
            }
            for id in out.toRead { reads.insert(id) }
            problem = nil
            return true
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return false }
            say("couldn't list the playlists: \(error)")
            return false
        }
    }

    /// One playlist read: its answer taken in by PlaylistDownloads.read, kept, and acted on - a 404 a list without it.
    private func readOne(_ id: String, client: DeadwaxClient, generation mine: Int) async {
        let at = ListenTracker.wallMs()
        let since = keeping.serial(id)
        do {
            let answered = try await client.playlistAnswered(id: id)
            guard mine == generation, store != nil else { return }
            // nil: no longer kept, or a newer answer was taken in while this one was out (this one is older)
            guard let change = keeping.answered(answered.playlist, body: answered.body, at: at, since: since,
                                                carrying: carrying(id)) else { return }
            if perform(change, "keep \(id)'s answer") { problem = nil }
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return }
            guard ErrorWords.kind(of: error) == .notFound else {
                say("couldn't read \(id): \(error)")
                return
            }
            guard let change = keeping.gone(id, at: at, since: since, carrying: carrying(id)) else { return }
            if case .delete = change.write {
                note("playlists: \(id) answered gone ten minutes apart - let go")
                reads.remove(id)
            } else {
                note("playlists: \(id) answered gone - marked")
            }
            perform(change, "mark \(id) gone")
        }
    }

    /// A change made (PlaylistKeeping.run): its write to the store, then - only once that holds - into memory and onto
    /// the songs. False, with why in Debug's words, when the write failed.
    @discardableResult
    private func perform(_ change: PlaylistKeeping.Change, _ what: String) -> Bool {
        guard let store else { return false }
        var failure: (any Error)?
        let made = PlaylistKeeping.run(change, write: { (write: PlaylistKeeping.Write) throws -> Void in
            do {
                switch write {
                case .put(let entry): try store.database.putPlaylist(entry)
                case .delete(let id): try store.database.deletePlaylist(id)
                }
            } catch {
                failure = error
                throw error
            }
        }, apply: { (made: PlaylistKeeping.Change) -> Void in
            self.keeping.apply(made)
        }, take: { (songs: [String], id: String) -> Bool in
            self.note("playlists: \(id) - \(songs.count) songs let go")
            return self.take(songs, id)
        }, ask: { (songs: [Song], id: String) -> Void in
            self.note("playlists: \(id) - asked \(songs.count) songs")
            self.ask(songs, id)
        })
        if !made { say("couldn't \(what): \(failure.map { (error: any Error) -> String in "\(error)" } ?? "")") }
        return made
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
