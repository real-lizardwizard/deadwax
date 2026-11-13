import Foundation
import Testing
@testable import DeadwaxCore

/// Play history's phone-only parts (app 0.8): the outbox's own starts and continuation, what a send's answer means,
/// a start as deadwax reads and writes it, and the person's store's `start_pending`. The rules the web shares are
/// HistoryVectorTests'.
@Suite struct PlayHistoryTests {
    private let t: Int64 = 1_800_000_000_000

    private func start(_ id: String, _ at: Int64, queue: String? = "q", entry: Int? = 0, counted: Bool = false) -> Played {
        Played(at: at, counted: counted, queue: queue, entry: entry, song: simTrack(id))
    }

    // MARK: the outbox

    @Test func startsAreKeptNewestFirstTheNewest500() {
        var outbox = HistoryOutbox()
        let kept = (0..<502).map { n in outbox.record(start("\(n)", t + Int64(n))) }
        #expect(kept.allSatisfy { $0 })
        #expect(outbox.own.count == PlayHistory.ownKept && outbox.own.first?.song.id == "501" && outbox.own.last?.song.id == "2")
        outbox.forget()
        #expect(outbox.own.isEmpty && outbox.continuation == nil)
    }

    @Test func aQueuePutBackMidSongCarriesOnWithoutAStart() {
        let queue = startUpNext(simAlbum(3), start: 1, id: "q-put")
        var outbox = HistoryOutbox()
        outbox.continuing(queue)
        #expect(outbox.continuation == Continuation(queue: "q-put", entry: 1))
        // the same entry begun: the listen carrying on - not kept, and the continuation spent
        let carried = outbox.record(PlayHistory.startOf(queue.tracks[1], at: t, queue: queue))
        #expect(!carried && outbox.own.isEmpty && outbox.continuation == nil)
        // the same entry again: a start now
        let again = outbox.record(PlayHistory.startOf(queue.tracks[1], at: t + 1, queue: queue))
        // another start first ends it: the entry put back, begun after, is a start
        outbox.continuing(queue)
        let other = outbox.record(start("x", t + 2, queue: "q-other", entry: 1))
        let after = outbox.record(PlayHistory.startOf(queue.tracks[1], at: t + 3, queue: queue))
        #expect(again && other && after)
        #expect(outbox.own.map(\.song.id) == ["2", "x", "2"])
        // nil - another queue put back, or one put back at its start - ends one
        outbox.continuing(queue)
        outbox.continuing(nil)
        #expect(outbox.continuation == nil)
        outbox.continuing(UpNextQueue(tracks: simAlbum(2), index: 0))
        #expect(outbox.continuation == nil)
    }

    @Test func aCountedPlayMarksItsStart() {
        var outbox = HistoryOutbox()
        outbox.record(start("a", t))
        outbox.record(start("b", t + 1000))
        let marked = outbox.counted(songID: "a", at: t)
        #expect(marked && outbox.own.map(\.counted) == [false, true])
        let twice = outbox.counted(songID: "a", at: t)
        let then = outbox.counted(songID: "a", at: t + 1)
        #expect(!twice && !then, "already counted; no start of it then")
        // the web's ids, by UTF-16 unit: "\u{e9}" isn't "e\u{301}"
        outbox.record(start("\u{e9}", t + 2000))
        let spelled = outbox.counted(songID: "e\u{301}", at: t + 2000)
        #expect(!spelled)
    }

    // MARK: a start

    @Test func aStartIsTheSongAsTheQueueHoldsItWithoutItsLevel() {
        let queue = withNext(startUpNext(rAlbum(3, level: .album), start: 1, id: "q-7"), [rTrack("n", level: .track)])
        let played = PlayHistory.startOf(queue.tracks[queue.index], at: t, queue: queue)
        #expect(played == Played(at: t, counted: false, queue: "q-7", entry: 1, song: rTrack("2")))
        #expect(played.song.level == nil && played.song.coverArt == "al-mez")
        let plain = PlayHistory.startOf(rTrack("1"), at: t, queue: UpNextQueue(tracks: [rTrack("1")], index: 0))
        #expect(plain.queue == nil && plain.entry == nil)
    }

    @Test func aSendsAnswer() {
        #expect(PlayHistory.after(status: nil) == .stopped)
        #expect([200, 201, 204].map { PlayHistory.after(status: $0) } == [.sent, .sent, .sent])
        #expect(PlayHistory.after(status: 401) == .held)
        #expect([400, 403, 404, 413, 422].map { PlayHistory.after(status: $0) } == Array(repeating: .dropped, count: 5))
        #expect([408, 429, 500, 502, 503].map { PlayHistory.after(status: $0) } == Array(repeating: .stopped, count: 5))
    }

    @Test func writtenAsTheWebWritesAStart() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let one = String(decoding: try encoder.encode(HistoryPost(starts: [start("1", t, queue: nil, entry: nil)])), as: UTF8.self)
        #expect(one == #"{"starts":[{"at":1800000000000,"counted":false,"entry":null,"queue":null,"song":{"album":"Mezzanine","albumId":"mez","artist":"Massive Attack","bitDepth":16,"channels":2,"contentType":"audio\/flac","coverArt":null,"duration":200,"id":"1","sampleRate":44100,"suffix":"flac","title":"song 1"}}]}"#)
        let levelled = Played(at: t, queue: "q", entry: 3, song: rTrack("2", level: .album))
        let back = try JSONDecoder().decode(Played.self, from: try encoder.encode(levelled))
        #expect(back == levelled && back.song.level == nil)
    }

    @Test func readAsDeadwaxAnswersLeniently() throws {
        let page = try JSONDecoder().decode(HistoryPage.self, from: Data(#"""
            {"plays":[{"at":1800000001000,"counted":true,"queue":"q-1","entry":4,"song":{"id":"a","title":"A","artist":"B",
              "album":"C","albumId":"al","coverArt":"al","duration":201.5,"contentType":"audio/flac","suffix":"flac",
              "sampleRate":96000,"bitDepth":24,"channels":2}},
             {"at":1800000000000,"song":{"id":"b"},"extra":"ignored"}],
             "next":{"at":1800000000000,"id":"b"},"shared":false}
            """#.utf8))
        #expect(page.plays.count == 2 && page.next == HistoryCursor(at: t, id: "b") && !page.shared)
        #expect(page.plays[0].counted && page.plays[0].entry == 4 && page.plays[0].song.sampleRate == 96000 && page.plays[0].song.duration == 201.5)
        #expect(page.plays[1] == Played(at: t, queue: nil, entry: nil, song: QueueTrack(
            id: "b", title: "", artist: "", album: "", albumId: nil, coverArt: nil, duration: 0, contentType: nil, suffix: nil,
            sampleRate: 0, bitDepth: 0, channels: 0)))
        let last = try JSONDecoder().decode(HistoryPage.self, from: Data(#"{"plays":[],"next":null,"shared":true}"#.utf8))
        #expect(last.plays.isEmpty && last.next == nil && last.shared)
        let taken = try JSONDecoder().decode(HistoryTaken.self, from: Data(#"{"taken":3,"skipped":1}"#.utf8))
        #expect(taken == HistoryTaken(taken: 3, skipped: 1))
    }
}

/// `start_pending`: the starts deadwax hasn't taken, kept in the person's download store across launches.
@Suite struct StartPendingTests {
    private func withDatabase(_ body: (DownloadDatabase, String) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-starts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("downloads.sqlite").path
        try body(try DownloadDatabase(path: path), path)
    }

    @Test func keptOldestFirstCountedAndForgotten() throws {
        try withDatabase { db, path in
            let t: Int64 = 1_800_000_000_000
            let late = Played(at: t + 2000, queue: "q", entry: 2, song: rTrack("c", level: .album))
            let early = Played(at: t, queue: nil, entry: nil, song: rTrack("a"))
            let tie = Played(at: t, queue: "q", entry: 0, song: rTrack("b"))
            let ids = try [late, early, tie].map { try db.keepStart($0) }
            #expect(try db.keptStartCount() == 3)
            #expect(try db.keptStarts().map(\.played) == [early, tie, late])
            #expect(try db.keptStarts(limit: 2).map(\.id) == [ids[1], ids[2]])
            #expect(try db.keptStarts().last?.played.song.level == nil)
            try db.countStart(songID: "b", at: t)
            try db.countStart(songID: "c", at: t)
            #expect(try db.keptStarts().map(\.played.counted) == [false, true, false])
            try db.forgetStarts([ids[0], ids[1]])
            // kept across a launch
            let again = try DownloadDatabase(path: path)
            #expect(try again.keptStarts().map(\.played) == [tie.asCounted])
            // a download store emptied (removeAll) keeps them: they are the person's plays, not downloads
            try again.removeAll()
            #expect(try again.keptStartCount() == 1)
        }
    }

    @Test func aVersionTwoFileIsGivenTheTableItsPlaysKept() throws {
        try withDatabase { _, path in
            let old = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("v2.sqlite").path
            do {
                let v2 = try DownloadDatabase(path: old, upTo: 2)
                #expect(try v2.userVersion() == 2)
                try v2.keepPlay(songID: "a", timeMs: 5)
                #expect(throws: DownloadDatabase.Failure.self) {
                    try v2.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a")))
                }
            }
            let v3 = try DownloadDatabase(path: old)
            #expect(try v3.userVersion() == 3)
            #expect(try v3.keptPlays().map(\.songID) == ["a"])
            #expect(try v3.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a"))) > 0)
        }
    }
}
