import Foundation
import Testing
@testable import DeadwaxCore

/// Reading Fixtures/deck/, as ios/scripts/export-deck-vectors.cjs writes it: a double is a string of its IEEE bits in
/// hex, a space, then the number as JavaScript writes it ("3ff8000000000000 1.5") - the bits are what is compared;
/// long runs of doubles are base64 of their little-endian bytes. And the web's Math answers (maths.json), as a
/// RecordedMaths.
enum DeckFixtures {
    /// A fixture of the deck's, by its name under Fixtures/deck/.
    static func json(_ name: String) throws -> JSONValue {
        try Fixtures.json("deck/\(name)")
    }

    /// A double as the fixtures write it; nil for null.
    static func double(_ value: JSONValue?) -> Double? {
        guard let text = value?.string else { return nil }
        let hex = text.prefix(16)
        guard hex.count == 16, let bits = UInt64(hex, radix: 16) else { return nil }
        return Double(bitPattern: bits)
    }

    /// A double the fixture must hold - NaN, which no answer is, where it doesn't, so the comparison fails loudly.
    static func number(_ value: JSONValue?) -> Double {
        double(value) ?? .nan
    }

    /// Base64 of little-endian doubles.
    static func doubles(_ base64: String?) -> [Double] {
        guard let base64, let data = Data(base64Encoded: base64) else { return [] }
        var out: [Double] = []
        out.reserveCapacity(data.count / 8)
        data.withUnsafeBytes { raw in
            for i in stride(from: 0, to: raw.count - 7, by: 8) {
                out.append(Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: UInt64.self))))
            }
        }
        return out
    }

    /// A Float32's bits as the exporter writes them: any NaN as 0x7fc00000 (RecordedMaths.bits says why).
    static func bits(_ x: Float) -> UInt32 {
        x.isNaN ? 0x7FC0_0000 : x.bitPattern
    }

    /// The same double, bit for bit - NaN matching any NaN (an engine's NaN may carry another sign or payload, and
    /// nothing reads them).
    static func same(_ a: Double, _ b: Double) -> Bool {
        (a.isNaN && b.isNaN) || a.bitPattern == b.bitPattern
    }

    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return same(x, y)
        default: return false
        }
    }

    /// Every Math answer the web's runs evaluated (maths.json), read once.
    static let answers: [RecordedMaths.Call: UInt64] = {
        guard let maths = try? json("maths.json"), let table = maths["table"]?.object else { return [:] }
        var answers: [RecordedMaths.Call: UInt64] = [:]
        for function in DeckMathsFunction.allCases {
            let name = "\(function)"
            guard let entry = table[name], let data = entry["bits"]?.string.flatMap({ Data(base64Encoded: $0) }) else { continue }
            let arity = [.atan2, .hypot, .pow].contains(function) ? 2 : 1
            let width = (arity + 1) * 8
            data.withUnsafeBytes { raw in
                for at in stride(from: 0, to: raw.count - width + 1, by: width) {
                    func word(_ k: Int) -> UInt64 { UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: at + 8 * k, as: UInt64.self)) }
                    let call = arity == 2 ? RecordedMaths.Call(function, word(0), word(1)) : RecordedMaths.Call(function, word(0))
                    answers[call] = word(arity)
                }
            }
        }
        return answers
    }()

    /// A RecordedMaths answering as the web's runs did.
    static func maths() -> RecordedMaths {
        RecordedMaths(answers: answers)
    }

    /// The sha256 each fixture names its sources by, so a test's failure can say which fixture to make again.
    static func madeFrom(_ fixture: JSONValue) -> String {
        (fixture["made_from"]?.object?.keys.sorted() ?? []).joined(separator: ", ")
    }
}

@Suite struct DeckFixturesTests {
    @Test func theWebsMathsAreRead() throws {
        let maths = try DeckFixtures.json("maths.json")
        let calls = DeckMathsFunction.allCases.reduce(0) { $0 + (maths["table"]?["\($1)"]?["calls"]?.int ?? 0) }
        #expect(calls > 0)
        #expect(DeckFixtures.answers.count == calls)
    }

    @Test func aDoubleIsReadFromItsBits() {
        #expect(DeckFixtures.double(.string("3ff8000000000000 1.5")) == 1.5)
        #expect(DeckFixtures.double(.string("8000000000000000 -0"))?.sign == .minus)
        #expect(DeckFixtures.double(.null) == nil)
        #expect(DeckFixtures.doubles("AAAAAAAA+D8=") == [1.5])
    }

    /// A NaN's sign is the CPU's (x64's arithmetic makes 0xfff8000000000000): the fixtures write one NaN, and a call
    /// with a NaN is looked up, hashed and written by it here whichever NaN this machine made.
    @Test func everyNaNIsOne() {
        let negative = Double(bitPattern: 0xFFF8_0000_0000_0000)
        let quiet = Double(bitPattern: 0x7FF8_0000_0000_0000)
        let other = Double(bitPattern: 0x7FF0_0000_0000_0001)
        for nan in [negative, quiet, other, -Double.nan] {
            #expect(RecordedMaths.bits(nan) == 0x7FF8_0000_0000_0000)
            #expect(hex(nan) == "7ff8000000000000")
        }
        #expect(RecordedMaths.bits(-0.0) == 0x8000_0000_0000_0000)
        #expect(DeckFixtures.bits(Float(bitPattern: 0xFFC0_0000)) == 0x7FC0_0000)
        #expect(DeckFixtures.bits(Float(-1.5)) == Float(-1.5).bitPattern)
        let canonical = RecordedMaths.Call(.atan2, 0x7FF8_0000_0000_0000, 0x7FF8_0000_0000_0000)
        let one = RecordedMaths(answers: [canonical: 0x7FF8_0000_0000_0000])
        #expect(one.atan2(negative, other).isNaN && one.missed.isEmpty)
        let two = RecordedMaths(answers: [canonical: 0x7FF8_0000_0000_0000])
        _ = two.atan2(quiet, quiet)
        #expect(one.hash == two.hash)
    }
}
