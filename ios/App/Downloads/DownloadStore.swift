import DeadwaxCore
import Foundation

/// One person's downloads on this phone (notes/ios-specs/phase2-downloads.md 8.1): their folder, its database (Core's
/// DownloadDatabase) and the files - what's kept off backups, readable while the phone is locked, and how much room is
/// left.
///
/// ```
/// Application Support/deadwax/<server>/downloads/<person>/
///   downloads.sqlite (+ -wal, -shm)
///   music/<song-id>.<suffix>          the file as served
///   music/<song-id>.<suffix>.part     a finished task's file until its length is checked
///   covers/<cover-id>-1024.<ext>
/// ```
///
/// Per (server, person): another sign-in on this phone has its own, and the first person's stay for them. Used on the
/// main actor; the background session's delegate only asks `partURL(for:)`, which needs nothing open.
final class DownloadStore {
    /// The server's key (`ServerAddress.key`) and the person (`me.user`, or "local" with logins off).
    let server: String
    let person: String
    let folder: URL
    let music: URL
    let covers: URL
    let database: DownloadDatabase

    /// The size covers are kept at: one size, drawn smaller wherever it is shown (8.1).
    static let coverSize = 1024

    init(server: String, person: String) throws {
        self.server = server
        self.person = person
        folder = Self.folder(server: server, person: person)
        music = folder.appendingPathComponent("music", isDirectory: true)
        covers = folder.appendingPathComponent("covers", isDirectory: true)
        let manager = FileManager.default
        for made in [folder, music, covers] {
            try manager.createDirectory(at: made, withIntermediateDirectories: true)
            Self.protect(made)
        }
        // the whole `downloads` folder off backups: else the music goes into iCloud backups
        Self.keepOffBackups(folder.deletingLastPathComponent())
        Self.keepOffBackups(folder)
        let path = folder.appendingPathComponent("downloads.sqlite").path
        database = try DownloadDatabase(path: path)
        for suffix in ["", "-wal", "-shm"] where manager.fileExists(atPath: path + suffix) {
            Self.protect(URL(fileURLWithPath: path + suffix))
        }
    }

    // MARK: where things are

    /// Application Support/deadwax.
    static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("deadwax", isDirectory: true)
    }

    /// Every person's downloads from `server`.
    static func accounts(server: String) -> URL {
        base.appendingPathComponent(KeptAlbumIndex.safeName(server), isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
    }

    static func folder(server: String, person: String) -> URL {
        accounts(server: server).appendingPathComponent(KeptAlbumIndex.safeName(person), isDirectory: true)
    }

    /// Where a finished task's file goes before its length is checked - from the task's name alone, so the delegate can
    /// move it before it returns (the system deletes it after), whoever is signed in now.
    static func partURL(for name: DownloadTaskName) -> URL? {
        guard let file = LocalFiles.name(songID: name.songID, suffix: name.suffix) else { return nil }
        return folder(server: name.server, person: name.person)
            .appendingPathComponent("music", isDirectory: true)
            .appendingPathComponent(file + ".part")
    }

    /// The song's copy, whether or not it is there.
    func fileURL(_ record: DownloadRecord) -> URL? {
        record.fileName.map { music.appendingPathComponent($0) }
    }

    func partURL(_ record: DownloadRecord) -> URL? {
        record.fileName.map { music.appendingPathComponent($0 + ".part") }
    }

    /// A cover's file name: its id made safe, the size, and the kind of image it is.
    static func coverName(_ coverID: String, data: Data) -> String {
        "\(KeptAlbumIndex.safeName(coverID))-\(coverSize).\(imageExtension(data))"
    }

    private static func imageExtension(_ data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.count >= 12, head[0...3] == [0x52, 0x49, 0x46, 0x46], head[8...11] == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }

    // MARK: files

    /// The length of the file at `url`, or nil when there is none.
    static func length(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Readable while the phone is locked after its first unlock - a locked phone opens the next song, and a background
    /// relaunch records a finished download. Set explicitly on each, so a change of default can't turn it off.
    static func protect(_ url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
    }

    static func keepOffBackups(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// The bytes of every file under `url`.
    static func bytes(under url: URL) -> Int64 {
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// The room the phone has for something the person asked for (iOS's "important usage" figure, which counts what
    /// it would clear to make room), or nil when iOS won't say.
    static func freeSpace() -> Int64? {
        let values = try? base.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Everything downloaded deleted - the songs, the albums, their covers - keeping the plays and the queue save
    /// waiting to be sent (they are the person's, not the downloads').
    func removeEverything() throws {
        try database.removeAll()
        let manager = FileManager.default
        for folder in [music, covers] {
            try? manager.removeItem(at: folder)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            Self.protect(folder)
        }
    }

    // MARK: other accounts

    /// The other people's downloads from `server` on this phone, with their bytes - You > Downloads' "Other accounts on
    /// this phone" (6.3), only those with something here.
    static func others(server: String, except person: String) -> [(folder: URL, bytes: Int64)] {
        let mine = KeptAlbumIndex.safeName(person)
        let all = (try? FileManager.default.contentsOfDirectory(at: accounts(server: server), includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent != mine }.compactMap { folder in
            let bytes = Self.bytes(under: folder.appendingPathComponent("music")) + Self.bytes(under: folder.appendingPathComponent("covers"))
            return bytes > 0 ? (folder, bytes) : nil
        }
    }

    /// Another person's downloads removed - their database emptied the way Remove All empties one, so the plays they made
    /// here are still theirs to send.
    static func removeOther(_ folder: URL) {
        let manager = FileManager.default
        if let database = try? DownloadDatabase(path: folder.appendingPathComponent("downloads.sqlite").path) {
            try? database.removeAll()
        }
        for name in ["music", "covers"] {
            let made = folder.appendingPathComponent(name, isDirectory: true)
            try? manager.removeItem(at: made)
            try? manager.createDirectory(at: made, withIntermediateDirectories: true)
            protect(made)
        }
    }

    /// Phase 0's own downloads (`deadwax/phase0`), deleted at 0.3's first launch and never made again.
    static func retirePhase0() {
        let old = base.appendingPathComponent("phase0", isDirectory: true)
        if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.removeItem(at: old) }
    }
}
