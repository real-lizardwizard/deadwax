import AVFAudio
import DeadwaxAudio
import DeadwaxCore
import Foundation

/// Where songs are on the phone:
///
/// - **Streamed**: fetched into the streaming cache (Caches/deadwax/stream/<song-id>.<suffix>, Core's
///   StreamCache) and decoded as the bytes arrive. Once a song has all arrived it is kept, across
///   launches, and plays from that file - seekable to the sample - the next time, while its length is
///   still the song's. The least recently played go first once the cache passes 2,000,000,000 bytes;
///   iOS may empty Caches itself under pressure, and then songs are fetched again. A song skipped past
///   has its fetch let go and its part deleted.
/// - **Downloaded** (Phase 0's, kept for the Test sounds screen): the original as deadwax sends it
///   (`format=raw`), kept in Application Support (not Caches, which iOS deletes under pressure),
///   excluded from backup, and readable while the phone is locked after its first unlock - so a locked
///   phone can open the next song.
///
/// Opened from the engine's queue and the main thread, so everything is behind one lock.
final class SongFiles: @unchecked Sendable {
    private let lock = NSLock()
    /// The fetches still arriving, by song id. A complete one leaves (it is in the cache now), and so
    /// does one that failed (the next ask streams afresh) or was let go.
    private var fetches: [String: StreamFetch] = [:]
    /// The cache's names of the songs in use - the one heard and those the engine may read next -
    /// never evicted.
    private var kept: Set<String> = []
    let cache: StreamCacheFolder
    let downloadFolder: URL

    init() {
        let manager = FileManager.default
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cache = StreamCacheFolder(url: caches.appendingPathComponent("deadwax/stream", isDirectory: true))
        downloadFolder = support.appendingPathComponent("deadwax/phase0", isDirectory: true)
        // the parts of fetches the app was stopped in, and anything the cache doesn't name, deleted
        // (everything, once, in the folder 0.1 left: its fetches wrote under the song's own name, so a
        // song cut short there would pass for whole); the songs kept, down to the limit
        cache.sweep()
        try? manager.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        Self.keepOffBackups(downloadFolder)
    }

    // MARK: streaming

    /// The song's audio from `start`: the cache's complete copy when there is one, or a decode of
    /// the bytes as they arrive (a fetch started now, or the one already running).
    func streamSource(for song: Song, client: DeadwaxClient, start: StartPoint) throws -> PCMSource {
        if let url = cached(song) {
            return try FileSource(url: url, start: start)
        }
        let fetch = try startFetch(for: song, client: client)
        if fetch.isComplete {
            return try FileSource(url: fetch.fileURL, start: start)
        }
        return try StreamSource(bytes: fetch, typeHint: audioFileType(forSuffix: StreamFormat.suffix(for: song)),
                                start: start)
    }

    /// Starts fetching the song now (the next song, while this one plays), so its first bytes are
    /// there when the engine reaches it and the join stays seamless. Nothing when the cache has it.
    func prefetch(_ song: Song, client: DeadwaxClient) {
        if let name = StreamCache.name(for: song), StreamCache.reuse(bytes: cache.bytes(of: name), song: song) == .play {
            return
        }
        _ = try? startFetch(for: song, client: client)
    }

    /// `inUse`: the song heard and the next one - their files are never evicted (nor is any song
    /// still arriving). `ahead`: the ids of every song from the one heard to the queue's end (the
    /// earliest the engine may be reading: StreamCache.kept) - a fetch of any other song (one skipped
    /// past, or of a queue played no more) is let go and its part deleted; a complete one is the
    /// cache's, and stays. Songs further ahead keep arriving: the engine may be reading one already (a
    /// short next song), and they will play.
    func keep(_ inUse: [Song], ahead: Set<String>) {
        let gone: [StreamFetch] = lock.withLock {
            kept = Set(inUse.compactMap(StreamCache.name(for:)))
            let gone = fetches.filter { !ahead.contains($0.key) }
            for id in gone.keys { fetches[id] = nil }
            return Array(gone.values)
        }
        for fetch in gone { fetch.cancel() }
    }

    /// The cache's complete copy, unless a fetch of the song is running (which will replace it).
    private func cached(_ song: Song) -> URL? {
        let fetching = lock.withLock { fetches[song.id] != nil }
        return fetching ? nil : cache.reusable(song)
    }

    private func startFetch(for song: Song, client: DeadwaxClient) throws -> StreamFetch {
        guard let name = StreamCache.name(for: song) else {
            throw AudioFailure("That song's id can't name a file.", kind: .unsupported)
        }
        let (fetch, fresh): (StreamFetch, Bool) = lock.withLock {
            if let fetch = fetches[song.id], fetch.failure == nil, !fetch.isCancelled { return (fetch, false) }
            let request = URLRequest(client.streamRequest(songID: song.id, format: StreamFormat.format(for: song)))
            let fetch = StreamFetch(request: request, fileURL: cache.url(for: name))
            fetch.onFinish = { [weak self] fetch in self?.finished(fetch, songID: song.id) }
            fetches[song.id] = fetch
            return (fetch, true)
        }
        // started outside the lock: a fetch that fails at once calls onFinish, which takes it
        if fresh { fetch.start() }
        return fetch
    }

    /// A fetch ended: complete (in the cache now - the cache kept to its limit) or failed.
    private func finished(_ fetch: StreamFetch, songID: String) {
        let keep: Set<String> = lock.withLock {
            if fetches[songID] === fetch { fetches[songID] = nil }
            return kept.union(fetches.values.map(\.fileURL.lastPathComponent))
        }
        if fetch.isComplete { cache.evict(keep: keep) }
    }

    /// The first bytes of the song's file, wherever it is on the phone - for the readout's FLAC
    /// STREAMINFO.
    func header(of song: Song) -> Data? {
        if let url = downloadedURL(for: song) {
            return try? FileHandle(forReadingFrom: url).read(upToCount: 64 * 1024)
        }
        if let fetch = lock.withLock({ fetches[song.id] }) {
            return fetch.bytes(at: 0, count: 64 * 1024)
        }
        guard let name = StreamCache.name(for: song), cache.bytes(of: name) != nil else { return nil }
        return try? FileHandle(forReadingFrom: cache.url(for: name)).read(upToCount: 64 * 1024)
    }

    // MARK: downloads

    func downloadedURL(for song: Song) -> URL? {
        guard let name = LocalFiles.name(songID: song.id, suffix: StreamFormat.suffix(for: song)) else { return nil }
        let url = downloadFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads the original, checks its length against Navidrome's size, and keeps it.
    func download(_ song: Song, client: DeadwaxClient) async throws {
        guard let name = LocalFiles.name(songID: song.id, suffix: StreamFormat.suffix(for: song)) else {
            throw AudioFailure("That song's id can't name a file.", kind: .unsupported)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.allowsCellularAccess = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(client.streamRequest(songID: song.id, format: StreamFormat.format(for: song)))
        let (temporary, response) = try await session.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw status == 401
                ? AudioFailure("deadwax says this phone isn't signed in (401). Sign in again.", kind: .signedOut, status: 401)
                : AudioFailure("deadwax answered \(status) for this song.", kind: .unsupported, status: status)
        }
        let length = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard StreamFormat.format(for: song) != "raw" || LocalFiles.lengthMatches(length, song: song) else {
            try? FileManager.default.removeItem(at: temporary)
            throw AudioFailure("The download was \(length) bytes, not the \(song.size ?? 0) Navidrome says - left out.",
                               kind: .network)
        }
        let target = downloadFolder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: target.path)
        Self.keepOffBackups(target)
    }

    func removeDownloads() {
        try? FileManager.default.removeItem(at: downloadFolder)
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        Self.keepOffBackups(downloadFolder)
    }

    private static func keepOffBackups(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
