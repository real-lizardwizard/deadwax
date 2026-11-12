import DeadwaxAudio
import DeadwaxCore
import Foundation
import Observation
import UIKit

/// Downloads to this phone, for the screens to bind to (notes/ios-specs/phase2-downloads.md): each song's and album's
/// state in Core's words, the two settings, what's used, and the actions - Download, Remove Download, Try again,
/// Remove All - each made in the tap, nothing awaited first. Every rule is Core's (DownloadRules, DownloadPlan,
/// DownloadWords); this keeps the state, the store (DownloadStore), the background session (DownloadSession) and the
/// checks (FLACVerifier) in step.
///
/// **Reading a state** - `state(_:)` for a song, `album(_:)` for an album's songs (or `album(id:)` from its kept
/// answer), `choices(...)` for a menu, `isHere(_:)` for what plays offline. Progress is read from the session while a
/// screen follows it (`followProgress()` in its `.task`): a song with no byte yet shows its wait, never 0%.
///
/// **Per person**: the store is the signed-in person's on this server; another sign-in has its own, and the first's stay
/// for them. A task's end lands in the store it was made for, whoever is signed in by then.
@MainActor
@Observable
final class DownloadModel {
    // MARK: the settings (You > Downloads)

    /// Download over: Wi-Fi only (the default) or Wi-Fi and cellular. A change makes every task out again under the new
    /// request.
    var downloadOver: DownloadOver {
        didSet {
            guard downloadOver != oldValue else { return }
            UserDefaults.standard.set(downloadOver.rawValue, forKey: DownloadOver.storageKey)
            Task { await remakeTasks() }
        }
    }

    /// The storage limit: 5, 10, 20 (the default), 50, 100 GB or none. Nothing here is ever removed for it: what doesn't
    /// fit waits.
    var storageLimit: StorageLimit {
        didSet {
            guard storageLimit != oldValue else { return }
            UserDefaults.standard.set(storageLimit.rawValue, forKey: StorageLimit.storageKey)
            replan()
        }
    }

    /// Debug's "Stream even when downloaded" - the admin's A/B. Never kept: every launch plays the copies.
    var streamEvenWhenDownloaded = false {
        didSet { playable.streamAlways(streamEvenWhenDownloaded) }
    }

    // MARK: what the screens read

    /// Every song asked for or here, by id.
    private(set) var records: [String: DownloadRecord] = [:]
    /// Why each was asked for.
    private(set) var origins: [String: Set<DownloadOrigin>] = [:]
    /// The planner's latest wait for each song not here - the shared reasons (network, sign-in) said at once.
    private(set) var planned: [String: DownloadWait] = [:]
    /// Bytes each task has brought, while a screen follows progress.
    private(set) var received: [String: Int64] = [:]
    /// The albums' kept answers (`GET /navidrome/albums/{id}` as answered), by id.
    private(set) var albums: [String: Album] = [:]
    /// Every album with a song asked for or here: its songs' ids.
    private(set) var songsOfAlbum: [String: [String]] = [:]
    /// The bytes of every copy here.
    private(set) var bytesHere: Int64 = 0
    /// Other accounts' downloads on this phone, from this server (6.3).
    private(set) var otherBytes: Int64 = 0
    /// When iOS last cancelled downloads because the app was force quit (shown for a day: DownloadWords.forceQuit).
    private(set) var forceQuitAt: Date?
    /// The store couldn't be opened: the system's words (Debug), the screens say DownloadWords.storeUnreadable.
    private(set) var storeProblem: String?
    /// A store is open (someone is signed in, or logins are off).
    private(set) var isOpen = false
    /// Plays made while deadwax couldn't be reached, waiting to be sent.
    private(set) var playsWaiting = 0

    // Debug's (6.9)
    /// The last 50 download events, newest last.
    private(set) var log: [String] = []
    /// How long each check took, in seconds, by song id.
    private(set) var checkSeconds: [String: Double] = [:]

    /// The engine's index of the copies here (read on its own queue) - SongFiles'.
    let playable: PlayableCopies

    // MARK: kept

    @ObservationIgnored private let server: ServerModel
    @ObservationIgnored private let reachability: Reachability
    @ObservationIgnored private let files: SongFiles
    @ObservationIgnored private let session: DownloadSession
    @ObservationIgnored private var store: DownloadStore?
    /// Stores opened for a task's end that isn't the signed-in person's (a background relaunch, someone else signed in).
    @ObservationIgnored private var elsewhere: [String: DownloadStore] = [:]
    /// The task the app made for each song this launch, by song id - an older task's end is not this one's.
    @ObservationIgnored private var live: [String: Int] = [:]
    /// When each task was made (monotonic): a failure is a try only when deadwax answered since.
    @ObservationIgnored private var madeAt: [String: Double] = [:]
    @ObservationIgnored private var planQueued = false
    @ObservationIgnored private var planning = false
    @ObservationIgnored private var planAgain = false
    @ObservationIgnored private var followers = 0
    @ObservationIgnored private var albumsAsked: Set<String> = []
    @ObservationIgnored private var verifyQueue: [String] = []
    @ObservationIgnored private var verifying: String?
    @ObservationIgnored private var verifyStop = StopFlag()
    @ObservationIgnored private var sendingPlays = false
    @ObservationIgnored private var launchedFor: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// A download was answered 401 under this session (nil inside: no session): nothing more is fetched under it for a
    /// minute - /me is asked, and its 401 brings the sign-in - or until the client changes.
    @ObservationIgnored private var refusedSession: String??
    @ObservationIgnored private var refusedAt: Double = 0

    init(server: ServerModel, reachability: Reachability, files: SongFiles, session: DownloadSession) {
        self.server = server
        self.reachability = reachability
        self.files = files
        self.session = session
        playable = files.downloads
        downloadOver = DownloadOver(saved: UserDefaults.standard.string(forKey: DownloadOver.storageKey))
        storageLimit = StorageLimit(saved: UserDefaults.standard.string(forKey: StorageLimit.storageKey))
        DownloadStore.retirePhase0()
        session.connect { [weak self] event in self?.handle(event) }
        reachability.whenChanged { [weak self] in self?.reachabilityChanged() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.movedToBackground() }
        })
        watchServer()
        serverChanged()
    }

    // MARK: reading a state

    /// The song's state now.
    func state(_ songID: String) -> SongDownload {
        DownloadRules.state(records[songID], received: received[songID], planned: planned[songID])
    }

    /// An album's state from its songs (spec 2.2) - the album page's control, hero line and footer.
    func album(_ songs: [Song]) -> AlbumDownload {
        AlbumDownload.of(songs.map(facts))
    }

    /// An album's state from what this phone kept of it - for a tile, where the songs aren't in hand. An album with
    /// nothing asked for is `none` at once (a Library of thousands asks this of every tile drawn).
    func album(id albumID: String) -> AlbumDownload {
        guard let ids = songsOfAlbum[albumID] else { return .none }
        if let songs = albums[albumID]?.song, !songs.isEmpty { return album(songs) }
        return AlbumDownload.of(ids.map { facts(id: $0) })
    }

    /// An album's state from some of its songs' records - You > Downloads' rows, which count what was asked for.
    func album(records: [DownloadRecord]) -> AlbumDownload {
        AlbumDownload.of(records.map { facts(id: $0.id) })
    }

    /// How many of `songs` are on this phone, and their bytes - the album page's footer, the control's "Downloaded ·
    /// 412 MB".
    func here(_ songs: [Song]) -> (count: Int, bytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        for song in songs {
            guard let record = records[song.id], record.state == .done else { continue }
            count += 1
            bytes += record.bytes ?? 0
        }
        return (count, bytes)
    }

    /// Anything of the album asked for or here (its songs' records, by id) - nil for none.
    func songIDs(album albumID: String) -> [String]? { songsOfAlbum[albumID] }

    /// A ••• menu's download items for one song.
    func choices(song songID: String) -> [DownloadChoice] {
        DownloadChoice.forSong(state(songID))
    }

    /// An album's or Up Next's download items; `gone` when the album is no longer in the collection.
    func choices(songs: [Song], gone: Bool = false) -> [DownloadChoice] {
        DownloadChoice.forSongs(songs.map { state($0.id) }, gone: gone)
    }

    /// Now Playing's Download Up Next: how many of `songs` it would ask for (two or more), else nil.
    func upNextCount(_ songs: [Song], paged: Bool) -> Int? {
        DownloadChoice.upNext(songs.map { state($0.id) }, paged: paged)
    }

    /// The song plays from this phone.
    func isHere(_ songID: String) -> Bool { records[songID]?.state == .done }

    /// Anything at all is on this phone.
    var anythingHere: Bool { records.values.contains { $0.state == .done } }

    /// The Library's Downloaded list (5.1): every album on this phone - downloaded, partly, or on its way (its tile says
    /// which) - its Recently added the moment its first song arrived, or, for one with nothing here yet, when it was
    /// asked for.
    var downloadedAlbums: [IndexAlbum] {
        var arrived: [String: Int64] = [:]
        var asked: [String: Int64] = [:]
        for record in records.values {
            asked[record.albumID] = min(asked[record.albumID] ?? record.wantedAt, record.wantedAt)
            guard record.state == .done else { continue }
            let at = record.doneAt ?? record.wantedAt
            arrived[record.albumID] = min(arrived[record.albumID] ?? at, at)
        }
        return DownloadedAlbums.index(Array(albums.values), arrived: asked.merging(arrived) { _, here in here })
    }

    /// How many albums Downloaded lists - the Library root's On this phone row's count (5.2).
    var albumCount: Int { songsOfAlbum.keys.reduce(0) { $0 + (albums[$1] != nil ? 1 : 0) } }

    /// The song as its album's kept answer has it (a row's title and artist), or nil.
    func song(_ songID: String) -> Song? {
        guard let record = records[songID] else { return nil }
        return albums[record.albumID]?.song?.first { $0.id == songID }
    }

    /// You > Downloads' Downloading section: every song asked for and not here or failed, in the order they go.
    var downloading: [DownloadRecord] {
        ordered(records.values.filter { $0.state == .wanted || $0.state == .fetching })
    }

    /// Its Didn't download section.
    var failed: [DownloadRecord] {
        ordered(records.values.filter { $0.state == .failed })
    }

    /// Its Downloaded section's songs (grouped by album on the screen).
    var downloaded: [DownloadRecord] {
        ordered(records.values.filter { $0.state == .done })
    }

    /// You's Downloads row footer: how many are fetching, how many to go, the first one's wait, how many failed.
    var summary: (fetching: Int, toGo: Int, firstWait: DownloadWait?, failed: Int) {
        let going = downloading
        var fetching = 0
        var firstWait: DownloadWait?
        for record in going {
            switch state(record.id) {
            case .fetching: fetching += 1
            case .waiting(let wait) where wait != .queued && firstWait == nil: firstWait = wait
            default: break
            }
        }
        return (fetching, going.count, firstWait, failed.count)
    }

    /// Whether the shown state is old enough to say: the force quit is said for a day.
    var forceQuitShown: Bool {
        guard let at = forceQuitAt else { return false }
        return Date().timeIntervalSince(at) < DownloadWords.forceQuitShownSeconds && !downloading.isEmpty
    }

    /// The album's kept loudness answer (7.3: put on the shelf for a queue's albums, marked old).
    func keptLoudness(_ albumID: String) -> AlbumLoudness? {
        guard let kept = try? store?.database.loudness().first(where: { $0.id == albumID }) else { return nil }
        return try? JSONDecoder().decode(AlbumLoudness.self, from: kept.json)
    }

    /// The album's kept answer as it was answered.
    func keptAlbum(_ albumID: String) -> Album? { albums[albumID] }

    /// An album page's fresh answer for an album with songs asked for or here (3.7): kept in place of the old one, as
    /// answered. A song whose file deadwax now gives another size - its audio replaced on the server - is fetched again
    /// (8.4's "When the store changes a file"): the copy here is deleted and the song asked for afresh.
    func albumAnswered(_ album: Album, body: Data) {
        guard let store, songsOfAlbum[album.id] != nil else { return }
        try? store.database.putAlbum(id: album.id, json: body, fetchedAt: ListenTracker.wallMs())
        albums[album.id] = album
        var changed: [String: Int64] = [:]
        for song in album.song ?? [] {
            guard let record = records[song.id], !record.isTranscode, let size = song.size, size > 0,
                  let kept = record.sizeExpected, kept != size else { continue }
            changed[song.id] = size
        }
        guard !changed.isEmpty else {
            reload()
            return
        }
        for id in changed.keys {
            guard let record = records[id], record.state == .done, let file = store.fileURL(record) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
        update(Array(changed.keys)) { record in
            var r = record
            r.sizeExpected = changed[r.id]
            if r.state == .done { r = DownloadRules.apply(.fileMissing, to: r) }
            return r
        }
        note("album \(album.id): \(changed.count) replaced on the server, fetched again")
        replan()
    }

    // MARK: actions (in the tap)

    /// A song's Download (its own origin).
    func download(_ song: Song) {
        want([song], origin: .song)
    }

    /// An album's Download: its songs not here, planned whole.
    func download(album: Album) {
        want(album.song ?? [], origin: .album(album.id), album: album)
    }

    /// Up Next's Download Up Next: each song its own.
    func download(songs: [Song]) {
        want(songs, origin: .song)
    }

    /// A song's Remove Download: its own origin and its album's taken away; deleted when none is left.
    func remove(_ songID: String) {
        guard let record = records[songID] else { return }
        removeOrigins([.song, .album(record.albumID)], from: [songID])
    }

    /// An album's Remove Download: every song of it asked for through the album or alone.
    func remove(album albumID: String) {
        let songs = records.values.filter { $0.albumID == albumID }.map(\.id)
        removeOrigins([.song, .album(albumID)], from: songs)
    }

    /// Up Next's or a selection's Remove Download.
    func remove(songs songIDs: [String]) {
        for id in songIDs { remove(id) }
    }

    /// A failed song's Try again (its tries start afresh), or a done one's Download Again.
    func tryAgain(_ songID: String) {
        update([songID]) { DownloadRules.apply(.retry, to: $0) }
        note("try again: \(songID)")
        replan()
    }

    /// Didn't download's Try All Again.
    func tryAllAgain() {
        update(failed.map(\.id)) { DownloadRules.apply(.retry, to: $0) }
        replan()
    }

    /// Remove All Downloads (6.7): every task cancelled, every copy and kept album deleted - the plays waiting to be
    /// sent kept.
    func removeAll() {
        guard let store else { return }
        let tasks = Set(live.values)
        live = [:]
        madeAt = [:]
        verifyStop.set()
        verifyQueue = []
        Task { _ = await session.cancel(tasks, resume: false) }
        do {
            try store.removeEverything()
            note("removed everything")
        } catch {
            note("remove all failed: \(error)")
        }
        reload()
    }

    /// Other accounts' downloads on this phone removed (6.3).
    func removeOthers() {
        guard let store else { return }
        for other in DownloadStore.others(server: store.server, except: store.person) {
            DownloadStore.removeOther(other.folder)
        }
        otherBytes = 0
    }

    /// Progress followed while the caller's task runs - a screen's `.task { await downloads.followProgress() }`: read
    /// from the session about four times a second, never kept.
    func followProgress() async {
        followers += 1
        defer {
            followers -= 1
            if followers == 0 { received = [:] }
        }
        while !Task.isCancelled {
            await readProgress()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    // MARK: plays kept (7.6)

    /// A play that couldn't be sent, kept with its time to send later. Nothing when no one's store is open.
    func keepPlay(songID: String, timeMs: Int64) {
        guard let store, (try? store.database.keepPlay(songID: songID, timeMs: timeMs)) != nil else { return }
        playsWaiting += 1
        note("play kept: \(songID)")
    }

    /// The plays kept sent, oldest first, one at a time: each forgotten on a 200; a 401 holds them; another 4xx drops
    /// that one; a 5xx or no answer stops until the next time deadwax answers.
    func sendKeptPlays() {
        guard !sendingPlays, reachability.online, server.launch == .ready, server.signInOver == nil,
              let store, let client = server.client else { return }
        sendingPlays = true
        Task {
            defer {
                sendingPlays = false
                playsWaiting = (try? store.database.keptPlays().count) ?? 0
            }
            for play in (try? store.database.keptPlays()) ?? [] {
                guard self.store === store else { return }
                var status: Int?
                do {
                    try await client.scrobble(songID: play.songID, submission: true, time: play.timeMs)
                    status = 200
                } catch let failure as APIFailure {
                    status = failure.answer?.status
                } catch {
                    status = nil
                }
                switch PendingPlays.after(status: status) {
                case .sent, .dropped:
                    try? store.database.forgetPlay(play.id)
                case .held, .stopped:
                    return
                }
            }
        }
    }

    // MARK: the person and the server

    private func watchServer() {
        withObservationTracking {
            _ = server.launch
            _ = server.me
            _ = server.signInOver
            _ = server.client
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.serverChanged()
                    self?.watchServer()
                }
            }
        }
    }

    /// The store for whoever is signed in now; the one before let go (its tasks cancelled into a sign-in wait - they
    /// carry that person's cookie). Then a plan: signed out mid-use is a sign-in wait for every task.
    private func serverChanged() {
        if let refused = refusedSession, refused != server.client?.session { refusedSession = nil }
        let key: (server: String, person: String)? = {
            guard let address = server.address, let me = server.me else { return nil }
            return (address.key, me.loginsOn ? me.user : "local")
        }()
        if let store, key.map({ $0.server != store.server || $0.person != store.person }) ?? true {
            close(store)
        }
        if store == nil, let key {
            open(server: key.server, person: key.person)
        }
        replan()
        sendKeptPlays()
    }

    private func open(server: String, person: String) {
        do {
            let opened = try elsewhere.removeValue(forKey: "\(server)|\(person)") ?? DownloadStore(server: server, person: person)
            store = opened
            storeProblem = nil
            isOpen = true
            note("opened \(person)")
            reload()
            Task { await settle(opened) }
        } catch {
            storeProblem = String(describing: error)
            isOpen = false
            note("couldn't open the store: \(error)")
        }
    }

    private func close(_ closing: DownloadStore) {
        let out = records.values.filter { $0.state == .fetching }
        let tasks = Set(out.compactMap { live[$0.id] })
        for record in out {
            try? closing.database.put(DownloadRules.apply(.signedOut, to: record))
        }
        Task { _ = await session.cancel(tasks, resume: false) }
        verifyStop.set()
        verifyQueue = []
        live = [:]
        madeAt = [:]
        store = nil
        isOpen = false
        records = [:]
        songsOfAlbum = [:]
        origins = [:]
        planned = [:]
        received = [:]
        albums = [:]
        bytesHere = 0
        otherBytes = 0
        playsWaiting = 0
        forceQuitAt = nil
        playable.set([:])
        KeptCovers.shared.set([:])
    }

    /// A store just opened, put in step with the session and the disk: tasks lost (the app was gone) back to wanted,
    /// tasks nobody wants cancelled, copies gone from disk forgotten, unchecked ones checked, failed ones given their
    /// launch's try, albums with no kept answer asked again.
    private func settle(_ opened: DownloadStore) async {
        let outs = await session.tasks().filter { $0.name.server == opened.server && $0.name.person == opened.person }
        guard store === opened else { return }
        var orphans = Set<Int>()
        for out in outs {
            let record = records[out.name.songID]
            if record?.state == .fetching, live[out.name.songID] == nil {
                live[out.name.songID] = out.task
            } else if live[out.name.songID] != out.task {
                orphans.insert(out.task)
            }
        }
        if !orphans.isEmpty { _ = await session.cancel(orphans, resume: false) }
        let first = launchedFor.insert("\(opened.server)|\(opened.person)").inserted
        update(Array(records.keys)) { record in
            var r = record
            if r.state == .fetching, self.live[r.id] == nil { r = DownloadRules.apply(.cancelled(resume: nil), to: r) }
            if r.state == .done, let url = opened.fileURL(r), DownloadStore.length(url) == nil {
                r = DownloadRules.apply(.fileMissing, to: r)
            }
            if first { r = DownloadRules.apply(.launched, to: r) }
            return r
        }
        // a .part is a file between its move and its check: one left now was never checked
        let parts = (try? FileManager.default.contentsOfDirectory(at: opened.music, includingPropertiesForKeys: nil)) ?? []
        for part in parts where part.pathExtension == "part" {
            let id = part.deletingPathExtension().deletingPathExtension().lastPathComponent
            if records[id]?.state != .fetching { try? FileManager.default.removeItem(at: part) }
        }
        for record in records.values where record.state == .done && record.check == .unchecked {
            queueCheck(record.id)
        }
        for albumID in Set(records.values.map(\.albumID)) where albums[albumID] == nil {
            keepAlbum(albumID, client: server.client)
        }
        rereadLoudness()
        otherBytes = DownloadStore.others(server: opened.server, except: opened.person).reduce(0) { $0 + $1.bytes }
        replan()
        sendKeptPlays()
    }

    // MARK: the app's moments

    private func becameActive() {
        Task {
            if let store { await settle(store) }
        }
        sendKeptPlays()
    }

    private func movedToBackground() {
        received = [:]
    }

    private func reachabilityChanged() {
        replan()
        if reachability.online { sendKeptPlays() }
    }

    // MARK: asking

    private func want(_ songs: [Song], origin: DownloadOrigin, album: Album? = nil) {
        guard let store, !songs.isEmpty else { return }
        let now = ListenTracker.wallMs()
        let albumID = album?.id
        var fresh: [Song] = []
        do {
            try store.database.transaction {
                for (index, song) in songs.enumerated() {
                    let id = albumID ?? song.albumId ?? ""
                    let at = now + Int64(index) // the album's order kept among songs asked together
                    if var record = try store.database.song(song.id) {
                        if record.state == .failed { record = DownloadRules.apply(.retry, to: record) }
                        try store.database.put(record)
                    } else {
                        try store.database.put(DownloadRecord(song: song, albumID: id, now: at))
                        fresh.append(song)
                    }
                    try store.database.addOrigin(origin, song: song.id, at: at)
                }
            }
        } catch {
            note("couldn't keep the ask: \(error)")
            return
        }
        note("asked: \(songs.count) (\(origin.raw))")
        reload()
        // a song whose whole copy is in the streaming cache is copied in - an APFS clone - and checked as any download
        for song in fresh {
            guard let cached = files.cache.reusable(song), var record = records[song.id], let part = store.partURL(record)
            else { continue }
            try? FileManager.default.removeItem(at: part)
            guard (try? FileManager.default.copyItem(at: cached, to: part)) != nil else { continue }
            record = arrive(record, part: part, in: store)
            try? store.database.put(record)
            note("from the streaming cache: \(song.id)")
        }
        for id in Set(songs.compactMap { albumID ?? $0.albumId }) where albums[id] == nil {
            keepAlbum(id, client: server.client)
        }
        reload()
        replan()
    }

    private func removeOrigins(_ removed: Set<DownloadOrigin>, from songIDs: [String]) {
        guard let store, !songIDs.isEmpty else { return }
        var deleted: [String] = []
        do {
            deleted = try store.database.removeOrigins(removed, songs: songIDs)
        } catch {
            note("couldn't remove: \(error)")
            return
        }
        let tasks = Set(deleted.compactMap { live.removeValue(forKey: $0) })
        if !tasks.isEmpty { Task { _ = await session.cancel(tasks, resume: false) } }
        for id in deleted {
            verifyQueue.removeAll { $0 == id }
            guard let record = records[id] else { continue }
            if let file = store.fileURL(record) { try? FileManager.default.removeItem(at: file) }
            if let part = store.partURL(record) { try? FileManager.default.removeItem(at: part) }
        }
        // an album with no song left goes, its cover with it
        let left = Set(((try? store.database.songs()) ?? []).map(\.albumID))
        for kept in (try? store.database.albums()) ?? [] where !left.contains(kept.id) {
            if let cover = kept.cover { try? FileManager.default.removeItem(at: store.covers.appendingPathComponent(cover)) }
            try? store.database.deleteAlbum(kept.id)
        }
        note("removed: \(deleted.count)")
        reload()
        replan()
    }

    // MARK: the plan (8.5)

    /// A plan run soon: every ask, finish, failure, setting change, path and reachability change, and coming to the front.
    private func replan() {
        guard !planQueued else { return }
        planQueued = true
        Task {
            planQueued = false
            await plan()
        }
    }

    private func plan() async {
        guard let store else { return }
        guard !planning else {
            planAgain = true
            return
        }
        planning = true
        defer {
            planning = false
            if planAgain {
                planAgain = false
                replan()
            }
        }
        let asked = records.values.filter { $0.state == .wanted || $0.state == .fetching }
        let facts = DownloadPlan.Facts(bytesHere: bytesHere, limit: storageLimit.bytes,
                                       freeSpace: DownloadStore.freeSpace() ?? Int64.max / 4,
                                       reach: reachability.reach, path: reachability.path,
                                       signedIn: server.launch == .ready && server.signInOver == nil && server.client != nil
                                           && !refused(server.client?.session),
                                       over: downloadOver)
        let decisions = DownloadPlan.plan(asked.map { DownloadPlan.Asked($0, origins: origins[$0.id] ?? [.song],
                                                                          received: received[$0.id] ?? 0) }, facts)
        planned = decisions.mapValues(\.wait)
        // tasks the plan lets go: cancelled, their resume data kept - but not a sign-out's (it carries the old cookie)
        let letGo = asked.filter { $0.state == .fetching && decisions[$0.id]?.task == false }
        if !letGo.isEmpty {
            let signOut = DownloadPlan.sharedWait(facts) == .signIn
            let ids = Set(letGo.compactMap { live[$0.id] })
            let resumes = await session.cancel(ids, resume: !signOut)
            guard self.store === store else { return }
            update(letGo.map(\.id)) { record in
                let task = self.live.removeValue(forKey: record.id)
                return signOut ? DownloadRules.apply(.signedOut, to: record)
                    : DownloadRules.apply(.cancelled(resume: task.flatMap { resumes[$0] }), to: record)
            }
        }
        // the waits kept, so a relaunch shows them before its first plan
        let waits = asked.filter { record in
            guard record.state == .wanted, let decision = decisions[record.id], !decision.task else { return false }
            return record.wait != decision.wait
        }
        update(waits.map(\.id)) { record in
            var r = record
            r.wait = decisions[r.id]?.wait
            return r
        }
        // tasks the plan lets go of the leash: made now, the oldest ask's album from its top
        let toMake = ordered(records.values.filter { $0.state == .wanted && decisions[$0.id]?.task == true })
        var made: [String: String] = [:]
        for (index, record) in toMake.enumerated() {
            if let name = make(record, in: store, priority: max(0.1, 0.9 - Float(index) * 0.01)) { made[record.id] = name }
        }
        update(Array(made.keys)) { record in
            var r = DownloadRules.apply(.taskMade(made[record.id] ?? ""), to: record)
            r.resume = nil // spent on the task made from it
            return r
        }
    }

    /// The song's task made: its request with the setting's network flags, from its resume data when it has some.
    /// Its name, or nil when no task could be made.
    private func make(_ record: DownloadRecord, in store: DownloadStore, priority: Float) -> String? {
        guard let client = server.client else { return nil }
        var request = URLRequest(client.streamRequest(songID: record.id, format: record.format))
        let access = downloadOver.access
        request.allowsCellularAccess = access.cellular
        request.allowsExpensiveNetworkAccess = access.expensive
        request.allowsConstrainedNetworkAccess = access.constrained
        let name = DownloadTaskName(server: store.server, person: store.person, songID: record.id, suffix: record.suffix)
        guard let task = session.make(request, name: name, resume: record.resume, priority: priority) else { return nil }
        live[record.id] = task
        madeAt[record.id] = Monotonic.seconds()
        note("task \(task): \(record.id)\(record.resume == nil ? "" : " (resumed)")")
        return name.description
    }

    /// Download over changed: every task out cancelled and made again under the new request. Their resume data is let
    /// go - a task made from it would carry the old request's network flags - so a song part-way starts again.
    private func remakeTasks() async {
        guard let store else { return }
        let out = records.values.filter { $0.state == .fetching }
        let ids = Set(out.compactMap { live[$0.id] })
        _ = await session.cancel(ids, resume: false)
        guard self.store === store else { return }
        update(out.map(\.id)) { record in
            self.live[record.id] = nil
            var r = DownloadRules.apply(.cancelled(resume: nil), to: record)
            r.resume = nil
            return r
        }
        note("download over: \(downloadOver.rawValue) - \(out.count) made again")
        replan()
    }

    // MARK: what the session says (8.3)

    private func handle(_ event: DownloadSession.Event) {
        switch event {
        case .finished(let task, let name, let status, let part, let unsaved, let full):
            guard let found = storeFor(name) else {
                if let part { try? FileManager.default.removeItem(at: part) }
                return
            }
            let (target, current) = found
            if current, let mine = live[name.songID], mine != task {
                if let part { try? FileManager.default.removeItem(at: part) }
                return
            }
            live[name.songID] = nil
            guard var record = try? target.database.song(name.songID), record.state != .done else {
                if let part { try? FileManager.default.removeItem(at: part) }
                return
            }
            if !DownloadRules.isTheSong(status: status) {
                if status == 401 {
                    record = DownloadRules.apply(.signedOut, to: record)
                    if current { signedOutHeard() }
                } else {
                    record = DownloadRules.apply(.refused(status: status, detail: nil), to: record)
                }
                note("\(name.songID): deadwax answered \(status)")
            } else if let part, unsaved == nil {
                record = arrive(record, part: part, in: target)
            } else {
                record = DownloadRules.apply(.unsaved(outOfSpace: full), to: record)
                note("\(name.songID): not saved - \(unsaved ?? "no file")")
            }
            try? target.database.put(record)
        case .failed(let task, let name, let error, let resume, let forceQuit, let ours):
            guard !ours, let found = storeFor(name) else { return }
            let (target, current) = found
            if current, let mine = live[name.songID], mine != task { return }
            live[name.songID] = nil
            guard var record = try? target.database.song(name.songID), record.state != .done else { return }
            if forceQuit {
                try? target.database.setMeta("force_quit_at", String(ListenTracker.wallMs()))
                record = DownloadRules.apply(.cancelled(resume: resume), to: record)
                note("\(name.songID): force quit\(resume == nil ? "" : ", resumable")")
            } else if error.code == NSURLErrorCancelled {
                record = DownloadRules.apply(.cancelled(resume: resume), to: record)
            } else {
                let reason = error.localizedDescription
                let failure: DownloadFailure = error.code == NSURLErrorTimedOut ? .timeout(reason: reason) : .offline(reason: reason)
                let counts = current && madeAt[name.songID].map { reachability.answeredSince($0) && reachability.online } ?? false
                record = DownloadRules.apply(.noAnswer(failure, resume: resume, counts: counts), to: record)
                if !counts { reachability.heard(answered: false) }
                note("\(name.songID): \(reason)\(counts ? " (a try)" : "")")
            }
            try? target.database.put(record)
        }
        reload()
        replan()
    }

    /// A download answered 401: nothing more is fetched under this session, and /me is asked - its 401 brings the sign-in
    /// over the app (the downloads' session never goes through DeadwaxClient, which would have).
    private func signedOutHeard() {
        let session = server.client?.session
        guard !refused(session) else { return }
        refusedSession = .some(session)
        refusedAt = Monotonic.seconds()
        Task { await server.refreshMe() }
        // asked again after the minute, by a plan: a 401 then asks /me again, at most once a minute
        Task {
            try? await Task.sleep(nanoseconds: UInt64(ServerModel.loginsAskAgainSeconds * 1_000_000_000))
            replan()
        }
    }

    private func refused(_ session: String?) -> Bool {
        refusedSession == .some(session) && Monotonic.seconds() - refusedAt < ServerModel.loginsAskAgainSeconds
    }

    /// The store a task's end belongs in, and whether it is the signed-in person's.
    private func storeFor(_ name: DownloadTaskName) -> (DownloadStore, Bool)? {
        if let store, store.server == name.server, store.person == name.person { return (store, true) }
        let key = "\(name.server)|\(name.person)"
        if let other = elsewhere[key] { return (other, false) }
        guard let opened = try? DownloadStore(server: name.server, person: name.person) else { return nil }
        elsewhere[key] = opened
        return (opened, false)
    }

    /// A finished file checked for length (8.4 step 1): the song's own name and here - playing from now on - or deleted
    /// as a try. A FLAC with an MD5 is checked for sound after.
    private func arrive(_ record: DownloadRecord, part: URL, in target: DownloadStore) -> DownloadRecord {
        let manager = FileManager.default
        let length = DownloadStore.length(part) ?? 0
        guard DownloadRules.lengthMatches(length, record: record) else {
            try? manager.removeItem(at: part)
            note("\(record.id): \(length) bytes, not \(record.sizeExpected ?? 0)")
            return DownloadRules.apply(.wrongLength, to: record)
        }
        guard let file = target.fileURL(record) else { return DownloadRules.apply(.unsaved(outOfSpace: false), to: record) }
        do {
            try? manager.removeItem(at: file)
            try manager.moveItem(at: part, to: file)
        } catch {
            try? manager.removeItem(at: part)
            return DownloadRules.apply(.unsaved(outOfSpace: false), to: record)
        }
        DownloadStore.protect(file)
        let isFLAC = record.suffix.lowercased() == "flac"
        let info = isFLAC ? (try? FileHandle(forReadingFrom: file).read(upToCount: 64 * 1024)).flatMap(FLACStreamInfo.parse) : nil
        let check: CopyCheck = isFLAC ? DownloadRules.checkAfterLength(info) : .bySize
        let arrived = DownloadRules.apply(.arrived(bytes: length, check: check, flac: info.map(FLACFacts.init),
                                                   at: ListenTracker.wallMs()), to: record)
        note("\(record.id): here, \(length) bytes, \(check.rawValue)")
        if check == .unchecked, target === store { queueCheck(record.id) }
        return arrived
    }

    // MARK: the sound check (8.4 step 2)

    private func queueCheck(_ songID: String) {
        guard !verifyQueue.contains(songID), verifying != songID else { return }
        verifyQueue.append(songID)
        checkNext()
    }

    private func checkNext() {
        guard verifying == nil, let store, !verifyQueue.isEmpty else { return }
        let id = verifyQueue.removeFirst()
        guard let record = records[id], record.state == .done, record.check == .unchecked, let url = store.fileURL(record) else {
            checkNext()
            return
        }
        // in the background, a check is started only with time left to finish one (it stops cleanly if not)
        let application = UIApplication.shared
        if application.applicationState == .background, application.backgroundTimeRemaining < 10 {
            verifyQueue.insert(id, at: 0)
            return
        }
        verifying = id
        let stop = StopFlag()
        verifyStop = stop
        let background = application.beginBackgroundTask(withName: "deadwax.check") {
            stop.set()
        }
        Task.detached(priority: .utility) {
            let head = try? FileHandle(forReadingFrom: url).read(upToCount: 64 * 1024)
            let (outcome, seconds) = FLACVerifier.timed(url, info: head.flatMap(FLACStreamInfo.parse), stop: { stop.isSet })
            await MainActor.run {
                self.checked(id, in: store, url: url, outcome: outcome, seconds: seconds)
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            }
        }
    }

    private func checked(_ id: String, in checkedStore: DownloadStore, url: URL, outcome: FLACVerifier.Outcome, seconds: Double) {
        verifying = nil
        defer { checkNext() }
        guard store === checkedStore, var record = records[id], record.state == .done else { return }
        checkSeconds[id] = seconds
        switch outcome {
        case .matched:
            record = DownloadRules.apply(.checked(.matched), to: record)
        case .bySize:
            record = DownloadRules.apply(.checked(.bySize), to: record)
        case .mismatch:
            try? FileManager.default.removeItem(at: url)
            record = DownloadRules.apply(.soundMismatch, to: record)
        case .unreadable(let words):
            try? FileManager.default.removeItem(at: url)
            record = DownloadRules.apply(.unreadable, to: record)
            note("\(id): \(words)")
        case .stopped:
            note("\(id): check stopped, again later")
            return
        }
        note("\(id): checked \(String(format: "%.1f", seconds)) s - \(outcome)")
        try? checkedStore.database.put(record)
        reload()
        if record.state != .done { replan() }
    }

    // MARK: albums, covers and loudness kept (8.2)

    /// The album's answer kept as it was answered, then its cover (1024) and its loudness - warmed first, whatever
    /// Normalization is set to, so a person may turn it on later.
    private func keepAlbum(_ albumID: String, client: DeadwaxClient?) {
        guard let client, let store, !albumID.isEmpty, albumsAsked.insert(albumID).inserted else { return }
        Task {
            defer { albumsAsked.remove(albumID) }
            do {
                let response = try await client.answer(client.request(Routes.album, path: ["album_id": albumID]))
                let album = try client.decode(Album.self, response)
                guard self.store === store else { return }
                try store.database.putAlbum(id: albumID, json: response.body, fetchedAt: ListenTracker.wallMs())
                albums[albumID] = album
                if let cover = album.coverArt, !cover.isEmpty {
                    let data = try await client.cover(coverID: cover, size: DownloadStore.coverSize)
                    let name = DownloadStore.coverName(cover, data: data)
                    let url = store.covers.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                    DownloadStore.protect(url)
                    try store.database.setCover(album: albumID, file: name)
                    KeptCovers.shared.keep(cover, url)
                }
                await keepLoudness(albumID, client: client, store: store)
                note("album kept: \(album.name ?? albumID)")
            } catch {
                if !APIFailure.isCancellation(error) { note("album \(albumID) not kept: \(error)") }
            }
        }
    }

    private func keepLoudness(_ albumID: String, client: DeadwaxClient, store: DownloadStore) async {
        _ = try? await client.warmLevels(albumID: albumID)
        guard let response = try? await client.answer(client.request(Routes.loudness, path: ["album_id": albumID])),
              let loudness = try? client.decode(AlbumLoudness.self, response), self.store === store else { return }
        try? store.database.putLoudness(album: albumID, json: response.body, algorithm: loudness.algorithm,
                                        fetchedAt: ListenTracker.wallMs())
    }

    /// At each launch, an album's loudness not yet measured is read again.
    private func rereadLoudness() {
        guard let store, let client = server.client, reachability.online else { return }
        let kept = (try? store.database.loudness()) ?? []
        for answer in kept {
            guard let loudness = try? JSONDecoder().decode(AlbumLoudness.self, from: answer.json),
                  loudness.state != .measured || !loudness.whole else { continue }
            Task { await keepLoudness(answer.id, client: client, store: store) }
        }
    }

    // MARK: progress

    private func readProgress() async {
        guard store != nil, records.values.contains(where: { $0.state == .fetching }) else {
            if !received.isEmpty { received = [:] }
            return
        }
        var now: [String: Int64] = [:]
        for out in await session.tasks() where live[out.name.songID] == out.task {
            guard let record = records[out.name.songID] else { continue }
            // a resumed task's answer brings only the rest: what came before it counted in
            let expected = record.expectedBytes
            let before = out.expected > 0 && expected > out.expected ? expected - out.expected : 0
            if out.received > 0 { now[out.name.songID] = before + out.received }
        }
        if now != received { received = now }
    }

    // MARK: the store's rows, read back

    private func update(_ ids: [String], _ change: (DownloadRecord) -> DownloadRecord) {
        guard let store, !ids.isEmpty else { return }
        try? store.database.transaction {
            for id in ids {
                guard let record = try store.database.song(id) else { continue }
                let changed = change(record)
                if changed != record { try store.database.put(changed) }
            }
        }
        reload()
    }

    private func reload() {
        guard let store else { return }
        let songs = (try? store.database.songs()) ?? []
        var byID: [String: DownloadRecord] = [:]
        var urls: [String: URL] = [:]
        var bytes: Int64 = 0
        for record in songs {
            byID[record.id] = record
            if record.state == .done, let url = store.fileURL(record) {
                urls[record.id] = url
                bytes += record.bytes ?? 0
            }
        }
        if byID != records { records = byID }
        var byAlbum: [String: [String]] = [:]
        for record in songs { byAlbum[record.albumID, default: []].append(record.id) }
        if byAlbum != songsOfAlbum { songsOfAlbum = byAlbum }
        let kept = (try? store.database.origins()) ?? [:]
        if kept != origins { origins = kept }
        if bytes != bytesHere { bytesHere = bytes }
        playable.set(urls)
        var keptAlbums: [String: Album] = [:]
        var covers: [String: URL] = [:]
        for answer in (try? store.database.albums()) ?? [] {
            guard let album = albums[answer.id] ?? (try? JSONDecoder().decode(Album.self, from: answer.json)) else { continue }
            keptAlbums[answer.id] = album
            if let cover = album.coverArt, let file = answer.cover { covers[cover] = store.covers.appendingPathComponent(file) }
        }
        if keptAlbums != albums { albums = keptAlbums }
        KeptCovers.shared.set(covers)
        let quit = (try? store.database.meta("force_quit_at")).flatMap { $0.flatMap(Double.init) }
        let at = quit.map { Date(timeIntervalSince1970: $0 / 1000) }
        if at != forceQuitAt { forceQuitAt = at }
        let plays = (try? store.database.keptPlays().count) ?? 0
        if plays != playsWaiting { playsWaiting = plays }
    }

    // MARK: helpers

    private func facts(_ song: Song) -> AlbumSongFacts { facts(id: song.id) }

    private func facts(id: String) -> AlbumSongFacts {
        AlbumSongFacts(state: state(id), expected: records[id]?.expectedBytes ?? 0, received: received[id] ?? 0)
    }

    /// In the order they go: the order asked, then disc and track.
    private func ordered(_ songs: [DownloadRecord]) -> [DownloadRecord] {
        songs.sorted { a, b in
            if a.wantedAt != b.wantedAt { return a.wantedAt < b.wantedAt }
            if (a.disc ?? 0) != (b.disc ?? 0) { return (a.disc ?? 0) < (b.disc ?? 0) }
            if (a.track ?? 0) != (b.track ?? 0) { return (a.track ?? 0) < (b.track ?? 0) }
            return a.id < b.id
        }
    }

    private func note(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("\(stamp) \(line)")
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }

    /// The tasks out, for Debug.
    func debugTasks() async -> [DownloadSession.Out] { await session.tasks() }
}

/// The engine's index of the copies on this phone, read on its own queue: a song's downloaded copy by id - nil with
/// Debug's "Stream even when downloaded".
final class PlayableCopies: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String: URL] = [:]
    private var streaming = false

    func url(for songID: String) -> URL? {
        lock.withLock { streaming ? nil : urls[songID] }
    }

    func set(_ new: [String: URL]) {
        lock.withLock { urls = new }
    }

    func streamAlways(_ on: Bool) {
        lock.withLock { streaming = on }
    }
}

/// The covers kept with downloads, by cover id - CoverCache looks here before it asks deadwax (8.8).
final class KeptCovers: @unchecked Sendable {
    static let shared = KeptCovers()
    private let lock = NSLock()
    private var urls: [String: URL] = [:]

    func url(for coverID: String) -> URL? { lock.withLock { urls[coverID] } }
    func set(_ new: [String: URL]) { lock.withLock { urls = new } }
    func keep(_ coverID: String, _ url: URL) { lock.withLock { urls[coverID] = url } }
}

/// Told to stop, from any thread.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isSet: Bool { lock.withLock { stopped } }
    func set() { lock.withLock { stopped = true } }
}
