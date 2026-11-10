import Foundation

// What deadwax says about an album's loudness, for the phone's Normalization: `GET
// /deadwax/navidrome/loudness/album/{album_id}` (2.1.1, src/levels.py album_loudness) and the warm it asks for,
// `POST /deadwax/navidrome/level/album/{album_id}`. Snake-case JSON, so every struct names its keys; the raw,
// unrounded numbers, from which the phone works the gain out itself (`gainFor`, no reserve).

/// A song's (or the album's) state in the loudness answer. A state this app doesn't know - a later server's -
/// decodes as `.unmeasured`: the song plays as it is, and nothing fails.
public enum LoudnessState: String, Codable, Sendable, CaseIterable {
    case measured, measuring, unmeasured
    case notLevelled = "not_levelled"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LoudnessState(rawValue: raw) ?? .unmeasured
    }
}

/// `GET /deadwax/navidrome/loudness/album/{album_id}`: what deadwax has measured of an album - never measuring
/// anything to answer. `album` is the pooled loudness of the songs that count (only with `state` measured);
/// `songs` is every song of Navidrome's listing, in its order. `whole` is false when a song couldn't be looked
/// at just now (or the listing couldn't be had): the album is then never levelled from part of it.
public struct AlbumLoudness: Codable, Sendable, Equatable {
    /// the reference the server levels to (-18) - for Info and a downloaded copy, never checked against ours
    public let referenceLufs: Double
    /// the measurement's version (src/loudness.py ALGORITHM_VERSION): Phase 2 fetches a stored copy again when
    /// the server's is another
    public let algorithm: Int
    public let state: LoudnessState
    /// why it isn't measured or can't be levelled, in the server's words (Debug says them; About reads them)
    public let why: String?
    public let whole: Bool
    public let album: AlbumLevel
    public let songs: [SongLoudness]

    enum CodingKeys: String, CodingKey {
        case referenceLufs = "reference_lufs"
        case algorithm, state, why, whole, album, songs
    }

    public init(referenceLufs: Double = Loudness.referenceLUFS, algorithm: Int = Loudness.algorithm, state: LoudnessState,
                why: String? = nil, whole: Bool = true, album: AlbumLevel, songs: [SongLoudness]) {
        self.referenceLufs = referenceLufs
        self.algorithm = algorithm
        self.state = state
        self.why = why
        self.whole = whole
        self.album = album
        self.songs = songs
    }

    /// The entry for one song of the album, by its id (the first, should Navidrome list one twice).
    public func song(_ id: String) -> SongLoudness? {
        songs.first { $0.id == id }
    }
}

/// The album's own numbers: its pooled loudness (null: silent) and its largest sample (1.0 = full scale), only
/// when it is measured, and how many of its songs count toward its level.
public struct AlbumLevel: Codable, Sendable, Equatable {
    public let loudnessLufs: Double?
    public let peak: Double?
    public let songs: Int

    enum CodingKeys: String, CodingKey {
        case loudnessLufs = "loudness_lufs"
        case peak, songs
    }

    public init(loudnessLufs: Double? = nil, peak: Double? = nil, songs: Int) {
        self.loudnessLufs = loudnessLufs
        self.peak = peak
        self.songs = songs
    }
}

/// One song of the album: its loudness (null: silent) and peak when measured, and why not when it isn't.
public struct SongLoudness: Codable, Sendable, Equatable {
    public let id: String
    public let state: LoudnessState
    public let loudnessLufs: Double?
    public let peak: Double?
    public let why: String?

    enum CodingKeys: String, CodingKey {
        case loudnessLufs = "loudness_lufs"
        case id, state, peak, why
    }

    public init(id: String, state: LoudnessState, loudnessLufs: Double? = nil, peak: Double? = nil, why: String? = nil) {
        self.id = id
        self.state = state
        self.loudnessLufs = loudnessLufs
        self.peak = peak
        self.why = why
    }
}

/// `POST /deadwax/navidrome/level/album/{album_id}` (always 202): "measuring" (started, or already), "busy"
/// (another album is being measured: dropped, ask again later) or "not_levelled" (this server measures nothing).
public struct WarmAnswer: Codable, Sendable, Equatable {
    public let state: String

    public init(state: String) {
        self.state = state
    }
}

/// What deadwax would say of a song's level, in the shape Info's words are written against - the web's
/// LevelAnswer (ui/src/lib/loudness.ts, src/levels.py describe()). The phone makes it from what it applied
/// (`levelAnswer`), so the web's words say what is heard.
public struct LevelAnswer: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable, CaseIterable {
        case measured, measuring, unmeasured, plain
        case notLevelled = "not_levelled"
    }

    public let level: Level
    public let state: State
    public let gainDb: Double?
    public let wantedDb: Double?
    public let loudnessLufs: Double?
    public let peakDb: Double?
    public let held: Bool
    public let songs: Int
    public let measuredSongs: Int
    public let why: String?

    enum CodingKeys: String, CodingKey {
        case gainDb = "gain_db"
        case wantedDb = "wanted_db"
        case loudnessLufs = "loudness_lufs"
        case peakDb = "peak_db"
        case measuredSongs = "measured_songs"
        case level, state, held, songs, why
    }

    public init(level: Level, state: State, gainDb: Double? = nil, wantedDb: Double? = nil, loudnessLufs: Double? = nil,
                peakDb: Double? = nil, held: Bool = false, songs: Int = 1, measuredSongs: Int = 0, why: String? = nil) {
        self.level = level
        self.state = state
        self.gainDb = gainDb
        self.wantedDb = wantedDb
        self.loudnessLufs = loudnessLufs
        self.peakDb = peakDb
        self.held = held
        self.songs = songs
        self.measuredSongs = measuredSongs
        self.why = why
    }
}
