import Foundation
import Testing
@testable import DeadwaxCore

// What the Up Next tests share: the sims' generator, upnext.sim.cjs's songs, the fixtures' JSON, and words for a
// queue that read well in a failure.

/// Park-Miller, as ui/test/upnext.sim.cjs's seeded(): `s = s * 16807 % (2^31 - 1)`, `(s - 1) / 2147483646`. With
/// Int64 every step is exact (s * 16807 < 2^46), so it gives JavaScript's numbers bit for bit.
struct ParkMiller {
    private(set) var state: Int64

    init(_ seed: Int64) {
        precondition(seed >= 1 && seed < 2_147_483_647, "Park-Miller needs a seed in 1...2147483646")
        state = seed
    }

    mutating func int() -> Int64 {
        state = state * 16807 % 2_147_483_647
        return state
    }

    mutating func next() -> Double { Double(int() - 1) / 2_147_483_646 }
}

/// A seeded() to pass as `random`: a class, so a non-escaping closure can draw from it.
final class Seeded {
    var generator: ParkMiller
    init(_ seed: Int64) { generator = ParkMiller(seed) }
    func next() -> Double { generator.next() }
    func pick(_ count: Int) -> Int { Int((next() * Double(count)).rounded(.down)) }
}

/// upnext.sim.cjs's track(): Mezzanine's, unless told otherwise.
func simTrack(_ id: String, album: String = "Mezzanine", albumId: String? = "mez") -> QueueTrack {
    QueueTrack(id: id, title: "song \(id)", artist: "Massive Attack", album: album, albumId: albumId, coverArt: nil,
               duration: 200, contentType: "audio/flac", suffix: "flac", sampleRate: 44100, bitDepth: 16, channels: 2)
}

/// upnext.sim.cjs's album(n, prefix): songs "1"..."n".
func simAlbum(_ count: Int, _ prefix: String = "") -> [QueueTrack] {
    (0..<count).map { simTrack("\(prefix)\($0 + 1)") }
}

extension UpNextQueue {
    /// The ids, as the sim's ids().
    var ids: [String] { tracks.map(\.id) }
    /// The ids after the song playing, as the sim's after().
    var after: [String] { Array(tracks.dropFirst(index + 1)).map(\.id) }
    /// The marks after the song playing as the sim's froms(): "s0", "a", "o".
    var froms: [String] {
        (upNext?.marks.dropFirst(index + 1) ?? []).map { $0.from == .source ? "s\($0.pass)" : String($0.from.rawValue.prefix(1)) }
    }
    /// `{ ...queue, index }`, the engine moving.
    func at(_ index: Int) -> UpNextQueue {
        var moved = self
        moved.index = index
        return moved
    }
    /// The song after this one ending on its own: the next entry, copies included.
    var ended: UpNextQueue { at(Swift.min(index + 1, tracks.count - 1)) }
    /// The key of the nth entry after the song playing with this id (and from), or nil.
    func key(_ id: String, from: MarkFrom? = nil, nth: Int = 0) -> Int? {
        guard let marks = upNext?.marks else { return nil }
        let places = tracks.indices.filter { $0 > index && tracks[$0].id == id && (from == nil || marks[$0].from == from) }
        return places.count > nth ? marks[places[nth]].key : nil
    }
}

/// A JSON value as the fixtures hold it, read with JSONDecoder (the same on Linux as on a Mac).
enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    var int: Int? { if case .number(let n) = self, n == n.rounded() { return Int(n) }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var isNull: Bool { self == .null }
}

enum Fixtures {
    /// A fixture of this target's, by its path under Fixtures/ (copied into the test bundle whole).
    static func data(_ path: String) throws -> Data {
        let url = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures").appendingPathComponent(path),
                               "the test bundle has no resources")
        return try Data(contentsOf: url)
    }

    static func json(_ path: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data(path))
    }
}

/// A fixture's song, as export-traces.cjs wrote it.
func queueTrack(_ json: JSONValue) -> QueueTrack? {
    guard let id = json["id"]?.string, let title = json["title"]?.string, let artist = json["artist"]?.string,
          let album = json["album"]?.string else { return nil }
    return QueueTrack(id: id, title: title, artist: artist, album: album, albumId: json["albumId"]?.string,
                      coverArt: json["coverArt"]?.string, duration: json["duration"]?.double ?? 0,
                      contentType: json["contentType"]?.string, suffix: json["suffix"]?.string,
                      sampleRate: json["sampleRate"]?.int ?? 0, bitDepth: json["bitDepth"]?.int ?? 0,
                      channels: json["channels"]?.int ?? 0, level: json["level"]?.string.flatMap(Level.init(rawValue:)))
}

/// A fixture's Paged.
func paged(_ json: JSONValue) -> Paged? {
    guard let token = json["token"]?.string, let total = json["total"]?.int, let fetched = json["fetched"]?.int,
          let scope = json["scope"]?.string.flatMap(PagedScope.init(rawValue:)) else { return nil }
    return Paged(token: token, total: total, fetched: fetched, scope: scope, level: json["level"]?.string.flatMap(Level.init(rawValue:)))
}
