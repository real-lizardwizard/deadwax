import Foundation
import Testing
@testable import DeadwaxCore

// resume.sim.cjs's round trip (Fixtures/resume/roundtrip.json): 500 runs of 25 steps of Up Next, each step's
// snapshot written by toSave and read back. The phone runs the same seeded generator over its own Up Next and must
// write the web's very texts at every step (digested), the first 40 runs held whole - their queues, and each
// snapshot read back as the web reads it.

@Suite struct ResumeRoundTripTests {
    static let position = 12.5

    /// What toSave's snapshot must read back as: the window of the queue, its account whole - (2.1.3) startedAt past
    /// the song playing's run, as an app before 2.1.3 saved it, lowered to the run.
    static func wanted(_ queue: UpNextQueue, _ saving: Saving) -> UpNextQueue {
        let state = queue.upNext!
        let range = saving.start..<(saving.start + saving.ids.count)
        var run = queue.index
        while run > 0 && state.marks[run].from == .one { run -= 1 }
        return UpNextQueue(tracks: Array(queue.tracks[range]), index: queue.index - saving.start, upNext: UpNextState(
            id: state.id, marks: Array(state.marks[range]), source: state.source, shuffle: state.shuffle, nextKey: state.nextKey,
            startedAt: min(max(0, state.startedAt - saving.start), run - saving.start), left: state.left, paged: state.paged,
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
        var histories = 0
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
                //? (2.1.3) History after a reload is History before it - the same rows, keys and songs
                if let history = Self.historyBack(queue, saving) {
                    failures += 1
                    Issue.record("run \(run) step \(step): History came back otherwise: \(history)")
                } else if !historyRows(queue).isEmpty {
                    histories += 1
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
        #expect(histories > 5_000, "\(histories) steps with a History")
    }

    /// The window read back has the History the queue had (nil), or the two as "key:id" lists.
    static func historyBack(_ queue: UpNextQueue, _ saving: Saving) -> String? {
        let range = saving.start..<(saving.start + saving.ids.count)
        let bare = queue.tracks[range].map { track -> QueueTrack in
            var plain = track
            plain.level = nil
            return plain
        }
        guard let back = fromSnapshot(saving.snapshot, tracks: bare, index: saving.index, setting: .auto) else {
            return historyRows(queue).isEmpty ? nil : "nothing read back"
        }
        let rows = { (q: UpNextQueue) in historyRows(q).map { "\($0.key):\($0.track.id)" } }
        return rows(back) == rows(queue) ? nil : "\(rows(back)) for \(rows(queue))"
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
        //? (2.1.15) the run's queue under its own id, as the export gives it: every snapshot carries it
        var queue = toppedUp(startUpNext(tracks, start: start, shuffle: shuffle, random: random.next, paged: paged,
                                         id: "rt-\(run)"), mode, random: random.next)
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
                //? (2.1.3) a row's tap - of History's now and then (an entry before the song playing)
                let before = queue.upNext!.marks.prefix(queue.index).map(\.key)
                let key = !before.isEmpty && random.next() < 0.3 ? before[pick(before.count)] : someKey()
                if let jumped = jumpedTo(queue, key) { queue = jumped.queue.at(jumped.index) }
            case 9:
                if let next = onward(queue) { queue = queue.at(next) }
            case 10:
                //? (2.1.3) as the player moves now (wentBack), or - half the time - as an app before 2.1.3 saved it
                if case .go(let index) = backward(queue, position: 0) {
                    queue = random.next() < 0.5 ? wentBack(queue, index) : queue.at(index)
                }
            default:
                queue = queue.at(min(queue.index + 1, queue.tracks.count - 1))
            }
            queue = toppedUp(queue, mode, random: random.next)
            each(queue)
        }
    }
}

/// (2.1.3) History across a reload, as resume.sim.cjs holds it at the window's edge and after an old pick-up.
@Suite struct ResumeHistoryTests {
    private func readBack(_ queue: UpNextQueue, position: Double) -> UpNextQueue? {
        let saving = toSave(queue, position: position)
        let window = Array(queue.tracks[saving.start..<(saving.start + saving.ids.count)])
        return fromSnapshot(saving.snapshot, tracks: window, index: saving.index, setting: .auto)
    }
    private func rows(_ queue: UpNextQueue) -> [String] { historyRows(queue).map { "\($0.key):\($0.track.id)" } }

    @Test func historyAtTheWindowsEdgeIsTheSameAfterAReload() {
        // song 100 played three times under Repeat One, its first play the 51st entry back: History stops short of it
        var q = toppedUp(startUpNext(simAlbum(200), start: 0).at(99), .one)
        q = toppedUp(q.at(100), .one).at(101)
        q = withRepeat(q, .off).at(151)
        let back = readBack(q, position: 0)
        #expect(rows(q).count == 49 && rows(q).first == "\(q.upNext!.marks[102].key):101")
        #expect(back.map(rows) == rows(q))
        #expect(UpNext.historyBack == Resume.before)
    }

    @Test func aStartedAtSavedPastTheIndexIsLoweredSoHistoryShowsTheSongGoneBackTo() {
        // the iPhone's 0.2 (or the web's 2.1.2): an album started at 5, Previous to 4 - startedAt left at 4
        let old = startUpNext(simAlbum(10), start: 4).at(3)
        #expect(old.upNext?.startedAt == 4)
        var on = readBack(old, position: 12)!
        #expect(on.upNext?.startedAt == 3)
        on = on.at(onward(on)!)
        on = on.at(onward(on)!)
        #expect(on.current?.id == "6" && historyRows(on).map(\.track.id) == ["4", "5"])
    }
}
