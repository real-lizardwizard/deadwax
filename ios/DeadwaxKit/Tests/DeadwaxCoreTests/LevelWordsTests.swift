import Foundation
import Testing
@testable import DeadwaxCore

/// Info's Normalization and Format words: the web's, held to the TypeScript's own answers, and the phone's own
/// lines for what it applied (D3, D8).
@Suite struct LevelWordsTests {
    @Test func debugAndAboutSayWhatTheWebSays() throws {
        let cases = try LevelVectors.levels().typescript.words
        #expect(cases.count >= 40)
        for each in cases {
            let track = each.track
            #expect(LevelWords.describeLevel(suffix: track.suffix, contentType: track.contentType, level: track.level,
                                             format: each.format, answer: each.answer) == each.debug, "\(each.name): Debug")
            #expect(LevelWords.aboutLevel(suffix: track.suffix, contentType: track.contentType, level: track.level,
                                          format: each.format, answer: each.answer) == each.about, "\(each.name): About")
        }
    }

    @Test func theFormatIsTheWebs() throws {
        let cases = try LevelVectors.levels().typescript.formatWords
        #expect(cases.count >= 10)
        for each in cases {
            #expect(LevelWords.formatWords(each.track.file) == each.words, "\(each.track.file)")
            #expect(LevelWords.debugFormat(each.track.file) == (each.words.isEmpty ? "Navidrome didn't say" : each.words))
        }
    }

    @Test func theSoundGroupIsTheWebs() throws {
        let cases = try LevelVectors.levels().typescript.soundRows
        #expect(cases.count >= 4)
        for each in cases {
            #expect(LevelWords.soundRows(file: each.track.file, level: each.track.level, gapless: each.gapless, format: each.format,
                                         answer: each.level) == each.rows, "\(each.track.id)")
        }
    }

    @Test func gainsAndLoudnessAreSaidAsTheWebSaysThem() throws {
        let web = try LevelVectors.levels().typescript
        for each in web.signedDb {
            #expect(LevelWords.signedDb(each.value) == each.words, "\(each.value)")
        }
        for each in web.volumeChange {
            #expect(LevelWords.volumeChange(each.gain) == each.words, "\(each.gain)")
        }
        #expect(LevelWords.signedDb(-0.004) == "+0.00 dB")
        #expect(LevelWords.volumeChange(-0.04) == "no change needed")
    }

    @Test func theWordsAreTheWebsConstants() throws {
        let constants = try LevelVectors.levels().typescript.constants
        #expect(LevelWords.soundTitle == constants.SOUND_TITLE)
        #expect(LevelWords.checking == constants.LEVEL_CHECKING)
        #expect(LevelWords.notKnownYet == constants.LEVEL_NOT_KNOWN_YET)
        #expect(LevelWords.notKnown == constants.NOT_KNOWN)
        #expect(Set(constants.OFF_WORDS.keys) == Set(LevelWords.Off.allCases.map(\.rawValue)))
        for off in LevelWords.Off.allCases {
            #expect(off.words == constants.OFF_WORDS[off.rawValue])
        }
    }

    @Test func aboutNeverSaysDebugsWords() throws {
        //? info.sim.cjs's rule for the web's About, over every About line here - the web's and the phone's own
        var lines = try LevelVectors.levels().typescript.words.map(\.about)
        lines += Level.allCases.map(LevelWords.unansweredAbout)
        lines += PhoneWordsTests.everyAbout()
        #expect(lines.count > 60)
        let banned = ["LUFS", "levelled", "numpy", "soundfile", "MiB", "STREAMINFO", "Navidrome", "hasn't said"]
        for line in lines {
            #expect(!banned.contains { line.contains($0) }, "\(line)")
            #expect(!Self.hundredths(line), "\(line)")
        }
        #expect(Self.hundredths("Album, -7.42 dB") && !Self.hundredths("3.6 dB quieter") && Self.hundredths("x10.25"))
    }

    /// `/\d\.\d\d/`: a number to the hundredth, without NSRegularExpression (which isn't the same on Linux).
    static func hundredths(_ line: String) -> Bool {
        let units = Array(line.unicodeScalars)
        func digit(_ i: Int) -> Bool { i < units.count && (48...57).contains(units[i].value) }
        return units.indices.contains { i in digit(i) && i + 1 < units.count && units[i + 1] == "." && digit(i + 2) && digit(i + 3) }
    }
}

/// The phone's Normalization in Info: the web's words, written from what the phone applied.
@Suite struct PhoneWordsTests {
    static let flac = Song(id: "s2", albumId: "al", suffix: "flac", contentType: "audio/flac", samplingRate: 96000, bitDepth: 24,
                           channelCount: 2)

    static func measured(loudness: Double = -10.6, peak: Double = 0.5) -> AlbumLoudness {
        DecisionTests.answer(.measured, album: AlbumLevel(loudnessLufs: loudness, peak: peak, songs: 3))
    }

    /// Every About line the phone's cases below can say, for the banned-words check.
    static func everyAbout() -> [String] {
        let song = flac
        var lines: [String] = []
        for level in [nil, Level.album, .track] {
            for answer in [nil, measured(), QueueDecisionTests.measuring, DecisionTests.answer(.unmeasured),
                           DecisionTests.answer(.notLevelled, why: "none of its songs can be levelled")] {
                lines.append(LevelWords.about(song: song, level: level, decided: nil, live: answer))
                let decided = decide(level: level, song: song, answer: answer)
                lines.append(LevelWords.about(song: song, level: level, decided: decided, live: nil))
            }
        }
        return lines
    }

    @Test func aGainAppliedIsSaidAsTheWebSaysTheServers() {
        let applied = decide(level: .album, song: Self.flac, answer: Self.measured())
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: applied, live: nil) == "Album volume matching, 7.4 dB quieter")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: applied, live: nil) == "Album, -7.40 dB \u{00B7} the album at -10.6 LUFS")
        let song = decide(level: .track, song: Self.flac, answer: Self.measured())
        #expect(LevelWords.about(song: Self.flac, level: .track, decided: song, live: nil) == "Song volume matching, 4.0 dB quieter")
        #expect(LevelWords.debug(song: Self.flac, level: .track, decided: song, live: nil) == "Song, -4.00 dB \u{00B7} the song at -14.0 LUFS")
    }

    @Test func theNumbersAreRoundedAsTheServerRoundsItsOwn() {
        //? -10.249 to two places is -10.25, which the web's toFixed(1) says as -10.3 (a tie, rounded away): the
        //? phone says what the web would have, not -10.2
        let applied = decide(level: .album, song: Self.flac, answer: Self.measured(loudness: -10.249))
        let answer = levelAnswer(applied)
        #expect(answer?.loudnessLufs == -10.25)
        #expect(answer?.gainDb == -7.76)
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: applied, live: nil) == "Album, -7.76 dB \u{00B7} the album at -10.3 LUFS")
        //? held: what it wanted, to two places as the server gives it
        let held = decide(level: .album, song: Self.flac, answer: Self.measured(loudness: -24, peak: pow(10, -3.5 / 20)))
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: held, live: nil) == "Album, +3.49 dB \u{00B7} held there by its peak (it wanted +6.00)")
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: held, live: nil) == "Album volume matching, 3.5 dB louder - as loud as it can go without distorting")
    }

    @Test func aSilentAlbumHasNothingToAdjust() {
        let silent = DecisionTests.answer(.measured, album: AlbumLevel(loudnessLufs: nil, peak: 0, songs: 3))
        let applied = decide(level: .album, song: Self.flac, answer: silent)
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: applied, live: nil) == "Album volume matching - nothing to adjust, the album is silent")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: applied, live: nil) == "Album, +0.00 dB \u{00B7} the album is silent")
    }

    @Test func aSongNotBegunSaysWhatDeadwaxSaysNow() {
        let measuring = QueueDecisionTests.measuring
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: nil, live: measuring) == "Measuring the album\u{2026} (1 of 3 songs)")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: nil, live: measuring) == "Measuring its album\u{2026} (1 of 3 songs)")
        #expect(LevelWords.about(song: Self.flac, level: .track, decided: nil, live: measuring) == "Measuring the song\u{2026}")
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: nil, live: nil) == LevelWords.checking)
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: nil, live: nil) == LevelWords.notKnownYet)
        //? once it plays, what was applied - not what deadwax says since
        let plain = decide(level: .album, song: Self.flac, answer: measuring)
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: plain, live: Self.measured()) == "Not this time - the album was still being measured")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: plain, live: Self.measured()) == "Played as it is this time - its album was still being measured")
    }

    @Test func noAnswerInTimeHasTheD3Lines() {
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: .unanswered(.album), live: Self.measured())
                == "Not this time - the album's volume couldn't be checked")
        #expect(LevelWords.about(song: Self.flac, level: .track, decided: .unanswered(.track), live: nil)
                == "Not this time - the song's volume couldn't be checked")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: .unanswered(.album), live: nil)
                == "Played as it is this time - deadwax didn't say in time")
    }

    @Test func offNotFlacAndRefusedAreTheWebs() {
        #expect(LevelWords.about(song: Self.flac, level: nil, decided: .off, live: Self.measured()) == "Off")
        #expect(LevelWords.debug(song: Self.flac, level: nil, decided: .off, live: nil) == "Off")
        let mp3 = Song(id: "m", suffix: "mp3", contentType: "audio/mpeg")
        #expect(LevelWords.about(song: mp3, level: .album, decided: .notFlac, live: nil) == "Off for this song - only FLAC songs are adjusted")
        #expect(LevelWords.debug(song: mp3, level: .album, decided: .notFlac, live: nil) == "Not levelled - MP3 songs play as they are")
        let refused = decide(level: .album, song: Self.flac, answer: DecisionTests.answer(.measured, songs: [
            SongLoudness(id: "s2", state: .notLevelled, why: "its file can't be read as FLAC by deadwax (20- or 32-bit)")]))
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: refused, live: nil) == "Off for this song - its file can't be measured")
        #expect(LevelWords.debug(song: Self.flac, level: .album, decided: refused, live: nil)
                == "Not levelled - its file can't be read as FLAC by deadwax (20- or 32-bit)")
        let unmeasured = decide(level: .album, song: Self.flac, answer: DecisionTests.answer(.unmeasured))
        #expect(LevelWords.about(song: Self.flac, level: .album, decided: unmeasured, live: nil) == "Not this time - the album hasn't been measured yet")
    }

    @Test func theSoundGroupOnThePhone() {
        let applied = decide(level: .album, song: Self.flac, answer: Self.measured())
        #expect(LevelWords.soundRows(song: Self.flac, level: .album, decided: applied, live: nil) == [
            SoundRow(label: "Format", value: "FLAC, 24-bit, 96 kHz, stereo"),
            SoundRow(label: "Gapless", value: "On"),
            SoundRow(label: "Normalization", value: "Album volume matching, 7.4 dB quieter"),
        ])
        let bare = Song(id: "x")
        #expect(LevelWords.soundRows(song: bare, level: nil, decided: nil, live: nil) == [
            SoundRow(label: "Format", value: "Not known"),
            SoundRow(label: "Gapless", value: "On"),
            SoundRow(label: "Normalization", value: "Off"),
        ])
        #expect(LevelWords.formatWords(FileFacts(song: Song(id: "y", contentType: "audio/x-flac; q=1", samplingRate: 44100, channelCount: 1)))
                == "FLAC, 44.1 kHz, mono")
    }
}
