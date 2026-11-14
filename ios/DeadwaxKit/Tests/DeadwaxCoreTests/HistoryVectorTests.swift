import Foundation
import Testing
@testable import DeadwaxCore

/// Play history's rules held to the web's own (app 0.8): Fixtures/history/vectors.json is what ui/src/lib/
/// playHistory.ts answers, written by ios/scripts/export-history.cjs (ui/test/ioshistory.sim.cjs keeps it current) -
/// the numbers, keys, merged, withNewest and withOlder, countedIn, afterFailure, retryAfter, and each start drawn
/// once: 300 seeded runs of moves made here again from the same Park-Miller numbers through DeadwaxCore's own Up Next,
/// every step's line of what queueShows and pastRows answer digested as the web's were. (2.1.18) A History row's tap
/// rolls back; an older row's brings it and every older row below it back (rowsFrom, broughtBack with the floor); each
/// line carries the starts the queue holds and each older row's starts and entry - and (review of the port) what an
/// older row's tap hands the roll-back, PlayHistory.brought: the web's replayPast made from its own parts.
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

    /// The settings by turns, as export-history.cjs's SETTINGS.
    static let settings: [Normalization] = [.auto, .song, .album, .off]

    /// What a roll-back is handed, as export-history.cjs's handedLine writes it: the floor, then each row's song, its
    /// level, its starts and its entry.
    static func handedLine(_ handed: (rows: [Brought], floor: Int?)) -> String {
        let rows = handed.rows.map { row in
            "\(row.track.id):\(row.track.level?.rawValue ?? "-")/\(row.starts.map(String.init).joined(separator: "."))/"
                + (row.entry.map(String.init) ?? "-")
        }
        return "\(handed.floor.map(String.init) ?? "-")>" + rows.joined(separator: ",")
    }

    /// (review of the port) What an older row's tap hands the roll-back - PlayHistory.brought, as the web's replayPast
    /// (app/UpNext.tsx) makes it from rowsFrom, queued() and the floor: rows given whole (a song's own level among them,
    /// kept under Off), every setting, a key no row has, a queue with History, one without, a plain queue. And
    /// replayPast's text as this port follows it: a new hash means it changed - port it, then take the hash.
    @Test func whatAnOlderRowsTapHandsTheRollBack() throws {
        #expect(file["replayPast"]?.string == "64993629b47120872dad4bf2d87df4bf9aa39e9372e7f728535489d544fa2e3a",
                "app/UpNext.tsx replayPast changed: port it to PlayHistory.brought")
        let brought = try #require(file["brought"])
        var past: [PastRow] = []
        for item in brought["past"]?.array ?? [] {
            let row = try #require(item.array)
            var song = simTrack(try #require(row[1].string))
            song.level = row[2].string.flatMap(Level.init(rawValue:))
            let starts = try #require(row[3].array).compactMap { $0.int.map(Int64.init) }
            past.append(PastRow(key: try #require(row[0].string), track: song, starts: starts, entry: row[4].int))
        }
        #expect(past.count == 4 && past.contains { $0.track.level == .album } && past.contains { $0.track.level == nil })
        let queues: [String: UpNextQueue] = [
            "history": startUpNext(simAlbum(4), start: 0, id: "qb-1").at(2),
            "none": startUpNext(simAlbum(4), start: 1, id: "qb-2"),
            "plain": UpNextQueue(tracks: simAlbum(2), index: 1),
        ]
        #expect(brought["queues"]?.array?.compactMap(\.string).sorted() == queues.keys.sorted())
        let cases = brought["cases"]?.array ?? []
        #expect(cases.count == 48)
        for item in cases {
            let queue = try #require(queues[item["queue"]?.string ?? ""], "\(item)")
            let setting = try #require(item["setting"]?.string.flatMap(Normalization.init(rawValue:)), "\(item)")
            let handed = PlayHistory.brought(rows: past, queue: queue, key: try #require(item["key"]?.string), setting: setting)
            #expect(Self.handedLine(handed) == item["out"]?.string, "\(item)")
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
        var tally = Tally()
        for run in 0..<runs {
            let made = propertyRun(run, steps: steps, problems: &problems, tally: &tally)
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
        // the check made here, on the phone's own answers, saw both kinds of start, many times over - (2.1.18) and starts
        // held by rows brought back
        #expect(tally.looked > 100_000 && tally.above > 10_000 && tally.held > 1_000, "\(tally)")
        #expect(unlike.isEmpty, "\(unlike.count) runs unlike the web's, the first \(unlike.prefix(5))")
    }

    // MARK: - the runs

    /// What the each-start check saw: starts looked at, those above History, (2.1.18) those held by a row brought back,
    /// and those moved back down into Up Next past the rows drawn.
    struct Tally {
        var looked = 0, above = 0, held = 0, movedDown = 0
    }

    /// export-history.cjs's propertyRun, move for move and number for number.
    private func propertyRun(_ run: Int, steps: Int, problems: inout [String], tally: inout Tally) -> (lines: [String], starts: Int) {
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
            guard let jump = jumpedTo(from, key, mode) else { return false }
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
                //? (2.1.18) an older row tapped: it and every older row below it brought back (rowsFrom), with the floor
                //? the rows were read against - History's first row, else the song playing's - as Up Next's pastRow hands
                //? them (UpNextScreen)
                let rows = PlayHistory.pastRows(PlayHistory.merged([], recorded), queue: queue, limit: limit)
                if !rows.isEmpty, let state = queue.upNext {
                    let back = PlayHistory.rowsFrom(rows, rows[pick(rows.count)].key)
                        .map { Brought(track: $0.track, starts: $0.starts, entry: $0.entry) }
                    let floor = historyRows(queue).first?.key ?? state.marks[queue.index].key
                    if let jump = broughtBack(queue, back, mode, floor: floor) {
                        queue = toppedUp(jump.queue.at(jump.index), mode, random: random.next)
                        began = true
                    }
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
            drawnOnce(recorded, queue, mode, limit: limit, at: "run \(run) step \(step)", &problems, &tally)
            let pages = recorded.enumerated().filter { $0.offset % 3 == 0 }.map(\.element.asCounted)
            let plays = PlayHistory.merged(pages, recorded)
            let shows = PlayHistory.queueShows(queue, limit: limit)
            let rows = PlayHistory.pastRows(plays, queue: queue, limit: limit)
            //? (2.1.18) the starts the queue holds (sorted by UTF-16 unit, as JavaScript's sort()), each row's starts and
            //? its entry
            let held = shows.held.sorted { $0.lexicographicallyPrecedes($1) }.map { String(decoding: $0, as: UTF16.self) }
            //? (review of the port) the middle row of Up Next's as drawn tapped: what PlayHistory.brought hands the
            //? roll-back, at a setting by turns - nothing drawn
            let drawn = PlayHistory.pastRows(plays, queue: queue)
            let handed = drawn.isEmpty ? "-" : Self.handedLine(PlayHistory.brought(
                plays, queue: queue, key: drawn[drawn.count / 2].key, setting: Self.settings[step % 4]))
            lines.append([
                "\(step):\(op)", "\(queue.index)", shows.id ?? "-", shows.keys.sorted().map(String.init).joined(separator: ","),
                held.joined(separator: ","),
                rows.map { "\($0.key)=\($0.track.id)/\($0.starts.map(String.init).joined(separator: "."))/\($0.entry.map(String.init) ?? "-")" }
                    .joined(separator: ","),
                "\(plays.filter(\.counted).count)", "\(plays.count)", handed,
            ].joined(separator: "|"))
        }
        return (lines, recorded.count)
    }

    /// EACH START DRAWN EXACTLY ONCE, judged here on the phone's own answers (history.sim's check, which the lines above
    /// only replay): every start recorded is either the queue's - its own entry's, or (2.1.18) held by a row brought
    /// back with it (heldByQueue) - and then a row Up Next draws stands for that entry (History's, the song playing's,
    /// the songs added, the list's first `limit`), or it was moved back down into Up Next (after the song playing, at or
    /// before the furthest played), and no older row claims it - or exactly one older row's: the run of one song it
    /// falls in, drawn by pastRows, and neither its entry nor a row holding it one of the queue's.
    private func drawnOnce(_ recorded: [Played], _ queue: UpNextQueue, _ mode: Repeat, limit: Int, at label: String,
                           _ problems: inout [String], _ tally: inout Tally) {
        guard let state = queue.upNext else { return }
        let shows = PlayHistory.queueShows(queue, limit: limit)
        let view = upNextView(queue, mode, limit: limit)
        let viewKeys = Set((view.history + view.added + (view.list?.rows ?? [])).map(\.key))
        func unitStart(_ place: Int) -> Int {
            var at = place
            while at > 0 && state.marks[at].from == .one { at -= 1 }
            return at
        }
        let playingStart = unitStart(queue.index)
        func drawnByQueue(_ place: Int) -> Bool {
            place >= 0 && (unitStart(place) == playingStart || viewKeys.contains(state.marks[unitStart(place)].key))
        }
        //? (2.1.18) moved back down into Up Next: after the song playing, at or before the furthest song played - drawn as
        //? a row, or past the rows drawn, counted in "And N more"
        let reachAt = state.reached.flatMap { reached in state.marks.firstIndex { $0.key == reached } } ?? -1
        func movedDown(_ place: Int) -> Bool {
            place > queue.index && reachAt > queue.index && unitStart(place) <= reachAt
        }
        //? (2.1.18) the entry holding a start brought back with an older row - the song and the moment its mark carries
        func holderOf(_ played: Played) -> Int {
            state.marks.indices.first { at in
                (state.marks[at].starts ?? []).contains(played.at) && WebText.same(queue.tracks[at].id, played.song.id)
            } ?? -1
        }
        let ordered = PlayHistory.merged([], recorded)
        let pastKeys = Set(PlayHistory.pastRows(ordered, queue: queue, limit: limit).map(\.key))
        // which older row stands for each start not the queue's: its run's first, walking oldest first
        var runOf: [String: String] = [:]
        var current = ""
        var lastSong: String?
        for played in ordered.reversed() where !PlayHistory.heldByQueue(played, shows) {
            if lastSong.map({ !WebText.same(played.song.id, $0) }) ?? true {
                current = PlayHistory.key(played)
                lastSong = played.song.id
            }
            runOf[PlayHistory.key(played)] = current
        }
        for played in recorded {
            tally.looked += 1
            let key = PlayHistory.key(played)
            let ours = played.queue.map { WebText.same($0, state.id) } ?? false
            let place = ours ? (state.marks.firstIndex { $0.key == played.entry } ?? -1) : -1
            let holder = holderOf(played)
            if PlayHistory.heldByQueue(played, shows) {
                let own = PlayHistory.shownByQueue(played, shows)
                let at = own ? place : holder
                if !own { tally.held += 1 }
                if !drawnByQueue(at) {
                    if movedDown(at) {
                        tally.movedDown += 1
                    } else {
                        problems.append("\(label): \(key) the queue's, but no row of it draws it, nor is it to come")
                    }
                }
                if runOf[key] != nil { problems.append("\(label): \(key) drawn twice") }
            } else {
                tally.above += 1
                if !pastKeys.contains(runOf[key] ?? "") { problems.append("\(label): \(key) drawn nowhere") }
                if ours && (drawnByQueue(place) || movedDown(place)) {
                    problems.append("\(label): \(key) above, and its entry a row of the queue's too")
                }
                if holder >= 0 && (drawnByQueue(holder) || movedDown(holder)) {
                    problems.append("\(label): \(key) above, and held by a row of the queue's too")
                }
            }
        }
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
