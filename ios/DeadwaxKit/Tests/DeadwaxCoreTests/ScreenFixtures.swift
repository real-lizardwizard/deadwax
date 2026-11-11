import Foundation
import Testing
@testable import DeadwaxCore

/// The screens' fixtures (Fixtures/screens), written by ios/scripts/export-screen-vectors.cjs from the web app's own
/// compiled TypeScript - never by hand - and read here as JSON values, since a case mixes kinds the way JavaScript's
/// arrays do. Numbers JSON can't hold come as strings: "NaN", "Infinity", "-Infinity", "-0".
indirect enum Web: Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Web])
    case object([String: Web])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let text = try? value.decode(String.self) { self = .string(text) }
        else if let list = try? value.decode([Web].self) { self = .array(list) }
        else { self = .object(try value.decode([String: Web].self)) }
    }

    static func load(_ name: String) throws -> Web {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/screens")
                               ?? Bundle.module.resourceURL?.appendingPathComponent("Fixtures/screens/\(name).json"),
                               "Fixtures/screens/\(name).json isn't in the test bundle")
        return try JSONDecoder().decode(Web.self, from: Data(contentsOf: url))
    }

    subscript(key: String) -> Web {
        if case .object(let fields) = self { return fields[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> Web {
        if case .array(let list) = self, list.indices.contains(index) { return list[index] }
        return .null
    }

    var isNull: Bool { if case .null = self { return true } else { return false } }
    var list: [Web] { if case .array(let list) = self { return list } else { return [] } }
    var string: String? { if case .string(let text) = self { return text } else { return nil } }
    var bool: Bool? { if case .bool(let flag) = self { return flag } else { return nil } }
    var keys: [String] { if case .object(let fields) = self { return Array(fields.keys) } else { return [] } }

    /// A number, the fixtures' strings for what JSON can't hold read back.
    var num: Double? {
        switch self {
        case .number(let number): return number
        case .string("NaN"): return .nan
        case .string("Infinity"): return .infinity
        case .string("-Infinity"): return -.infinity
        case .string("-0"): return -0.0
        default: return nil
        }
    }

    var int: Int? { num.flatMap { $0 == $0.rounded() && abs($0) < 1e15 ? Int($0) : nil } }

    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let flag): return String(flag)
        case .number(let number): return "\(number)"
        case .string(let text): return Screens.spelled(text)
        case .array(let list): return "[" + list.map(\.description).joined(separator: ", ") + "]"
        case .object(let fields): return "{" + fields.keys.sorted().map { "\($0): \(fields[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

enum Screens {
    /// Two numbers the same as JavaScript writes them out: NaN is NaN, and -0 isn't 0.
    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return (x.isNaN && y.isNaN) || (x == y && x.sign == y.sign)
        default: return false
        }
    }

    /// Strings the same as JavaScript compares them - every UTF-16 unit, not Swift's canonical equivalence.
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.utf16.elementsEqual(y.utf16)
        default: return false
        }
    }

    /// A string for a failure message, with its code points when it isn't plain ASCII.
    static func spelled(_ text: String?) -> String {
        guard let text else { return "nil" }
        if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f }) { return "\"\(text)\"" }
        return "\"\(text)\" [" + text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ") + "]"
    }
}

/// What differs, one line each - so a failure names its cases (by the sim's names where it has them), never dumps two
/// whole lists. Strings are compared as JavaScript does, numbers so that -0 and NaN count.
final class ScreenDiffs {
    private(set) var lines: [String] = []
    private(set) var checked = 0

    func text(_ label: @autoclosure () -> String, _ swift: String?, _ web: Web) {
        checked += 1
        let expected = web.isNull ? nil : web.string
        if web.isNull ? swift != nil : !Screens.same(swift, expected) {
            lines.append("\(label()): Swift \(Screens.spelled(swift)), the web \(web)")
        }
    }

    func number(_ label: @autoclosure () -> String, _ swift: Double?, _ web: Web) {
        checked += 1
        if !Screens.same(swift, web.num) { lines.append("\(label()): Swift \(swift.map { "\($0)" } ?? "nil"), the web \(web)") }
    }

    func flag(_ label: @autoclosure () -> String, _ swift: Bool?, _ web: Web) {
        checked += 1
        if swift != web.bool { lines.append("\(label()): Swift \(swift.map { "\($0)" } ?? "nil"), the web \(web)") }
    }

    func check<T: Equatable>(_ label: @autoclosure () -> String, _ swift: T, _ web: T) {
        checked += 1
        if swift != web { lines.append("\(label()): Swift \(swift), the web \(web)") }
    }

    var summary: String { "\(lines.count) of \(checked) differ: " + lines.prefix(8).joined(separator: " | ") }

    /// Nothing differs - and something was compared: a fixture list read under a wrong name is empty, not a pass.
    func done(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(checked > 0, "nothing was compared", sourceLocation: sourceLocation)
        #expect(lines.isEmpty, "\(summary)", sourceLocation: sourceLocation)
    }
}

/// An error as a fixture says it, made as the web makes it: deadwax's answer (`status`...), no answer (`offline`), no
/// answer in time (`timeout`), or another (`other`).
func screenFailure(_ spec: Web, path: String = "/auth/login", method: String = "POST") -> APIFailure {
    let server = try! ServerAddress.parse("192.168.3.20:8090").get()
    if let words = spec["offline"].string { return .offline(.init(server: server, method: method, path: path, reason: words)) }
    if let words = spec["timeout"].string { return .timeout(.init(server: server, method: method, path: path, reason: words)) }
    if let words = spec["other"].string { return .other(words) }
    return .answered(.init(status: spec["status"].int ?? 0, method: method, path: spec["path"].string ?? path,
                           detail: spec["detail"].string, why: spec["why"].string, kind: spec["kind"].string,
                           busy: spec["busy"].bool == true))
}

/// The made_from block names each source with its sha256 - so a fixture says which TypeScript it was made from.
func expectMadeFrom(_ fixture: Web, _ sources: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    let named = Set(fixture["made_from"].keys)
    for source in sources {
        #expect(named.contains(source), "made_from names \(source)", sourceLocation: sourceLocation)
        #expect(fixture["made_from"][source].string?.utf8.count == 64, "\(source)'s sha256", sourceLocation: sourceLocation)
    }
}
