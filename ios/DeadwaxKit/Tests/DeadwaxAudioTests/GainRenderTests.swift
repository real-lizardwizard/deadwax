#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Normalization's multiply (GainedSource), rendered offline and compared sample by sample: Off is
// the decode bit for bit, a gain is exactly one Float multiply per sample, once, on every path, and an
// album at one gain joins as exactly as it does at none. In EngineRenderTests' suite, so it runs
// serialized with the other renders.
extension EngineRenderTests {
    @Test func noGainIsTheDecodeBitForBit() throws {
        let rate = 44_100.0
        let a = signal(frames: 13_230, channels: 2, seed: 0.11)
        let b = signal(frames: 11_025, channels: 2, seed: 0.71)
        let source = MemorySource(a, rate: rate)
        #expect(GainedSource.wrap(source, factor: nil) === source, "Off: the source itself, no wrapper")
        #expect(GainedSource.wrap(source, factor: 1) === source, "0.00 dB: the source itself")
        #expect(GainedSource.wrap(source, factor: 0.5) !== source)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([a, b], rate: rate, factors: [nil, 1]), from: 0)
        engine.settle()
        let total = a[0].count + b[0].count
        let out = try renderAll(engine, frames: total + 4_096)
        for channel in 0..<2 {
            let expected = a[channel] + b[channel]
            #expect(firstDifference(out[channel][4_096..<total], expected[4_096...]) == nil, "channel \(channel)")
            #expect(out[channel][total...].allSatisfy { $0 == 0 })
        }
    }

    @Test func aGainIsOneMultiplyPerSample() throws {
        let rate = 44_100.0
        let m = multiplier(-6.02)
        let a = signal(frames: 22_050, channels: 2, seed: 0.21)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([a], rate: rate, factors: [m]), from: 0)
        engine.settle()
        let out = try renderAll(engine, frames: a[0].count)
        for channel in 0..<2 {
            // vDSP's single-precision multiply rounds as Swift's `*` does (IEEE); the inputs are
            // multiples of 1/32768, nowhere near a denormal
            let expected = a[channel].map { $0 * m }
            #expect(firstDifference(out[channel][4_096...], expected[4_096...]) == nil, "channel \(channel) at \(m)")
            let ramp = (0..<4_096).map { abs(out[channel][$0] - expected[$0]) }.max() ?? 0
            print("gain \(m): largest difference in the first 4096 frames (the start ramp, if any): \(ramp)")
        }
    }

    @Test func anAlbumAtOneGainJoinsExactly() throws {
        let rate = 44_100.0
        let m = multiplier(-3.5)
        let songs = [signal(frames: 13_230, channels: 2, seed: 0.31), signal(frames: 8_820, channels: 2, seed: 0.41),
                     signal(frames: 11_025, channels: 2, seed: 0.51)]
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked(songs, rate: rate, factors: [m, m, m]), from: 0)
        engine.settle()
        let total = songs.reduce(0) { $0 + $1[0].count }
        let out = try renderAll(engine, frames: total + 1_024)
        for channel in 0..<2 {
            let expected = (songs[0][channel] + songs[1][channel] + songs[2][channel]).map { $0 * m }
            #expect(firstDifference(out[channel][4_096..<total], expected[4_096...]) == nil,
                    "channel \(channel): the joins at 13230 and 22050 are the album's, scaled")
        }
    }

    // The layout of aShortSongInAnotherFormatPlaysBetweenNotOver: the third song's first buffer is
    // decoded, refused (its lane still holds the first song) and parked, then scheduled later - the
    // same buffer, multiplied once when it was read.
    @Test func aParkedBufferIsMultipliedOnce() throws {
        let rate = 44_100.0
        let (m1, m2, m3) = (multiplier(-2), multiplier(-4), multiplier(-6.02))
        let first = signal(frames: 22_050, channels: 2, seed: 0.16)
        let between = signal(frames: 48_000, channels: 2, seed: 0.26)
        let third = signal(frames: 22_050, channels: 2, seed: 0.36)
        let engine = try offlineEngine(rate: rate, channels: 2)
        var parked = false
        engine.trace = { line in if line.contains("entry 2 parked") { parked = true } }
        engine.play([entry(first, rate: rate, key: 0, id: "a", factor: m1), entry(between, rate: 96_000, key: 1, id: "b", factor: m2),
                     entry(third, rate: rate, key: 2, id: "c", factor: m3)], from: 0)
        engine.settle()
        let left = try render(engine, frames: 66_150 + 8_192)
        let margin = 4_096
        #expect(parked, "the third song's first buffer was parked, as the layout means it to be")
        #expect(firstDifference(left[margin..<22_050], first[0][margin...].map { $0 * m1 }) == nil, "the first song at its gain")
        let expected = third[0].map { $0 * m3 }
        #expect(firstDifference(left[(44_100 + margin)..<66_150], expected[margin...]) == nil,
                "the third song at m3 once (twice would be m3 x m3)")
    }

    @Test func aGainStaysThroughAPauseAndANewRoute() throws {
        let rate = 48_000.0
        let m = multiplier(-9.1)
        let song = signal(frames: 192_000, channels: 2, seed: 0.66)
        let scaled = song[0].map { $0 * m }
        let engine = try offlineEngine(rate: rate, channels: 2)
        // the entry's gain is the app's, decided once: every open (the pause's, the route's) wraps with it
        engine.play(tracksFromWhereAsked([song], rate: rate, factors: [m]), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        let paused = try #require(engine.position())
        engine.pause()
        engine.resume()
        engine.settle()
        var out = try engine.renderOffline(24_000)
        var from = Int((paused.seconds * rate).rounded())
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], scaled[(from + 8_192)..<(from + 9_192)]) == nil,
                "after the pause, on from \(from) at the same gain")
        let before = try #require(engine.position())
        engine.systemStopped(change: true)
        engine.settle()
        out = try engine.renderOffline(24_000)
        from = Int((before.seconds * rate).rounded())
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], scaled[(from + 8_192)..<(from + 9_192)]) == nil,
                "after the new route, on from \(from) at the same gain")
    }

    @Test func aPositiveGainIsNotClipped() throws {
        let rate = 44_100.0
        let m = multiplier(6.02)
        let song = signal(frames: 22_050, channels: 2, seed: 0.77)
        let peak = song.flatMap { $0 }.map(abs).max() ?? 0
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([song], rate: rate, factors: [m]), from: 0)
        engine.settle()
        let out = try renderAll(engine, frames: song[0].count)
        #expect(firstDifference(out[0][4_096...], song[0][4_096...].map { $0 * m }) == nil)
        let outPeak = out.flatMap { $0 }.map(abs).max() ?? 0
        print("a +6.02 dB gain: the song's peak \(peak) comes out at \(outPeak)")
        #expect(outPeak > peak * 1.9 && outPeak <= 1, "brought up, not held at the old peak, and under full scale")
    }

    // Plan R10: the one place a sample can pass full scale is a lane's rate converter ringing on a song
    // brought up until its sample peak touches 1.0 - an inter-sample peak. Measured and printed: the
    // bounds only catch a conversion that is broken outright.
    @Test func theConverterOvershootMeasured() throws {
        // full-scale samples (1, 1, -1, -1...) of an 11025 Hz tone phased so its true peaks fall between
        // them: the band-limited wave peaks at 1.414 (+3 dB)
        let rate = 44_100.0
        let one = (0..<44_100).map { Float(2.0.squareRoot() * sin(2 * Double.pi * 11_025 * Double($0) / rate + Double.pi / 4)) }
        let engine = try offlineEngine(rate: 48_000, channels: 2)
        engine.play(tracksFromWhereAsked([[one, one]], rate: rate), from: 0)
        engine.settle()
        let out = try renderAll(engine, frames: 48_000)
        let middle = out[0][4_800..<43_200]
        let largest = middle.map(abs).max() ?? 0
        print("an inter-sample peak through the 44.1 -> 48 kHz lane: samples at \(one.map(abs).max() ?? 0), out at \(largest) (\(String(format: "%+.2f", 20 * log10(Double(largest)))) dBFS)")
        #expect(largest > 0.9 && largest < 2, "a conversion that kept the tone")
    }
}
#endif
