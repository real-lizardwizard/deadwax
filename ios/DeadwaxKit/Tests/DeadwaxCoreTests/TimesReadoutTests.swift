import Testing
@testable import DeadwaxCore

// Now Playing's readout between the scrubber's two times (27 Nov, notes/ios.md "Now Playing's readout under the
// scrubber (27 Nov)"): its words are BarDisplay's readout - the place and the format joined with " · ", either alone -
// and it goes between the times while it clears the wider of them on both sides, else on a line of its own under them.
@Suite struct TimesReadoutTests {
    // MARK: the words

    /// An album of 11 songs, the third playing - its songs naming a format, or none.
    private func album(format: Bool) -> UpNextQueue {
        let songs = (1...11).map { (n: Int) -> QueueTrack in
            QueueTrack(id: "s\(n)", title: "Song \(n)", artist: "Wilco", album: "Wilco (The Album)", albumId: "al",
                       duration: 200, contentType: format ? "audio/flac" : nil, suffix: format ? "flac" : nil,
                       sampleRate: format ? 44100 : 0, bitDepth: format ? 16 : 0, channels: 2)
        }
        return startUpNext(songs, start: 2)
    }

    @Test func bothJoinWithADot() {
        #expect(BarDisplay.readout(album(format: true)) == "3 of 11 · FLAC 16/44.1")
        #expect(DiscHeadings.dot == " · ")
        // VoiceOver's words as they were: a comma between, the format said in full
        #expect(BarDisplay.readoutSpoken(album(format: true)) == "3 of 11, FLAC, 16-bit, 44.1 kHz")
    }

    @Test func thePlaceAloneHasNoDot() {
        // a song naming no format: its place alone
        let queue = album(format: false)
        #expect(BarDisplay.format(queue.tracks[queue.index]) == nil)
        #expect(BarDisplay.readout(queue) == "3 of 11")
        #expect(BarDisplay.readoutSpoken(queue) == "3 of 11")
    }

    @Test func theFormatAloneHasNoDot() {
        // a song added with Play Next has no place: its format alone
        let extra = QueueTrack(id: "x", title: "Added", artist: "Someone", album: "Else", suffix: "mp3")
        var queue = withNext(album(format: true), [extra])
        queue.index = 3
        #expect(BarDisplay.place(queue) == nil)
        #expect(BarDisplay.readout(queue) == "MP3")
        #expect(BarDisplay.readoutSpoken(queue) == "MP3")
    }

    @Test func neitherIsNoReadout() {
        let extra = QueueTrack(id: "x", title: "Added", artist: "Someone", album: "Else")
        var queue = withNext(album(format: false), [extra])
        queue.index = 3
        #expect(BarDisplay.readout(queue) == nil)
        #expect(BarDisplay.readoutSpoken(queue) == nil)
    }

    // MARK: the times at their widest

    @Test func theTimesAtTheirWidestAreTheEndAndTheStart() {
        #expect(TimesReadout.widest(length: 221) == ["3:41", "-3:41"])
        // the figures a clock gains past ten minutes, and an hour (minutes on, as the clocks say it)
        #expect(TimesReadout.widest(length: 612.4) == ["10:12", "-10:12"])
        #expect(TimesReadout.widest(length: 3723) == ["62:03", "-62:03"])
        // no length yet: the clocks' own words for none
        #expect(TimesReadout.widest(length: 0) == ["0:00", "-0:00"])
        // what the clocks draw is never wider: every second of the song, each clock's words no longer than these
        let length = 612.0
        let widest = TimesReadout.widest(length: length)
        for second in stride(from: 0.0, through: length, by: 1) {
            #expect(PlayerWords.elapsed(shown: second).count <= widest[0].count)
            #expect(PlayerWords.remaining(shown: second, length: length).count <= widest[1].count)
        }
    }

    // MARK: between the times, or under them

    @Test func itGoesBetweenWhileItClearsBothTimes() {
        // exactly at the edge: between; a hair over: under
        #expect(TimesReadout.fitsBetween(readout: 100, time: 40, width: 200, clear: 10))
        #expect(!TimesReadout.fitsBetween(readout: 100.5, time: 40, width: 200, clear: 10))
        #expect(!TimesReadout.fitsBetween(readout: 100, time: 40.25, width: 200, clear: 10))
        #expect(!TimesReadout.fitsBetween(readout: 100, time: 40, width: 199.5, clear: 10))
        // nothing to draw always fits
        #expect(TimesReadout.fitsBetween(readout: 0, time: 40, width: 200, clear: 10))
    }

    @Test func onANarrowPhoneItFoldsOnlyAtTheLargestSizes() {
        // Courier Prime's every figure 0.6 of its size; the column 327 on a 375-pt phone (24 either side). A 3:41
        // song's "3 of 11 · FLAC 16/44.1" (22) and "-3:41" (5): between at the default 12 and at xxLarge's 15,
        // under at xxxLarge's 17 - and a library shuffle's "1,612 of 2,100 · FLAC 24/176.4" (30) under from xLarge's 13
        func fits(_ readout: String, _ time: String, at points: Double) -> Bool {
            TimesReadout.fitsBetween(readout: 0.6 * points * Double(readout.count),
                                     time: 0.6 * points * Double(time.count), width: 327, clear: 10)
        }
        let album = "3 of 11 · FLAC 16/44.1"
        #expect(fits(album, "-3:41", at: 12) && fits(album, "-3:41", at: 15))
        #expect(!fits(album, "-3:41", at: 17))
        let shuffle = "1,612 of 2,100 · FLAC 24/176.4"
        #expect(fits(shuffle, "-3:41", at: 12))
        #expect(!fits(shuffle, "-3:41", at: 13))
    }
}
