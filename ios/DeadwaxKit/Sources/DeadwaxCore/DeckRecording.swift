import Foundation

// Debug's recording of the record's sound (notes/ios-specs/turntable.md 6.3; slice 4): 20 s of what the deck engine's
// voice played, every message it applied and when, every touch and handover, as the web's own file
// (`deadwax-turntable.json`, deck.ts's finishRecording, version 3) with the phone's own keys under `phone`, which the
// web's reader never looks at. The render taps each block into a ring made before the engine starts (DeckVoiceHost);
// the main thread drains it into a `DeckRecorder` here, and the file is written from that. `DeckReplay` reads either
// file back and plays it through the Swift voice.

// MARK: what the render taps

/// One block of the record's sound as the deck engine's render made it: written on the audio thread into the tap
/// ring's slot beside its samples, so plain numbers only.
public struct DeckTapBlock: Equatable, Sendable {
    /// the render's count of blocks before this one, and the engine's count of starts (the voice is made afresh around
    /// its window at every stop, so a new count is a voice from rest - which is where a replay begins again)
    public var block: UInt64 = 0
    public var starts: UInt64 = 0
    public var frames: UInt32 = 0
    public var channels: UInt32 = 0
    public var rate = 0.0
    /// the voice's now for the block, and `L`: how far behind the block's presentation it ran (3.2; offline 0)
    public var now = 0.0
    public var lead = 0.0
    /// the block's time stamp as the render was handed it: host ticks (0: none) and sample time
    public var hostTime: UInt64 = 0
    public var sampleTime = 0.0
    /// the window the voice had as the block began, and the one it rendered with (after the block's messages)
    public var windowBefore: UInt32 = 0
    public var window: UInt32 = 0
    /// how many messages the voice was told before the block - the tap's message ring holds them, in order
    public var messages: UInt32 = 0
    /// the voice's read head at the block's end (song s), and the block's loudest sample before the deck's EQ
    public var pos = 0.0
    public var peak: Float = 0
    /// blocks and messages the full rings lost before this one, since the recording began
    public var lostBlocks: UInt64 = 0
    public var lostMessages: UInt64 = 0
    public init() {}
}

/// A message as the voice was told it, before which block. The slot's pointers mean nothing once off the audio
/// thread; its window's id names the PCM the deck engine kept for the recording.
public struct DeckTapMessage {
    public var block: UInt64 = 0
    public var slot = DeckSlot()
    public init() {}
    public init(block: UInt64, slot: DeckSlot) {
        self.block = block
        self.slot = slot
    }
}

// MARK: the recorder

/// A recording under way, on the main thread: what the deck engine's tap gave, and what the deck did meanwhile. It
/// begins with the first block the tap gives - the deck engine starts tapping at a start, the voice then at rest -
/// and is done `seconds` of the host clock later.
public struct DeckRecorder {
    public static let seconds = 20.0

    public let seconds: Double
    /// page ms it was asked for
    public let armedAt: Double
    public private(set) var blocks: [DeckTapBlock] = []
    public private(set) var applied: [DeckTapMessage] = []
    public private(set) var lostBlocks: UInt64 = 0
    public private(set) var lostMessages: UInt64 = 0
    var left: [Float] = []
    var right: [Float] = []
    var posted: [String] = []
    var heard: [VoiceHeard] = []
    var touches: [String] = []
    var handovers: [String] = []
    var windows: [UInt32: DeckPCM] = [:]

    public init(seconds: Double = DeckRecorder.seconds, armedAt: Double) {
        self.seconds = seconds
        self.armedAt = armedAt
    }

    /// Whether the tap has given a block yet.
    public var started: Bool { !blocks.isEmpty }

    /// The seconds from its first block's now to its last block's end.
    public var recordedSeconds: Double {
        guard let first = blocks.first, let last = blocks.last, last.rate > 0 else { return 0 }
        return last.now + Double(last.frames) / last.rate - first.now
    }

    /// Done: `seconds` of the voice's clock since its first block, as of voice time `now`.
    public func done(now: Double) -> Bool {
        guard let first = blocks.first else { return false }
        return now - first.now >= seconds
    }

    /// Over: its seconds have passed by the clock - a block at or past its end seen (and not kept), its last block's
    /// end there, or the deck engine's clock there while the record rested. Once over, nothing more is kept. Judged by
    /// the clock, not by the last block kept: a rest across the end gives no block inside it, and a recording judged by
    /// its last block would then never end (slice 4's review).
    public private(set) var over = false

    /// Over, by the clock at voice time `now` (the deck engine's word, from a block or from its clock).
    public mutating func clock(_ now: Double) {
        if done(now: now) { over = true }
    }

    /// The bytes of its audio so far: what Debug says while it runs.
    public var frames: Int { left.count }

    /// A block the tap gave, with its samples (`right` nil: one channel).
    public mutating func block(_ block: DeckTapBlock, left: UnsafePointer<Float>, right: UnsafePointer<Float>?) {
        clock(block.now)
        if over { return }
        lostBlocks = Swift.max(lostBlocks, block.lostBlocks)
        lostMessages = Swift.max(lostMessages, block.lostMessages)
        blocks.append(block)
        let frames = Int(block.frames)
        self.left.append(contentsOf: UnsafeBufferPointer(start: left, count: frames))
        self.right.append(contentsOf: UnsafeBufferPointer(start: right ?? left, count: frames))
    }

    /// A message the voice was told.
    public mutating func message(_ message: DeckTapMessage) { applied.append(message) }

    /// A window's PCM, kept for the file by the id the deck engine gave it.
    public mutating func window(_ id: UInt32, _ pcm: DeckPCM) { windows[id] = pcm }

    /// What the deck posted, as the web's recorder notes it (deck.ts noteForRecording): page ms to a tenth, a window
    /// by its shape only.
    public mutating func posted(_ post: DeckPost, at ms: Double) {
        let t = JSMath.round(ms * 10) / 10
        var fields: [(String, Double?)] = []
        let type: String
        switch post {
        case .window(let window):
            type = "window"
            let length = window.pcm?.frames ?? window.channels.first?.count ?? 0
            fields = [("start", window.start), ("rate", window.rate), ("length", Double(length))]
        case let .take(at, rate, time, until):
            type = "take"
            fields = [("at", at), ("rate", rate), ("time", time), ("until", until)]
        case let .drive(at, rate, accel, time, until):
            type = "drive"
            fields = [("at", at), ("rate", rate)] + (accel.map { [("accel", $0)] } ?? []) + [("time", time), ("until", until)]
        case let .hand(at, time):
            type = "hand"
            fields = [("at", at), ("time", time)]
        case .fade(let seconds):
            type = "fade"
            fields = [("seconds", seconds)]
        case .stop:
            type = "stop"
        }
        posted.append(DeckFileText.object([("t", .number(t)), ("type", .text(type))] + fields.map { ($0.0, .number($0.1)) }))
    }

    /// What the voice said of where it was.
    public mutating func heard(_ said: VoiceHeard) { heard.append(said) }

    /// A touch as the deck had it (page ms, points), with the raw samples UIKit gave for it: each sample's own
    /// timestamp (UITouch.timestamp, seconds) and place, before PointerSamples kept or dropped any.
    public mutating func touch(_ kind: String, pointer: Int, at ms: Double?, x: Double?, y: Double?,
                               raw: [(time: Double, x: Double, y: Double)] = []) {
        var fields: [(String, DeckFileText.Value)] = [("kind", .text(kind)), ("pointer", .number(Double(pointer))),
                                                      ("t", .number(ms))]
        if let x, let y { fields += [("x", .number(x)), ("y", .number(y))] }
        if !raw.isEmpty {
            fields.append(("raw", .raw("[" + raw.map { "[\(DeckFileText.number($0.time)),\(DeckFileText.number($0.x)),\(DeckFileText.number($0.y))]" }.joined(separator: ",") + "]")))
        }
        touches.append(DeckFileText.object(fields))
    }

    /// A let-go's handover (3.5): its lead, the predicted `E` and - once known - the actual one, seconds.
    public mutating func handover(at ms: Double, lead: Double, predicted: Double, took: Double?) {
        handovers.append(DeckFileText.object([("t", .number(ms)), ("lead", .number(lead)), ("predicted", .number(predicted)),
                                              ("took", .number(took))]))
    }

    /// What the file says of where it was made.
    public struct About {
        public var when: String
        public var userAgent: String
        /// the device's audio after the voice: the IO buffer and the output's latency, seconds
        public var base: Double
        public var output: Double
        public init(when: String, userAgent: String, base: Double, output: Double) {
            self.when = when
            self.userAgent = userAgent
            self.base = base
            self.output = output
        }
    }

    /// The window's samples kept in the file: the stretch the read head could have reached - its block-end places
    /// over the blocks that rendered with the window, `margin` song seconds either side (more than a block's travel at
    /// the voice's fastest, 24x, and its kernel) - as frames [from, from + count).
    public static let margin = 2.0
    func kept(_ id: UInt32, _ pcm: DeckPCM, start: Double, rate: Double) -> (from: Int, count: Int) {
        var low = Double.infinity, high = -Double.infinity
        var previous: DeckTapBlock?
        for block in blocks {
            if block.window == id {
                low = Swift.min(low, block.pos)
                high = Swift.max(high, block.pos)
                if let previous, previous.starts == block.starts {
                    low = Swift.min(low, previous.pos)
                    high = Swift.max(high, previous.pos)
                }
            }
            previous = block
        }
        guard low <= high, rate > 0 else { return (0, 0) }
        let from = Swift.max(0, Int(((low - Self.margin - start) * rate).rounded(.down)))
        let to = Swift.min(pcm.frames, Int(((high + Self.margin - start) * rate).rounded(.up)))
        return to > from ? (from, to - from) : (0, 0)
    }

    /// The file: the web's version 3, every key it writes, and the phone's under `phone`.
    public func file(_ about: About) -> Data {
        let rate = blocks.first?.rate ?? 48_000
        let block = Double(blocks.first?.frames ?? 1_024)
        let count = left.count
        // the web's 16 bits, interleaved - as deck.ts rounds them
        var pcm = [Int16](repeating: 0, count: count * 2)
        for i in 0..<count {
            pcm[2 * i] = Self.int16(left[i])
            pcm[2 * i + 1] = Self.int16(right[i])
        }
        let int16 = pcm.withUnsafeBytes { Data($0) }.base64EncodedString()
        var floats = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            floats[i] = left[i]
            floats[count + i] = right[i]
        }
        let float32 = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
        let heardText = heard.map { said in
            DeckFileText.object([("type", .text("heard")), ("pos", .number(said.pos)), ("rate", .number(said.rate)),
                                 ("gain", .number(said.gain)), ("time", .number(said.time)), ("held", .number(said.held)),
                                 ("peaks", .number(said.peaks)), ("lowest", .number(said.lowest))])
        }
        let column = { (value: (DeckTapBlock) -> Double) -> DeckFileText.Value in
            .raw("[" + blocks.map { DeckFileText.number(value($0)) }.joined(separator: ",") + "]")
        }
        let phoneBlocks = DeckFileText.object([
            ("block", column { Double($0.block) }), ("starts", column { Double($0.starts) }),
            ("frames", column { Double($0.frames) }), ("rate", column { $0.rate }), ("now", column { $0.now }),
            ("L", column { $0.lead }), ("hostTime", column { Double($0.hostTime) }), ("sampleTime", column { $0.sampleTime }),
            ("windowBefore", column { Double($0.windowBefore) }), ("window", column { Double($0.window) }),
            ("messages", column { Double($0.messages) }), ("pos", column { $0.pos }), ("peak", column { Double($0.peak) }),
        ])
        let appliedText = applied.map { DeckFileText.object(Self.fields(of: $0)) }
        var windowTexts: [String] = []
        for id in windows.keys.sorted() {
            guard let pcm = windows[id], let shape = applied.first(where: { $0.slot.id == id && $0.slot.tag == DeckSlot.Tag.window.rawValue })?.slot
                    ?? held(id) else { continue }
            let span = kept(id, pcm, start: shape.a, rate: shape.b)
            var samples = [Float](repeating: 0, count: span.count * pcm.channelCount)
            for c in 0..<pcm.channelCount {
                let channel = pcm.channel(c)
                for i in 0..<span.count { samples[c * span.count + i] = channel[span.from + i] }
            }
            windowTexts.append(DeckFileText.object([
                ("id", .number(Double(id))), ("start", .number(shape.a)), ("rate", .number(shape.b)),
                ("length", .number(Double(pcm.frames))), ("channels", .number(Double(pcm.channelCount))),
                ("from", .number(Double(span.from))), ("frames", .number(Double(span.count))),
                ("format", .text("float32le")),
                ("base64", .text(samples.withUnsafeBytes { Data($0) }.base64EncodedString())),
            ]))
        }
        let phone = DeckFileText.object([
            ("version", .number(1)), ("blocks", .raw(phoneBlocks)), ("applied", .raw("[" + appliedText.joined(separator: ",") + "]")),
            ("audio", .raw(DeckFileText.object([("format", .text("float32le")), ("layout", .text("planar")),
                                                ("channels", .number(2)), ("frames", .number(Double(count))),
                                                ("base64", .text(float32))]))),
            ("windows", .raw("[" + windowTexts.joined(separator: ",") + "]")),
            ("touches", .raw("[" + touches.joined(separator: ",") + "]")),
            ("handovers", .raw("[" + handovers.joined(separator: ",") + "]")),
            ("lost", .raw(DeckFileText.object([("blocks", .number(Double(lostBlocks))), ("messages", .number(Double(lostMessages)))]))),
            ("armedAt", .number(armedAt)),
        ])
        let first = blocks.first?.now ?? 0
        let text = DeckFileText.object([
            ("recording", .text("deadwax turntable sound")), ("version", .number(3)), ("when", .text(about.when)),
            ("userAgent", .text(about.userAgent)), ("secure", .raw("null")), ("voice", .text("phone")),
            ("sampleRate", .number(rate)), ("delaySeconds", .number(DeckVoice.handDelayS)), ("block", .number(block)),
            ("scriptLagSeconds", .number(0)),
            ("latency", .raw(DeckFileText.object([("block", .number(block)), ("base", .number(about.base)),
                                                  ("output", .number(about.output))]))),
            // the voice's clock is the host clock in seconds and the deck's page ms are the same clock's: no offset
            ("clock", .raw(DeckFileText.object([("offset", .number(0)), ("step", .number(block / rate)),
                                                ("count", .number(Double(blocks.count)))]))),
            ("report", .raw("null")), ("pageTimeAtStart", .number(first * 1_000)),
            ("tapBlock", .number(block)), ("blockTimes", column { $0.now }), ("blockPeaks", column { Double($0.peak) }),
            ("limiter", .raw(DeckFileText.object([("ceiling", .number(DeckVoice.ceiling(PlatformMaths()))),
                                                  ("lookaheadSeconds", .number(DeckVoice.lookaheadS))]))),
            ("audio", .raw(DeckFileText.object([("format", .text("int16le")), ("channels", .number(2)),
                                                ("frames", .number(Double(count))), ("base64", .text(int16))]))),
            ("messages", .raw("[" + posted.joined(separator: ",") + "]")),
            ("heard", .raw("[" + heardText.joined(separator: ",") + "]")),
            ("phone", .raw(phone)),
        ])
        return Data(text.utf8)
    }

    /// A window that was the voice's when the recording began (no message for it in the recording): its shape from
    /// the first block that rendered with it is not enough, so the deck engine hands its message along with its PCM.
    var windowShapes: [UInt32: DeckSlot] = [:]
    public mutating func window(_ id: UInt32, _ pcm: DeckPCM, shape: DeckSlot) {
        windows[id] = pcm
        windowShapes[id] = shape
    }
    func held(_ id: UInt32) -> DeckSlot? { windowShapes[id] }

    /// deck.ts's 16 bits: Math.max(-32768, Math.min(32767, Math.round(v * 32767))).
    public static func int16(_ v: Float) -> Int16 {
        Int16(JSMath.max(-32_768, JSMath.min(32_767, JSMath.round(Double(v) * 32_767))))
    }

    static func fields(of message: DeckTapMessage) -> [(String, DeckFileText.Value)] {
        let s = message.slot
        var out: [(String, DeckFileText.Value)] = [("block", .number(Double(message.block)))]
        switch DeckSlot.Tag(rawValue: s.tag) ?? .stop {
        case .window: out += [("type", .text("window")), ("id", .number(Double(s.id))), ("start", .number(s.a)),
                              ("rate", .number(s.b)), ("length", .number(Double(s.length))),
                              ("channels", .number(s.second == nil ? 1 : 2))]
        case .noWindow: out += [("type", .text("window")), ("id", .number(0))]
        case .take: out += [("type", .text("take")), ("at", .number(s.a)), ("rate", .number(s.b)), ("time", .number(s.c)),
                            ("until", .number(s.d))]
        case .drive: out += [("type", .text("drive")), ("at", .number(s.a)), ("rate", .number(s.b))]
            + (s.hasAccel ? [("accel", .number(s.c))] : []) + [("time", .number(s.d)), ("until", .number(s.e))]
        case .hand: out += [("type", .text("hand")), ("at", .number(s.a)), ("time", .number(s.b))]
        case .fade: out += [("type", .text("fade")), ("seconds", .number(s.a))]
        case .stop: out += [("type", .text("stop"))]
        }
        return out
    }
}

/// A finished recording on its way to a file, written off the main thread: handed over whole, and nothing else holds
/// it (its windows' PCM is read, never written, from here on).
public struct DeckRecordingWrite: @unchecked Sendable {
    public let recorder: DeckRecorder
    public let about: DeckRecorder.About
    public let url: URL
    public init(recorder: DeckRecorder, about: DeckRecorder.About, url: URL) {
        self.recorder = recorder
        self.about = about
        self.url = url
    }

    /// The file written: its bytes, or why not.
    public func write() -> Result<Int, Error> {
        let data = recorder.file(about)
        do {
            try data.write(to: url, options: .atomic)
            return .success(data.count)
        } catch {
            return .failure(error)
        }
    }
}

/// JSON written by hand, as the web's JSON.stringify writes it (WebJSON's numbers and strings) - objects in the order
/// given, a non-finite number as null.
public enum DeckFileText {
    public enum Value {
        case number(Double?)
        case text(String)
        /// already JSON
        case raw(String)
    }

    public static func number(_ value: Double) -> String { value.isFinite ? WebJSON.number(value) : "null" }

    public static func object(_ fields: [(String, Value)]) -> String {
        "{" + fields.map { (key, value) -> String in
            let written: String
            switch value {
            case .number(let n): written = n.map(number) ?? "null"
            case .text(let s): written = WebJSON.quoted(s)
            case .raw(let r): written = r
            }
            return WebJSON.quoted(key) + ":" + written
        }.joined(separator: ",") + "}"
    }
}
