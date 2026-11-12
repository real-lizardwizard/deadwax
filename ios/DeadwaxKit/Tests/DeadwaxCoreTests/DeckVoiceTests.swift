import Foundation
import Testing
@testable import DeadwaxCore

/// The record's voice (DeckVoice.swift) against lib/deckVoice.ts's own output (Fixtures/deck/voice/, the spec's 7.0):
///
/// - **Test A, the port exactly**: every case's every run replayed with `RecordedMaths` - V8's own answers to every
///   Math call - and each block given the web's `now`; every 4,096 frames' hash of the output's Float32 bits, every
///   report, the Math calls' count and order, and three stretches' output whole must match bit for bit.
/// - **Test B, James's bar**: the same runs with `PlatformMaths` (this platform's libm) beside `RecordedMaths`, in
///   lockstep: no sample further apart than -100 dBFS, the reports' place and time within 1e-9.
@Suite(.serialized) struct DeckVoiceTests {
    // MARK: the windows, made from their recipes

    /// A window made from its recipe (export-deck-vectors.cjs recipeChannel), its channels kept for the run.
    final class MadeWindow {
        let channels: [UnsafeMutableBufferPointer<Float>]
        let rate: Double
        init(channels: [UnsafeMutableBufferPointer<Float>], rate: Double) {
            self.channels = channels
            self.rate = rate
        }
        deinit { channels.forEach { $0.deallocate() } }

        func window(start: Double) -> VoiceWindow {
            VoiceWindow(first: UnsafePointer(channels[0].baseAddress!), second: channels.count > 1 ? UnsafePointer(channels[1].baseAddress!) : nil,
                        length: channels[0].count, start: start, rate: rate)
        }

        var hash: String {
            var fnv = FNV()
            for channel in channels { for sample in channel { fnv.add32(sample.bitPattern) } }
            return fnv.hex
        }
    }

    static let windowSeconds = 8

    static func recipeChannel(_ kind: String, _ seed: Int, _ ch: Int, _ length: Int) -> UnsafeMutableBufferPointer<Float> {
        let out = UnsafeMutableBufferPointer<Float>.allocate(capacity: length)
        var x = UInt32(truncatingIfNeeded: seed * 2 + ch + 1)
        var phase = 0
        let period = 2400 + seed * 7 + ch * 331
        let stepAt = length / 2 + ch * 9601
        for i in 0..<length {
            var v: Int32 = 0
            switch kind {
            case "noise", "soft":
                x ^= x << 13
                x ^= x >> 17
                x ^= x << 5
                v = Int32(x >> 16) - 32768
                if kind == "soft" { v >>= 3 }
            case "sweep":
                phase = (phase + 1 + ((i >> 7) % 600) * (ch + 1)) & 0xffff
                v = Int32(phase < 32768 ? phase * 2 - 32768 : (65535 - phase) * 2 - 32767)
            case "clicks":
                let at = i % period
                v = at == 0 ? 32767 : at == 1 ? -32768 : 0
            case "step":
                v = i >= stepAt ? (ch == 0 ? 32767 : -32768) : 0
            default:
                break
            }
            out[i] = Float(v) / 32768
        }
        return out
    }

    /// Every window the cases read, made once.
    final class Windows: @unchecked Sendable {
        private var made: [String: MadeWindow] = [:]
        private let lock = NSLock()
        func get(_ kind: String, _ seed: Int, _ rate: Double, _ channels: Int) -> MadeWindow {
            lock.lock()
            defer { lock.unlock() }
            let key = "\(kind) \(seed) \(rate) \(channels)"
            if let window = made[key] { return window }
            let length = DeckVoiceTests.windowSeconds * Int(rate)
            let window = MadeWindow(channels: (0..<channels).map { DeckVoiceTests.recipeChannel(kind, seed, $0, length) }, rate: rate)
            made[key] = window
            return window
        }
    }
    static let windows = Windows()

    // MARK: the cases

    struct Message {
        let post: Double
        let message: VoiceMessage
    }

    struct Run {
        let rate: Double
        let block: Int
        let from: Int
        let frames: Int
        let spans: [String]
        let reportCount: Int
        let reportHash: String
        let reportsWhole: [Double]?
        let mathsCalls: Int
        let mathsHash: String
        let whole: (file: String, from: Int, frames: Int)?
    }

    struct Case {
        let name: String
        let messages: [Message]
        let runs: [Run]
    }

    static func message(_ json: JSONValue) -> Message? {
        let n = { (key: String) in DeckFixtures.number(json[key]) }
        let post = n("post")
        switch json["type"]?.string {
        case "window":
            guard let window = json["window"], !window.isNull else { return Message(post: post, message: .window(nil)) }
            let made = windows.get(window["kind"]?.string ?? "", window["seed"]?.int ?? 0, DeckFixtures.number(window["rate"]), window["channels"]?.int ?? 2)
            return Message(post: post, message: .window(made.window(start: DeckFixtures.number(window["start"]))))
        case "take": return Message(post: post, message: .take(at: n("at"), rate: n("rate"), time: n("time"), until: n("until")))
        case "drive": return Message(post: post, message: .drive(at: n("at"), rate: n("rate"), accel: DeckFixtures.double(json["accel"]), time: n("time"), until: n("until")))
        case "hand": return Message(post: post, message: .hand(at: n("at"), time: n("time")))
        case "fade": return Message(post: post, message: .fade(seconds: n("seconds")))
        case "stop": return Message(post: post, message: .stop)
        default: return nil
        }
    }

    static func cases() throws -> [Case] {
        let folder = try Fixtures.url("deck/voice")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") && $0 != "windows.json" }.sorted()
        return try names.map { name in
            let json = try DeckFixtures.json("voice/\(name)")
            let messages = (json["messages"]?.array ?? []).compactMap(message)
            let runs: [Run] = (json["runs"]?.array ?? []).map { run in
                let whole = run["whole"].flatMap { $0.isNull ? nil : $0 }.map { (file: $0["file"]?.string ?? "", from: $0["from"]?.int ?? 0, frames: $0["frames"]?.int ?? 0) }
                return Run(rate: run["rate"]?.double ?? 0, block: run["block"]?.int ?? 0, from: run["from"]?.int ?? 0, frames: run["frames"]?.int ?? 0,
                           spans: (run["spans"]?.array ?? []).compactMap(\.string), reportCount: run["reports"]?["count"]?.int ?? -1,
                           reportHash: run["reports"]?["hash"]?.string ?? "", reportsWhole: run["reports"]?["whole"]?.string.map(DeckFixtures.doubles),
                           mathsCalls: run["maths"]?["calls"]?.int ?? -1, mathsHash: run["maths"]?["hash"]?.string ?? "", whole: whole)
            }
            return Case(name: json["name"]?.string ?? name, messages: messages, runs: runs)
        }
    }

    // MARK: a run, as the exporter's runVoice

    struct Output {
        var spans: [String] = []
        var reports: [Double] = []
        var reportCount = 0
        var reportHash = FNV()
        var whole: [Float] = []
        /// Every sample, both channels interleaved, when asked for.
        var samples: [Float] = []
    }

    /// The voice over a case's messages, as runVoice drives it - each block's output and report handed to `block`.
    static func render<M: DeckMaths>(_ c: Case, _ run: Run, _ maths: M, block: (UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>, Int, Int, VoiceHeard?) -> Void) {
        var state = DeckVoice.newVoiceState(maths)
        defer { state.deallocate() }
        let left = UnsafeMutablePointer<Float>.allocate(capacity: run.block), right = UnsafeMutablePointer<Float>.allocate(capacity: run.block)
        let outputs = UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        outputs[0] = left
        outputs[1] = right
        defer {
            left.deallocate()
            right.deallocate()
            outputs.deallocate()
        }
        var next = 0, done = 0
        while done < run.frames {
            let n = Swift.min(run.block, run.frames - done)
            let now = Double(run.from + done) / run.rate
            while next < c.messages.count && c.messages[next].post <= now {
                DeckVoice.voiceCommand(&state, c.messages[next].message, now, run.rate, maths)
                next += 1
            }
            DeckVoice.renderVoice(&state, outputs, n, run.rate, now, maths)
            let heard = DeckVoice.voiceReport(&state, n, run.rate, now, DeckVoice.reportsPerSecond)
            block(outputs, n, done, heard)
            done += n
        }
    }

    static func output<M: DeckMaths>(_ c: Case, _ run: Run, _ maths: M, all: Bool = false) -> Output {
        var out = Output()
        var span = FNV(), inSpan = 0
        if all { out.samples.reserveCapacity(run.frames * 2) }
        render(c, run, maths) { outputs, n, done, heard in
            for i in 0..<n {
                if all { out.samples.append(outputs[0][i]); out.samples.append(outputs[1][i]) }
                span.add32(DeckFixtures.bits(outputs[0][i]))
                span.add32(DeckFixtures.bits(outputs[1][i]))
                if let whole = run.whole {
                    let k = done + i - whole.from
                    if k >= 0 && k < whole.frames { out.whole.append(outputs[0][i]); out.whole.append(outputs[1][i]) }
                }
                inSpan += 1
                if inSpan == 4096 {
                    out.spans.append(span.hex)
                    span = FNV()
                    inSpan = 0
                }
            }
            if let heard {
                let values = [heard.time, heard.pos, heard.rate, heard.gain, heard.held, heard.peaks, heard.lowest]
                out.reportCount += 1
                out.reports.append(contentsOf: values)
                for value in values { out.reportHash.add64(RecordedMaths.bits(value)) }
            }
        }
        if inSpan > 0 { out.spans.append(span.hex) }
        return out
    }

    // MARK: test A

    @Test func theWindowsAreTheWebs() throws {
        let fixture = try DeckFixtures.json("voice/windows.json")
        let listed = fixture["windows"]?.array ?? []
        #expect(listed.count >= 8)
        for entry in listed {
            let made = Self.windows.get(entry["kind"]?.string ?? "", entry["seed"]?.int ?? 0, entry["rate"]?.double ?? 0, entry["channels"]?.int ?? 0)
            #expect(made.hash == entry["hash"]?.string, "the \(entry["kind"]?.string ?? "?") window, seed \(entry["seed"]?.int ?? 0)")
        }
    }

    @Test func testA_everyRunIsTheWebsBitForBit() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 8)
        var runs = 0, wholes = 0
        for c in cases {
            for run in c.runs {
                let what = "\(c.name) at \(Int(run.rate)) Hz in blocks of \(run.block)"
                let maths = DeckFixtures.maths()
                maths.restart()
                let out = Self.output(c, run, maths)
                runs += 1
                #expect(maths.missed.isEmpty, "\(what): asked Math what the web never did, first \(maths.missed.prefix(3))")
                #expect(maths.calls == run.mathsCalls, "\(what): \(maths.calls) Math calls, the web's \(run.mathsCalls)")
                #expect(String(maths.hash, radix: 16).leftPadded(16) == run.mathsHash, "\(what): the Math calls in another order")
                #expect(out.spans.count == run.spans.count, "\(what): spans")
                if let first = zip(out.spans, run.spans).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                    Issue.record("\(what): the output first differs in frames \(first.offset * 4096)..<\((first.offset + 1) * 4096)")
                }
                #expect(out.reportCount == run.reportCount, "\(what): \(out.reportCount) reports, the web's \(run.reportCount)")
                #expect(out.reportHash.hex == run.reportHash, "\(what): the reports")
                if let whole = run.reportsWhole {
                    #expect(out.reports.count == whole.count)
                    if let i = zip(out.reports, whole).enumerated().first(where: { !DeckFixtures.same($0.element.0, $0.element.1) })?.offset {
                        Issue.record("\(what): report \(i / 7) field \(i % 7) is \(out.reports[i]), the web's \(whole[i])")
                    }
                }
                if let whole = run.whole {
                    wholes += 1
                    let data = try Fixtures.data("deck/\(whole.file)")
                    #expect(data.count == whole.frames * 8)
                    var differ = 0
                    data.withUnsafeBytes { raw in
                        for k in 0..<whole.frames {
                            let l = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4 * k, as: UInt32.self))
                            let r = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4 * (whole.frames + k), as: UInt32.self))
                            if DeckFixtures.bits(out.whole[2 * k]) != l || DeckFixtures.bits(out.whole[2 * k + 1]) != r { differ += 1 }
                        }
                    }
                    #expect(differ == 0, "\(what): \(differ) of \(whole.frames) frames differ from \(whole.file)")
                }
            }
        }
        #expect(runs >= 72 && wholes == 3, "\(runs) runs, \(wholes) whole")
    }

    // MARK: test B

    @Test func testB_thePlatformsVoiceIsWithinAHundredDecibels() throws {
        let cases = try Self.cases()
        var worst = 0.0, worstWhere = ""
        for c in cases {
            //? the runs at 48 and 44.1 kHz in blocks of 128 and 1024, and in blocks of 1: the arithmetic is the same at
            //? every block size (test A holds each to the web), the libm's answers are what differ
            for run in c.runs where run.block == 1 || run.block == 128 || run.block == 1024 {
                let recorded = Self.output(c, run, DeckFixtures.maths(), all: true)
                let platform = Self.output(c, run, PlatformMaths(), all: true)
                #expect(recorded.samples.count == platform.samples.count)
                for (a, b) in zip(recorded.samples, platform.samples) {
                    let gap = Swift.abs(Double(a) - Double(b))
                    if gap > worst { worst = gap; worstWhere = "\(c.name) at \(Int(run.rate)) Hz in blocks of \(run.block)" }
                }
                let platformReports = platform.reports
                #expect(platformReports.count == recorded.reports.count)
                for i in stride(from: 0, to: Swift.min(platformReports.count, recorded.reports.count), by: 7) {
                    #expect(Swift.abs(platformReports[i] - recorded.reports[i]) <= 1e-9 && Swift.abs(platformReports[i + 1] - recorded.reports[i + 1]) <= 1e-9,
                            "\(c.name): report \(i / 7)'s time and place")
                }
            }
        }
        let db = worst == 0 ? -Double.infinity : 20 * Foundation.log10(worst)
        print("DeckVoiceTests B: the platform's voice at worst \(db) dBFS from the web's (\(worstWhere))")
        #expect(db <= -100, "the platform's voice is \(db) dBFS from the web's at worst (\(worstWhere))")
    }
}

/// FNV-1a 64, as the exporter hashes.
struct FNV {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    mutating func add(_ byte: UInt8) {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    mutating func add32(_ value: UInt32) {
        add(UInt8(truncatingIfNeeded: value))
        add(UInt8(truncatingIfNeeded: value >> 8))
        add(UInt8(truncatingIfNeeded: value >> 16))
        add(UInt8(truncatingIfNeeded: value >> 24))
    }
    mutating func add64(_ value: UInt64) {
        add32(UInt32(truncatingIfNeeded: value))
        add32(UInt32(truncatingIfNeeded: value >> 32))
    }
    var hex: String { String(hash, radix: 16).leftPadded(16) }
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
