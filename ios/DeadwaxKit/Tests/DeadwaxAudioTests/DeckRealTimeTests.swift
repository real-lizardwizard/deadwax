#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAllocHook
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The record's render is real-time safe (notes/ios-specs/turntable.md 4.3, 7.2): its entry called 10,000 times over
// every message kind and two window swaps, and 1,000 blocks through AVAudioEngine's own real-time manual render, with
// not one allocation or free on the rendering thread - counted by CAllocHook (EQRealTimeTests' `allocations`, whose
// canary must be seen first). Meant for the release build, a step of its own on ios.yml's macOS job:
// `swift test -c release --filter DeckRealTimeTests`. The bound holds only there; a debug build prints the counts.

@Suite(.serialized) struct DeckRealTimeTests {
    /// The state the render reaches holds nothing Swift counts.
    @Test func theRendersStateIsPlainNumbersAndPointers() {
        #expect(_isPOD(DeckHostState.self) && _isPOD(VoiceState.self) && _isPOD(DeckLead.self) && _isPOD(DeckSlot.self))
    }

    /// 10,000 calls of the render entry, as the source node's block makes them - blocks of 512, every 100th of
    /// 4,096 - with a host time (the live clock, `L` moving), every message kind, two window swaps (each giving the
    /// last one back through the return ring), the report ring full and folding, and the EQ crossfading to a curve.
    @Test func theRenderAllocatesNothing() throws {
        let rate = 48_000.0
        let deck = try DeckCases.offlineDeck(rate: rate)
        deck.host.pointee.offline = false
        deck.host.pointee.eq = EQRender.make(rate: rate, channels: 2, maximumFrames: 4_096)
        let host = try #require(deck.eq)
        host.setOutput(EQTestCurve.key)
        let windows = (0..<3).map { (k: Int) -> DeckPCM in
            DeckPCM((0..<2).map { (c: Int) -> [Float] in
                (0..<(8 * 48_000)).map { (i: Int) -> Float in Float(sin(Double(i) * 0.01 * Double(k + c + 1)) * 0.5) }
            })
        }
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 4_096)
        storage.initialize(repeating: 0, count: 2 * 4_096)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        let time = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
        time.initialize(to: AudioTimeStamp())
        defer {
            storage.deallocate()
            free(list.unsafeMutablePointer)
            time.deallocate()
        }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        var statuses: [OSStatus] = []
        statuses.reserveCapacity(10_000)
        var frame = 0.0
        func call(_ frames: Int) {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                      mData: UnsafeMutableRawPointer(storage + c * 4_096))
            }
            time.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
            time.pointee.mSampleTime = frame
            // the output 10 ms ahead of the call, as a device's is - so `L` is what it would be on a phone, not the
            // run's own pace (10,000 blocks made in far less time than they last)
            time.pointee.mHostTime = UInt64((PlaybackEngine.hostSeconds() + 0.01) * ticksPerSecond)
            statuses.append(DeckVoiceHost.render(deck.host, time, UInt32(frames), list.unsafeMutablePointer))
            frame += Double(frames)
        }
        // the schedule: what is posted before which call (posting allocates on the main side; the render must not)
        // a message's time is the voice's now when it is posted (the output's time less `L`, about the host's now)
        func at(_: Int) -> Double { PlaybackEngine.hostSeconds() }
        var schedule: [Int: [() -> Void]] = [:]
        func on(_ i: Int, _ post: @escaping () -> Void) { schedule[i, default: []].append(post) }
        on(10) { deck.post(.window(windows[0].voiceWindow(start: 0, rate: rate)), keeping: windows[0]) }
        on(11) { deck.post(.take(at: 2, rate: 1, time: at(11), until: .infinity), keeping: nil) }
        for i in stride(from: 20, to: 2_000, by: 2) {
            on(i) { deck.post(.hand(at: 2 + 0.3 * sin(Double(i) / 50), time: at(i)), keeping: nil) }
        }
        on(2_500) { deck.post(.drive(at: 3, rate: -1.5, accel: 0.8, time: at(2_500), until: at(2_500) + 1), keeping: nil) }
        on(3_000) { deck.post(.window(windows[1].voiceWindow(start: 0.5, rate: rate)), keeping: windows[1]) }
        on(3_100) { _ = host.publish(EQTestCurve.bank(on: true, rate: rate, version: 1)) }
        on(4_000) { deck.post(.drive(at: 4, rate: 1, accel: nil, time: at(4_000), until: .infinity), keeping: nil) }
        on(6_000) { deck.post(.window(windows[2].voiceWindow(start: 1, rate: rate)), keeping: windows[2]) }
        on(7_000) { deck.post(.fade(seconds: 0.03), keeping: nil) }
        on(8_000) { deck.post(.take(at: 5, rate: 2, time: at(8_000), until: at(8_000) + 0.12), keeping: nil) }
        on(9_000) { deck.post(.stop, keeping: nil) }
        on(9_500) { deck.post(.window(nil), keeping: nil) }
        // the warm-up's work, outside the count: the first blocks and first messages, on both clocks - and the test's
        // own clock read once (AVAudioTime's first use allocates, on whichever thread makes it)
        DeckEngine.warm()
        _ = PlaybackEngine.hostSeconds()
        // the count after each call (made before the count starts), so a nonzero count says which calls allocated
        var after = [UInt64](repeating: 0, count: 10_000)
        var paused = [Bool](repeating: false, count: 10_000)
        let counted = allocations { (pause: (() -> Void) -> Void) -> Void in
            for i in 0..<10_000 {
                if let posts = schedule[i] {
                    pause { for post in posts { post() } }
                    paused[i] = true
                }
                call(i % 100 == 99 ? 4_096 : 512)
                after[i] = alloc_hook_allocations()
            }
        }
        let allocating = (0..<10_000).filter { (i: Int) -> Bool in after[i] > (i == 0 || paused[i] ? 0 : after[i - 1]) }
        let status = deck.status()
        print("Deck allocations: 10,000 render calls, \(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted") "
              + "on the rendering thread; \(status.messages) messages applied, \(status.windowsReturned) windows given back, "
              + "\(status.reportsFolded) reports folded, L \(status.lead.map { String(format: "%.2f ms", $0 * 1_000) } ?? "-"), "
              + "the EQ in \(host.status().mode)")
        #expect(statuses.allSatisfy { $0 == noErr })
        #expect(status.blocks == 10_000 && status.messages == schedule.values.reduce(0) { $0 + $1.count } - 1)
        #expect(status.windowsReturned == 3, "each swap, and the window(nil), gave the last one back")
        #expect(status.reportsFolded > 0, "the report ring filled (nothing read it) and folded")
        #expect(status.lead != nil)
        #if !DEBUG
        if let counted {
            #expect(counted.made == 0 && counted.freed == 0,
                    "the render allocated \(counted.made), freed \(counted.freed), in calls \(allocating.prefix(20))")
        }
        #endif
    }

    /// Through the framework: the deck engine in AVAudioEngine's real-time manual rendering - its source node, the main
    /// mixer, the output - rendered by the engine's own block, 1,050 blocks (50 outside the count), every 100th of
    /// 4,096: not one allocation or free on the rendering thread, the bridge to the source node's block included.
    @Test func theFrameworksOwnRenderAllocatesNothing() throws {
        let rate = 48_000.0
        var settings = DeckEngine.Settings()
        settings.offline = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        settings.realtimeManual = true
        let deck = DeckEngine(settings: settings)
        try deck.start()
        defer { deck.stop() }
        let pcm = DeckPCM((0..<2).map { (c: Int) -> [Float] in
            (0..<(16 * 48_000)).map { (i: Int) -> Float in Float(sin(Double(i) * 0.02 * Double(c + 1)) * 0.5) }
        })
        deck.post(.window(pcm.voiceWindow(start: 0, rate: rate)), keeping: pcm)
        deck.post(.take(at: 1, rate: 1, time: 0, until: .infinity), keeping: nil)
        let render = deck.manualRenderingBlock
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
        var peak: Float = 0
        func block(_ frames: Int) {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                      mData: UnsafeMutableRawPointer(storage + c * 4_096))
            }
            results.append(render(AVAudioFrameCount(frames), list.unsafeMutablePointer, &error))
            for i in 0..<frames { peak = max(peak, abs(storage[i])) }
        }
        for _ in 0..<50 { block(512) }
        let counted = allocations { (pause: (() -> Void) -> Void) -> Void in
            for i in 0..<1_000 {
                if i == 500 { pause { deck.post(.hand(at: 1.4, time: 0.6), keeping: nil) } }
                block(i % 100 == 99 ? 4_096 : 512)
            }
        }
        print("Deck allocations through AVAudioEngine's real-time render: 1,050 blocks, "
              + "\(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted") in the 1,000 counted; peak \(peak)")
        #expect(results.allSatisfy { $0 == .success } && error == noErr)
        #expect(peak > 0.1, "it plays (the window's 15 s from 1 s, the hand at block 500 holding it still)")
        #expect(deck.status().blocks == 1_050)
        #if !DEBUG
        if let counted {
            #expect(counted.made == 0 && counted.freed == 0, "\(counted.made) allocations, \(counted.freed) frees")
        }
        #endif
    }
}
#endif
