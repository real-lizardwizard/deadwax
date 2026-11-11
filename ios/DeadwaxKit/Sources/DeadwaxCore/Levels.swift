import Foundation

// Normalization on the phone (Phase 1, app 0.2): the web's setting and rule, and the server's gain rule.
//
// The web app asks deadwax for a levelled copy of a FLAC song (`&level=album|track`, src/levels.py); the
// phone plays the original file and multiplies it itself, once per decoded sample (DeadwaxAudio's
// GainedSource) - so it takes the web's setting and rule as they are (ui/src/lib/loudness.ts levelFor,
// ui/src/lib/resume.ts relevel, ui/src/lib/streamWrap.ts isFlac) and the server's measurements and gain rule
// (src/loudness.py gain_for) with no reserve: nothing is resampled on the way, so no room is kept for a
// resample's ringing. Fixtures/levels/levels-vectors.json holds each to its source's own answers
// (ios/scripts/export-level-vectors.cjs writes it; tests/test_ios_levels.py and ui/test/ioslevels.sim.cjs read
// it too). See notes/ios.md.

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

/// How songs were queued: an album played as an album (its page's Play, Shuffle or a row, its own Play Next
/// or Play Last), or songs (a song's Play Next or Play Last, and later a playlist or a shuffle).
public enum QueuedAs: String, Sendable, CaseIterable {
    case album, songs
}

/// The level a queue entry is played at: its album's gain, or its own.
public enum Level: String, Codable, Sendable, CaseIterable {
    case album, track
}

/// The level a setting asks for, for songs queued `as` an album or as songs - nil for none (Off). Automatic
/// levels what was queued as an album by album, and everything else song by song (loudness.ts levelFor).
public func levelFor(_ setting: Normalization, _ queuedAs: QueuedAs) -> Level? {
    switch setting {
    case .off: return nil
    case .song: return .track
    case .album: return .album
    case .auto: return queuedAs == .album ? .album : .track
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

/// The server's loudness constants, and the two rules every level answer goes through.
public enum Loudness {
    /// ReplayGain 2.0's reference, LUFS (src/loudness.py REFERENCE_LUFS): every song or album is brought to it.
    public static let referenceLUFS = -18.0
    /// The largest 24-bit sample in dBFS, `20 * log10((2^23 - 1) / 2^23)` (FULL_DB) - written as Python's repr of
    /// it, so the limit is the server's to the last bit whatever this platform's log10 says (a test checks the
    /// two agree, and tests/test_ios_levels.py that this is the server's).
    public static let fullDB = -1.0354387945871882e-06
    /// The measurement's version (src/loudness.py ALGORITHM_VERSION), which the loudness route's `algorithm`
    /// carries: a stored answer of another one is fetched again (Phase 2).
    public static let algorithm = 1

    /// A FLAC file, by its extension or by the type Navidrome gives it - streamWrap.ts isFlac exactly: the
    /// suffix "flac" in any case, or the type's part before ";", trimmed and lowercased, `audio/flac` or
    /// `audio/x-flac`.
    public static func isFlac(suffix: String?, contentType: String?) -> Bool {
        let head = (contentType ?? "").split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let type = WebText.trim(head).lowercased()
        return suffix?.lowercased() == "flac" || type == "audio/flac" || type == "audio/x-flac"
    }

    /// Whether a song is levelled at all (loudness.ts levels): a level on its entry, the file as it is (a
    /// transcode to MP3 has no FLAC in it), and a FLAC. Everything else plays as it is.
    public static func levels(suffix: String?, contentType: String?, level: Level?, format: String) -> Bool {
        level != nil && format == "raw" && isFlac(suffix: suffix, contentType: contentType)
    }
}

extension Song {
    /// streamWrap.ts isFlac, on this song's suffix and type. The phone always asks for a FLAC as it is
    /// (`StreamFormat`), so a levelled entry is levelled exactly when this holds.
    public var isFlac: Bool { Loudness.isFlac(suffix: suffix, contentType: contentType) }
}

/// The gain applied to a song or an album, and why it is that (src/loudness.py Gain).
public struct Gain: Equatable, Sendable {
    /// dB, rounded down to the hundredth
    public let gainDb: Double
    /// what levelling alone asked for: the reference less the loudness (0 for silence)
    public let wantedDb: Double
    /// the loudness it was worked out from, LUFS (-infinity: silence)
    public let loudness: Double
    /// the peak it is held under, dBFS (-infinity: a peak of 0)
    public let peakDb: Double
    /// the peak held it under what was wanted
    public let held: Bool

    public init(gainDb: Double, wantedDb: Double, loudness: Double, peakDb: Double, held: Bool) {
        self.gainDb = gainDb
        self.wantedDb = wantedDb
        self.loudness = loudness
        self.peakDb = peakDb
        self.held = held
    }
}

/// src/loudness.py gain_for(), line for line: the gain that takes `loudness` (LUFS; -infinity for silence) to
/// the reference, held so the loudest sample (`peak`, 1.0 = full scale) lands no higher than the largest 24-bit
/// sample, with `reserveDb` more room besides - and rounded DOWN to 0.01 dB, after snapping to a millionth of a
/// hundredth as Python's `round(x, 6)` does (correctly rounded, which `String(format: "%.6f")` is too; the
/// shortcut `(x * 1e6).rounded() / 1e6` is not, and three of the vectors are inputs where it differs). The
/// snap never passes the limit. The phone's reserve is 0.
public func gainFor(loudness: Double, peak: Double, reserveDb: Double = 0) -> Gain {
    let wanted = loudness.isFinite ? Loudness.referenceLUFS - loudness : 0.0
    let peakDb = peak > 0 ? 20 * log10(peak) : -Double.infinity
    let limit = Loudness.fullDB - peakDb - reserveDb
    let gain = min(wanted, limit)
    var rounded = WebText.pythonRound(gain * 100, 6).rounded(.down) / 100
    if rounded > limit {
        rounded = (gain * 100).rounded(.down) / 100
    }
    return Gain(gainDb: rounded, wantedDb: wanted, loudness: loudness, peakDb: peakDb, held: limit < wanted)
}

/// The one number every sample of a levelled song is multiplied by: 10^(dB/20) worked out in Double and
/// rounded to a Float once, so the same gain is always the same Float wherever it is made.
public func gainMultiplier(_ gainDb: Double) -> Float {
    Float(pow(10.0, gainDb / 20.0))
}
