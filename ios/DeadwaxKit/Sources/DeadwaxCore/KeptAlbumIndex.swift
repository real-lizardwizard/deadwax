import Foundation

/// The last album_index answer of one (server, person, scope), kept across launches - the phone's own (D2; library.md
/// Open question 5: the web keeps nothing across a reload). The app writes it as each list lands and reads it back
/// before its first ask, so the Library draws at once and asks with its ETag (an unchanged list is a 304, one small
/// round trip); Phase 2's database replaces it.
///
/// What is decided here, so it is tested on Linux: where a list is kept (a folder per server, a file per person and
/// scope, every name made safe and kept apart), and which bytes may be drawn - only a record of this version, written
/// for exactly this server, person and scope. A kept `yours` never draws for another person, even where two names
/// come to one file (a disk that folds case or Unicode forms).
public struct KeptAlbumIndex: Codable, Sendable, Equatable {
    /// The record's shape; a record of another version is no list (and the app deletes it).
    public static let currentVersion = 1

    public let version: Int
    /// ServerAddress.key
    public let server: String
    /// /me's `user`
    public let user: String
    public let scope: AlbumScope
    /// the ETag the answer came with, exactly as received
    public let etag: String?
    /// when it landed, milliseconds since 1970
    public let at: Int64
    public let answer: AlbumIndexAnswer

    public init(server: String, user: String, scope: AlbumScope, etag: String?, at: Int64, answer: AlbumIndexAnswer) {
        version = Self.currentVersion
        self.server = server
        self.user = user
        self.scope = scope
        self.etag = etag
        self.at = at
        self.answer = answer
    }

    /// Whether this record may be drawn for `server`, `user` and `scope`: written by this version, for exactly them
    /// (compared as code units, as the names were sent).
    public func isFor(server: String, user: String, scope: AlbumScope) -> Bool {
        version == Self.currentVersion && self.scope == scope
            && self.server.utf16.elementsEqual(server.utf16) && self.user.utf16.elementsEqual(user.utf16)
    }

    /// The bytes to write.
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// A record read back for `server`, `user` and `scope` - nil for bytes that aren't one, or one that is anyone
    /// else's (`isFor`).
    public static func read(_ data: Data, server: String, user: String, scope: AlbumScope) -> KeptAlbumIndex? {
        guard let record = try? JSONDecoder().decode(KeptAlbumIndex.self, from: data),
              record.isFor(server: server, user: user, scope: scope) else { return nil }
        return record
    }

    // MARK: where it is kept

    /// The folder of a server's lists, inside the app's own: "<server>/album-index".
    public static func folder(server: String) -> [String] { [safeName(server), "album-index"] }

    /// A person's list of a scope: "user-<user>.<scope>.json".
    public static func fileName(user: String, scope: AlbumScope) -> String {
        "user-\(safeName(user)).\(scope.rawValue).json"
    }

    /// A name as a file name: ASCII letters and digits as they are, every other byte of its UTF-8 as `%XX` - so one
    /// name is one file name ("%" itself is "%25"), never with a "/", a "." or anything a file system reads twice.
    public static func safeName(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: out.unicodeScalars.append(Unicode.Scalar(byte))
            default: out += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
            }
        }
        return out
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
