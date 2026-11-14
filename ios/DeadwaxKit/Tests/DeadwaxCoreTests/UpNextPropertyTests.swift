import Foundation
import Testing
@testable import DeadwaxCore

/// Up Next's invariant by property, as ui/test/upnext.sim.cjs checks it (:195-460): seeded runs of 30 steps - every
/// edit, top-up and forward move, a row of Up Next's or History's tapped, Previous by wentBack (2.1.3), older rows of
/// the play history brought back (2.1.18), its draws and its choices from the one Park-Miller generator, in the sim's
/// order - each step checked. Fixtures/upnext/property.json holds a digest of the queue each of the sim's 2,000 runs
/// ended with (made by export-traces.cjs from the same loop), so the first test runs the very queues the sim checks.
/// After Previous or a roll-back the order behind the place is as it played (`loose`); and after every step History is
/// exactly what Previous walks back through, by place and by song, every copy is of its run's song, Up Next draws every
/// song up to the furthest played and what was drawn after it, in order, and every row drawn is reached by its tap.
///
/// (2.1.18) The sim lets each seed's first number go - from a seed under 2,000 it is under 0.016, so every run had
/// been a one-song list - and one run in twenty is a long album (55-74 songs), so History's 50 and the older rows
/// before it come in. A History tap is a roll-back (the same queue, the place moved back to the row - exactly
/// Previous's walk to it with no copies anywhere); older rows brought back are each its own entry, first, in order -
/// moved, or a new song added - with their starts, the queue from History's first row on after them as it was. The
/// second test runs the same loop from seeds spread over the generator's range, lists of 1-12.
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
            let random = Seeded(Int64(run + 1))
            _ = random.next()
            let long = run % 20 == 7
            if long { tally.longRuns += 1 }
            let size = long ? 55 + random.pick(20) : 1 + random.pick(6)
            let queue = propertyRun(run, random, size: size, problems: &problems, tally: &tally)
            if run < digests.count && digest(queue) != digests[run] { unlike.append(run) }
        }
        #expect(problems.isEmpty, "\(problems)")
        #expect(tally.walkedBack > 500 && tally.historyTaps > 500 && tally.drawnChecked > 10_000, "\(tally)")
        #expect(tally.walkedTo > 300 && tally.brought > 500 && tally.broughtMoved > 200 && tally.broughtNew > 500
                && tally.longRuns > 50, "\(tally)")
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
            let queue = propertyRun(run, random, size: 1 + random.pick(12), problems: &problems, tally: &tally)
            sizes.insert(queue.upNext?.source.count ?? 0)
            if queue.upNext?.shuffle == true { shuffled += 1 }
        }
        #expect(problems.isEmpty, "\(problems)")
        #expect(sizes == Set(1...12) && shuffled > 500)
        #expect(tally.brought > 500 && tally.historyTaps > 500, "\(tally)")
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

    /// How much of 2.1.3 and 2.1.18 the runs reached: Previous moves, History taps (roll-backs), drawn rows tapped; a
    /// History tap held to Previous's walk, older rows brought back (moved, new), long albums.
    struct Tally {
        var walkedBack = 0, historyTaps = 0, drawnChecked = 0
        var walkedTo = 0, brought = 0, broughtMoved = 0, broughtNew = 0, longRuns = 0
    }

    /// (2.1.18) upnext.sim's playingKey: the key of the unit playing.
    private func playingKey(_ queue: UpNextQueue) -> Int {
        let marks = queue.upNext?.marks ?? []
        var p = queue.index
        while p > 0 && marks[p].from == .one { p -= 1 }
        return marks[p].key
    }

    /// (2.1.18) upnext.sim's aheadKeys: the rows Up Next draws after the song playing, every one (no cap).
    private func aheadKeys(_ queue: UpNextQueue, _ mode: Repeat) -> [Int] {
        let view = upNextView(queue, mode, limit: Int.max)
        return (view.added + (view.list?.rows ?? [])).map(\.key)
    }

    /// (2.1.18) upnext.sim's firstShown: where History's rows begin - its first row's place, else the song playing's.
    private func firstShown(_ queue: UpNextQueue) -> Int {
        let marks = queue.upNext?.marks ?? []
        let key = historyRows(queue).first?.key ?? playingKey(queue)
        return marks.firstIndex { $0.key == key } ?? -1
    }

    /// One of the sim's runs: a list of `size` songs started, then 30 steps, each checked; the queue it ended with.
    private func propertyRun(_ run: Int, _ random: Seeded, size: Int, problems: inout [String],
                             tally: inout Tally) -> UpNextQueue {
        var found: [String] = []
        func note(_ step: Int, _ what: String) {
            if found.count < 8 { found.append("run \(run) step \(step): \(what)") }
        }
        let pick = { (count: Int) in random.pick(count) }
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
            let op = pick(15)
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
                    let jump = jumpedTo(queue, key, mode)
                    if let jumped = jump, jumped.back {
                        //? (2.1.18) History's: a roll-back, the queue already at the row
                        rolledBack(queue, jumped, to: place, key: key, fromHistory: fromHistory, mode,
                                   note: { note(step, $0) }, tally: &tally)
                        queue = jumped.queue
                        back = true
                    } else if let jumped = jump {
                        if fromHistory { note(step, "a row History draws jumped to, not rolled back to") }
                        let kept = jumped.queue.index == queue.index
                            && (0...queue.index).allSatisfy {
                                jumped.queue.tracks[$0] == queue.tracks[$0] && jumped.queue.upNext?.marks[$0] == queue.upNext?.marks[$0]
                            }
                        if !kept { note(step, "a jump's edit touched the song playing or before it") }
                        if !(jumped.index > queue.index && jumped.index < jumped.queue.tracks.count) {
                            note(step, "a jump to \(jumped.index) from \(queue.index)")
                        }
                        if place <= queue.index { note(step, "entry \(place), not drawn in History, jumped to") }
                        if jumped.queue.upNext?.marks[jumped.index].key != key { note(step, "an Up Next tap landed elsewhere") }
                        if jumped.queue.ids.sorted() != queue.ids.sorted() { note(step, "an Up Next tap dropped or added a song") }
                        queue = jumped.queue.at(jumped.index)
                    } else if fromHistory {
                        note(step, "a row History draws refused")
                    }
                } else if op == 14 {
                    //? (2.1.18) older rows of the play history brought back, oldest first: entries of this queue (before
                    //? History's floor or not, in order or not, copies, another song than theirs, one twice) and songs from
                    //? elsewhere - each row's song as UpNext.tsx passes it, at a level of its own
                    let from = firstShown(queue)
                    let marks = queue.upNext?.marks ?? []
                    let rows = (0..<(1 + pick(4))).map { i -> Brought in
                        let starts = (0..<(1 + pick(2))).map { k in Int64(run * 1000 + step * 10 + i * 3 + k) }
                        if random.next() < 0.6 {
                            let range = random.next() < 0.8 ? from : queue.tracks.count
                            let p = pick(max(1, range))
                            var track: QueueTrack
                            if random.next() < 0.9 {
                                track = queue.tracks[p]
                                track.level = random.next() < 0.5 ? .album : .track
                            } else {
                                track = simTrack("x\(extra)")
                                extra += 1
                            }
                            return Brought(track: track, starts: starts, entry: marks[p].key)
                        }
                        let track = simTrack("p\(extra)")
                        extra += 1
                        let entry: Int? = random.next() < 0.5 ? nil : (queue.upNext?.nextKey ?? 0) + 5
                        return Brought(track: track, starts: starts, entry: entry)
                    }
                    if let jump = broughtBack(queue, rows, mode), jump.back, jump.index == 0, jump.queue.index == 0 {
                        broughtRows(queue, jump.queue, rows, from: from, mode, note: { note(step, $0) }, tally: &tally)
                        queue = jump.queue
                        back = true
                    } else {
                        note(step, "older rows: not a roll-back to the first")
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

    /// (2.1.18) A History tap, as upnext.sim checks it: History's rows alone, and the same queue with the place moved
    /// back to the row - outside Repeat One less the copies after it (a row plays once) - nothing added; every row from
    /// it on drawn as it was, now to come (the row tapped the card, then History's rows after it, the song that was
    /// playing, Playing Next, the list); History above it the rows above the row tapped; and with no copies anywhere,
    /// exactly Previous's walk to it, one row at a time.
    private func rolledBack(_ queue: UpNextQueue, _ jumped: Jump, to place: Int, key: Int, fromHistory: Bool, _ mode: Repeat,
                            note: (String) -> Void, tally: inout Tally) {
        guard let state = queue.upNext else { return }
        if !fromHistory { note("entry \(place), not drawn in History, rolled back to") }
        tally.historyTaps += 1
        let keeps = { (i: Int) -> Bool in !(mode != .one && i > place && state.marks[i].from == .one) }
        let wantTracks = queue.tracks.indices.filter(keeps).map { queue.tracks[$0] }
        let wantMarks = state.marks.indices.filter(keeps).map { state.marks[$0] }
        let j = jumped.queue
        if jumped.index != place || j.index != place || j.tracks != wantTracks || j.upNext?.marks != wantMarks
            || j.upNext?.nextKey != state.nextKey {
            note("History's tap: not the same queue, moved back to the row")
        }
        let drawnHistory = historyRows(queue)
        let tappedAt = drawnHistory.firstIndex { $0.key == key } ?? 0
        let was = drawnHistory[tappedAt...].map(\.key) + [playingKey(queue)] + aheadKeys(queue, mode)
        let now = [playingKey(j)] + aheadKeys(j, mode)
        if was != now { note("History's tap: drawn \(now) where \(was) was") }
        let above = drawnHistory[..<tappedAt].map(\.key)
        let nowHistory = historyRows(j).map(\.key)
        if nowHistory.count < above.count || Array(nowHistory.suffix(above.count)) != above {
            note("History's tap: History above it rewritten")
        }
        if !state.marks.contains(where: { $0.from == .one }) {
            var w = queue
            while w.index > place {
                guard case .go(let index) = backward(w, position: 0) else { break }
                w = wentBack(w, index)
            }
            if w.ids != j.ids || w.index != j.index || w.upNext != j.upNext { note("History's tap: not where Previous walks to") }
            tally.walkedTo += 1
        }
    }

    /// (2.1.18) Older rows brought back, as upnext.sim checks them: each row its own entry, first, in order - moved (the
    /// entry it names, kept whole) while that is before History's floor, not a copy, of the row's song and after the
    /// last moved; else a new song added - with its starts; then the queue from History's first row on, as it was
    /// (outside Repeat One less its copies); drawn as they play - the rows, History's songs, the song that was playing,
    /// then Up Next as it was; History empty, startedAt 0, the queue's id kept.
    private func broughtRows(_ queue: UpNextQueue, _ j: UpNextQueue, _ rows: [Brought], from: Int, _ mode: Repeat,
                             note: (String) -> Void, tally: inout Tally) {
        guard let state = queue.upNext, let now = j.upNext else { return }
        tally.brought += 1
        let marks = state.marks
        var last = -1
        for (i, row) in rows.enumerated() {
            let p = row.entry.flatMap { entry in marks.firstIndex { $0.key == entry } } ?? -1
            let moves = p > last && p < from && marks[p].from != .one && queue.tracks[p].id == row.track.id
            if moves { last = p }
            guard i < now.marks.count else {
                note("older row \(i): not in the queue")
                continue
            }
            let mark = now.marks[i]
            //? in parts, each a few comparisons: one ternary of && chains is slow to type-check in newer Swift
            let right: Bool
            if moves {
                let place = mark.key == marks[p].key && mark.from == marks[p].from
                let round = mark.at == marks[p].at && mark.pass == marks[p].pass
                right = place && round && j.tracks[i] == queue.tracks[p]
            } else {
                let added = mark.from == .added && mark.key >= state.nextKey
                let unplaced = mark.at == -1 && mark.pass == -1
                right = added && unplaced && j.tracks[i] == row.track
            }
            if moves { tally.broughtMoved += 1 } else { tally.broughtNew += 1 }
            if !right || mark.starts != row.starts { note("older row \(i): not \(moves ? "moved" : "a new song added") with its starts") }
        }
        let keeps = { (i: Int) -> Bool in i >= from && !(mode != .one && marks[i].from == .one) }
        let rest = queue.tracks.indices.filter(keeps)
        let sameLength = j.tracks.count == rows.count + rest.count
        //? read only at the same length: past it the indexes run off the end
        let restMoved = sameLength && rest.enumerated().contains { (n: Int, i: Int) -> Bool in
            j.tracks[rows.count + n] != queue.tracks[i] || now.marks[rows.count + n] != marks[i]
        }
        if !sameLength || restMoved {
            note("older rows: the queue after them not as it was")
        }
        let was = now.marks.prefix(rows.count).map(\.key) + historyRows(queue).map(\.key) + [playingKey(queue)] + aheadKeys(queue, mode)
        let drawn = [playingKey(j)] + aheadKeys(j, mode)
        if was != drawn { note("older rows: drawn \(drawn) where \(was) was") }
        if now.startedAt != 0 || !historyRows(j).isEmpty || now.id != state.id {
            note("older rows: History, startedAt or the queue's id not as they should be")
        }
    }

    /// (2.1.3) What upnext.sim checks after every step: startedAt at or before the song playing; History exactly the
    /// units Previous walks back through, down to its floor, by place and by song; every copy of its run's song; the
    /// rows drawn on their side of the song playing, none twice; (2.1.18) every song up to the furthest played and what
    /// was drawn after it while it played drawn, whatever its time round, in order, each once - else every song before
    /// the next time round; and every row reached by its tap.
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
        //? the end of the time round shown from a place: past the copies after it, up to the first list song of another round
        let end = { (q: UpNextQueue) -> Int in
            let shown = shownPass(q)
            let marks = q.upNext?.marks ?? []
            var p = q.index + 1
            while p < marks.count && marks[p].from == .one { p += 1 }
            while p < marks.count && !(marks[p].from == .source && marks[p].pass != shown) { p += 1 }
            return p
        }
        let reachAt = state.reached.flatMap { reached in marks.firstIndex { $0.key == reached } } ?? -1
        let stop = max(end(queue), reachAt > queue.index ? end(queue.at(reachAt)) : 0)
        let want = (queue.index + 1..<max(stop, queue.index + 1)).filter { marks[$0].from != .one }.map { marks[$0].key }
        let pending = state.paged.map { max(0, $0.total - $0.fetched) } ?? 0
        let drawnCount = view.added.count + (view.list.map { $0.rows.count + $0.more - pending } ?? 0)
        if drawnCount != want.count { note("Up Next draws \(drawnCount) of the \(want.count) songs to come") }
        let every = aheadKeys(queue, mode)
        if every != want { note("Up Next draws \(every) where \(want) play") }
        for row in ahead + view.history {
            tally.drawnChecked += 1
            guard let jumped = jumpedTo(queue, row.key, mode), jumped.queue.tracks[jumped.index] == row.track else {
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

    /// export-traces.cjs's canonical line, FNV-1a'd - (2.1.18) with how far it had got, the starts each row brought back
    /// carries, and the entries' levels.
    private func digest(_ queue: UpNextQueue) -> String {
        guard let state = queue.upNext else { return "" }
        let char: (MarkFrom) -> String = { $0 == .source ? "s" : $0 == .added ? "a" : "o" }
        let level: (Level?) -> String = { $0 == .album ? "a" : $0 == .track ? "t" : "-" }
        //? each part on its own, its type spelled out: as one array literal CI's Xcode 26.6 gave up type-checking it
        let marks: String = state.marks.map { (mark: Mark) -> String in
            "\(mark.key)\(char(mark.from))\(mark.at)/\(mark.pass)"
        }.joined(separator: ",")
        let left: String = state.left.map { (each: LeftOut) -> String in "\(each.pass)/\(each.at)" }
            .joined(separator: ",")
        let reached: String = state.reached.map { (at: Int) -> String in String(at) } ?? ""
        let starts: String = state.marks.compactMap { (mark: Mark) -> String? in
            guard let each = mark.starts else { return nil }
            return "\(mark.key):\(each.map { (moment: Int64) -> String in String(moment) }.joined(separator: "."))"
        }.joined(separator: ",")
        let levels: String = queue.tracks.map { (track: QueueTrack) -> String in level(track.level) }.joined()
        let parts: [String] = [
            "\(queue.index)",
            queue.ids.joined(separator: ","),
            marks,
            state.source.map { (song: QueueTrack) -> String in song.id }.joined(separator: ","),
            "\(state.shuffle ? 1 : 0),\(state.nextKey),\(state.startedAt)",
            left,
            reached,
            starts,
            levels,
        ]
        let line = parts.joined(separator: ";")
        var hash: UInt32 = 0x811c_9dc5
        for byte in line.utf8 {
            hash = (hash ^ UInt32(byte)) &* 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}
