import Foundation
import Testing
@testable import DeadwaxCore

@Suite struct LaneTimelineTests {
    /// Song A (1000 frames) then song B (500) on one node, joined end to end.
    func twoSongs() -> LaneTimeline {
        var lane = LaneTimeline()
        #expect(lane.begin(id: 1) == 0)
        lane.extend(id: 1, frames: 600)
        lane.extend(id: 1, frames: 400)
        #expect(lane.begin(id: 2) == 1000)
        lane.extend(id: 2, frames: 500)
        return lane
    }

    @Test func theJoinIsTheFirstFrameOfTheNextSong() throws {
        let lane = twoSongs()
        let last = try #require(lane.locate(999))
        #expect(last.entry.id == 1 && last.songFrame == 999)
        let first = try #require(lane.locate(1000))
        #expect(first.entry.id == 2 && first.songFrame == 0)
        #expect(lane.locate(1250)?.songFrame == 250)
    }

    @Test func beforeTheStartAndPastTheEnd() {
        let lane = twoSongs()
        #expect(lane.locate(-512)?.entry.id == 1)
        #expect(lane.locate(-512)?.songFrame == 0)
        #expect(lane.locate(9999)?.entry.id == 2)
        #expect(lane.locate(9999)?.songFrame == 500)
        #expect(LaneTimeline().locate(0) == nil)
    }

    @Test func aSeekStartsPartWayIn() {
        var lane = LaneTimeline()
        lane.begin(id: 7, songOffset: 44_100 * 60)
        lane.extend(id: 7, frames: 22_050)
        let expected: Int64 = 44_100 * 60 + 100
        #expect(lane.locate(100)?.songFrame == expected)
    }

    @Test func beginningANewSongClosesTheOneBefore() {
        var lane = twoSongs()
        #expect(lane.entry(id: 1)?.closed == true)
        lane.extend(id: 1, frames: 10)
        #expect(lane.entry(id: 1)?.frames == 1000)
        #expect(lane.end == 1500)
    }

    @Test func playedEntriesAreForgottenButTheLastIsKept() {
        var lane = twoSongs()
        lane.forget(before: 1000)
        #expect(lane.entries.map(\.id) == [2])
        lane.forget(before: 99_999)
        #expect(lane.entries.map(\.id) == [2])
    }
}

@Suite struct FLACStreamInfoTests {
    /// "fLaC" and a STREAMINFO block with these values, packed as the format packs them.
    static func header(rate: Int, channels: Int, bits: Int, total: Int64, md5: [UInt8], last: Bool = true) -> Data {
        var s = [UInt8](repeating: 0, count: 34)
        s[0] = 0x10; s[1] = 0x00 // min block 4096
        s[2] = 0x10; s[3] = 0x00 // max block 4096
        s[10] = UInt8((rate >> 12) & 0xFF)
        s[11] = UInt8((rate >> 4) & 0xFF)
        s[12] = UInt8(((rate & 0x0F) << 4) | (((channels - 1) & 0x07) << 1) | (((bits - 1) >> 4) & 0x01))
        s[13] = UInt8((((bits - 1) & 0x0F) << 4) | Int((total >> 32) & 0x0F))
        s[14] = UInt8((total >> 24) & 0xFF)
        s[15] = UInt8((total >> 16) & 0xFF)
        s[16] = UInt8((total >> 8) & 0xFF)
        s[17] = UInt8(total & 0xFF)
        for (index, byte) in md5.enumerated() { s[18 + index] = byte }
        var data = Data("fLaC".utf8)
        data.append(contentsOf: [last ? 0x80 : 0x00, 0x00, 0x00, 34])
        data.append(contentsOf: s)
        return data
    }

    @Test func aTwentyFourOneNinetyTwoFile() throws {
        let md5 = (0..<16).map { UInt8($0 * 7 + 1) }
        let info = try #require(FLACStreamInfo.parse(Self.header(rate: 192_000, channels: 2, bits: 24,
                                                                  total: 0x9_1234_5678, md5: md5)))
        #expect(info.sampleRate == 192_000)
        #expect(info.channels == 2)
        #expect(info.bitsPerSample == 24)
        #expect(info.totalSamples == 0x9_1234_5678)
        #expect(info.md5 == md5 && info.md5Known)
        #expect(info.minBlockSize == 4096 && info.maxBlockSize == 4096)
    }

    @Test func aCdFileAndItsLength() throws {
        let info = try #require(FLACStreamInfo.parse(Self.header(rate: 44_100, channels: 2, bits: 16,
                                                                  total: 176_400, md5: [UInt8](repeating: 0, count: 16), last: false)))
        #expect(info.sampleRate == 44_100 && info.bitsPerSample == 16)
        #expect(info.duration == 4.0)
        #expect(!info.md5Known)
    }

    @Test func anId3TagInFrontIsSkipped() throws {
        var data = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]) // 128 bytes of tag
        data.append(Data(repeating: 0, count: 128))
        data.append(Self.header(rate: 96_000, channels: 1, bits: 24, total: 1, md5: []))
        #expect(FLACStreamInfo.parse(data)?.sampleRate == 96_000)
        #expect(FLACStreamInfo.parse(data)?.channels == 1)
    }

    @Test func notAFlacOrTooShort() {
        #expect(FLACStreamInfo.parse(Data("RIFF....WAVEfmt ".utf8)) == nil)
        #expect(FLACStreamInfo.parse(Self.header(rate: 44_100, channels: 2, bits: 16, total: 1, md5: []).prefix(30)) == nil)
    }
}

@Suite struct FormatsTests {
    @Test func theFileAsItIsUnlessIOSCantDecodeIt() {
        #expect(StreamFormat.format(for: Song(id: "a", suffix: "flac", contentType: "audio/flac")) == "raw")
        #expect(StreamFormat.format(for: Song(id: "a", suffix: "m4a")) == "raw")
        #expect(StreamFormat.format(for: Song(id: "a")) == "raw")
        for suffix in ["ogg", "OGA", "opus", "wma"] {
            #expect(StreamFormat.format(for: Song(id: "a", suffix: suffix)) == "mp3")
        }
        #expect(StreamFormat.format(for: Song(id: "a", contentType: "audio/ogg")) == "mp3")
        #expect(StreamFormat.suffix(for: Song(id: "a", suffix: "opus")) == "mp3")
        #expect(StreamFormat.suffix(for: Song(id: "a", suffix: "FLAC")) == "flac")
    }

    @Test func ratesInWords() {
        #expect(RateWords.kHz(44_100) == "44.1 kHz")
        #expect(RateWords.kHz(48_000) == "48 kHz")
        #expect(RateWords.kHz(192_000) == "192 kHz")
        #expect(RateWords.kHz(88_200) == "88.2 kHz")
    }

    @Test func theHiResReadout() {
        #expect(RateWords.readout(fileRate: 192_000, bits: 24, codec: "flac", outputRate: 48_000)
                == "24-bit 192 kHz FLAC file \u{2192} 48 kHz output")
        #expect(RateWords.readout(fileRate: 48_000, bits: nil, codec: nil, outputRate: 48_000)
                == "48 kHz file \u{2192} 48 kHz output, no rate conversion")
        #expect(RateWords.readout(fileRate: 44_100, bits: 16, codec: "flac", outputRate: nil) == "16-bit 44.1 kHz FLAC file")
    }

    @Test func fileNamesAreSafe() {
        #expect(LocalFiles.name(songID: "add42f0e6531", suffix: "flac") == "add42f0e6531.flac")
        #expect(LocalFiles.name(songID: "../../etc/passwd", suffix: "fl/ac") == "etcpasswd.flac")
        #expect(LocalFiles.name(songID: "abc", suffix: nil) == "abc.bin")
        #expect(LocalFiles.name(songID: "///", suffix: "flac") == nil)
    }

    @Test func aDownloadsLengthIsTheSongs() {
        #expect(LocalFiles.lengthMatches(804_602, song: Song(id: "a", size: 804_602)))
        #expect(!LocalFiles.lengthMatches(804_601, song: Song(id: "a", size: 804_602)))
        #expect(LocalFiles.lengthMatches(10, song: Song(id: "a")))
        #expect(!LocalFiles.lengthMatches(0, song: Song(id: "a")))
    }
}

@Suite struct StartPointTests {
    @Test func aFrameIsExactAtItsOwnRate() {
        let expected: Int64 = 44_100 * 160 + 37
        #expect(StartPoint.frame(expected, rate: 44_100).frame(at: 44_100) == expected)
        // no round trip through seconds: frame / rate * rate isn't always the frame in floating point
        let odd: Int64 = 12_345_679
        #expect(StartPoint.frame(odd, rate: 192_000).frame(at: 192_000) == odd)
        #expect(StartPoint.beginning.frame(at: 96_000) == 0)
    }

    @Test func secondsAreTurnedIntoFramesAtTheFilesRate() {
        let cd: Int64 = 2_646_000
        let hiRes: Int64 = 11_520_000
        #expect(StartPoint.seconds(60).frame(at: 44_100) == cd)
        #expect(StartPoint.seconds(60).frame(at: 192_000) == hiRes)
        #expect(StartPoint.seconds(60).seconds == 60)
    }

    @Test func aFrameAtAnotherRateIsTheSameTime() {
        let at48: Int64 = 480_000
        #expect(StartPoint.frame(441_000, rate: 44_100).frame(at: 48_000) == at48)
        #expect(StartPoint.frame(441_000, rate: 44_100).seconds == 10)
    }

    @Test func nothingBeforeTheStart() {
        #expect(StartPoint.seconds(-3).frame(at: 44_100) == 0)
        #expect(StartPoint.seconds(.nan).frame(at: 44_100) == 0)
        #expect(StartPoint.seconds(.infinity).seconds == 0)
        #expect(StartPoint.frame(-5, rate: 44_100).frame(at: 44_100) == 0)
        #expect(StartPoint.seconds(5).frame(at: 0) == 0)
    }
}
