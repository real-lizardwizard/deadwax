import Foundation
import Testing
@testable import DeadwaxCore

// What the resume tests share: resume.sim.cjs's songs, the fixtures' songs table and queue records, text compared as
// the web compares it (UTF-16 units, never Swift's canonical equivalence), and the controller's fakes on a virtual
// clock.

/// resume.sim.cjs's song (export-traces.cjs's rTrack): Mezzanine's, with a cover.
func rTrack(_ id: String, level: Level? = nil) -> QueueTrack {
    QueueTrack(id: id, title: "song \(id)", artist: "Massive Attack", album: "Mezzanine", albumId: "mez", coverArt: "al-mez",
               duration: 200, contentType: "audio/flac", suffix: "flac", sampleRate: 44100, bitDepth: 16, channels: 2,
               level: level)
}

/// rAlbum(n, prefix): songs "<prefix>1"..."<prefix>n", every one at `level`.
func rAlbum(_ count: Int, _ prefix: String = "", level: Level? = nil) -> [QueueTrack] {
    (0..<count).map { rTrack("\(prefix)\($0 + 1)", level: level) }
}

/// Two texts the same as JavaScript's `===` says: the same UTF-16 units (Swift's `==` takes "é" for "e\u{301}").
func sameText(_ a: String?, _ b: String?) -> Bool {
    a.map { Array($0.utf16) } == b.map { Array($0.utf16) }
}

/// export-traces.cjs's fnv1a: 32-bit FNV-1a over a text's UTF-16 units, as eight hex digits.
func unitHash(_ text: String) -> String {
    var hash: UInt32 = 0x811c_9dc5
    for unit in text.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 0x0100_0193
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 8 - hex.count) + hex
}

/// The first `count` UTF-16 units of a text, as JavaScript's slice(0, count).
func unitPrefix(_ text: String, _ count: Int) -> [UInt16] {
    Array(text.utf16.prefix(count))
}

/// A WebJSON value written as export-traces.cjs's canonical(): keys sorted by UTF-16 unit, leaves as JSON.stringify.
/// Without recursion - the fixtures nest 1,000 deep, past a test thread's stack in a debug build.
func canonical(_ value: WebJSON.Value) -> String {
    enum Task {
        case value(WebJSON.Value)
        case text(String)
    }
    var tasks: [Task] = [.value(value)]
    var out = ""
    while let task = tasks.popLast() {
        switch task {
        case .text(let text): out += text
        case .value(.null): out += "null"
        case .value(.bool(let flag)): out += flag ? "true" : "false"
        case .value(.number(let number)): out += WebJSON.number(number)
        case .value(.string(let text)): out += WebJSON.quoted(text)
        case .value(.array(let items)):
            out += "["
            tasks.append(.text("]"))
            for (at, item) in items.enumerated().reversed() {
                tasks.append(.value(item))
                if at > 0 { tasks.append(.text(",")) }
            }
        case .value(.object(let fields)):
            out += "{"
            tasks.append(.text("}"))
            let keys = fields.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            for (at, key) in keys.enumerated().reversed() {
                tasks.append(.value(fields[key]!))
                tasks.append(.text(WebJSON.quoted(key) + ":"))
                if at > 0 { tasks.append(.text(",")) }
            }
        }
    }
    return out
}

/// A resume fixture's songs: `"<level>:<id>"` (or `"...#n"`, a variant) to the song, its level with it.
struct ResumeSongs {
    let table: [String: QueueTrack]

    init(_ json: JSONValue?) throws {
        let fields = try #require(json?.object, "the fixture has no songs table")
        var table: [String: QueueTrack] = [:]
        for (key, song) in fields { table[key] = try #require(queueTrack(song), "song \(key) doesn't read") }
        self.table = table
    }

    func tracks(_ keys: JSONValue?) -> [QueueTrack]? {
        guard let keys = keys?.array else { return nil }
        let made = keys.compactMap { $0.string.flatMap { table[$0] } }
        return made.count == keys.count ? made : nil
    }

    /// A queue from export-traces.cjs's queueRecord: song keys, the index, Up Next's account when it has one.
    func queue(_ record: JSONValue?) -> UpNextQueue? {
        guard let record, let index = record["index"]?.int, let tracks = tracks(record["tracks"]) else { return nil }
        guard let state = record["upNext"] else { return UpNextQueue(tracks: tracks, index: index) }
        guard let marks = state["marks"]?.array else { return nil }
        let made = marks.compactMap { mark -> Mark? in
            guard let parts = mark.array, parts.count == 4, let key = parts[0].int, let from = parts[1].string,
                  let at = parts[2].int, let pass = parts[3].int else { return nil }
            let kind: MarkFrom? = from == "s" ? .source : from == "a" ? .added : from == "o" ? .one : nil
            return kind.map { Mark(key: key, from: $0, at: at, pass: pass) }
        }
        guard made.count == marks.count, let source = self.tracks(state["source"]), let shuffle = state["shuffle"]?.bool,
              let nextKey = state["nextKey"]?.int, let startedAt = state["startedAt"]?.int,
              let leftItems = state["left"]?.array else { return nil }
        let left = leftItems.compactMap { gone -> LeftOut? in
            guard let parts = gone.array, parts.count == 2, let pass = parts[0].int, let at = parts[1].int else { return nil }
            return LeftOut(pass: pass, at: at)
        }
        guard left.count == leftItems.count else { return nil }
        var rounds: [PagedRound]?
        if let held = state["pagedRounds"] {
            guard let items = held.array else { return nil }
            rounds = items.compactMap { item in
                guard let pass = item["pass"]?.int, let kept = item["paged"].flatMap(paged) else { return nil }
                return PagedRound(pass: pass, paged: kept)
            }
            guard rounds?.count == items.count else { return nil }
        }
        return UpNextQueue(tracks: tracks, index: index, upNext: UpNextState(
            marks: made, source: source, shuffle: shuffle, nextKey: nextKey, startedAt: startedAt, left: left,
            paged: state["paged"].flatMap(paged), pagedRounds: rounds))
    }
}

/// Where two queues first differ, in words - never two whole queues (Swift Testing's diff of a large one can take
/// the test process down: notes/ios.md).
func queueDifference(_ ours: UpNextQueue?, _ theirs: UpNextQueue?) -> String? {
    guard let ours, let theirs else { return ours == nil && theirs == nil ? nil : "one is nil: \(ours == nil), \(theirs == nil)" }
    if ours == theirs { return nil }
    if ours.index != theirs.index { return "index \(ours.index) vs \(theirs.index)" }
    if ours.tracks.count != theirs.tracks.count { return "\(ours.tracks.count) songs vs \(theirs.tracks.count)" }
    if let at = ours.tracks.indices.first(where: { ours.tracks[$0] != theirs.tracks[$0] }) {
        return "song \(at): \(ours.tracks[at].id) \(String(describing: ours.tracks[at].level)) vs \(theirs.tracks[at].id) \(String(describing: theirs.tracks[at].level))"
    }
    guard let a = ours.upNext, let b = theirs.upNext else { return "Up Next: \(ours.upNext == nil) vs \(theirs.upNext == nil)" }
    if a.marks != b.marks { return "marks differ" }
    if a.source != b.source { return "source differs" }
    if a.shuffle != b.shuffle || a.nextKey != b.nextKey || a.startedAt != b.startedAt { return "shuffle/nextKey/startedAt" }
    if a.left != b.left { return "left differs" }
    if a.paged != b.paged { return "paged differs" }
    if a.pagedRounds != b.pagedRounds { return "pagedRounds differ" }
    return "differs elsewhere"
}

/* ===== the controller's world, faked ===== */

/// Time that moves only when told: `soon` work runs before any wait comes due, waits in the order they come due.
final class VirtualClock: ResumeClock {
    final class Wait: ResumeWait {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    private(set) var now: Int64 = 1_000_000
    private var waits: [(due: Int64, order: Int, wait: Wait, work: () -> Void)] = []
    private var made = 0
    private var soonWork: [() -> Void] = []

    func after(_ ms: Int64, _ work: @escaping () -> Void) -> ResumeWait {
        let wait = Wait()
        made += 1
        waits.append((now + ms, made, wait, work))
        return wait
    }

    func soon(_ work: @escaping () -> Void) {
        soonWork.append(work)
    }

    func drain() {
        while !soonWork.isEmpty { soonWork.removeFirst()() }
    }

    /// `ms` on: everything soon, then each wait as it comes due.
    func run(_ ms: Int64) {
        let end = now + ms
        drain()
        while true {
            waits.removeAll { $0.wait.cancelled }
            guard let next = waits.min(by: { ($0.due, $0.order) < ($1.due, $1.order) }), next.due <= end else { break }
            waits.removeAll { $0.order == next.order }
            now = next.due
            next.work()
            drain()
        }
        now = end
    }
}

/// deadwax, faked: every request kept, answered by the test.
final class FakeResumeServer: ResumeServer {
    enum Kind { case get, full, at }
    final class Ask {
        let kind: Kind
        let full: QueueSaveBody?
        let at: QueueAtBody?
        var done = false
        private let answerQueue: ((Result<QueueAnswer, ResumeFailure>) -> Void)?
        private let answerSave: ((Result<SavedQueue, ResumeFailure>) -> Void)?

        init(get done: @escaping (Result<QueueAnswer, ResumeFailure>) -> Void) {
            kind = .get; full = nil; at = nil; answerQueue = done; answerSave = nil
        }
        init(full body: QueueSaveBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) {
            kind = .full; full = body; at = nil; answerQueue = nil; answerSave = done
        }
        init(at body: QueueAtBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) {
            kind = .at; full = nil; at = body; answerQueue = nil; answerSave = done
        }

        func answer(_ queue: QueueAnswer) {
            guard !done else { return }
            done = true
            answerQueue?(.success(queue))
        }
        /// sim's ok(entry, rev, idsRev)
        func ok(_ rev: Int? = 6, _ idsRev: Int? = 6) {
            guard !done else { return }
            done = true
            answerSave?(.success(SavedQueue(rev: rev, ids_rev: idsRev)))
        }
        func refuse(_ failure: ResumeFailure) {
            guard !done else { return }
            done = true
            answerQueue?(.failure(failure))
            answerSave?(.failure(failure))
        }
    }

    var asks: [Ask] = []
    func asked(_ kind: Kind) -> [Ask] { asks.filter { $0.kind == kind } }

    func queue(_ done: @escaping (Result<QueueAnswer, ResumeFailure>) -> Void) { asks.append(Ask(get: done)) }
    func save(_ body: QueueSaveBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) { asks.append(Ask(full: body, done)) }
    func saveAt(_ body: QueueAtBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void) { asks.append(Ask(at: body, done)) }
}

/// The player as resume sees it - resume.sim.cjs's fakePlayer: restoreQueue fitted to Repeat off and refused while
/// playing; what it puts back reported to the controller as the app's player reports it.
final class FakeResumePlayer: ResumePlayer {
    var queue = UpNextQueue.empty
    var playing = false
    var at = 0.0
    var restored: [(ids: [String], index: Int, position: Double)] = []
    weak var controller: ResumeController?

    func position() -> Double { at }

    func restoreQueue(_ queue: UpNextQueue, position: Double) -> UpNextQueue? {
        if playing { return nil }
        let next = toppedUp(withRepeat(queue, .off), .off)
        guard next.current != nil else { return nil }
        restored.append((next.ids, next.index, position))
        self.queue = next
        at = position
        controller?.observe(queue: next, playing: playing)
        return next
    }
}

/// resume.sim.cjs's page(): a controller over the fakes, its queue observed and started - deadwax answering the
/// open's ask with `answer`, if any, 20 ms on.
final class ResumePage {
    let clock = VirtualClock()
    let server = FakeResumeServer()
    let player = FakeResumePlayer()
    var said: [String] = []
    var session = 1
    var setting = Normalization.auto
    var controller: ResumeController!

    init(device: String = "phone-device-1", answer: QueueAnswer? = nil, playing: Bool = false) {
        player.playing = playing
        controller = ResumeController(device: device, player: player, server: server, clock: clock,
                                      session: { [unowned self] in self.session },
                                      normalization: { [unowned self] in self.setting },
                                      say: { [unowned self] in self.said.append($0) })
        player.controller = controller
        draw()
        controller.start()
        clock.run(20)
        if let answer, let get = server.asked(.get).last { get.answer(answer) }
        clock.run(80)
    }

    /// The app re-drawn: the player's queue and play state observed.
    func draw() {
        controller.observe(queue: player.queue, playing: player.playing)
    }

    func set(_ queue: UpNextQueue, playing: Bool? = nil) {
        player.queue = queue
        if let playing { player.playing = playing }
        draw()
    }

    func run(_ ms: Int64) { clock.run(ms) }

    /// sim's play(p, ms, from): the position reported every 250 ms, as the app's ticker does, for `ms`.
    func play(_ ms: Int64, from: Double? = nil) {
        let start = from ?? player.at
        var t: Int64 = 0
        while t < ms {
            clock.run(250)
            t += 250
            report(start + Double(t) / 1000)
        }
    }

    /// A position report (and a seek): the player's second, told.
    func report(_ seconds: Double) {
        player.at = seconds
        controller.position(seconds)
    }

    /// Back to the front, settled.
    func focus() {
        controller.foreground()
        clock.run(0)
    }

    func asked(_ kind: FakeResumeServer.Kind) -> [FakeResumeServer.Ask] { server.asked(kind) }
}

/// resume.sim.cjs's songOf: Portishead's, as GET /queue sends them.
func navidromeSong(_ id: String) -> Song {
    Song(id: id, title: "song \(id)", album: "Dummy", albumId: "nd-dummy", artist: "Portishead", duration: 200,
         suffix: "flac", contentType: "audio/flac", coverArt: "al-1")
}

/// queueOf: those songs as queue entries.
func queueOf(_ ids: [String], level: Level? = nil) -> [QueueTrack] {
    ids.map { id in
        var track = shuffledTrack(navidromeSong(id))
        track.album = "Dummy"
        track.level = level
        return track
    }
}

/// answerOf(ids, index, position, more)
func answerOf(_ ids: [String], _ index: Int?, _ position: Double, changedBy: String = "deadwax", shared: Bool = false,
              kept: KeptQueue? = nil) -> QueueAnswer {
    QueueAnswer(tracks: ids.map(navidromeSong), index: index, position: position, changed_by: changedBy, shared: shared, kept: kept)
}

/// keptOf(ids, index, position, more): deadwax's record of a queue another device of the person's saved.
func keptOf(_ ids: [String], _ index: Int, _ position: Double, rev: Int = 5, idsRev: Int = 4, device: String = "desk-device-2",
            label: String = "Mac") -> KeptQueue {
    let saving = toSave(startUpNext(queueOf(ids, level: .album), start: index), position: position)
    return KeptQueue(rev: rev, ids_rev: idsRev, ids: saving.ids, index: saving.index, position: position,
                     snapshot: saving.snapshot, device: device, label: label)
}
