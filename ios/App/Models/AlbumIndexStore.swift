import DeadwaxCore
import Foundation

/// The last album list of each (server, person, scope) kept on disk (D2): Core's KeptAlbumIndex - which says where
/// it goes and which bytes may be drawn for whom - written and read here, off the main actor, one at a time.
///
/// In Application Support/deadwax/<server>/album-index/, excluded from backup (it is all deadwax's to send again).
/// A file read back that isn't a list for the person asking - another version, unreadable, or written for another
/// name that came to the same file - is deleted and is no list. A failure to write only means the next launch waits
/// for the network, as Phase 0's did.
actor AlbumIndexFiles {
    /// Whose list, of which scope, on which server (ServerAddress.key, /me's `user`).
    struct Key: Sendable, Hashable {
        let server: String
        let user: String
        let scope: AlbumScope
    }

    /// A list as kept: the answer, its ETag, and when it landed (milliseconds since 1970).
    struct Saved: Sendable {
        let answer: AlbumIndexAnswer
        let etag: String?
        let at: Int64
    }

    private let base: URL?

    init(base: URL? = AlbumIndexFiles.defaultBase()) {
        self.base = base
    }

    nonisolated static func defaultBase() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("deadwax", isDirectory: true)
    }

    /// The list kept for `key`, or nil.
    func read(_ key: Key) -> Saved? {
        guard let url = file(key), let data = try? Data(contentsOf: url) else { return nil }
        guard let kept = KeptAlbumIndex.read(data, server: key.server, user: key.user, scope: key.scope) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return Saved(answer: kept.answer, etag: kept.etag, at: kept.at)
    }

    /// `saved` kept as `key`'s list, in place of the one before (written whole, then moved into place).
    func write(_ key: Key, _ saved: Saved) {
        guard let folder = folder(key), let url = file(key) else { return }
        let kept = KeptAlbumIndex(server: key.server, user: key.user, scope: key.scope, etag: saved.etag, at: saved.at,
                                  answer: saved.answer)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            Self.excludeFromBackup(folder)
            try kept.encoded().write(to: url, options: .atomic)
            Self.excludeFromBackup(url)
        } catch {
            // not kept: the next launch waits for the network
        }
    }

    private func folder(_ key: Key) -> URL? {
        guard let base else { return nil }
        return KeptAlbumIndex.folder(server: key.server).reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    private func file(_ key: Key) -> URL? {
        folder(key)?.appendingPathComponent(KeptAlbumIndex.fileName(user: key.user, scope: key.scope), isDirectory: false)
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
