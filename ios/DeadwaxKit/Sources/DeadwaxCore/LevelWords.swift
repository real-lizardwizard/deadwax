import Foundation

/// The facts about a song's file that Info's Format row and the level words read - the queue entry's
/// `suffix`, `contentType` and Navidrome's OpenSubsonic `samplingRate`, `bitDepth` and `channelCount`, each 0
/// when Navidrome didn't say (the web's QueueTrack keeps them so).
public struct FileFacts: Sendable, Equatable {
    public var suffix: String?
    public var contentType: String?
    public var sampleRate: Int
    public var bitDepth: Int
    public var channels: Int

    public init(suffix: String? = nil, contentType: String? = nil, sampleRate: Int = 0, bitDepth: Int = 0, channels: Int = 0) {
        self.suffix = suffix
        self.contentType = contentType
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
    }

    public init(song: Song) {
        self.init(suffix: song.suffix, contentType: song.contentType, sampleRate: song.samplingRate ?? 0,
                  bitDepth: song.bitDepth ?? 0, channels: song.channelCount ?? 0)
    }
}

/// One row of Info: a label and its value.
public struct SoundRow: Sendable, Equatable, Codable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Info's words for a song's Normalization and its file - the web's, ported verbatim (ui/src/lib/loudness.ts
/// describeLevel for Debug, an admin's, with the numbers; ui/src/lib/aboutSound.ts aboutLevel, About's
/// "Sound" group, in a listener's words; ui/src/lib/debugRows.ts formatWords), every toFixed through `jsFixed`.
/// Fixtures/levels/levels-vectors.json holds each to the TypeScript's own answers. The phone adds one case the
/// web hasn't got - no answer about the album had come when the song had to start - with two lines of its own
/// (D3), and its own words for You's Off (`Normalization.note`).
public enum LevelWords {
    /// About's group heading (aboutSound.ts SOUND_TITLE).
    public static let soundTitle = "Sound"
    /// About's Normalization while deadwax hasn't answered (LEVEL_CHECKING).
    public static let checking = "Checking…"
    /// Debug's, the same (loudness.ts LEVEL_NOT_KNOWN_YET).
    public static let notKnownYet = "Asked for; deadwax hasn't said yet"
    /// Info's word where there is nothing to say (debugRows.ts NOT_KNOWN).
    public static let notKnown = "Not known"
    /// Debug's Format row when Navidrome said nothing of the file (debugRows.ts formatRow).
    public static let formatUnsaid = "Navidrome didn't say"

    /// (The phone's own, D3) Debug, for a song that started before any answer about its level had come.
    public static let unansweredDebug = "Played as it is this time - deadwax didn't say in time"

    /// (The phone's own, D3) About, the same: "Not this time - the album's volume couldn't be checked".
    public static func unansweredAbout(_ level: Level) -> String {
        "Not this time - the \(level == .album ? "album" : "song")'s volume couldn't be checked"
    }

    /// Why About says a levelled song is off for it (aboutSound.ts OFF_WORDS), each a listener's line.
    public enum Off: String, CaseIterable, Sendable {
        /// numpy or soundfile can't be loaded, or the player's cache can't be used: nothing is levelled there
        case server
        /// not a FLAC: only FLAC is levelled
        case kind
        /// a FLAC sent as MP3 (never on the phone, which plays every FLAC as it is; kept as the web has it)
        case transcoded
        /// too large to make the web's levelled copy of (never from the loudness route)
        case large
        /// anything else: a file deadwax can't read or measure
        case file

        public var words: String {
            switch self {
            case .server: return "Off for this song - this server can't adjust volume"
            case .kind: return "Off for this song - only FLAC songs are adjusted"
            case .transcoded: return "Off for this song - this device can't play FLAC, so it's sent as MP3"
            case .large: return "Off for this song - its file is too large"
            case .file: return "Off for this song - its file can't be measured"
            }
        }
    }

    /// The listener's line for deadwax's reason not to level a song, by what the server's words are
    /// (aboutSound.ts ABOUT_REASONS, first match): never the server's words themselves.
    public static func offWords(_ why: String?) -> String {
        let words = why ?? ""
        if words.contains("without numpy") || words.contains("player's cache can't be used") { return Off.server.words }
        if words.hasPrefix("it isn't a FLAC file") { return Off.kind.words }
        if words.contains("MiB a song is held in memory") { return Off.large.words }
        return Off.file.words
    }

    /// A gain as a listener reads it: "3.6 dB quieter", "1.2 dB louder", "no change needed" (aboutSound.ts).
    public static func volumeChange(_ gain: Double) -> String {
        let size = jsFixed(abs(gain), 1)
        if size == "0.0" { return "no change needed" }
        return "\(size) dB \(gain < 0 ? "quieter" : "louder")"
    }

    /// A gain as Debug says it: "+1.20 dB", "-7.42 dB" - never "-0.00" (loudness.ts signedDb).
    public static func signedDb(_ value: Double) -> String {
        let fixed = jsFixed(abs(value), 2)
        return "\(value < 0 && fixed != "0.00" ? "-" : "+")\(fixed) dB"
    }

    /// A loudness as Debug says it: "-10.6 LUFS" (loudness.ts lufs).
    public static func lufs(_ value: Double) -> String {
        let fixed = jsFixed(abs(value), 1)
        return "\(value < 0 && fixed != "0.0" ? "-" : "")\(fixed) LUFS"
    }

    static func kindWords(suffix: String?) -> String {
        let kind = (suffix ?? "").isEmpty ? "" : suffix!.uppercased()
        return kind.isEmpty ? "only FLAC songs are levelled" : "\(kind) songs play as they are"
    }

    static func songs(_ count: Int) -> String {
        count == 1 ? "song" : "songs"
    }

    /// Info > Debug's Normalization row (loudness.ts describeLevel): Off; not levelled and why; Album or Song,
    /// the gain, and the loudness it came from - or the peak that held it; measuring, and how far an album has
    /// got; played as it is this time; not measured yet. `format` is how the song is asked for ("raw" or "mp3";
    /// nil reads as raw).
    public static func describeLevel(suffix: String?, contentType: String?, level: Level?, format: String?, answer: LevelAnswer?) -> String {
        guard level != nil else { return "Off" }
        guard Loudness.levels(suffix: suffix, contentType: contentType, level: level, format: format ?? "raw") else {
            return "Not levelled - \(kindWords(suffix: suffix))"
        }
        guard let answer else { return notKnownYet }
        let album = answer.level == .album
        switch answer.state {
        case .notLevelled:
            return "Not levelled - \(answer.why ?? "deadwax won't level it")"
        case .measuring:
            return album ? "Measuring its album… (\(answer.measuredSongs) of \(answer.songs) \(songs(answer.songs)))" : "Measuring the song…"
        case .plain:
            return "Played as it is this time - its \(album ? "album was" : "loudness was") still being measured"
        case .unmeasured, .measured:
            break
        }
        guard answer.state != .unmeasured, let gain = answer.gainDb else { return "Not measured yet - it played as it is this time" }
        let whose = album ? "album" : "song"
        let head = "\(album ? "Album" : "Song"), \(signedDb(gain))"
        if answer.held, let wanted = answer.wantedDb {
            return "\(head) · held there by its peak (it wanted \(String(signedDb(wanted).dropLast(3))))"
        }
        guard let loudness = answer.loudnessLufs else { return "\(head) · the \(whose) is silent" }
        return "\(head) · the \(whose) at \(lufs(loudness))"
    }

    /// Info > About's Normalization, in a listener's words (aboutSound.ts aboutLevel): Off; off for this song,
    /// and why; checking; measuring; not this time; "Album volume matching, 3.6 dB quieter" - "as loud as it
    /// can go without distorting" when its peak held it, "kept as it is" when its peak held it at no change at
    /// all, "nothing to adjust" for a silent one.
    public static func aboutLevel(suffix: String?, contentType: String?, level: Level?, format: String?, answer: LevelAnswer?) -> String {
        guard level != nil else { return "Off" }
        guard Loudness.levels(suffix: suffix, contentType: contentType, level: level, format: format ?? "raw") else {
            return Loudness.isFlac(suffix: suffix, contentType: contentType) ? Off.transcoded.words : Off.kind.words
        }
        guard let answer else { return checking }
        if answer.state == .notLevelled { return offWords(answer.why) }
        let whose = answer.level == .album ? "album" : "song"
        switch answer.state {
        case .measuring:
            return answer.level == .album
                ? "Measuring the album… (\(answer.measuredSongs) of \(answer.songs) \(songs(answer.songs)))"
                : "Measuring the song…"
        case .plain:
            return "Not this time - the \(whose) was still being measured"
        default:
            break
        }
        guard answer.state != .unmeasured, let gain = answer.gainDb else { return "Not this time - the \(whose) hasn't been measured yet" }
        let head = "\(answer.level == .album ? "Album" : "Song") volume matching"
        if answer.loudnessLufs == nil { return "\(head) - nothing to adjust, the \(whose) is silent" }
        if answer.held && (answer.wantedDb ?? 0) > 0 && jsFixed(abs(gain), 1) == "0.0" {
            return "\(head) - kept as it is, it can't go louder without distorting"
        }
        let change = "\(head), \(volumeChange(gain))"
        return answer.held ? "\(change) - as loud as it can go without distorting" : change
    }

    // ------------------------------------------------------------ the phone's

    /// The answer Info's words are written from on the phone: what was applied to the song, once it is settled
    /// (it plays or has played, or its album's answer is fixed for the queue) - or, for a song whose open will
    /// decide from whatever deadwax says then, what deadwax says of its album now (so "Measuring the album… (3
    /// of 10 songs)" can show). Nil until either exists.
    static func answer(song: Song, level: Level?, decided: AppliedLevel?, live: AlbumLoudness?) -> LevelAnswer? {
        if let decided { return levelAnswer(decided) }
        guard let live else { return nil }
        return levelAnswer(decide(level: level, song: song, answer: live), live: true)
    }

    static func unanswered(_ decided: AppliedLevel?) -> Level? {
        if case .unanswered(let level) = decided { return level }
        return nil
    }

    /// About's Normalization for a song on the phone: `level` as it was queued, `decided` what is settled for it
    /// (`LevelDecisions.settled` - nil while nothing is), `live` the book's answer for its album now. The app
    /// calls the form that takes the queue's decisions, so a settled decision is never missed.
    public static func about(song: Song, level: Level?, decided: AppliedLevel?, live: AlbumLoudness?) -> String {
        if let late = unanswered(decided) { return unansweredAbout(late) }
        return aboutLevel(suffix: song.suffix, contentType: song.contentType, level: level, format: StreamFormat.format(for: song),
                          answer: answer(song: song, level: level, decided: decided, live: live))
    }

    /// Debug's Normalization for a song on the phone, from the same as `about`.
    public static func debug(song: Song, level: Level?, decided: AppliedLevel?, live: AlbumLoudness?) -> String {
        if unanswered(decided) != nil { return unansweredDebug }
        return describeLevel(suffix: song.suffix, contentType: song.contentType, level: level, format: StreamFormat.format(for: song),
                             answer: answer(song: song, level: level, decided: decided, live: live))
    }

    /// About's Normalization for the queue's entry `key`: what its queue has settled for it, else what deadwax
    /// says now.
    public static func about(song: Song, level: Level?, key: Int, decisions: LevelDecisions, live: AlbumLoudness?) -> String {
        about(song: song, level: level, decided: decisions.settled(key: key, level: level, song: song), live: live)
    }

    /// Debug's Normalization for the queue's entry `key`, from the same as `about`.
    public static func debug(song: Song, level: Level?, key: Int, decisions: LevelDecisions, live: AlbumLoudness?) -> String {
        debug(song: song, level: level, decided: decisions.settled(key: key, level: level, song: song), live: live)
    }

    // ------------------------------------------------------------ the file

    static func khz(_ rate: Int) -> String {
        "\(WebText.number(Double(rate) / 1000)) kHz"
    }

    static func channelWords(_ channels: Int) -> String {
        channels == 1 ? "mono" : channels == 2 ? "stereo" : "\(channels) channels"
    }

    /// The file's kind in capitals - FLAC, MP3 - from its extension, else from its type; "" unknown.
    static func kindOf(_ file: FileFacts) -> String {
        if let suffix = file.suffix, !suffix.isEmpty { return suffix.uppercased() }
        let type = WebText.trim(WebText.beforeSemicolon(file.contentType ?? "")).lowercased()
        guard type.hasPrefix("audio/") else { return "" }
        var kind = String(type.dropFirst("audio/".count))
        if kind.hasPrefix("x-") { kind.removeFirst(2) }
        return kind.uppercased()
    }

    /// The file as Navidrome read it, plainly: "FLAC, 24-bit, 192 kHz, stereo" - a part nobody gave left out,
    /// "" when none of it is known (debugRows.ts formatWords).
    public static func formatWords(_ file: FileFacts) -> String {
        [
            kindOf(file),
            file.bitDepth > 0 ? "\(file.bitDepth)-bit" : "",
            file.sampleRate > 0 ? khz(file.sampleRate) : "",
            file.channels > 0 ? channelWords(file.channels) : "",
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Debug's Format row's value (debugRows.ts formatRow).
    public static func debugFormat(_ file: FileFacts) -> String {
        let words = formatWords(file)
        return words.isEmpty ? formatUnsaid : words
    }

    /// About's Sound group as the web draws it (aboutSound.ts soundRows): Format, Gapless, Normalization - an
    /// answer about another level than the entry's read as none.
    public static func soundRows(file: FileFacts, level: Level?, gapless: Bool, format: String?, answer: LevelAnswer?) -> [SoundRow] {
        let mine = answer.flatMap { $0.level == level ? $0 : nil }
        let words = formatWords(file)
        return [
            SoundRow(label: "Format", value: words.isEmpty ? notKnown : words),
            SoundRow(label: "Gapless", value: gapless ? "On" : "Off"),
            SoundRow(label: "Normalization", value: aboutLevel(suffix: file.suffix, contentType: file.contentType, level: level,
                                                              format: format, answer: mine)),
        ]
    }

    /// About's Sound group on the phone: the same three rows, Gapless always On (the engine joins every song
    /// end to end; D8), Normalization from what is settled or what deadwax says now.
    public static func soundRows(song: Song, level: Level?, decided: AppliedLevel?, live: AlbumLoudness?) -> [SoundRow] {
        let words = formatWords(FileFacts(song: song))
        return [
            SoundRow(label: "Format", value: words.isEmpty ? notKnown : words),
            SoundRow(label: "Gapless", value: "On"),
            SoundRow(label: "Normalization", value: about(song: song, level: level, decided: decided, live: live)),
        ]
    }

    /// About's Sound group for the queue's entry `key` (the form the app calls).
    public static func soundRows(song: Song, level: Level?, key: Int, decisions: LevelDecisions, live: AlbumLoudness?) -> [SoundRow] {
        soundRows(song: song, level: level, decided: decisions.settled(key: key, level: level, song: song), live: live)
    }
}
