import Foundation

/// The EQ as this phone keeps it (eq.md 4): `Application Support/deadwax/eq.json`, per output, never per person and
/// never on the server. Version 1; a version this build doesn't know, or a file it can't read, is set aside and the
/// phone starts with every output Off - never overwritten, never guessed at.
public struct EQSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Advanced's switch, for the whole phone (3.8)
    public var advanced: Bool
    /// your presets, shared by every output
    public var presets: [EQYourPreset]
    public var outputs: [EQOutputSetting]

    public init(version: Int = EQSettings.currentVersion, advanced: Bool = false, presets: [EQYourPreset] = [],
                outputs: [EQOutputSetting] = []) {
        self.version = version
        self.advanced = advanced
        self.presets = presets
        self.outputs = outputs
    }

    /// The file read: nil when it can't be, or is a version this build doesn't know.
    public static func read(_ data: Data) -> EQSettings? {
        struct Version: Decodable { let version: Int }
        guard let v = try? JSONDecoder().decode(Version.self, from: data), v.version == currentVersion else { return nil }
        return try? JSONDecoder().decode(EQSettings.self, from: data)
    }

    /// The file written (keys sorted, so a change shows as itself).
    public func written() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The name an unreadable file is set aside under, beside it: `eq-unreadable-2026-11-12.json`.
    public static func unreadableName(day: String) -> String { "eq-unreadable-\(day).json" }

    /// The same, when one is already set aside that day (slice 3, the store): the second `eq-unreadable-2026-11-12-2.json`
    /// and on - never one written over another.
    public static func unreadableName(day: String, attempt: Int) -> String {
        attempt <= 1 ? unreadableName(day: day) : "eq-unreadable-\(day)-\(attempt).json"
    }

    public func output(_ key: String) -> EQOutputSetting? { outputs.first { $0.key == key } }

    /// A tone's ten gains: a built-in's, yours (flat if it has gone), or Custom's own.
    public func gains(_ tone: EQTone) -> [Double] {
        switch tone {
        case .preset(let id): EQGraphic.preset(id)?.gains ?? EQGraphic.flat
        case .yours(let id): presets.first { $0.id == id }?.gains ?? EQGraphic.flat
        case .custom(let gains): gains
        }
    }

    /// An output's bank at a rate (1.6): its correction, its tone and its preamp - or the identity, Off.
    public func bank(_ output: EQOutputSetting, rate: Double, version: Int) -> EQBank {
        let preamp: Double?
        switch output.preamp {
        case .automatic: preamp = nil
        case .hand(let dB): preamp = dB
        }
        return EQBank.make(rate: rate, key: output.key, version: version, on: output.on,
                           correction: output.correction?.filters ?? [], offsets: output.correction?.preamp ?? .zero,
                           bands: gains(output.tone), preamp: preamp)
    }

    /// Deleting one of your presets leaves each output that uses it where its sliders were, as Custom (3.6).
    public mutating func deletePreset(_ id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        for i in outputs.indices where outputs[i].tone == .yours(id) { outputs[i].tone = .custom(preset.gains) }
        presets.removeAll { $0.id == id }
    }

    /// A preset's name as saved - trimmed, at most 40 characters - or why it can't be (3.6): none given, or one
    /// taken (case and accents folded, the built-ins included; the one being renamed aside).
    public func presetName(_ typed: String, renaming id: String? = nil) -> Result<String, EQNameProblem> {
        let name = String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.empty) }
        // Fold's NFKD less its marks, lower-cased: Fold.swift's own way, run on Linux by the Core suites, where
        // String.folding(options:locale:) is swift-corelibs-foundation's to answer
        func folded(_ s: String) -> String {
            String(String.UnicodeScalarView(s.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !Fold.isMark($0) }))
                .lowercased()
        }
        let taken = EQGraphic.presets.map(\.name) + presets.filter { $0.id != id }.map(\.name)
        if let other = taken.first(where: { folded($0) == folded(name) }) { return .failure(.taken(other)) }
        return .success(name)
    }

    /// A new output's setting (3.12): Off, no correction, the tone Flat, the preamp automatic.
    public static func newOutput(_ output: EQOutput, seen: String) -> EQOutputSetting {
        EQOutputSetting(key: output.key, type: output.port, uid: output.uid, name: output.name, renamed: nil, seen: seen,
                        suggestion: nil, on: false, correction: nil, tone: .preset("flat"), preamp: .automatic)
    }
}

public enum EQNameProblem: Error, Equatable, Sendable {
    case empty
    /// the name it clashes with, as written
    case taken(String)
}

/// One of your presets: a name and the ten sliders.
public struct EQYourPreset: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var gains: [Double]

    public init(id: String, name: String, gains: [Double]) {
        self.id = id
        self.name = name
        self.gains = gains
    }
}

/// One output's EQ (4).
public struct EQOutputSetting: Codable, Equatable, Sendable {
    public enum Suggestion: String, Codable, Sendable { case shown, notNow }

    public var key: String
    public var type: EQPort
    public var uid: String
    /// the name iOS gives it
    public var name: String
    /// yours, from Rename
    public var renamed: String?
    /// when it was last the output, ISO 8601 ("2026-11-12T10:41:00Z")
    public var seen: String
    public var suggestion: Suggestion?
    public var on: Bool
    public var correction: EQCorrection?
    public var tone: EQTone
    public var preamp: EQPreampSetting

    public init(key: String, type: EQPort, uid: String, name: String, renamed: String?, seen: String,
                suggestion: Suggestion?, on: Bool, correction: EQCorrection?, tone: EQTone, preamp: EQPreampSetting) {
        self.key = key
        self.type = type
        self.uid = uid
        self.name = name
        self.renamed = renamed
        self.seen = seen
        self.suggestion = suggestion
        self.on = on
        self.correction = correction
        self.tone = tone
        self.preamp = preamp
    }

    /// What it is called everywhere: yours, else iOS's.
    public var shownName: String { renamed ?? name }
}

/// A correction (4): from AutoEq, from a file, or built from your own filters - its source kept (the text, so "Back
/// to AutoEq's" works), and the filters that play, each with its own id from the correction's counter.
public struct EQCorrection: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case autoeq, file, built }

    public var kind: Kind
    /// AutoEq's profile id
    public var id: String?
    /// the headphone's name (AutoEq), or the file's name
    public var name: String
    /// who measured it (AutoEq)
    public var source: String?
    public var rig: String?
    public var form: String?
    /// the file's text or AutoEq's ParametricEQ.txt
    public var text: String?
    /// an AutoEq correction edited since
    public var changed: Bool
    /// a GraphicEQ, converted (3.10)
    public var converted: Bool
    /// the file's own preamp parts: its shared part, and each ear's offset
    public var preamp: EQPreampParts
    public var nextFilterID: Int
    public var filters: [EQFilter]

    public init(kind: Kind, id: String? = nil, name: String, source: String? = nil, rig: String? = nil,
                form: String? = nil, text: String? = nil, changed: Bool = false, converted: Bool = false,
                preamp: EQPreampParts = .zero, nextFilterID: Int, filters: [EQFilter]) {
        self.kind = kind
        self.id = id
        self.name = name
        self.source = source
        self.rig = rig
        self.form = form
        self.text = text
        self.changed = changed
        self.converted = converted
        self.preamp = preamp
        self.nextFilterID = nextFilterID
        self.filters = filters
    }

    /// A file read (3.9), kept with its name and text: its filters numbered from 1, its counter after them.
    public static func file(name: String, text: String, reading: APOReading) -> EQCorrection {
        EQCorrection(kind: .file, name: name, text: text, converted: !reading.fits.isEmpty, preamp: reading.preamp,
                     nextFilterID: reading.nextFilterID, filters: reading.filters)
    }

    /// An AutoEq profile's ParametricEQ.txt, read.
    public static func autoeq(id: String, name: String, source: String, rig: String?, form: String?, text: String,
                              reading: APOReading) -> EQCorrection {
        EQCorrection(kind: .autoeq, id: id, name: name, source: source, rig: rig, form: form, text: text,
                     preamp: reading.preamp, nextFilterID: reading.nextFilterID, filters: reading.filters)
    }

    private enum Keys: String, CodingKey {
        case kind, id, name, source, rig, form, text, changed, converted, preamp, nextFilterID, filters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        rig = try c.decodeIfPresent(String.self, forKey: .rig)
        form = try c.decodeIfPresent(String.self, forKey: .form)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        changed = try c.decodeIfPresent(Bool.self, forKey: .changed) ?? false
        converted = try c.decodeIfPresent(Bool.self, forKey: .converted) ?? false
        preamp = try c.decodeIfPresent(EQPreampParts.self, forKey: .preamp) ?? .zero
        nextFilterID = try c.decode(Int.self, forKey: .nextFilterID)
        filters = try c.decode([EQFilter].self, forKey: .filters)
    }
}

/// The tone (4): a built-in preset, one of yours, or Custom's ten gains.
public enum EQTone: Codable, Equatable, Sendable {
    case preset(String)
    case yours(String)
    case custom([Double])

    private enum Keys: String, CodingKey { case preset, yours, custom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .preset) {
            self = .preset(id)
        } else if let id = try c.decodeIfPresent(String.self, forKey: .yours) {
            self = .yours(id)
        } else {
            self = .custom(try c.decode([Double].self, forKey: .custom))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .preset(let id): try c.encode(id, forKey: .preset)
        case .yours(let id): try c.encode(id, forKey: .yours)
        case .custom(let gains): try c.encode(gains, forKey: .custom)
        }
    }
}

/// The preamp (4): deadwax's automatic one, or yours (-30 to +12 dB, 3.8).
public enum EQPreampSetting: Codable, Equatable, Sendable {
    case automatic
    case hand(Double)

    private enum Keys: String, CodingKey {
        case automatic
        case dB
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if try c.decode(Bool.self, forKey: .automatic) {
            self = .automatic
        } else {
            self = .hand(try c.decode(Double.self, forKey: .dB))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .automatic:
            try c.encode(true, forKey: .automatic)
        case .hand(let dB):
            try c.encode(false, forKey: .automatic)
            try c.encode(dB, forKey: .dB)
        }
    }
}
