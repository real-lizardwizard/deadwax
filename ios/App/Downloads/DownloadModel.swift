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
            // resume data carries the request it was made from, network flags and all: a song waiting with some would
            // resume under the old setting (mobile data used under Wi-Fi only) - so it starts again, at once, before any
            // plan can make a task from it
            dropResumeData()
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
    /// (Phase 3) Your library's fill at the last plan - "N of M albums fit" - nil while it is off.
    private(set) var libraryFill: LibraryFill.Plan?
    /// Downloading's one row for your library: its albums still to come - nil when none is.
    private(set) var libraryProgress: LibraryDownloads.Progress?
    /// What its songs wait for, while none of them is being fetched (the row says it in place of its progress).
    private(set) var libraryWait: DownloadWait?
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
    /// (app 0.8) Songs begun that deadwax hasn't taken into the person's play history yet.
    private(set) var startsWaiting = 0

    // Debug's (6.9)
    /// The last 50 download events, newest last.
    private(set) var log: [String] = []
    /// How long each check took, in seconds, by song id.
    private(set) var checkSeconds: [String: Double] = [:]

    /// The engine's index of the copies here (read on its own queue) - SongFiles'.
    let playable: PlayableCopies
    /// (Phase 3, slice 1) Your library followed onto this phone, read-only - Debug's "Follow your library"
    /// (phase3-autodownload.md 6.1). Opened and closed with the store.
    let follower: LibraryFollower

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
    /// The Download over each task of this launch was made under: a task's resume data is kept only while it is still
    /// the setting (its request's network flags are in it). A task from before this launch was made under today's.
    @ObservationIgnored private var madeUnder: [String: DownloadOver] = [:]
    /// The session the open store's resume data was made under (nil inside: logins off) - resume data carries the
    /// request's `Cookie:`, so another session's is dropped: it would be refused, and it is a credential kept on disk.
    @ObservationIgnored private var resumeSession: String??
    /// Songs asked for this launch whose whole copy was in the streaming cache: copied from there when the plan lets
    /// them go, rather than fetched.
    @ObservationIgnored private var cachedCopies: [String: URL] = [:]
    /// The kept covers' lengths, by file - counted in what's used (6.3), read from disk once each.
    @ObservationIgnored private var coverLengths: [String: Int64] = [:]
    @ObservationIgnored private var planQueued = false
    @ObservationIgnored private var planning = false
    @ObservationIgnored private var planAgain = false
    @ObservationIgnored private var followers = 0
    @ObservationIgnored private var albumsAsked: Set<String> = []
    /// Songs whose lyrics are queued or being asked for (4.7 of notes/app-lyrics.md): each asked once at a time.
    @ObservationIgnored private var lyricsAsked: Set<String> = []
    @ObservationIgnored private var lyricsQueue: [String] = []
    @ObservationIgnored private var askingLyrics = false
    @ObservationIgnored private var verifyQueue: [String] = []
    @ObservationIgnored private var verifying: String?
    @ObservationIgnored private var verifyStop = StopFlag()
    /// (app 0.8) The kept starts and plays sent: Core's KeptSender holds the loop's rules - whose, in which order,
    /// what is forgotten after which answer, the wait after a failure, the starts held with no store.
    @ObservationIgnored private var sender: KeptSender!
    /// The sender's next try after a send of starts stopped (PlayHistory.retryAfter: 30 s doubling to 10 min).
    @ObservationIgnored private var startsRetry: DispatchWorkItem?
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
        follower = LibraryFollower(server: server, reachability: reachability)
        downloadOver = DownloadOver(saved: UserDefaults.standard.string(forKey: DownloadOver.storageKey))
        storageLimit = StorageLimit(saved: UserDefaults.standard.string(forKey: StorageLimit.storageKey))
        DownloadStore.retirePhase0()
        session.connect { [weak self] event in self?.handle(event) }
        reachability.whenChanged { [weak self] in self?.reachabilityChanged() }
        sender = KeptSender(world: KeptSendWorld(
            openStore: { [weak self] in self?.keptStore() },
            line: { [weak self] in self?.sendLine() },
            retry: { [weak self] ms in self?.retryStarts(after: ms) },
            note: { [weak self] line in self?.note(line) },
            changed: { [weak self] in self?.recountWaiting() }))
        follower.note = { [weak self] line in self?.note(line) }
        follower.changed = { [weak self] in self?.replan() }
        follower.switchedOff = { [weak self] in self?.libraryOff() }
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

    /// A ••• menu's download items for one song - no Remove Download of a song your library keeps (it would come
    /// back at once: its album's Remove Download keeps the album off).
    func choices(song songID: String) -> [DownloadChoice] {
        DownloadChoice.forSong(state(songID), keptByLibrary: keptByLibrary(songID))
    }

    /// An album's download items (its Remove Download takes your library's too); `gone` when the album is no longer in
    /// the collection. `alone`: Up Next's or a selection's songs, each asked for alone - Remove Download only for a song
    /// your library doesn't keep.
    func choices(songs: [Song], gone: Bool = false, alone: Bool = false) -> [DownloadChoice] {
        let states = songs.map { state($0.id) }
        guard alone else { return DownloadChoice.forSongs(states, gone: gone) }
        return DownloadChoice.forSongs(states, gone: gone, keptByLibrary: songs.map { keptByLibrary($0.id) })
    }

    /// The song carries your library's origin.
    func keptByLibrary(_ songID: String) -> Bool { origins[songID]?.contains(.library) == true }

    /// What Download your library keeps - yours, or the collection - as its words name it.
    var libraryScope: AlbumScope { follower.scope ?? AlbumScope.albums(for: server.me) }

    /// What the album's page says of it and your library (3.4): with it, waiting for room, or kept off.
    func libraryMark(album albumID: String) -> LibraryDownloads.AlbumMark {
        guard follower.on else { return .none }
        let entry = follower.ordered.first { $0.id == albumID }
        let songs = LibraryDownloads.songs(records.values.filter { $0.albumID == albumID }, origins: origins,
                                           library: entry.map { [$0] } ?? [])
        return LibraryDownloads.mark(albumID, following: true, library: entry, fill: libraryFill, songs: songs)
    }

    /// Remove from my library lets the album's download go too: your library has some of it here, and no song of it
    /// was downloaded by hand (3.4, open question 9).
    func goesWithLibrary(album albumID: String) -> Bool {
        guard libraryMark(album: albumID) == .withLibrary else { return false }
        let songs = LibraryDownloads.songs(records.values.filter { $0.albumID == albumID }, origins: origins, library: [])
        return !songs.contains { $0.byHand }
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
        // an album your library alone wants only once something of it came (3.3)
        let listed = listedAlbums
        for record in records.values where listed.contains(record.albumID) {
            asked[record.albumID] = min(asked[record.albumID] ?? record.wantedAt, record.wantedAt)
            guard record.state == .done else { continue }
            let at = record.doneAt ?? record.wantedAt
            arrived[record.albumID] = min(arrived[record.albumID] ?? at, at)
        }
        return DownloadedAlbums.index(Array(albums.values), arrived: asked.merging(arrived) { _, here in here })
    }

    /// How many albums Downloaded lists - the Library root's On this phone row's count (5.2).
    var albumCount: Int {
        let listed = listedAlbums
        return songsOfAlbum.keys.reduce(0) { $0 + (albums[$1] != nil && listed.contains($1) ? 1 : 0) }
    }

    /// The albums Downloaded lists (LibraryDownloads.listed): never one your library alone wants that only waits.
    private var listedAlbums: Set<String> {
        LibraryDownloads.listed(LibraryDownloads.songs(Array(records.values), origins: origins, library: []))
    }

    /// The song as its album's kept answer has it (a row's title and artist), or nil.
    func song(_ songID: String) -> Song? {
        guard let record = records[songID] else { return nil }
        return albums[record.albumID]?.song?.first { $0.id == songID }
    }

    /// You > Downloads' Downloading section: every song asked for and not here or failed, in the order they go - but
    /// not your library's own (its one row is `libraryProgress`'s, 3.3).
    var downloading: [DownloadRecord] {
        ordered(records.values.filter { record in
            (record.state == .wanted || record.state == .fetching)
                && !DownloadOrigin.onlyLibrary(origins[record.id] ?? [.song])
        })
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

    /// A downloaded song's kept lyrics answer and its ETag (notes/app-lyrics.md 4.7) - none for the song included.
    func keptLyrics(_ songID: String) -> (lyrics: SongLyrics, etag: String?)? {
        guard let kept = try? store?.database.lyrics(songID),
              let lyrics = try? JSONDecoder().decode(SongLyrics.self, from: kept.json) else { return nil }
        return (lyrics, kept.etag)
    }

    /// An answer the player got online, for a song downloaded here: kept in place of the one kept when it differs - so a
    /// Get lyrics or a re-time on the server reaches the phone the next time the song plays (4.7). A 304 changes
    /// nothing, and isn't brought here.
    func lyricsAnswered(_ songID: String, body: Data, etag: String?) {
        guard let store, records[songID]?.state == .done else { return }
        let kept = try? store.database.lyrics(songID)
        guard kept?.json != body || kept?.etag != etag else { return }
        _ = try? store.database.putLyrics(song: songID, json: body, etag: etag, fetchedAt: ListenTracker.wallMs())
    }

    /// An album page's fresh answer for an album with songs asked for or here (3.7): kept in place of the old one, as
    /// answered. A song whose file deadwax now gives another size - its audio replaced on the server - is fetched again
    /// (8.4's "When the store changes a file"): the copy here is deleted and the song asked for afresh.
    ///
    /// The same answer gives a song asked for without its size (Now Playing's Download, Download Up Next on a queue put
    /// back - a queue entry carries no size) the size it lacked: the planner counts it at its real bytes, not a
    /// transcode's 320 kbps estimate (a FLAC is three times that), and its copy's length is checked against it.
    func albumAnswered(_ album: Album, body: Data) {
        guard let store, songsOfAlbum[album.id] != nil else { return }
        try? store.database.putAlbum(id: album.id, json: body, fetchedAt: ListenTracker.wallMs())
        albums[album.id] = album
        // deadwax's size now, for each song whose kept size differs or was never known
        var sizes: [String: Int64] = [:]
        // songs whose copy here isn't that size: not the file deadwax has now
        var refetch: Set<String> = []
        for song in album.song ?? [] {
            guard let record = records[song.id], !record.isTranscode, let size = song.size, size > 0,
                  record.sizeExpected != size else { continue }
            sizes[song.id] = size
            if record.state == .done, record.bytes != size { refetch.insert(song.id) }
        }
        guard !sizes.isEmpty else {
            reload()
            return
        }
        for id in refetch {
            guard let record = records[id], let file = store.fileURL(record) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
        update(Array(sizes.keys)) { record in
            var r = record
            r.sizeExpected = sizes[r.id]
            if refetch.contains(r.id), r.state == .done { r = DownloadRules.apply(.fileMissing, to: r) }
            return r
        }
        if !refetch.isEmpty { note("album \(album.id): \(refetch.count) replaced on the server, fetched again") }
        replan()
    }

    // MARK: actions (in the tap)

    /// A song's Download (its own origin).
    func download(_ song: Song) {
        want([song], origin: .song)
    }

    /// An album's Download: its songs not here, planned whole - a hand download, first in the order and never given
    /// way, even of an album of your library waiting for room; one kept off is kept off no more (2.7).
    func download(album: Album) {
        follower.setKeptOff(album: album.id, at: nil)
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

    /// An album's Remove Download: every song of it asked for through the album or alone, and with your library - which
    /// then leaves it off this phone until it is downloaded again (2.7, open question 7). Marked first, so the plan the
    /// removal starts doesn't ask for it again.
    func remove(album albumID: String) {
        if follower.on { follower.setKeptOff(album: albumID, at: ListenTracker.wallMs()) }
        let songs = records.values.filter { $0.albumID == albumID }.map(\.id)
        removeOrigins([.song, .album(albumID), .library], from: songs)
    }

    /// Didn't download's Remove of an album your library keeps: those songs' origins taken, the library's with them,
    /// and the album kept off - else the library would ask for them again. The library then lets go of the rest of it
    /// at the next turn, as for any album kept off; a song of it downloaded by hand stays.
    func remove(failed songIDs: [String], album albumID: String) {
        if follower.on { follower.setKeptOff(album: albumID, at: ListenTracker.wallMs()) }
        removeOrigins([.song, .album(albumID), .library], from: songIDs)
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
    /// sent kept. With Download your library on, it is turned off first (its dialog says so) - else the next check
    /// would download it all again; the library's list is kept.
    func removeAll() {
        guard let store else { return }
        if follower.on { follower.on = false }
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

    /// The starts and plays kept sent (app 0.8): Core's KeptSender - the starts first, so a play's count finds its start
    /// at deadwax, in batches of at most PlayHistory.postMax; then the plays, one at a time - only ever as the person
    /// whose store is open, and one send at a time.
    func sendKeptPlays() {
        sender.send()
    }

    /// The open store as the sender reads it: whose, and its database.
    private func keptStore() -> KeptStore? {
        store.map { KeptStore(owner: KeptOwner(server: $0.server, person: $0.person), database: $0.database) }
    }

    /// Who is signed in on this server now - whose a start is, and who a send would go as.
    private var signedIn: KeptOwner? {
        KeptOwner.of(server: server.address?.key, me: server.me)
    }

    /// What sends now, and as whom: nil offline, before the launch is ready, under a sign-in, with no client or no one
    /// signed in. Each answer comes back on the main thread.
    private func sendLine() -> KeptLine? {
        guard reachability.online, server.launch == .ready, server.signInOver == nil, let client = server.client,
              let owner = signedIn else { return nil }
        return KeptLine(owner: owner, sendStarts: { starts, done in
            Task { @MainActor in done(await KeptLine.status { _ = try await client.recordStarts(starts) }) }
        }, sendPlay: { play, done in
            Task { @MainActor in
                done(await KeptLine.status { try await client.scrobble(songID: play.songID, submission: true, time: play.timeMs) })
            }
        })
    }

    /// Debug's counts: the open store's plays and starts, and the starts held with no store for whoever is signed in.
    private func recountWaiting() {
        let plays = (try? store?.database.keptPlays().count) ?? 0
        let starts = ((try? store?.database.keptStartCount()) ?? 0) + sender.looseCount(signedIn)
        if plays != playsWaiting { playsWaiting = plays }
        if starts != startsWaiting { startsWaiting = starts }
    }

    /// The next send of the starts, `ms` from now (a start recorded before then sends at once).
    private func retryStarts(after ms: Int64) {
        startsRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sendKeptPlays() }
        }
        startsRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(ms)), execute: work)
    }

    // MARK: play history's starts (app 0.8)

    /// A song begun, kept until deadwax takes it - in the person's store, or held by the sender while none is open -
    /// and sent now, if it can be.
    func keepStart(_ played: Played) {
        sender.keep(played, owner: signedIn)
    }

    /// A play counted: its start, wherever it waits, sent counted.
    func countStart(songID: String, at: Int64) {
        sender.counted(songID: songID, at: at)
    }

    /// The starts waiting to be sent, oldest first - drawn in Up Next before deadwax has them.
    func keptStarts() -> [Played] {
        ((try? store?.database.keptStarts()) ?? []).map(\.played)
    }

    /// The newest page of the person's play history kept on this phone (`meta`), for Up Next with deadwax out of reach.
    func keptHistoryPage() -> HistoryPage? {
        guard let text = (try? store?.database.meta(PlayHistory.keptPageKey)) ?? nil else { return nil }
        return try? JSONDecoder().decode(HistoryPage.self, from: Data(text.utf8))
    }

    /// The newest page come, kept in place of the last.
    func keepHistoryPage(_ page: HistoryPage) {
        guard let store, let data = try? JSONEncoder().encode(page) else { return }
        try? store.database.setMeta(PlayHistory.keptPageKey, String(decoding: data, as: UTF8.self))
    }

    // MARK: the queue kept (7.5, 7.6)

    /// The person's queue kept on this phone (resume's: ResumeController reads it as it is made for them) - nil for
    /// none, or when their store can't be opened. By (server, person), not the open store: the player's resume may be
    /// made before this model has opened the person's store.
    func keptQueue(server: String, person: String) -> QueueKept? {
        guard let found = store(server: server, person: person) else { return nil }
        return try? found.database.keptResume()
    }

    /// The person's kept queue replaced (nil: forgotten) - as resume saves or takes a queue.
    func keepQueue(_ kept: QueueKept?, server: String, person: String) {
        guard let found = store(server: server, person: person) else { return }
        do {
            try found.database.keepResume(kept, at: Int64(Date().timeIntervalSince1970 * 1000))
        } catch {
            note("couldn't keep the queue: \(error)")
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
            return (address.key, DownloadStore.person(me))
        }()
        if let store, key.map({ $0.server != store.server || $0.person != store.person }) ?? true {
            close(store)
        }
        if store == nil, let key {
            open(server: key.server, person: key.person)
        }
        // the same person signed in again (a new session): the resume data kept carries the old session's cookie - it
        // would be refused, and every download held a minute for it
        if store != nil {
            let session = server.client?.session
            if let made = resumeSession, made != session { dropResumeData() }
            resumeSession = .some(session)
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
            follower.opened(opened)
            Task { await settle(opened) }
        } catch {
            storeProblem = String(describing: error)
            isOpen = false
            note("couldn't open the store: \(error)")
        }
    }

    private func close(_ closing: DownloadStore) {
        follower.closed()
        let out = records.values.filter { $0.state == .fetching }
        let tasks = Set(out.compactMap { live[$0.id] })
        // the tasks out become sign-in waits, and no resume data is kept past the person: it carries their session's
        // cookie, which has no business on disk once they have signed out (and is refused after a new sign-in)
        try? closing.database.transaction {
            for record in records.values where record.state == .fetching || record.resume != nil {
                var r = record.state == .fetching ? DownloadRules.apply(.signedOut, to: record) : record
                r.resume = nil
                try closing.database.put(r)
            }
        }
        Task { _ = await session.cancel(tasks, resume: false) }
        verifyStop.set()
        verifyQueue = []
        // the lyrics not yet asked for were the person's before: the next store's settle queues its own
        lyricsAsked.subtract(lyricsQueue)
        lyricsQueue = []
        live = [:]
        madeAt = [:]
        madeUnder = [:]
        resumeSession = nil
        coverLengths = [:]
        cachedCopies = [:]
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
        startsWaiting = 0
        sender.storeClosed()
        startsRetry?.cancel()
        startsRetry = nil
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
        // every song here with no lyrics kept - downloaded under 0.3, or its ask failed - asked again (4.7)
        if reachability.online {
            let withLyrics = (try? opened.database.lyricsSongs()) ?? []
            keepLyrics(ordered(records.values.filter { $0.state == .done && !withLyrics.contains($0.id) }).map(\.id))
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
        follower.cameToFront()
    }

    private func movedToBackground() {
        received = [:]
    }

    private func reachabilityChanged() {
        replan()
        if reachability.online { sendKeptPlays() }
        follower.reachabilityChanged()
    }

    // MARK: your library (Phase 3)

    /// Add to or Remove from my library answered in this app, for the album (Navidrome's id): the library followed is
    /// checked at once, a Remove marked so it goes without waiting for a second check (phase3-autodownload.md 2.3).
    func libraryChanged(album: String, removed: Bool) {
        follower.changedHere(album: album, removed: removed, at: ListenTracker.wallMs())
    }

    /// The switch went off: the library's origin taken from every song that carries it - those left with none
    /// deleted, through Phase 2's removeOrigins as every library removal is.
    private func libraryOff() {
        let songs = LibraryDownloads.songs(Array(records.values), origins: origins, library: [])
        let actions = LibraryDownloads.switchedOff(songs)
        libraryFill = nil
        libraryProgress = nil
        libraryWait = nil
        guard !actions.take.isEmpty else { return }
        note("library: switched off - \(actions.take.count) songs let go")
        removeOrigins(LibraryDownloads.gives, from: actions.take)
    }

    /// What the library does at this plan (2.7): its takes through removeOrigins (its own origin only), then its asks.
    /// Whether anything was done (a plan follows it).
    private func act(_ actions: LibraryDownloads.Actions, removedAlbums: Set<String>) -> Bool {
        var acted = false
        if !actions.take.isEmpty {
            let byWhy = Dictionary(grouping: actions.why.keys.sorted(), by: { (album: String) -> String in
                actions.why[album]?.rawValue ?? ""
            })
            for (why, albums) in byWhy.sorted(by: { $0.key < $1.key }) {
                note("library: \(why) - \(albums.count == 1 ? albums[0] : "\(albums.count) albums")")
            }
            // the store couldn't be written: nothing more this plan, and nothing marked done
            guard removeOrigins(LibraryDownloads.gives, from: actions.take) else { return true }
            acted = true
        }
        // the removed albums' downloads are let go (or they had none): done with
        follower.removalsDone(removedAlbums)
        if !actions.ask.isEmpty {
            wantLibrary(actions.ask)
            acted = true
        }
        return acted
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
                        var record = DownloadRecord(song: song, albumID: id, now: at)
                        // a queue entry carries no size: the kept album's answer may have it (else it comes with the
                        // album's answer, asked below, before the song's task is made)
                        if record.sizeExpected == nil, !record.isTranscode,
                           let size = albums[id]?.song?.first(where: { $0.id == song.id })?.size, size > 0 {
                            record.sizeExpected = size
                        }
                        try store.database.put(record)
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
        // a song whose whole copy is in the streaming cache is copied from there when the plan lets it go - so the
        // storage limit and the phone's reserve hold for it as for any download
        for song in fresh {
            if let cached = files.cache.reusable(song) { cachedCopies[song.id] = cached }
        }
        for id in Set(songs.compactMap { albumID ?? $0.albumId }) where albums[id] == nil {
            keepAlbum(id, client: server.client)
        }
        reload()
        replan()
    }

    /// Your library's albums that fit asked for under its origin (2.7) - one transaction, one plan after: a song already
    /// asked for by hand gains the origin beside its own; each album's answer, cover and loudness kept as a hand
    /// download's.
    private func wantLibrary(_ asks: [LibraryDownloads.Ask]) {
        guard let store else { return }
        let now = ListenTracker.wallMs()
        var fresh: [Song] = []
        var count = 0
        do {
            try store.database.transaction {
                for ask in asks {
                    for followed in ask.songs {
                        let at = now + Int64(count)
                        count += 1
                        if var record = try store.database.song(followed.id) {
                            if record.state == .failed {
                                record = DownloadRules.apply(.retry, to: record)
                                try store.database.put(record)
                            }
                        } else {
                            try store.database.put(DownloadRecord(song: followed.song, albumID: ask.album, now: at))
                            fresh.append(followed.song)
                        }
                        try store.database.addOrigin(.library, song: followed.id, at: at)
                    }
                }
            }
        } catch {
            note("library: couldn't keep the ask: \(error)")
            return
        }
        note("library: asked \(asks.count == 1 ? asks[0].album : "\(asks.count) albums") (\(count) songs)")
        for song in fresh {
            if let cached = files.cache.reusable(song) { cachedCopies[song.id] = cached }
        }
        for ask in asks where albums[ask.album] == nil { keepAlbum(ask.album, client: server.client) }
        reload()
        replan()
    }

    /// Origins taken from songs - Remove Download's, and the only way your library ever lets one go: a song left with
    /// none is deleted, its file, its task and (with its album's last song) the album's answer and cover. False when
    /// the store couldn't be written.
    @discardableResult
    private func removeOrigins(_ removed: Set<DownloadOrigin>, from songIDs: [String]) -> Bool {
        guard let store, !songIDs.isEmpty else { return true }
        var deleted: [String] = []
        do {
            deleted = try store.database.removeOrigins(removed, songs: songIDs)
        } catch {
            note("couldn't remove: \(error)")
            return false
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
        return true
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
        let freeSpace = DownloadStore.freeSpace() ?? Int64.max / 4
        // your library (Phase 3): the store's songs as its rules read them, its albums' places in the fill's order
        let library = follower.on ? follower.ordered : []
        let storeSongs = LibraryDownloads.songs(Array(records.values), origins: origins, library: library)
        let libraryHere = LibraryDownloads.fillInputs(storeSongs).libraryHere
        var rank: [String: Int] = [:]
        for (place, entry) in library.enumerated() where rank[entry.id] == nil { rank[entry.id] = place }
        var albumOf: [String: String] = [:]
        for song in storeSongs { albumOf[song.id] = song.albumID }
        let facts = DownloadPlan.Facts(bytesHere: bytesHere, libraryHere: libraryHere, limit: storageLimit.bytes,
                                       freeSpace: freeSpace,
                                       reach: reachability.reach, path: reachability.path,
                                       signedIn: server.launch == .ready && server.signInOver == nil && server.client != nil
                                           && !refused(server.client?.session),
                                       over: downloadOver)
        let askedSongs = asked.map { (record: DownloadRecord) -> DownloadPlan.Asked in
            DownloadPlan.Asked(record, origins: origins[record.id] ?? [.song], received: received[record.id] ?? 0,
                               libraryRank: rank[albumOf[record.id] ?? record.albumID])
        }
        if follower.on {
            // what the library asks for and gives back, before anything is planned: a plan follows whatever it does
            let removedAlbums = follower.removed
            let turn = LibraryDownloads.turn(library, removed: removedAlbums, songs: storeSongs, bytesHere: bytesHere,
                                             handToCome: DownloadPlan.handToCome(askedSongs, facts),
                                             limit: storageLimit.bytes, freeSpace: freeSpace,
                                             readsPending: follower.readsPending)
            if turn.fill != libraryFill { libraryFill = turn.fill }
            let progress = LibraryDownloads.progress(library, fill: turn.fill, songs: storeSongs)
            if progress != libraryProgress { libraryProgress = progress }
            // a list kept from before this launch (or before the switch went on) asks for nothing new until a check
            // has answered: what it gives back stands - the fill's and the checks' own
            var actions = turn.actions
            if !follower.fresh { actions.ask = [] }
            if act(actions, removedAlbums: removedAlbums) { return }
        } else if libraryFill != nil || libraryProgress != nil {
            libraryFill = nil
            libraryProgress = nil
        }
        let decisions = DownloadPlan.plan(askedSongs, facts)
        planned = decisions.mapValues(\.wait)
        // the row's wait: what the library's songs wait for while none is fetched
        let libraryAsked = askedSongs.filter { (song: DownloadPlan.Asked) -> Bool in song.isLibrary }
        let fetching = libraryAsked.contains { (song: DownloadPlan.Asked) -> Bool in song.out }
        let wait: DownloadWait? = fetching ? nil
            : libraryAsked.compactMap { (song: DownloadPlan.Asked) -> DownloadWait? in decisions[song.id]?.wait }
                .first { (wait: DownloadWait) -> Bool in wait != .queued }
        if wait != libraryWait { libraryWait = wait }
        // tasks the plan lets go: cancelled, their resume data kept - but not a sign-out's (it carries the old cookie)
        let letGo = asked.filter { $0.state == .fetching && decisions[$0.id]?.task == false }
        if !letGo.isEmpty {
            let signOut = DownloadPlan.sharedWait(facts) == .signIn
            let ids = Set(letGo.compactMap { live[$0.id] })
            let resumes = await session.cancel(ids, resume: !signOut)
            guard self.store === store else { return }
            update(letGo.map(\.id)) { record in
                // one that arrived (or ended otherwise) while the cancel was out is left as it is now: a copy here
                // set back to wanted would be fetched again
                guard record.state == .fetching else { return record }
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
        // tasks the plan lets go of the leash: made now, the oldest ask's album from its top - but not a song whose size
        // is on its way with its album's answer (it would be counted at a transcode's estimate, and its copy's length
        // checked against nothing)
        let toMake = ordered(records.values.filter {
            $0.state == .wanted && decisions[$0.id]?.task == true && !sizeComing($0)
        })
        var made: [String: String] = [:]
        var copied: [DownloadRecord] = []
        for (index, record) in toMake.enumerated() {
            // a cached copy that didn't hold (its length, or its move) is simply downloaded, as if there were none
            if let copy = copyFromCache(record, in: store), copy.state == .done {
                copied.append(copy)
                continue
            }
            if let name = make(record, in: store, priority: max(0.1, 0.9 - Float(index) * 0.01)) { made[record.id] = name }
        }
        if !copied.isEmpty {
            try? store.database.transaction {
                for record in copied { try store.database.put(record) }
            }
            reload()
        }
        update(Array(made.keys)) { record in
            var r = DownloadRules.apply(.taskMade(made[record.id] ?? ""), to: record)
            r.resume = nil // spent on the task made from it
            return r
        }
    }

    /// The song's whole copy from the streaming cache, when it had one as it was asked for: copied in (an APFS clone, at
    /// once, no data spent) and checked as any download - the record as it arrived, or nil (no copy, or it's gone).
    private func copyFromCache(_ record: DownloadRecord, in store: DownloadStore) -> DownloadRecord? {
        guard let cached = cachedCopies.removeValue(forKey: record.id), let part = store.partURL(record) else { return nil }
        try? FileManager.default.removeItem(at: part)
        guard (try? FileManager.default.copyItem(at: cached, to: part)) != nil else { return nil }
        note("from the streaming cache: \(record.id)")
        return arrive(record, part: part, in: store)
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
        madeUnder[record.id] = downloadOver
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
            // arrived while the cancel was out: kept as it is
            guard record.state == .fetching else { return record }
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
                // an older task's file: one that ended while the app was gone, its event later than the launch's settle,
                // which asked for the song again. A whole file is the song all the same - taken, and the newer task let
                // go, rather than fetched twice; anything else is dropped and the newer task carries on.
                guard let part, unsaved == nil, DownloadRules.isTheSong(status: status),
                      let waiting = try? target.database.song(name.songID), waiting.state == .fetching,
                      DownloadRules.lengthMatches(DownloadStore.length(part) ?? 0, record: waiting) else {
                    if let part { try? FileManager.default.removeItem(at: part) }
                    return
                }
                Task { _ = await session.cancel([mine], resume: false) }
                note("\(name.songID): an older task's file taken, task \(mine) let go")
            }
            // `live` is the signed-in person's: another's task ending says nothing of theirs
            if current { live[name.songID] = nil }
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
            if current { live[name.songID] = nil }
            // resume data from a task made under another Download over than now would resume under that one's flags
            let kept = current && madeUnder[name.songID].map { $0 != downloadOver } == true ? nil : resume
            guard var record = try? target.database.song(name.songID), record.state != .done else { return }
            if forceQuit {
                try? target.database.setMeta("force_quit_at", String(ListenTracker.wallMs()))
                record = DownloadRules.apply(.cancelled(resume: kept), to: record)
                note("\(name.songID): force quit\(resume == nil ? "" : ", resumable")")
            } else if error.code == NSURLErrorCancelled {
                record = DownloadRules.apply(.cancelled(resume: kept), to: record)
            } else {
                let reason = error.localizedDescription
                let failure: DownloadFailure = error.code == NSURLErrorTimedOut ? .timeout(reason: reason) : .offline(reason: reason)
                let counts = current && madeAt[name.songID].map { reachability.answeredSince($0) && reachability.online } ?? false
                record = DownloadRules.apply(.noAnswer(failure, resume: kept, counts: counts), to: record)
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
        guard let found = store(server: name.server, person: name.person) else { return nil }
        return (found, found === store)
    }

    /// A person's store: the open one when it is theirs, else one opened aside (kept in `elsewhere`, which `open` takes
    /// it from when they are signed in).
    private func store(server: String, person: String) -> DownloadStore? {
        if let store, store.server == server, store.person == person { return store }
        let key = "\(server)|\(person)"
        if let other = elsewhere[key] { return other }
        guard let opened = try? DownloadStore(server: server, person: person) else { return nil }
        elsewhere[key] = opened
        return opened
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
        if target === store { keepLyrics([record.id]) }
        return arrived
    }

    // MARK: the sound check (8.4 step 2)

    /// A song's sound check queued. Started on the next turn, not now: a copy queued as it arrives has its record written
    /// and read back just after (`arrive` returns it to be kept) - a check started at once would find it not here yet
    /// and drop it until the next launch or return to the front.
    private func queueCheck(_ songID: String) {
        guard !verifyQueue.contains(songID), verifying != songID else { return }
        verifyQueue.append(songID)
        Task { self.checkNext() }
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
            defer {
                albumsAsked.remove(albumID)
                // its songs held for their size go now, with it or (no answer) at their estimate
                replan()
            }
            do {
                let response = try await client.answer(client.request(Routes.album, path: ["album_id": albumID]))
                let album = try client.decode(Album.self, response)
                // removed meanwhile: nothing kept of it
                guard self.store === store, songsOfAlbum[albumID] != nil else { return }
                // kept as an album page's answer is: a song's size learned, or a replaced file fetched again
                albumAnswered(album, body: response.body)
                if let cover = album.coverArt, !cover.isEmpty {
                    let data = try await client.cover(coverID: cover, size: DownloadStore.coverSize)
                    guard self.store === store else { return }
                    let name = DownloadStore.coverName(cover, data: data)
                    let url = store.covers.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                    DownloadStore.protect(url)
                    try store.database.setCover(album: albumID, file: name)
                    KeptCovers.shared.keep(cover, url)
                    reload()
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

    // MARK: lyrics kept (notes/app-lyrics.md 4.7)

    /// The songs' lyrics asked for and kept with them, one ask at a time, never holding a download up: queued as each
    /// song's file arrives and, for every song here with none, at each settle. Started on the next turn, as the sound
    /// check is - a song queued as it arrives has its record written just after.
    private func keepLyrics(_ songIDs: [String]) {
        let fresh = songIDs.filter { lyricsAsked.insert($0).inserted }
        guard !fresh.isEmpty else { return }
        lyricsQueue.append(contentsOf: fresh)
        guard !askingLyrics else { return }
        askingLyrics = true
        Task {
            while !lyricsQueue.isEmpty {
                let songID = lyricsQueue.removeFirst()
                await keepLyrics(songID)
                lyricsAsked.remove(songID)
            }
            askingLyrics = false
        }
    }

    /// One song's: asked with the kept answer's ETag (none, for a song never kept), and kept unless the store changed
    /// meanwhile (another person signed in) or the song is no longer here. A failure keeps nothing - the next settle
    /// asks again.
    private func keepLyrics(_ songID: String) async {
        guard let store, let client = server.client, reachability.online, records[songID]?.state == .done else { return }
        let kept = try? store.database.lyrics(songID)
        do {
            let fetched = try await client.lyrics(songID: songID, ifNoneMatch: kept?.etag)
            guard case .fresh(let answer, let etag) = fetched, self.store === store, records[songID]?.state == .done,
                  answer.body != kept?.json || etag != kept?.etag else { return }
            try store.database.putLyrics(song: songID, json: answer.body, etag: etag, fetchedAt: ListenTracker.wallMs())
            note("lyrics kept: \(songID)\(answer.lyrics.lines.isEmpty ? " (none)" : "")")
        } catch {
            if !APIFailure.isCancellation(error) { note("lyrics \(songID) not kept: \(error)") }
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
        playable.set(urls)
        var keptAlbums: [String: Album] = [:]
        var covers: [String: URL] = [:]
        for answer in (try? store.database.albums()) ?? [] {
            if let file = answer.cover { bytes += coverLength(file, in: store) }
            guard let album = albums[answer.id] ?? (try? JSONDecoder().decode(Album.self, from: answer.json)) else { continue }
            keptAlbums[answer.id] = album
            if let cover = album.coverArt, let file = answer.cover { covers[cover] = store.covers.appendingPathComponent(file) }
        }
        if keptAlbums != albums { albums = keptAlbums }
        // what's used is the songs' bytes and their covers', as the planner counts them (6.3, 8.5)
        if bytes != bytesHere { bytesHere = bytes }
        KeptCovers.shared.set(covers)
        let quit = (try? store.database.meta("force_quit_at")).flatMap { $0.flatMap(Double.init) }
        let at = quit.map { Date(timeIntervalSince1970: $0 / 1000) }
        if at != forceQuitAt { forceQuitAt = at }
        recountWaiting()
    }

    // MARK: helpers

    /// A kept cover's length, read from disk once.
    private func coverLength(_ file: String, in store: DownloadStore) -> Int64 {
        if let known = coverLengths[file] { return known }
        let length = DownloadStore.length(store.covers.appendingPathComponent(file)) ?? 0
        if length > 0 { coverLengths[file] = length }
        return length
    }

    /// Every song's resume data let go (its tasks are made from the first byte): a Download over changed, or another
    /// session. Not a fetching song's - its task is cancelled and remade by whoever let it go.
    private func dropResumeData() {
        let stale = records.values.filter { $0.resume != nil && $0.state != .fetching }.map(\.id)
        guard !stale.isEmpty else { return }
        update(stale) { record in
            var r = record
            r.resume = nil
            return r
        }
        note("resume data let go: \(stale.count)")
    }

    /// A song asked for without its size (a queue entry has none) whose album's answer, which has it, is being asked:
    /// its task waits for it.
    private func sizeComing(_ record: DownloadRecord) -> Bool {
        !record.isTranscode && record.sizeExpected == nil && albumsAsked.contains(record.albumID)
    }

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
