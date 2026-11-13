#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAllocHook
import CAudioRing
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// 1.7 tests 5, 8, 9 and 10 (notes/ios-specs/eq.md 1.5, 1.10): the unit's render block called directly, as the AU
// framework calls it - the Objective-C block its `internalRenderBlock` hands out, with an Objective-C pull block - and
// (the review) test 5 again through AVAudioEngine's own real-time manual rendering block, which allocates nothing of
// its own on the rendering thread (measured with no unit), so the framework's bridge to the unit, its own pull block
// and its ask for the render block are in the count too. Meant for the release build, a step of its own on ios.yml's
// macOS job: `swift test -c release --filter EQRealTimeTests`. The bounds hold only there; a debug build prints them.

/// The pull block as the framework hands it, and the render block as the framework calls it: Objective-C blocks,
/// so a call from here goes in exactly as the framework's does.
typealias RawPull = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>, UnsafePointer<AudioTimeStamp>,
                                        AUAudioFrameCount, Int, UnsafeMutablePointer<AudioBufferList>) -> AUAudioUnitStatus
typealias RawRender = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>, UnsafePointer<AudioTimeStamp>,
                                          AUAudioFrameCount, Int, UnsafeMutablePointer<AudioBufferList>,
                                          UnsafePointer<AURenderEvent>?, RawPull?) -> AUAudioUnitStatus

/// What the pull block reads: a loop of input samples, and how often it was called.
struct Feed {
    var samples: UnsafeMutablePointer<Float>
    var length: Int
    var position = 0
    var pulls = 0
    var silent = false
}

/// An EQ unit made, attached to its host and allocated as AVAudioEngine would, and everything a call needs - made
/// before anything is measured.
final class UnitRig {
    let unit: EQUnit
    let host = EQHost()
    let rate: Double
    let channels: Int
    let capacity: Int
    let renderObject: AnyObject
    let render: RawRender
    let pull: RawPull
    let feed: UnsafeMutablePointer<Feed>
    let list: UnsafeMutableAudioBufferListPointer
    /// the host's own buffers, `channels` x `capacity`
    let output: UnsafeMutablePointer<Float>
    let flags = UnsafeMutablePointer<AudioUnitRenderActionFlags>.allocate(capacity: 1)
    let time = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)

    init(rate: Double, channels: Int = 2, capacity: Int = 8_192, noise: Bool = true) throws {
        self.rate = rate
        self.channels = channels
        self.capacity = capacity
        EQUnit.register()
        unit = try EQUnit(componentDescription: EQUnit.component, options: [])
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels))!
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        unit.maximumFramesToRender = EQUnit.maximumFrames
        unit.attach(host)
        host.made()
        try unit.allocateRenderResources()
        let object = try #require(unit.value(forKey: "internalRenderBlock") as AnyObject?)
        renderObject = object
        render = unsafeBitCast(object, to: RawRender.self)

        let length = 1 << 16
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: length + capacity)
        var random = SeededRandom(seed: 42)
        for i in 0..<(length + capacity) { samples[i] = noise ? Float(random.next() * 0.5) : 0 }
        feed = .allocate(capacity: 1)
        feed.initialize(to: Feed(samples: samples, length: length))
        let feed = feed
        pull = { (_, _, frames, _, into) -> AUAudioUnitStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(into)
            let from = feed.pointee.samples + feed.pointee.position
            for c in 0..<buffers.count {
                guard let data = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { return kAudioUnitErr_NoConnection }
                if feed.pointee.silent {
                    data.update(repeating: 0, count: Int(frames))
                } else {
                    data.update(from: from + c * 7, count: Int(frames))
                }
            }
            feed.pointee.position = (feed.pointee.position + Int(frames)) % feed.pointee.length
            feed.pointee.pulls += 1
            return noErr
        }
        list = AudioBufferList.allocate(maximumBuffers: channels)
        output = .allocate(capacity: channels * capacity)
        output.initialize(repeating: 0, count: channels * capacity)
        flags.initialize(to: [])
        time.initialize(to: AudioTimeStamp())
        time.pointee.mFlags = .sampleTimeValid
        handBuffers()
    }

    deinit {
        unit.deallocateRenderResources()
        feed.pointee.samples.deallocate()
        feed.deallocate()
        free(list.unsafeMutablePointer)
        output.deallocate()
        flags.deallocate()
        time.deallocate()
    }

    /// The host hands its own buffers (what AVAudioEngine does for an effect's output).
    func handBuffers() {
        for c in 0..<channels {
            list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(capacity * 4),
                                  mData: UnsafeMutableRawPointer(output + c * capacity))
        }
    }

    /// The host hands none: the unit points them at its own.
    func handNone() {
        for c in 0..<channels { list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil) }
    }

    /// One block, as the framework calls it.
    @discardableResult
    func call(_ frames: Int) -> AUAudioUnitStatus {
        flags.pointee = []
        let status = render(flags, time, AUAudioFrameCount(frames), 0, list.unsafeMutablePointer, nil, pull)
        time.pointee.mSampleTime += Double(frames)
        return status
    }
}

/// The allocation hook is the process's one - one malloc_logger, one watched thread - and the suites run side by side
/// (the release steps filter to one suite; a plain `swift test` doesn't): each use holds this, or one test's watch
/// moves another's count off its thread and its remove stops the other's count mid-run, so a count can read low and
/// pass (turntable slice 2's review: DeckWindowTests' byte count, 16.12 MB every time run alone, read as low as
/// 15.80 in the full suite).
let allocationHookInUse = NSLock()

/// The allocations and frees made on this thread while `body` runs, with `pause` able to step outside the count (a
/// bank published: the producers allocate, the render must not). Nil where the hook can't run, or when the canary -
/// one malloc made on purpose - isn't seen.
func allocations(_ body: (_ pause: (() -> Void) -> Void) throws -> Void) rethrows -> (made: UInt64, freed: UInt64)? {
    guard alloc_hook_available() else { return nil }
    allocationHookInUse.lock()
    defer { allocationHookInUse.unlock() }
    alloc_hook_install()
    defer { alloc_hook_remove() }
    alloc_hook_watch_this_thread()
    alloc_hook_canary()
    let canary = alloc_hook_allocations()
    alloc_hook_unwatch()
    guard canary >= 1 else {
        Issue.record("the allocation hook didn't see its canary: it can't be trusted to see anything")
        return nil
    }
    var made: UInt64 = 0, freed: UInt64 = 0
    alloc_hook_watch_this_thread()
    try body { (outside: () -> Void) -> Void in
        made += alloc_hook_allocations()
        freed += alloc_hook_frees()
        alloc_hook_unwatch()
        outside()
        alloc_hook_watch_this_thread()
    }
    made += alloc_hook_allocations()
    freed += alloc_hook_frees()
    alloc_hook_unwatch()
    print("EQ allocation hook: the canary seen (\(canary) allocation)")
    return (made, freed)
}

@Suite(.serialized) struct EQRealTimeTests {
    /// Test 5: 10,000 blocks through the unit's render block - passing through, a crossfade in, filtering, a bank for
    /// another rate, a crossfade with a bank arriving in the middle of it, Off, and the host handing no buffers - and
    /// not one allocation or free on the rendering thread.
    @Test func theRenderAllocatesNothing() throws {
        let rate = 48_000.0
        let rig = try UnitRig(rate: rate)
        rig.host.setOutput(EQTestCurve.key)
        rig.host.publish(toneBank(EQGraphic.flat, rate: rate, version: 0))
        // every bank made before the count starts
        let filtering = EQBank.make(rate: rate, key: EQTestCurve.key, version: 1, on: true, correction: aCorrection,
                                    offsets: .zero, bands: EQGraphic.preset("bassBoost")!.gains, preamp: nil)
        let otherRate = EQBank.make(rate: 96_000, key: EQTestCurve.key, version: 2, on: true, correction: aCorrection,
                                    offsets: .zero, bands: EQGraphic.flat, preamp: nil)
        let swapped = toneBank(EQGraphic.preset("vocal")!.gains, rate: rate, version: 3, preamp: nil)
        let midway = toneBank(EQGraphic.preset("loudness")!.gains, rate: rate, version: 4, preamp: nil)
        let off = EQBank.identity(rate: rate, key: EQTestCurve.key, version: 5)
        let again = EQBank.make(rate: rate, key: EQTestCurve.key, version: 6, on: true, correction: aCorrection,
                                offsets: .zero, bands: EQGraphic.preset("trebleBoost")!.gains, preamp: nil)
        let schedule: [Int: EQBank] = [1_000: filtering, 3_000: otherRate, 5_000: swapped, 5_001: midway, 7_000: off,
                                       8_000: again]
        var statuses: [AUAudioUnitStatus] = []
        statuses.reserveCapacity(10_000)
        let counted = allocations { pause in
            for i in 0..<10_000 {
                if let bank = schedule[i] { pause { rig.host.publish(bank) } }
                if i >= 9_000 { rig.handNone() }
                // blocks of 512, and every 100th one of 4,096 (a locked screen's)
                statuses.append(rig.call(i % 100 == 99 ? 4_096 : 512))
            }
        }
        let status = rig.host.status()
        print("EQ allocations: 10,000 render calls, \(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted") "
              + "on the rendering thread; \(describe(status)); \(rig.feed.pointee.pulls) pulls")
        #expect(statuses.allSatisfy { $0 == noErr })
        #expect(rig.feed.pointee.pulls == 10_000)
        // what the framework is handed is the unit's own block, made once
        #expect(rig.renderObject === rig.unit.renderObject)
        #expect(rig.unit.value(forKey: "internalRenderBlock") as AnyObject? === rig.unit.renderObject)
        // a debug build's unoptimised Swift allocates in Core's loops; what ships is the release build, the one 1.5
        // bounds
        #if !DEBUG
        if let counted {
            #expect(counted.made == 0 && counted.freed == 0, "the render allocated \(counted.made), freed \(counted.freed)")
        }
        #endif
        // the run covered what it says
        #expect(status.crossfades == 5 && status.waited >= 1 && status.otherRate == 1, "\(describe(status))")
        #expect(status.mode == .filtering && status.blocks == 10_000)
    }

    /// Test 5 through the framework (the review): the unit in AVAudioEngine's graph - a looping player, the main
    /// mixer, the unit, the output - rendered by the engine's own real-time manual rendering block, as the phone's
    /// output pulls it. So the framework asks the added getter for the block, wraps it in its own render, and hands it
    /// its own pull block (a heap block: Swift's _Block_copy of it is a count, not a copy). 1,000 blocks of 512, every
    /// 100th 4,096 - passing through, a crossfade in, filtering, another crossfade, Off - and beside it the same run
    /// with no unit at all: not one allocation or free on the rendering thread in either.
    @Test func theFrameworksOwnRenderAllocatesNothing() throws {
        EQUnit.register()
        let rate = 48_000.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let song = tone(440, rate: rate, seconds: 1, level: 0.25)
        let loop = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(song[0].count)))
        loop.frameLength = loop.frameCapacity
        for c in 0..<2 {
            song[c].withUnsafeBufferPointer { (from: UnsafeBufferPointer<Float>) -> Void in
                loop.floatChannelData![c].update(from: from.baseAddress!, count: from.count)
            }
        }
        let schedule: [Int: EQBank] = [
            200: toneBank(EQGraphic.preset("bassBoost")!.gains, rate: rate, version: 1, preamp: nil),
            500: toneBank(EQGraphic.preset("vocal")!.gains, rate: rate, version: 2, preamp: nil),
            800: EQBank.identity(rate: rate, key: EQTestCurve.key, version: 3),
        ]
        for withUnit in [false, true] {
            let engine = AVAudioEngine()
            try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: 4_096)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            let host = EQHost()
            if withUnit {
                let node = try EQUnit.node()
                let unit = try #require(node.auAudioUnit as? EQUnit)
                unit.maximumFramesToRender = EQUnit.maximumFrames
                unit.attach(host)
                host.made()
                engine.attach(node)
                engine.connect(engine.mainMixerNode, to: node, format: format)
                engine.connect(node, to: engine.outputNode, format: format)
                host.setOutput(EQTestCurve.key)
                host.publish(EQBank.identity(rate: rate, key: EQTestCurve.key, version: 0))
            }
            try engine.start()
            defer { engine.stop() }
            player.scheduleBuffer(loop, at: nil, options: .loops)
            player.play()
            let render = engine.manualRenderingBlock
            let list = AudioBufferList.allocate(maximumBuffers: 2)
            let storage = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 4_096)
            storage.initialize(repeating: 0, count: 2 * 4_096)
            defer {
                free(list.unsafeMutablePointer)
                storage.deallocate()
            }
            var error: OSStatus = noErr
            var results: [AVAudioEngineManualRenderingStatus] = []
            results.reserveCapacity(1_100)
            func block(_ frames: Int) {
                for c in 0..<2 {
                    list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                          mData: UnsafeMutableRawPointer(storage + c * 4_096))
                }
                results.append(render(AVAudioFrameCount(frames), list.unsafeMutablePointer, &error))
            }
            // the player's and the engine's first touches, outside the count
            for _ in 0..<50 { block(512) }
            let counted = allocations { (pause: (() -> Void) -> Void) -> Void in
                for i in 0..<1_000 {
                    if withUnit, let bank = schedule[i] { pause { host.publish(bank) } }
                    block(i % 100 == 99 ? 4_096 : 512)
                }
            }
            let peak = (0..<4_096).reduce(Float(0)) { max($0, abs(storage[$1])) }
            let status = host.status()
            print("EQ allocations through AVAudioEngine's real-time render, \(withUnit ? "the unit in the graph" : "no unit"): "
                  + "1,050 blocks, \(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted") "
                  + "in the 1,000 counted; peak \(peak)"
                  + (withUnit ? "; the render block asked for \(status.renderBlockAsked) times; \(describe(status))" : ""))
            #expect(results.allSatisfy { $0 == .success } && error == noErr)
            #expect(peak > 0.1, "it plays")
            if withUnit {
                // the framework took the block from the added getter, and every block went through it
                #expect(status.renderBlockAsked >= 1 && status.blocks == 1_050)
                #expect(status.crossfades == 3 && status.mode == .passing, "\(describe(status))")
            }
            #if !DEBUG
            if let counted {
                #expect(counted.made == 0 && counted.freed == 0,
                        "\(withUnit ? "with the unit" : "no unit"): \(counted.made) allocations, \(counted.freed) frees")
            }
            #endif
        }
    }

    /// Test 10: a block of 4,096 frames (iOS's with the screen locked) renders; one of 4,097 is answered
    /// `kAudioUnitErr_TooManyFramesToProcess`, counted, nothing pulled and the output untouched.
    @Test func aLockedScreensBlockRendersAndALargerOneIsRefused() throws {
        let rate = 48_000.0
        let rig = try UnitRig(rate: rate)
        rig.host.setOutput(EQTestCurve.key)
        rig.host.publish(toneBank(EQGraphic.preset("bassBoost")!.gains, rate: rate, version: 0, preamp: nil))
        #expect(rig.call(4_096) == noErr)
        #expect(rig.feed.pointee.pulls == 1)
        // a pattern the refusal must leave as it is
        for i in 0..<(rig.channels * rig.capacity) { rig.output[i] = Float(i % 1_000) / 1_000 }
        let refused = rig.call(4_097)
        let untouched = (0..<(rig.channels * rig.capacity)).allSatisfy { rig.output[$0] == Float($0 % 1_000) / 1_000 }
        let status = rig.host.status()
        print("EQ blocks: 4,096 frames answered \(noErr), 4,097 answered \(refused) "
              + "(kAudioUnitErr_TooManyFramesToProcess is \(kAudioUnitErr_TooManyFramesToProcess)); "
              + "refused \(status.refused), the output untouched \(untouched), pulls \(rig.feed.pointee.pulls)")
        #expect(refused == kAudioUnitErr_TooManyFramesToProcess)
        #expect(untouched && rig.feed.pointee.pulls == 1)
        #expect(status.refused == 1 && status.blocks == 1)
        // and it renders on
        #expect(rig.call(4_096) == noErr && rig.host.status().blocks == 2)
    }

    /// Test 8 (1.10): the worst case - 74 sections a channel (64 correction filters and the tone's ten), two
    /// channels, at 192 kHz, a new bank every block so it is always crossfading (a drag) - in the unit's own count of
    /// its render time. Bounded in the release build on the MEDIAN block, at 15% of a block's duration (the review):
    /// this M2 measures 8.5-8.6%, and ios.yml's runner is a shared virtual machine on slower cores, where a mean taken
    /// against 10% (1.10's first bound) would fail on the hardware rather than the code - and a mean moves with every
    /// block the scheduler takes the thread away for, where a median doesn't. 15% still fails a render twice as slow.
    /// The mean (Debug's Render row) and the worst are printed beside it.
    @Test func theWorstCaseCostsLittleOfEachBlock() throws {
        let rate = 192_000.0
        let rig = try UnitRig(rate: rate)
        rig.host.setOutput(EQTestCurve.key)
        let correction = (0..<64).map { (i: Int) -> EQFilter in
            EQFilter(id: i + 1, kind: .peak, fc: 30 * pow(500, Double(i) / 63), gain: i % 2 == 0 ? 3 : -3,
                     width: .q(1))
        }
        func bank(_ version: Int) -> EQBank {
            let tilt = version % 2 == 0 ? 1.0 : -1.0
            let gains = (0..<10).map { (b: Int) -> Double in (b % 2 == 0 ? 2 : -2) * tilt }
            return EQBank.make(rate: rate, key: EQTestCurve.key, version: version, on: true, correction: correction,
                               offsets: .zero, bands: gains, preamp: nil)
        }
        let banks = (0..<301).map(bank)
        #expect(banks[0].left.count == 74 && banks[0].right.count == 74)
        rig.host.publish(banks[0])
        rig.call(4_096)
        let tick = EQHost.secondsPerTick
        var blocks: [Double] = []
        blocks.reserveCapacity(300)
        for version in 1...300 {
            rig.host.publish(banks[version])
            let before = audio_counters_load(rig.host.counters, EQCounter.ticks.rawValue)
            let status = rig.call(4_096)
            blocks.append(Double(audio_counters_load(rig.host.counters, EQCounter.ticks.rawValue) &- before) * tick)
            #expect(status == noErr)
        }
        let status = rig.host.status()
        let blockSeconds = 4_096 / rate
        let share = status.meanSeconds / blockSeconds
        let medianShare = median(blocks) / blockSeconds
        print("EQ cost at 192 kHz, 74 sections x 2 channels, crossfading every block: "
              + "\(String(format: "%.3f", median(blocks) * 1_000)) ms a block's median - "
              + "\(String(format: "%.1f", medianShare * 100))% of its \(String(format: "%.1f", blockSeconds * 1_000)) ms; "
              + "\(String(format: "%.3f", status.meanSeconds * 1_000)) ms on average (\(String(format: "%.1f", share * 100))%), "
              + "\(String(format: "%.3f", status.worstSeconds * 1_000)) ms at worst (\(status.crossfades) crossfades)")
        #expect(status.crossfades == 300)
        #if !DEBUG
        #expect(medianShare <= 0.15, "the render's median block takes \(medianShare * 100)% of the block")
        #endif
    }

    /// Test 9 (1.5's denormals): `EQRender.process` called directly - a +12 dB, Q 10 peak at 20 Hz and a high pass at
    /// 0.45 x the rate, at 192 kHz - given a second of noise and then 5 minutes of exact zeros, the states decaying
    /// into the subnormals on the way. No stretch of the silence costs more than twice what noise does a block.
    /// Bounded in the release build; printed in both.
    @Test func silenceCostsNoMoreThanNoise() throws {
        let rate = 192_000.0, frames = 4_096, channels = 2
        let bank = EQBank.make(rate: rate, key: "", version: 0, on: true,
                               correction: [EQFilter(id: 1, kind: .peak, fc: 20, gain: 12, width: .q(10)),
                                            EQFilter(id: 2, kind: .highPass, fc: 0.45 * rate)],
                               offsets: .zero, bands: EQGraphic.flat, preamp: 0)
        #expect(bank.left.count == 2, "both filters play at 192 kHz")
        let state = EQRender.make(rate: rate, channels: channels, maximumFrames: frames)
        defer { EQRender.free(state) }
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: channels * frames)
        let pointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        defer {
            samples.deallocate()
            pointers.deallocate()
        }
        for c in 0..<channels { pointers[c] = samples + c * frames }
        let packed = bank.packed
        var random = SeededRandom(seed: 9)
        let tick = EQHost.secondsPerTick

        func timed(_ offered: UnsafePointer<Double>?) -> Double {
            let began = mach_absolute_time()
            EQRender.process(state, buffers: UnsafePointer(pointers), frames: frames, offered: offered)
            return Double(mach_absolute_time() - began) * tick
        }
        // a second of noise at full scale: the burst, and what a block costs over noise
        var noise: [Double] = []
        for block in 0..<47 {
            for i in 0..<(channels * frames) { samples[i] = Float(random.next()) }
            if block == 0 {
                noise.append(packed.withUnsafeBufferPointer { timed($0.baseAddress) })
            } else {
                noise.append(timed(nil))
            }
        }
        // 5 minutes of zeros
        let blocks = Int(300 * rate) / frames
        var silence: [Double] = []
        silence.reserveCapacity(blocks)
        var quietFrom: Int?
        for block in 0..<blocks {
            samples.update(repeating: 0, count: channels * frames)
            silence.append(timed(nil))
            if quietFrom == nil, (0..<(channels * frames)).allSatisfy({ samples[$0] == 0 }) { quietFrom = block }
        }
        let noiseMedian = median(Array(noise.dropFirst()))
        // each 10 s stretch's median: a denormal slowdown lasts as long as the states are subnormal, a scheduler's
        // interruption one block
        let stretch = Int(10 * rate) / frames
        let stretches = stride(from: 0, to: blocks, by: stretch).map { median(Array(silence[$0..<min($0 + stretch, blocks)])) }
        let slowestStretch = stretches.max() ?? 0
        let slowestBlock = silence.max() ?? 0
        let slowestAt = silence.firstIndex(of: slowestBlock) ?? 0
        print("EQ silence at 192 kHz: a block of noise \(String(format: "%.4f", noiseMedian * 1_000)) ms (median); "
              + "the output exactly 0 from \(quietFrom.map { String(format: "%.1f s", Double($0 * frames) / rate) } ?? "never"); "
              + "each 10 s of silence (median a block, ms): "
              + stretches.map { String(format: "%.4f", $0 * 1_000) }.joined(separator: " ")
              + "; the slowest stretch \(String(format: "%.2f", slowestStretch / noiseMedian))x noise, the slowest block "
              + "\(String(format: "%.4f", slowestBlock * 1_000)) ms (\(String(format: "%.2f", slowestBlock / noiseMedian))x, "
              + "at \(String(format: "%.1f", Double(slowestAt * frames) / rate)) s)")
        #if !DEBUG
        #expect(slowestStretch <= 2 * noiseMedian, "silence costs \(slowestStretch / noiseMedian)x noise")
        #endif
    }
}

func median(_ x: [Double]) -> Double {
    guard !x.isEmpty else { return 0 }
    let sorted = x.sorted()
    return sorted[sorted.count / 2]
}
#endif
