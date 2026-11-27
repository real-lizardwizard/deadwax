import Foundation

/// (Speed A, fix 3 - notes/ios.md "Speed A: what's asked again") The library's scan as Edit album last read it
/// (`GET /library/albums?tracks=false`), kept on disk with its ETag - one per server, for the session it was read under -
/// so the first Edit of a launch asks with `If-None-Match` and an unchanged library is a 304 with no body, where it
/// downloaded every folder again.
///
/// Kept only for its ETag: the copy is drawn only once deadwax has said it is still the scan (a 304 to that ETag), so
/// managing never shows anything stale as live. It is read back only for exactly the server and session that wrote it
/// (the session by a digest, never the cookie itself): another person, or a sign-in again, never reads it.
///
/// The file is a line of JSON (the record's version, server, session digest and ETag) and then deadwax's body exactly as
/// it came, so it is read with the very decoder a fresh answer is (ScanAnswer's, the 304's headers laid on).
public struct ScanKept: Sendable, Equatable {
    /// The record's shape; a record of another version is no scan (and is replaced at the next read).
    public static let currentVersion = 1

    /// ServerAddress.key
    public let server: String
    /// The session's digest (`who`).
    public let who: String
    public let etag: String
    /// deadwax's answer, byte for byte.
    public let body: Data

    public init(server: String, session: String?, etag: String, body: Data) {
        self.server = server
        who = Self.who(session)
        self.etag = etag
        self.body = body
    }

    /// The session a scan was read under, as kept: a digest of the cookie (FNV-1a, the same on every run), never the
    /// cookie - "-" for none (logins off).
    public static func who(_ session: String?) -> String {
        guard let session, !session.isEmpty else { return "-" }
        return SessionFile.fnv1a(session)
    }

    private struct Head: Codable {
        let version: Int
        let server: String
        let who: String
        let etag: String
    }

    /// The bytes to write: the head's line, then the body.
    public func encoded() throws -> Data {
        var data = try JSONEncoder().encode(Head(version: Self.currentVersion, server: server, who: who, etag: etag))
        data.append(0x0A)
        data.append(body)
        return data
    }

    /// A record read back for `server` and `session` - nil for bytes that aren't one, of another version, or anyone
    /// else's (compared as code units, as the names were made).
    public static func read(_ data: Data, server: String, session: String?) -> ScanKept? {
        guard let newline = data.firstIndex(of: 0x0A),
              let head = try? JSONDecoder().decode(Head.self, from: data[data.startIndex..<newline]),
              head.version == currentVersion, !head.etag.isEmpty,
              head.server.utf16.elementsEqual(server.utf16), head.who.utf16.elementsEqual(who(session).utf16) else {
            return nil
        }
        return ScanKept(server: head.server, who: head.who, etag: head.etag,
                        body: Data(data[data.index(after: newline)...]))
    }

    private init(server: String, who: String, etag: String, body: Data) {
        self.server = server
        self.who = who
        self.etag = etag
        self.body = body
    }

    /// The scan kept, with the 304's headers laid on (when the disk was read, and whether it is stale - deadwax sends
    /// them on a 304 too) - nil when the body can't be read.
    public func answer(_ unchanged: HTTPResponse) -> ScanAnswer? {
        guard let answer = try? JSONDecoder().decode(ScanAnswer.self, from: body) else { return nil }
        return answer.with(headers: unchanged)
    }

    // MARK: where it is kept

    /// The folder of a server's scan, inside the app's Caches: "deadwax/<server>/library-scan".
    public static func folder(server: String) -> [String] { ["deadwax", KeptAlbumIndex.safeName(server), "library-scan"] }

    /// The one file in it: a server's scan is the last session's to read it.
    public static let fileName = "scan.kept"
}

/// (Speed A, fix 3) Where ScanKept's records are written and read, under `base` (the app's Caches, which the system may
/// empty and never backs up): a file per server, written whole then moved into place. A record that isn't for the server
/// and session asking is no scan, and the next fresh answer replaces whatever is there. Read and written off the main
/// actor by its caller.
public struct ScanFiles: Sendable {
    public let base: URL

    public init(base: URL) {
        self.base = base
    }

    /// The app's: in its Caches - nil when there are none.
    public static func inCaches() -> ScanFiles? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map { ScanFiles(base: $0) }
    }

    public func file(server: String) -> URL {
        ScanKept.folder(server: server).reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
            .appendingPathComponent(ScanKept.fileName, isDirectory: false)
    }

    /// The scan kept for `server` and `session`, or nil.
    public func read(server: String, session: String?) -> ScanKept? {
        let url = file(server: server)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ScanKept.read(data, server: server, session: session)
    }

    /// `kept` as its server's scan, in place of the one before.
    public func write(_ kept: ScanKept) {
        let url = file(server: kept.server)
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try kept.encoded().write(to: url, options: .atomic)
        } catch {
            // not kept: the next launch's first Edit asks without an ETag, as before
        }
    }
}

extension DeadwaxClient {
    /// The scan, as `libraryScan(ifNoneMatch:)` asks it, with what keeping it on disk needs: a fresh answer's body as it
    /// came, and a 304's own headers (deadwax's scan headers ride on it too).
    public enum ScanFetched: Sendable {
        case fresh(ScanAnswer, etag: String?, body: Data)
        case unchanged(HTTPResponse)
    }

    /// `GET /library/albums?tracks=false`, with `If-None-Match` when `etag` is one.
    public func libraryScanKeeping(ifNoneMatch etag: String?) async throws -> ScanFetched {
        var built = request(Routes.libraryAlbums, query: [("tracks", "false")])
        if let etag, !etag.isEmpty { built.headers["If-None-Match"] = etag }
        let response = try await answer(built, accept: built.headers["If-None-Match"] == nil ? [200] : [200, 304])
        if response.status == 304 { return .unchanged(response) }
        return .fresh(try decode(ScanAnswer.self, response).with(headers: response), etag: response.header("ETag"),
                      body: response.body)
    }
}
