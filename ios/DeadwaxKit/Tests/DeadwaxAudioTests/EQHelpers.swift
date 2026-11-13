#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// What the EQ's tests share (notes/ios-specs/eq.md 1.7).

/// An offline engine as `offlineEngine` makes it - everything scheduled at once, 0.1 s buffers - with the EQ's unit
/// in its graph, or (`eq` false) none at all.
func eqEngine(rate: Double, channels: AVAudioChannelCount = 2, eq: Bool = true) throws -> PlaybackEngine {
    var settings = PlaybackEngine.Settings()
    settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)
    settings.aheadSeconds = 60
    settings.startSeconds = 0
    settings.bufferSeconds = 0.1
    settings.changeSettleSeconds = 0
    settings.eq = eq
    settings.varispeedAtOne = testVarispeedAtOne
    let engine = try PlaybackEngine(settings: settings)
    engine.scheduleLag = testScheduleLag
    return engine
}

/// Every channel of `frames` frames, rendered 4,096 at a time (the unit's blocks are the render's), the engine's
/// completions handled between; `before` is called with the frames rendered so far ahead of each block.
func renderChannels(_ engine: PlaybackEngine, frames: Int, before: ((Int) -> Void)? = nil,
                    sourceLocation: SourceLocation = #_sourceLocation) throws -> [[Float]] {
    var out: [[Float]] = []
    var done = 0
    while done < frames {
        before?(done)
        let piece = try engine.renderOffline(AVAudioFrameCount(min(4_096, frames - done)))
        if out.isEmpty { out = Array(repeating: [], count: Int(piece.format.channelCount)) }
        for channel in out.indices { out[channel] += samples(piece, channel: channel) }
        done += Int(piece.frameLength)
        try completionsHandled(engine, sourceLocation: sourceLocation)
    }
    return out
}

/// A bank of the tone's ten bands alone, at the test's own output.
func toneBank(_ gains: [Double], rate: Double, version: Int, key: String = EQTestCurve.key,
              preamp: Double? = 0) -> EQBank {
    EQBank.make(rate: rate, key: key, version: version, on: true, correction: [], offsets: .zero, bands: gains,
                preamp: preamp)
}

/// Ten gains with one band set.
func band(_ index: Int, _ gain: Double) -> [Double] {
    var gains = EQGraphic.flat
    gains[index] = gain
    return gains
}

/// An AutoEq-shaped correction (crinacle's AirPods Pro's first and sixth filters, two of ours), to put another
/// output's curve in.
let aCorrection = [
    EQFilter(id: 1, kind: .lowShelf, written: "LSC", fc: 105, gain: 2.6, width: .q(0.7)),
    EQFilter(id: 2, kind: .peak, fc: 514, gain: -4.4, width: .q(0.68)),
    EQFilter(id: 3, kind: .peak, fc: 3_000, gain: 3, width: .q(2)),
    EQFilter(id: 4, kind: .highShelf, written: "HSC", fc: 10_000, gain: -0.5, width: .q(0.7)),
]

/// Core's own render (`EQRender.process`) over `input`, in blocks of `block` frames from its first - the bank
/// offered at a block is the one whose frame it starts at. What the unit must equal, sample for sample.
func coreRender(_ input: [[Float]], rate: Double, banks: [Int: EQBank], block: Int = 4_096,
                fadeFrames: Int? = nil) -> [[Float]] {
    let channels = input.count
    let frames = input[0].count
    let state = EQRender.make(rate: rate, channels: channels, maximumFrames: block, fadeFrames: fadeFrames)
    defer { EQRender.free(state) }
    let buffers = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
    let storage = UnsafeMutablePointer<Float>.allocate(capacity: channels * block)
    defer {
        buffers.deallocate()
        storage.deallocate()
    }
    for c in 0..<channels { buffers[c] = storage + c * block }
    var out = input
    var at = 0
    while at < frames {
        let n = min(block, frames - at)
        for c in 0..<channels {
            input[c].withUnsafeBufferPointer { (from: UnsafeBufferPointer<Float>) -> Void in
                buffers[c].update(from: from.baseAddress! + at, count: n)
            }
        }
        if let bank = banks[at] {
            let packed = bank.packed
            packed.withUnsafeBufferPointer { (offered: UnsafeBufferPointer<Double>) -> Void in
                EQRender.process(state, buffers: UnsafePointer(buffers), frames: n, offered: offered.baseAddress)
            }
        } else {
            EQRender.process(state, buffers: UnsafePointer(buffers), frames: n, offered: nil)
        }
        for c in 0..<channels {
            for i in 0..<n { out[c][at + i] = buffers[c][i] }
        }
        at += n
    }
    return out
}

/// An 8th-order Butterworth high-pass in Double (four of the cookbook's high-pass sections, Butterworth's Qs), run
/// over a render to find a click - 1.7 test 3's measure.
func butterworthHighPass(_ x: [Float], cutoff: Double, rate: Double) -> [Double] {
    var y = x.map(Double.init)
    for k in 0..<4 {
        let q = 1 / (2 * cos(Double.pi * Double(2 * k + 1) / 16))
        let c = EQCookbook.coefficients(.highPass, gain: 0, f0: cutoff, rate: rate, value: q, isBandwidthOrS: false)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for n in y.indices {
            let xn = y[n]
            let yn = c.b0 * xn + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
            x2 = x1
            x1 = xn
            y2 = y1
            y1 = yn
            y[n] = yn
        }
    }
    return y
}

/// The largest of `x[range]`, in dBFS (-inf for none).
func peakDBFS(_ x: [Double], _ range: Range<Int>) -> Double {
    let clipped = max(range.lowerBound, 0)..<min(range.upperBound, x.count)
    let peak = x[clipped].reduce(0.0) { max($0, abs($1)) }
    return 20 * log10(peak)
}

/// Where two renders first part, over every channel (nil: the same, bit for bit). -0 and +0 are different bits.
func firstBitDifference(_ got: [[Float]], _ expected: [[Float]], in range: Range<Int>? = nil) -> String? {
    guard got.count == expected.count else { return "\(got.count) channels, expected \(expected.count)" }
    for c in got.indices {
        let r = range ?? 0..<max(got[c].count, expected[c].count)
        guard r.upperBound <= got[c].count, r.upperBound <= expected[c].count else {
            return "channel \(c): \(got[c].count) frames, expected \(expected[c].count) (compared to \(r.upperBound))"
        }
        for i in r where got[c][i].bitPattern != expected[c][i].bitPattern {
            return "channel \(c), frame \(i): \(got[c][i]), expected \(expected[c][i])"
        }
    }
    return nil
}

/// A track that plays `samples` at `rate`, under Up Next's `key`.
func memoryTrack(_ samples: [[Float]], rate: Double, key: Int) -> EngineTrack {
    entry(samples, rate: rate, key: key, id: "eq-\(key)")
}
#endif
