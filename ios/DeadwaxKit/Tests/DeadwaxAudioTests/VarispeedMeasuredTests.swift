#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The speed (notes/ios-specs/turntable.md 5.2): an AVAudioUnitVarispeed per lane, out of the sound's path at 1x. These
// are 5.3's eight measurements, the gate the fader is built on - each prints its numbers, which go to James before
// the fader's view is written (notes/ios.md "The speed, measured").

/// An offline engine at `rate`, `ahead` seconds scheduled ahead (all of it, by default) in 0.1 s buffers, hearing
/// `latency` behind the render, its varispeed at 1x as given (the app's: out of the path).
func speedEngine(rate: Double = 48_000, atOne: PlaybackEngine.VarispeedAtOne = .outOfPath,
                 latency: Double = 0, ahead: Double = 60) throws -> PlaybackEngine {
    var settings = PlaybackEngine.Settings()
    settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)
    settings.aheadSeconds = ahead
    settings.startSeconds = 0
    settings.bufferSeconds = 0.1
    settings.changeSettleSeconds = 0
    settings.varispeedAtOne = atOne
    let engine = try PlaybackEngine(settings: settings)
    engine.latency = { latency }
    engine.scheduleLag = testScheduleLag
    return engine
}

/// A sine of `cycles` a frame fitted to `x` over `range` (least squares, its phase and amplitude free): its amplitude,
/// what else is there in dB under it (all of it, and its largest sample), and where that largest is.
struct ToneFit {
    var amplitude: Double
    var snr: Double
    var worst: Double
    var worstAt: Int
}

func fitTone(_ x: [Float], cycles: Double, in range: Range<Int>) -> ToneFit {
    var ss = 0.0, cc = 0.0, sc = 0.0, xs = 0.0, xc = 0.0
    for i in range {
        let w = 2 * Double.pi * cycles * Double(i)
        let s = sin(w), c = cos(w), v = Double(x[i])
        ss += s * s
        cc += c * c
        sc += s * c
        xs += v * s
        xc += v * c
    }
    let det = ss * cc - sc * sc
    let a = (xs * cc - xc * sc) / det
    let b = (xc * ss - xs * sc) / det
    var signal = 0.0, residual = 0.0, worst = 0.0, worstAt = range.lowerBound
    for i in range {
        let w = 2 * Double.pi * cycles * Double(i)
        let fit = a * sin(w) + b * cos(w)
        let left = Double(x[i]) - fit
        signal += fit * fit
        residual += left * left
        if abs(left) > worst {
            worst = abs(left)
            worstAt = i
        }
    }
    let amplitude = (a * a + b * b).squareRoot()
    return ToneFit(amplitude: amplitude, snr: 10 * log10(signal / max(residual, 1e-30)),
                   worst: 20 * log10(max(worst, 1e-15) / max(amplitude, 1e-15)), worstAt: worstAt)
}

/// A sine at `frequency` Hz, `seconds` long at `rate`, from `phase` seconds into it; `level` its amplitude.
func sine(_ frequency: Double, rate: Double, seconds: Double, level: Double = 0.5, from start: Double = 0) -> [Float] {
    (0..<Int((rate * seconds).rounded())).map { (n: Int) -> Float in
        Float(level * sin(2 * Double.pi * frequency * (start + Double(n) / rate)))
    }
}

/// Clicks: 0.5 at every `every`-th frame from frame `first`, silence between.
func clicks(frames: Int, every: Int, first: Int) -> [Float] {
    (0..<frames).map { (n: Int) -> Float in n >= first && (n - first) % every == 0 ? 0.5 : 0 }
}

/// Where each click is in a render: the largest sample of each burst over `threshold`, placed between frames by the
/// parabola through it and its neighbours.
func clickPlaces(_ x: [Float], threshold: Float = 0.1, apart: Int) -> [Double] {
    var places: [Double] = []
    var i = 0
    while i < x.count {
        guard abs(x[i]) > threshold else {
            i += 1
            continue
        }
        var best = i
        for j in i..<min(i + apart / 2, x.count) where abs(x[j]) > abs(x[best]) { best = j }
        var place = Double(best)
        if best > 0, best + 1 < x.count {
            let l = Double(abs(x[best - 1])), m = Double(abs(x[best])), r = Double(abs(x[best + 1]))
            let bend = l - 2 * m + r
            if bend != 0 { place += 0.5 * (l - r) / bend }
        }
        places.append(place)
        i = best + apart / 2
    }
    return places
}

/// The largest step between neighbouring samples over `range`.
func largestStep(_ x: [Float], in range: Range<Int>) -> (step: Float, at: Int) {
    var step: Float = 0, at = range.lowerBound
    for i in range.dropFirst() where abs(x[i] - x[i - 1]) > step {
        step = abs(x[i] - x[i - 1])
        at = i
    }
    return (step, at)
}

func db(_ x: Double) -> String { String(format: "%.1f dB", x) }

/// Every channel of a render, `piece` frames at a time, the buffer completions handled between - `before` called with
/// the frames rendered so far ahead of each piece.
func renderPieces(_ engine: PlaybackEngine, frames: Int, piece: Int, before: ((Int) -> Void)? = nil,
                  sourceLocation: SourceLocation = #_sourceLocation) throws -> [[Float]] {
    var out: [[Float]] = []
    var done = 0
    while done < frames {
        before?(done)
        let rendered = try engine.renderOffline(AVAudioFrameCount(min(piece, frames - done)))
        if out.isEmpty { out = Array(repeating: [], count: Int(rendered.format.channelCount)) }
        for channel in out.indices { out[channel] += samples(rendered, channel: channel) }
        done += Int(rendered.frameLength)
        try completionsHandled(engine, sourceLocation: sourceLocation)
    }
    return out
}

/// The lag (0 to 199 frames) at which `got` is most nearly `expected` over a 4,800-frame stretch from `at`.
func bestLag(_ got: [Float], _ expected: [Float], at: Int) -> Int {
    var best = (lag: 0, largest: Float.infinity)
    for lag in 0..<200 {
        var largest: Float = 0
        for i in at..<(at + 4_800) { largest = max(largest, abs(got[i + lag] - expected[i])) }
        if largest < best.largest { best = (lag, largest) }
    }
    return best.lag
}

@Suite(.serialized) struct VarispeedMeasuredTests {
    /// 5.3 item 1: 1x is today's sound. A 30 s file of seeded noise and a 20 Hz-20 kHz sweep, as a 48 kHz FLAC, renders
    /// as its own decoded samples, every bit, with the varispeed out of the path - the app's. Bypassed in the path,
    /// every sample comes out exact but 47 frames late; in the path at rate 1, 48 frames late and filtered. So the
    /// varispeed is out of the path at 1x; the render suites were run each way too (notes/ios.md "The speed, measured").
    @Test func oneXIsTheSongBitForBit() throws {
        let rate = 48_000.0
        let song = noiseAndSweep(seconds: 30, rate: rate)
        guard let url = flacFile(song, rate: rate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try decodeAll(try FileSource(url: url), maxFrames: 48_000)
        var right: [Float] = []
        let rightSource = try FileSource(url: url)
        while case .frames(let buffer) = try rightSource.read(maxFrames: 48_000) { right += samples(buffer, channel: 1) }
        let frames = decoded.count
        func rendered(_ atOne: PlaybackEngine.VarispeedAtOne) throws -> [[Float]] {
            let engine = try speedEngine(rate: rate, atOne: atOne)
            engine.play([EngineTrack(key: 0, audio: "noise", song: Song(id: "noise")) { start in
                try FileSource(url: url, start: start)
            }], from: 0)
            engine.settle()
            return try renderChannels(engine, frames: frames + 4_096)
        }
        let expected = [decoded + [Float](repeating: 0, count: 4_096), right + [Float](repeating: 0, count: 4_096)]

        let out = try rendered(.outOfPath)
        let exact = firstBitDifference(out, expected, in: 0..<(frames + 4_096))
        print("speed 1x, the varispeed out of the path: \(frames) frames of noise and sweep against the file's own "
              + "samples - \(exact ?? "the same, bit for bit, from the first frame")")
        #expect(exact == nil)

        // bypassed: the same samples, late
        let bypassed = try rendered(.bypassed)
        let late = bestLag(bypassed[0], decoded, at: 96_000)
        var bypassedExact = true
        for channel in 0..<2 {
            for i in 4_096..<frames where bypassed[channel][i + late].bitPattern != expected[channel][i].bitPattern {
                bypassedExact = false
                break
            }
        }
        print("speed 1x, the varispeed in the path and bypassed: \(late) frames late, and "
              + (bypassedExact ? "every sample exact after that" : "its samples not the song's even then"))
        #expect(late != 0, "bypassed is the song as it was, frame for frame: if so, it could be the way 1x is kept")

        // at rate 1: late and filtered
        let atOne = try rendered(.atRateOne)
        let lag = bestLag(atOne[0], decoded, at: 96_000)
        var largest: Float = 0
        for i in 4_096..<frames { largest = max(largest, abs(atOne[0][i + lag] - decoded[i])) }
        print("speed 1x, the varispeed in the path at rate 1: \(lag) frames late, and its samples differ by up to "
              + "\(largest) (\(db(20 * log10(Double(max(largest, 1e-12)))))) from the song's")
        #expect(lag != 0 || largest > 0, "at rate 1 the varispeed is the song as it was: if so, look again")
    }

    /// 5.3 item 2: its quality. A -6 dBFS tone at 0.25x, 0.5x, 1.5x and 2x: what is not the tone, against the lane
    /// converter's own bar (EngineRenderTests' theRateConversionMeasured: 1 kHz more than 60 dB above everything else,
    /// a 30 kHz tone's alias under -40 dB). A 20 kHz tone at each speed too: above 24 kHz at 1.5x and 2x (where it
    /// would fold back), and imaged at 0.25x and 0.5x.
    @Test func theProductsAtEachSpeed() throws {
        let rate = 48_000.0
        func render(_ song: [Float], speed: Double) throws -> [Float] {
            let engine = try speedEngine(rate: rate)
            engine.setSpeed(speed)
            engine.play([memoryTrack([song, song], rate: rate, key: 0)], from: 0)
            engine.settle()
            return try renderChannels(engine, frames: 9_600 + 24_000 + 4_096)[0]
        }
        let window = 9_600..<(9_600 + 24_000)
        let reference = 0.5 / 2.0.squareRoot()
        var lines: [String] = []
        for speed in [0.25, 0.5, 1.5, 2] {
            let seconds = 0.5 + 38_000 * speed / rate
            let out = try render(sine(1_000, rate: rate, seconds: seconds), speed: speed)
            let fit = fitTone(out, cycles: 1_000 * speed / rate, in: window)
            var line = "speed \(speed)x: 1 kHz comes out at \(Int(1_000 * speed)) Hz, \(db(fit.snr)) above everything else "
                + "(its level \(db(20 * log10(fit.amplitude / 0.5))))"
            #expect(fit.snr > 60, "\(line)")
            #expect(abs(20 * log10(fit.amplitude / 0.5)) < 0.1, "\(line)")
            let high = try render(sine(20_000, rate: rate, seconds: seconds), speed: speed)
            if 20_000 * speed > rate / 2 {
                let rms = sqrt(window.map { Double(high[$0]) * Double(high[$0]) }.reduce(0, +) / Double(window.count))
                let left = 20 * log10(max(rms, 1e-12) / reference)
                line += "; 20 kHz, at \(Int(20_000 * speed)) Hz past the output's 24 kHz, is left at \(db(left))"
                #expect(left < -40, "\(line)")
            } else {
                let highFit = fitTone(high, cycles: 20_000 * speed / rate, in: window)
                line += "; 20 kHz comes out at \(Int(20_000 * speed)) Hz, \(db(highFit.snr)) above everything else "
                    + "(its level \(db(20 * log10(highFit.amplitude / 0.5))))"
            }
            if speed == 2 {
                // the bar's own 30 kHz: 15 kHz at 2x
                let alias = try render(sine(15_000, rate: rate, seconds: seconds), speed: speed)
                let rms = sqrt(window.map { Double(alias[$0]) * Double(alias[$0]) }.reduce(0, +) / Double(window.count))
                let left = 20 * log10(max(rms, 1e-12) / reference)
                line += "; 15 kHz, at 30 kHz, is left at \(db(left))"
                #expect(left < -40, "\(line)")
            }
            lines.append(line)
        }
        print(lines.joined(separator: "\n"))
    }

    /// 5.3 items 3 and 8: the position at speed, and the varispeed's own delay. Clicks every 10 ms of the song played at
    /// 1.5x (and at 0.25x, 1x through the varispeed, 2x): the position read after each 480 frames rendered, against
    /// where the clicks are heard - within one output frame, with the output's latency (0.1 s) counted in the song's
    /// time and without. The delay is what the clicks say the node's frame is ahead of the ear.
    @Test func thePositionIsTheClicksHeard() throws {
        let rate = 48_000.0, every = 480
        var lines: [String] = []
        let cases: [(speed: Double, latency: Double, atOne: PlaybackEngine.VarispeedAtOne)] = [
            (1.5, 0, .outOfPath), (1.5, 0.1, .outOfPath), (0.25, 0, .outOfPath), (2, 0.1, .outOfPath), (1, 0, .atRateOne),
        ]
        for (speed, latency, atOne) in cases {
            let frames = 96_000
            let song = clicks(frames: Int(Double(frames) * speed) + 48_000, every: every, first: 9_600)
            let engine = try speedEngine(rate: rate, atOne: atOne, latency: latency)
            engine.setSpeed(speed)
            engine.play([memoryTrack([song, song], rate: rate, key: 0)], from: 0)
            engine.settle()
            var readings: [(rendered: Int, frame: Double)] = []
            let out = try renderPieces(engine, frames: frames, piece: 480) { (done: Int) -> Void in
                if done > 0, let at = engine.position() { readings.append((done, at.seconds * rate)) }
            }[0]
            // where each click is heard: output frame -> song frame
            let places = clickPlaces(out, apart: Int(Double(every) / speed))
            var heard: [(out: Double, song: Double)] = []
            for index in places.indices { heard.append((places[index], Double(9_600 + index * every))) }
            try #require(heard.count > 10, "the clicks came out: \(heard.count)")
            // the ear `latency` behind the render: the song frame heard at output frame K is the one rendered at K - latency
            let behind = latency * rate
            var worst = 0.0, worstAt = 0, delays: [Double] = []
            for reading in readings {
                let at = Double(reading.rendered) - behind
                guard let i = heard.firstIndex(where: { $0.out > at }), i > 0 else { continue }
                let (a, b) = (heard[i - 1], heard[i])
                let song = a.song + (at - a.out) * (b.song - a.song) / (b.out - a.out)
                let error = (reading.frame - song) / speed // in output frames
                delays.append(song - reading.frame + Double(PlaybackEngine.varispeedDelayFrames))
                if abs(error) > abs(worst) {
                    worst = error
                    worstAt = reading.rendered
                }
            }
            try #require(delays.count > 10)
            let delay = delays.reduce(0, +) / Double(delays.count)
            let line = "speed \(speed)x\(atOne == .atRateOne ? " (the varispeed in the path)" : "")"
                + (latency > 0 ? ", the output's latency \(latency) s" : "")
                + ": the position against the clicks heard, at \(delays.count) readings - out by at most "
                + String(format: "%.2f", worst) + " output frames (at \(worstAt)); the varispeed's delay "
                + String(format: "%.2f", delay) + " of the node's frames"
            #expect(abs(worst) <= 1, "\(line)")
            #expect(abs(delay - Double(PlaybackEngine.varispeedDelayFrames)) <= max(speed, 1), "\(line)")
            lines.append(line)
        }
        print(lines.joined(separator: "\n"))
    }

    /// 5.3 item 4: joins at speed. Test sounds 9 and 10 (440 Hz at -12 dBFS, 44.1 kHz, cut near a peak - one lane, the
    /// two back to back) at 2x and 0.25x (and 1x, to compare): a sine fitted across the join, what is not the sine within
    /// 50 ms of it held to -50 dB at its largest. And a change of lane at speed, with the phone's buffering (2 s ahead, 1 s
    /// before a start, 4,096-frame renders - a locked phone's): a 441 Hz tone, 3 s of it at 44.1 kHz and the next 0.5 s
    /// at 96 kHz, cut at a crossing on a whole frame of the output - the second lane made and put through its varispeed
    /// while the first plays, and started at the sample the first ends at, in its own node's time. Each lane's
    /// converter rings at the cut (it takes its part for a song on its own: notes/ios.md "The speed, measured"), so the
    /// bar is 1x's own join: no worse at speed, 4x (the reach shortest) among them.
    @Test func joinsAtSpeedAreUnbroken() throws {
        let rate = 48_000.0
        var lines: [String] = []
        func rendered(_ tracks: [EngineTrack], speed: Double, seconds: Double,
                      phone: Bool = false) throws -> (out: [Float], trace: TraceLines) {
            let engine: PlaybackEngine
            if phone {
                engine = try phoneLikeEngine(rate: rate)
            } else {
                engine = try speedEngine(rate: rate)
            }
            let trace = TraceLines()
            engine.trace = trace.add
            engine.setSpeed(speed)
            engine.play(tracks, from: 0)
            engine.settle()
            return (try renderChannels(engine, frames: Int(seconds / speed * rate) + 4_096)[0], trace)
        }
        // test sounds 9 and 10
        let cut = 22_050 + 25 // a quarter of 440 Hz's period past 0.5 s: near a peak
        let whole = sine(440, rate: 44_100, seconds: 1, level: 0.25)
        let first = Array(whole[..<cut]), second = Array(whole[cut...])
        for speed in [1.0, 2.0, 0.25] {
            let tracks = [memoryTrack([first, first], rate: 44_100, key: 0), memoryTrack([second, second], rate: 44_100, key: 1)]
            let (out, trace) = try rendered(tracks, speed: speed, seconds: 0.95)
            let join = Int(Double(cut) / 44_100 * rate / speed)
            let length = Int(0.95 / speed * rate)
            let all = 4_096..<(length - 1_024)
            let near = max(join - 2_400, 4_096)..<min(join + 2_400, length - 1_024)
            let fit = fitTone(out, cycles: 440 * speed / rate, in: all)
            let nearFit = fitTone(out, cycles: 440 * speed / rate, in: near)
            let line = "join at \(speed)x, one tone cut in two (one lane): 440 Hz at \(Int(440 * speed)) Hz across "
                + "\(all.count) frames, \(db(fit.snr)) above everything else, its largest stray sample \(db(fit.worst)); "
                + "within 50 ms of the join (near \(join)) \(db(nearFit.snr)), its largest \(db(nearFit.worst))"
            #expect(fit.snr > 60 && fit.worst < -50, "\(line)\n\(trace)")
            #expect(nearFit.snr > 60 && nearFit.worst < -50, "\(line)")
            lines.append(line)
        }
        // a change of lane, with the phone's buffering
        let firstPart = sine(441, rate: 44_100, seconds: 3, level: 0.25)
        let secondPart = sine(441, rate: 96_000, seconds: 0.5, level: 0.25, from: 3)
        let lanes = [memoryTrack([firstPart, firstPart], rate: 44_100, key: 0),
                     memoryTrack([secondPart, secondPart], rate: 96_000, key: 1)]
        var atOne = 0.0
        for speed in [1.0, 2.0, 4.0, 0.25] {
            let (out, trace) = try rendered(lanes, speed: speed, seconds: 3.45, phone: true)
            let join = Int(3 * rate / speed)
            let near = (join - 2_400)..<(join + 2_400)
            let away = (join - 12_000)..<(join - 2_400)
            let nearFit = fitTone(out, cycles: 441 * speed / rate, in: near)
            let awayFit = fitTone(out, cycles: 441 * speed / rate, in: away)
            if speed == 1 { atOne = nearFit.worst }
            let line = "join at \(speed)x, 44.1 kHz into 96 kHz (a change of lane, the phone's buffering): 441 Hz at "
                + "\(Int(441 * speed)) Hz, within 50 ms of the join (at \(join)) \(db(nearFit.snr)) above everything else, its "
                + "largest stray sample \(db(nearFit.worst)) (at \(nearFit.worstAt)); before it \(db(awayFit.snr)), its "
                + "largest \(db(awayFit.worst))"
            #expect(nearFit.worst <= atOne + 3, "\(line): worse than the same join at 1x (\(db(atOne)))\n\(trace)")
            #expect(awayFit.snr > 60, "\(line)")
            lines.append(line)
        }
        // the new lane can be started only once a render has pulled its node through its varispeed (its time begins
        // then): with less ahead than a render, the first lane runs out first and the second starts from silence after
        // it - late, never over it. 0.3 s ahead at 2x is 7,200 frames: under two 4,096-frame renders
        do {
            let engine = try speedEngine(rate: rate, ahead: 0.3)
            engine.setSpeed(2)
            let short = [memoryTrack([Array(firstPart[..<22_050]), Array(firstPart[..<22_050])], rate: 44_100, key: 0),
                         memoryTrack([Array(secondPart), Array(secondPart)], rate: 96_000, key: 1)]
            engine.play(short, from: 0)
            engine.settle()
            let out = try renderChannels(engine, frames: 24_000)[0]
            // the longest run under 0.01: an 882 Hz tone at 0.25 steps 0.029 a frame, so under it for a frame at a crossing
            var gap = 0, run = 0, gapAt = 0
            for i in 8_000..<20_000 {
                run = abs(out[i]) < 0.01 ? run + 1 : 0
                if run > gap {
                    gap = run
                    gapAt = i - run + 1
                }
            }
            let line = "a change of lane at 2x with 0.3 s ahead and 4,096-frame renders: \(gap) frames of silence from \(gapAt) "
                + "(the first lane ends at 12000)"
            #expect(gapAt + gap >= 12_000 && (gap <= 2 || gapAt >= 11_990), "\(line): over the first lane's end")
            lines.append(line)
        }
        print(lines.joined(separator: "\n"))
    }

    /// 5.3 item 5: a speed changed while playing - 1.5x, then 0.75x, then 2x, then 0.6x, a second apart - no click (no
    /// step between neighbouring samples larger than the faster tone's own largest) and no jump in the position (each
    /// 480 frames rendered moves it 480 times a speed between the old and the new).
    @Test func aSpeedChangedWhilePlaying() throws {
        let rate = 48_000.0
        let song = sine(440, rate: rate, seconds: 6, level: 0.5)
        let engine = try speedEngine(rate: rate)
        engine.setSpeed(1.5)
        engine.play([memoryTrack([song, song], rate: rate, key: 0)], from: 0)
        engine.settle()
        let speeds: [(at: Int, speed: Double)] = [(0, 1.5), (48_000, 0.75), (96_000, 2), (144_000, 0.6)]
        var readings: [(rendered: Int, frame: Double, speed: Double)] = []
        var now = 1.5
        let out = try renderPieces(engine, frames: 192_000, piece: 480) { (done: Int) -> Void in
            if let at = engine.position(), done > 0 { readings.append((done, at.seconds * rate, now)) }
            if let change = speeds.first(where: { $0.at == done && done > 0 }) {
                engine.setSpeed(change.speed)
                now = change.speed
            }
        }[0]
        var lines: [String] = []
        for (index, change) in speeds.enumerated() where index > 0 {
            let before = speeds[index - 1].speed
            let fastest = max(before, change.speed)
            let steady = 0.5 * 2 * sin(Double.pi * 440 * fastest / rate) // a sine's largest step at the faster speed
            let around = largestStep(out, in: (change.at - 2_400)..<(change.at + 2_400))
            let line = "\(before)x to \(change.speed)x at \(change.at): the largest step within 50 ms "
                + String(format: "%.5f", around.step) + " (at \(around.at)), the faster tone's own " + String(format: "%.5f", steady)
            #expect(Double(around.step) <= steady * 1.02, "\(line)")
            lines.append(line)
        }
        var jumps = 0
        for (a, b) in zip(readings, readings.dropFirst()) {
            let moved = (b.frame - a.frame) / Double(b.rendered - a.rendered)
            let low = min(a.speed, b.speed), high = max(a.speed, b.speed)
            if moved < low - 2.0 / 480 || moved > high + 2.0 / 480 {
                jumps += 1
                lines.append("the position moved \(moved) a frame from \(a.rendered) to \(b.rendered), the speed \(a.speed)x-\(b.speed)x")
            }
        }
        print((lines + ["the position read at \(readings.count) points across four speeds: \(jumps) jumps"]).joined(separator: "\n"))
        #expect(jumps == 0)
    }

    /// 5.3 item 7: crossing 1x while playing, both ways. A drag from 0.9x up through 1x to 1.1x and back, a step of 0.01
    /// every 10 ms: the varispeed stays in the path at 1 (at rate 1, never bypassed - this engine takes it out of the path
    /// at 1x, which can't be done to a node playing), so no click and no gap. Then a pause and play at 1x: out of the
    /// path again, the song's own samples. And a song begun at 1x, the speed then moved off it: the lane begun again in
    /// the path, from the frame the render reached - the gap that leaves, measured.
    @Test func crossingOneX() throws {
        let rate = 48_000.0
        let song = sine(440, rate: rate, seconds: 8, level: 0.5)
        var lines: [String] = []
        do {
            let engine = try speedEngine(rate: rate)
            engine.setSpeed(0.9)
            engine.play([memoryTrack([song, song], rate: rate, key: 0)], from: 0)
            engine.settle()
            let up = (0...20).map { 0.9 + Double($0) / 100 }
            let drag = up + up.reversed().dropFirst()
            let start = 24_000
            let out = try renderPieces(engine, frames: start + drag.count * 480 + 24_000, piece: 480) { (done: Int) -> Void in
                let step = (done - start) / 480
                if done >= start, step < drag.count { engine.setSpeed(drag[step]) }
            }[0]
            let steady = 0.5 * 2 * sin(Double.pi * 440 * 1.1 / rate)
            let around = largestStep(out, in: (start - 2_400)..<(start + drag.count * 480 + 2_400))
            var quietest: Float = .infinity
            for block in stride(from: start - 2_400, to: start + drag.count * 480 + 2_400, by: 480) {
                quietest = min(quietest, out[block..<(block + 480)].reduce(Float(0)) { max($0, abs($1)) })
            }
            let line = "a drag 0.9x-1.1x-0.9x through 1x: the largest step " + String(format: "%.5f", around.step)
                + " (at \(around.at)), the 1.1x tone's own " + String(format: "%.5f", steady)
                + "; the quietest 10 ms peaks at " + String(format: "%.4f", quietest) + " of the tone's 0.5"
            #expect(Double(around.step) <= steady * 1.02, "\(line)")
            #expect(quietest > 0.49, "\(line)")
            lines.append(line)
            // back at 1x, then a pause and play: the lane begun afresh, the varispeed out of the path
            engine.setSpeed(1)
            engine.settle()
            engine.pause()
            engine.settle()
            let held = try #require(engine.position())
            engine.resume()
            engine.settle()
            let after = try renderChannels(engine, frames: 24_000)[0]
            let from = Int((held.seconds * rate).rounded())
            let exact = firstDifference(after[4_096..<24_000], song[(from + 4_096)..<(from + 24_000)])
            let words = "after the drag, at 1x, a pause and play: \(exact ?? "the song's own samples again, bit for bit")"
            #expect(exact == nil, "\(words)")
            lines.append(words)
        }
        do {
            // begun at 1x (out of the path), then 1.01x: begun again through the varispeed
            let engine = try speedEngine(rate: rate)
            engine.play([memoryTrack([song, song], rate: rate, key: 0)], from: 0)
            engine.settle()
            let start = 48_000
            var before: Double?, afterwards: Double?
            let out = try renderPieces(engine, frames: start + 48_000, piece: 480) { (done: Int) -> Void in
                if done == start {
                    before = engine.position()?.seconds
                    engine.setSpeed(1.01)
                    engine.settle()
                    afterwards = engine.position()?.seconds
                }
            }[0]
            let exactBefore = firstDifference(out[4_096..<start], song[4_096..<start])
            // the gap: the longest run of near silence where the tone was (a 440 Hz sine at 0.5 is under 0.001 for one
            // frame at most, at a crossing)
            var gap = 0, run = 0, gapAt = start
            for i in (start - 480)..<(start + 4_800) {
                run = abs(out[i]) < 0.001 ? run + 1 : 0
                if run > gap {
                    gap = run
                    gapAt = i - run + 1
                }
            }
            let fit = fitTone(out, cycles: 440 * 1.01 / rate, in: (start + 4_800)..<(start + 48_000))
            let line = "begun at 1x, then 1.01x at \(start): before it, \(exactBefore ?? "the song's own samples"); the position "
                + "\(before.map { String(format: "%.5f", $0) } ?? "-") s before the change and "
                + "\(afterwards.map { String(format: "%.5f", $0) } ?? "-") s after it; the longest quiet \(gap) frames, from "
                + "\(gapAt - start) after the change; then a 444.4 Hz tone \(db(fit.snr)) above everything else"
            #expect(exactBefore == nil, "\(line)")
            #expect(before != nil && before == afterwards, "\(line)")
            #expect(fit.snr > 60, "\(line)")
            lines.append(line)
        }
        print(lines.joined(separator: "\n"))
    }

    /// The speed as the engine takes it: 0.25 to 4, anything else held to the nearer end (and not a number, 1).
    @Test func theSpeedIsHeldToItsRange() throws {
        let engine = try speedEngine()
        #expect(engine.speed == 1)
        engine.setSpeed(0.1)
        #expect(engine.speed == 0.25)
        engine.setSpeed(9)
        #expect(engine.speed == 4)
        engine.setSpeed(.nan)
        #expect(engine.speed == 1)
        engine.setSpeed(1.25)
        #expect(engine.speed == 1.25)
    }
}

/// 5.3 item 6: its cost - render time at 2x on a 192 kHz file, against 1x. Run again in the release build (ios.yml), which
/// bounds it; a debug build prints.
@Suite(.serialized) struct VarispeedCostTests {
    @Test func theCostAtTwoXOnA192kFile() throws {
        let fileRate = 192_000.0, rate = 48_000.0
        let song = noiseAndSweep(seconds: 12, rate: fileRate)
        guard let url = flacFile(song, rate: fileRate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        func measured(_ speed: Double) throws -> (block: Double, scheduling: Double) {
            let engine = try speedEngine(rate: rate)
            engine.setSpeed(speed)
            let began = Date()
            engine.play([EngineTrack(key: 0, audio: "noise", song: Song(id: "noise")) { start in
                try FileSource(url: url, start: start)
            }], from: 0)
            engine.settle()
            _ = try engine.renderOffline(4_096) // the start, and its settle
            let scheduling = Date().timeIntervalSince(began)
            var blocks: [Double] = []
            for _ in 0..<Int(5 * rate / 4_096) {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try engine.renderOffline(4_096)
                blocks.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
                try completionsHandled(engine)
            }
            return (median(blocks), scheduling)
        }
        let blockSeconds = 4_096 / rate
        let plain = try measured(1)
        let fast = try measured(2)
        let quarter = try measured(0.25)
        func share(_ x: Double) -> String { String(format: "%.2f%%", x / blockSeconds * 100) }
        print("speed's cost, a 192 kHz file to a 48 kHz output: a block of 4,096 frames (\(String(format: "%.1f", blockSeconds * 1_000)) ms) "
              + "renders in \(share(plain.block)) of its time at 1x (no varispeed), \(share(fast.block)) at 2x, "
              + "\(share(quarter.block)) at 0.25x (medians); the whole 12 s file decoded, converted and scheduled in "
              + String(format: "%.2f s at 1x, %.2f s at 2x", plain.scheduling, fast.scheduling))
        #if !DEBUG
        #expect(fast.block / blockSeconds <= 0.15, "the render at 2x takes \(share(fast.block)) of the block")
        #endif
    }
}
#endif
