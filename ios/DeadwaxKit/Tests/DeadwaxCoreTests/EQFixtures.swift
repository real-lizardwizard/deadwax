import Foundation
@testable import DeadwaxCore

/// Fixtures/eq/: what ios/scripts/make-eq-fixtures.py writes (never by hand) - the cookbook, Equalizer APO's reading
/// rules, AutoEq's biquads, the GraphicEQ fit, the presets and a Direct Form I reference, each written out again in
/// Python (eq.md 5.1) - and the shapes they are read into. Exact numbers are Python's repr in strings, which
/// `Double(_:)` reads back to the same bits; arrays are base64 of little-endian float32 (`_f4`) or float64 (`_f8`).
enum EQFixtures {
    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Fixtures.data("eq/\(name)"))
    }

    static func filters() throws -> FiltersFile { try load(FiltersFile.self, "filters.json") }
    static func profiles() throws -> ProfilesFile { try load(ProfilesFile.self, "profiles.json") }
    static func graphic() throws -> GraphicFile { try load(GraphicFile.self, "graphic.json") }
    static func preamp() throws -> PreampFile { try load(PreampFile.self, "preamp.json") }
    static func render() throws -> RenderFile { try load(RenderFile.self, "render.json") }
    static func apo() throws -> APOFile { try load(APOFile.self, "apo.json") }

    /// A repr string as its Double, exactly.
    static func d(_ text: String) -> Double {
        guard let value = Double(text) else { fatalError("not a number: \(text)") }
        return value
    }

    static func floats(_ base64: String) -> [Float] {
        let data = Data(base64Encoded: base64)!
        return data.withUnsafeBytes { raw in
            (0..<(raw.count / 4)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    static func doubles(_ base64: String) -> [Double] {
        let data = Data(base64Encoded: base64)!
        return data.withUnsafeBytes { raw in
            (0..<(raw.count / 8)).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
        }
    }

    // ------------------------------------------------------------ shared shapes

    struct FilterJSON: Decodable {
        let id: Int
        let kind: String
        let written: String
        let fc: String
        let gain: String
        let width: [String: String]?
        let corner: Bool
        let channel: String
        let on: Bool

        var filter: EQFilter {
            var w: EQWidth?
            if let width, let (key, value) = width.first {
                switch key {
                case "q": w = .q(d(value))
                case "bandwidth": w = .bandwidth(d(value))
                default: w = .slope(d(value))
                }
            }
            return EQFilter(id: id, kind: EQKind(rawValue: kind)!, written: written, fc: d(fc), gain: d(gain), width: w,
                            corner: corner, channel: EQChannel(rawValue: channel)!, on: on)
        }
    }

    // ------------------------------------------------------------ filters.json

    struct FiltersFile: Decodable {
        let rates: [String]
        let cases: [FilterCase]
    }

    struct FilterCase: Decodable {
        let name: String
        let rate: String
        let filter: FilterJSON
        let outcome: String
        let f0: String?
        let coefficients: [String]?
        let response_f4: String?
        let impulse_f8: String?

        var coefficientsValue: EQCoefficients? {
            guard let c = coefficients?.map(d) else { return nil }
            return EQCoefficients(b0: c[0], b1: c[1], b2: c[2], a1: c[3], a2: c[4])
        }
    }

    // ------------------------------------------------------------ profiles.json

    struct ProfilesFile: Decodable {
        let gridCount: Int
        let profiles: [Profile]
    }

    struct Profile: Decodable {
        let path: String
        let measurer: String
        let rig: String?
        let form: String
        let csv: String?
        let filePreamp: String
        let filters: [FilterJSON]
        let peq44100_f4: String
        let peq48000_f4: String
        let top48000: String
        let topAt48000: String
        let automaticPreamp48000: String

        var name: String { "\(measurer): \(path.split(separator: "/").last!)" }
    }

    /// The profiles' grid: every 1/48 octave from 20 Hz to 20 kHz.
    static func profileGrid() -> [Double] {
        var out: [Double] = []
        var k = 0
        while 20 * pow(2.0, Double(k) / 48) <= 20000 {
            out.append(20 * pow(2.0, Double(k) / 48))
            k += 1
        }
        return out
    }

    // ------------------------------------------------------------ graphic.json

    struct GraphicFile: Decodable {
        let centres: [String]
        let q: String
        let gridCount: Int
        let fits: [GraphicFit]
    }

    struct GraphicFit: Decodable {
        let path: String
        let points: Int
        let median: String
        let target_f8: String
        let unrounded: [String]
        let rounded: [String]
        let kept: Int
        let rounds: Int
        let stats48000: [String: String]
        let stats44100: [String: String]
    }

    // ------------------------------------------------------------ preamp.json

    struct PreampFile: Decodable {
        let bandQ: String
        let presets: [PresetRow]
        let closePairs: [ClosePair]
    }

    struct PresetRow: Decodable {
        let id: String
        let gains: [String]
        let rate48000: PresetAtRate
        let rate44100: PresetAtRate
    }

    struct PresetAtRate: Decodable {
        let top: String
        let topAt: String
        let lowest: String
        let lowestAt: String
        let preamp: String
    }

    struct ClosePair: Decodable {
        let name: String
        let rate: String
        let filters: [FilterJSON]
        let trueTop: String
        let gridTop: String
    }

    // ------------------------------------------------------------ render.json

    struct RenderFile: Decodable {
        let rate: String
        let levels: [String]
        let lists: [[RenderSection]]
        let scenarios: [RenderScenario]
    }

    struct RenderSection: Decodable {
        let id: String
        let kind: String
        let coefficients: [String]

        var section: EQSection {
            let parts = id.split(separator: ":")
            let number = Int(parts[1])!
            let c = coefficients.map(d)
            return EQSection(id: parts[0] == "band" ? .band(number) : .filter(number), kind: EQKind(rawValue: kind)!,
                             f0: 0, coefficients: EQCoefficients(b0: c[0], b1: c[1], b2: c[2], a1: c[3], a2: c[4]))
        }
    }

    struct RenderScenario: Decodable {
        let name: String
        let frames: Int
        let channels: Int
        let input_f4: [String]
        let output_f4: [String]
        let overs: Int
        let largest: String
    }

    // ------------------------------------------------------------ apo.json

    struct APOFile: Decodable {
        let readings: [APOCase]
    }

    struct APOCase: Decodable {
        let name: String
        let file: String
        let transform: String
        let pasted: Bool
        let reading: APOReadingJSON
    }

    struct APOReadingJSON: Decodable {
        struct Refusal: Decodable {
            let kind: String
            let line: Int?
            let text: String
        }
        struct Graphic: Decodable {
            let channel: String
            let line: Int
            let points: [[String]]
        }
        struct Fit: Decodable {
            let ear: String
            let filters: Int
            let median: String
            let rounds: Int
            let mean: String
            let largest: String
            let above: String
            let aboveAt: String
        }
        struct Note: Decodable {
            let kind: String
            let first: Int?
            let last: Int?
            let text: String
        }
        let refused: Refusal?
        let filters: [FilterJSON]?
        let preamp: [String: String]?
        let graphic: [Graphic]?
        let fits: [Fit]?
        let notes: [Note]?
    }
}
