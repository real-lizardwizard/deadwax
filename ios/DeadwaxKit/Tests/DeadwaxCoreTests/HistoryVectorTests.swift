import Foundation
import Testing
@testable import DeadwaxCore

/// Play history's rules held to the web's own (app 0.8): Fixtures/history/vectors.json is what ui/src/lib/
/// playHistory.ts answers, written by ios/scripts/export-history.cjs (ui/test/ioshistory.sim.cjs keeps it current) -
/// the numbers, keys, merged, withNewest and withOlder, countedIn, afterFailure, retryAfter, and each start drawn
/// once: 300 seeded runs of moves made here again from the same Park-Miller numbers through DeadwaxCore's own Up Next,
/// every step's line of what queueShows and pastRows answer digested as the web's were.
@Suite struct HistoryVectorTests {
    let file: JSONValue

    init() throws {
        file = try Fixtures.json("history/vectors.json")
    }

    @Test func upNextsWordsForThemAreTheWebs() {
        let words = file["words"]
        #expect(words?["history"]?.string == UpNextWords.history)
        #expect(words?["loadingEarlier"]?.string == UpNextWords.loadingEarlier)
        #expect(words?["earlierFailed"]?.string == UpNextWords.earlierFailed)
        #expect(words?["tryAgain"]?.string == UpNextWords.tryAgain)
        #expect(UpNextWords.playAgain("Roads") == "Roads" + (words?["playAgain"]?.string ?? "?"))
        #expect(UpNextWords.playing("Roads") == (words?["playing"]?.string ?? "?") + "Roads")
    }

    @Test func theNumbersAreTheWebs() {
        let numbers = file["constants"]
        #expect(numbers?["page"]?.int == PlayHistory.page)
        #expect(numbers?["postMax"]?.int == PlayHistory.postMax)
        #expect(numbers?["ownKept"]?.int == PlayHistory.ownKept)
        #expect(numbers?["retryMs"]?.int == Int(PlayHistory.retryMs))
        #expect(numbers?["retryMaxMs"]?.int == Int(PlayHistory.retryMaxMs))
        #expect(numbers?["drawn"]?.int == UpNext.drawn)
        #expect(numbers?["historyBack"]?.int == UpNext.historyBack)
    }

    @Test func aStartsKey() throws {
        let cases = try #require(file["keys"]?.array)
        #expect(cases.count == 4)
        for item in cases {
            let at = try #require(item["at"]?.int), id = try #require(item["id"]?.string)
            let key = PlayHistory.key(Played(at: Int64(at), queue: nil, entry: nil, song: simTrack(id)))
            #expect(sameText(key, item["key"]?.string), "\(item)")
        }
    }

    @Test func merged() throws {
        let cases = try #require(file["merged"]?.array)
        #expect(cases.count == 160)
        var ties = 0
        for (n, item) in cases.enumerated() {
            let pages = try starts(item["pages"]), own = try starts(item["own"])
            let made = PlayHistory.merged(pages, own)
            #expect(made.map(text) == (try starts(item["merged"])).map(text), "case \(n)")
            if Set(made.map(\.at)).count < made.count { ties += 1 }
        }
        #expect(ties > 40)
    }

    @Test func withNewestAndWithOlder() throws {
        let steps = try #require(file["held"]?.array)
        #expect(steps.count == 209)
        var newest = 0, older = 0
        for (n, step) in steps.enumerated() {
            let was = try held(step["held"]), page = try self.page(step["page"]), out = try held(step["out"])
            let made: HistoryHeld
            if step["op"]?.string == "newest" {
                made = PlayHistory.withNewest(was, page)
                newest += 1
            } else {
                let from = try #require(try cursor(step["from"]))
                made = PlayHistory.withOlder(was, from: from, page)
                older += 1
            }
            #expect(heldText(made) == heldText(out), "step \(n) (\(step["op"]?.string ?? "?"))")
        }
        #expect(newest > 80 && older > 80)
    }

    @Test func countedIn() throws {
        let cases = try #require(file["counted"]?.array)
        #expect(cases.count == 80)
        var marked = 0
        for (n, item) in cases.enumerated() {
            let own = try starts(item["own"])
            let made = PlayHistory.countedIn(own, songID: try #require(item["songId"]?.string), at: Int64(try #require(item["at"]?.int)))
            #expect(made.map(text) == (try starts(item["out"])).map(text), "case \(n)")
            #expect((made.map(text) == own.map(text)) == (item["same"]?.bool == true), "case \(n)")
            if item["same"]?.bool == false { marked += 1 }
        }
        #expect(marked > 5)
    }

    @Test func whatAFailedSendMeans() throws {
        let cases = try #require(file["afterFailure"]?.array)
        #expect(cases.count == 21)
        for item in cases {
            let status = item["status"]?.int
            #expect(PlayHistory.afterFailure(status).rawValue == item["out"]?.string, "\(item)")
        }
        let waits = try #require(file["retryAfter"]?.array)
        #expect(waits.count == 28)
        for item in waits {
            #expect(PlayHistory.retryAfter(try #require(item["failures"]?.int)) == Int64(try #require(item["ms"]?.int)), "\(item)")
        }
    }

    @Test func eachStartIsDrawnOnceAsTheWebDrawsIt() throws {
        let property = try #require(file["property"])
        let runs = try #require(property["runs"]?.int), steps = try #require(property["steps"]?.int)
        let digests = (property["digests"]?.array ?? []).compactMap(\.string)
        let sample = (property["sample"]?.array ?? []).compactMap(\.string)
        #expect(runs == 300 && steps == 50 && digests.count == runs && sample.count == steps)

        var starts = 0
        var unlike: [Int] = []
        var problems: [String] = []
        for run in 0..<runs {
            let made = propertyRun(run, steps: steps, problems: &problems)
            starts += made.starts
            if run == 0 {
                for (step, line) in made.lines.enumerated() where step < sample.count && !sameText(line, sample[step]) {
                    problems.append("run 0 step \(step): \(line) - the web's \(sample[step])")
                    break
                }
            }
            if run < digests.count && unitHash(made.lines.joined(separator: "\n")) != digests[run] { unlike.append(run) }
        }
        #expect(problems.isEmpty, "\(problems.prefix(5))")
        #expect(starts == property["starts"]?.int)
        #expect(unlike.isEmpty, "\(unlike.count) runs unlike the web's, the first \(unlike.prefix(5))")
    }

    // MARK: - the runs

    /// export-history.cjs's propertyRun, move for move and number for number.
    private func propertyRun(_ run: Int, steps: Int, problems: inout [String]) -> (lines: [String], starts: Int) {
        let random = Seeded(Int64(run) * 1_000_003 % 2_147_483_646 + 1)
        _ = random.next()
        let pick = { (count: Int) in random.pick(count) }
        let limit = run % 2 == 0 ? 8 : UpNext.drawn
        var mode = Repeat.allCases[pick(3)]
        var made = 0
        func fresh(_ songs: [QueueTrack], start: Int?, shuffle: Bool) -> UpNextQueue {
            defer { made += 1 }
            return startUpNext(songs, start: start, shuffle: shuffle, random: random.next, id: "q\(run)-\(made)")
        }
        let size = 2 + pick(40)
        let start: Int? = random.next() < 0.3 ? nil : 0
        let shuffle = random.next() < 0.3
        var queue = toppedUp(fresh(simAlbum(size, "r\(run)-"), start: start, shuffle: shuffle), mode, random: random.next)
        var clock: Int64 = 1_800_000_000_000
        var recorded: [Played] = []
        func begin() {
            clock += 1000
            recorded.append(PlayHistory.startOf(queue.tracks[queue.index], at: clock, queue: queue))
        }
        func jumpTo(_ from: UpNextQueue, _ key: Int) -> Bool {
            guard let jump = jumpedTo(from, key) else { return false }
            queue = toppedUp(jump.queue.at(jump.index), mode, random: random.next)
            return true
        }
        begin()
        var lines: [String] = []
        for step in 0..<steps {
            let op = pick(13)
            var began = false
            switch op {
            case 0...2:
                if let to = onward(queue) {
                    queue = toppedUp(queue.at(to), mode, random: random.next)
                    began = true
                }
            case 3:
                if case .go(let index) = backward(queue, position: 0) {
                    queue = wentBack(queue, index)
                    began = true
                }
            case 4:
                let view = upNextView(queue, mode, limit: limit)
                let rows = view.added + (view.list?.rows ?? [])
                if !rows.isEmpty { began = jumpTo(queue, rows[pick(rows.count)].key) }
            case 5:
                let rows = historyRows(queue)
                if !rows.isEmpty { began = jumpTo(queue, rows[pick(rows.count)].key) }
            case 6:
                //? an older row tapped: Play Next, then the jump to it (QueueController.playAgain's two steps)
                let rows = PlayHistory.pastRows(PlayHistory.merged([], recorded), queue: queue, limit: limit)
                if !rows.isEmpty, let key = queue.upNext?.nextKey {
                    began = jumpTo(withNext(queue, [rows[pick(rows.count)].track]), key)
                }
            case 7:
                let song = simTrack("p\(run)-\(step)")
                queue = random.next() < 0.5 ? withNext(queue, [song]) : withLast(queue, [song])
            case 8:
                queue = toppedUp(withShuffle(queue, !(queue.upNext?.shuffle ?? false), random: random.next), mode, random: random.next)
            case 9:
                mode = Repeat.allCases[pick(3)]
                queue = toppedUp(withRepeat(queue, mode), mode, random: random.next)
            case 10:
                let saving = toSave(queue, position: 30)
                let window = Array(queue.tracks[saving.start..<(saving.start + saving.ids.count)])
                guard let back = fromSnapshot(saving.snapshot, tracks: window, index: saving.index, setting: .auto,
                                              newId: { "made-a-new-id" }) else {
                    problems.append("run \(run) step \(step): a snapshot that doesn't read back")
                    return (lines, recorded.count)
                }
                queue = toppedUp(withRepeat(back, mode), mode, random: random.next)
            case 11:
                let size = 2 + pick(20)
                let start = pick(2)
                let shuffle = random.next() < 0.3
                queue = toppedUp(fresh(simAlbum(size, "m\(run)-\(step)-"), start: start, shuffle: shuffle), mode, random: random.next)
                began = true
            default:
                began = true
            }
            if began { begin() }
            let pages = recorded.enumerated().filter { $0.offset % 3 == 0 }.map(\.element.asCounted)
            let plays = PlayHistory.merged(pages, recorded)
            let shows = PlayHistory.queueShows(queue, limit: limit)
            let rows = PlayHistory.pastRows(plays, queue: queue, limit: limit)
            lines.append([
                "\(step):\(op)", "\(queue.index)", shows.id ?? "-", shows.keys.sorted().map(String.init).joined(separator: ","),
                rows.map { "\($0.key)=\($0.track.id)" }.joined(separator: ","), "\(plays.filter(\.counted).count)", "\(plays.count)",
            ].joined(separator: "|"))
        }
        return (lines, recorded.count)
    }

    // MARK: - reading the fixture

    /// A start as the fixture holds it: [at, counted, queue, entry, song id] - its song upnext.sim's track(id).
    private func starts(_ json: JSONValue?) throws -> [Played] {
        try #require(json?.array).map { item in
            let parts = try #require(item.array)
            try #require(parts.count == 5)
            return Played(at: Int64(try #require(parts[0].int)), counted: try #require(parts[1].bool as Bool?), queue: parts[2].string,
                          entry: parts[3].int, song: simTrack(try #require(parts[4].string)))
        }
    }

    private func cursor(_ json: JSONValue?) throws -> HistoryCursor? {
        guard let json, !json.isNull else { return nil }
        return HistoryCursor(at: Int64(try #require(json["at"]?.int)), id: try #require(json["id"]?.string))
    }

    private func held(_ json: JSONValue?) throws -> HistoryHeld {
        HistoryHeld(plays: try starts(json?["plays"]), before: try cursor(json?["before"]), asked: try #require(json?["asked"]?.bool as Bool?))
    }

    private func page(_ json: JSONValue?) throws -> HistoryPage {
        HistoryPage(plays: try starts(json?["plays"]), next: try cursor(json?["next"]), shared: try #require(json?["shared"]?.bool as Bool?))
    }

    /// A start in words that tell every field apart - its song id by UTF-16 unit, as JavaScript tells them.
    private func text(_ played: Played) -> String {
        "\(played.at)|\(played.counted)|\(played.queue ?? "null")|\(played.entry.map(String.init) ?? "null")|\(Array(played.song.id.utf16))"
    }

    private func heldText(_ held: HistoryHeld) -> String {
        let before = held.before.map { "\($0.at):\(Array($0.id.utf16))" } ?? "null"
        return "\(held.plays.map(text).joined(separator: ";"))#\(before)#\(held.asked)"
    }
}
