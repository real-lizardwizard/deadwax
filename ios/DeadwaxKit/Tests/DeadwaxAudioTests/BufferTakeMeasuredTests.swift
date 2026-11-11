#if canImport(AVFAudio)
import AVFAudio
import Foundation
import Testing
@testable import DeadwaxAudio

// A MEASUREMENT, printed - never a check (notes/ios.md "A node's buffers, taken late"). The engine's offline renders
// wait `PlaybackEngine.offlineScheduleSettle` after a buffer goes on a node, because AVAudioPlayerNode takes it on a
// queue of its own (its CommandQueue) and there is no fence to wait on instead: the settle is a bound on how late
// that queue runs, and only the machine running the tests knows how late that is. So it is timed wherever the tests
// run and printed as one line, "AVAudioPlayerNode taking a buffer, measured", in both of ios.yml's macOS runs - to
// read before the settle is changed again, and when a test says "AVAudioPlayerNode took the buffer late".
//
// It must NEVER assert on timing: a measurement that can fail is one more flaky test on the very machine it is there
// to measure. It checks nothing: an error is printed, a trial whose buffer never comes is counted. It is one of
// EngineRenderTests (serialized), so it never shares the machine with the engine's own renders.
extension EngineRenderTests {
    @Test func howLateANodeTakesABufferIsMeasured() {
        do {
            print(try BufferTake.measure())
        } catch {
            print("AVAudioPlayerNode taking a buffer: not measured (\(error))")
        }
    }
}

enum BufferTake {
    /// Frames rendered at a time while waiting for the buffer, and the wait between (on the engine's strict timer):
    /// the measurement's resolution.
    static let piece: AVAudioFrameCount = 64
    static let poll: TimeInterval = 0.000_2
    /// A trial whose buffer hasn't come by then is counted as that late, and as never taken.
    static let giveUp: TimeInterval = 0.5
    static let atOnce = 150
    static let behindTheHook = 50
    static let sleeps = 20

    /// Everything measured, as the one line printed. About a second here.
    static func measure() throws -> String {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for channel in 0..<2 { buffer.floatChannelData![channel].update(repeating: 0.25, count: 4_800) }
        // the tests' hook as the engine has it (`PlaybackEngine.scheduleLag`, its queue private): a serial queue of
        // the same QoS, each block held until its due time on the same strict timer, then the buffer scheduled
        let lag = testScheduleLag > 0 ? testScheduleLag : 0.010
        let hook = DispatchQueue(label: "deadwax.tests.schedule-lag-measured", qos: .userInitiated)

        var atOnce: [Double] = [], untaken = 0
        for _ in 0..<Self.atOnce {
            let (late, _) = try trial(format: format, buffer: buffer, lag: 0, hook: hook)
            if late == nil { untaken += 1 }
            atOnce.append(late ?? giveUp)
        }
        var pastDue: [Double] = [], hop: [Double] = []
        for _ in 0..<Self.behindTheHook {
            let (late, blockLate) = try trial(format: format, buffer: buffer, lag: lag, hook: hook)
            if late == nil { untaken += 1 }
            pastDue.append(late ?? giveUp)
            if let blockLate { hop.append(blockLate) }
        }
        // what the hook and the settle waited with until both were put on the strict timer: how late the system lets
        // an ordinary 10 ms sleep run on this machine (its timer coalescing)
        let sleeps = (0..<Self.sleeps).map { _ in
            let began = PlaybackEngine.hostSeconds()
            Thread.sleep(forTimeInterval: 0.010)
            return PlaybackEngine.hostSeconds() - began - 0.010
        }
        let settle = PlaybackEngine.offlineScheduleSettle
        return "AVAudioPlayerNode taking a buffer, measured (notes/ios.md \"A node's buffers, taken late\"; printed, "
            + "never checked) - asked at once, scheduleBuffer to the first render carrying it: "
            + spread(atOnce, over: [0.010, 0.020, 0.030], settle: settle, named: "the settle")
            + " - behind a \(ms(lag)) ms scheduleLag hook, its due time to the first render carrying it: "
            + spread(pastDue, over: [0.010, 0.020, 0.030], settle: settle - lag, named: "the settle less the lag")
            + "; the hook's own block past its due time: " + spread(hop, over: [], settle: nil, named: "")
            + " - never taken within \(whole(giveUp)) ms: \(untaken) - a 10 ms Thread.sleep past its time: "
            + spread(sleeps, over: [0.005, 0.020], settle: nil, named: "")
    }

    /// One trial, as rawLate in the investigation had it and as a test's first lane meets it: an offline engine
    /// started, then a new node attached and connected while it runs (every lane is), the buffer put on it - at once,
    /// or through the hook `lag` later - and play() at once; then rendered `piece` frames at a time until the output
    /// carries it. Seconds from when the node was asked to take it (the call, or the hook's due time) to the start of
    /// that render - an upper bound, within one poll - or nil past `giveUp`; and how late the hook's block ran past
    /// its due time (behind the hook, the render waits for the hook's call: below). A fresh engine's node takes its first buffer later than one on an engine long running (median
    /// 0.26 ms here, against 0.00), so this is the worse of the two.
    static func trial(format: AVAudioFormat, buffer: AVAudioPCMBuffer, lag: TimeInterval,
                      hook: DispatchQueue) throws -> (Double?, Double?) {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        _ = engine.mainMixerNode
        try engine.start()
        let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096)!
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        defer {
            hook.sync {} // the hook's block has run before the node goes (scheduling on a detached node throws)
            node.stop()
            engine.detach(node)
            engine.stop()
        }
        let blockLate = Late()
        let asked = PlaybackEngine.hostSeconds() + lag
        if lag > 0 {
            hook.async {
                PlaybackEngine.sleep(until: asked)
                blockLate.set(PlaybackEngine.hostSeconds() - asked)
                node.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { _ in }
            }
        } else {
            node.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { _ in }
        }
        node.play()
        // No render until the hook's call has returned, as in the engine (its render comes the settle after the
        // buffer was asked for, the hook's call the lag after): a scheduleBuffer called on one thread while an
        // offline render runs on another can block for a timed wait (5-6 ms here, now and then; up to 164 ms in a
        // background process), which is a path the tests never take - measured, it would only mislead.
        if lag > 0 { hook.sync {} }
        while true {
            let began = PlaybackEngine.hostSeconds()
            if began - asked > giveUp { return (nil, blockLate.value) }
            guard try engine.renderOffline(piece, to: out) == .success else { return (nil, blockLate.value) }
            let left = out.floatChannelData![0]
            if (0..<Int(out.frameLength)).contains(where: { left[$0] != 0 }) {
                return (max(0, began - asked), lag > 0 ? blockLate.value : nil)
            }
            PlaybackEngine.sleep(until: PlaybackEngine.hostSeconds() + poll)
        }
    }

    /// min / median / p90 / p99 / max in ms, and the share over each of `over` and `settle`.
    static func spread(_ values: [Double], over: [Double], settle: Double?, named: String) -> String {
        guard !values.isEmpty else { return "no trials" }
        let sorted = values.sorted()
        func rank(_ q: Double) -> Double { sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count) * q).rounded(.up)) - 1))] }
        var line = "\(sorted.count) trials, min \(ms(sorted[0])) / median \(ms(rank(0.5))) / p90 \(ms(rank(0.9))) / "
            + "p99 \(ms(rank(0.99))) / max \(ms(sorted[sorted.count - 1])) ms"
        var shares = over.map { "\(whole($0)) ms \(share(sorted, $0))" }
        if let settle { shares.append("\(whole(settle)) ms (\(named)) \(share(sorted, settle))") }
        if !shares.isEmpty { line += ", over " + shares.joined(separator: ", ") }
        return line
    }

    static func share(_ values: [Double], _ limit: Double) -> String {
        String(format: "%.1f%%", 100 * Double(values.filter { $0 > limit }.count) / Double(values.count))
    }

    static func ms(_ seconds: Double) -> String {
        let value = seconds * 1_000
        return value >= 10 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }

    static func whole(_ seconds: Double) -> String { String(format: "%.0f", seconds * 1_000) }

    /// A time the hook's block writes and the trial reads.
    final class Late {
        private let lock = NSLock()
        private var seconds: Double?
        func set(_ value: Double) { lock.withLock { seconds = value } }
        var value: Double? { lock.withLock { seconds } }
    }
}
#endif
