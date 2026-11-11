import Foundation

// The player's Normalization setting and resume's re-fitting of a saved level to it - the very same declarations,
// to the character, as the Normalization port's (branch p1/levels, Levels.swift: `Normalization` and `relevel`).
// Resume needs both (Resume.swift's fromSnapshot and resumed re-level every song they put back), and the two ports
// were built side by side; where they meet, this file is deleted and Levels.swift's are kept - nothing else
// changes, since the names, cases, raw values and API are the same. (Level.swift is its twin for `Level`.)

/// The player's Normalization, kept per device as the web keeps it (localStorage there, UserDefaults here,
/// under the same name): Automatic by default.
public enum Normalization: String, CaseIterable, Sendable {
    case auto, song, album, off

    public static let `default`: Normalization = .auto
    /// The UserDefaults key: the web's localStorage key (ui/src/state/persisted.ts), so the two read alike.
    public static let storageKey = "deadwax-player-normalization"
    /// You > Playback's heading for the four choices.
    public static let title = "Normalization"

    /// What was stored, as the web reads it (readPlayerNormalization): "song", "album" and "off" as they are,
    /// anything else - nothing stored, junk, "auto" - Automatic.
    public static func read(_ stored: String?) -> Normalization {
        switch stored {
        case "song": return .song
        case "album": return .album
        case "off": return .off
        default: return .auto
        }
    }

    /// The choice's name, as the web's You shows it (ui/src/app/NormalizationChoice.tsx).
    public var label: String {
        switch self {
        case .auto: return "Automatic"
        case .song: return "By song"
        case .album: return "By album"
        case .off: return "Off"
        }
    }

    /// The line under it: the web's words, but Off's, which on the web ends "unless Maximum quality converts
    /// it" - a setting the phone hasn't got (D3: the clause dropped). "bit for bit" stays, as the web pins it.
    public var note: String {
        switch self {
        case .auto:
            return "An album you play keeps one level for the whole album, so its quiet songs stay quiet beside its loud ones. "
                + "Anything else - a playlist, a shuffle, a song you add with Play Next - is levelled song by song."
        case .song: return "Every song brought to the same loudness, even the quiet and loud songs of one album."
        case .album: return "Every song at its album's level, even when it plays on its own or in a playlist."
        case .off: return "No levelling: every song plays exactly as the file is, bit for bit."
        }
    }
}

/// A saved level re-fitted to this device's setting, as a queue put back is (resume.ts relevel): Off none, By
/// song track, By album album, Automatic the level saved - or track where none was saved.
public func relevel(_ saved: Level?, _ setting: Normalization) -> Level? {
    switch setting {
    case .off: return nil
    case .song: return .track
    case .album: return .album
    case .auto: return saved ?? .track
    }
}
