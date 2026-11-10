import Foundation
import Testing
@testable import DeadwaxCore

/// Up Next's invariant by property, as ui/test/upnext.sim.cjs checks it (:157-231): seeded runs of 30 steps - every
/// edit, top-up and forward move, its draws and its choices from the one Park-Miller generator, in the sim's order -
/// each step checked. Fixtures/upnext/property.json holds a digest of the queue each of the sim's 2,000 runs ended
/// with (made by export-traces.cjs from the same loop), so the first test runs the very queues the sim checks.
/// (Previous isn't among the steps: going back across another song's copies can leave the order the invariant
/// describes - the traces pin what it does instead.)
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
        for run in 0..<2000 {
            let queue = propertyRun(run, Seeded(Int64(run + 1)), sizes: 6, problems: &problems)
            if run < digests.count && digest(queue) != digests[run] { unlike.append(run) }
        }
        #expect(problems.isEmpty, "\(problems)")
        #expect(unlike.isEmpty, "\(unlike.count) runs ended unlike the sim's, the first \(unlike.prefix(5))")
    }

    @Test func theInvariantHoldsOverLongerLists() {
        var problems: [String] = []
        var sizes = Set<Int>()
        var shuffled = 0
        for run in 0..<2000 {
            let random = Seeded(Int64(run) * 1_000_003 % 2_147_483_646 + 1)
            _ = random.next()
            let queue = propertyRun(run, random, sizes: 12, problems: &problems)
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

    /// One of the sim's runs: a list of 1...`sizes` songs started, then 30 steps, each checked; the queue it ended with.
    private func propertyRun(_ run: Int, _ random: Seeded, sizes: Int, problems: inout [String]) -> UpNextQueue {
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
        for step in 0..<30 {
            let before = queue
            let op = pick(12)
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
                if op == 8 {
                    if let jumped = jumpedTo(queue, someKey()) {
                        let kept = jumped.index == queue.index
                            && (0...queue.index).allSatisfy { jumped.tracks[$0] == queue.tracks[$0] }
                        if !kept { note(step, "a jump touched the song playing or before it") }
                        if let next = onward(jumped) { queue = jumped.at(next) } else { note(step, "a jump with nothing to move onto") }
                    }
                } else if op == 9 {
                    if let next = onward(queue) { queue = queue.at(next) }
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
            if let wrong = shape(queue) { note(step, "op \(op): \(wrong)") }
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
