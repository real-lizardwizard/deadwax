import Foundation
import Testing
@testable import DeadwaxCore

/// Up Next's invariant by property, as ui/test/upnext.sim.cjs checks it (:175-350): seeded runs of 30 steps - every
/// edit, top-up and forward move, a row of Up Next's or History's tapped, Previous by wentBack (2.1.3), its draws and
/// its choices from the one Park-Miller generator, in the sim's order - each step checked. Fixtures/upnext/
/// property.json holds a digest of the queue each of the sim's 2,000 runs ended with (made by export-traces.cjs from
/// the same loop), so the first test runs the very queues the sim checks. After Previous the order behind the place is
/// as it played (`loose`); and after every step History is exactly what Previous walks back through, by place and by
/// song, every copy is of its run's song, and every row drawn is reached by its tap.
///
/// The sim seeds run n with n + 1, and Park-Miller's first number from a seed under 2,000 is under 0.016 - so every
/// one of the sim's runs starts from a ONE-song list (`1 + pick(6)` is always 1), with songs added after. The second
/// test runs the same loop from seeds spread over the generator's range, its first number let go, lists of 1-12.
@Suite struct UpNextPropertyTests {
    @Test func theInvariantHoldsOverTheSimsTwoThousandRuns() throws {
        let file = try Fixtures.json("upnext/property.json")
        #expect(file["runs"]?.int == 2000 && file["steps"]?.int == 30)
        let digests = (file["digests"]?.array ?? []).flatMap { $0.array ?? [] }.compactMap(\.string)
        #expect(digests.count == 2000)

        var problems: [String] = []
        var unlike: [Int] = []
        var tally = Tally()
        for run in 0..<2000 {
            let queue = propertyRun(run, Seeded(Int64(run + 1)), sizes: 6, problems: &problems, tally: &tally)
            if run < digests.count && digest(queue) != digests[run] { unlike.append(run) }
        }
        #expect(problems.isEmpty, "\(problems)")
        #expect(tally.walkedBack > 500 && tally.historyTaps > 500 && tally.drawnChecked > 10_000, "\(tally)")
        #expect(unlike.isEmpty, "\(unlike.count) runs ended unlike the sim's, the first \(unlike.prefix(5))")
    }

    @Test func theInvariantHoldsOverLongerLists() {
        var problems: [String] = []
        var sizes = Set<Int>()
        var shuffled = 0
        var tally = Tally()
        for run in 0..<2000 {
            let random = Seeded(Int64(run) * 1_000_003 % 2_147_483_646 + 1)
            _ = random.next()
            let queue = propertyRun(run, random, sizes: 12, problems: &problems, tally: &tally)
            sizes.insert(queue.upNext?.source.count ?? 0)
            if queue.upNext?.shuffle == true { shuffled += 1 }
        }
        #expect(problems.isEmpty, "\(problems)")
        #expect(sizes == Set(1...12) && shuffled > 500)
    }

    @Test func repeatAllShuffledNeverStartsARoundWithTheSongThatEndedTheLast() {
        var starts = 0
        for seed in Int64(1)...1000 {
            for size in [2, 4] {
                let list = startUpNext(simAlbum(size), start: 0, shuffle: true, random: Seeded(seed).next)
                let end = toppedUp(list.at(size - 1), .all, random: Seeded(seed * 7).next)
                if end.tracks[size].id == end.tracks[size - 1].id { starts += 1 }
            }
        }
        #expect(starts == 0)
    }

    @Test func theSameNumbersMakeTheSameQueueAsStartQueue() {
        // startQueue (playQueue.ts) isn't ported - nothing in the app calls it - but its shuffle is the same Fisher-
        // Yates over the same calls: tapping a song still plays THAT song first, every song once.
        let album = simAlbum(5)
        let shuffled = startUpNext(album, start: 3, shuffle: true, random: Seeded(7).next)
        #expect(shuffled.current?.id == "4")
        #expect(shuffled.ids.sorted() == ["1", "2", "3", "4", "5"])
        #expect(shuffled.ids.joined() != "41235")
        let openers = Set([7, 11, 13, 17, 23].map { startUpNext(album, start: nil, shuffle: true, random: Seeded($0).next).current?.id })
        #expect(openers.count > 1)
        #expect(startUpNext(album, start: nil).current?.id == "1")
    }

    /// How much of 2.1.3 the runs reached: Previous moves, History taps, drawn rows tapped.
    struct Tally {
        var walkedBack = 0, historyTaps = 0, drawnChecked = 0
    }

    /// One of the sim's runs: a list of 1...`sizes` songs started, then 30 steps, each checked; the queue it ended with.
    private func propertyRun(_ run: Int, _ random: Seeded, sizes: Int, problems: inout [String],
                             tally: inout Tally) -> UpNextQueue {
        var found: [String] = []
        func note(_ step: Int, _ what: String) {
            if found.count < 8 { found.append("run \(run) step \(step): \(what)") }
        }
        let pick = { (count: Int) in random.pick(count) }
        let size = 1 + pick(sizes)
        var mode = Repeat.allCases[pick(3)]
        let start: Int? = random.next() < 0.3 ? nil : pick(size)
        let shuffle = random.next() < 0.5
        var queue = toppedUp(startUpNext(simAlbum(size), start: start, shuffle: shuffle, random: random.next),
                             mode, random: random.next)
        var extra = 0
        let made = { (prefix: String) -> [QueueTrack] in
            (0..<(1 + pick(2))).map { _ in
                defer { extra += 1 }
                return simTrack("\(prefix)\(extra)")
            }
        }
        var back = false
        for step in 0..<30 {
            let before = queue
            let op = pick(14)
            var edit = true
            let someKey = { () -> Int in
                let keys = (queue.upNext?.marks.dropFirst(queue.index + 1) ?? []).map(\.key)
                return !keys.isEmpty && random.next() < 0.85 ? keys[pick(keys.count)] : pick((queue.upNext?.nextKey ?? 0) + 2)
            }
            switch op {
            case 0: queue = withNext(queue, made("n"))
            case 1: queue = withLast(queue, made("l"))
            case 2: queue = withoutKey(queue, someKey())
            case 3:
                let key = someKey()
                queue = movedKey(queue, key, to: pick(6))
            case 4: queue = withoutAdded(queue)
            case 5: queue = withShuffle(queue, random.next() < 0.5, random: random.next)
            case 6:
                mode = Repeat.allCases[pick(3)]
                queue = toppedUp(withRepeat(queue, mode), mode, random: random.next)
            case 7: queue = toppedUp(queue, mode, random: random.next)
            default:
                edit = false
                if op == 8 || op == 12 {
                    //? 12: a row of History's tap; 8: a row of Up Next's - its keys mostly, any key of the queue's, or none
                    let drawnHistory = historyRows(queue)
                    let key: Int
                    if op == 12 && !drawnHistory.isEmpty {
                        key = drawnHistory[pick(drawnHistory.count)].key
                    } else if random.next() < 0.5 {
                        key = someKey()
                    } else {
                        let marks = queue.upNext?.marks ?? []
                        key = marks[pick(marks.count)].key
                    }
                    let place = queue.upNext?.marks.firstIndex { $0.key == key } ?? -1
                    let fromHistory = drawnHistory.contains { $0.key == key }
                    if let jumped = jumpedTo(queue, key) {
                        let kept = jumped.queue.index == queue.index
                            && (0...queue.index).allSatisfy {
                                jumped.queue.tracks[$0] == queue.tracks[$0] && jumped.queue.upNext?.marks[$0] == queue.upNext?.marks[$0]
                            }
                        if !kept { note(step, "a jump's edit touched the song playing or before it") }
                        if !(jumped.index > queue.index && jumped.index < jumped.queue.tracks.count) {
                            note(step, "a jump to \(jumped.index) from \(queue.index)")
                        }
                        if fromHistory {
                            tally.historyTaps += 1
                            let again = jumped.queue.upNext?.marks[jumped.index]
                            if jumped.queue.tracks[jumped.index] != queue.tracks[place] || again?.from != .added
                                || jumped.queue.tracks.count != queue.tracks.count + 1 {
                                note(step, "History's tap: not that song again, as one song added")
                            }
                            let was = drawnHistory.map(\.key)
                            let now = historyRows(jumped.queue.at(jumped.index)).map(\.key)
                            let gone = was.filter { !now.contains($0) }
                            if gone != Array(was.prefix(gone.count)) || Array(now.prefix(was.count - gone.count)) != Array(was.dropFirst(gone.count)) {
                                note(step, "History's tap rewrote History")
                            }
                        } else {
                            if place <= queue.index { note(step, "entry \(place), not drawn in History, jumped to") }
                            if jumped.queue.upNext?.marks[jumped.index].key != key { note(step, "an Up Next tap landed elsewhere") }
                            if jumped.queue.ids.sorted() != queue.ids.sorted() { note(step, "an Up Next tap dropped or added a song") }
                        }
                        queue = jumped.queue.at(jumped.index)
                    } else if fromHistory {
                        note(step, "a row History draws refused")
                    }
                } else if op == 9 {
                    if let next = onward(queue) { queue = queue.at(next) }
                } else if op == 13 {
                    //? Previous, early: as the player moves (wentBack)
                    if case .go(let index) = backward(queue, position: 0) {
                        queue = wentBack(queue, index)
                        back = true
                        tally.walkedBack += 1
                    }
                } else {
                    queue = queue.ended
                }
                queue = toppedUp(queue, mode, random: random.next)
            }
            guard let state = queue.upNext else {
                note(step, "no Up Next account")
                continue
            }
            let marks = state.marks
            if marks.count != queue.tracks.count { note(step, "marks \(marks.count) for \(queue.tracks.count) songs") }
            if Set(marks.map(\.key)).count != marks.count { note(step, "a key twice") }
            if marks.contains(where: { $0.key >= state.nextKey }) { note(step, "a key past nextKey") }
            if edit {
                if queue.index != before.index { note(step, "op \(op) moved the index") }
                let beforeMarks = before.upNext?.marks ?? []
                for i in 0...max(before.index, 0) where i <= before.index {
                    if queue.tracks[i] != before.tracks[i] || marks[i] != beforeMarks[i] {
                        note(step, "op \(op) changed entry \(i) of the played")
                        break
                    }
                }
            }
            if let wrong = back ? loose(queue) : shape(queue) { note(step, "op \(op): \(wrong)") }
            historyChecks(queue, mode, op: op, note: { note(step, $0) }, tally: &tally)
            for (i, mark) in marks.enumerated() {
                if mark.from == .source && mark.at < 0 { note(step, "entry \(i) of the list has no place in it") }
                if mark.at >= 0 && (mark.at >= state.source.count || state.source[mark.at].id != queue.tracks[i].id) {
                    note(step, "entry \(i) is not its place in the list")
                }
            }
        }
        if problems.count < 8 { problems.append(contentsOf: found.prefix(8 - problems.count)) }
        return queue
    }

    /// (2.1.3) What upnext.sim checks after every step: startedAt at or before the song playing; History exactly the
    /// units Previous walks back through, down to its floor, by place and by song; every copy of its run's song; the
    /// rows drawn on their side of the song playing, none twice, every song before the next time round drawn, and
    /// every row reached by its tap.
    private func historyChecks(_ queue: UpNextQueue, _ mode: Repeat, op: Int, note: (String) -> Void, tally: inout Tally) {
        guard let state = queue.upNext else { return }
        let marks = state.marks
        if state.startedAt > queue.index { note("startedAt \(state.startedAt) past the song playing (\(queue.index))") }
        let floor = max(state.startedAt, queue.index - UpNext.historyBack, 0)
        var walk: [Int] = []
        var heard: [String] = []
        var w = queue
        while case .go(let index) = backward(w, position: 0) {
            var unit = index
            while unit > 0 && marks[unit].from == .one { unit -= 1 }
            if marks[unit].from == .one || unit < floor { break }
            walk.insert(unit, at: 0)
            heard.insert(queue.tracks[index].id, at: 0)
            w = w.at(index)
        }
        let rows = historyRows(queue)
        let drawn = rows.map { row in marks.firstIndex { $0.key == row.key } ?? -1 }
        if drawn != walk { note("History at \(drawn) where Previous walks \(walk)") }
        if rows.map(\.track.id) != heard { note("History names \(rows.map(\.track.id)) where Previous plays \(heard)") }
        for (i, mark) in marks.enumerated() where mark.from == .one {
            var start = i
            while start > 0 && marks[start].from == .one { start -= 1 }
            if queue.tracks[start].id != queue.tracks[i].id { note("op \(op): entry \(i), a copy, in another song's run") }
        }
        let view = upNextView(queue, mode)
        let ahead = view.added + (view.list?.rows ?? [])
        let placeOf = { (key: Int) in marks.firstIndex { $0.key == key } ?? -1 }
        if view.history.contains(where: { placeOf($0.key) >= queue.index }) || ahead.contains(where: { placeOf($0.key) <= queue.index }) {
            note("a row on the wrong side of the song playing")
        }
        if Set((view.history + ahead).map(\.key)).count != view.history.count + ahead.count { note("a row drawn twice") }
        let shown = shownPass(queue)
        var p = queue.index + 1
        var want = 0
        while p < marks.count && marks[p].from == .one { p += 1 }
        while p < marks.count {
            defer { p += 1 }
            if marks[p].from == .one { continue }
            if marks[p].from == .source && marks[p].pass != shown { break }
            want += 1
        }
        let pending = state.paged.map { max(0, $0.total - $0.fetched) } ?? 0
        let drawnCount = view.added.count + (view.list.map { $0.rows.count + $0.more - pending } ?? 0)
        if drawnCount != want { note("Up Next draws \(drawnCount) of the \(want) songs before the next round") }
        for row in ahead + view.history {
            tally.drawnChecked += 1
            guard let jumped = jumpedTo(queue, row.key), jumped.queue.tracks[jumped.index] == row.track else {
                note("row \(row.key) not reached by its tap")
                break
            }
        }
    }

    /// (2.1.3) After Previous: the order behind the place as it played - copies, then units whose list songs' rounds
    /// never go down, songs added among them.
    private func loose(_ queue: UpNextQueue) -> String? {
        var pass = Int.min
        let after = Array(queue.upNext?.marks.dropFirst(queue.index + 1) ?? [])
        for mark in after.drop(while: { $0.from == .one }) where mark.from == .source {
            if mark.pass < pass { return "pass \(mark.pass) after \(pass)" }
            pass = mark.pass
        }
        return nil
    }

    /// After the song playing: copies, then songs added, then the list's time round by time round.
    private func shape(_ queue: UpNextQueue) -> String? {
        var stage = 0
        var pass = Int.min
        for mark in queue.upNext?.marks.dropFirst(queue.index + 1) ?? [] {
            let kind = mark.from == .one ? 0 : mark.from == .added ? 1 : 2
            if kind < stage { return "\(mark.from) after a later kind" }
            stage = kind
            if kind == 2 {
                if mark.pass < pass { return "pass \(mark.pass) after \(pass)" }
                pass = mark.pass
            }
        }
        return nil
    }

    /// export-traces.cjs's canonical line, FNV-1a'd.
    private func digest(_ queue: UpNextQueue) -> String {
        guard let state = queue.upNext else { return "" }
        let char: (MarkFrom) -> String = { $0 == .source ? "s" : $0 == .added ? "a" : "o" }
        let line = [
            "\(queue.index)",
            queue.ids.joined(separator: ","),
            state.marks.map { "\($0.key)\(char($0.from))\($0.at)/\($0.pass)" }.joined(separator: ","),
            state.source.map(\.id).joined(separator: ","),
            "\(state.shuffle ? 1 : 0),\(state.nextKey),\(state.startedAt)",
            state.left.map { "\($0.pass)/\($0.at)" }.joined(separator: ","),
        ].joined(separator: ";")
        var hash: UInt32 = 0x811c_9dc5
        for byte in line.utf8 {
            hash = (hash ^ UInt32(byte)) &* 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}
