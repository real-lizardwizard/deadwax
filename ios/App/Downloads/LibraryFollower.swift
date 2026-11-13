import DeadwaxCore
import Foundation
import Observation

/// Your library followed from deadwax onto this phone (notes/ios-specs/phase3-autodownload.md 2.2-2.4, 2.7): the checks
/// and their minute timer, each album's songs read four at a time in the order they would come onto the phone, the
/// question an empty list or a large drop asks, and the marks Remove Download and Download set. Every rule is Core's
/// (LibraryFollow, LibraryFill, LibraryDownloads); this asks deadwax, keeps the answers in the person's download store
/// (its `library` table and meta) and says what happened in the downloads log.
///
/// **It deletes nothing itself.** DownloadModel works out at every plan what the library asks for and gives back
/// (LibraryDownloads.turn) from what this keeps: `ordered`, the albums checks `removed`, and `readsPending`. The only
/// thing that ever lets a library download go is DownloadModel taking the library's own origin through Phase 2's
/// removeOrigins.
///
/// **The switch** (slice 2) is You > Downloads' Download your library, per phone (AutoDownload.libraryKey) and off until
/// chosen. Off: checks stop, the library's origin is taken from every song (`switchedOff`), the table is kept - so
/// turning it on again says "N of M" at once.
///
/// One thing at a time: a check, then the reads; a check asked for while reads run is made after the batch in hand,
/// then the reads go on. Nothing is asked while deadwax can't be reached or the person must sign in - a check that
/// can't answer changes nothing anyway.
@MainActor
@Observable
final class LibraryFollower {
    /// Slice 1's Debug switch, retired: its key let go.
    private static let slice1Key = "debugFollowLibrary"

    /// Download your library (or the collection) - You > Downloads' switch.
    var on: Bool {
        didSet {
            guard on != oldValue else { return }
            UserDefaults.standard.set(on, forKey: AutoDownload.libraryKey)
            if on {
                note("library: on")
                fresh = false
                restore()
                startTimer()
                check(.byHand)
            } else {
                note("library: off - its downloads let go, the list kept")
                stop()
                switchedOff()
            }
            changed()
        }
    }

    // MARK: what the screens read

    /// The library in the order its albums come onto the phone (LibraryFollow.ordered), songs as read.
    private(set) var ordered: [FollowedAlbum] = []
    /// What is followed: yours, or the collection.
    private(set) var scope: AlbumScope?
    /// Why the last list's absences weren't believed.
    private(set) var held: LibraryFollow.Held?
    /// You said Keep Them to the question: put away until a list is believed again.
    private(set) var keptThem = false
    /// You said Remove: the held list is believed - its absences go by the same two checks as any.
    private(set) var believing = false
    /// The last check, answered or not.
    private(set) var lastCheck: LibraryCheckRecord?
    /// When the last check that answered began (ms) - "Checked 3 minutes ago".
    private(set) var lastAnswered: Int64?
    /// A check is out.
    private(set) var checking = false
    /// Albums' songs being read now.
    private(set) var readingNow = 0
    /// The first read of every album's songs (R13): how long, and how many albums - once it has ended.
    private(set) var firstRead: (seconds: Double, albums: Int)?
    /// The store couldn't be read or written: its words.
    private(set) var problem: String?
    /// The albums checks removed whose library downloads DownloadModel hasn't let go yet.
    private(set) var removed: Set<String> = []
    /// The last check's failure, for You > Downloads' footer (ErrorNote's split) - nil once one answers.
    private(set) var lastError: (any Error)?
    /// A check has answered since the store opened or the switch went on: until then the kept list may be days old, so
    /// nothing new is asked for from it (what it gives back is the fill's and the checks', and stands).
    private(set) var fresh = false

    /// The question (3.1) is asked now.
    var asks: Bool { on && LibraryFollow.asks(held, keptThem: keptThem) }

    /// Albums' songs are still being read this run: nothing is asked for below the first one (LibraryDownloads.actions).
    var readsPending: Bool { running && !LibraryFollow.toRead(ordered).isEmpty }

    /// (read, of): the listed albums whose songs are read, of every listed album - "Reading your library - 1,240 of
    /// 3,010 albums" while some aren't.
    var reading: (read: Int, of: Int) {
        let listed = ordered.filter(\.isListed)
        return (listed.filter { $0.songs != nil }.count, listed.count)
    }

    // MARK: kept

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    /// The downloads log (DownloadModel.note).
    @ObservationIgnored var note: (String) -> Void = { _ in }
    /// Something the library's turn reads changed: a check kept, songs read, a mark - DownloadModel plans again.
    @ObservationIgnored var changed: () -> Void = {}
    /// The switch went off: DownloadModel takes the library's origin from every song.
    @ObservationIgnored var switchedOff: () -> Void = {}
    @ObservationIgnored private var store: DownloadStore?
    @ObservationIgnored private var etag: String?
    /// When the last check began (ms) - `due`'s.
    @ObservationIgnored private var lastBegan: Int64?
    /// A check asked for and not yet made: the first reason asked.
    @ObservationIgnored private var pending: LibraryCheck?
    @ObservationIgnored private var running = false
    /// Bumped as the store closes or the switch goes off: a run of an older one stops.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The first read under way: when it began (the run's clock) and how many albums it reads.
    @ObservationIgnored private var firstReadBegan: ContinuousClock.Instant?
    @ObservationIgnored private var firstReadAlbums = 0
    @ObservationIgnored private var wasOnline = true

    init(server: ServerModel, reachability: Reachability) {
        self.server = server
        self.reachability = reachability
        UserDefaults.standard.removeObject(forKey: Self.slice1Key)
        on = UserDefaults.standard.bool(forKey: AutoDownload.libraryKey)
        wasOnline = reachability.online
    }

    // MARK: the moments (2.2)

    /// A store opened: launch, a sign-in, another person.
    func opened(_ opened: DownloadStore) {
        store = opened
        generation += 1
        fresh = false
        guard on else { return }
        restore()
        startTimer()
        check(.opened)
    }

    /// The store closed (signed out, another person): nothing of theirs stays in memory.
    func closed() {
        store = nil
        generation += 1
        timer?.cancel()
        timer = nil
        clearMemory()
    }

    /// The app came to the front.
    func cameToFront() { check(.front) }

    /// The network or deadwax's answer changed: back after it couldn't be reached, a check.
    func reachabilityChanged() {
        let online = reachability.online
        defer { wasOnline = online }
        if online && !wasOnline { check(.back) }
    }

    /// Add to or Remove from my library answered in this app (`at`: when it answered, ms): a Remove marks the album so the
    /// next list without it removes it at once; either way, a check now.
    func changedHere(album: String, removed: Bool, at: Int64) {
        guard on, let store else { return }
        if removed {
            do {
                if try store.database.setRemovedHere(album: album, at: at),
                   let index = ordered.firstIndex(where: { $0.id == album }) {
                    ordered[index].removedHere = at
                }
            } catch {
                say("couldn't mark a removal: \(error)")
            }
            changed()
        }
        check(.changedHere)
    }

    /// A check for `reason`, when it is due (LibraryFollow.due): made now, or once the one under way ends.
    func check(_ reason: LibraryCheck) {
        guard on, store != nil else { return }
        guard LibraryFollow.due(reason, lastBegan: lastBegan, now: ListenTracker.wallMs()) else { return }
        if pending == nil { pending = reason }
        if !running { Task { await run() } }
    }

    // MARK: the marks and the question

    /// Remove Download on an album of your library (`at`, ms): left off this phone until downloaded again - or nil, its
    /// Download: the mark cleared. Whether the album is in the library.
    @discardableResult
    func setKeptOff(album: String, at: Int64?) -> Bool {
        guard let store else { return false }
        let index = ordered.firstIndex(where: { $0.id == album })
        if let index, ordered[index].keptOff == at { return true }
        do {
            // the store's row, whether or not the switch has it in memory (off, it isn't read)
            guard try store.database.setKeptOff(album: album, at: at) else { return false }
        } catch {
            say("couldn't mark a download kept off: \(error)")
            return false
        }
        guard let index else { return true }
        ordered[index].keptOff = at
        note("library: \(album) \(at == nil ? "downloaded again" : "kept off")")
        changed()
        return true
    }

    /// The question's Keep Them: nothing goes, and it isn't asked again until a list is believed.
    func keepThem() {
        guard let store else { return }
        try? store.database.setMeta(DownloadDatabase.libraryHeldKeptKey, "1")
        keptThem = true
        note("library: kept them")
    }

    /// The question's Remove: the held list is believed from the next check - a fresh list, not a 304 of the held one -
    /// and what it misses goes by the same rule as any: missing first, removed when a check ten minutes or more on agrees.
    func removeThem() {
        guard let store else { return }
        do {
            try store.database.transaction {
                try store.database.setMeta(DownloadDatabase.libraryBelieveKey, "1")
                try store.database.setMeta(DownloadDatabase.libraryHeldKeptKey, nil)
                try store.database.setMeta(DownloadDatabase.libraryETagKey, nil)
            }
        } catch {
            say("couldn't keep the answer: \(error)")
            return
        }
        believing = true
        keptThem = false
        etag = nil
        note("library: remove them - believed from the next list")
        check(.byHand)
    }

    /// DownloadModel let go of the library downloads of these removed albums (or they had none).
    func removalsDone(_ albums: Set<String>) {
        guard let store, !albums.isDisjoint(with: removed) else { return }
        let left = removed.subtracting(albums)
        do {
            try store.database.setMeta(DownloadDatabase.libraryRemovedKey, Self.joined(left))
        } catch {
            say("couldn't keep the removals: \(error)")
            return
        }
        removed = left
    }

    // MARK: the run

    private var canAsk: Bool {
        reachability.online && server.launch == .ready && server.signInOver == nil && server.client != nil
    }

    /// Checks asked for, then the reads, until nothing is left that can be done now.
    private func run() async {
        // two asked for before either began: the second finds the first running, and its check is the first's pending
        guard !running else { return }
        guard on, store != nil else {
            pending = nil
            return
        }
        running = true
        let mine = generation
        var failed = Set<String>()
        defer {
            running = false
            // the reads ended: what was held for them is asked for now
            if mine == generation { changed() }
            // a check asked for while an older run was stopping: made by a run of its own
            if pending != nil, on, store != nil { Task { await run() } }
        }
        while mine == generation, on {
            if let reason = pending {
                pending = nil
                failed = []
                await checkNow(reason, generation: mine)
                continue
            }
            guard canAsk, let client = server.client else { return }
            let unread = LibraryFollow.toRead(ordered, failed: failed)
            guard !unread.isEmpty else {
                firstReadEnded()
                return
            }
            let batch = Array(unread.prefix(LibraryFollow.readsAtOnce))
            readingNow = batch.count
            let results = await read(batch, client: client)
            readingNow = 0
            guard mine == generation, let store else { return }
            let at = ListenTracker.wallMs()
            var refused = 0
            for (id, outcome) in results {
                switch outcome {
                case .success(let songs):
                    do {
                        guard try store.database.setLibrarySongs(album: id, songs: songs, at: at) else { continue }
                    } catch {
                        say("couldn't keep an album's songs: \(error)")
                        return
                    }
                    if let index = ordered.firstIndex(where: { $0.id == id }) {
                        ordered[index].songs = songs
                        ordered[index].readAt = at
                    }
                case .failure(let error):
                    if APIFailure.isCancellation(error) { return }
                    failed.insert(id)
                    refused += 1
                    note(LibraryFollowWords.readFailed(id, String(describing: error)))
                }
            }
            changed()
            // every one of a batch refused: deadwax or the network is the matter - the next check reads on
            if refused == batch.count { return }
        }
    }

    /// One check: the list asked for with the last one's ETag, and what Core makes of it kept (2.3).
    private func checkNow(_ reason: LibraryCheck, generation mine: Int) async {
        guard let store, canAsk, let client = server.client else { return }
        let scope = AlbumScope.albums(for: server.me)
        if scope != self.scope {
            // another scope's list: its ETag says nothing of this one. The library is kept - so the list it answers
            // goes by the same rules as any, a large drop held and asked about, nothing removed on one list.
            do {
                try store.database.setMeta(DownloadDatabase.libraryScopeKey, scope.rawValue)
                try store.database.setMeta(DownloadDatabase.libraryETagKey, nil)
            } catch {
                say("couldn't keep the scope: \(error)")
                return
            }
            if self.scope != nil { note("library: now \(scope.rawValue)") }
            etag = nil
            self.scope = scope
        }
        let began = ListenTracker.wallMs()
        lastBegan = began
        checking = true
        defer { checking = false }
        let clock = ContinuousClock()
        let start = clock.now
        let wasEmpty = ordered.isEmpty
        do {
            let fetched = try await client.fetch(Routes.albumIndex, as: AlbumIndexAnswer.self,
                                                 query: [("scope", scope.rawValue)],
                                                 ifNoneMatch: wasEmpty ? nil : etag)
            guard mine == generation, self.store === store else { return }
            let answer: LibraryFollow.Answer
            var nextETag = etag
            var listed = 0
            switch fetched {
            case .fresh(let list, let tag):
                answer = .listed(list)
                nextETag = tag
                listed = list.albums.count
            case .unchanged:
                answer = .unchanged
            }
            let out = LibraryFollow.sync(ordered, answer: answer, held: held, at: began, believing: believing)
            let stillBelieving = believing && LibraryFollow.keepsBelieving(out, listed: answer != .unchanged)
            // removed and not yet let go - an album back in the list is no longer among them
            var nextRemoved = removed.union(out.removed)
            nextRemoved.subtract(out.albums.map(\.id))
            let nextKept = keptThem && out.held != nil
            do {
                try store.database.transaction {
                    try store.database.putLibrary(out.albums, replacing: ordered)
                    try store.database.setMeta(DownloadDatabase.libraryETagKey, nextETag)
                    try store.database.setMeta(DownloadDatabase.libraryHeldKey, out.held?.raw)
                    try store.database.setMeta(DownloadDatabase.libraryCheckedKey, String(began))
                    try store.database.setMeta(DownloadDatabase.libraryBelieveKey, stillBelieving ? "1" : nil)
                    try store.database.setMeta(DownloadDatabase.libraryHeldKeptKey, nextKept ? "1" : nil)
                    try store.database.setMeta(DownloadDatabase.libraryRemovedKey, Self.joined(nextRemoved))
                }
            } catch {
                say("couldn't keep the library: \(error)")
                return
            }
            etag = nextETag
            held = out.held
            believing = stillBelieving
            keptThem = nextKept
            removed = nextRemoved
            lastAnswered = began
            lastError = nil
            fresh = true
            ordered = LibraryFollow.ordered(out.albums, scope: scope, now: began)
            problem = nil
            let record = LibraryCheckRecord(reason: reason, result: answer == .unchanged ? .unchanged : .listed(albums: listed),
                                            began: began, seconds: Self.seconds(clock.now - start))
            lastCheck = record
            note(LibraryFollowWords.logLine(record, out) + (out.believed ? " - believed (Remove)" : ""))
            if wasEmpty, !out.added.isEmpty {
                firstReadBegan = clock.now
                firstReadAlbums = out.added.count
            }
            changed()
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return }
            let record = LibraryCheckRecord(reason: reason, result: .failed(String(describing: error)), began: began,
                                            seconds: Self.seconds(clock.now - start))
            lastCheck = record
            lastError = error
            note(LibraryFollowWords.logLine(record, nil))
        }
    }

    /// Each album's songs asked for at once (`GET /navidrome/albums/{id}`), what came of each.
    private func read(_ ids: [String], client: DeadwaxClient) async -> [(String, Result<[FollowedSong], any Error>)] {
        await withTaskGroup(of: (String, Result<[FollowedSong], any Error>).self) {
            (group: inout TaskGroup<(String, Result<[FollowedSong], any Error>)>) async -> [(String, Result<[FollowedSong], any Error>)] in
            for id in ids {
                group.addTask { () async -> (String, Result<[FollowedSong], any Error>) in
                    do {
                        let album = try await client.call(Routes.album, as: Album.self, path: ["album_id": id])
                        let songs: [FollowedSong] = (album.song ?? []).map { (song: Song) -> FollowedSong in FollowedSong(song) }
                        return (id, .success(songs))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            var out: [(String, Result<[FollowedSong], any Error>)] = []
            for await result in group { out.append(result) }
            // in the order asked, so the log reads in the fill's order
            return ids.compactMap { (id: String) -> (String, Result<[FollowedSong], any Error>)? in
                out.first(where: { $0.0 == id })
            }
        }
    }

    // MARK: kept

    /// The library as the store keeps it, into memory - once per store opened with the switch on.
    private func restore() {
        guard let store else { return }
        do {
            let kept = try store.database.library()
            let keptScope = try store.database.meta(DownloadDatabase.libraryScopeKey).flatMap(AlbumScope.init(rawValue:))
            scope = keptScope
            etag = try store.database.meta(DownloadDatabase.libraryETagKey)
            held = LibraryFollow.Held(raw: try store.database.meta(DownloadDatabase.libraryHeldKey))
            believing = try store.database.meta(DownloadDatabase.libraryBelieveKey) == "1"
            keptThem = try store.database.meta(DownloadDatabase.libraryHeldKeptKey) == "1"
            removed = Self.split(try store.database.meta(DownloadDatabase.libraryRemovedKey))
            lastAnswered = try store.database.meta(DownloadDatabase.libraryCheckedKey).flatMap { Int64($0) }
            firstRead = Self.firstRead(try store.database.meta(DownloadDatabase.libraryFirstReadKey))
            ordered = LibraryFollow.ordered(kept, scope: keptScope ?? .store, now: ListenTracker.wallMs())
            problem = nil
        } catch {
            say("couldn't read the library: \(error)")
        }
    }

    /// The switch off: nothing more asked, a run under way stopped. The store's library is kept.
    private func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        pending = nil
        readingNow = 0
        checking = false
    }

    private func clearMemory() {
        ordered = []
        scope = nil
        held = nil
        keptThem = false
        believing = false
        removed = []
        etag = nil
        lastCheck = nil
        lastError = nil
        lastAnswered = nil
        fresh = false
        lastBegan = nil
        pending = nil
        firstRead = nil
        firstReadBegan = nil
        firstReadAlbums = 0
        readingNow = 0
        checking = false
        problem = nil
    }

    /// The first read's end: every listed album's songs read - its time kept (Debug's, R13).
    private func firstReadEnded() {
        guard let began = firstReadBegan, LibraryFollow.toRead(ordered).isEmpty else { return }
        let seconds = Self.seconds(ContinuousClock.now - began)
        firstReadBegan = nil
        firstRead = (seconds, firstReadAlbums)
        try? store?.database.setMeta(DownloadDatabase.libraryFirstReadKey, "\(seconds) \(firstReadAlbums)")
        note("library: first read \(LibraryFollowWords.firstRead(seconds: seconds, albums: firstReadAlbums))")
    }

    private static func firstRead(_ kept: String?) -> (seconds: Double, albums: Int)? {
        guard let parts = kept?.split(separator: " "), parts.count == 2, let seconds = Double(parts[0]),
              let albums = Int(parts[1]) else { return nil }
        return (seconds, albums)
    }

    private static func joined(_ ids: Set<String>) -> String? { ids.isEmpty ? nil : ids.sorted().joined(separator: "\n") }

    private static func split(_ kept: String?) -> Set<String> {
        Set((kept ?? "").split(separator: "\n").map(String.init))
    }

    /// A check every minute while the app is alive (in front, or playing): one is made when 15 minutes have passed
    /// since the last began (`due`'s `timer`).
    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.check(.timer)
            }
        }
    }

    private func say(_ words: String) {
        problem = words
        note("library: \(words)")
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
