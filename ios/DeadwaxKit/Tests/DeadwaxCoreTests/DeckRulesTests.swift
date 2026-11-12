import Foundation
import Testing
@testable import DeadwaxCore

/// The deck's rules held to the web's (notes/ios-specs/turntable.md 7.0): each rules/*.json - the real Deck driven
/// through deck.sim's harness, every input with its time and every effect - replayed into DeckRules over a world that
/// records the same effects in the same words, with RecordedMaths answering every Math call as V8 did. Every effect
/// must be the web's, in the web's order, bit for bit; then again with the platform's maths, doubles within 1e-9.
@Suite(.serialized)
struct DeckRulesTests {
    /// The arguments each input carries after its time (export-deck-vectors.cjs RULE_OPS).
    static let arity: [UInt8: Int] = [
        0: 6, 1: 5, 2: 1, 3: 1, 4: 0, 5: 2, 6: 3, 7: 8, 8: 3,
        10: 0, 11: 0, 12: 0, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 3, 21: 2, 22: 3, 23: 2,
        24: 0, 25: 0, 26: 0, 27: 0, 28: 1,
    ]

    struct Input {
        let op: UInt8
        let t: Double
        let args: [Double]
    }

    struct Case {
        let name: String
        let songs: [DeckSong]
        let words: [String]
        let inputs: [Input]
        let stamps: [UInt64: Double]
        let count: Int
        let spans: [String]
        let whole: [String]?
    }

    static func cases() throws -> [Case] {
        let folder = try Fixtures.url("deck/rules")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.sorted()
        return try names.map { name in
            let json = try DeckFixtures.json("rules/\(name)")
            let songs = (json["songs"]?.array ?? []).map { song -> DeckSong in
                let fields = song.array ?? []
                return DeckSong(id: fields[0].string ?? "", length: DeckFixtures.number(fields[1]), flac: fields[2].bool ?? false, kind: fields[3].string ?? "")
            }
            let words = (json["words"]?.array ?? []).map { $0.string ?? "" }
            let data = Data(base64Encoded: json["inputs"]?["bytes"]?.string ?? "") ?? Data()
            var inputs: [Input] = []
            data.withUnsafeBytes { raw in
                var at = 0
                func next() -> Double {
                    defer { at += 8 }
                    return Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt64.self)))
                }
                while at < raw.count {
                    let op = raw[at]
                    at += 1
                    let t = next()
                    let args = (0..<(arity[op] ?? 0)).map { _ in next() }
                    inputs.append(Input(op: op, t: t, args: args))
                }
            }
            let pairs = DeckFixtures.doubles(json["stamps"]?.string)
            var stamps: [UInt64: Double] = [:]
            for i in stride(from: 0, to: pairs.count - 1, by: 2) { stamps[pairs[i].bitPattern] = pairs[i + 1] }
            let effects = json["effects"]
            return Case(name: json["name"]?.string ?? name, songs: songs, words: words, inputs: inputs, stamps: stamps,
                        count: effects?["count"]?.int ?? -1, spans: (effects?["spans"]?.array ?? []).map { $0.string ?? "" },
                        whole: effects?["whole"]?.array.map { $0.map { $0.string ?? "" } })
        }
    }

    /// Replays a case, returning its effects as the web words them.
    static func replay<M: DeckMaths>(_ c: Case, _ maths: M) -> [String] {
        let world = TraceWorld(c)
        world.numbered = true
        var rules: DeckRules<M>?
        for (index, input) in c.inputs.enumerated() {
            world.input = index
            world.time = input.t
            let a = input.args
            func on(_ i: Int) -> Bool { a[i] != 0 }
            if input.op == 0 {
                world.set(song: a[0], playing: a[1], at: a[2], ready: a[4], made: a[5])
                rules = DeckRules(host: world, clock: world, maths: maths, reduced: on(3))
                continue
            }
            guard let deck = rules else {
                world.record("(no deck for input \(input.op))")
                continue
            }
            switch input.op {
            case 1: world.set(song: a[0], playing: a[1], at: a[2], ready: a[3], made: a[4])
            case 2:
                world.at = a[0]
                for listener in world.listeners { listener.run(a[0]) }
            case 3:
                let n = Int(a[0])
                if let run = world.timers.removeValue(forKey: n) { run() } else { world.record("(timer \(n) isn't pending)") }
            case 4:
                let frames = world.frames
                world.frames = []
                if frames.isEmpty { world.record("(no frame asked)") }
                for frame in frames { frame.run(input.t) }
            case 5:
                world.ready = on(0)
                world.made = on(1)
                deck.audioChanged()
            case 6: deck.heard(VoiceHeard(pos: a[0], rate: a[1], gain: a[2], time: 0, held: 0, peaks: 0, lowest: 0))
            case 7:
                let n = Int(a[0])
                let first = a[1], samples = a[2], rate = a[3]
                let zeros = world.zeros(Int(a[4]))
                let got = DeckWindow(channels: Array(repeating: zeros, count: Int(a[7])), start: first / rate, end: (first + samples) / rate,
                                     rate: a[5], source: .server, bytes: Int(a[6]), madeIn: 0)
                world.asks[n](.success(got))
            case 8:
                let n = Int(a[0]), word = Int(a[2]) >= 0 ? c.words[Int(a[2])] : nil
                let error: DeckWindowError = a[1] == 415 ? .notFlac(word) : a[1] == 416 ? .pastTheEnd : .failed(word ?? "")
                world.asks[n](.failure(error))
            case 10: world.record("return \(deck.live())")
            case 11: world.record("return \(deck.taken())")
            case 12: world.record("return \(hex(deck.anchor()))")
            case 13: deck.setShowing(on(0))
            case 14: deck.setWindDown(on(0))
            case 15: deck.speedChanged(a[0])
            case 16: deck.playingChanged(on(0))
            case 17: deck.songChanged(Int(a[0]) >= 0 ? c.songs[Int(a[0])].id : "")
            case 18: deck.pressed(a[0])
            case 19: deck.holdStill(on(0))
            case 20: deck.touched(a[0], turned: a[1], offset: a[2])
            case 21: world.record("return \(hex(deck.takeOver(a[0], quick: on(1))))")
            case 22: deck.hand(a[0], turned: a[1], at: a[2])
            case 23:
                let out = deck.release(a[0], cancel: on(1))
                world.record("return \(out.seek.map(hex) ?? "null") \(out.play)")
            case 24: world.record("return \(deck.pausing().map(hex) ?? "null")")
            case 25: world.record("return \(deck.resuming().map(hex) ?? "null")")
            case 26: deck.armTaken()
            case 27: deck.destroy()
            case 28: deck.reducedChanged(on(0))
            default: world.record("(an input the replay doesn't know: \(input.op))")
            }
        }
        return world.effects
    }

    static func spans(_ effects: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < effects.count {
            var fnv = FNV()
            for words in effects[i..<Swift.min(i + 512, effects.count)] {
                for byte in words.utf8 { fnv.add(byte) }
                fnv.add(10)
            }
            out.append(fnv.hex)
            i += 512
        }
        return out
    }

    @Test func everyCaseIsTheWebsEffectForEffect() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 35, "the rules cases: \(cases.count)")
        var effects = 0
        for c in cases {
            let maths = DeckFixtures.maths()
            maths.restart()
            let got = Self.replay(c, maths)
            effects += got.count
            #expect(maths.missed.isEmpty, "\(c.name): asked Math what the web never did, first \(maths.missed.prefix(3))")
            if let whole = c.whole {
                let first = (0..<Swift.min(got.count, whole.count)).first { got[$0] != whole[$0] }
                if let first {
                    Issue.record("\(c.name): effect \(first) is \(got[first]), the web's \(whole[first]) - before it: \(whole[Swift.max(0, first - 4)..<first].joined(separator: " | "))")
                }
                #expect(got.count == whole.count, "\(c.name): \(got.count) effects, the web's \(whole.count)")
            } else {
                #expect(got.count == c.count, "\(c.name): \(got.count) effects, the web's \(c.count)")
                let mine = Self.spans(got)
                if let first = (0..<Swift.min(mine.count, c.spans.count)).first(where: { mine[$0] != c.spans[$0] }) {
                    Issue.record("\(c.name): effects \(first * 512)-\(first * 512 + 511) differ from the web's (its first there: \(got.count > first * 512 ? got[first * 512] : "-"))")
                }
            }
        }
        print("DeckRulesTests: \(cases.count) cases, \(effects) effects replayed")
    }

    /// The platform's maths: the same effects, their doubles within 1e-9 (relative) of the web's - for the cases kept
    /// whole; the hashed ones in number.
    @Test func thePlatformsMathsGiveTheSameEffects() throws {
        var worst = 0.0
        for c in try Self.cases() {
            let got = Self.replay(c, PlatformMaths())
            guard let whole = c.whole else {
                #expect(got.count == c.count, "\(c.name): \(got.count) effects with the platform's maths, the web's \(c.count)")
                continue
            }
            #expect(got.count == whole.count, "\(c.name): \(got.count) effects with the platform's maths, the web's \(whole.count)")
            for (mine, theirs) in zip(got, whole) where mine != theirs {
                let a = mine.split(separator: " "), b = theirs.split(separator: " ")
                guard a.count == b.count else {
                    Issue.record("\(c.name): \(mine), the web's \(theirs)")
                    break
                }
                for (x, y) in zip(a, b) where x != y {
                    guard x.count == 16, y.count == 16, let bx = UInt64(x, radix: 16), let by = UInt64(y, radix: 16) else {
                        Issue.record("\(c.name): \(mine), the web's \(theirs)")
                        continue
                    }
                    let dx = Double(bitPattern: bx), dy = Double(bitPattern: by)
                    let gap = Swift.abs(dx - dy) / Swift.max(1, Swift.abs(dy))
                    worst = Swift.max(worst, gap)
                    #expect(gap <= 1e-9, "\(c.name): \(mine), the web's \(theirs)")
                }
            }
        }
        print("DeckRulesTests: the platform's maths at worst \(worst) (relative) from the web's")
    }
}

func hex(_ x: Double) -> String {
    String(x.bitPattern, radix: 16).leftPadded(16)
}

/// The world a trace was made in: the host, the clock, the player's position and the deck engine's state, recording
/// every effect in the exporter's words.
final class TraceWorld: DeckHost, DeckClock {
    struct Listener {
        let id: Int
        let run: (Double) -> Void
    }

    struct Frame {
        let id: Int
        let run: (Double) -> Void
    }

    let songs: [DeckSong]
    let stamps: [UInt64: Double]
    var songNow: DeckSong?
    var isPlaying = false
    var at = 0.0
    var ready = false
    var made = false
    var time = 0.0
    var effects: [String] = []
    /// each effect after the number of the input it came in (the replay's), as the exporter writes them
    var numbered = false
    var input = 0
    var listeners: [Listener] = []
    var nextListener = 1
    var timers: [Int: () -> Void] = [:]
    var timerCount = 0
    var frames: [Frame] = []
    var nextFrame = 1
    var asks: [(Result<DeckWindow, DeckWindowError>) -> Void] = []
    var zeroChannels: [Int: [Float]] = [:]

    init(_ c: DeckRulesTests.Case) {
        songs = c.songs
        stamps = c.stamps
    }

    func record(_ words: String) {
        effects.append(numbered ? "\(input) \(words)" : words)
    }

    func set(song: Double, playing: Double, at: Double, ready: Double, made: Double) {
        songNow = Int(song) >= 0 ? songs[Int(song)] : nil
        isPlaying = playing != 0
        self.at = at
        self.ready = ready != 0
        self.made = made != 0
    }

    func zeros(_ count: Int) -> [Float] {
        if let had = zeroChannels[count] { return had }
        let made = [Float](repeating: 0, count: count)
        zeroChannels[count] = made
        return made
    }

    // DeckHost
    func song() -> DeckSong? { songNow }
    func playing() -> Bool { isPlaying }
    func position() -> Double { at }
    func onPosition(_ listener: @escaping (Double) -> Void) -> () -> Void {
        record("listen")
        let id = nextListener
        nextListener += 1
        listeners.append(Listener(id: id, run: listener))
        return { [weak self] in
            guard let self else { return }
            self.record("unlisten")
            self.listeners.removeAll { $0.id == id }
        }
    }
    func hold() {
        record("hold")
        isPlaying = false
    }
    func resume() {
        record("resume")
        isPlaying = true
    }
    func turnFace(_ degrees: Double) { record("face \(hex(degrees))") }
    func show(_ at: Double?, scrubbing: Bool) { record(at.map { "show \(hex($0)) \(scrubbing)" } ?? "show null") }
    func grabbed() { record("grabbed") }
    func soundReady() -> Bool { ready }
    func voiceMade() -> Bool { made }
    func window(_ song: DeckSong, from: Double, seconds: Double, answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void) {
        record("ask \(asks.count) \(songs.firstIndex(of: song) ?? -1) \(hex(from)) \(hex(seconds))")
        asks.append(answer)
    }
    func post(_ message: DeckPost) {
        switch message {
        case .window(let w): record("post window \(hex(w.start)) \(hex(w.rate)) \(w.channels.count) \(w.channels.first?.count ?? 0)")
        case let .take(at, rate, time, until): record("post take \(hex(at)) \(hex(rate)) \(hex(time)) \(hex(until))")
        case let .drive(at, rate, accel, time, until): record("post drive \(hex(at)) \(hex(rate)) \(accel.map(hex) ?? "-") \(hex(time)) \(hex(until))")
        case let .hand(at, time): record("post hand \(hex(at)) \(hex(time))")
        case let .fade(seconds): record("post fade \(hex(seconds))")
        case .stop: record("post stop")
        }
    }
    func sleepAudio() { record("sleep") }
    func closeAudio() { record("close") }

    // DeckClock
    func now() -> Double { time }
    func stamp(_ ms: Double) -> Double { stamps[ms.bitPattern] ?? ms / 1000 }
    func after(_ ms: Double, _ run: @escaping () -> Void) -> Int {
        let n = timerCount
        timerCount += 1
        timers[n] = run
        record("timer \(n) \(hex(ms))")
        return n + 1
    }
    func cancel(_ id: Int) {
        if timers.removeValue(forKey: id - 1) != nil { record("clear \(id - 1)") }
    }
    func frame(_ run: @escaping (Double) -> Void) -> Int {
        record("raf")
        let id = nextFrame
        nextFrame += 1
        frames.append(Frame(id: id, run: run))
        return id
    }
    func cancelFrame(_ id: Int) {
        if frames.contains(where: { $0.id == id }) {
            record("unraf")
            frames.removeAll { $0.id == id }
        }
    }
}
