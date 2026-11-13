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
            let read = try db.keptStarts()
            #expect(try db.forgetStarts(read.filter { $0.id == ids[0] || $0.id == ids[1] }) == 2)
            // kept across a launch
            let again = try DownloadDatabase(path: path)
            #expect(try again.keptStarts().map(\.played) == [tie.asCounted])
            // a download store emptied (removeAll) keeps them: they are the person's plays, not downloads
            try again.removeAll()
            #expect(try again.keptStartCount() == 1)
        }
    }

    @Test func aVersionTwoFileIsGivenTheTableEverythingInItKept() throws {
        try withDatabase { _, path in
            let old = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("v2.sqlite").path
            let flac = FLACFacts(rate: 96_000, bits: 24, md5: String(repeating: "cd", count: 16))
            let done = DownloadRecord(id: "s1", albumID: "al", disc: 1, track: 3, format: "raw", suffix: "flac",
                                      sizeExpected: 4_000, duration: 201.5, state: .done, check: .matched, bytes: 4_000,
                                      flac: flac, tries: 1, wantedAt: 10, doneAt: 20)
            let waiting = DownloadRecord(id: "s2", albumID: "al", suffix: "mp3", wait: .wifi, wantedAt: 11)
            let album = Data(#"{"id":"al","name":"Mezzanine"}"#.utf8)
            let loudness = Data(#"{"id":"al","gain":-6.5}"#.utf8)
            let lyrics = Data(#"{"synced":true,"lines":[{"time":1.5,"text":"one"}]}"#.utf8)
            let queue = Data(#"{"answer":"kept"}"#.utf8)
            do {
                let v2 = try DownloadDatabase(path: old, upTo: 2)
                #expect(try v2.userVersion() == 2)
                try v2.put(done)
                try v2.put(waiting)
                try v2.addOrigin(.album("al"), song: "s1", at: 10)
                try v2.addOrigin(.song, song: "s2", at: 11)
                try v2.putAlbum(id: "al", json: album, fetchedAt: 12)
                try v2.setCover(album: "al", file: "al.jpg")
                try v2.putLoudness(album: "al", json: loudness, algorithm: 3, fetchedAt: 13)
                #expect(try v2.putLyrics(song: "s1", json: lyrics, etag: "\"e1\"", fetchedAt: 14))
                try v2.keepPlay(songID: "s1", timeMs: 5)
                try v2.keepQueue(kind: "unsent", body: queue, at: 15)
                try v2.setMeta("force_quit_at", "16")
                #expect(throws: DownloadDatabase.Failure.self) {
                    try v2.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a")))
                }
            }
            let v3 = try DownloadDatabase(path: old, upTo: 3)
            #expect(try v3.userVersion() == 3)
            // every row of every table as it was
            #expect(try v3.songs() == [done, waiting])
            #expect(try v3.origins() == ["s1": [.album("al")], "s2": [.song]])
            let albums = try v3.albums()
            #expect(albums.map(\.id) == ["al"] && albums.first?.json == album && albums.first?.cover == "al.jpg"
                    && albums.first?.fetchedAt == 12)
            let levels = try v3.loudness()
            #expect(levels.map(\.id) == ["al"] && levels.first?.json == loudness && levels.first?.algorithm == 3)
            let kept = try v3.lyrics("s1")
            #expect(kept?.json == lyrics && kept?.etag == "\"e1\"")
            #expect(try v3.lyricsSongs() == ["s1"])
            #expect(try v3.keptPlays().map(\.songID) == ["s1"] && v3.keptPlays().map(\.timeMs) == [5])
            #expect(try v3.keptQueue() == DownloadDatabase.PendingQueue(kind: "unsent", body: queue, keptAt: 15))
            #expect(try v3.meta("force_quit_at") == "16")
            // and the lyrics' trigger still takes a song's lyrics with it
            try v3.deleteSong("s1")
            #expect(try v3.lyrics("s1") == nil)
            // the new table, empty and working
            #expect(try v3.keptStartCount() == 0)
            #expect(try v3.keepStart(Played(at: 1, queue: nil, entry: nil, song: rTrack("a"))) > 0)
        }
    }
}

/// HistoryAsking: what Up Next's history may ask deadwax, and which failure it says.
@Suite struct HistoryAskingTests {
    // (each mutating call bound first: #expect and #require can't take one)
    @Test func onlyTheNewestAnswerOfEachKindCounts() throws {
        var asking = HistoryAsking()
        let firstAsked = asking.askNewest(online: true)
        let first = try #require(firstAsked)
        let secondAsked = asking.askNewest(online: true)
        let second = try #require(secondAsked)
        let firstCounts = asking.newestCame(first)
        let secondCounts = asking.newestCame(second)
        #expect(!firstCounts && secondCounts)
        let olderAsked = asking.askOlder(more: true)
        let older = try #require(olderAsked)
        let another = asking.askOlder(more: true)
        #expect(asking.loadingOlder && another == nil, "one older page at a time")
        asking.reset()
        let late = asking.olderCame(older)
        #expect(!late && !asking.loadingOlder, "another person: the answer on its way dropped")
    }

    @Test func offlineTheNewestPageIsntAskedForNorItsFailureSaid() throws {
        var asking = HistoryAsking()
        let offline = asking.askNewest(online: false)
        #expect(offline == nil)
        let askAsked = asking.askNewest(online: true)
        let ask = try #require(askAsked)
        let failed = asking.failedNewest(ask)
        #expect(failed)
        #expect(asking.shown(online: true) == .newest && asking.shown(online: false) == nil)
        // a newest page that comes lets it go
        let againAsked = asking.askNewest(online: true)
        let again = try #require(againAsked)
        let came = asking.newestCame(again)
        #expect(came && asking.shown(online: true) == nil)
    }

    @Test func theNewestPagesFailureNeverStopsTheOlderPages() throws {
        var asking = HistoryAsking()
        let newestAsked = asking.askNewest(online: true)
        let newest = try #require(newestAsked)
        _ = asking.failedNewest(newest)
        #expect(asking.mayAskOlder(more: true))
        let olderAsked = asking.askOlder(more: true)
        let older = try #require(olderAsked)
        let failed = asking.failedOlder(older)
        #expect(failed)
        // an older page's failure stops them until Try again, and is said first, online or not
        #expect(!asking.mayAskOlder(more: true) && asking.shown(online: false) == .older && asking.shown(online: true) == .older)
        let retried = asking.retry(online: true)
        #expect(retried == .older && asking.mayAskOlder(more: true))
        let retriedNext = asking.retry(online: true)
        #expect(retriedNext == .newest && asking.shown(online: true) == nil)
        let retriedLast = asking.retry(online: true)
        #expect(retriedLast == nil)
        #expect(!asking.mayAskOlder(more: false))
        // a stale failure changes nothing
        let lateAsked = asking.askOlder(more: true)
        let late = try #require(lateAsked)
        let stale = asking.failedOlder(late - 1)
        #expect(!stale && asking.loadingOlder)
        let came = asking.olderCame(late)
        #expect(came && !asking.loadingOlder && asking.shown(online: true) == nil)
    }

    @Test func aPageThatBringsNoRowIntoViewAsksForTheNextItself() {
        let order = (0..<30).map { "r\($0)" }
        // the rows in view near the top, after a page that added none above them: ask again
        #expect(HistoryAsking.asksAgain(order, inView: ["r3", "r4", "r5"], more: true))
        #expect(HistoryAsking.asksAgain(order, inView: ["r9", "r10"], more: true))
        // a page that pushed them down past the first ten: scrolling asks, as rows come into view
        #expect(!HistoryAsking.asksAgain(order, inView: ["r10", "r11", "r12"], more: true))
        // none left, or nothing in view
        #expect(!HistoryAsking.asksAgain(order, inView: ["r3"], more: false))
        #expect(!HistoryAsking.asksAgain(order, inView: [], more: true))
        #expect(HistoryAsking.near == 10)
    }
}
