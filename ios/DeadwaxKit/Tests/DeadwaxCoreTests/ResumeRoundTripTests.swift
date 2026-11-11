import Foundation
import Testing
@testable import DeadwaxCore

// resume.sim.cjs's round trip (Fixtures/resume/roundtrip.json): 500 runs of 25 steps of Up Next, each step's
// snapshot written by toSave and read back. The phone runs the same seeded generator over its own Up Next and must
// write the web's very texts at every step (digested), the first 40 runs held whole - their queues, and each
// snapshot read back as the web reads it.

@Suite struct ResumeRoundTripTests {
    static let position = 12.5

    /// What toSave's snapshot must read back as: the window of the queue, its account whole.
    static func wanted(_ queue: UpNextQueue, _ saving: Saving) -> UpNextQueue {
        let state = queue.upNext!
        let range = saving.start..<(saving.start + saving.ids.count)
        return UpNextQueue(tracks: Array(queue.tracks[range]), index: queue.index - saving.start, upNext: UpNextState(
            marks: Array(state.marks[range]), source: state.source, shuffle: state.shuffle, nextKey: state.nextKey,
            startedAt: max(0, state.startedAt - saving.start), left: state.left, paged: state.paged,
            pagedRounds: state.pagedRounds))
    }

    /// Reads back whole at its own index, as the web's own check of itself: its window's songs with no level, Auto.
    static func readsBack(_ queue: UpNextQueue, _ saving: Saving) -> String? {
        let range = saving.start..<(saving.start + saving.ids.count)
        let bare = queue.tracks[range].map { track -> QueueTrack in
            var plain = track
            plain.level = nil
            return plain
        }
        let back = fromSnapshot(saving.snapshot, tracks: bare, index: saving.index, setting: .auto)
        return queueDifference(back, wanted(queue, saving))
    }

    @Test func theKeptStatesWriteAndReadAsTheWebs() throws {
        let json = try Fixtures.json("resume/roundtrip.json")
        #expect(json["position"]?.double == Self.position)
        let songs = try ResumeSongs(json["songs"])
        let states = try #require(json["states"]?.array)
        #expect(states.count == 1000)
        for state in states {
            let at = "run \(state["run"]?.int ?? -1) step \(state["step"]?.int ?? -1)"
            let queue = try #require(songs.queue(state["queue"]), "\(at): the queue doesn't rebuild")
            let saving = toSave(queue, position: Self.position)
            #expect(sameText(saving.snapshot, state["snapshot"]?.string), "\(at): snapshot")
            #expect(saving.index == state["index"]?.int && saving.start == state["start"]?.int, "\(at): index/start")
            let difference = Self.readsBack(queue, saving)
            #expect(difference == nil, "\(at): \(difference ?? "")")
        }
    }

    @Test func everyRunOfTheGeneratorWritesTheWebsTexts() throws {
        let json = try Fixtures.json("resume/roundtrip.json")
        let runs = try #require(json["runs"]?.int)
        let steps = try #require(json["steps"]?.int)
        let digests = try #require(json["digests"]?.array)
        let songs = try ResumeSongs(json["songs"])
        let kept = try #require(json["states"]?.array)
        #expect(runs == 500 && steps == 25 && digests.count == runs)
        var counts = (states: 0, behind: 0, paged: 0, left: 0, ones: 0, added: 0, shuffled: 0)
        var failures = 0
        for run in 0..<runs {
            let wantedDigests = try #require(digests[run].array)
            var step = 0
            Self.generate(run: run, steps: steps) { queue in
                defer { step += 1 }
                let saving = toSave(queue, position: Self.position)
                let digest = saving.snapshot.map(unitHash)
                let state = queue.upNext!
                counts.states += 1
                if state.startedAt > queue.index { counts.behind += 1 }
                if state.paged != nil { counts.paged += 1 }
                if !state.left.isEmpty { counts.left += 1 }
                if state.marks.contains(where: { $0.from == .one }) { counts.ones += 1 }
                if state.marks.contains(where: { $0.from == .added }) { counts.added += 1 }
                if state.shuffle { counts.shuffled += 1 }
                guard failures < 10 else { return }
                if digest != wantedDigests[step].string {
                    failures += 1
                    Issue.record("run \(run) step \(step): the snapshot isn't the web's (\(digest ?? "nil") vs \(wantedDigests[step].string ?? "nil"))")
                }
                if let difference = Self.readsBack(queue, saving) {
                    failures += 1
                    Issue.record("run \(run) step \(step) doesn't read back: \(difference)")
                }
                if run < kept.count / steps, let recorded = songs.queue(kept[run * steps + step]["queue"]),
                   let difference = queueDifference(queue, recorded) {
                    failures += 1
                    Issue.record("run \(run) step \(step): the queue isn't the web's: \(difference)")
                }
            }
            #expect(step == steps)
        }
        let c = try #require(json["counts"])
        #expect(counts.states == c["states"]?.int && counts.behind == c["behind"]?.int && counts.paged == c["paged"]?.int)
        #expect(counts.left == c["left"]?.int && counts.ones == c["ones"]?.int && counts.added == c["added"]?.int)
        #expect(counts.shuffled == c["shuffled"]?.int)
    }

    /// export-traces.cjs's round trip, step for step and draw for draw (its arguments drawn in JavaScript's order).
    static func generate(run: Int, steps: Int, each: (UpNextQueue) -> Void) {
        let random = Seeded(Int64(run + 7))
        _ = random.next()
        let pick = { (count: Int) in random.pick(count) }
        let level = { random.next() < 0.5 ? Level.album : Level.track }
        let size = 1 + pick(7)
        var mode = Repeat.allCases[pick(3)]
        let paged = run % 5 == 0 ? Paged(token: "t\(run)", total: size + 6, fetched: size, scope: .yours, level: .track) : nil
        let tracks = rAlbum(size, level: level())
        let start: Int? = random.next() < 0.3 ? nil : pick(size)
        let shuffle = random.next() < 0.5
        var queue = toppedUp(startUpNext(tracks, start: start, shuffle: shuffle, random: random.next, paged: paged), mode,
                             random: random.next)
        var extra = 0
        let made = { (prefix: String, level: () -> Level) -> QueueTrack in
            defer { extra += 1 }
            return rTrack("\(prefix)\(extra)", level: level())
        }
        for _ in 0..<steps {
            let op = pick(12)
            let someKey = { () -> Int in
                let keys = queue.upNext!.marks.dropFirst(queue.index + 1).map(\.key)
                if !keys.isEmpty && random.next() < 0.85 { return keys[pick(keys.count)] }
                return pick(queue.upNext!.nextKey + 2)
            }
            switch op {
            case 0: queue = withNext(queue, (0..<(1 + pick(2))).map { _ in made("n", level) })
            case 1: queue = withLast(queue, (0..<(1 + pick(2))).map { _ in made("l", level) })
            case 2: queue = withoutKey(queue, someKey())
            case 3:
                let key = someKey()
                queue = movedKey(queue, key, to: pick(6))
            case 4: queue = withoutAdded(queue)
            case 5: queue = withShuffle(queue, random.next() < 0.5, random: random.next)
            case 6:
                mode = Repeat.allCases[pick(3)]
                queue = toppedUp(withRepeat(queue, mode), mode, random: random.next)
            case 7:
                if let p = queue.upNext?.paged {
                    let more = (0..<(1 + pick(3))).map { _ in made("p", { .track }) }
                    let next = p.fetched >= p.total && mode == .all
                        ? Paged(token: "\(p.token)+", total: 3, fetched: 0, scope: p.scope, level: .track) : nil
                    queue = withMore(queue, token: p.token, tracks: more, next: next)
                } else {
                    queue = toppedUp(queue, mode, random: random.next)
                }
            case 8:
                if let jumped = jumpedTo(queue, someKey()), let next = onward(jumped) { queue = jumped.at(next) }
            case 9:
                if let next = onward(queue) { queue = queue.at(next) }
            case 10:
                if case .go(let index) = backward(queue, position: 0) { queue = queue.at(index) }
            default:
                queue = queue.at(min(queue.index + 1, queue.tracks.count - 1))
            }
            queue = toppedUp(queue, mode, random: random.next)
            each(queue)
        }
    }
}
