import Foundation
import Testing
@testable import DeadwaxCore

/// The Swift port replays what the web app's TypeScript did (Fixtures/upnext/, written by
/// ios/scripts/export-traces.cjs): the same inputs, the same random numbers, and after every op the same queue,
/// field by field - or the very queue it was given where the TypeScript handed that back. A failure names the trace
/// (or scenario), the op and the field, and stops that trace: everything after it would differ too.
@Suite struct UpNextTraceTests {
    @Test func everyTraceReplays() throws {
        let file = try Fixtures.json("upnext/traces.json")
        let songs = try #require(file["songs"]?.object).compactMapValues(queueTrack)
        let traces = try #require(file["traces"]?.array)
        #expect(traces.count == 150)
        var replayed = 0
        var failed = 0
        for trace in traces {
            let seed = trace["seed"]?.int ?? -1
            var replay = Replay(songs: songs)
            for (n, op) in (trace["ops"]?.array ?? []).enumerated() {
                if let problem = replay.run(op) {
                    Issue.record("trace \(seed), op \(n) (\(op["op"]?.string ?? "?")): \(problem)")
                    failed += 1
                    break
                }
                replayed += 1
            }
            if failed >= 10 { break }
        }
        let ops = traces.reduce(0) { $0 + ($1["ops"]?.array?.count ?? 0) }
        #expect(replayed == ops, "replayed \(replayed) of \(ops) ops")
    }

    @Test func everyScenarioReplays() throws {
        let file = try Fixtures.json("upnext/scenarios.json")
        let scenarios = try #require(file["scenarios"]?.array)
        #expect(scenarios.count > 40)
        var ops = 0
        for scenario in scenarios {
            let name = scenario["name"]?.string ?? "?"
            var replay = Replay(songs: (scenario["songs"]?.object ?? [:]).compactMapValues(queueTrack))
            for (n, op) in (scenario["ops"]?.array ?? []).enumerated() {
                if let problem = replay.run(op) {
                    Issue.record("scenario \"\(name)\", op \(n) (\(op["op"]?.string ?? "?")): \(problem)")
                    break
                }
                ops += 1
            }
        }
        #expect(ops > 350)
    }

    @Test func theWordsAndTheNumbersAreTheWebs() throws {
        let file = try Fixtures.json("upnext/scenarios.json")
        let constants = try #require(file["constants"])
        #expect(constants["REPEAT_AHEAD"]?.int == UpNext.repeatAhead)
        #expect(constants["UP_NEXT_DRAWN"]?.int == UpNext.drawn)
        #expect(constants["TOP_UP_HEARD_S"]?.double == UpNext.topUpHeardSeconds)
        #expect(constants["RESTART_AFTER_SECONDS"]?.double == UpNext.restartAfterSeconds)
        #expect(constants["HISTORY_BACK"]?.int == UpNext.historyBack && UpNext.historyBack == Resume.before)
        #expect(constants["REPEATS"]?.array?.compactMap(\.string) == Repeat.allCases.map(\.rawValue))

        let scenario = try #require(file["scenarios"]?.array?.first { $0["name"]?.string == "the words" })
        let songs = (scenario["songs"]?.object ?? [:]).compactMapValues(queueTrack)
        let words = try #require(scenario["words"]?.array)
        #expect(words.count > 20)
        for word in words {
            let expected = word["result"]?.string
            let mode = word["repeat"]?.string.flatMap(Repeat.init(rawValue:)) ?? .off
            let said: String?
            switch word["fn"]?.string {
            case "listTitle":
                said = listTitle((word["ids"]?.array ?? []).compactMap { $0.string.flatMap { songs[$0] } }, again: word["again"]?.bool ?? false)
            case "queuedWords":
                said = queuedWords(word["how"]?.string == "next" ? .next : .last, label: word["label"]?.string ?? "")
            case "repeatLabel": said = repeatLabel(mode)
            case "nextRepeat": said = nextRepeat(mode).rawValue
            case "upNextLabel": said = upNextLabel(shuffle: word["shuffle"]?.bool ?? false, repeat: mode)
            case "shuffleLabel": said = shuffleLabel(word["scope"]?.string.flatMap(PagedScope.init(rawValue:)))
            default: said = nil
            }
            #expect(said != nil && said == expected, "\(word["fn"]?.string ?? "?"): \(said ?? "nothing"), the web's \(expected ?? "nothing")")
        }
    }
}

/// The numbers a recorded op drew, handed out in order.
final class Tape {
    private let states: [Int64]
    private(set) var used = 0

    init(_ json: JSONValue?) {
        states = (json?.array ?? []).compactMap { $0.double.map { Int64($0) } }
    }

    func next() -> Double {
        defer { used += 1 }
        //? an exhausted tape: the port drew more than the TypeScript - said after the op; a number meanwhile
        guard used < states.count else { return 0.5 }
        return Double(states[used] - 1) / 2_147_483_646
    }

    /// What's wrong with how the op drew, if anything.
    var problem: String? {
        used == states.count ? nil : "drew \(used) random numbers where the TypeScript drew \(states.count)"
    }
}

/// One trace's or scenario's queue, the ops made on it one at a time.
struct Replay {
    let songs: [String: QueueTrack]
    var queue = UpNextQueue.empty
    var kept: [String: UpNextQueue] = [:]

    init(songs: [String: QueueTrack]) {
        self.songs = songs
    }

    private func tracks(_ json: JSONValue?) -> [QueueTrack]? {
        guard let ids = json?.array else { return nil }
        let found = ids.compactMap { $0.string.flatMap { songs[$0] } }
        return found.count == ids.count ? found : nil
    }

    /// Runs one op; what differs from the record, or nil.
    mutating func run(_ op: JSONValue) -> String? {
        guard let name = op["op"]?.string else { return "no op" }
        let tape = Tape(op["randoms"])
        let random = { tape.next() }
        let mode = op["repeat"]?.string.flatMap(Repeat.init(rawValue:)) ?? .off
        var result: UpNextQueue?
        var answer: String?

        switch name {
        case "start":
            guard let list = tracks(op["ids"]) else { return "a song not in the table" }
            result = startUpNext(list, start: op["start"]?.int, shuffle: op["shuffle"]?.bool ?? false, random: random,
                                 paged: op["paged"].flatMap(paged))
        case "toppedUp": result = toppedUp(queue, mode, random: random)
        case "withRepeat": result = withRepeat(queue, mode)
        case "withShuffle": result = withShuffle(queue, op["on"]?.bool ?? false, random: random)
        case "withNext", "withLast":
            guard let list = tracks(op["ids"]) else { return "a song not in the table" }
            result = name == "withNext" ? withNext(queue, list) : withLast(queue, list)
        case "withoutKey": result = withoutKey(queue, op["key"]?.int ?? -99)
        case "movedKey": result = movedKey(queue, op["key"]?.int ?? -99, to: op["to"]?.int ?? 0)
        case "withoutAdded": result = withoutAdded(queue)
        case "jumpedTo":
            let jumped = jumpedTo(queue, op["key"]?.int ?? -99)
            if op["result"]?.isNull == true {
                return jumped == nil ? tape.problem : "jumped, where the TypeScript gave null"
            }
            guard let jumped else { return "null, where the TypeScript jumped" }
            //? (2.1.3) the edit, then the index to move to - the next op (setIndex) makes the move
            if jumped.index != op["index"]?.int { return "a jump to \(jumped.index), the web's \(describe(op["index"]))" }
            result = jumped.queue
        case "wentBack": result = wentBack(queue, op["index"]?.int ?? -99)
        case "withMore":
            guard let list = tracks(op["ids"]) else { return "a song not in the table" }
            result = withMore(queue, token: op["token"]?.string ?? "", tracks: list, next: op["next"].flatMap(paged))
        case "setIndex": result = queue.at(op["index"]?.int ?? -99)
        case "setPaged":
            var next = queue
            next.upNext?.paged = op["paged"].flatMap(paged)
            result = next
        case "plain":
            guard let list = tracks(op["ids"]) else { return "a song not in the table" }
            result = UpNextQueue(tracks: list, index: op["index"]?.int ?? -99)
        case "empty": result = .empty
        case "set":
            guard let state = op["state"], let made = queueFrom(state) else { return "a state that can't be made" }
            queue = made
            return nil
        case "keep":
            kept[op["name"]?.string ?? ""] = queue
            return nil
        case "use":
            guard let named = kept[op["name"]?.string ?? ""] else { return "nothing kept as that" }
            queue = named
            return nil

        case "onward": answer = differsInt(onward(queue), op["result"])
        case "nextIndex": answer = differsInt(nextIndex(queue), op["result"])
        case "shownPass": answer = differsInt(shownPass(queue), op["result"])
        case "pastCopies": answer = differsInt(pastCopies(queue, from: op["from"]?.int ?? -99), op["result"])
        case "backward":
            let action = backward(queue, position: op["position"]?.double ?? 0)
            let expected = op["result"]
            switch action {
            case .restart: answer = expected?["kind"]?.string == "restart" ? nil : "restart, the web's \(describe(expected))"
            case .go(let index):
                answer = expected?["kind"]?.string == "go" && expected?["index"]?.int == index ? nil : "go \(index), the web's \(describe(expected))"
            }
        case "historyRows":
            let rows = op["back"]?.int.map { historyRows(queue, back: $0) } ?? historyRows(queue)
            answer = firstDifference("history", rows.map { "\($0.key) \($0.track.id)" }, rowsOf(op["result"]))
        case "upNextView":
            let view = op["limit"]?.int.map { upNextView(queue, mode, limit: $0) } ?? upNextView(queue, mode)
            answer = differsView(view, op["result"])
        default:
            return "an op the replay doesn't know: \(name)"
        }

        if let problem = tape.problem { return problem }
        guard let next = result else { return answer }
        if op["same"]?.bool == true {
            //? the TypeScript handed back the very queue it was given: the port an equal one
            guard next == queue else {
                return "changed the queue where the TypeScript handed back the same one: index \(next.index), ids \(next.ids), " +
                    "marks \(next.upNext?.marks.count ?? 0) (it was index \(queue.index), ids \(queue.ids))"
            }
            return nil
        }
        if let problem = differs(next, op["state"]) { return problem }
        queue = next
        return nil
    }

    /// A queue from a recorded state (the `set` op): the songs from the table.
    func queueFrom(_ state: JSONValue) -> UpNextQueue? {
        guard let index = state["index"]?.int, let tracks = tracks(state["ids"]) else { return nil }
        guard let marks = state["marks"]?.array else { return UpNextQueue(tracks: tracks, index: index) }
        let made = marks.compactMap { mark -> Mark? in
            guard let parts = mark.array, parts.count == 4, let key = parts[0].int, let from = parts[1].string,
                  let at = parts[2].int, let pass = parts[3].int else { return nil }
            let kind: MarkFrom? = from == "s" ? .source : from == "a" ? .added : from == "o" ? .one : nil
            return kind.map { Mark(key: key, from: $0, at: at, pass: pass) }
        }
        guard made.count == marks.count, let source = self.tracks(state["source"]), let shuffle = state["shuffle"]?.bool,
              let nextKey = state["nextKey"]?.int, let startedAt = state["startedAt"]?.int else { return nil }
        let left = (state["left"]?.array ?? []).compactMap { gone -> LeftOut? in
            guard let parts = gone.array, parts.count == 2, let pass = parts[0].int, let at = parts[1].int else { return nil }
            return LeftOut(pass: pass, at: at)
        }
        return UpNextQueue(tracks: tracks, index: index, upNext: UpNextState(
            marks: made, source: source, shuffle: shuffle, nextKey: nextKey, startedAt: startedAt, left: left,
            paged: state["paged"].flatMap(paged),
            pagedRounds: state["pagedRounds"]?.array?.compactMap { held in
                guard let pass = held["pass"]?.int, let kept = held["paged"].flatMap(paged) else { return nil }
                return PagedRound(pass: pass, paged: kept)
            }))
    }

    /// What differs between the queue and the recorded state, field by field - the first difference only, never two
    /// whole arrays (Swift Testing's diff of large collections can kill the test process: notes/ios.md).
    func differs(_ queue: UpNextQueue, _ state: JSONValue?) -> String? {
        guard let state else { return "no state recorded" }
        if queue.index != state["index"]?.int { return "index \(queue.index), the web's \(describe(state["index"]))" }
        let ids = (state["ids"]?.array ?? []).compactMap(\.string)
        if let problem = firstDifference("ids", queue.ids, ids) { return problem }
        for track in queue.tracks where songs[track.id] != track {
            return "the song \(track.id) isn't the table's: \(track)"
        }
        guard let marks = state["marks"]?.array else {
            return queue.upNext == nil ? nil : "an Up Next account where the web has none"
        }
        guard let upNext = queue.upNext else { return "no Up Next account where the web has one" }
        let theirs = marks.map { mark -> String in
            let parts = mark.array ?? []
            return parts.map { $0.string ?? $0.int.map(String.init) ?? "?" }.joined(separator: " ")
        }
        let ours = upNext.marks.map { "\($0.key) \($0.from.rawValue.prefix(1)) \($0.at) \($0.pass)" }
        if let problem = firstDifference("marks", ours, theirs) { return problem }
        if let problem = firstDifference("source", upNext.source.map(\.id), (state["source"]?.array ?? []).compactMap(\.string)) {
            return problem
        }
        if upNext.shuffle != state["shuffle"]?.bool { return "shuffle \(upNext.shuffle), the web's \(describe(state["shuffle"]))" }
        if upNext.nextKey != state["nextKey"]?.int { return "nextKey \(upNext.nextKey), the web's \(describe(state["nextKey"]))" }
        if upNext.startedAt != state["startedAt"]?.int { return "startedAt \(upNext.startedAt), the web's \(describe(state["startedAt"]))" }
        let left = (state["left"]?.array ?? []).map { ($0.array ?? []).compactMap(\.int).map(String.init).joined(separator: "/") }
        if let problem = firstDifference("left", upNext.left.map { "\($0.pass)/\($0.at)" }, left) { return problem }
        let theirPaged = state["paged"].flatMap(paged)
        if (state["paged"] == nil) != (upNext.paged == nil) || theirPaged != upNext.paged {
            return "paged \(String(describing: upNext.paged)), the web's \(describe(state["paged"]))"
        }
        let rounds = state["pagedRounds"]?.array
        if (rounds == nil) != (upNext.pagedRounds == nil) {
            return "pagedRounds \(upNext.pagedRounds == nil ? "absent" : "present") where the web's is \(rounds == nil ? "absent" : "present")"
        }
        if let rounds, let ours = upNext.pagedRounds {
            let theirs = rounds.map { "\($0["pass"]?.int ?? -99) \(String(describing: $0["paged"].flatMap(paged)))" }
            if let problem = firstDifference("pagedRounds", ours.map { "\($0.pass) \(String(describing: Optional($0.paged)))" }, theirs) {
                return problem
            }
        }
        return nil
    }

    private func differsInt(_ value: Int?, _ expected: JSONValue?) -> String? {
        let theirs = expected?.int
        if value == theirs && (value != nil || expected?.isNull == true) { return nil }
        return "\(value.map(String.init) ?? "nil"), the web's \(describe(expected))"
    }

    private func differsView(_ view: UpNextView, _ expected: JSONValue?) -> String? {
        guard let expected else { return "no view recorded" }
        if view.playing?.id != expected["playing"]?.string { return "playing \(view.playing?.id ?? "none"), the web's \(describe(expected["playing"]))" }
        let rows = rowsOf
        if let problem = firstDifference("history", view.history.map { "\($0.key) \($0.track.id)" }, rows(expected["history"])) {
            return problem
        }
        if let problem = firstDifference("added", view.added.map { "\($0.key) \($0.track.id)" }, rows(expected["added"])) { return problem }
        if let list = expected["list"], !list.isNull {
            guard let ours = view.list else { return "no list, the web's \(describe(list["title"]))" }
            if ours.title != list["title"]?.string { return "list title \(ours.title), the web's \(describe(list["title"]))" }
            if ours.more != list["more"]?.int { return "list more \(ours.more), the web's \(describe(list["more"]))" }
            if let problem = firstDifference("list rows", ours.rows.map { "\($0.key) \($0.track.id)" }, rows(list["rows"])) { return problem }
        } else if let ours = view.list {
            return "a list (\(ours.title)) where the web has none"
        }
        if view.then != expected["then"]?.string { return "then \(view.then ?? "nil"), the web's \(describe(expected["then"]))" }
        if view.repeatOne != expected["repeatOne"]?.bool { return "repeatOne \(view.repeatOne), the web's \(describe(expected["repeatOne"]))" }
        return nil
    }

    /// Recorded rows ([key, id] pairs) as "key id".
    private func rowsOf(_ json: JSONValue?) -> [String] {
        (json?.array ?? []).map { ($0.array ?? []).map { $0.string ?? $0.int.map(String.init) ?? "?" }.joined(separator: " ") }
    }

    private func firstDifference(_ field: String, _ ours: [String], _ theirs: [String]) -> String? {
        for i in 0..<min(ours.count, theirs.count) where ours[i] != theirs[i] {
            return "\(field)[\(i)] is \(ours[i]), the web's \(theirs[i])"
        }
        if ours.count != theirs.count { return "\(field) has \(ours.count), the web's \(theirs.count)" }
        return nil
    }
}

func describe(_ json: JSONValue?) -> String {
    switch json {
    case nil: return "absent"
    case .null?: return "null"
    case .bool(let b)?: return "\(b)"
    case .number(let n)?: return n == n.rounded() ? "\(Int(n))" : "\(n)"
    case .string(let s)?: return "\"\(s)\""
    case .array(let a)?: return "[\(a.map { describe($0) }.joined(separator: ", "))]"
    case .object(let o)?: return "{\(o.keys.sorted().map { "\($0): \(describe(o[$0]))" }.joined(separator: ", "))}"
    }
}
