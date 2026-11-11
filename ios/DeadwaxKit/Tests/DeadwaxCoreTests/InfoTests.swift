import Foundation
import Testing
@testable import DeadwaxCore

/// Info on the phone (Info.swift): the tabs, Debug's rows and About's inputs - held to ui/test/debug.sim.cjs's own
/// checks of debugRows.ts, each case and answer copied from the line named, and to info-vectors.json's About cards
/// through the routes' Album model.
@Suite struct InfoTests {
    static func json(_ text: String) throws -> RawJSON {
        try JSONDecoder().decode(RawJSON.self, from: Data(text.utf8))
    }

    /// debug.sim.cjs `table`: each row as label -> value, or [value, note].
    static func table(_ sections: [InfoSection]) -> [String: [String]] {
        var all: [String: [String]] = [:]
        for row in sections.flatMap(\.rows) { all[row.label] = row.note.map { [row.value, $0] } ?? [row.value] }
        return all
    }

    static func song(suffix: String? = "flac", contentType: String? = "audio/flac", rate: Int? = 44100, bits: Int? = 16,
                     channels: Int? = 2) -> Song {
        Song(id: "s1", title: "Time", album: "The Dark Side of the Moon", albumId: "a1", artist: "Pink Floyd", duration: 425,
             suffix: suffix, contentType: contentType, samplingRate: rate, bitDepth: bits, channelCount: channels, coverArt: "c1")
    }

    // ------------------------------------------------------------ the tabs (debug.sim.cjs:501-505)

    @Test func debugIsAnAdminsTab() {
        #expect(InfoTab.tabs(admin: true).map(\.label) == ["About", "Debug"])
        #expect(InfoTab.tabs(admin: false).map(\.label) == ["About"])
        #expect([InfoTab.shown(.debug, admin: true), .shown(.about, admin: true), .shown(.debug, admin: false), .shown(.about, admin: false)]
                == [.debug, .about, .about, .about])
    }

    // ------------------------------------------------------------ Fields from Navidrome (debug.sim.cjs:409-447)

    @Test func theFieldsNamesAsTheyCame() throws {
        let album = try Self.json(#"""
        {"id": "a1", "name": "The Dark Side of the Moon", "discTitles": [{"disc": 1, "title": "Side one"}],
         "song": [{"id": "s1", "title": "Time", "musicBrainzId": "mb", "played": "2026-09-30", "playCount": 12, "discNumber": 1, "bitDepth": 24}],
         "year": 1973}
        """#)
        let section = InfoDebug.fieldsSection(songID: "s1", album: album)
        let all = Self.table([section])
        #expect(all["Song fields"] == ["bitDepth, discNumber, id, musicBrainzId, playCount, played, title"])
        #expect(all["Album fields"] == ["discTitles, id, name, song, year"])
        #expect(section.rows.map { [$0.label, String($0.mono)] } == [["Song fields", "true"], ["Only on other songs", "false"], ["Album fields", "true"]])
        #expect(all["Only on other songs"] == ["Nothing this song lacks"])
        let none = Self.table([InfoDebug.fieldsSection(songID: "s1", album: nil)])
        #expect([none["Song fields"], none["Only on other songs"], none["Album fields"]] == [["Not known"], ["Not known"], ["Not known"]])
        #expect(InfoDebug.fieldNames(try Self.json("{}")) == [])
    }

    @Test func emptiesAreNamedApartAndFalseIsAValue() throws {
        //? what Navidrome 0.64.2 writes for an older rip, a song never played, beside one that has been
        let album = try Self.json(#"""
        {"id": "a1", "name": "The Dark Side of the Moon", "musicBrainzId": "", "discTitles": [], "userRating": 0, "isCompilation": false,
         "releaseDate": {},
         "song": [{"id": "s1", "title": "Time", "isDir": false, "musicBrainzId": "", "bpm": 0, "bitDepth": 0, "replayGain": {}, "genres": [], "track": 4},
                  {"id": "s2", "title": "Money", "isDir": false, "musicBrainzId": "", "bpm": 0, "bitDepth": 0, "replayGain": {}, "genres": [], "track": 6,
                   "playCount": 3, "played": "2026-09-29", "starred": "2026-09-01"}]}
        """#)
        let section = InfoDebug.fieldsSection(songID: "s1", album: album)
        let all = Self.table([section])
        #expect(all["Song fields"] == ["id, isDir, title, track", "Empty: bitDepth, bpm, genres, musicBrainzId, replayGain"])
        #expect(all["Album fields"] == ["id, isCompilation, name, song", "Empty: discTitles, musicBrainzId, releaseDate, userRating"])
        #expect([section.rows[0].noteMono, section.rows[2].noteMono] == [true, true])
        #expect(all["Only on other songs"] == ["playCount, played, starred"])
        #expect(section.rows[1].mono)
    }

    @Test func anotherSongIsNeverTheSongItself() throws {
        let one = try Self.json(#"{"song": [{"id": "x", "musicBrainzId": ""}, {"id": "y", "musicBrainzId": "abc"}]}"#)
        #expect(InfoDebug.otherSongsFields(song: InfoDebug.song("x", in: one), album: one) == ["musicBrainzId"])
        let again = try Self.json(#"{"song": [{"id": "x", "a": 1, "b": 2}]}"#)
        //? the web's case gives the song apart from the album's list; here it is found in it, by its id
        #expect(InfoDebug.otherSongsFields(song: (place: 1, song: try Self.json(#"{"id": "x", "a": 1}"#)), album: again) == [])
        //? the same song twice in the list: the second is the song again, by its id
        let twice = try Self.json(#"{"song": [{"id": "x"}, {"id": "x", "playCount": 2}, {"id": "z", "year": 1}]}"#)
        #expect(InfoDebug.otherSongsFields(song: InfoDebug.song("x", in: twice), album: twice) == ["year"])
        //? no song list, or the song not in it
        #expect(InfoDebug.otherSongsFields(song: nil, album: twice) == nil)
        #expect(InfoDebug.otherSongsFields(song: InfoDebug.song("x", in: twice), album: try Self.json(#"{"id": "a"}"#)) == nil)
        #expect(InfoDebug.song("q", in: twice) == nil)
    }

    @Test func whatCountsAsEmpty() throws {
        let values = try ["\"\"", "0", "[]", "{}", "null", "false", "\"x\"", "[0]", #"{"a": 0}"#].map { try Self.json($0) }
        #expect(values.map(InfoDebug.isEmptyValue) == [true, true, true, true, true, false, false, false, false])
        #expect(InfoDebug.isEmptyValue(nil))
        #expect(InfoDebug.isEmptyValue(try Self.json("-0")))
        //? an answer of empties only
        let row = InfoDebug.sentRow("Song fields", try Self.json(#"{"a": ""}"#))
        #expect([row.value, row.note] == ["Nothing with a value", "Empty: a"])
        //? false kept apart from 0 as it is read: a value
        #expect(try Self.json("false") == .bool(false) && Self.json("0") == .number(0))
    }

    @Test func namesSortByCodeUnitAsJavaScriptsDo() throws {
        //? Object.keys(...).sort(): upper case before lower, "_" between them, by UTF-16 code unit
        let answer = try Self.json(#"{"b": 1, "B": 1, "_x": 1, "a": 1, "é": 1, "z": 1, "Z": 1, "10": 1, "9": 1}"#)
        #expect(InfoDebug.fieldNames(answer) == ["10", "9", "B", "Z", "_x", "a", "b", "z", "é"])
        //? a list is an object to typeof: its places are its names
        #expect(InfoDebug.fieldNames(try Self.json(#"["a", ""]"#)) == ["0", "1"])
        #expect(InfoDebug.sentRow("Album fields", try Self.json("3")).value == "Not known")
    }

    // ------------------------------------------------------------ Sent as (debug.sim.cjs:334, :383, :384, :386)

    @Test func sentAsIsTheFileOrNavidromesMP3() {
        #expect(InfoDebug.sentAs(Self.song()).value == "FLAC, as the file is")
        #expect(InfoDebug.sentAs(Self.song(suffix: "mp3", contentType: "audio/mpeg", bits: nil)).value == "MP3, as the file is")
        #expect(InfoDebug.sentAs(Self.song(suffix: nil, contentType: nil)).value == "The file as it is")
        //? the phone asks Navidrome for an MP3 of what iOS can't decode (StreamFormat), as the web does in a browser
        #expect(InfoDebug.sentAs(Self.song(suffix: "opus", contentType: "audio/ogg", rate: 48000, bits: nil)).value == "MP3, transcoded by Navidrome")
        #expect(InfoDebug.sentAs(Self.song(suffix: nil, contentType: "audio/x-flac")).value == "FLAC, as the file is")
        #expect(InfoDebug.sentAs(Self.song()).label == "Sent as" && !InfoDebug.sentAs(Self.song()).mono)
    }

    @Test func debugsSectionsOnThePhone() throws {
        let song = Self.song(rate: 192000, bits: 24)
        let sections = InfoDebug.sections(song: song, level: nil, key: 0, decisions: LevelDecisions(), live: nil,
                                          engine: InfoDebug.Engine(), album: nil)
        #expect(sections.map(\.title) == ["The file", "Sent to this device", "Fields from Navidrome"])
        #expect(sections.map { $0.rows.map(\.label) } == [["Format"], ["Sent as", "Normalization", "Gapless"],
                                                         ["Song fields", "Only on other songs", "Album fields"]])
        let all = Self.table(sections)
        #expect(all["Format"] == ["FLAC, 24-bit, 192 kHz, stereo"])
        #expect(all["Normalization"] == ["Off"])
        #expect(all["Gapless"] == ["On"])
        //? a levelled FLAC no answer has come for yet: Debug's own words for that
        let levelled = InfoDebug.sections(song: song, level: .album, key: 0, decisions: LevelDecisions(), live: nil,
                                          engine: InfoDebug.Engine(), album: nil)
        #expect(Self.table(levelled)["Normalization"] == [LevelWords.notKnownYet])
        #expect(Self.table([InfoSection(title: "", rows: [InfoRow(label: "Format", value: LevelWords.debugFormat(FileFacts(song: Self.song(suffix: nil, contentType: nil, rate: nil, bits: nil, channels: nil))))])])["Format"]
                == ["Navidrome didn't say"])
    }

    @Test func theEnginesOwnRows() {
        let engine = InfoDebug.Engine(outputRate: 48000, outputName: "AirPods Pro", latency: 0.0214, conversion: "24-bit 192 kHz FLAC file → 48 kHz output",
                                      laneRate: 44100, laneChannels: 2, nodeRate: 48000, converting: true, aheadSeconds: 1.84, lastStartSeconds: 0.306)
        let rows = InfoDebug.engineRows(engine)
        #expect(rows.map(\.label) == ["Output", "Conversion", "Lane", "Buffered ahead", "Last start"])
        #expect(rows.map(\.value) == ["48 kHz · AirPods Pro · 21 ms latency", "24-bit 192 kHz FLAC file → 48 kHz output",
                                      "44.1 kHz stereo, converted to 48 kHz", "1.8 s", "0.31 s from the tap to sound"])
        #expect(InfoDebug.laneLine(rate: 48000, channels: 2, nodeRate: 48000, converting: false) == "48 kHz stereo, no conversion")
        #expect(InfoDebug.laneLine(rate: 88200, channels: 1, nodeRate: 48000, converting: true) == "88.2 kHz mono, converted to 48 kHz")
        #expect(InfoDebug.laneLine(rate: 22050, channels: 6, nodeRate: 48000, converting: true) == "22.05 kHz 6 channels, converted to 48 kHz")
        //? what the engine hasn't said is left out, never guessed
        #expect(InfoDebug.engineRows(InfoDebug.Engine()) == [])
        #expect(InfoDebug.outputLine(rate: nil, name: " ", latency: nil) == nil)
        #expect(InfoDebug.outputLine(rate: 44100, name: nil, latency: nil) == "44.1 kHz")
        #expect(InfoDebug.engineRows(InfoDebug.Engine(aheadSeconds: .nan, lastStartSeconds: -1)) == [])
    }

    // ------------------------------------------------------------ About's inputs

    @Test func aboutReadsTheQueueEntryNotAFreshSong() {
        //? the entry's album and cover came from the album (toQueueTrack); a Song with none would say ""
        let song = Song(id: "t1", title: "Roads")
        let entry = QueueTrack(song: song, albumId: "al", albumName: "Dummy", albumArtist: "Portishead", albumCoverArt: "cv")
        let track = AboutTrack(entry: entry)
        #expect(track == AboutTrack(id: "t1", title: "Roads", artist: "Portishead", album: "Dummy", albumId: "al", coverArt: "cv", duration: 0))
        #expect(AboutTrack(song: song).album == "")
        let about = AboutCard.about(track: track, album: nil)
        #expect(about.album?.title == "Dummy" && about.album?.coverArt == "cv" && about.artist?.name == "Portishead")
    }

    /// Every About case of info-vectors.json whose album the routes' Album model reads: its card from
    /// `AboutAlbum(album:)` is the TypeScript's. The cases whose album the model reads apart from About's own JS
    /// Number() reading are named, and nothing else may differ.
    @Test func theAlbumModelGivesTheWebsCards() throws {
        let cases = try LevelVectors.info().aboutRows
        let raw = try JSONDecoder().decode(JSONValue.self, from: Fixtures.data("levels/info-vectors.json"))
        guard let rawCases = raw["aboutRows"]?.array else {
            Issue.record("info-vectors.json has no aboutRows")
            return
        }
        #expect(rawCases.count == cases.count)
        //? a playlist's stub (`partial`) is Phase 4's: the routes' model hasn't the field, and Phase 1 plays none
        var compared = 0
        var stubs: [String] = []
        for (each, rawCase) in zip(cases, rawCases) {
            guard let albumJSON = rawCase["album"], !albumJSON.isNull else { continue }
            if albumJSON["partial"]?.bool == true {
                stubs.append(each.name)
                continue
            }
            let data = try JSONEncoder().encode(Reencoded(albumJSON))
            let album = try JSONDecoder().decode(Album.self, from: data)
            let details = each.details.map { AboutDetails(song: $0.song, present: $0.store?.present) }
            let about = AboutCard.about(track: each.track.aboutTrack, album: AboutAlbum(album: album), details: details, folders: each.folders)
            #expect(about == each.about, "\(each.name)")
            compared += 1
        }
        #expect(stubs == ["played from a playlist's stub", "a playlist's stub of two discs"])
        #expect(compared >= 40)
    }

    @Test func aPressingRowIsTheBridgesRow() throws {
        let text = #"{"present": [{"id": 4, "path": "Pink Floyd/Wish You Were Here (1975)", "edition": "Experience edition", "year": "2011", "formats": ["flac"]}]}"#
        let store = try JSONDecoder().decode(StoreAlbum.self, from: Data(text.utf8))
        #expect(store.present.map(PressingRow.init(row:)) == [PressingRow(path: "Pink Floyd/Wish You Were Here (1975)", edition: "Experience edition",
                                                                         year: "2011", formats: ["flac"])])
    }

    @Test func aQueueEntryAsASongKeepsWhatTheLevelRulesRead() {
        let entry = QueueTrack(id: "t1", title: "Roads", artist: "Portishead", album: "Dummy", albumId: "al", coverArt: "cv", duration: 305,
                               contentType: "audio/flac", suffix: "flac", sampleRate: 44100, bitDepth: 16, channels: 2, level: .album)
        let song = Song(queued: entry)
        #expect(song.isFlac && song.albumId == "al" && song.id == "t1")
        #expect(FileFacts(song: song) == FileFacts(suffix: "flac", contentType: "audio/flac", sampleRate: 44100, bitDepth: 16, channels: 2))
        #expect(FileFacts(song: Song(queued: QueueTrack(id: "x", title: "", artist: "", album: ""))) == FileFacts())
    }

    // ------------------------------------------------------------ Now Playing's words

    @Test func theMoreButtonSaysWhatTheMenuHolds() {
        #expect(NowPlayingWords.more(hasAlbum: true) == "More: info, go to album")
        #expect(NowPlayingWords.more(hasAlbum: false) == "More: info")
    }
}

/// A fixture's JSON written out again, for a model to decode.
private struct Reencoded: Encodable {
    let value: JSONValue

    init(_ value: JSONValue) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null: try container.encodeNil()
        case .bool(let flag): try container.encode(flag)
        case .number(let number): try container.encode(number)
        case .string(let text): try container.encode(text)
        case .array(let items): try container.encode(items.map(Reencoded.init))
        case .object(let fields): try container.encode(fields.mapValues(Reencoded.init))
        }
    }
}
