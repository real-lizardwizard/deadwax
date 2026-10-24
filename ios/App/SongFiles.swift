import AVFAudio
import DeadwaxAudio
import DeadwaxCore
import Foundation

/// Where songs are on the phone, Phase 0's way:
///
/// - **Streamed**: fetched into the streaming cache (Caches/deadwax/stream, which iOS may empty) and
///   decoded as the bytes arrive. Once a song has all arrived it plays from that file, seekable to
///   the sample. Phase 0 keeps the cache for one launch: it is emptied when the app starts.
/// - **Downloaded**: the original as deadwax sends it (`format=raw`), kept in Application Support
///   (not Caches, which iOS deletes under pressure), excluded from backup, and readable while the
///   phone is locked after its first unlock - so a locked phone can open the next song.
///
/// Opened from the engine's queue and the main thread, so everything is behind one lock.
final class SongFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var fetches: [String: StreamFetch] = [:]
    let streamFolder: URL
    let downloadFolder: URL

    init() {
        let manager = FileManager.default
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        streamFolder = caches.appendingPathComponent("deadwax/stream", isDirectory: true)
        downloadFolder = support.appendingPathComponent("deadwax/phase0", isDirectory: true)
        try? manager.removeItem(at: streamFolder)
        try? manager.createDirectory(at: streamFolder, withIntermediateDirectories: true)
        try? manager.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        Self.keepOffBackups(downloadFolder)
    }

    // MARK: streaming

    /// The song's audio from `start`: the cache's complete copy when there is one, or a decode of
    /// the bytes as they arrive (a fetch started now, or the one already running).
    func streamSource(for song: Song, client: DeadwaxClient, start: StartPoint) throws -> PCMSource {
        let fetch = startFetch(for: song, client: client)
        if fetch.isComplete {
            return try FileSource(url: fetch.fileURL, start: start)
        }
        return try StreamSource(bytes: fetch, typeHint: audioFileType(forSuffix: StreamFormat.suffix(for: song)),
                                start: start)
    }

    /// Starts fetching the song now (the next song, while this one plays), so its first bytes are
    /// there when the engine reaches it and the join stays seamless.
    func prefetch(_ song: Song, client: DeadwaxClient) {
        _ = startFetch(for: song, client: client)
    }

    private func startFetch(for song: Song, client: DeadwaxClient) -> StreamFetch {
        lock.lock()
        defer { lock.unlock() }
        if let fetch = fetches[song.id], fetch.failure == nil { return fetch }
        let name = LocalFiles.name(songID: song.id, suffix: StreamFormat.suffix(for: song)) ?? "song.bin"
        let request = URLRequest(client.streamRequest(songID: song.id, format: StreamFormat.format(for: song)))
        let fetch = StreamFetch(request: request, fileURL: streamFolder.appendingPathComponent(name))
        fetches[song.id] = fetch
        fetch.start()
        return fetch
    }

    /// The first bytes of the song's file, wherever it is on the phone - for the readout's FLAC
    /// STREAMINFO.
    func header(of song: Song) -> Data? {
        if let url = downloadedURL(for: song) {
            return try? FileHandle(forReadingFrom: url).read(upToCount: 64 * 1024)
        }
        lock.lock()
        let fetch = fetches[song.id]
        lock.unlock()
        return fetch?.bytes(at: 0, count: 64 * 1024)
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
            throw AudioFailure("That song's id can't name a file.")
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
            throw AudioFailure(status == 401 ? "deadwax says this phone isn't signed in (401)."
                                             : "deadwax answered \(status) for this song.")
        }
        let length = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard StreamFormat.format(for: song) != "raw" || LocalFiles.lengthMatches(length, song: song) else {
            try? FileManager.default.removeItem(at: temporary)
            throw AudioFailure("The download was \(length) bytes, not the \(song.size ?? 0) Navidrome says - left out.")
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
