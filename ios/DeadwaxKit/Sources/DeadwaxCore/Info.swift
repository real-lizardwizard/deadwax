import Foundation

// Info on the phone (Phase 1, D8): what the sheet's tabs are, what Debug's rows say, and the queue entry, the
// album answer and the id bridge's rows as About reads them - so the app's InfoView only draws.
//
//  - The tabs: the web's lib/debugRows.ts INFO_TABS, infoTabs and shownTab - Debug an admin's alone.
//  - Debug's rows: debugRows.ts formatRow, sentAsRow (the phone has no MP4 and never resamples: the file as it
//    is, or Navidrome's MP3), normalizationRow (LevelWords.debug, from what the queue settled), the Gapless row
//    (always On, D8), and "Fields from Navidrome" (fieldNames, isEmptyValue, sentFields, sentRow,
//    otherSongsFields, otherSongsRow) on the album answer's RAW JSON - so false stays a value, apart from 0.
//    The web's Resampled, Why sent this way, Speed, Last song change and seek, and the turntable's rows are the
//    web's own and left out; the phone adds its engine's rows (Output, Conversion, Lane, Buffered ahead, Last
//    start), new words with no TypeScript behind them (plays-words.md 2.8's proposal).
//  - About's inputs: the web builds About from the QUEUE ENTRY (its QueueTrack, whose title, artist, album and
//    cover fell back to the album's when it was queued) and the album answer the queue was played from. The app
//    keeps those as Core's QueueTrack and Album; `AboutTrack(entry:)`, `AboutAlbum(album:)`,
//    `SongDetails(song:)` and `PressingRow(row:)` read them as About.swift's own types, field for field.
//
// Held to the web: Tests/DeadwaxCoreTests/InfoTests.swift mirrors ui/test/debug.sim.cjs's checks of these
// functions line for line (:409-447 the fields, :334/:383/:384 Sent as, :501-505 the tabs), and replays
// Fixtures/levels/info-vectors.json through `AboutAlbum(album:)` against the TypeScript's own answers.

// MARK: - the tabs

/// Info's two tabs (debugRows.ts InfoTab, INFO_TABS).
public enum InfoTab: String, Sendable, CaseIterable, Hashable {
    case about, debug

    /// The tab's name on its segment.
    public var label: String {
        switch self {
        case .about: return "About"
        case .debug: return "Debug"
        }
    }

    /// The tabs this person has (infoTabs): About and Debug for an admin - a Navidrome admin, break-glass, or
    /// everyone with logins off (/me's `admin`) - and About alone for anyone else, who gets no tab strip at all.
    public static func tabs(admin: Bool) -> [InfoTab] {
        admin ? allCases : [.about]
    }

    /// The tab shown (shownTab): the one chosen while this person has it - About once the admin role goes.
    public static func shown(_ tab: InfoTab, admin: Bool) -> InfoTab {
        tabs(admin: admin).contains(tab) ? tab : .about
    }
}

/// Info's own words (ui/src/app/InfoSheet.tsx), each as the web says it.
public enum InfoWords {
    public static let title = "Info"
    public static let done = "Done"
    public static let songTitle = "The song"
    public static let albumTitle = "The album"
    public static let artistTitle = "The artist"
    /// (2.0.7) the album's folder's heading - a path on the server, for whoever looks after the albums
    public static let serverTitle = "On the server"
    public static let folder = "Folder"

    /// The song card's writers' line.
    public static func writtenBy(_ writers: String) -> String { "Written by \(writers)" }

    /// How long the song's and the store's answers are held back for each other as Info opens (useInfoDetails.ts
    /// INFO_SETTLE_MS), so a card doesn't grow under a finger reaching for the one below it.
    public static let settleSeconds = 0.5
}

// MARK: - Debug's rows

/// One row of Info > Debug (debugRows.ts DebugRow): a label, its value, a smaller note under it - and which of
/// them are data (Navidrome's field names), set in the monospaced face.
public struct InfoRow: Sendable, Equatable {
    public let label: String
    public let value: String
    public let note: String?
    public let mono: Bool
    public let noteMono: Bool

    public init(label: String, value: String, note: String? = nil, mono: Bool = false, noteMono: Bool = false) {
        self.label = label
        self.value = value
        self.note = note
        self.mono = mono
        self.noteMono = noteMono
    }
}

/// A headed group of Info's rows.
public struct InfoSection: Sendable, Equatable {
    public let title: String
    public let rows: [InfoRow]

    public init(title: String, rows: [InfoRow]) {
        self.title = title
        self.rows = rows
    }
}

/// An answer as Navidrome sent it, every field kept, for "Fields from Navidrome": JSON's six kinds, with `false`
/// apart from `0` (JSONSerialization's NSNumber would make them one, and `false` is a value, `0` none).
public indirect enum RawJSON: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RawJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RawJSON].self))
        }
    }

    /// A field of an object; nil for anything else, and for a field it hasn't got.
    public subscript(key: String) -> RawJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    /// The fields JavaScript's `Object.keys` gives: an object's names, a list's places ("0", "1"...), none for
    /// anything else - what `typeof value === 'object'` lets through (a list included, null not).
    var fields: [String: RawJSON]? {
        switch self {
        case .object(let fields): return fields
        case .array(let items): return Dictionary(uniqueKeysWithValues: items.enumerated().map { (String($0.offset), $0.element) })
        default: return nil
        }
    }
}

public enum InfoDebug {
    /// Where there is nothing to say (debugRows.ts NOT_KNOWN).
    public static let notKnown = LevelWords.notKnown

    // ------------------------------------------------------------ Fields from Navidrome

    /// The names of the fields an answer carries, sorted as JavaScript sorts strings - by UTF-16 code unit, the
    /// same on every device (fieldNames): none for no answer, or one that isn't an object.
    public static func fieldNames(_ answer: RawJSON?) -> [String] {
        guard let fields = answer?.fields else { return [] }
        return fields.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    /// A value that carries nothing (isEmptyValue): null, "", 0, an empty list or object - what Navidrome writes for
    /// a field it always sends when the file has nothing for it. `false` is a value, and so is anything inside a
    /// list or an object.
    public static func isEmptyValue(_ value: RawJSON?) -> Bool {
        switch value {
        case nil, .null: return true
        case .string(let text): return text.isEmpty
        case .number(let number): return number == 0
        case .array(let items): return items.isEmpty
        case .object(let fields): return fields.isEmpty
        case .bool: return false
        }
    }

    /// An answer's field names with a value, apart from those sent empty - each sorted (sentFields).
    public static func sentFields(_ answer: RawJSON?) -> (filled: [String], empty: [String]) {
        let names = fieldNames(answer)
        let fields = answer?.fields ?? [:]
        let empty = names.filter { isEmptyValue(fields[$0]) }
        return (names.filter { !empty.contains($0) }, empty)
    }

    /// "Song fields" and "Album fields" (sentRow): the names, empties named apart in the note - both data, in the
    /// monospaced face; "Not known" with no answer, or one with no fields.
    public static func sentRow(_ label: String, _ answer: RawJSON?) -> InfoRow {
        guard answer?.fields != nil else { return InfoRow(label: label, value: notKnown) }
        let (filled, empty) = sentFields(answer)
        if filled.isEmpty && empty.isEmpty { return InfoRow(label: label, value: notKnown) }
        return InfoRow(label: label, value: filled.isEmpty ? "Nothing with a value" : filled.joined(separator: ", "),
                       note: empty.isEmpty ? nil : "Empty: \(empty.joined(separator: ", "))", mono: true, noteMono: !empty.isEmpty)
    }

    /// The song's entry in the album answer, and its place there: the first whose `id` is the song's (the web's
    /// `album.song.find(each => each.id === track.id)`), nil when the answer or its list has none.
    public static func song(_ id: String, in album: RawJSON?) -> (place: Int, song: RawJSON)? {
        guard case .array(let songs)? = album?["song"] else { return nil }
        for (place, each) in songs.enumerated() where each["id"] == .string(id) {
            return (place, each)
        }
        return nil
    }

    /// The fields another song of the album carries with a value and this one doesn't - sent empty or left out
    /// (otherSongsFields): nil with no song, or no song list. Neither the song itself (`place`) nor another entry
    /// with its `id` is "another song".
    public static func otherSongsFields(song: (place: Int, song: RawJSON)?, album: RawJSON?) -> [String]? {
        guard let song, case .array(let songs)? = album?["song"] else { return nil }
        let mine = Set(sentFields(song.song).filled)
        let id = song.song["id"]
        var theirs = Set<String>()
        for (place, other) in songs.enumerated() {
            guard other.fields != nil, place != song.place else { continue }
            if let theirID = other["id"], let id, same(theirID, id) { continue }
            for name in sentFields(other).filled where !mine.contains(name) { theirs.insert(name) }
        }
        return theirs.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    /// JavaScript's `===` between two of JSON's values: a list or an object is only ever itself.
    static func same(_ a: RawJSON, _ b: RawJSON) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.string(let x), .string(let y)): return x.utf16.elementsEqual(y.utf16)
        default: return false
        }
    }

    /// "Only on other songs" (otherSongsRow): the names, as data; "Nothing this song lacks"; "Not known".
    public static func otherSongsRow(song: (place: Int, song: RawJSON)?, album: RawJSON?) -> InfoRow {
        let label = "Only on other songs"
        guard let names = otherSongsFields(song: song, album: album) else { return InfoRow(label: label, value: notKnown) }
        return names.isEmpty ? InfoRow(label: label, value: "Nothing this song lacks")
                             : InfoRow(label: label, value: names.joined(separator: ", "), mono: true)
    }

    /// "Fields from Navidrome", on the album answer the queue was played from as Navidrome sent it (nil when it
    /// isn't in hand): the song's entry in it, what other songs carry, the album's own.
    public static func fieldsSection(songID: String, album: RawJSON?) -> InfoSection {
        let song = song(songID, in: album)
        return InfoSection(title: "Fields from Navidrome", rows: [
            sentRow("Song fields", song?.song),
            otherSongsRow(song: song, album: album),
            sentRow("Album fields", album),
        ])
    }

    // ------------------------------------------------------------ Sent to this device

    /// How the song comes to the phone (sentAsRow, the phone's half): the file as it is - "FLAC, as the file is",
    /// "The file as it is" with no kind known - or, for what iOS can't decode, Navidrome's MP3 (StreamFormat).
    public static func sentAs(_ song: Song) -> InfoRow {
        let label = "Sent as"
        switch StreamFormat.format(for: song) {
        case "mp3":
            return InfoRow(label: label, value: "MP3, transcoded by Navidrome")
        case "raw":
            let kind = LevelWords.kindOf(FileFacts(song: song))
            return InfoRow(label: label, value: kind.isEmpty ? "The file as it is" : "\(kind), as the file is")
        default:
            return InfoRow(label: label, value: notKnown)
        }
    }

    /// What the phone's engine says of the song heard, for its own rows - each nil when it hasn't said.
    public struct Engine: Sendable, Equatable {
        /// the output's rate (Hz), its name (the route: "AirPods Pro", "Speaker") and its latency (seconds)
        public var outputRate: Double?
        public var outputName: String?
        public var latency: Double?
        /// the file's rate and bits against the output's, in Phase 0's words ("24-bit 192 kHz FLAC file → 48 kHz output")
        public var conversion: String?
        /// the lane the song heard is on: the songs' rate and channels, the rate its node runs at, and whether it converts
        public var laneRate: Double?
        public var laneChannels: Int?
        public var nodeRate: Double?
        public var converting: Bool?
        /// scheduled ahead of what has been heard, in seconds
        public var aheadSeconds: Double?
        /// from the last play asked for to its first sample heard, in seconds
        public var lastStartSeconds: Double?

        public init(outputRate: Double? = nil, outputName: String? = nil, latency: Double? = nil, conversion: String? = nil,
                    laneRate: Double? = nil, laneChannels: Int? = nil, nodeRate: Double? = nil, converting: Bool? = nil,
                    aheadSeconds: Double? = nil, lastStartSeconds: Double? = nil) {
            self.outputRate = outputRate
            self.outputName = outputName
            self.latency = latency
            self.conversion = conversion
            self.laneRate = laneRate
            self.laneChannels = laneChannels
            self.nodeRate = nodeRate
            self.converting = converting
            self.aheadSeconds = aheadSeconds
            self.lastStartSeconds = lastStartSeconds
        }
    }

    static func rate(_ hz: Double) -> String {
        "\(WebText.number(hz / 1000)) kHz"
    }

    /// "48 kHz · AirPods Pro · 21 ms latency" - the parts the engine has said.
    public static func outputLine(rate: Double?, name: String?, latency: Double?) -> String? {
        let parts = [
            rate.flatMap { $0 > 0 ? Self.rate($0) : nil },
            name.flatMap { WebText.trim($0).isEmpty ? nil : WebText.trim($0) },
            latency.flatMap { $0.isFinite && $0 >= 0 ? "\(jsFixed($0 * 1000, 0)) ms latency" : nil },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "44.1 kHz stereo, converted to 48 kHz", "48 kHz stereo, no conversion".
    public static func laneLine(rate: Double, channels: Int, nodeRate: Double, converting: Bool) -> String {
        let shape = channels > 0 ? " \(LevelWords.channelWords(channels))" : ""
        return converting ? "\(Self.rate(rate))\(shape), converted to \(Self.rate(nodeRate))" : "\(Self.rate(rate))\(shape), no conversion"
    }

    /// The phone's own rows, those the engine has something for.
    public static func engineRows(_ engine: Engine) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let output = outputLine(rate: engine.outputRate, name: engine.outputName, latency: engine.latency) {
            rows.append(InfoRow(label: "Output", value: output))
        }
        if let conversion = engine.conversion, !conversion.isEmpty {
            rows.append(InfoRow(label: "Conversion", value: conversion))
        }
        if let rate = engine.laneRate, rate > 0, let nodeRate = engine.nodeRate, let converting = engine.converting {
            rows.append(InfoRow(label: "Lane", value: laneLine(rate: rate, channels: engine.laneChannels ?? 0, nodeRate: nodeRate,
                                                               converting: converting)))
        }
        if let ahead = engine.aheadSeconds, ahead.isFinite, ahead >= 0 {
            rows.append(InfoRow(label: "Buffered ahead", value: "\(jsFixed(ahead, 1)) s"))
        }
        if let start = engine.lastStartSeconds, start.isFinite, start >= 0 {
            rows.append(InfoRow(label: "Last start", value: "\(jsFixed(start, 2)) s from the tap to sound"))
        }
        return rows
    }

    /// Info > Debug for the queue's entry `key`, top to bottom (debugSections, the phone's): The file; Sent to this
    /// device - Sent as, Normalization (from what the queue settled for the entry, else what deadwax says now),
    /// Gapless, the engine's rows; Fields from Navidrome, on the album answer as Navidrome sent it.
    public static func sections(song: Song, level: Level?, key: Int, decisions: LevelDecisions, live: AlbumLoudness?,
                                engine: Engine, album: RawJSON?) -> [InfoSection] {
        [
            InfoSection(title: "The file", rows: [InfoRow(label: "Format", value: LevelWords.debugFormat(FileFacts(song: song)))]),
            InfoSection(title: "Sent to this device", rows: [
                sentAs(song),
                InfoRow(label: "Normalization", value: LevelWords.debug(song: song, level: level, key: key, decisions: decisions, live: live)),
                InfoRow(label: "Gapless", value: "On"),
            ] + engineRows(engine)),
            fieldsSection(songID: song.id, album: album),
        ]
    }
}

// MARK: - About's inputs, from what the app keeps

extension AboutTrack {
    /// The queue's entry as About reads it - the web's QueueTrack, whose title, artist, album and cover were filled
    /// in from the album when it was queued (toQueueTrack). Never a fresh Song: `init(song:)` leaves those "" where
    /// the entry has the album's.
    public init(entry: QueueTrack) {
        self.init(id: entry.id, title: entry.title, artist: entry.artist, album: entry.album, albumId: entry.albumId,
                  coverArt: entry.coverArt, duration: entry.duration)
    }
}

extension SongDetails {
    /// A song as the routes' model read it, as About reads one: every field it has, the numbers as numbers.
    public init(song: Song) {
        self.init(id: song.id, artist: song.artist, artistId: song.artistId, track: song.track.map(Double.init),
                  discNumber: song.discNumber.map(Double.init), duration: song.duration, suffix: song.suffix,
                  playCount: song.playCount.map(Double.init), displayComposer: song.displayComposer,
                  contributors: song.contributors?.map { Credit(role: $0.role, name: $0.artist?.name) })
    }
}

extension AboutAlbum {
    /// The album answer the queue was played from, as the routes' model read it, for About. Nothing of a playlist's
    /// stub in Phase 1 (`partial` nil). The model reads a disc title's `disc` as an Int or a string of digits,
    /// narrower than About's own JS Number() reading - they agree on everything Navidrome sends.
    public init(album: Album) {
        self.init(id: album.id, name: album.name, artist: album.artist, year: album.year.map(Double.init),
                  coverArt: album.coverArt, songCount: album.songCount.map(Double.init),
                  song: album.song?.map { SongDetails(song: $0) }, partial: nil,
                  discTitles: album.discTitles?.map { AboutDiscTitle(disc: $0.disc.map(Double.init), title: $0.title) },
                  artistId: album.artistId, recordLabels: album.recordLabels?.map { AboutAlbum.Label(name: $0.name) })
    }
}

extension PressingRow {
    /// One of the id bridge's `present` rows, as "This pressing" and the folder read it.
    public init(row: StoreRow) {
        self.init(path: row.path, edition: row.edition, year: row.year, formats: row.formats)
    }
}

extension Song {
    /// A queue entry as a Song, for what is worked out from a song when the app has only the entry (a queue put
    /// back): its id, names, album, cover, length and file facts - the fields Info's Sound and the level rules read.
    public init(queued entry: QueueTrack) {
        self.init(id: entry.id, title: entry.title, album: entry.album, albumId: entry.albumId, artist: entry.artist,
                  duration: entry.duration, suffix: entry.suffix, contentType: entry.contentType,
                  samplingRate: entry.sampleRate > 0 ? entry.sampleRate : nil, bitDepth: entry.bitDepth > 0 ? entry.bitDepth : nil,
                  channelCount: entry.channels > 0 ? entry.channels : nil, coverArt: entry.coverArt)
    }
}

// MARK: - Now Playing's own words

/// Now Playing's words that PlayerWords hasn't got (ui/src/player/NowPlaying.tsx, app/ActionMenu.tsx).
public enum NowPlayingWords {
    /// The chevron at the top.
    public static let close = "Close"
    public static let previous = "Previous"
    public static let airPlay = "AirPlay"
    /// The ••• menu's rows (Phase 1: Info and Go to album; the web's playlist and pin rows come later).
    public static let info = "Info"
    public static let goToAlbum = "Go to album"

    /// The ••• button's name: what the menu holds - "Go to album" only for a song that names its album
    /// (NowPlaying.tsx's `More: info, add to a playlist, go to album, pin`, without what Phase 1 hasn't got).
    public static func more(hasAlbum: Bool) -> String {
        "More: info\(hasAlbum ? ", go to album" : "")"
    }
}

extension UpNextWords {
    /// The header's buttons (UpNext.tsx): Edit, and Done - which ends Edit while editing, else closes.
    public static let edit = "Edit"
    public static let done = "Done"
    /// The Shuffle chip's own word (the Repeat chip's is `repeatLabel`).
    public static let shuffle = "Shuffle"
}
