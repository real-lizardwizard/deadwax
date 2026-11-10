import Foundation
import Testing
@testable import DeadwaxCore

// The streaming cache's rules and its folder (a temp folder: FileManager is Linux's too), and the
// heard position's arithmetic - the parts of the engine's Phase 1 that need no AVFAudio.

/// A fresh folder for one test, deleted after.
private func withFolder(_ body: (StreamCacheFolder) throws -> Void) rethrows {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deadwax-stream-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(StreamCacheFolder(url: url))
}

private func write(_ folder: StreamCacheFolder, _ name: String, bytes: Int, played: Date? = nil) {
    FileManager.default.createFile(atPath: folder.url(for: name).path, contents: Data(repeating: 7, count: bytes))
    if let played { folder.touch(name, now: played) }
}

private func names(_ folder: StreamCacheFolder) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []).sorted()
}

private let flac = Song(id: "song-1", suffix: "flac", size: 1_000)

@Suite struct StreamCacheTests {
    @Test func theNamesAreTheSongsAndTheirParts() {
        #expect(StreamCache.name(for: flac) == "song-1.flac")
        #expect(StreamCache.name(for: Song(id: "o", suffix: "opus")) == "o.mp3", "a transcode arrives as mp3")
        #expect(StreamCache.name(for: Song(id: "../..")) == nil)
        #expect(StreamCache.partName("song-1.flac") == "song-1.flac.part")
        #expect(StreamCache.isSongName("song-1.flac"))
        #expect(StreamCache.isSongName("A_b-9.bin"))
        #expect(!StreamCache.isSongName("song-1.flac.part"), "a part is never a song")
        #expect(!StreamCache.isSongName("song.part"))
        #expect(!StreamCache.isSongName(".DS_Store"))
        #expect(!StreamCache.isSongName("noextension"))
        #expect(!StreamCache.isSongName("a b.flac"))
        #expect(!StreamCache.isSongName("song.FLAC"), "LocalFiles lowercases the suffix")
        #expect(!StreamCache.isSongName("song.waytoolongsuffix"))
        #expect(!StreamCache.isSongName(String(repeating: "x", count: 129) + ".flac"))
    }

    @Test func partialsAreDeletedAtLaunch() {
        withFolder { folder in
            write(folder, "song-1.flac", bytes: 10)
            write(folder, "song-2.flac.part", bytes: 5)
            write(folder, ".DS_Store", bytes: 1)
            write(folder, "not a song", bytes: 1)
            try? FileManager.default.createDirectory(at: folder.url(for: "stray"), withIntermediateDirectories: true)
            let gone = folder.sweep()
            #expect(gone == [".DS_Store", "not a song", "song-2.flac.part", "stray"])
            #expect(names(folder) == ["song-1.flac"], "the complete song is kept across launches")
        }
    }

    @Test func aLaunchMakesTheFolder() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadwax-stream-\(UUID().uuidString)/stream", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(StreamCacheFolder(url: url).sweep().isEmpty)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func aCompleteFileIsReused() {
        withFolder { folder in
            let then = Date(timeIntervalSince1970: 1_000_000)
            write(folder, "song-1.flac", bytes: 1_000, played: then)
            let now = Date(timeIntervalSince1970: 2_000_000)
            #expect(folder.reusable(flac, now: now) == folder.url(for: "song-1.flac"))
            let played = folder.files().first { $0.name == "song-1.flac" }?.lastPlayed
            #expect(played.map { abs($0.timeIntervalSince(now)) < 1 } == true, "marked as played now")
            #expect(StreamCache.reuse(bytes: 1_000, song: flac) == .play)
            #expect(StreamCache.reuse(bytes: 5, song: Song(id: "x", suffix: "flac")) == .play, "no size said: any length")
            #expect(StreamCache.reuse(bytes: nil, song: flac) == StreamCache.Reuse.none)
        }
    }

    @Test func aFileOfAnotherSizeIsDropped() {
        withFolder { folder in
            write(folder, "song-1.flac", bytes: 999)
            #expect(StreamCache.reuse(bytes: 999, song: flac) == .replace)
            #expect(folder.reusable(flac) == nil)
            #expect(names(folder).isEmpty, "deleted, so the song is streamed afresh")
            #expect(StreamCache.reuse(bytes: 0, song: Song(id: "x", suffix: "flac")) == .replace, "an empty file never plays")
            #expect(folder.reusable(Song(id: "missing", suffix: "flac")) == nil)
        }
    }

    @Test func aTranscodeIsKept() {
        withFolder { folder in
            let opus = Song(id: "o", suffix: "opus", size: 5_000_000)
            write(folder, "o.mp3", bytes: 1_234)
            // Navidrome's size is the original's: a transcode's length never matches it
            #expect(StreamCache.reuse(bytes: 1_234, song: opus) == .play)
            #expect(folder.reusable(opus) == folder.url(for: "o.mp3"))
            #expect(StreamCache.reuse(bytes: 0, song: opus) == .replace)
        }
    }

    @Test func theLeastRecentlyPlayedGoesFirst() {
        let day = { (n: Double) in Date(timeIntervalSince1970: n * 86_400) }
        let files = [
            StreamCache.File(name: "new.flac", bytes: 600, lastPlayed: day(3)),
            StreamCache.File(name: "old.flac", bytes: 600, lastPlayed: day(1)),
            StreamCache.File(name: "mid.flac", bytes: 600, lastPlayed: day(2)),
        ]
        #expect(StreamCache.evictions(files, limit: 1_200, keep: []) == ["old.flac"])
        #expect(StreamCache.evictions(files, limit: 600, keep: []) == ["old.flac", "mid.flac"])
        #expect(StreamCache.evictions(files, limit: 1_800, keep: []).isEmpty, "at the limit: nothing goes")
        let tie = [StreamCache.File(name: "b.flac", bytes: 10, lastPlayed: day(1)),
                   StreamCache.File(name: "a.flac", bytes: 10, lastPlayed: day(1))]
        #expect(StreamCache.evictions(tie, limit: 10, keep: []) == ["a.flac"], "a tie goes by name")
        withFolder { folder in
            write(folder, "old.flac", bytes: 600, played: day(1))
            write(folder, "new.flac", bytes: 600, played: day(3))
            write(folder, "mid.flac", bytes: 600, played: day(2))
            #expect(folder.evict(limit: 1_200, keep: []) == ["old.flac"])
            #expect(names(folder) == ["mid.flac", "new.flac"])
            #expect(folder.reusable(Song(id: "mid", suffix: "flac", size: 600), now: day(4)) != nil)
            #expect(folder.evict(limit: 600, keep: []) == ["new.flac"], "playing it made mid the newest")
        }
    }

    @Test func aSongInUseIsNeverEvicted() {
        let day = { (n: Double) in Date(timeIntervalSince1970: n * 86_400) }
        let files = [
            StreamCache.File(name: "heard.flac", bytes: 1_000, lastPlayed: day(1)),
            StreamCache.File(name: "next.flac", bytes: 1_000, lastPlayed: day(2)),
            StreamCache.File(name: "other.flac", bytes: 1_000, lastPlayed: day(3)),
        ]
        #expect(StreamCache.evictions(files, limit: 1_000, keep: ["heard.flac", "next.flac"]) == ["other.flac"],
                "everything else goes; the total stays over the limit rather than lose a song in use")
        #expect(StreamCache.evictions(files, limit: 2_000, keep: ["heard.flac"]) == ["next.flac"])
    }

    @Test func theTotalEndsAtOrUnderTheLimit() {
        var seed: UInt64 = 0x5EED
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        for round in 0..<200 {
            let files = (0..<Int(next() % 40)).map { index in
                StreamCache.File(name: "s\(index).flac", bytes: Int64(next() % 300_000_000),
                                 lastPlayed: Date(timeIntervalSince1970: Double(next() % 1_000_000)))
            }
            let keep = Set(files.filter { _ in next() % 5 == 0 }.map(\.name))
            let gone = Set(StreamCache.evictions(files, keep: keep))
            #expect(gone.isDisjoint(with: keep), "round \(round): a song in use went")
            let left = files.filter { !gone.contains($0.name) }
            let total = left.reduce(Int64(0)) { $0 + $1.bytes }
            let kept = files.filter { keep.contains($0.name) }.reduce(Int64(0)) { $0 + $1.bytes }
            #expect(total <= StreamCache.limit || total == kept, "round \(round): \(total) bytes left")
            // nothing went that needn't have: put back the newest gone and it is over again
            if let newest = files.filter({ gone.contains($0.name) }).max(by: {
                $0.lastPlayed != $1.lastPlayed ? $0.lastPlayed < $1.lastPlayed : $0.name < $1.name
            }) {
                #expect(total + newest.bytes > StreamCache.limit, "round \(round): \(newest.name) went for nothing")
            }
        }
        #expect(StreamCache.limit == 2_000_000_000)
    }
}

@Suite struct HeardEstimateTests {
    @Test func theEarIsTheLatencyBehindTheRender() {
        #expect(HeardEstimate.heard(rendered: 48_000, latency: 0.1, rate: 48_000) == 43_200)
        #expect(HeardEstimate.heard(rendered: 44_100, latency: 0, rate: 44_100) == 44_100)
        #expect(HeardEstimate.heard(rendered: 1_000, latency: 0.1, rate: 48_000) == 0, "never before the start")
        #expect(HeardEstimate.heard(rendered: 1_000, latency: -1, rate: 48_000) == 1_000, "no negative latency")
        #expect(HeardEstimate.frames(0.0213, rate: 44_100) == 939)
        #expect(HeardEstimate.frames(.nan, rate: 44_100) == 0)
    }

    @Test func aReadingIsCarriedOnForASecondAtMost() {
        let reading = HeardReading(frame: 96_000, at: 100.0, latency: 0.02)
        #expect(HeardEstimate.rendered(reading, now: 100.25, rate: 48_000, end: 1_000_000) == 108_000)
        #expect(HeardEstimate.rendered(reading, now: 101.0, rate: 48_000, end: 1_000_000) == 144_000)
        #expect(HeardEstimate.rendered(reading, now: 101.5, rate: 48_000, end: 1_000_000) == 96_000,
                "past a second the reading is too old to carry on: it is used as it is")
        #expect(HeardEstimate.rendered(reading, now: 99.0, rate: 48_000, end: 1_000_000) == 96_000, "a clock gone back")
        #expect(HeardEstimate.rendered(reading, now: nil, rate: 48_000, end: 1_000_000) == 96_000, "offline: no clock")
        let offline = HeardReading(frame: 96_000, at: nil, latency: 0)
        #expect(HeardEstimate.rendered(offline, now: 100.5, rate: 48_000, end: 1_000_000) == 96_000)
    }

    @Test func neverPastWhatWasScheduled() {
        let reading = HeardReading(frame: 96_000, at: 100.0, latency: 0)
        #expect(HeardEstimate.rendered(reading, now: 100.5, rate: 48_000, end: 100_000) == 100_000)
        #expect(HeardEstimate.rendered(reading, now: 100.5, rate: 48_000, end: 90_000) == 96_000,
                "an end before the reading itself: the reading")
    }

    @Test func atAStopTheOldRoutesLatencyIsTakenOff() {
        // AirPlay's latency was 2 s; the speaker's is what the session says now, and doesn't count
        let reading = HeardReading(frame: 480_000, at: 50.0, latency: 2.0)
        #expect(HeardEstimate.atStop(reading, now: 50.5, rate: 48_000, end: 10_000_000) == 480_000 + 24_000 - 96_000)
        let speaker = HeardReading(frame: 480_000, at: nil, latency: 0.1)
        #expect(HeardEstimate.atStop(speaker, now: nil, rate: 48_000, end: 10_000_000) == 480_000 - 4_800)
    }
}
