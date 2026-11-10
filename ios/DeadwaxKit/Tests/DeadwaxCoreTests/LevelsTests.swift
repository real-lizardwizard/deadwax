import Foundation
import Testing
@testable import DeadwaxCore

/// Normalization's rule on the phone: the server's gain_for() and the web's setting and level table, each held
/// to its own source's answers (Fixtures/levels/levels-vectors.json) and to the cases tests/test_loudness.py and
/// the sims pin.
@Suite struct GainTests {
    @Test func everyServerCaseGivesTheServersGain() throws {
        let python = try LevelVectors.levels().python_gain_for
        #expect(python.cases.count >= 41)
        for each in python.cases {
            let gain = gainFor(loudness: each.loudness_lufs ?? -.infinity, peak: each.peak, reserveDb: each.reserve_db)
            #expect(gain.gainDb == each.gain_db, "\(each.name): gain")
            #expect(gain.wantedDb == each.wanted_db, "\(each.name): wanted")
            #expect(gain.held == each.held, "\(each.name): held")
            if let peakDb = each.peak_db {
                #expect(abs(gain.peakDb - peakDb) <= 1e-12, "\(each.name): peak dB")
            } else {
                #expect(gain.peakDb == -.infinity, "\(each.name): a peak of 0 is -inf dB")
            }
            let multiplier = gainMultiplier(gain.gainDb)
            let expected = Float(each.multiplier_f32)
            #expect(Double(expected) == each.multiplier_f32, "\(each.name): the vector's Float32 is one")
            #expect(abs(multiplier - expected) <= expected.ulp, "\(each.name): multiplier \(multiplier) against \(expected)")
            //? the rule keeps every sample at or under full scale, in the very Float the phone multiplies by
            #expect(Float(each.peak) * multiplier <= 1, "\(each.name): the peak stays inside full scale")
        }
    }

    @Test func theConstantsAreTheServers() throws {
        let python = try LevelVectors.levels().python_gain_for
        #expect(Loudness.referenceLUFS == python.REFERENCE_LUFS)
        #expect(Loudness.fullDB == python.FULL_DB)
        #expect("\(Loudness.fullDB)" == python.FULL_DB_repr)
        //? the literal is the formula's value, to within this platform's log10
        let formula = 20 * log10(Double((1 << 23) - 1) / Double(1 << 23))
        #expect(abs(formula - Loudness.fullDB) <= 1e-18)
        #expect(Loudness.algorithm == 1)
    }

    // ported from tests/test_loudness.py

    @Test func silenceHasNoLoudnessAndAsksForNoGain() {
        let gain = gainFor(loudness: -.infinity, peak: 0)
        #expect(gain.gainDb == 0 && gain.wantedDb == 0 && !gain.held)
        #expect(gain.peakDb == -.infinity)
    }

    @Test func aGainTakesASongToTheReference() {
        let gain = gainFor(loudness: -10.6, peak: pow(10, -1.0 / 20))
        #expect(gain.gainDb == -7.4)
        #expect(!gain.held)
    }

    @Test func aGainIsHeldUnderThePeak() {
        //? -24 LUFS wants +6, a peak at -3.5 dBFS allows 3.49 (3.5 less the 24-bit limit's millionths, rounded down)
        let gain = gainFor(loudness: -24, peak: pow(10, -3.5 / 20))
        #expect(gain.wantedDb == 6)
        #expect(gain.held)
        #expect(gain.gainDb == 3.49)
    }

    @Test func theResamplesRoomIsReservedInsideTheLimit() {
        let unheld = gainFor(loudness: -20, peak: pow(10, -6.0 / 20))
        #expect(unheld.gainDb == 2.0 && !unheld.held)
        #expect(gainFor(loudness: -20, peak: pow(10, -6.0 / 20), reserveDb: 3).gainDb == 2.0, "room enough for both")
        let reserved = gainFor(loudness: -20, peak: pow(10, -4.0 / 20), reserveDb: 3)
        #expect(reserved.held && reserved.gainDb == 0.99)
        //? the phone keeps no reserve: the same song is not held there
        let phone = gainFor(loudness: -20, peak: pow(10, -4.0 / 20))
        #expect(phone.gainDb == 2.0 && !phone.held)
    }

    @Test func theGainIsRoundedDownToTheHundredth() {
        func gain(wanting wanted: Double) -> Double { gainFor(loudness: Loudness.referenceLUFS - wanted, peak: 0.01).gainDb }
        #expect(gain(wanting: -7.42) == -7.42)
        #expect(gain(wanting: -7.425) == -7.43)
        #expect(gain(wanting: -7.4299999) == -7.43)
        #expect(gain(wanting: 1.2) == 1.2)
        #expect(gain(wanting: 0.0) == 0.0)
        #expect(gain(wanting: -0.001) == -0.01)
        #expect(gain(wanting: 3.999) == 3.99)
    }

    @Test func noInputCanTakeASamplePast24BitsAfterTheRule() {
        //? tests/test_loudness.py's sweep with a seed of this test's own: every peak a 24-bit or 16-bit sample can
        //? have, every loudness and reserve - the peak quantised at the gain the rule gives stays inside 24 bits,
        //? either sign; and the Float the phone multiplies by never takes the peak past full scale
        var generator = SplitMix(seed: 23)
        let full = Double(1 << 23)
        var peaks: [Double] = (0..<3000).map { _ in Double(generator.next() % UInt64((1 << 23) - 1) + 1) }
        peaks += [1, full - 1, full]
        peaks += (0..<500).map { _ in Double((generator.next() % UInt64((1 << 15) - 1) + 1) << 8) }
        var failures: [String] = []
        for raw in peaks {
            let value = raw / full
            for lufs in [-60.0, -30, -18, -5] {
                for reserve in [0.0, 3.0] {
                    let gain = gainFor(loudness: lufs, peak: value, reserveDb: reserve)
                    let scale = full * pow(10, gain.gainDb / 20)
                    for sign in [1.0, -1.0] {
                        let quantised = ((sign * value) * scale).rounded(.toNearestOrEven)
                        if quantised < -full || quantised > full - 1 { failures.append("\(raw) \(lufs) \(reserve) \(sign): \(quantised)") }
                    }
                    if Float(value) * gainMultiplier(gain.gainDb) > 1 { failures.append("\(raw) \(lufs) \(reserve): the Float") }
                }
            }
        }
        #expect(peaks.count == 3503)
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    @Test func aMultiplierIsOneFloatOfTheDoubleWorkedOut() {
        #expect(gainMultiplier(0) == 1)
        #expect(gainMultiplier(-6.02) == Float(pow(10.0, -6.02 / 20)))
        #expect(gainMultiplier(20) == 10)
    }
}

/// A small, fixed generator (SplitMix64), so the sweep is the same on every platform and every run.
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct NormalizationRuleTests {
    @Test func theSettingIsReadAsTheWebReadsIt() {
        #expect(Normalization.read(nil) == .auto)
        #expect(Normalization.read("junk") == .auto)
        #expect(Normalization.read("auto") == .auto)
        #expect(Normalization.read("song") == .song)
        #expect(Normalization.read("album") == .album)
        #expect(Normalization.read("off") == .off)
        #expect(Normalization.read("Song") == .auto)
        #expect(Normalization.default == .auto)
        #expect(Normalization.storageKey == "deadwax-player-normalization")
        #expect(Normalization.allCases.map(\.rawValue) == ["auto", "song", "album", "off"])
    }

    @Test func theChoicesAreTheWebsWordsButOffsClause() throws {
        let web = try LevelVectors.levels().typescript
        #expect(web.constants.DEFAULT_NORMALIZATION == Normalization.default.rawValue)
        #expect(web.settings.map(\.value) == Normalization.allCases.map(\.rawValue))
        for choice in web.settings {
            let mine = try #require(Normalization(rawValue: choice.value))
            #expect(mine.label == choice.label)
            if mine == .off {
                //? D3: Off's line without the Maximum quality clause, the phone having no such setting - the rest
                //? the web's, so a change to the web's line fails here until it is looked at
                #expect(choice.note.hasSuffix(", unless Maximum quality converts it."))
                #expect(mine.note == choice.note.replacingOccurrences(of: ", unless Maximum quality converts it.", with: "."))
            } else {
                #expect(mine.note == choice.note)
            }
        }
        #expect(Normalization.off.note.contains("bit for bit"))
        #expect(!Normalization.off.note.contains("before this setting"))
        #expect(!Normalization.allCases.contains { $0.note.contains("Maximum quality") })
        #expect(!Normalization.allCases.contains { $0.note.contains("\u{2014}") || $0.note.contains("Deadwax") })
    }

    @Test func levelForIsTheWebsTable() throws {
        let cases = try LevelVectors.levels().typescript.levelFor
        #expect(cases.count == 8)
        for each in cases {
            let setting = try #require(Normalization(rawValue: each.setting))
            let queued = try #require(QueuedAs(rawValue: each.as))
            #expect(levelFor(setting, queued) == Level.named(each.level), "\(each.setting) \(each.as)")
        }
        #expect(levelFor(.auto, .album) == .album)
        #expect(levelFor(.auto, .songs) == .track)
        #expect(levelFor(.off, .album) == nil)
    }

    @Test func relevelIsTheWebsTable() throws {
        let cases = try LevelVectors.levels().typescript.relevel
        #expect(cases.count == 12)
        for each in cases {
            let setting = try #require(Normalization(rawValue: each.setting))
            #expect(relevel(Level.named(each.saved), setting) == Level.named(each.level), "\(each.setting) \(each.saved ?? "none")")
        }
        #expect(relevel(nil, .auto) == .track)
    }

    @Test func isFlacIsTheWebs() throws {
        let cases = try LevelVectors.levels().typescript.isFlac
        #expect(cases.count >= 9)
        for each in cases {
            #expect(Loudness.isFlac(suffix: each.suffix, contentType: each.contentType) == each.isFlac,
                    "\(each.suffix ?? "nil") \(each.contentType ?? "nil")")
        }
        #expect(Song(id: "x", suffix: "FLAC").isFlac)
        #expect(!Song(id: "x", suffix: "mp3", contentType: "audio/mpeg").isFlac)
    }

    @Test func levelsIsTheWebs() throws {
        let cases = try LevelVectors.levels().typescript.levels
        #expect(cases.count >= 24)
        for each in cases {
            #expect(Loudness.levels(suffix: each.suffix, contentType: each.contentType, level: Level.named(each.level), format: each.format) == each.levels)
        }
    }

    @Test func jsFixedIsJavaScriptsToFixed() throws {
        let cases = try LevelVectors.levels().typescript.toFixed
        #expect(cases.count > 400)
        for each in cases {
            #expect(jsFixed(each.value, each.digits) == each.fixed, "\(each.value).toFixed(\(each.digits))")
        }
        //? where printf parts from it: the ties
        #expect(jsFixed(0.25, 1) == "0.3" && String(format: "%.1f", 0.25) == "0.2")
        #expect(jsFixed(3.25, 1) == "3.3")
        #expect(jsFixed(0.125, 2) == "0.13")
        #expect(jsFixed(2.5, 0) == "3")
        #expect(jsFixed(-0.004, 2) == "-0.00")
        #expect(LevelWords.lufs(-10.25) == "-10.3 LUFS")
    }
}

@Suite struct LoudnessAnswerTests {
    static let example = """
    {"reference_lufs": -18.0, "algorithm": 1, "state": "measured", "why": null, "whole": true,
     "album": {"loudness_lufs": -11.437218417201565, "peak": 0.98876953125, "songs": 3},
     "songs": [
      {"id": "a1", "state": "measured", "loudness_lufs": -12.80316, "peak": 0.98876953125, "why": null},
      {"id": "a2", "state": "measured", "loudness_lufs": -10.94121, "peak": 0.9710693359375, "why": null},
      {"id": "a3", "state": "measured", "loudness_lufs": null, "peak": 0.0, "why": null},
      {"id": "a4", "state": "not_levelled", "loudness_lufs": null, "peak": null, "why": "it isn't a FLAC file"}
     ]}
    """

    @Test func theRoutesExampleDecodes() throws {
        let answer = try JSONDecoder().decode(AlbumLoudness.self, from: Data(Self.example.utf8))
        #expect(answer.referenceLufs == -18 && answer.algorithm == 1 && answer.state == .measured && answer.whole)
        #expect(answer.album == AlbumLevel(loudnessLufs: -11.437218417201565, peak: 0.98876953125, songs: 3))
        #expect(answer.songs.map(\.state) == [.measured, .measured, .measured, .notLevelled])
        #expect(answer.song("a3") == SongLoudness(id: "a3", state: .measured, loudnessLufs: nil, peak: 0))
        #expect(answer.song("a4")?.why == "it isn't a FLAC file")
        //? the phone's album gain from it (levels.md 3.1)
        let applied = decide(level: .album, song: Song(id: "a1", albumId: "al", suffix: "flac"), answer: answer)
        guard case .gain(let gain, .album, songs: 3) = applied else {
            Issue.record("expected the album's gain, got \(applied)")
            return
        }
        #expect(gain.gainDb == -6.57)
    }

    @Test func aStateThisAppDoesntKnowPlaysAsItIs() throws {
        let text = Self.example.replacingOccurrences(of: "\"state\": \"measured\", \"why\": null, \"whole\"", with: "\"state\": \"queued\", \"why\": null, \"whole\"")
            .replacingOccurrences(of: "{\"id\": \"a1\", \"state\": \"measured\"", with: "{\"id\": \"a1\", \"state\": \"resampling\"")
        let answer = try JSONDecoder().decode(AlbumLoudness.self, from: Data(text.utf8))
        #expect(answer.state == .unmeasured)
        #expect(answer.song("a1")?.state == .unmeasured)
        #expect(decide(level: .album, song: Song(id: "a1", suffix: "flac"), answer: answer).multiplier == nil)
    }

    @Test func aWarmsAnswerDecodes() throws {
        let warm = try JSONDecoder().decode(WarmAnswer.self, from: Data(#"{"state": "busy"}"#.utf8))
        #expect(warm == WarmAnswer(state: "busy"))
    }

    @Test func aLevelAnswerReadsTheWebsShape() throws {
        let text = #"{"level": "album", "state": "plain", "gain_db": null, "wanted_db": null, "loudness_lufs": null, "peak_db": null, "held": false, "songs": 3, "measured_songs": 1, "why": null}"#
        let answer = try JSONDecoder().decode(LevelAnswer.self, from: Data(text.utf8))
        #expect(answer == LevelAnswer(level: .album, state: .plain, songs: 3, measuredSongs: 1))
    }
}

/// The phone's decision, a branch at a time (levels.md 4.1).
@Suite struct DecisionTests {
    static let flac = Song(id: "s2", albumId: "al", suffix: "flac", contentType: "audio/flac")

    static func answer(_ state: LoudnessState, album: AlbumLevel = AlbumLevel(loudnessLufs: -10.6, peak: 0.5, songs: 3),
                       songs: [SongLoudness]? = nil, why: String? = nil, whole: Bool = true) -> AlbumLoudness {
        AlbumLoudness(state: state, why: why, whole: whole, album: album, songs: songs ?? [
            SongLoudness(id: "s1", state: .measured, loudnessLufs: -9, peak: 0.5),
            SongLoudness(id: "s2", state: .measured, loudnessLufs: -14, peak: 0.25),
            SongLoudness(id: "s3", state: .measured, loudnessLufs: -11, peak: 0.4),
        ])
    }

    @Test func offAndNotFlacComeFirst() {
        #expect(decide(level: nil, song: Self.flac, answer: Self.answer(.measured)) == .off)
        #expect(decide(level: .album, song: Song(id: "s2", suffix: "mp3", contentType: "audio/mpeg"), answer: Self.answer(.measured)) == .notFlac)
        #expect(decide(level: .album, song: Self.flac, answer: nil) == .unanswered(.album))
        #expect(AppliedLevel.off.multiplier == nil && AppliedLevel.notFlac.multiplier == nil && AppliedLevel.unanswered(.track).multiplier == nil)
    }

    @Test func anAlbumMeasuredIsPlayedAtItsGain() {
        let applied = decide(level: .album, song: Self.flac, answer: Self.answer(.measured))
        #expect(applied == .gain(gainFor(loudness: -10.6, peak: 0.5), .album, songs: 3))
        #expect(applied.multiplier == gainMultiplier(-7.4))
        #expect(applied.level == .album)
    }

    @Test func aSongMeasuredIsPlayedAtItsOwnGain() {
        let applied = decide(level: .track, song: Self.flac, answer: Self.answer(.measuring))
        #expect(applied == .gain(gainFor(loudness: -14, peak: 0.25), .track, songs: 1))
        #expect(applied.multiplier == gainMultiplier(gainFor(loudness: -14, peak: 0.25).gainDb))
    }

    @Test func theSongsNotLevelledBeatsAMeasuredAlbum() {
        let songs = [SongLoudness(id: "s1", state: .measured, loudnessLufs: -9, peak: 0.5),
                     SongLoudness(id: "s2", state: .notLevelled, why: "its file can't be read as FLAC by deadwax (20- or 32-bit)")]
        let applied = decide(level: .album, song: Self.flac, answer: Self.answer(.measured, songs: songs))
        #expect(applied == .notLevelled(why: "its file can't be read as FLAC by deadwax (20- or 32-bit)", .album))
        #expect(applied.multiplier == nil)
    }

    @Test func silenceIsAGainOfNothingAndNoMultiply() {
        let silent = Self.answer(.measured, album: AlbumLevel(loudnessLufs: nil, peak: 0, songs: 2))
        let applied = decide(level: .album, song: Self.flac, answer: silent)
        #expect(applied == .gain(Gain(gainDb: 0, wantedDb: 0, loudness: -.infinity, peakDb: -.infinity, held: false), .album, songs: 2))
        #expect(applied.multiplier == nil)
    }

    @Test func aSongMissingFromTheAnswerPlaysAsItIs() {
        let other = Song(id: "s9", albumId: "al", suffix: "flac")
        #expect(decide(level: .album, song: other, answer: Self.answer(.measured)) == .unmeasured(.album, songs: 3))
        #expect(decide(level: .track, song: other, answer: Self.answer(.measured)) == .unmeasured(.track, songs: 1))
    }

    @Test func anAlbumBeingMeasuredPlaysAsItIsThisTime() {
        let songs = [SongLoudness(id: "s1", state: .measured, loudnessLufs: -9, peak: 0.5), SongLoudness(id: "s2", state: .measuring),
                     SongLoudness(id: "s3", state: .unmeasured), SongLoudness(id: "s4", state: .notLevelled, why: "it isn't a FLAC file")]
        let answer = Self.answer(.measuring, album: AlbumLevel(songs: 3), songs: songs)
        #expect(decide(level: .album, song: Self.flac, answer: answer) == .plain(.album, songs: 3, measured: 1))
        #expect(decide(level: .track, song: Self.flac, answer: answer) == .plain(.track, songs: 1, measured: 0))
        #expect(decide(level: .track, song: Song(id: "s3", suffix: "flac"), answer: answer) == .unmeasured(.track, songs: 1))
        #expect(decide(level: .track, song: Song(id: "s1", suffix: "flac"), answer: answer) == .gain(gainFor(loudness: -9, peak: 0.5), .track, songs: 1))
    }

    @Test func anAlbumNotMeasuredOrRefused() {
        #expect(decide(level: .album, song: Self.flac, answer: Self.answer(.unmeasured, album: AlbumLevel(songs: 3))) == .unmeasured(.album, songs: 3))
        let refused = Self.answer(.notLevelled, album: AlbumLevel(songs: 0), why: "none of its songs can be levelled")
        #expect(decide(level: .album, song: Self.flac, answer: refused) == .notLevelled(why: "none of its songs can be levelled", .album))
    }

    @Test func wholeIsNeverRead() {
        let answer = Self.answer(.measured, whole: false)
        #expect(decide(level: .album, song: Self.flac, answer: answer) == decide(level: .album, song: Self.flac, answer: Self.answer(.measured)))
    }

    @Test func aGainOfExactlyNothingMultipliesNothing() {
        let atReference = AppliedLevel.gain(gainFor(loudness: -18, peak: 0.5), .album, songs: 1)
        #expect(atReference.multiplier == nil)
        let tiny = AppliedLevel.gain(gainFor(loudness: -18.01, peak: 0.5), .album, songs: 1)
        #expect(tiny.multiplier == gainMultiplier(0.01))
    }
}

/// One queue's decisions (D3): an entry once, an album once.
@Suite struct QueueDecisionTests {
    static let measured = DecisionTests.answer(.measured)
    static let measuring = DecisionTests.answer(.measuring, album: AlbumLevel(songs: 3), songs: [
        SongLoudness(id: "s1", state: .measured, loudnessLufs: -9, peak: 0.5), SongLoudness(id: "s2", state: .measuring),
        SongLoudness(id: "s3", state: .unmeasured)])

    static func song(_ id: String, album: String = "al", suffix: String = "flac") -> Song {
        Song(id: id, albumId: album, suffix: suffix)
    }

    @Test func anEntryKeepsItsDecisionThroughEveryOpen() {
        var decisions = LevelDecisions()
        let first = decisions.decide(key: 1, level: .track, song: Self.song("s2"), answer: Self.measuring)
        #expect(first == .plain(.track, songs: 1, measured: 0))
        //? a seek, a resume, a new route: the same entry opened again, its album measured since - the same decision
        #expect(decisions.decide(key: 1, level: .track, song: Self.song("s2"), answer: Self.measured) == first)
        #expect(decisions.decided(1) == first)
        #expect(decisions.decided(2) == nil)
    }

    @Test func anAlbumIsDecidedFromOneAnswerForTheQueuesLife() {
        var decisions = LevelDecisions()
        //? the first song of the album began while it was being measured: as it is, and so the whole album
        let first = decisions.decide(key: 1, level: .album, song: Self.song("s1"), answer: Self.measuring)
        #expect(first == .plain(.album, songs: 3, measured: 1))
        #expect(decisions.fixed(album: "al"))
        let second = decisions.decide(key: 2, level: .album, song: Self.song("s2"), answer: Self.measured)
        #expect(second == .plain(.album, songs: 3, measured: 1))
        #expect(second.multiplier == nil)
        //? a track-level entry of the same album is its own
        #expect(decisions.decide(key: 3, level: .track, song: Self.song("s3"), answer: Self.measured) == .gain(gainFor(loudness: -11, peak: 0.4), .track, songs: 1))
        //? another album is decided apart
        let other = decisions.decide(key: 4, level: .album, song: Self.song("s1", album: "al-2"), answer: Self.measured)
        #expect(other == .gain(gainFor(loudness: -10.6, peak: 0.5), .album, songs: 3))
        //? a new play is a new queue: the album's next play picks the gain up
        var next = LevelDecisions()
        #expect(next.decide(key: 1, level: .album, song: Self.song("s1"), answer: Self.measured).multiplier == gainMultiplier(-7.4))
    }

    @Test func anAlbumWithNoAnswerPlaysAsItIsThroughout() {
        var decisions = LevelDecisions()
        #expect(decisions.decide(key: 1, level: .album, song: Self.song("s1"), answer: nil) == .unanswered(.album))
        #expect(decisions.decide(key: 2, level: .album, song: Self.song("s2"), answer: Self.measured) == .unanswered(.album))
    }

    @Test func anAlbumAtOneGainKeepsItThroughout() {
        var decisions = LevelDecisions()
        let first = decisions.decide(key: 1, level: .album, song: Self.song("s1"), answer: Self.measured)
        let later = decisions.decide(key: 2, level: .album, song: Self.song("s3"), answer: Self.measuring)
        #expect(first == later)
        #expect(first.multiplier == later.multiplier)
    }

    @Test func aSongThatIsntAFlacFixesNothing() {
        var decisions = LevelDecisions()
        #expect(decisions.decide(key: 1, level: .album, song: Self.song("m1", suffix: "mp3"), answer: nil) == .notFlac)
        #expect(!decisions.fixed(album: "al"))
        #expect(decisions.decide(key: 2, level: .album, song: Self.song("s1"), answer: Self.measured).multiplier == gainMultiplier(-7.4))
        //? and Off fixes nothing either
        #expect(decisions.decide(key: 3, level: nil, song: Self.song("s1", album: "al-3"), answer: nil) == .off)
        #expect(!decisions.fixed(album: "al-3"))
    }
}

@Suite struct LevelWaitTests {
    static let flac = Song(id: "s2", albumId: "al", suffix: "flac")

    @Test func onlyALevelledFlacWaitsAndOnlyWhileItsMeasureIsComing() {
        let measuring = QueueDecisionTests.measuring
        #expect(LevelWait.shouldWait(level: .album, song: Self.flac, answer: nil, waited: 0))
        #expect(LevelWait.shouldWait(level: .album, song: Self.flac, answer: measuring, waited: 19.9))
        #expect(!LevelWait.shouldWait(level: .album, song: Self.flac, answer: measuring, waited: 20))
        #expect(!LevelWait.shouldWait(level: nil, song: Self.flac, answer: nil, waited: 0))
        #expect(!LevelWait.shouldWait(level: .album, song: Song(id: "s2", suffix: "mp3"), answer: nil, waited: 0))
        #expect(!LevelWait.shouldWait(level: .album, song: Self.flac, answer: QueueDecisionTests.measured, waited: 0))
        #expect(!LevelWait.shouldWait(level: .album, song: Self.flac, answer: DecisionTests.answer(.unmeasured), waited: 0))
        //? a song's own level waits on the song, not the album
        #expect(LevelWait.shouldWait(level: .track, song: Self.flac, answer: measuring, waited: 0))
        #expect(!LevelWait.shouldWait(level: .track, song: Song(id: "s1", suffix: "flac"), answer: measuring, waited: 0))
        //? one deadwax won't level, or one the answer doesn't list, is decided the same however long it waits
        #expect(!LevelWait.shouldWait(level: .album, song: Song(id: "s9", suffix: "flac"), answer: measuring, waited: 0))
        let refused = DecisionTests.answer(.measuring, songs: [SongLoudness(id: "s2", state: .notLevelled, why: "x")])
        #expect(!LevelWait.shouldWait(level: .album, song: Self.flac, answer: refused, waited: 0))
        #expect(LevelWait.limitSeconds == 20 && LevelWait.pollSeconds == 1)
    }
}

@Suite struct LoudnessAskingTests {
    @Test func whatFollowsAReadAndAWarm() {
        #expect(LoudnessAsking.afterRead(DecisionTests.answer(.measured)) == .done)
        #expect(LoudnessAsking.afterRead(DecisionTests.answer(.notLevelled)) == .done)
        #expect(LoudnessAsking.afterRead(DecisionTests.answer(.measuring)) == .readAgain)
        #expect(LoudnessAsking.afterRead(DecisionTests.answer(.unmeasured)) == .warm)
        #expect(LoudnessAsking.afterWarm(WarmAnswer(state: "measuring")) == .readAgain)
        #expect(LoudnessAsking.afterWarm(WarmAnswer(state: "busy")) == .warm)
        #expect(LoudnessAsking.afterWarm(WarmAnswer(state: "not_levelled")) == .readAgain)
    }

    @Test func howLongAnAnswerIsBelieved() {
        #expect(LoudnessAsking.fresh(DecisionTests.answer(.measured), fetchedAt: 100, now: 699))
        #expect(!LoudnessAsking.fresh(DecisionTests.answer(.measured), fetchedAt: 100, now: 700))
        #expect(LoudnessAsking.fresh(DecisionTests.answer(.notLevelled), fetchedAt: 100, now: 100))
        #expect(!LoudnessAsking.fresh(DecisionTests.answer(.measuring), fetchedAt: 100, now: 100))
        #expect(!LoudnessAsking.fresh(DecisionTests.answer(.unmeasured), fetchedAt: 100, now: 100))
        #expect(LoudnessAsking.againSeconds == 5 && LoudnessAsking.wantedAhead == 3 && LoudnessAsking.keptSeconds == 600)
    }
}
