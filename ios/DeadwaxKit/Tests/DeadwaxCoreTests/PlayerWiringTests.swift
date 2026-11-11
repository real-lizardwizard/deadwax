import Foundation
import Testing
@testable import DeadwaxCore

/// The rules the app's player wiring adds to the Core (PlayerWiring.swift, LevelDecisions.carry): the phone's own,
/// with no TypeScript behind them, so each is held here by hand.
@Suite struct PlayerWiringTests {
    static func track(_ id: String, album: String? = "al", suffix: String? = "flac", level: Level? = .album) -> QueueTrack {
        QueueTrack(id: id, title: "T \(id)", artist: "A", album: "Al", albumId: album, coverArt: "c", duration: 200,
                   contentType: suffix == "flac" ? "audio/flac" : "audio/mpeg", suffix: suffix, sampleRate: 44_100,
                   bitDepth: 16, channels: 2, level: level)
    }

    // MARK: Song(track:)

    @Test func anEntrysSongReadsAsTheEntry() {
        let entry = Self.track("s1")
        let song = Song(track: entry, size: 1234)
        #expect(song.id == "s1" && song.title == "T s1" && song.artist == "A" && song.album == "Al")
        #expect(song.albumId == "al" && song.coverArt == "c" && song.duration == 200 && song.size == 1234)
        #expect(song.suffix == "flac" && song.contentType == "audio/flac")
        #expect(song.samplingRate == 44_100 && song.bitDepth == 16 && song.channelCount == 2)
        //? what the engine and the cache read of it is the entry's
        #expect(song.isFlac == Loudness.isFlac(suffix: entry.suffix, contentType: entry.contentType))
        #expect(StreamCache.name(for: song) == "s1.flac")
        #expect(StreamFormat.format(for: song) == "raw")
        //? made back into an entry, it is the same entry
        #expect(QueueTrack(song: song, albumId: "al", albumName: "Al", level: .album) == entry)
    }

    @Test func whatAnEntryLeftOutIsNil() {
        let bare = QueueTrack(id: "s9", title: "", artist: "", album: "")
        let song = Song(track: bare)
        #expect(song.title == nil && song.artist == nil && song.album == nil && song.albumId == nil)
        #expect(song.duration == nil && song.samplingRate == nil && song.bitDepth == nil && song.channelCount == nil)
        #expect(song.size == nil && song.suffix == nil)
        //? the cache names it as Phase 0 named a song with no suffix
        #expect(StreamCache.name(for: song) == "s9.bin")
        #expect(QueueTrack(song: song, albumId: "", albumName: "").title == "")
    }

    // MARK: the albums the queue wants

    @Test func theSongPlayingAndTheNextThreeWithALevelAreWanted() {
        let tracks = [Self.track("s0", album: "a0"), Self.track("s1", album: "a1"), Self.track("s2", album: "a2"),
                      Self.track("s3", album: "a3"), Self.track("s4", album: "a4"), Self.track("s5", album: "a5")]
        #expect(LoudnessAsking.wanted(tracks, playing: 0) == ["a0", "a1", "a2", "a3"])
        #expect(LoudnessAsking.wanted(tracks, playing: 4) == ["a4", "a5"])
        #expect(LoudnessAsking.wanted(tracks, playing: 5) == ["a5"])
        //? nothing playing, nothing wanted
        #expect(LoudnessAsking.wanted(tracks, playing: -1) == [])
        #expect(LoudnessAsking.wanted(tracks, playing: 6) == [])
        #expect(LoudnessAsking.wanted([], playing: 0) == [])
    }

    @Test func onlyAnEntryWithALevelThatIsAFlacWantsItsAlbum() {
        let tracks = [Self.track("s0", album: "a0", level: nil), Self.track("s1", album: "a1", level: nil),
                      Self.track("s2", album: "a2", suffix: "mp3"), Self.track("s3", album: "a3", level: .track),
                      Self.track("s4", album: nil), Self.track("s5", album: ""), Self.track("s6", album: "a6")]
        //? Off (no level) wants nothing and isn't counted among the next three; an MP3 with a level is counted, and
        //? wants nothing; an entry with no album id wants nothing
        #expect(LoudnessAsking.wanted(tracks, playing: 0) == ["a3"])
        #expect(LoudnessAsking.wanted(tracks, playing: 3) == ["a3", "a6"])
    }

    @Test func anAlbumIsWantedOnce() {
        let tracks = (0..<6).map { Self.track("s\($0)", album: $0 < 4 ? "al" : "b") }
        #expect(LoudnessAsking.wanted(tracks, playing: 0) == ["al"])
        #expect(LoudnessAsking.wanted(tracks, playing: 1) == ["al", "b"])
    }

    // MARK: a warm's answer kept

    static let unmeasured = AlbumLoudness(state: .unmeasured, why: "not measured yet", album: AlbumLevel(songs: 3), songs: [
        SongLoudness(id: "s1", state: .measured, loudnessLufs: -9, peak: 0.5),
        SongLoudness(id: "s2", state: .unmeasured),
        SongLoudness(id: "s3", state: .notLevelled, why: "too short"),
    ])

    @Test func aWarmThatSaysMeasuringIsKeptAsMeasuring() throws {
        let kept = try #require(LoudnessAsking.warmed(Self.unmeasured, said: WarmAnswer(state: "measuring")))
        #expect(kept.state == .measuring && kept.why == nil && kept.album == Self.unmeasured.album)
        #expect(kept.songs.map(\.state) == [.measured, .measuring, .notLevelled])
        #expect(kept.songs[0] == Self.unmeasured.songs[0] && kept.songs[2] == Self.unmeasured.songs[2])
        //? the first song of a play waits on it now, at either level - it didn't on the read's answer
        let song = Song(id: "s2", albumId: "al", suffix: "flac")
        #expect(!LevelWait.shouldWait(level: .album, song: song, answer: Self.unmeasured, waited: 0))
        #expect(!LevelWait.shouldWait(level: .track, song: song, answer: Self.unmeasured, waited: 0))
        #expect(LevelWait.shouldWait(level: .album, song: song, answer: kept, waited: 0))
        #expect(LevelWait.shouldWait(level: .track, song: song, answer: kept, waited: 0))
        //? and what it is fixed at, should the 20 s run out, says it was being measured
        #expect(decide(level: .album, song: song, answer: kept) == .plain(.album, songs: 3, measured: 1))
    }

    @Test func anyOtherWarmAnswerKeepsWhatIsThere() {
        for said in ["busy", "not_levelled", "measured", "", "later"] {
            #expect(LoudnessAsking.warmed(Self.unmeasured, said: WarmAnswer(state: said)) == nil, "\(said)")
        }
        let measured = AlbumLoudness(state: .measured, album: AlbumLevel(loudnessLufs: -10, peak: 0.5, songs: 1),
                                     songs: [SongLoudness(id: "s1", state: .measured, loudnessLufs: -10, peak: 0.5)])
        #expect(LoudnessAsking.warmed(measured, said: WarmAnswer(state: "measuring")) == nil)
        #expect(LoudnessAsking.warmed(nil, said: WarmAnswer(state: "measuring")) == nil)
    }

    // MARK: the wait, ended by a failed read

    @Test func aFailedReadWithNoAnswerEndsTheWait() {
        let song = Song(id: "s2", albumId: "al", suffix: "flac")
        #expect(LevelWait.shouldWait(level: .album, song: song, answer: nil, waited: 0, readFailed: false))
        #expect(!LevelWait.shouldWait(level: .album, song: song, answer: nil, waited: 0, readFailed: true))
        //? with a measuring answer in hand, a failed read since changes nothing
        let measuring = LoudnessAsking.warmed(Self.unmeasured, said: WarmAnswer(state: "measuring"))
        #expect(LevelWait.shouldWait(level: .album, song: song, answer: measuring, waited: 3, readFailed: true))
        //? and the 20 s still end it
        #expect(!LevelWait.shouldWait(level: .album, song: song, answer: measuring, waited: 20, readFailed: false))
        #expect(!LevelWait.shouldWait(level: nil, song: song, answer: nil, waited: 0, readFailed: false))
    }

    // MARK: a failure in the phone's engine

    @Test func aSignedOutOrThePhonesOwnFailureStopsTheQueue() {
        for intends in [true, false] {
            for retried in [true, false] {
                #expect(PlayerWords.afterEngineFailure(.signedOut, intendsToPlay: intends, retried: retried) == .stop)
                #expect(PlayerWords.afterEngineFailure(.other, intendsToPlay: intends, retried: retried) == .stop)
            }
        }
    }

    @Test func everyOtherFailureIsAfterFailures() {
        for failure in [PlayerWords.Failure.network, .decode, .unsupported] {
            for intends in [true, false] {
                for retried in [true, false] {
                    #expect(PlayerWords.afterEngineFailure(failure, intendsToPlay: intends, retried: retried)
                            == PlayerWords.afterFailure(failure, intendsToPlay: intends, retried: retried))
                }
            }
        }
        //? which is: a load failure asked again once, then passed over; a decode passed over; paused, stopped
        #expect(PlayerWords.afterEngineFailure(.network, intendsToPlay: true, retried: false) == .retry)
        #expect(PlayerWords.afterEngineFailure(.network, intendsToPlay: true, retried: true) == .skip)
        #expect(PlayerWords.afterEngineFailure(.decode, intendsToPlay: true, retried: false) == .skip)
        #expect(PlayerWords.afterEngineFailure(.unsupported, intendsToPlay: false, retried: false) == .stop)
    }

    // MARK: a decision carried to a new key

    @Test func aReKeyedEntryKeepsItsDecision() {
        let measuring = DecisionTests.answer(.measuring, album: AlbumLevel(songs: 3), songs: [
            SongLoudness(id: "s1", state: .measuring)])
        var decisions = LevelDecisions()
        let song = Song(id: "s1", albumId: "al", suffix: "flac")
        let made = decisions.decide(key: 4, level: .track, song: song, answer: measuring)
        #expect(made == .plain(.track, songs: 1, measured: 0))
        decisions.carry(from: 4, to: 9)
        #expect(decisions.decided(9) == made)
        //? opened again under its new key once the song is measured: still the level it was heard at
        #expect(decisions.decide(key: 9, level: .track, song: song, answer: QueueDecisionTests.measured) == made)
        //? a key with a decision of its own keeps it; an old key with none carries nothing
        let other = decisions.decide(key: 10, level: .track, song: Song(id: "s3", albumId: "al", suffix: "flac"),
                                     answer: QueueDecisionTests.measured)
        decisions.carry(from: 4, to: 10)
        #expect(decisions.decided(10) == other)
        decisions.carry(from: 77, to: 78)
        #expect(decisions.decided(78) == nil)
        decisions.carry(from: 4, to: 4)
        #expect(decisions.decided(4) == made)
    }

    @Test func anEditKeepsTheDecisionsOfWhatTheEngineKept() {
        let song = { (id: String) in Song(id: id, albumId: "al", suffix: "flac") }
        var decisions = LevelDecisions()
        let a = decisions.decide(key: 1, level: .track, song: song("s1"), answer: QueueDecisionTests.measured)
        let b = decisions.decide(key: 2, level: .track, song: song("s2"), answer: QueueDecisionTests.measured)
        let c = decisions.decide(key: 3, level: .track, song: song("s3"), answer: QueueDecisionTests.measured)
        let entry = { (key: Int, id: String) in QueueEntry(key: key, track: Self.track(id, level: .track)) }
        let old = [entry(0, "s0"), entry(1, "s1"), entry(2, "s2"), entry(3, "s3")]
        //? Shuffle off: the same songs after the one heard, new keys - each kept entry's decision under its new key
        decisions.carry(from: old, to: [entry(0, "s0"), entry(11, "s1"), entry(12, "s2"), entry(13, "s3")], after: 0)
        #expect(decisions.decided(11) == a && decisions.decided(12) == b && decisions.decided(13) == c)
        //? the walk stops at the first song that differs: nothing after it carried
        var stopped = LevelDecisions()
        _ = stopped.decide(key: 1, level: .track, song: song("s1"), answer: QueueDecisionTests.measured)
        _ = stopped.decide(key: 3, level: .track, song: song("s3"), answer: QueueDecisionTests.measured)
        stopped.carry(from: old, to: [entry(0, "s0"), entry(21, "s1"), entry(22, "s9"), entry(23, "s3")], after: 0)
        #expect(stopped.decided(21) != nil && stopped.decided(22) == nil && stopped.decided(23) == nil)
        //? the same song at another level is other audio: not carried
        var levelled = LevelDecisions()
        _ = levelled.decide(key: 1, level: .track, song: song("s1"), answer: QueueDecisionTests.measured)
        levelled.carry(from: old, to: [entry(0, "s0"), QueueEntry(key: 31, track: Self.track("s1", level: .album))], after: 0)
        #expect(levelled.decided(31) == nil)
        //? nothing before the entry heard, nor the entry heard itself, is walked; a list too short ends the walk
        var before = LevelDecisions()
        _ = before.decide(key: 0, level: .track, song: song("s0"), answer: QueueDecisionTests.measured)
        before.carry(from: old, to: [entry(40, "s0"), entry(41, "s1")], after: 0)
        #expect(before.decided(40) == nil)
        before.carry(from: old, to: [], after: 0)
        before.carry(from: old, to: old, after: 5)
        #expect(before.entries.count == 1)
    }
}
