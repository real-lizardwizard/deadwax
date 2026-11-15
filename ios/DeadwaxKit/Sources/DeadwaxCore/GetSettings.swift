import Foundation

// You > Getting albums as kept on deadwax (GET and PUT /deadwax/me/preferences), and the Sources sheet's chips they start
// (Phase 6, slices 2 and 3): ui/src/lib/getSettings.ts - readGetSettings's three values and `can_save`, GET_MODES,
// QUALITY_FLOORS and FORMATS in You's words, floorFilters, sourceChips, candidateFilters and pressedCount - held to it by
// Fixtures/get/get-vectors.json; and app/useGetSettings.ts's `shown` - a choice laid over deadwax's last word while it is
// being saved - held by hand (GetTests), as it lives in a store the exporter can't compile.

/// "When I tap Get" (`GetMode`).
public enum GetMode: String, Sendable, CaseIterable {
    case sources, pick

    /// You's words for it (`GET_MODES`).
    public var label: String {
        switch self {
        case .sources: return "Show me the sources"
        case .pick: return "Pick the best source for me"
        }
    }
}

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

/// The Format a search is scored by (`FormatPreference`, src/matching.py score_format). `allCases` is the server's
/// order, the default first (FORMAT_PREFERENCE_VALUES); You lists them in `youOrder`.
public enum FormatPreference: String, Sendable, CaseIterable {
    case preferLossless = "prefer_lossless"
    case any
    case losslessOnly = "lossless_only"

    /// You's order (`FORMATS`, the main page's Settings -> Downloads order): Any, Prefer lossless, Lossless only.
    public static let youOrder: [FormatPreference] = [.any, .preferLossless, .losslessOnly]

    /// You's words for it (`FORMATS`).
    public var label: String {
        switch self {
        case .any: return "Any"
        case .preferLossless: return "Prefer lossless"
        case .losslessOnly: return "Lossless only"
        }
    }
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

    /// These with `choice` laid over them: what it names, the rest as they were (useGetSettings.ts `{ ...now, ...values }`).
    public func with(_ choice: GetChoice) -> GetSettings {
        GetSettings(mode: choice.mode ?? mode, floor: choice.floor ?? floor, format: choice.format ?? format)
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

/// What `/me/preferences` answers - to a read and to a save, which answers with all of them as they stand after it
/// (`GetSettingsAnswer`): the three, and whether deadwax can keep them at all (`can_save`: false when its database
/// isn't writable). Read leniently, as `readGetSettings` reads it: anything but `false` can be saved. The web's
/// `stored`, `seeded` and `unseeded` are its carrying-over of the old main page's settings in a browser - the phone never
/// had them, so it reads none and seeds nothing.
public struct GetSettingsAnswer: Decodable, Sendable, Equatable {
    public let settings: GetSettings
    public let canSave: Bool

    public init(settings: GetSettings, canSave: Bool = true) {
        self.settings = settings
        self.canSave = canSave
    }

    enum CodingKeys: String, CodingKey {
        case canSave = "can_save"
    }

    public init(from decoder: any Decoder) throws {
        settings = try GetSettings(from: decoder)
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        canSave = fields?.looseField(Bool.self, .canSave) != false
    }

    /// What You shows (useGetSettings.ts `shown`): deadwax's last word with every choice still being saved laid over
    /// it, in the order made - so an answer to an older save can't put a newer choice back. Nil while deadwax hasn't
    /// answered and nothing is being saved: nothing is shown as chosen then.
    public static func shown(_ confirmed: GetSettingsAnswer?, pending: [GetChoice]) -> GetSettingsAnswer? {
        if confirmed == nil && pending.isEmpty { return nil }
        let base = confirmed ?? GetSettingsAnswer(settings: .defaults, canSave: true)
        let laid = pending.reduce(base.settings) { (now: GetSettings, choice: GetChoice) -> GetSettings in now.with(choice) }
        return GetSettingsAnswer(settings: laid, canSave: base.canSave)
    }
}

/// One choice in You > Getting albums, as `PUT /me/preferences` takes it (src/routes/me.py `Preferences`, extra keys
/// refused): only what was chosen is sent - the rest are left as they are on deadwax.
public struct GetChoice: Encodable, Sendable, Equatable {
    public var mode: GetMode?
    public var floor: QualityFloor?
    public var format: FormatPreference?

    public init(mode: GetMode? = nil, floor: QualityFloor? = nil, format: FormatPreference? = nil) {
        self.mode = mode
        self.floor = floor
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case mode = "get_mode"
        case floor = "quality_floor"
        case format = "format_preference"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encodeIfPresent(mode?.rawValue, forKey: .mode)
        try fields.encodeIfPresent(floor?.rawValue, forKey: .floor)
        try fields.encodeIfPresent(format?.rawValue, forKey: .format)
    }
}

/// You > Getting albums' words (GettingChoices.tsx, You.tsx, useGetSettings.ts) - read out of their source by the
/// exporter and held here. The section's title is RequestWords.gettingAlbums, and its offline line the phone's own
/// StoreLine.offline ("Getting albums works once deadwax is back.").
public enum GettingWords {
    /// The three choices' titles.
    public static let modeTitle = "When I tap Get"
    public static let floorTitle = "Quality floor"
    public static let formatTitle = "Format"
    /// The note under the three (You.tsx `app-get-note`).
    public static let note = "\u{201C}Show me the sources\u{201D} lets you choose each download yourself. \u{201C}Pick the best source for me\u{201D} downloads the best match that meets your quality floor, and shows you the sources instead when nothing matches well, or when you already have the album or are getting it. The quality floor is also what the sources start filtered to. Format: Prefer lossless ranks lossless downloads higher, and Lossless only leaves out anything without a lossless file. All three are kept for you on deadwax, so they follow you to every device."
    /// deadwax's database won't keep them (`GETTING_UNSAVED`) - "Tell whoever runs deadwax." after it for anyone else.
    public static let unsaved = "deadwax can't keep these: its database isn't writable."
    /// The first read unanswered, and a choice deadwax wouldn't keep - each a lead before the error's words.
    public static let readFailed = "Couldn't get these from deadwax."
    public static let notSaved = "Not saved."

    /// The unsaved line, for whoever reads it.
    public static func unsavedLine(runsDeadwax: Bool) -> String {
        runsDeadwax ? unsaved : "\(unsaved) \(ErrorWords.tell)"
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
