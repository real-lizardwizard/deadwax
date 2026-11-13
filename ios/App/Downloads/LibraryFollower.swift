import DeadwaxCore
import Foundation
import Observation

/// Your library followed from deadwax onto this phone (notes/ios-specs/phase3-autodownload.md 2.2-2.4; slice 1): the
/// checks and their minute timer, each album's songs read four at a time in the order they would come onto the phone,
/// and what Debug shows. Every rule is Core's (LibraryFollow, LibraryFill); this asks deadwax, keeps the answers in
/// the person's download store (its `library` table) and says what happened in the downloads log.
///
/// **Slice 1 is read-only**: nothing downloads and nothing is deleted - no origin is written, the planner is
/// untouched. It runs only with Debug's own "Follow your library" on (off by default, kept per phone); turning it off
/// forgets what it followed, so turning it on again reads every album from the start (check L0a).
///
/// One thing at a time: a check, then the reads; a check asked for while reads run is made after the batch in hand,
/// then the reads go on. Nothing is asked while deadwax can't be reached or the person must sign in - a check that
/// can't answer changes nothing anyway.
@MainActor
@Observable
final class LibraryFollower {
    /// Debug's switch (3.5): UserDefaults, per phone.
    static let followKey = "debugFollowLibrary"

    /// Follow your library (Debug's, slice 1). Off: the library followed is forgotten.
    var following: Bool {
        didSet {
            guard following != oldValue else { return }
            UserDefaults.standard.set(following, forKey: Self.followKey)
            if following {
                note("library: following")
                restore()
                startTimer()
                check(.byHand)
            } else {
                note("library: not following - forgotten")
                forget()
            }
        }
    }

    // MARK: what Debug reads

    /// The library in the order its albums would come onto the phone (LibraryFollow.ordered), songs as read.
    private(set) var ordered: [FollowedAlbum] = []
    /// What is followed: yours, or the collection.
    private(set) var scope: AlbumScope?
    /// Why the last list's absences weren't believed.
    private(set) var held: LibraryFollow.Held?
    /// The last check, answered or not.
    private(set) var lastCheck: LibraryCheckRecord?
    /// A check is out.
    private(set) var checking = false
    /// Albums' songs being read now.
    private(set) var readingNow = 0
    /// The first read of every album's songs (R13): how long, and how many albums - once it has ended.
    private(set) var firstRead: (seconds: Double, albums: Int)?
    /// The store couldn't be read or written: its words.
    private(set) var problem: String?

    // MARK: kept

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    /// The downloads log (DownloadModel.note).
    @ObservationIgnored var note: (String) -> Void = { _ in }
    @ObservationIgnored private var store: DownloadStore?
    @ObservationIgnored private var etag: String?
    /// When the last check began (ms) - `due`'s.
    @ObservationIgnored private var lastBegan: Int64?
    /// A check asked for and not yet made: the first reason asked.
    @ObservationIgnored private var pending: LibraryCheck?
    @ObservationIgnored private var running = false
    /// Bumped as the store closes, is forgotten, or the switch goes off: a run of an older one stops.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The first read under way: when it began (the run's clock) and how many albums it reads.
    @ObservationIgnored private var firstReadBegan: ContinuousClock.Instant?
    @ObservationIgnored private var firstReadAlbums = 0
    @ObservationIgnored private var wasOnline = true

    init(server: ServerModel, reachability: Reachability) {
        self.server = server
        self.reachability = reachability
        following = UserDefaults.standard.bool(forKey: Self.followKey)
        wasOnline = reachability.online
    }

    // MARK: the moments (2.2)

    /// A store opened: launch, a sign-in, another person.
    func opened(_ opened: DownloadStore) {
        store = opened
        generation += 1
        guard following else { return }
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
        guard following, let store else { return }
        if removed {
            do {
                if try store.database.setRemovedHere(album: album, at: at),
                   let index = ordered.firstIndex(where: { $0.id == album }) {
                    ordered[index].removedHere = at
                }
            } catch {
                say("couldn't mark a removal: \(error)")
            }
        }
        check(.changedHere)
    }

    /// A check for `reason`, when it is due (LibraryFollow.due): made now, or once the one under way ends.
    func check(_ reason: LibraryCheck) {
        guard following, store != nil else { return }
        guard LibraryFollow.due(reason, lastBegan: lastBegan, now: ListenTracker.wallMs()) else { return }
        if pending == nil { pending = reason }
        if !running { Task { await run() } }
    }

    /// The fill at `limit` with the hand downloads as DownloadModel counts them (2.6) - Debug's "Would fit".
    func wouldFit(limit: StorageLimit, hand: DownloadModel.HandBytes, freeSpace: Int64) -> LibraryFill.Plan {
        LibraryFill.plan(LibraryFill.albums(ordered, hand: hand.songs),
                         LibraryFill.Facts(handBytes: hand.bytes, handToCome: hand.toCome, limit: limit.bytes,
                                           freeSpace: freeSpace))
    }

    // MARK: the run

    private var canAsk: Bool {
        reachability.online && server.launch == .ready && server.signInOver == nil && server.client != nil
    }

    /// Checks asked for, then the reads, until nothing is left that can be done now.
    private func run() async {
        // two asked for before either began: the second finds the first running, and its check is the first's pending
        guard !running else { return }
        guard following, store != nil else {
            pending = nil
            return
        }
        running = true
        let mine = generation
        var failed = Set<String>()
        defer {
            running = false
            // a check asked for while an older run was stopping: made by a run of its own
            if pending != nil, following, store != nil { Task { await run() } }
        }
        while mine == generation, following {
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
            // every one of a batch refused: deadwax or the network is the matter - the next check reads on
            if refused == batch.count { return }
        }
    }

    /// One check: the list asked for with the last one's ETag, and what Core makes of it kept (2.3).
    private func checkNow(_ reason: LibraryCheck, generation mine: Int) async {
        guard let store, canAsk, let client = server.client else { return }
        let scope = AlbumScope.albums(for: server.me)
        if scope != self.scope {
            // another scope's list says nothing of this one's absences: followed again from nothing
            do {
                try store.database.forgetLibrary()
                try store.database.setMeta(DownloadDatabase.libraryScopeKey, scope.rawValue)
            } catch {
                say("couldn't start the library afresh: \(error)")
                return
            }
            if self.scope != nil { note("library: now \(scope.rawValue) - followed afresh") }
            clearMemory()
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
            let out = LibraryFollow.sync(ordered, answer: answer, held: held, at: began)
            do {
                try store.database.transaction {
                    try store.database.putLibrary(out.albums, replacing: ordered)
                    try store.database.setMeta(DownloadDatabase.libraryETagKey, nextETag)
                    try store.database.setMeta(DownloadDatabase.libraryHeldKey, out.held?.raw)
                    try store.database.setMeta(DownloadDatabase.libraryCheckedKey, String(began))
                }
            } catch {
                say("couldn't keep the library: \(error)")
                return
            }
            etag = nextETag
            held = out.held
            ordered = LibraryFollow.ordered(out.albums, scope: scope, now: began)
            problem = nil
            let record = LibraryCheckRecord(reason: reason, result: answer == .unchanged ? .unchanged : .listed(albums: listed),
                                            began: began, seconds: Self.seconds(clock.now - start))
            lastCheck = record
            note(LibraryFollowWords.logLine(record, out))
            if wasEmpty, !out.added.isEmpty {
                firstReadBegan = clock.now
                firstReadAlbums = out.added.count
            }
        } catch {
            guard mine == generation, !APIFailure.isCancellation(error) else { return }
            let record = LibraryCheckRecord(reason: reason, result: .failed(String(describing: error)), began: began,
                                            seconds: Self.seconds(clock.now - start))
            lastCheck = record
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

    // MARK: kept and forgotten

    /// The library as the store keeps it, into memory - once per store opened with the switch on.
    private func restore() {
        guard let store else { return }
        do {
            let kept = try store.database.library()
            let keptScope = try store.database.meta(DownloadDatabase.libraryScopeKey).flatMap(AlbumScope.init(rawValue:))
            scope = keptScope
            etag = try store.database.meta(DownloadDatabase.libraryETagKey)
            held = LibraryFollow.Held(raw: try store.database.meta(DownloadDatabase.libraryHeldKey))
            firstRead = Self.firstRead(try store.database.meta(DownloadDatabase.libraryFirstReadKey))
            ordered = LibraryFollow.ordered(kept, scope: keptScope ?? .store, now: ListenTracker.wallMs())
            problem = nil
        } catch {
            say("couldn't read the library: \(error)")
        }
    }

    /// The switch off: the store's library and its facts forgotten, nothing more asked.
    private func forget() {
        generation += 1
        timer?.cancel()
        timer = nil
        do {
            try store?.database.forgetLibrary()
        } catch {
            say("couldn't forget the library: \(error)")
        }
        clearMemory()
    }

    private func clearMemory() {
        ordered = []
        scope = nil
        held = nil
        etag = nil
        lastCheck = nil
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
