import Foundation

// You > Getting albums as kept on deadwax (GET /deadwax/me/preferences), and the Sources sheet's chips they start
// (Phase 6, slice 2): ui/src/lib/getSettings.ts - readGetSettings's three values, floorFilters, sourceChips,
// candidateFilters and pressedCount - held to it by Fixtures/get/get-vectors.json. The phone reads the settings; changing
// them on the phone is slice 3's (PUT), as is "Pick the best source for me" - in slice 2 every Get shows the sources,
// whatever When I tap Get says (the web's default, the safe way round).

/// "When I tap Get" (`GetMode`).
public enum GetMode: String, Sendable, CaseIterable { case sources, pick }

/// What a source must at least be (`QualityFloor`).
public enum QualityFloor: String, Sendable, CaseIterable {
    case any
    case kbps320 = "320"
    case lossless
    case bit24 = "24bit"

    /// You's words for it (`QUALITY_FLOORS`).
    public var label: String {
        switch self {
        case .any: return "Any"
        case .kbps320: return "320 kbps"
        case .lossless: return "Lossless"
        case .bit24: return "24-bit"
        }
    }
}

/// The Format a search is scored by (`FormatPreference`, src/matching.py score_format).
public enum FormatPreference: String, Sendable, CaseIterable {
    case preferLossless = "prefer_lossless"
    case any
    case losslessOnly = "lossless_only"
}

/// You > Getting albums, read leniently (`readGetSettings`'s three values): anything it doesn't recognise is the
/// default - Show me the sources, Any, Prefer lossless.
public struct GetSettings: Decodable, Sendable, Equatable {
    public let mode: GetMode
    public let floor: QualityFloor
    public let format: FormatPreference

    public static let defaults = GetSettings(mode: .sources, floor: .any, format: .preferLossless)

    public init(mode: GetMode, floor: QualityFloor, format: FormatPreference) {
        self.mode = mode
        self.floor = floor
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case mode = "get_mode"
        case floor = "quality_floor"
        case format = "format_preference"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        mode = fields?.looseField(String.self, .mode).flatMap { GetMode(rawValue: $0) } ?? Self.defaults.mode
        floor = fields?.looseField(String.self, .floor).flatMap { QualityFloor(rawValue: $0) } ?? Self.defaults.floor
        format = fields?.looseField(String.self, .format).flatMap { FormatPreference(rawValue: $0) } ?? Self.defaults.format
    }

    // MARK: the Sources sheet's chips

    /// What the chips start as, for a Get: the quality floor, pressed (`floorFilters`).
    public static func floorFilters(_ floor: QualityFloor) -> SourceFilters {
        SourceFilters(lossless: floor == .lossless, bit24: floor == .bit24, kbps320: floor == .kbps320)
    }

    /// One chip: which filter, its words, and whether it is pressed.
    public struct Chip: Sendable, Equatable, Identifiable {
        public let key: SourceFilters.Key
        public let label: String
        public let on: Bool
        public var id: SourceFilters.Key { key }
    }

    /// The chips the sheet draws, in order, for a floor and what is pressed now (`sourceChips`): 320 kbps only while the
    /// floor is 320 or it is pressed, so that floor is never a filter on out of sight.
    public static func chips(_ floor: QualityFloor, _ filters: SourceFilters) -> [Chip] {
        var chips = [
            Chip(key: .lossless, label: "Lossless", on: filters.lossless),
            Chip(key: .bit24, label: "24-bit", on: filters.bit24),
            //? a free upload slot: the download starts at once
            Chip(key: .freeSlot, label: "Starts now", on: filters.freeSlot),
        ]
        if floor == .kbps320 || filters.kbps320 { chips.insert(Chip(key: .kbps320, label: "320 kbps", on: filters.kbps320), at: 2) }
        chips.append(Chip(key: .complete, label: "Complete albums only", on: filters.complete))
        return chips
    }

    /// The chips as the candidates' filters - what `Sources.passes`, the cards and the best match go by
    /// (`candidateFilters`, a phone's: no Signals chip, no sample-rate floor).
    public static func candidateFilters(_ filters: SourceFilters) -> CandidateFilters {
        CandidateFilters(freeSlotOnly: filters.freeSlot,
                         quality: QualityFilters(minBitrate: filters.kbps320 ? 320 : 0, minBitDepth: filters.bit24 ? 24 : 0),
                         lossless: filters.lossless, everyTrack: filters.complete)
    }

    /// How many chips are pressed - Clear filters shows only when some are (`pressedCount`).
    public static func pressedCount(_ filters: SourceFilters) -> Int {
        [filters.lossless, filters.bit24, filters.freeSlot, filters.kbps320, filters.complete].filter { $0 }.count
    }
}

/// The Sources sheet's chips (`SourceFilters`).
public struct SourceFilters: Sendable, Equatable {
    public enum Key: String, Sendable, CaseIterable { case lossless, bit24, freeSlot, kbps320, complete }

    public var lossless: Bool
    public var bit24: Bool
    public var freeSlot: Bool
    public var kbps320: Bool
    public var complete: Bool

    public static let none = SourceFilters()

    public init(lossless: Bool = false, bit24: Bool = false, freeSlot: Bool = false, kbps320: Bool = false,
                complete: Bool = false) {
        self.lossless = lossless
        self.bit24 = bit24
        self.freeSlot = freeSlot
        self.kbps320 = kbps320
        self.complete = complete
    }

    public subscript(key: Key) -> Bool {
        get {
            switch key {
            case .lossless: return lossless
            case .bit24: return bit24
            case .freeSlot: return freeSlot
            case .kbps320: return kbps320
            case .complete: return complete
            }
        }
        set {
            switch key {
            case .lossless: lossless = newValue
            case .bit24: bit24 = newValue
            case .freeSlot: freeSlot = newValue
            case .kbps320: kbps320 = newValue
            case .complete: complete = newValue
            }
        }
    }
}
