import Foundation

// The Sources sheet (Phase 6, slice 2 - notes/ios-specs/phase6-get-requests.md 2.10): what POST
// /deadwax/download/find_candidates answers, and the web's rules and words for it - ui/src/lib/candidates.ts (the
// filters, the sort, a card's facts and reasoning, every state's line, the announcement) and perPerson.ts's
// candidateQuality - ported to the character and held to them by Fixtures/get/get-vectors.json (GetVectorTests). What a
// card's Get sends is `EnqueueBody`: the folder, the release it was searched for, its quality, and up to ten runners-up
// as SHOWN (useCandidateSearch.ts, ported by hand - a hook the exporter can't compile).

/// A file of a folder found (`CandidateFile`): what slskd is asked for.
public struct CandidateFile: Codable, Sendable, Equatable, Hashable {
    public let filename: String
    public let size: Double

    public init(filename: String, size: Double) {
        self.filename = filename
        self.size = size
    }

    enum CodingKeys: String, CodingKey { case filename, size }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        filename = fields.looseField(String.self, .filename) ?? ""
        size = fields.looseField(Double.self, .size) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(filename, forKey: .filename)
        try GetRelease.encodeNumber(size, &fields, .size)
    }
}

/// A track of the pressing nothing in the folder was paired with (`MissingTrack`).
public struct MissingTrack: Decodable, Sendable, Equatable, Hashable {
    public let position: Int?
    public let disc: Int?
    public let title: String

    public init(position: Int? = nil, disc: Int? = nil, title: String = "") {
        self.position = position
        self.disc = disc
        self.title = title
    }

    enum CodingKeys: String, CodingKey { case position, disc, title }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        position = fields.looseField(Int.self, .position)
        disc = fields.looseField(Int.self, .disc)
        title = fields.looseField(String.self, .title) ?? ""
    }
}

/// One folder a peer shares that may be the pressing (`Candidate`, routes/download.py `_serialize_candidate`) - a source,
/// as the app says it.
public struct Candidate: Decodable, Sendable, Equatable, Identifiable {
    public let username: String
    public let directory: String
    public let directoryName: String
    /// 0-1.
    public let score: Double
    /// Each signal the score was judged on, 0-1 - one that couldn't be judged (null) is left out.
    public let signals: [String: Double]
    public let matchedTracks: Int
    public let expectedTracks: Int
    public let audioFileCount: Int
    public let detectedEditionTags: [String]
    /// The peer's folder for each disc, for a set shared one folder per disc.
    public let discFolders: [String]
    public let formats: [String]
    /// The peer's own average upload rate, bytes a second - never the download speed.
    public let uploadSpeed: Double
    /// What deadwax measured from this peer before, bytes a second.
    public let measuredSpeed: Double?
    public let measuredSamples: Double?
    public let queueLength: Double
    public let hasFreeSlot: Bool
    public let totalSize: Double
    public let bitrates: [Double]
    public let bitDepths: [Double]
    public let sampleRates: [Double]
    public let variableBitrate: Bool
    public let missingTracks: [MissingTrack]?
    public let missingCount: Int?
    public let audioExpected: Double?
    public let files: [CandidateFile]

    /// `candidateKey`: a peer's folder.
    public var id: String { Sources.key(self) }

    public init(username: String, directory: String = "", directoryName: String = "", score: Double,
                signals: [String: Double] = [:], matchedTracks: Int = 0, expectedTracks: Int = 0, audioFileCount: Int = 0,
                detectedEditionTags: [String] = [], discFolders: [String] = [], formats: [String] = [],
                uploadSpeed: Double = 0, measuredSpeed: Double? = nil, measuredSamples: Double? = nil,
                queueLength: Double = 0, hasFreeSlot: Bool = false, totalSize: Double = 0, bitrates: [Double] = [],
                bitDepths: [Double] = [], sampleRates: [Double] = [], variableBitrate: Bool = false,
                missingTracks: [MissingTrack]? = nil, missingCount: Int? = nil, audioExpected: Double? = nil,
                files: [CandidateFile] = []) {
        self.username = username
        self.directory = directory
        self.directoryName = directoryName
        self.score = score
        self.signals = signals
        self.matchedTracks = matchedTracks
        self.expectedTracks = expectedTracks
        self.audioFileCount = audioFileCount
        self.detectedEditionTags = detectedEditionTags
        self.discFolders = discFolders
        self.formats = formats
        self.uploadSpeed = uploadSpeed
        self.measuredSpeed = measuredSpeed
        self.measuredSamples = measuredSamples
        self.queueLength = queueLength
        self.hasFreeSlot = hasFreeSlot
        self.totalSize = totalSize
        self.bitrates = bitrates
        self.bitDepths = bitDepths
        self.sampleRates = sampleRates
        self.variableBitrate = variableBitrate
        self.missingTracks = missingTracks
        self.missingCount = missingCount
        self.audioExpected = audioExpected
        self.files = files
    }

    enum CodingKeys: String, CodingKey {
        case username, directory, score, signals, formats, bitrates, files
        case directoryName = "directory_name"
        case matchedTracks = "matched_tracks"
        case expectedTracks = "expected_tracks"
        case audioFileCount = "audio_file_count"
        case detectedEditionTags = "detected_edition_tags"
        case discFolders = "disc_folders"
        case uploadSpeed = "upload_speed"
        case measuredSpeed = "measured_speed"
        case measuredSamples = "measured_samples"
        case queueLength = "queue_length"
        case hasFreeSlot = "has_free_slot"
        case totalSize = "total_size"
        case bitDepths = "bit_depths"
        case sampleRates = "sample_rates"
        case variableBitrate = "variable_bitrate"
        case missingTracks = "missing_tracks"
        case missingCount = "missing_count"
        case audioExpected = "audio_expected"
    }

    /// The signals object, any keys: a number kept, anything else (null - not judged) left out.
    private struct Signals: Decodable {
        let values: [String: Double]

        struct Key: CodingKey {
            let stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: Key.self)
            var values: [String: Double] = [:]
            for key in fields.allKeys {
                if let value = try? fields.decode(Double.self, forKey: key), value.isFinite { values[key.stringValue] = value }
            }
            self.values = values
        }
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        username = fields.looseField(String.self, .username) ?? ""
        directory = fields.looseField(String.self, .directory) ?? ""
        directoryName = fields.looseField(String.self, .directoryName) ?? ""
        score = fields.looseField(Double.self, .score) ?? 0
        signals = fields.looseField(Signals.self, .signals)?.values ?? [:]
        matchedTracks = fields.looseField(Int.self, .matchedTracks) ?? 0
        expectedTracks = fields.looseField(Int.self, .expectedTracks) ?? 0
        audioFileCount = fields.looseField(Int.self, .audioFileCount) ?? 0
        detectedEditionTags = fields.looseList(String.self, .detectedEditionTags) ?? []
        discFolders = fields.looseList(String.self, .discFolders) ?? []
        formats = fields.looseList(String.self, .formats) ?? []
        uploadSpeed = fields.looseField(Double.self, .uploadSpeed) ?? 0
        measuredSpeed = fields.looseField(Double.self, .measuredSpeed)
        measuredSamples = fields.looseField(Double.self, .measuredSamples)
        queueLength = fields.looseField(Double.self, .queueLength) ?? 0
        hasFreeSlot = fields.looseField(Bool.self, .hasFreeSlot) ?? false
        totalSize = fields.looseField(Double.self, .totalSize) ?? 0
        bitrates = fields.looseList(Double.self, .bitrates) ?? []
        bitDepths = fields.looseList(Double.self, .bitDepths) ?? []
        sampleRates = fields.looseList(Double.self, .sampleRates) ?? []
        variableBitrate = fields.looseField(Bool.self, .variableBitrate) ?? false
        missingTracks = fields.looseList(MissingTrack.self, .missingTracks)
        missingCount = fields.looseField(Int.self, .missingCount)
        audioExpected = fields.looseField(Double.self, .audioExpected)
        files = fields.looseList(CandidateFile.self, .files) ?? []
    }
}

/// `POST /deadwax/download/find_candidates`: the queries searched, how many peers answered, the folders found (best
/// match first) - and the store's four fields (`StoreStateAnswer`).
public struct FindCandidatesAnswer: Decodable, Sendable, Equatable {
    public let query: String
    public let queries: [String]?
    public let responseCount: Int
    public let candidates: [Candidate]
    public let store: StoreStateAnswer

    public init(query: String, queries: [String]? = nil, responseCount: Int = 0, candidates: [Candidate] = [],
                store: StoreStateAnswer = StoreStateAnswer()) {
        self.query = query
        self.queries = queries
        self.responseCount = responseCount
        self.candidates = candidates
        self.store = store
    }

    enum CodingKeys: String, CodingKey {
        case query, queries, candidates
        case responseCount = "response_count"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        query = fields.looseField(String.self, .query) ?? ""
        queries = fields.looseList(String.self, .queries)
        responseCount = fields.looseField(Int.self, .responseCount) ?? 0
        candidates = fields.looseList(Candidate.self, .candidates) ?? []
        store = try StoreStateAnswer(from: decoder)
    }
}

/// `POST /deadwax/download/enqueue`'s answer: the job asked for - or, joined (logins on: somebody else's download of
/// the same pressing), that one.
public struct EnqueueAnswer: Decodable, Sendable, Equatable {
    public let status: String
    public let queued: Int
    public let jobId: Int?
    public let joined: Bool

    public init(status: String = "", queued: Int = 0, jobId: Int?, joined: Bool = false) {
        self.status = status
        self.queued = queued
        self.jobId = jobId
        self.joined = joined
    }

    enum CodingKeys: String, CodingKey {
        case status, queued, joined
        case jobId = "job_id"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        status = fields.looseField(String.self, .status) ?? ""
        queued = fields.looseField(Int.self, .queued) ?? 0
        jobId = fields.looseField(Int.self, .jobId)
        joined = fields.looseField(Bool.self, .joined) ?? false
    }
}

/// What a Join answers (`POST /download/jobs/{job_id}/join`, slice 3): the download, and whether this was news -
/// `joined` false when you were already waiting for it. Read leniently.
public struct JoinAnswer: Decodable, Sendable, Equatable {
    public let status: String
    public let jobId: Int?
    public let joined: Bool

    public init(status: String = "ok", jobId: Int?, joined: Bool) {
        self.status = status
        self.jobId = jobId
        self.joined = joined
    }

    enum CodingKeys: String, CodingKey {
        case status, joined
        case jobId = "job_id"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        status = fields.looseField(String.self, .status) ?? ""
        jobId = fields.looseField(Int.self, .jobId)
        joined = fields.looseField(Bool.self, .joined) ?? false
    }
}

/// What a folder's files are, as its card showed them (`JobQuality`, routes/download.py Quality): kept with the job, so
/// someone offered to join it is told what they'd get.
public struct JobQuality: Encodable, Sendable, Equatable {
    public let formats: [String]
    public let bitrates: [Double]
    public let bitDepths: [Double]
    public let sampleRates: [Double]
    public let variableBitrate: Bool

    enum CodingKeys: String, CodingKey {
        case formats, bitrates
        case bitDepths = "bit_depths"
        case sampleRates = "sample_rates"
        case variableBitrate = "variable_bitrate"
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(formats, forKey: .formats)
        try fields.encode(bitrates.map(JSONWhole.init), forKey: .bitrates)
        try fields.encode(bitDepths.map(JSONWhole.init), forKey: .bitDepths)
        try fields.encode(sampleRates.map(JSONWhole.init), forKey: .sampleRates)
        try fields.encode(variableBitrate, forKey: .variableBitrate)
    }
}

/// A number written as JavaScript's JSON writes it: a whole one without a fraction.
struct JSONWhole: Encodable {
    let value: Double

    init(_ value: Double) { self.value = value }

    func encode(to encoder: any Encoder) throws {
        var one = encoder.singleValueContainer()
        if value.isFinite, value == value.rounded(.towardZero), abs(value) < 9_007_199_254_740_992 {
            try one.encode(Int64(value))
        } else {
            try one.encode(value)
        }
    }
}

/// What a Get searches with (`find_candidates`' body): the release, and the Format and an edited query
/// (useCandidateSearch.ts `{ ...release, query_override, format_preference }`) - flat, as the server declares them.
public struct FindCandidatesBody: Encodable, Sendable, Equatable {
    public let release: GetRelease
    public let format: FormatPreference
    /// "" for the search as deadwax builds it; an edited query otherwise (`Sources.queryOverride`).
    public let queryOverride: String

    public init(release: GetRelease, format: FormatPreference, queryOverride: String = "") {
        self.release = release
        self.format = format
        self.queryOverride = queryOverride
    }

    enum CodingKeys: String, CodingKey {
        case format = "format_preference"
        case queryOverride = "query_override"
    }

    public func encode(to encoder: any Encoder) throws {
        try release.encode(to: encoder)
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(queryOverride, forKey: .queryOverride)
        try fields.encode(format.rawValue, forKey: .format)
    }
}

/// A card's Get (`enqueue`'s body, useCandidateSearch.ts `ask`): the folder, the release it was SEARCHED for, the rest of
/// the list as shown for "next peer", and what the copy is.
public struct EnqueueBody: Encodable, Sendable, Equatable {
    /// A runner-up: somewhere else the same album could come from.
    public struct Alternative: Encodable, Sendable, Equatable {
        public let username: String
        public let directory: String
        public let files: [CandidateFile]
        public let score: Double
        public let quality: JobQuality
    }

    public let username: String
    public let files: [CandidateFile]
    public let directory: String
    public let release: GetRelease
    public let alternatives: [Alternative]
    public let quality: JobQuality

    /// `candidate` from a search for `release`, with `shown` - the list as the chips and the sort show it - for its
    /// runners-up: every other card, in order, the first ten.
    public init(candidate: Candidate, release: GetRelease, shown: [Candidate]) {
        let key = Sources.key(candidate)
        username = candidate.username
        files = candidate.files
        directory = candidate.directory
        self.release = release
        alternatives = shown.filter { !WebText.same(Sources.key($0), key) }.prefix(10).map {
            Alternative(username: $0.username, directory: $0.directory, files: $0.files, score: $0.score,
                        quality: Sources.quality($0))
        }
        quality = Sources.quality(candidate)
    }
}

/// The candidates' filters (`CandidateFilters`) - the phone's chips set the few its sheet draws.
public struct CandidateFilters: Sendable, Equatable {
    public var freeSlotOnly: Bool
    /// The main page's own Complete albums only, against every track - the app's is `everyTrack`.
    public var completeOnly: Bool
    /// 0-100, against the score as a percentage.
    public var minScore: Double
    /// Empty means every format.
    public var formats: Set<String>
    /// Per-signal minimums, 0-100; 0 is off.
    public var minSignals: [String: Double]
    public var quality: QualityFilters
    public var lossless: Bool
    public var everyTrack: Bool

    public init(freeSlotOnly: Bool = false, completeOnly: Bool = false, minScore: Double = 0, formats: Set<String> = [],
                minSignals: [String: Double] = [:], quality: QualityFilters = QualityFilters(), lossless: Bool = false,
                everyTrack: Bool = false) {
        self.freeSlotOnly = freeSlotOnly
        self.completeOnly = completeOnly
        self.minScore = minScore
        self.formats = formats
        self.minSignals = minSignals
        self.quality = quality
        self.lossless = lossless
        self.everyTrack = everyTrack
    }
}

/// What the files must be at least, judged against the folder's WORST file (`QualityFilters`); 0 is off.
public struct QualityFilters: Sendable, Equatable {
    public var minBitrate: Double
    public var minBitDepth: Double
    public var minSampleRate: Double
    public var minSizeMb: Double
    public var maxSizeMb: Double

    public init(minBitrate: Double = 0, minBitDepth: Double = 0, minSampleRate: Double = 0, minSizeMb: Double = 0,
                maxSizeMb: Double = 0) {
        self.minBitrate = minBitrate
        self.minBitDepth = minBitDepth
        self.minSampleRate = minSampleRate
        self.minSizeMb = minSizeMb
        self.maxSizeMb = maxSizeMb
    }
}

/// The sort's four orders (`CandidateSort`), in the order the menu lists them.
public enum CandidateSort: String, Sendable, CaseIterable, Identifiable {
    case score
    case quality
    case sizeDesc = "size_desc"
    case sizeAsc = "size_asc"

    public var id: String { rawValue }

    /// `SORT_LABELS`.
    public var label: String {
        switch self {
        case .score: return "Best match"
        case .quality: return "Highest quality"
        case .sizeDesc: return "Largest first"
        case .sizeAsc: return "Smallest first"
        }
    }
}

/// The candidates' rules and words (candidates.ts).
public enum Sources {
    /// The six signals, in the order the reasoning lists them, with their words and what each measures
    /// (`SIGNAL_LABELS`, `SIGNAL_MEANINGS`).
    public static let signals: [(signal: String, label: String, meaning: String)] = [
        ("title_match", "track names", "the pressing's tracks it has, found by their names"),
        ("track_count", "track count", "how near its number of files is to the pressing's tracks"),
        ("duration_match", "track lengths", "the tracks found whose length is right, to within 8 seconds"),
        ("edition", "edition", "whether its name says the same edition (deluxe, remaster…) - its year there helps"),
        ("format", "format", "lossless or not, as your Format asks"),
        ("peer", "availability", "how soon it can start: a free slot, a short queue, their speed"),
    ]

    public static let losslessFormats: Set<String> = ["flac", "alac", "ape", "wav", "aiff", "aif", "wv"]

    /// `candidateKey`: a candidate's identity within one result - a peer's folder.
    public static func key(_ candidate: Candidate) -> String { "\(candidate.username)\n\(candidate.directory)" }

    static func allLossless(_ candidate: Candidate) -> Bool {
        !candidate.formats.isEmpty && candidate.formats.allSatisfy { losslessFormats.contains($0) }
    }

    /// Every track of the pressing present, as a card counts its Tracks (`everyTrackPresent`).
    public static func everyTrackPresent(_ candidate: Candidate) -> Bool {
        if candidate.expectedTracks == 0 { return true }
        guard let audio = candidate.audioExpected, audio > 0 else { return candidate.matchedTracks >= candidate.expectedTracks }
        return max(candidate.missingCount ?? 0, candidate.missingTracks?.count ?? 0) == 0
    }

    static let mb = 1024.0 * 1024.0

    /// `passesQuality`: judged on the worst file; a lossless folder with no reported bitrate passes a bitrate minimum.
    public static func passesQuality(_ candidate: Candidate, _ quality: QualityFilters) -> Bool {
        if quality.minBitrate != 0 {
            if let worst = candidate.bitrates.min() {
                if worst < quality.minBitrate { return false }
            } else if !allLossless(candidate) {
                return false
            }
        }
        if quality.minBitDepth != 0 {
            guard let worst = candidate.bitDepths.min(), worst >= quality.minBitDepth else { return false }
        }
        if quality.minSampleRate != 0 {
            guard let worst = candidate.sampleRates.min(), worst >= quality.minSampleRate else { return false }
        }
        if quality.minSizeMb != 0 && candidate.totalSize < quality.minSizeMb * mb { return false }
        if quality.maxSizeMb != 0 && candidate.totalSize > quality.maxSizeMb * mb { return false }
        return true
    }

    /// `passesFilters`.
    public static func passes(_ candidate: Candidate, _ filters: CandidateFilters) -> Bool {
        if filters.freeSlotOnly && !candidate.hasFreeSlot { return false }
        if JSMath.round(candidate.score * 100) < filters.minScore { return false }
        if filters.completeOnly && candidate.expectedTracks != 0 && candidate.matchedTracks < candidate.expectedTracks {
            return false
        }
        if !filters.formats.isEmpty && !candidate.formats.contains(where: { filters.formats.contains($0) }) { return false }
        if filters.lossless && !allLossless(candidate) { return false }
        if filters.everyTrack && !everyTrackPresent(candidate) { return false }
        for (signal, minimum) in filters.minSignals where minimum != 0 {
            //? not judged can't satisfy a minimum asked for
            guard let value = candidate.signals[signal] else { return false }
            if JSMath.round(value * 100) < minimum { return false }
        }
        return passesQuality(candidate, filters.quality)
    }

    /// A folder's quality as a sortable tuple (`qualityRank`): lossless first, then the worst file's depth, rate and
    /// bitrate - unknown as zero.
    public static func qualityRank(_ candidate: Candidate) -> [Double] {
        [allLossless(candidate) ? 1 : 0, candidate.bitDepths.min() ?? 0, candidate.sampleRates.min() ?? 0,
         candidate.bitrates.min() ?? 0]
    }

    /// The list in the chosen order (`sortCandidates`): ties keep the server's order, the match score - JavaScript's sort
    /// is stable, so this one is too.
    public static func sorted(_ candidates: [Candidate], _ sort: CandidateSort) -> [Candidate] {
        func stable(_ before: (Candidate, Candidate) -> Bool) -> [Candidate] {
            candidates.enumerated().sorted { a, b in
                if before(a.element, b.element) { return true }
                if before(b.element, a.element) { return false }
                return a.offset < b.offset
            }.map(\.element)
        }
        switch sort {
        case .score: return candidates
        case .sizeDesc: return stable { $0.totalSize > $1.totalSize }
        case .sizeAsc: return stable { $0.totalSize < $1.totalSize }
        case .quality:
            return stable { a, b in
                let x = qualityRank(a), y = qualityRank(b)
                for index in x.indices where x[index] != y[index] { return x[index] > y[index] }
                return false
            }
        }
    }

    /// The best match through the chips - the top of the list by score - wherever the sort puts it (Sources.tsx `best`).
    public static func best(_ passing: [Candidate]) -> String? { passing.first.map(key) }

    public enum Band: String, Sendable { case good, mid, bad }

    /// `scoreClass`: good from 75, mid from 40, bad under.
    public static func band(_ percent: Double) -> Band { percent >= 75 ? .good : percent >= 40 ? .mid : .bad }

    /// A card's score as a percentage: `Math.round(score * 100)`.
    public static func percent(_ candidate: Candidate) -> Double { JSMath.round(candidate.score * 100) }

    /// Only an EDITED query overrides (`queryOverride`): the box shows the first of possibly several searches.
    public static func queryOverride(_ typed: String, _ lastShown: String) -> String {
        let trimmed = JSText.trim(typed)
        return !trimmed.isEmpty && !WebText.same(trimmed, lastShown) ? trimmed : ""
    }

    // MARK: a card

    /// A source card's speed bar is full at 3 MB/s, and capped there (`SPEED_BAR_FULL`).
    public static let speedBarFull = 3.0 * 1024 * 1024

    public struct SpeedFact: Sendable, Equatable {
        public enum Kind: String, Sendable { case measured, advertised, unknown }
        public let kind: Kind
        public let text: String
        public let note: String
        /// 0-100.
        public let percent: Double
    }

    /// The card's Speed: what deadwax measured from this peer where it has, else their own average (`speedFact`).
    public static func speedFact(_ candidate: Candidate) -> SpeedFact {
        func bar(_ rate: Double) -> Double { min(100, JSMath.round(rate / speedBarFull * 100)) }
        if let measured = candidate.measuredSpeed, measured != 0, !measured.isNaN {
            //? one transfer is an anecdote, said as measured; more than one is an average, said with a ~
            let samples = candidate.measuredSamples.flatMap { $0 == 0 || $0.isNaN ? nil : $0 } ?? 1
            return SpeedFact(kind: .measured, text: "\(samples > 1 ? "~" : "")\(RequestWords.speed(measured))",
                             note: "what you got from them", percent: bar(measured))
        }
        if candidate.uploadSpeed != 0, !candidate.uploadSpeed.isNaN {
            return SpeedFact(kind: .advertised, text: RequestWords.speed(candidate.uploadSpeed), note: "their usual speed",
                             percent: bar(candidate.uploadSpeed))
        }
        return SpeedFact(kind: .unknown, text: "Unknown", note: "no speed reported yet", percent: 0)
    }

    /// The card's Starts (`startsFact`): "now" with a free slot, "after 3 others" queued behind, else "soon".
    public static func startsFact(_ candidate: Candidate) -> (text: String, waits: Bool) {
        if candidate.hasFreeSlot { return ("now", false) }
        let ahead = candidate.queueLength
        return ahead > 0 ? ("after \(WebText.number(ahead)) \(ahead == 1 ? "other" : "others")", true) : ("soon", true)
    }

    /// `trimRate`: a rate in kHz, whole without a fraction, else to one place.
    static func trimRate(_ khz: Double) -> String {
        khz.isFinite && khz == khz.rounded(.towardZero) ? WebText.number(khz) : jsFixed(khz, 1)
    }

    /// The card's Quality, short (`qualityText`): "FLAC 16/44.1", "MP3 VBR 245k", "FLAC", "Unknown".
    public static func qualityText(_ candidate: Candidate) -> String {
        let formats = candidate.formats.filter { !$0.isEmpty }.map { $0.uppercased() }.joined(separator: ", ")
        if formats.isEmpty { return "Unknown" }
        func span(_ values: [Double], _ show: (Double) -> String) -> String {
            guard let low = values.min(), let high = values.max() else { return "" }
            return low == high ? show(low) : "\(show(low))-\(show(high))"
        }
        if allLossless(candidate) {
            let depth = span(candidate.bitDepths, WebText.number)
            let rate = span(candidate.sampleRates) { trimRate($0 / 1000) }
            if !depth.isEmpty && !rate.isEmpty { return "\(formats) \(depth)/\(rate)" }
            if !depth.isEmpty { return "\(formats) \(depth)-bit" }
            if !rate.isEmpty { return "\(formats) \(rate) kHz" }
            return formats
        }
        let bitrate = span(candidate.bitrates, WebText.number)
        return bitrate.isEmpty ? formats : "\(formats) \(candidate.variableBitrate ? "VBR " : "")\(bitrate)k"
    }

    /// The card's Tracks (`tracksText`): "11 of 11" against the release's audio tracks, "12 files" without a tracklist.
    public static func tracksText(_ candidate: Candidate) -> String {
        if candidate.expectedTracks == 0 {
            return "\(candidate.audioFileCount) \(candidate.audioFileCount == 1 ? "file" : "files")"
        }
        guard let audio = candidate.audioExpected, audio > 0 else {
            return "\(candidate.matchedTracks) of \(candidate.expectedTracks)"
        }
        let missing = Double(candidate.missingCount ?? candidate.missingTracks?.count ?? 0)
        return "\(WebText.number(max(0, audio - missing))) of \(WebText.number(audio))"
    }

    /// The size as the web writes it (lib/format.ts `formatSize`): "412 MB", "1.2 GB" - "" for none.
    public static func size(_ bytes: Double) -> String {
        guard bytes != 0, !bytes.isNaN else { return "" }
        let mb = bytes / (1024 * 1024)
        if mb < 1024 { return "\(WebText.number(JSMath.round(mb))) MB" }
        return "\(jsFixed(mb / 1024, 1)) GB"
    }

    /// One of a card's reasons: a signal, its words, its value as a percentage, its band and what it measures.
    public struct SignalChip: Sendable, Equatable, Identifiable {
        public let signal: String
        public let label: String
        public let value: Double
        public let band: Band
        /// "" for a signal deadwax doesn't name.
        public let meaning: String
        public var id: String { signal }
    }

    /// The score's signals as chips (`signalChips`): the six in their order, then any other the server sent by name - a
    /// signal not judged left out.
    public static func signalChips(_ candidate: Candidate) -> [SignalChip] {
        let known = Set(signals.map(\.signal))
        let others = candidate.signals.keys.filter { !known.contains($0) }
            .sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
        let named = Dictionary(signals.map { ($0.signal, $0) }, uniquingKeysWith: { first, _ in first })
        return (signals.map(\.signal) + others).compactMap { signal in
            guard let raw = candidate.signals[signal] else { return nil }
            let value = JSMath.round(raw * 100)
            let word = named[signal]?.label ?? signal
            return SignalChip(signal: signal, label: capitalised(word), value: value, band: band(value),
                              meaning: named[signal]?.meaning ?? "")
        }
    }

    /// `word.charAt(0).toUpperCase() + word.slice(1)`.
    static func capitalised(_ word: String) -> String {
        let units = Array(word.utf16)
        guard let first = units.first else { return "" }
        let head = String(decoding: [first], as: UTF16.self).uppercased()
        return head + String(decoding: units.dropFirst(), as: UTF16.self)
    }

    public enum EditionTone: String, Sendable { case amber, red, purple, green, plain }

    /// The edition words found in a folder's name, each with its tone (`editionTags`, EDITION_TAG_COLORS' families).
    public static func editionTags(_ candidate: Candidate) -> [(tag: String, tone: EditionTone)] {
        let colours: [String: EditionTone] = [
            "REMASTER": .amber, "SUPER DELUXE": .red, "DELUXE": .purple, "BOX SET": .green, "ANNIVERSARY": .plain,
            "EXPANDED": .plain, "LIMITED": .purple, "SPECIAL EDITION": .plain,
        ]
        return candidate.detectedEditionTags.filter { !$0.isEmpty }.map { ($0, colours[$0] ?? .plain) }
    }

    /// The card's amber line, or nil (`missingLine`): up to three named, the rest counted.
    public static func missingLine(_ candidate: Candidate) -> String? {
        let named = (candidate.missingTracks ?? []).map { (track: MissingTrack) -> String in
            "“\(track.title.isEmpty ? "track \(track.position.map(String.init) ?? "?")" : track.title)”"
        }
        let count = max(candidate.missingCount ?? 0, named.count)
        if count == 0 { return nil }
        let shown = Array(named.prefix(3))
        let more = count - shown.count
        if more == 0 { return "Missing \(PerPerson.listed(shown))" }
        return shown.isEmpty
            ? "Missing \(count) \(count == 1 ? "track" : "tracks")"
            : "Missing \(shown.joined(separator: ", ")) and \(more) more"
    }

    /// What a Get sends of the folder it picked (perPerson.ts `candidateQuality`).
    public static func quality(_ candidate: Candidate) -> JobQuality {
        JobQuality(formats: candidate.formats, bitrates: candidate.bitrates, bitDepths: candidate.bitDepths,
                   sampleRates: candidate.sampleRates, variableBitrate: candidate.variableBitrate)
    }

    // MARK: the sheet's lines

    /// What the sheet says under its asking line (Sources.tsx `SEARCH_TAKES`).
    public static let searchTakes = "This takes a few seconds."

    /// 'Looking for “Third” by Portishead…' - and 'by Kanye West or Ye…' for an album shared under two names
    /// (`searchingLine`).
    public static func searchingLine(_ release: GetRelease) -> String {
        searchingLine(artist: release.artist, albumArtist: release.albumArtist, album: release.album)
    }

    public static func searchingLine(artist: String, albumArtist: String, album: String) -> String {
        var names: [String] = []
        for name in [artist, albumArtist] {
            let trimmed = JSText.trim(name)
            if !trimmed.isEmpty, !WebText.same(trimmed, "N/A"),
               !names.contains(where: { WebText.same(JSText.lowercase($0), JSText.lowercase(trimmed)) }) {
                names.append(trimmed)
            }
        }
        return "Looking for “\(album)”\(names.isEmpty ? "" : " by \(names.joined(separator: " or "))")…"
    }

    /// "“Portishead Third”", or "“Kanye West Donda” and “Ye Donda”" - every query a search ran (`queriesText`).
    public static func queriesText(_ answer: FindCandidatesAnswer) -> String {
        let queries = !(answer.queries ?? []).isEmpty ? answer.queries ?? [] : answer.query.isEmpty ? [] : [answer.query]
        return PerPerson.listed(queries.map { "“\($0)”" })
    }

    /// Lossless only, Soulseek answered, and nothing is left (`nothingLossless`).
    public static func nothingLossless(_ answer: FindCandidatesAnswer, _ format: FormatPreference?) -> Bool {
        format == .losslessOnly && answer.candidates.isEmpty && answer.responseCount > 0
    }

    /// 'Nothing lossless found for “Portishead Third”.' (`nothingLosslessLine`).
    public static func nothingLosslessLine(_ answer: FindCandidatesAnswer) -> String {
        "Nothing lossless found for \(queriesText(answer))."
    }

    /// ...and under it, why - and where the setting is (`NOTHING_LOSSLESS_NOTE`).
    public static let nothingLosslessNote =
        "Some were found, but none with lossless files - your Format is Lossless only, which leaves the rest out. You can change it in You, under Getting albums."

    /// "41 sources", "1 source" (`sourcesCount`).
    public static func sourcesCount(_ count: Int) -> String { "\(count) \(count == 1 ? "source" : "sources")" }

    /// "41 sources found - none match your filters." (`noneMatchLine`).
    public static func noneMatchLine(_ count: Int) -> String {
        "\(sourcesCount(count)) found - none \(count == 1 ? "matches" : "match") your filters."
    }

    /// 'Nothing found for “Portishead Third”.' (`nothingFoundLine`).
    public static func nothingFoundLine(_ answer: FindCandidatesAnswer) -> String { "Nothing found for \(queriesText(answer))." }

    /// The line under the cards (`searchedLine`): 'Searched for “Portishead Third” · 41 sources, 4 match your filters'.
    public static func searchedLine(_ answer: FindCandidatesAnswer, shown: Int) -> String {
        let total = answer.candidates.count
        let matching = shown == total
            ? (total == 1 ? "it matches your filters" : "all match your filters")
            : "\(shown) \(shown == 1 ? "matches" : "match") your filters"
        return "Searched for \(queriesText(answer)) · \(sourcesCount(total)), \(matching)"
    }

    /// What the sheet says to VoiceOver as each outcome lands, in one line (`sourcesAnnouncement`).
    public static func announcement(pending: Bool, release: GetRelease?, error: String?, status: StoreStatus?,
                                    answer: FindCandidatesAnswer?, shown: Int, notPicked: String? = nil,
                                    format: FormatPreference?) -> String {
        if pending, let release { return searchingLine(release) }
        if let error, !error.isEmpty { return error }
        if let status { return status.title }
        guard let answer else { return "" }
        let total = answer.candidates.count
        let line = total == 0
            ? (nothingLossless(answer, format) ? "\(nothingLosslessLine(answer)) \(nothingLosslessNote)" : nothingFoundLine(answer))
            : shown == 0 ? noneMatchLine(total) : "\(sourcesCount(shown))."
        guard let notPicked, !notPicked.isEmpty else { return line }
        return "\(line) \(notPicked)"
    }
}

/// The Sources sheet's and a card's own words, and Get the album's - the ones the web builds inline in its components
/// (Sources.tsx, SourceCard.tsx, ReleaseGroupPage.tsx), read out of their source by the exporter and held here.
public enum SourcesWords {
    public static let title = "Choose a source"
    public static let cancel = "Cancel"
    public static let searchFor = "Search for"
    public static let search = "Search"
    public static let tryAgain = "Try again"
    public static let clearFilters = "Clear filters"
    public static let searchAgain = "Search again"
    /// VoiceOver's names for the sort and the chips.
    public static let sortLabel = "Sort the sources"
    public static let chipsLabel = "Filter the sources"

    /// A card's Get, and its name for VoiceOver: one peer often shares a FLAC folder and an MP3 one of the same album.
    public static let get = "Get"
    public static func getLabel(_ candidate: Candidate) -> String { "Get \(candidate.directoryName) from \(candidate.username)" }
    /// The score's name for VoiceOver: "92% match".
    public static func match(_ percent: Double) -> String { "\(Self.percent(percent)) match" }
    /// A score, and a signal's value, as drawn: "92%".
    public static func percent(_ value: Double) -> String { "\(WebText.number(value))%" }
    /// "from bob", " · in 2 parts, one per disc".
    public static func from(_ candidate: Candidate) -> String {
        let discs = candidate.discFolders.count
        return "from \(candidate.username)\(discs > 1 ? " · in \(discs) parts, one per disc" : "")"
    }
    public static let speed = "Speed"
    public static let tracks = "Tracks"
    public static let quality = "Quality"
    public static let size = "Size"
    public static let starts = "Starts"
    /// A size nobody reported.
    public static let noSize = "\u{2013}"
    /// "Why it's a 92% match".
    public static func reasons(_ percent: Double) -> String { "Why it's a \(WebText.number(percent))% match" }
    /// Before the edition words, for VoiceOver.
    public static let inItsName = "In its name: "

    /// The album you don't have's Get.
    public static let getTheAlbum = "Get the album"

    /// The sheet's subtitle, what the sources are for (ReleaseGroupPage.tsx's `subtitle`): the album's title and the
    /// pressing's label, "Third · CD · 2008 · GB · Island" - either left out when empty.
    public static func subtitle(title: String, pressing: String) -> String {
        [title, pressing].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    // The phone's own: what VoiceOver says of a disclosure - a card's score, Search again - as it says it of iOS's own
    // (the web's aria-expanded, which a screen reader reads the same way).
    public static let expanded = "expanded"
    public static let collapsed = "collapsed"
}
