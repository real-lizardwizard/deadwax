import Foundation

// A recording of the record's sound played again through the Swift voice (notes/ios-specs/turntable.md 6.3, 7.0's
// test B): the web's file from Safari or Chrome, or the phone's. The same messages at the same voice times, block by
// block, and what came out held against what the recording heard.
//
//  - The phone's file says exactly which messages the voice was told before which block, at what now, and gives the
//    window's samples: the replay is the render's own arithmetic again, compared as floats.
//  - The web's says when each message was POSTED and what the voice said of itself 30 times a second, not when the
//    voice was told: the lab's way (ui/src/lab/analysis.ts planTiming, fitOf, replay - ported here line for line) works
//    out the lead that fits the voice's own reports best, and the window's samples come from whoever replays it (the
//    song decoded on the Mac, or a test's recipe). Its audio is 16 bits, so it is compared as deck.ts wrote it - the
//    replay rounded the same way, every sample - and its blocks' loudest samples, which it keeps as floats.

/// A recording read back.
public struct DeckRecordingFile {
    public var voice: String
    public var sampleRate: Double
    public var block: Double?
    public var scriptLagSeconds: Double
    /// context seconds less page seconds, as the recording ended
    public var offset: Double
    public var tapBlock: Int
    public var blockTimes: [Double]
    public var blockPeaks: [Double]
    public var channels: Int
    /// the 16-bit audio, interleaved
    public var int16: [Int16]
    public var messages: [WebJSON.Value]
    public var heard: [VoiceHeard]
    public var phone: Phone?

    public struct Phone {
        public var blocks: [DeckTapBlock]
        public var applied: [WebJSON.Value]
        /// the voice's output as floats, per channel
        public var audio: [[Float]]
        public var windows: [Window]
        public var lostBlocks: Int
        public var lostMessages: Int
    }

    public struct Window {
        public var id: UInt32
        public var start: Double
        public var rate: Double
        public var length: Int
        public var channels: Int
        public var from: Int
        /// the kept frames, per channel
        public var samples: [[Float]]
    }

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notJSON, notARecording, missing(String)
        public var description: String {
            switch self {
            case .notJSON: return "it isn't JSON"
            case .notARecording: return "it isn't a recording of the record's sound"
            case .missing(let key): return "it has no \(key)"
            }
        }
    }

    public static func read(_ data: Data) throws -> DeckRecordingFile {
        guard let text = String(data: data, encoding: .utf8), let json = WebJSON.parse(text) else { throw Refusal.notJSON }
        guard json["recording"] == .string("deadwax turntable sound") else { throw Refusal.notARecording }
        func number(_ value: WebJSON.Value?) -> Double? { if case .number(let n)? = value { return n }; return nil }
        func numbers(_ value: WebJSON.Value?) -> [Double] {
            guard case .array(let items)? = value else { return [] }
            return items.map { number($0) ?? .nan }
        }
        func array(_ value: WebJSON.Value?) -> [WebJSON.Value] { if case .array(let items)? = value { return items }; return [] }
        func string(_ value: WebJSON.Value?) -> String? { if case .string(let s)? = value { return s }; return nil }
        func bytes(_ value: WebJSON.Value?) -> Data? { string(value?["base64"]).flatMap { Data(base64Encoded: $0) } }
        guard let rate = number(json["sampleRate"]) else { throw Refusal.missing("sampleRate") }
        guard let audio = json["audio"], let pcm = bytes(audio) else { throw Refusal.missing("audio") }
        let channels = Int(number(audio["channels"]) ?? 2)
        let int16 = values(pcm, Int16.self).map { Int16(littleEndian: $0) }
        let heard = array(json["heard"]).map { h in
            VoiceHeard(pos: number(h["pos"]) ?? 0, rate: number(h["rate"]) ?? 0, gain: number(h["gain"]) ?? 0,
                       time: number(h["time"]) ?? 0, held: number(h["held"]) ?? 0, peaks: number(h["peaks"]) ?? 0,
                       lowest: number(h["lowest"]) ?? 1)
        }
        var file = DeckRecordingFile(
            voice: string(json["voice"]) ?? "worklet", sampleRate: rate, block: number(json["block"]),
            scriptLagSeconds: number(json["scriptLagSeconds"]) ?? 0, offset: number(json["clock"]?["offset"]) ?? 0,
            tapBlock: Int(number(json["tapBlock"]) ?? 4_096), blockTimes: numbers(json["blockTimes"]),
            blockPeaks: numbers(json["blockPeaks"]), channels: channels, int16: int16, messages: array(json["messages"]),
            heard: heard, phone: nil)
        if let phone = json["phone"] {
            let b = phone["blocks"]
            let columns = ["block", "starts", "frames", "rate", "now", "L", "hostTime", "sampleTime", "windowBefore",
                           "window", "messages", "pos", "peak"].map { numbers(b?[$0]) }
            var blocks: [DeckTapBlock] = []
            for i in 0..<(columns.map(\.count).min() ?? 0) {
                var block = DeckTapBlock()
                block.block = UInt64(columns[0][i])
                block.starts = UInt64(columns[1][i])
                block.frames = UInt32(columns[2][i])
                block.rate = columns[3][i]
                block.now = columns[4][i]
                block.lead = columns[5][i]
                block.hostTime = UInt64(columns[6][i])
                block.sampleTime = columns[7][i]
                block.windowBefore = UInt32(columns[8][i])
                block.window = UInt32(columns[9][i])
                block.messages = UInt32(columns[10][i])
                block.pos = columns[11][i]
                block.peak = Float(columns[12][i])
                blocks.append(block)
            }
            guard let floats = bytes(phone["audio"]) else { throw Refusal.missing("phone.audio") }
            let all = values(floats, Float.self)
            let frames = Int(number(phone["audio"]?["frames"]) ?? Double(all.count / 2))
            let audio = [Array(all[0..<frames]), Array(all[frames..<(2 * frames)])]
            let windows = array(phone["windows"]).compactMap { w -> Window? in
                guard let data = bytes(w), let count = number(w["frames"]), let channels = number(w["channels"]) else { return nil }
                let samples = values(data, Float.self)
                let n = Int(count)
                return Window(id: UInt32(number(w["id"]) ?? 0), start: number(w["start"]) ?? 0, rate: number(w["rate"]) ?? 0,
                              length: Int(number(w["length"]) ?? 0), channels: Int(channels), from: Int(number(w["from"]) ?? 0),
                              samples: (0..<Int(channels)).map { c in Array(samples[(c * n)..<((c + 1) * n)]) })
            }
            file.phone = Phone(blocks: blocks, applied: array(phone["applied"]), audio: audio, windows: windows,
                               lostBlocks: Int(number(phone["lost"]?["blocks"]) ?? 0),
                               lostMessages: Int(number(phone["lost"]?["messages"]) ?? 0))
        }
        return file
    }

    /// Little-endian values out of bytes, copied (a Data's bytes needn't be aligned for them).
    static func values<T>(_ data: Data, _: T.Type) -> [T] where T: FixedWidthInteger {
        var out = [T](repeating: 0, count: data.count / MemoryLayout<T>.size)
        out.withUnsafeMutableBytes { to in _ = data.copyBytes(to: to) }
        return out
    }

    static func values(_ data: Data, _: Float.Type) -> [Float] {
        var out = [Float](repeating: 0, count: data.count / 4)
        out.withUnsafeMutableBytes { to in _ = data.copyBytes(to: to) }
        return out
    }
}

/// What a replay found.
public struct DeckReplayOutcome {
    /// blocks rendered, and those held against the recording
    public var blocks = 0
    public var compared = 0
    /// samples compared (every channel), the largest difference and the root mean square of them all, full scale 1
    public var samples = 0
    public var largest = 0.0
    public var rms = 0.0
    /// the web's 16 bits: samples that differ once the replay is rounded as deck.ts rounds, and by how many steps at most
    public var steps = 0
    public var largestStep = 0
    /// the web's blocks' loudest samples (floats): the largest difference
    public var peaksLargest = 0.0
    public var peaksCompared = 0
    /// the web's: the lead the messages were told at (seconds) and the worst miss against the voice's reports (song s)
    public var lead: Double?
    public var worstMiss: Double?
    /// the web's: the tap's offset against the replay, samples
    public var lag: Int?
    /// why some or all of it couldn't be compared
    public var notes: [String] = []

    public static func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -.infinity }
    public var largestDB: Double { Self.db(largest) }
    public var rmsDB: Double { Self.db(rms) }
    public var peaksDB: Double { Self.db(peaksLargest) }

    /// 7.0's test B: within -100 dB of full scale. The web's 16 bits: every sample as deck.ts rounded it, and every
    /// block's loudest sample within -100 dB.
    public var withinTestB: Bool {
        guard samples > 0 else { return false }
        if steps > 0 || largestStep > 0 { return false }
        return largestDB <= -100 || (peaksCompared > 0 && steps == 0 && peaksDB <= -100)
    }
}

public enum DeckReplay {
    // MARK: the phone's

    /// The phone's recording: every block again from the voice's state at the engine's start before it, told the
    /// messages the render told it, at its now - and compared, float for float, with what the render wrote. Blocks after
    /// one the tap lost aren't compared until the next start (the voice is from rest there again).
    public static func phone(_ file: DeckRecordingFile) -> DeckReplayOutcome? {
        guard let phone = file.phone else { return nil }
        var outcome = DeckReplayOutcome()
        var windows: [UInt32: DeckPCM] = [:]
        var shapes: [UInt32: (start: Double, rate: Double)] = [:]
        for w in phone.windows {
            let pcm = DeckPCM(channelCount: Swift.max(1, w.channels), capacity: w.length)
            for c in 0..<w.channels {
                let channel = pcm.channel(c)
                for (i, v) in w.samples[c].enumerated() where w.from + i < w.length { channel[w.from + i] = v }
            }
            windows[w.id] = pcm
            shapes[w.id] = (w.start, w.rate)
        }
        func window(_ id: UInt32) -> VoiceWindow? {
            guard let pcm = windows[id], let shape = shapes[id] else { return nil }
            return pcm.voiceWindow(start: shape.start, rate: shape.rate)
        }
        let largestBlock = Int(phone.blocks.map(\.frames).max() ?? 0)
        let voice = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        voice.initialize(to: DeckRender.newState())
        let left = UnsafeMutablePointer<Float>.allocate(capacity: Swift.max(1, largestBlock))
        let right = UnsafeMutablePointer<Float>.allocate(capacity: Swift.max(1, largestBlock))
        let outputs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        outputs[0] = left
        outputs[1] = right
        defer {
            voice.pointee.deallocate()
            voice.deinitialize(count: 1)
            voice.deallocate()
            left.deallocate()
            right.deallocate()
            outputs.deallocate()
        }
        var next = 0
        var at = 0
        var starts: UInt64?
        var exact = false
        var lost: UInt64 = 0
        var lostMessages: UInt64 = 0
        var sum = 0.0
        for block in phone.blocks {
            if starts != block.starts {
                // as the deck engine's stop left it: made afresh around the window it had (DeckEngine.settleStopped)
                voice.pointee.deallocate()
                voice.pointee = DeckRender.newState()
                voice.pointee.window = block.windowBefore == 0 ? nil : window(block.windowBefore)
                starts = block.starts
                exact = block.windowBefore == 0 || windows[block.windowBefore] != nil
            }
            if block.lostBlocks > lost || block.lostMessages > lostMessages {
                lost = block.lostBlocks
                lostMessages = block.lostMessages
                exact = false
                outcome.notes.append("the tap lost blocks or messages before block \(block.block): not compared until the next start")
            }
            while next < phone.applied.count, let b = number(phone.applied[next]["block"]), UInt64(b) < block.block {
                exact = false
                next += 1
            }
            while next < phone.applied.count, let b = number(phone.applied[next]["block"]), UInt64(b) == block.block {
                let entry = phone.applied[next]
                next += 1
                guard let message = message(entry, window: window) else {
                    exact = false
                    outcome.notes.append("a window the file doesn't hold, before block \(block.block)")
                    continue
                }
                DeckRender.command(voice, message, now: block.now, rate: block.rate)
            }
            let frames = Int(block.frames)
            DeckRender.render(voice, UnsafeMutableBufferPointer(start: outputs, count: 2), frames: frames, rate: block.rate,
                              now: block.now)
            _ = DeckRender.report(voice, frames: frames, rate: block.rate, now: block.now)
            outcome.blocks += 1
            if exact, at + frames <= phone.audio[0].count {
                outcome.compared += 1
                for c in 0..<2 {
                    let out = c == 0 ? left : right
                    for i in 0..<frames {
                        let d = Double(out[i]) - Double(phone.audio[c][at + i])
                        sum += d * d
                        outcome.largest = Swift.max(outcome.largest, Swift.abs(d))
                    }
                }
                outcome.samples += 2 * frames
            }
            at += frames
        }
        outcome.rms = outcome.samples > 0 ? (sum / Double(outcome.samples)).squareRoot() : 0
        return outcome
    }

    static func number(_ value: WebJSON.Value?) -> Double? { if case .number(let n)? = value { return n }; return nil }

    /// A file's message as the voice is told it - a window from those the replay has, by id.
    static func message(_ entry: WebJSON.Value, window: (UInt32) -> VoiceWindow?) -> VoiceMessage? {
        func n(_ key: String) -> Double { number(entry[key]) ?? .nan }
        guard case .string(let type)? = entry["type"] else { return nil }
        switch type {
        case "window":
            let id = UInt32(number(entry["id"]) ?? 0)
            if id == 0 { return .window(nil) }
            return window(id).map { .window($0) }
        case "take": return .take(at: n("at"), rate: n("rate"), time: n("time"), until: n("until"))
        case "drive": return .drive(at: n("at"), rate: n("rate"), accel: number(entry["accel"]), time: n("time"), until: n("until"))
        case "hand": return .hand(at: n("at"), time: n("time"))
        case "fade": return .fade(seconds: n("seconds"))
        case "stop": return .stop
        default: return nil
        }
    }

    // MARK: the web's

    /// The voice's block in samples (analysis.ts blockOf): the main-thread voice's as its file says, else the
    /// worklet's render quantum.
    public static func blockOf(_ file: DeckRecordingFile) -> Int {
        guard file.voice == "script" else { return 128 }
        if let block = file.block, block > 0 { return Int(block) }
        return 1_024
    }

    /// The blocks' times (analysis.ts grid).
    struct Grid {
        var frames: Int
        var at: (Int) -> Double
        var index: (Double) -> Int
        var reported: (Int) -> Int
    }

    static func grid(_ file: DeckRecordingFile, from: Double) -> Grid {
        let rate = file.sampleRate
        let frames = blockOf(file)
        let first = file.heard.first?.time ?? from
        if file.voice == "script" {
            let seconds = Double(frames) / rate
            var indices: [Int] = [], times: [Double] = []
            var index = 0
            for (i, heard) in file.heard.enumerated() {
                if i > 0 { index += Swift.max(1, Int(JSMath.round((heard.time - file.heard[i - 1].time) / seconds))) }
                indices.append(index)
                times.append(heard.time)
            }
            let last = indices.count - 1
            let at = { (b: Int) -> Double in
                if last < 0 { return first + Double(b) * seconds }
                if b <= indices[0] { return times[0] + Double(b - indices[0]) * seconds }
                if b >= indices[last] { return times[last] + Double(b - indices[last]) * seconds }
                var lo = 0, hi = last
                while hi - lo > 1 {
                    let mid = (lo + hi) >> 1
                    if indices[mid] <= b { lo = mid } else { hi = mid }
                }
                if indices[lo] == b { return times[lo] }
                return times[lo] + (Double(b - indices[lo]) * (times[hi] - times[lo])) / Double(indices[hi] - indices[lo])
            }
            let indexOf = { (t: Double) -> Int in
                var b = Int(((t - first) / seconds).rounded(.down))
                while at(b + 1) <= t { b += 1 }
                while b > -10_000_000 && at(b) > t { b -= 1 }
                return b
            }
            return Grid(frames: frames, at: at, index: indexOf, reported: { indices[$0] })
        }
        let f0 = JSMath.round(first * rate)
        return Grid(frames: frames, at: { (f0 + Double($0 * frames)) / rate },
                    index: { Int(((($0 * rate) - f0) / Double(frames)).rounded(.down)) },
                    reported: { Int(JSMath.round((file.heard[$0].time * rate - f0) / Double(frames))) })
    }

    /// A recorded message as the voice is told it (analysis.ts told): the main-thread voice hears what is timed its lag
    /// later; nil for a window the replay can't give.
    static func told(_ file: DeckRecordingFile, _ m: WebJSON.Value, windowFor: ((Double, Double, Int) -> [[Float]]?)?,
                     keep: inout [DeckPCM]) -> VoiceMessage? {
        let lag = file.voice == "script" ? file.scriptLagSeconds : 0
        func n(_ key: String) -> Double { number(m[key]) ?? .nan }
        guard case .string(let type)? = m["type"] else { return nil }
        switch type {
        case "window":
            guard let windowFor, let channels = windowFor(n("start"), n("rate"), Int(n("length"))), !channels.isEmpty else { return nil }
            let pcm = DeckPCM(channels)
            keep.append(pcm)
            return .window(pcm.voiceWindow(start: n("start"), rate: n("rate")))
        case "take": return .take(at: n("at"), rate: n("rate"), time: n("time") + lag, until: n("until") + lag)
        case "drive": return .drive(at: n("at"), rate: n("rate"), accel: number(m["accel"]), time: n("time") + lag, until: n("until") + lag)
        case "hand": return .hand(at: n("at"), time: n("time") + lag)
        case "fade": return .fade(seconds: n("seconds"))
        case "stop": return .stop
        default: return nil
        }
    }

    struct Started {
        var grid: Grid
        var startBlock: Int
        var endBlock: Int
        /// in the order of their context times (a stable sort, as JavaScript's)
        var messages: [(message: WebJSON.Value, at: Double)]
    }

    static func starting(_ file: DeckRecordingFile, from: Double, to: Double) -> Started {
        let g = grid(file, from: from)
        var timed: [(index: Int, message: WebJSON.Value, at: Double)] = []
        for (i, m) in file.messages.enumerated() {
            let t: Double = number(m["t"]) ?? 0
            timed.append((i, m, t / 1000 + file.offset))
        }
        timed.sort { (a: (index: Int, message: WebJSON.Value, at: Double), b: (index: Int, message: WebJSON.Value, at: Double)) -> Bool in
            a.at < b.at || (a.at == b.at && a.index < b.index)
        }
        let messages: [(message: WebJSON.Value, at: Double)] = timed.map { (message: $0.message, at: $0.at) }
        return Started(grid: g, startBlock: g.index(from), endBlock: g.index(to) + 1, messages: messages)
    }

    /// How a timing fits (analysis.ts fitOf): the path alone replayed a block at a time, its read head at each block's
    /// end held against what the voice said of itself there, once it followed a take.
    static func fit(_ file: DeckRecordingFile, _ toldAt: [Int], _ s: Started) -> (worst: Double, sum: Double, reports: Int) {
        let rate = file.sampleRate
        let voice = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        voice.initialize(to: DeckRender.newState())
        let g = s.grid
        let left = UnsafeMutablePointer<Float>.allocate(capacity: g.frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: g.frames)
        let outputs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        outputs[0] = left
        outputs[1] = right
        defer {
            voice.pointee.deallocate()
            voice.deinitialize(count: 1)
            voice.deallocate()
            left.deallocate()
            right.deallocate()
            outputs.deallocate()
        }
        var byBlock: [Int: VoiceHeard] = [:]
        for (i, heard) in file.heard.enumerated() { byBlock[g.reported(i)] = heard }
        var next = 0
        var taken = false
        var worst = 0.0, sum = 0.0, reports = 0
        var keep: [DeckPCM] = []
        var b = s.startBlock
        while b < s.endBlock {
            let at = g.at(b)
            while next < s.messages.count, (next < toldAt.count ? toldAt[next] : Int.max) <= b {
                let said = told(file, s.messages[next].message, windowFor: nil, keep: &keep)
                next += 1
                guard let said else { continue }
                if case .take = said { taken = true }
                DeckRender.command(voice, said, now: at, rate: rate)
            }
            DeckRender.render(voice, UnsafeMutableBufferPointer(start: outputs, count: 2), frames: g.frames, rate: rate, now: at)
            _ = DeckRender.report(voice, frames: g.frames, rate: rate, now: at)
            if let heard = byBlock[b], taken {
                let miss = Swift.abs(voice.pointee.pos - heard.pos)
                worst = Swift.max(worst, miss)
                sum += miss
                reports += 1
            }
            b += 1
        }
        return (worst, sum, reports)
    }

    static func timed(_ m: WebJSON.Value) -> Bool {
        m["type"] == .string("take") || m["type"] == .string("fade") || m["type"] == .string("stop")
    }

    /// When the voice was told each message (analysis.ts planTiming): each at the first block at least a lead after it
    /// was posted - the lead that fits the voice's reports best of a few a host can have - then each take, fade and stop
    /// moved to the block that fits best within three either side, in the order posted.
    static func planTiming(_ file: DeckRecordingFile, _ s: Started) -> (told: [Int], lead: Double, worst: Double, reports: Int) {
        let block = Double(blockOf(file)) / file.sampleRate
        let g = s.grid
        let toldAt = { (lead: Double) -> [Int] in
            s.messages.map { m in
                var b = g.index(m.at + lead)
                if g.at(b) < m.at + lead - 1e-12 { b += 1 }
                return b
            }
        }
        let steps: [Double] = file.voice == "script" ? [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4] : [-1, 0, 1, 2, 3, 4, 6, 8, 12, 16]
        var best = (lead: block, told: toldAt(block), worst: Double.infinity, sum: Double.infinity, reports: 0)
        for step in steps {
            let trial = toldAt(step * block)
            let f = fit(file, trial, s)
            if f.reports > 0 && f.sum < best.sum - 1e-12 { best = (step * block, trial, f.worst, f.sum, f.reports) }
        }
        guard best.reports > 0 else { return (best.told, best.lead, .infinity, 0) }
        var toldAtBest = best.told
        var sum = best.sum, worst = best.worst
        for j in s.messages.indices where timed(s.messages[j].message) {
            let low = j > 0 ? toldAtBest[j - 1] : Int.min
            let high = j + 1 < toldAtBest.count ? toldAtBest[j + 1] : Int.max
            let here = toldAtBest[j]
            var c = Swift.max(low, here - 3)
            while c <= Swift.min(high, here + 3) {
                if c != toldAtBest[j] {
                    var trial = toldAtBest
                    trial[j] = c
                    let f = fit(file, trial, s)
                    if f.sum < sum - 1e-12 {
                        toldAtBest[j] = c
                        sum = f.sum
                        worst = f.worst
                    }
                }
                c += 1
            }
        }
        return (toldAtBest, best.lead, worst, best.reports)
    }

    /// The window the voice had as the recording began, which the web's file doesn't carry (it was sent before).
    public struct WindowAtStart {
        public var channels: [[Float]]
        public var start: Double
        public var rate: Double
        public init(channels: [[Float]], start: Double, rate: Double) {
            self.channels = channels
            self.start = start
            self.rate = rate
        }
    }

    /// The web's recording: the voice from rest, told the recording's messages at the timing that fits its reports, a
    /// block at a time as its host renders - then the tap's 16 bits held against it, from the first take on, at the
    /// offset (within `reach` samples of where the tap's block times put it) where they agree best.
    public static func web(_ file: DeckRecordingFile, windowAtStart: WindowAtStart? = nil, reach: Int = 4_096,
                           windowFor: @escaping (Double, Double, Int) -> [[Float]]?) -> DeckReplayOutcome {
        var outcome = DeckReplayOutcome()
        let rate = file.sampleRate
        guard let firstTime = file.blockTimes.first, file.channels >= 1 else {
            outcome.notes.append("the file has no tapped audio")
            return outcome
        }
        let tapFrames = file.int16.count / file.channels
        let from = firstTime
        let to = firstTime + Double(tapFrames) / rate
        let s = starting(file, from: from, to: to)
        let plan = planTiming(file, s)
        outcome.lead = plan.lead
        outcome.worstMiss = plan.worst
        let g = s.grid
        let n = Swift.max(0, (s.endBlock - s.startBlock) * g.frames)
        var replayed = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
        let voice = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        voice.initialize(to: DeckRender.newState())
        let left = UnsafeMutablePointer<Float>.allocate(capacity: g.frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: g.frames)
        let outputs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        outputs[0] = left
        outputs[1] = right
        defer {
            voice.pointee.deallocate()
            voice.deinitialize(count: 1)
            voice.deallocate()
            left.deallocate()
            right.deallocate()
            outputs.deallocate()
        }
        var keep: [DeckPCM] = []
        if let start = windowAtStart {
            let pcm = DeckPCM(start.channels)
            keep.append(pcm)
            DeckRender.command(voice, .window(pcm.voiceWindow(start: start.start, rate: start.rate)), now: g.at(s.startBlock), rate: rate)
        }
        var next = 0
        var firstTake = -1
        var i = 0
        var b = s.startBlock
        while b < s.endBlock {
            let at = g.at(b)
            while next < s.messages.count, (next < plan.told.count ? plan.told[next] : Int.max) <= b {
                let said = told(file, s.messages[next].message, windowFor: windowFor, keep: &keep)
                next += 1
                guard let said else {
                    if s.messages[next - 1].message["type"] == .string("window") {
                        outcome.notes.append("a window the replay wasn't given")
                    }
                    continue
                }
                if case .take = said, firstTake < 0 { firstTake = i }
                DeckRender.command(voice, said, now: at, rate: rate)
            }
            DeckRender.render(voice, UnsafeMutableBufferPointer(start: outputs, count: 2), frames: g.frames, rate: rate, now: at)
            _ = DeckRender.report(voice, frames: g.frames, rate: rate, now: at)
            for k in 0..<g.frames {
                replayed[0][i + k] = left[k]
                replayed[1][i + k] = right[k]
            }
            i += g.frames
            outcome.blocks += 1
            b += 1
        }
        guard firstTake >= 0 else {
            outcome.notes.append("no take in the recording: nothing the voice played from rest to compare")
            return outcome
        }
        // where the tap's sample n sits in the replay: its block's time, then the offset that agrees best
        let t0 = g.at(s.startBlock)
        let channels = file.channels
        func place(_ sample: Int) -> Int {
            let k = sample / file.tapBlock
            let time = k < file.blockTimes.count ? file.blockTimes[k] : firstTime + Double(sample) / rate
            return Int(JSMath.round((time - t0) * rate)) + sample % file.tapBlock
        }
        func tapped(_ sample: Int, _ c: Int) -> Int16 { file.int16[sample * channels + Swift.min(c, channels - 1)] }
        // the stretch to align on: the loudest 2,048 of the tap after the first take
        var loudest = (at: -1, energy: -1.0)
        var sample = 0
        while sample + 2_048 <= tapFrames {
            if place(sample) >= firstTake {
                var energy = 0.0
                for j in Swift.stride(from: sample, to: sample + 2_048, by: 4) { energy += Double(tapped(j, 0)) * Double(tapped(j, 0)) }
                if energy > loudest.energy { loudest = (sample, energy) }
            }
            sample += 1_024
        }
        guard loudest.at >= 0, loudest.energy > 0 else {
            outcome.notes.append("the tap is silent after the first take")
            return outcome
        }
        var bestLag = 0, bestError = Double.infinity
        for lag in -reach...reach {
            var error = 0.0
            for j in loudest.at..<(loudest.at + 2_048) {
                let r = place(j) + lag
                guard r >= 0, r < n else { error = .infinity; break }
                let d = Double(DeckRecorder.int16(replayed[0][r])) - Double(tapped(j, 0))
                error += d * d
                if error >= bestError { break }
            }
            if error < bestError {
                bestError = error
                bestLag = lag
            }
        }
        outcome.lag = bestLag
        var sum = 0.0
        var peaks: [Int: Double] = [:]
        for j in 0..<tapFrames {
            let r = place(j) + bestLag
            guard r >= firstTake, r < n else { continue }
            for c in 0..<channels {
                let v = replayed[Swift.min(c, 1)][r]
                let step = Swift.abs(Int(DeckRecorder.int16(v)) - Int(tapped(j, c)))
                if step > 0 { outcome.steps += 1 }
                outcome.largestStep = Swift.max(outcome.largestStep, step)
                let d = Double(v) - Double(tapped(j, c)) / 32_767
                sum += d * d
                outcome.largest = Swift.max(outcome.largest, Swift.abs(d))
                outcome.samples += 1
                peaks[j / file.tapBlock, default: 0] = Swift.max(peaks[j / file.tapBlock, default: 0], Double(Swift.abs(v)))
            }
        }
        outcome.rms = outcome.samples > 0 ? (sum / Double(outcome.samples)).squareRoot() : 0
        // a tapped block's loudest sample, as a float, where the whole block was replayed
        for (k, peak) in peaks where k < file.blockPeaks.count {
            let whole = (0..<file.tapBlock).allSatisfy { j in
                let r = place(k * file.tapBlock + j) + bestLag
                return r >= firstTake && r < n
            }
            guard whole else { continue }
            outcome.peaksLargest = Swift.max(outcome.peaksLargest, Swift.abs(peak - file.blockPeaks[k]))
            outcome.peaksCompared += 1
        }
        return outcome
    }
}
