import Foundation

/// What the phone did with a queue entry's level - decided once, when the entry is first opened, and kept for
/// every later open of it (a seek, a pause's resume, a new route, a retry): a song never changes level while it
/// plays, and Info says what is heard.
public enum AppliedLevel: Equatable, Sendable {
    /// the entry has no level (Normalization Off when it was queued)
    case off
    /// levelled entry, not a FLAC: plays as it is, as the web plays an MP3
    case notFlac
    /// played at this gain: an album's (`songs` its counted songs) or the song's own (`songs` 1)
    case gain(Gain, Level, songs: Int)
    /// deadwax won't level it, and why in its words (the song's own reason before its album's)
    case notLevelled(why: String?, Level)
    /// played as it is this time: its album (or the song) was being measured when it had to start
    case plain(Level, songs: Int, measured: Int)
    /// played as it is this time: nothing measured yet
    case unmeasured(Level, songs: Int)
    /// played as it is this time: no answer had come when it had to start
    case unanswered(Level)

    /// The factor every sample is multiplied by - nil for none at all, so the source isn't wrapped and the song
    /// plays bit for bit what the decoder gave: Off, not a FLAC, anything played as it is, and a gain of
    /// exactly 0 dB (a silent album, or one already at the reference).
    public var multiplier: Float? {
        if case .gain(let gain, _, _) = self, gain.gainDb != 0 { return gainMultiplier(gain.gainDb) }
        return nil
    }

    /// The level the entry was queued at, nil for Off - and for a song that isn't a FLAC, whose words come
    /// from what the song is, before any level.
    public var level: Level? {
        switch self {
        case .off, .notFlac: return nil
        case .gain(_, let level, _), .notLevelled(_, let level), .plain(let level, _, _), .unmeasured(let level, _),
             .unanswered(let level):
            return level
        }
    }
}

/// The decision for one entry: `level` as it was queued (nil: Off), the song, and the loudness answer for its
/// album in hand when it had to start (nil: none had come). In order: Off; not a FLAC; no answer; the song
/// missing from the answer (the album changed since) plays as it is; the song's own `not_levelled` before
/// anything of its album's (as src/levels.py describe() decides); then by the song's own state (track) or the
/// album's (album). `whole` is never read: the server answers `measured` only for a whole album.
///
/// A measured loudness with no peak beside it (the server sends null only for a peak that isn't finite, which
/// today's never measures) plays as it is, as not measured: a peak of 0 would mean no limit at all, the whole
/// gain wanted - +22 dB for a song at -40 LUFS - and the engine has no limiter behind it. With no loudness
/// either it is silence, a gain of nothing, as the server's own gain_for() says.
public func decide(level: Level?, song: Song, answer: AlbumLoudness?) -> AppliedLevel {
    guard let level else { return .off }
    guard song.isFlac else { return .notFlac }
    guard let answer else { return .unanswered(level) }
    let songs = level == .album ? answer.album.songs : 1
    guard let mine = answer.song(song.id) else { return .unmeasured(level, songs: songs) }
    if mine.state == .notLevelled { return .notLevelled(why: mine.why, level) }
    switch level {
    case .track:
        switch mine.state {
        case .measured:
            guard let gain = safeGain(loudness: mine.loudnessLufs, peak: mine.peak) else { return .unmeasured(.track, songs: 1) }
            return .gain(gain, .track, songs: 1)
        case .measuring:
            return .plain(.track, songs: 1, measured: 0)
        case .unmeasured, .notLevelled:
            return .unmeasured(.track, songs: 1)
        }
    case .album:
        switch answer.state {
        case .measured:
            guard let gain = safeGain(loudness: answer.album.loudnessLufs, peak: answer.album.peak) else {
                return .unmeasured(.album, songs: songs)
            }
            return .gain(gain, .album, songs: songs)
        case .notLevelled:
            return .notLevelled(why: answer.why, .album)
        case .measuring:
            return .plain(.album, songs: songs, measured: answer.songs.filter { $0.state == .measured }.count)
        case .unmeasured:
            return .unmeasured(.album, songs: songs)
        }
    }
}

/// gain_for() on the route's numbers: a null loudness is silence (-infinity), a null peak beside a loudness is no
/// gain at all (nil: play as it is) - and beside silence a peak of 0, whose gain is nothing either way.
func safeGain(loudness: Double?, peak: Double?) -> Gain? {
    guard let loudness else { return gainFor(loudness: -.infinity, peak: peak ?? 0) }
    guard let peak else { return nil }
    return gainFor(loudness: loudness, peak: peak)
}

/// Info's answer for a decision, in the web's LevelAnswer shape, so the web's own words (`LevelWords`) say it.
/// A gain's numbers are rounded as the server rounds its own answer (src/levels.py `_measured`: wanted,
/// loudness and peak to 2 places with Python's round, None when not finite; the gain as it is) - so Debug
/// reads "-10.3 LUFS" for an album at -10.249, as the web does, not "-10.2". `live`: an answer about a song not
/// begun yet, where "being measured" is now (measuring) rather than when it started (plain). Nil for Off and
/// not a FLAC (their words come before any answer) and for no answer.
public func levelAnswer(_ applied: AppliedLevel, live: Bool = false) -> LevelAnswer? {
    func r2(_ value: Double) -> Double? { value.isFinite ? WebText.pythonRound(value, 2) : nil }
    switch applied {
    case .off, .notFlac, .unanswered:
        return nil
    case .gain(let gain, let level, let songs):
        return LevelAnswer(level: level, state: .measured, gainDb: gain.gainDb, wantedDb: r2(gain.wantedDb),
                           loudnessLufs: r2(gain.loudness), peakDb: r2(gain.peakDb), held: gain.held, songs: songs,
                           measuredSongs: songs, why: nil)
    case .notLevelled(let why, let level):
        return LevelAnswer(level: level, state: .notLevelled, why: why)
    case .plain(let level, let songs, let measured):
        return LevelAnswer(level: level, state: live ? .measuring : .plain, songs: songs, measuredSongs: measured)
    case .unmeasured(let level, let songs):
        return LevelAnswer(level: level, state: .unmeasured, songs: songs)
    }
}

/// One queue's decisions, kept for its life (a new play - Play, Shuffle, a song row, a queue put back - is a new
/// queue and a new one of these). Pure; the app holds it under a lock, since the engine opens songs on its own
/// queue.
///
///  - Each entry (Up Next's key, unique in a queue's life) is decided once, at its first open, and every later
///    open of it gets the same decision.
///  - Every album-level entry of one album is decided from ONE answer for the queue's life: the answer in hand
///    when the first of them was decided - even none. So an album plays at one gain throughout, or as it is
///    throughout, and a gapless join never steps (the web steps once its measurement lands; D3). Its next play
///    picks the gain up. A song of the album deadwax won't level is still that song's own decision.
///  - Track-level entries are each their own: decided from the answer in hand when each is opened.
///
/// Info reads `settled(key:level:song:)`, never a fresh `decide` on the book's answer: an album-level entry not
/// opened yet (skipped to while paused, D4) whose album is fixed already will play from the fixed answer, so
/// its words must come from that too.
public struct LevelDecisions: Sendable, Equatable {
    public private(set) var entries: [Int: AppliedLevel] = [:]
    /// the answer each album's album-level entries are decided from (an entry with nil: there was none)
    public private(set) var albums: [String: AlbumLoudness?] = [:]

    public init() {}

    /// The decision already made for an entry, if any.
    public func decided(_ key: Int) -> AppliedLevel? {
        entries[key]
    }

    /// The album whose one answer an entry is decided from: an album-level FLAC's, nil for anything else.
    static func sharing(level: Level?, song: Song) -> String? {
        guard level == .album, song.isFlac else { return nil }
        return song.albumId
    }

    /// What an entry is played at, as far as it is settled now, without deciding anything: the decision made at
    /// its first open; else, for an album-level entry whose album's answer is fixed already, the decision its
    /// open will make from that answer (it can be no other); else nil - its open will decide from whatever
    /// deadwax says then. What Info's words are written from (`LevelWords.about`'s `decided`).
    public func settled(key: Int, level: Level?, song: Song) -> AppliedLevel? {
        if let made = entries[key] { return made }
        guard let album = Self.sharing(level: level, song: song), let fixed = albums[album] else { return nil }
        return DeadwaxCore.decide(level: level, song: song, answer: fixed)
    }

    /// The entry's decision: the one made at its first open, or made now from `answer` (the book's for the
    /// song's album, at this moment) - for an album-level entry, from the answer its album's first was decided
    /// from.
    public mutating func decide(key: Int, level: Level?, song: Song, answer: AlbumLoudness?) -> AppliedLevel {
        if let made = settled(key: key, level: level, song: song) {
            entries[key] = made
            return made
        }
        if let album = Self.sharing(level: level, song: song) {
            albums[album] = .some(answer)
        }
        let made = DeadwaxCore.decide(level: level, song: song, answer: answer)
        entries[key] = made
        return made
    }

    /// Whether an album's album-level entries have their answer fixed already (so the first of a play needn't
    /// wait for it).
    public func fixed(album: String) -> Bool {
        albums[album] != nil
    }
}

/// How long the first song of a play may wait for its loudness, and when it should: only a levelled FLAC, only
/// while no answer has come or the one in hand says what it needs is being measured, polled every second, for
/// at most 20 s (src/levels.py LEVEL_WAIT_HIRES_SECONDS, the web's shorter wait). Joins never wait (they are
/// decided from what is in hand when the engine opens them); a queue put back is decided when it is played.
public enum LevelWait {
    public static let limitSeconds: Double = 20
    public static let pollSeconds: Double = 1

    public static func shouldWait(level: Level?, song: Song, answer: AlbumLoudness?, waited: Double) -> Bool {
        guard let level, song.isFlac, waited < limitSeconds else { return false }
        guard let answer else { return true }
        //? a song the answer doesn't list, or one deadwax won't level, is decided the same however long it waits
        guard let mine = answer.song(song.id), mine.state != .notLevelled else { return false }
        switch level {
        case .album: return answer.state == .measuring
        case .track: return mine.state == .measuring
        }
    }
}

/// When the app asks deadwax about an album's loudness (its `LoudnessBook`): nothing under Off, nothing for an
/// album with no FLAC; for an album wanted (its page open, or holding the entry playing or one of the next
/// three levelled ones) a read first, then a warm when nothing is measured, then a read every 5 s while it is
/// being measured (useInfoDetails.ts LEVEL_ASK_AGAIN_MS). A read before any warm: the warm answers "busy" while
/// any other album measures, even for one measured already.
public enum LoudnessAsking {
    /// how long a measured or not-levelled answer is believed; a measuring or unmeasured one only until the next read
    public static let keptSeconds: Double = 600
    /// the beat of the reads while measuring, and the least time between two warms of one album
    public static let againSeconds: Double = 5
    /// how many levelled entries after the one playing make their album wanted
    public static let wantedAhead = 3

    public enum Next: Equatable, Sendable {
        /// nothing more to ask while this answer is believed
        case done
        /// ask deadwax to measure it (POST), no sooner than `againSeconds` after the last
        case warm
        /// read it again in `againSeconds`
        case readAgain
    }

    /// Whether an answer fetched at `fetchedAt` is still to be believed at `now` (seconds on one clock).
    public static func fresh(_ answer: AlbumLoudness, fetchedAt: Double, now: Double) -> Bool {
        switch answer.state {
        case .measured, .notLevelled: return now - fetchedAt < keptSeconds
        case .measuring, .unmeasured: return false
        }
    }

    /// What follows a read.
    public static func afterRead(_ answer: AlbumLoudness) -> Next {
        switch answer.state {
        case .measured, .notLevelled: return .done
        case .measuring: return .readAgain
        case .unmeasured: return .warm
        }
    }

    /// What follows a warm: measuring - read again; busy - warm again; not levelled - one more read, which
    /// says why; anything else (a later server's) - read again.
    public static func afterWarm(_ answer: WarmAnswer) -> Next {
        answer.state == "busy" ? .warm : .readAgain
    }
}
