import Foundation

/// The streaming cache's rules (the plan's section 4): every song streamed is kept as
/// `Caches/deadwax/stream/<song-id>.<suffix>`, across launches, and played from that file the next
/// time; once their total passes `limit`, the least recently played go first. iOS may empty Caches
/// itself under pressure: then songs are fetched again, and nothing breaks.
///
/// - A fetch writes into `<name>.part`, renamed to `<name>` only once every byte has arrived and its
///   length is checked (the app's StreamFetch). So a file under its own name is always complete.
/// - At launch every part is deleted (a fetch the app was stopped in), and anything the cache
///   doesn't name: the rest are kept. A folder without `layoutMarker` (Phase 0's, whose fetches wrote
///   under the song's own name) is emptied once.
/// - A file is played again when its length is still the song's - for a file sent as it is,
///   Navidrome's `size` when it says one; a transcode (mp3) on any length but none. Another length
///   (the file replaced or retagged on the server) is deleted and the song streamed afresh.
/// - "Last played" is the file's modification date, set to now whenever it is opened to play.
/// - Never evicted: a song in use (the one heard, the next one, any being fetched).
///
/// Pure rules here, and the folder's own few operations (FileManager, which Linux has too) in
/// `StreamCacheFolder`, so all of it is tested on Linux. The app's SongFiles uses both.
public enum StreamCache {
    /// The cache's own limit: 2,000,000,000 bytes, as iOS's Storage screen counts (not 2 GiB).
    public static let limit: Int64 = 2_000_000_000
    /// What a fetch's file is called until the song has all arrived.
    public static let partExtension = "part"

    /// The song's file in the cache, as it arrives: `<id>.<suffix>` (`mp3` for a transcode). Nil
    /// for an id with nothing that can name a file.
    public static func name(for song: Song) -> String? {
        LocalFiles.name(songID: song.id, suffix: StreamFormat.suffix(for: song))
    }

    /// Where the fetch of `name` writes until it is complete.
    public static func partName(_ name: String) -> String { "\(name).\(partExtension)" }

    /// Whether a file name is one the cache gives a complete song: `<id>.<suffix>`, the id 1-128 of
    /// `[A-Za-z0-9_-]`, the suffix 1-10 of `[a-z0-9]` (LocalFiles.name's own rule). A part is not.
    public static func isSongName(_ fileName: String) -> Bool {
        guard let dot = fileName.lastIndex(of: ".") else { return false }
        let id = fileName[..<dot]
        let suffix = fileName[fileName.index(after: dot)...]
        guard (1...128).contains(id.unicodeScalars.count), (1...10).contains(suffix.unicodeScalars.count) else {
            return false
        }
        guard suffix != partExtension else { return false }
        return id.unicodeScalars.allSatisfy(LocalFiles.safe)
            && suffix.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    /// The file that says the folder is this layout's: every song under its own name complete, every
    /// fetch in a part. Phase 0 (app 0.1) wrote each fetch straight under the song's name, unchecked,
    /// and emptied the folder at every launch - so a folder without the marker can hold a song cut
    /// short under its own name, and is emptied once. (No dot in it: never a song's name.)
    public static let layoutMarker = "layout-1"

    /// What a launch deletes from the folder: every part, and anything the cache doesn't name - or,
    /// without the layout's marker (a folder Phase 0 left), everything in it.
    public static func sweep(_ fileNames: [String]) -> [String] {
        guard fileNames.contains(layoutMarker) else { return fileNames.sorted() }
        return fileNames.filter { !isSongName($0) && $0 != layoutMarker }.sorted()
    }

    /// The songs whose files and fetches the app keeps after the song heard changes. `shown` is the
    /// queue's index from the engine's last state to reach the main thread, `engineAt` the engine's own
    /// index read just now (nil: it holds no queue). A state can be older than the engine - a Previous
    /// the engine has already opened a fetch for - so the songs kept begin at the earlier of the two,
    /// and a fetch the engine has just opened is never let go on the word of a late state.
    /// `inUse` (never evicted): from there to the song after the later of the two. `ahead` (their
    /// fetches go on; any other is let go): every song from there to the queue's end, by id.
    public static func kept(_ songs: [Song], shown: Int, engineAt: Int?) -> (inUse: [Song], ahead: Set<String>) {
        guard !songs.isEmpty else { return ([], []) }
        let last = songs.count - 1
        let shownAt = min(max(shown, 0), last)
        let now = engineAt.map { min(max($0, 0), last) } ?? shownAt
        let from = min(shownAt, now)
        let through = min(max(shownAt, now) + 1, last)
        return (Array(songs[from...through]), Set(songs[from...].map(\.id)))
    }

    /// A file's length from its attributes, as either Foundation gives it: Apple's an NSNumber, the
    /// open-source one's (Linux) a Swift UInt. Zero when there is none.
    public static func byteCount(_ value: Any?) -> Int64 {
        switch value {
        case let count as UInt: return Int64(clamping: count)
        case let count as UInt64: return Int64(clamping: count)
        case let count as Int: return Int64(count)
        case let count as Int64: return count
        case let count as NSNumber: return count.int64Value
        default: return 0
        }
    }

    /// Whether a file's attributes are a regular file's (Apple's give the type bridged from a string).
    static func isRegular(_ attributes: [FileAttributeKey: Any]) -> Bool {
        let type = attributes[.type]
        return (type as? FileAttributeType) == .typeRegular || (type as? String) == FileAttributeType.typeRegular.rawValue
    }

    /// What to do with the cache's file for a song about to be played.
    public enum Reuse: Sendable, Equatable {
        /// No file: stream it.
        case none
        /// Its length is the song's: play the file.
        case play
        /// Another length: delete it, and stream the song afresh.
        case replace
    }

    /// Whether a complete file of `bytes` (nil: there is none) plays for `song`.
    public static func reuse(bytes: Int64?, song: Song) -> Reuse {
        guard let bytes else { return .none }
        if StreamFormat.format(for: song) == "raw" {
            return LocalFiles.lengthMatches(bytes, song: song) ? .play : .replace
        }
        // Navidrome's size is the original's, not the transcode's: any length but none
        return bytes > 0 ? .play : .replace
    }

    /// A complete song in the cache.
    public struct File: Sendable, Equatable {
        public let name: String
        public let bytes: Int64
        /// When it was last opened to play (its modification date).
        public let lastPlayed: Date

        public init(name: String, bytes: Int64, lastPlayed: Date) {
            self.name = name
            self.bytes = bytes
            self.lastPlayed = lastPlayed
        }
    }

    /// The files to delete so the rest total at most `limit`: the least recently played first (by
    /// name when two were played at the same moment), never one named in `keep`. When what is kept
    /// alone passes the limit, everything else goes and the total stays over it.
    public static func evictions(_ files: [File], limit: Int64 = limit, keep: Set<String>) -> [String] {
        var total = files.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
        guard total > limit else { return [] }
        let oldestFirst = files.filter { !keep.contains($0.name) }.sorted {
            $0.lastPlayed != $1.lastPlayed ? $0.lastPlayed < $1.lastPlayed : $0.name < $1.name
        }
        var gone: [String] = []
        for file in oldestFirst where total > limit {
            gone.append(file.name)
            total -= max(file.bytes, 0)
        }
        return gone
    }
}

/// The streaming cache's folder on disk: StreamCache's rules applied to it.
public struct StreamCacheFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func url(for name: String) -> URL { url.appendingPathComponent(name, isDirectory: false) }
    public func partURL(for name: String) -> URL { url(for: StreamCache.partName(name)) }

    /// At launch: the folder made if it isn't there, its parts and strangers deleted (all of it, once,
    /// when Phase 0 left it - then marked as this layout's), and the songs kept down to `limit`. Says
    /// what it deleted.
    @discardableResult
    public func sweep(limit: Int64 = StreamCache.limit) -> [String] {
        let manager = FileManager.default
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        let names = (try? manager.contentsOfDirectory(atPath: url.path)) ?? []
        var gone = StreamCache.sweep(names)
        for name in gone { try? manager.removeItem(at: url(for: name)) }
        if !names.contains(StreamCache.layoutMarker) {
            _ = manager.createFile(atPath: url(for: StreamCache.layoutMarker).path, contents: Data())
        }
        gone += evict(limit: limit, keep: [])
        return gone
    }

    /// The complete songs in the folder, with their lengths and when each was last played.
    public func files() -> [StreamCache.File] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter(StreamCache.isSongName).compactMap { name in
            guard let attributes = try? manager.attributesOfItem(atPath: url(for: name).path),
                  StreamCache.isRegular(attributes) else { return nil }
            let date = attributes[.modificationDate] as? Date ?? .distantPast
            return StreamCache.File(name: name, bytes: StreamCache.byteCount(attributes[.size]), lastPlayed: date)
        }
    }

    /// The length of the complete file of `name`, or nil when there is none.
    public func bytes(of name: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: name).path),
              StreamCache.isRegular(attributes) else { return nil }
        return StreamCache.byteCount(attributes[.size])
    }

    /// The cache's complete copy of `song`, marked as played `now` - or nil: there is none, or there
    /// was one of another length, deleted here so the song is streamed afresh.
    public func reusable(_ song: Song, now: Date = Date()) -> URL? {
        guard let name = StreamCache.name(for: song) else { return nil }
        switch StreamCache.reuse(bytes: bytes(of: name), song: song) {
        case .none:
            return nil
        case .replace:
            try? FileManager.default.removeItem(at: url(for: name))
            return nil
        case .play:
            touch(name, now: now)
            return url(for: name)
        }
    }

    /// Marks a song's file as played `now`.
    public func touch(_ name: String, now: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url(for: name).path)
    }

    /// Deletes the least recently played songs until the rest total at most `limit`, never one named
    /// in `keep`. Says what it deleted.
    @discardableResult
    public func evict(limit: Int64 = StreamCache.limit, keep: Set<String>) -> [String] {
        let gone = StreamCache.evictions(files(), limit: limit, keep: keep)
        for name in gone { try? FileManager.default.removeItem(at: url(for: name)) }
        return gone
    }
}
