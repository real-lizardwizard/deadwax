import Foundation

// The sign-in kept in a file, on the Mac (notes/ios.md "The Mac app, slice 1: it runs and plays"; the Mac app's plan,
// decision 2, James's of 17 Nov). On the iPhone deadwax's session cookie is kept in the Keychain (the App's
// SessionKeychain). On the Mac a Catalyst app's Keychain is the data protection keychain, whose access groups come from
// code-signing entitlements a provisioning profile must authorise (Apple's TN3137) - and the Mac build is signed with
// no profile, so that it never runs out after 7 days and takes none of a free account's three devices. So the Mac keeps
// the cookie here instead: one file per server, in a folder of the app's sandbox container, readable by this user
// alone, and removed at sign-out. The same three calls SessionKeychain has - read, save, delete - with the same
// outcomes: a save that fails keeps nothing for that server (the Keychain's deletes first), so the next launch asks the
// person to sign in rather than sending someone's old cookie.
//
// Never the password: the app doesn't keep it anywhere. Nothing here logs, and neither does anything that calls it.
// FileManager only, so it is built and tested on Linux.

/// deadwax's session cookie value, kept per server in a file: `<folder>/<name(server)>`, made 0600 in a folder 0700.
public struct SessionFile: Sendable, Equatable {
    /// The file's permissions: read and written by this user, nobody else.
    public static let permissions = 0o600
    /// The folder's: this user's alone.
    public static let folderPermissions = 0o700
    /// The longest name a server's file is given - well under a file system's 255 bytes, with room for the
    /// temporary name a save writes first.
    public static let longestName = 200

    /// Where the files are.
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The App's: `<Application Support>/deadwax/sessions` - beside the rest of what the app keeps per server
    /// (`deadwax/<server>/me.json`), inside the sandbox container on the Mac.
    public init(applicationSupport: URL) {
        folder = applicationSupport.appendingPathComponent("deadwax", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// A server's file name: the server (ServerAddress.key, the Keychain's account) as KeptAlbumIndex names a folder -
    /// ASCII letters and digits as they are, every other byte `%XX`, so it never holds a "/" or a "." and one server is
    /// one name. Past `longestName`, its start and a hash of the whole: still one name per server.
    public static func name(_ server: String) -> String {
        let safe = KeptAlbumIndex.safeName(server)
        guard safe.utf8.count > longestName else { return safe }
        return String(safe.prefix(longestName - 17)) + "-" + fnv1a(server)
    }

    /// The file `server`'s cookie is kept in. Never asked for an empty server: its name is empty, so this is the folder
    /// itself - which is why read, save and delete each refuse one first (a delete of it would take every session).
    public func url(_ server: String) -> URL {
        folder.appendingPathComponent(Self.name(server), isDirectory: false)
    }

    /// The cookie kept for `server`, or nil when there is none.
    public func read(_ server: String) -> String? {
        guard !server.isEmpty else { return nil }
        let manager = FileManager.default
        let path = url(server).path
        guard let attributes = try? manager.attributesOfItem(atPath: path), Self.isRegular(attributes),
              let data = manager.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Keeps `value` for `server`: written to a temporary file made 0600 while still empty, then put in the old one's
    /// place in one step (`place`), so the cookie is never in a file anyone else could read and there is no moment with
    /// no file. True when it was kept; on any failure, nothing is kept for `server` (the old file goes too). An empty
    /// server keeps nothing and touches nothing.
    @discardableResult
    public func save(_ value: String, for server: String) -> Bool {
        guard !server.isEmpty else { return false }
        let manager = FileManager.default
        let final = url(server)
        let temporary = folder.appendingPathComponent("." + Self.name(server) + ".new", isDirectory: false)
        guard makeFolder() else {
            delete(server)
            return false
        }
        try? manager.removeItem(at: temporary)
        let written: Bool = {
            guard manager.createFile(atPath: temporary.path, contents: nil,
                                     attributes: [.posixPermissions: Self.permissions]),
                  Self.ensure(Self.permissions, at: temporary.path),
                  let handle = try? FileHandle(forWritingTo: temporary) else { return false }
            defer { try? handle.close() }
            do {
                try handle.write(contentsOf: Data(value.utf8))
                try handle.synchronize()
                return true
            } catch {
                return false
            }
        }()
        guard written else {
            try? manager.removeItem(at: temporary)
            delete(server)
            return false
        }
        guard Self.place(temporary, at: final) else {
            try? manager.removeItem(at: temporary)
            delete(server)
            return false
        }
        return true
    }

    /// Forgets `server`'s cookie (signing out): its file, and a save's temporary one left by a stop midway. An empty
    /// server forgets nothing - its file would be the folder, and every server's session with it.
    public func delete(_ server: String) {
        guard !server.isEmpty else { return }
        let manager = FileManager.default
        try? manager.removeItem(at: url(server))
        try? manager.removeItem(at: folder.appendingPathComponent("." + Self.name(server) + ".new", isDirectory: false))
    }

    // MARK: -

    /// The folder made if it isn't there - its parent as any folder the app makes, itself 0700 - and held to 0700.
    private func makeFolder() -> Bool {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                     attributes: [.posixPermissions: Self.folderPermissions])
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { return false }
        return Self.ensure(Self.folderPermissions, at: folder.path)
    }

    /// The written file into `final`'s place. Over an old regular file, in one step (`replaceItemAt`, with the new
    /// file's own metadata - so its 0600, not the old file's mode): the old cookie is there until the new one is. Where
    /// there's none, moved in. Anything else of the name - a link, a folder - is taken away first and never written
    /// through (`attributesOfItem` reads the link, not what it points at). Then what is in place must be a regular
    /// file, 0600 - false otherwise.
    static func place(_ temporary: URL, at final: URL) -> Bool {
        let manager = FileManager.default
        let existing = try? manager.attributesOfItem(atPath: final.path)
        do {
            if let existing, isRegular(existing) {
                _ = try manager.replaceItemAt(final, withItemAt: temporary, backupItemName: nil,
                                              options: .usingNewMetadataOnly)
            } else {
                if existing != nil { try manager.removeItem(at: final) }
                try manager.moveItem(at: temporary, to: final)
            }
        } catch {
            return false
        }
        guard let placed = try? manager.attributesOfItem(atPath: final.path), isRegular(placed) else { return false }
        return ensure(permissions, at: final.path)
    }

    /// `path`'s permissions are `wanted`, set if they weren't - false when they can't be.
    static func ensure(_ wanted: Int, at path: String) -> Bool {
        if Self.mode(at: path) == wanted { return true }
        try? FileManager.default.setAttributes([.posixPermissions: wanted], ofItemAtPath: path)
        return Self.mode(at: path) == wanted
    }

    /// The permission bits of `path` (0o777 masked), nil when they can't be read.
    static func mode(at path: String) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let bits: Int?
        switch attributes[.posixPermissions] {
        case let value as Int: bits = value
        case let value as UInt16: bits = Int(value)
        case let value as Int16: bits = Int(value)
        case let value as UInt: bits = Int(value)
        case let value as UInt32: bits = Int(value)
        case let value as NSNumber: bits = value.intValue
        default: bits = nil
        }
        return bits.map { $0 & 0o777 }
    }

    static func isRegular(_ attributes: [FileAttributeKey: Any]) -> Bool {
        let type = attributes[.type]
        return (type as? FileAttributeType) == .typeRegular || (type as? String) == FileAttributeType.typeRegular.rawValue
    }

    /// FNV-1a, 64 bits, as 16 hex digits: the same for a text on every platform and every run.
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
