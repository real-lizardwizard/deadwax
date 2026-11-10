import Foundation
@testable import DeadwaxCore

/// Fixtures/levels/: what the web's TypeScript and the server's Python answer, written by
/// ios/scripts/export-level-vectors.cjs (never by hand), and the shapes they are read into.
enum LevelVectors {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/levels") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/levels/\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }

    static func levels() throws -> Levels { try load(Levels.self, "levels-vectors") }
    static func info() throws -> Info { try load(Info.self, "info-vectors") }
    static func plays() throws -> Plays { try load(Plays.self, "plays-vectors") }

    // ------------------------------------------------------------ levels-vectors.json

    struct Levels: Decodable {
        let python_gain_for: Python
        let typescript: TypeScript
    }

    struct Python: Decodable {
        let REFERENCE_LUFS: Double
        let FULL_DB: Double
        let FULL_DB_repr: String
        let HEADROOM_DB: Double
        let cases: [GainCase]
    }

    struct GainCase: Decodable {
        let name: String
        let loudness_lufs: Double?
        let peak: Double
        let reserve_db: Double
        let gain_db: Double
        let wanted_db: Double
        let peak_db: Double?
        let held: Bool
        let multiplier: Double
        let multiplier_f32: Double
    }

    struct TypeScript: Decodable {
        struct LevelForCase: Decodable { let setting: String; let `as`: String; let level: String? }
        struct RelevelCase: Decodable { let setting: String; let saved: String?; let level: String? }
        struct FlacCase: Decodable { let suffix: String?; let contentType: String?; let isFlac: Bool }
        struct LevelsCase: Decodable { let suffix: String?; let contentType: String?; let level: String?; let format: String; let levels: Bool }
        struct SignedCase: Decodable { let value: Double; let words: String }
        struct ChangeCase: Decodable { let gain: Double; let words: String }
        struct FixedCase: Decodable { let value: Double; let digits: Int; let fixed: String }
        struct WordsCase: Decodable { let name: String; let track: Entry; let format: String?; let answer: LevelAnswer?; let debug: String; let about: String }
        struct Entry: Decodable { let suffix: String?; let contentType: String?; let level: Level? }
        struct FormatCase: Decodable { let track: QueueEntry; let words: String }
        struct SoundCase: Decodable { let track: QueueEntry; let gapless: Bool; let format: String?; let level: LevelAnswer?; let rows: [SoundRow] }
        struct Choice: Decodable { let value: String; let label: String; let note: String }
        struct Constants: Decodable {
            let SOUND_TITLE: String
            let LEVEL_CHECKING: String
            let LEVEL_NOT_KNOWN_YET: String
            let OFF_WORDS: [String: String]
            let NOT_KNOWN: String
            let DEFAULT_NORMALIZATION: String
        }

        let levelFor: [LevelForCase]
        let relevel: [RelevelCase]
        let isFlac: [FlacCase]
        let levels: [LevelsCase]
        let signedDb: [SignedCase]
        let volumeChange: [ChangeCase]
        let toFixed: [FixedCase]
        let words: [WordsCase]
        let formatWords: [FormatCase]
        let soundRows: [SoundCase]
        let constants: Constants
        let settings: [Choice]
    }

    /// The web's QueueTrack, as the vectors write one.
    struct QueueEntry: Decodable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let albumId: String?
        let coverArt: String?
        let duration: Double
        let contentType: String?
        let suffix: String?
        let sampleRate: Int
        let bitDepth: Int
        let channels: Int
        let level: Level?

        var file: FileFacts {
            FileFacts(suffix: suffix, contentType: contentType, sampleRate: sampleRate, bitDepth: bitDepth, channels: channels)
        }

        var aboutTrack: AboutTrack {
            AboutTrack(id: id, title: title, artist: artist, album: album, albumId: albumId, coverArt: coverArt, duration: duration)
        }
    }

    // ------------------------------------------------------------ info-vectors.json

    struct Info: Decodable {
        struct Details: Decodable {
            struct Store: Decodable { let present: [PressingRow]? }
            let song: SongDetails?
            let store: Store?
        }

        struct AboutCase: Decodable {
            let name: String
            let track: QueueEntry
            let album: AboutAlbum?
            let details: Details?
            let folders: Bool
            let about: About
        }

        struct WrittenCase: Decodable { let song: SongDetails?; let words: String }
        struct PlayedCase: Decodable { let count: Double?; let words: String }
        struct LabelCase: Decodable { let labels: [AboutAlbum.Label]?; let words: String }
        struct TimeCase: Decodable { let seconds: Double?; let words: String }
        struct FormatCase: Decodable { let songs: [SongDetails]; let format: String? }

        let aboutRows: [AboutCase]
        let writtenBy: [WrittenCase]
        let playedLine: [PlayedCase]
        let labelLine: [LabelCase]
        let trackTime: [TimeCase]
        let sharedFormat: [FormatCase]
    }

    // ------------------------------------------------------------ plays-vectors.json

    struct Plays: Decodable {
        struct Constants: Decodable {
            let LISTEN_SLACK_SECONDS: Double
            let RESTART_AFTER_SECONDS: Double
            let NEW_LISTEN: WebListen
        }

        /// The web's Listen: `startedAt` 0 until it has begun.
        struct WebListen: Decodable, Equatable {
            let heard: Double
            let startedAt: Int64
            let submitted: Bool

            var listen: Listen { Listen(heard: heard, startedAt: startedAt == 0 ? nil : startedAt, submitted: submitted) }
        }

        struct CountCase: Decodable { let listened: Double; let duration: Double; let played: Bool }
        struct StepCase: Decodable { let previous: Double; let now: Double; let elapsed: Double; let rate: Double; let seeked: Bool; let step: Double }
        struct Split: Decodable { let before: Double; let after: Double }
        struct JoinCase: Decodable {
            let previous: Double; let oldLength: Double; let now: Double; let elapsed: Double; let rate: Double; let seeked: Bool
            let split: Split
        }
        struct ListenStep: Decodable {
            let kind: String
            let now: Int64?
            let seconds: Double?
            let duration: Double?
            let listen: WebListen
            let nowPlaying: Bool?
            let submit: Bool?
        }
        struct ListenScript: Decodable { let steps: [ListenStep] }

        let constants: Constants
        let countsAsPlayed: [CountCase]
        let listenedStep: [StepCase]
        let splitAcrossJoin: [JoinCase]
        let listens: [ListenScript]
    }
}

extension Level {
    /// A level as the vectors write one: "album", "track", or null.
    static func named(_ name: String?) -> Level? {
        name.flatMap(Level.init(rawValue:))
    }
}
