#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAllocHook
import CAudioRing
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Debug's recorder (notes/ios-specs/turntable.md 6.3, slice 4): what the deck engine's tap writes is the voice's own
// output, block for block, with every message it applied before which block - so the phone's file, read back and
// played through the Swift voice again (DeckReplay.phone), is the same sound to the bit. And its tap costs the render
// nothing it may not spend: the real-time suite's two counts again with a recording under way (DeckRealTimeTests,
// release build).

@Suite(.serialized) struct DeckRecordingTests {
    static let rate = 48_000.0

    static func window(seconds: Double = 8, rate: Double = rate) -> DeckPCM {
        DeckPCM((0..<2).map { (c: Int) -> [Float] in
            DeckCases.recipeChannel(c == 0 ? "sweep" : "noise", 3, c, Int(seconds * rate)).map { (v: Float) -> Float in v * 0.7 }
        })
    }

    /// A deck engine offline, recording, through two sounds with a rest between (the engine stopped and started, the
    /// voice made afresh around its window), the second at a new window: the file's every block replays to the bit.
    static func recorded(seconds: Double = 20) throws -> (file: Data, deck: DeckEngine, blocks: Int) {
        let deck = try DeckCases.offlineDeck(rate: rate, eq: true)
        deck.ioBuffer = { 0.005 }
        deck.record(seconds: seconds)
        var done = 0
        var blocks = 0
        func render(_ frames: Int, _ count: Int) throws {
            for _ in 0..<count {
                deck.setOfflineClock(frames: Double(done) - Double(deck.engine.manualRenderingSampleTime))
                _ = try deck.renderOffline(AVAudioFrameCount(frames))
                done += frames
                blocks += 1
                if blocks % 5 == 0 { deck.drainTap() }
            }
        }
        func now() -> Double { Double(done) / rate }
        let first = window()
        // posted while stopped: kept aside for the start, which posts it into the ring
        _ = deck.post(.window(DeckWindow(pcm: first, start: 10, end: 18, rate: rate, source: .file, bytes: 0, madeIn: 0)))
        try deck.start()
        _ = deck.post(.take(at: 12, rate: 1, time: now() + 0.02, until: now() + 0.14))
        try render(1_024, 10)
        for i in 0..<40 {
            _ = deck.post(.hand(at: 12 + 0.3 * sin(Double(i) / 6), time: now() + 0.12))
            try render(i % 7 == 6 ? 4_096 : 1_024, 1)
        }
        _ = deck.post(.drive(at: 12.2, rate: -1.4, accel: 0.9, time: now() + 0.12, until: now() + 0.6))
        try render(512, 20)
        _ = deck.post(.fade(seconds: 0.03))
        try render(1_024, 8)
        deck.stop()
        // the rest: a new window while stopped, then a second sound from rest
        _ = deck.post(.window(DeckWindow(pcm: window(seconds: 6), start: 30, end: 36, rate: rate, source: .file, bytes: 0, madeIn: 0)))
        try deck.start()
        _ = deck.post(.take(at: 31, rate: 1.5, time: now() + 0.01, until: now() + 0.13))
        try render(1_024, 12)
        _ = deck.post(.stop)
        try render(1_024, 4)
        deck.stop()
        let recorder = try #require(deck.finishRecording())
        let file = recorder.file(DeckRecorder.About(when: "2026-11-13T12:00:00.000Z", userAgent: "deadwax tests",
                                                    base: 0.005, output: 0.004))
        return (file, deck, blocks)
    }

    @Test func thePhonesFileReplaysToTheBit() throws {
        let (data, _, blocks) = try Self.recorded()
        // kept for a look, or for replay-deck-recording, where the run says
        if let keep = ProcessInfo.processInfo.environment["DECK_RECORDING_OUT"] { try data.write(to: URL(fileURLWithPath: keep)) }
        let file = try DeckRecordingFile.read(data)
        let phone = try #require(file.phone)
        #expect(phone.blocks.count == blocks, "every block the render made is in the file")
        #expect(Set(phone.blocks.map(\.starts)).count == 2, "two starts")
        #expect(phone.lostBlocks == 0 && phone.lostMessages == 0)
        #expect(phone.windows.count == 2 && phone.windows.allSatisfy { $0.samples[0].count < $0.length },
                "both windows, trimmed to where the read head went")
        let outcome = try #require(DeckReplay.phone(file))
        print("Phone recording replayed: \(outcome.compared) of \(outcome.blocks) blocks, \(outcome.samples) samples, "
              + "largest difference \(outcome.largest) (\(outcome.largestDB) dB)")
        #expect(outcome.blocks == blocks && outcome.compared == blocks)
        #expect(outcome.largest == 0, "the replay is the render's arithmetic again: identical")
        #expect(outcome.withinTestB)
        // the web's keys the web's reader reads
        let web = try #require(WebJSON.parse(String(decoding: data, as: UTF8.self)))
        #expect(web["recording"] == .string("deadwax turntable sound") && web["version"] == .number(3)
                && web["voice"] == .string("phone") && web["audio"]?["format"] == .string("int16le"))
        if case .array(let messages)? = web["messages"] {
            #expect(messages.count == 1 + 1 + 40 + 1 + 1 + 1 + 1 + 1, "every post noted, the two windows by shape")
        } else { Issue.record("no messages") }
        if case .array(let heard)? = web["heard"] { #expect(heard.count > 5) } else { Issue.record("no reports") }
        #expect(file.int16.count == 2 * phone.audio[0].count)
        #expect(zip(file.int16.enumerated().filter { $0.offset % 2 == 0 }.map(\.element), phone.audio[0])
            .allSatisfy { $0.0 == DeckRecorder.int16($0.1) }, "the 16 bits are the floats as deck.ts rounds them")
    }

    /// The replay is held to the file: a message's number, a block's now or a sample changed, and it says so.
    @Test func theReplayNoticesAChange() throws {
        let (data, _, _) = try Self.recorded()
        var text = String(decoding: data, as: UTF8.self)
        // a hand's place moved by a hundredth of a second
        let file = try DeckRecordingFile.read(data)
        let hand = try #require(file.phone?.applied.first { $0["type"] == .string("hand") })
        guard case .number(let at)? = hand["at"] else { Issue.record("no hand"); return }
        let written = "\"type\":\"hand\",\"at\":\(WebJSON.number(at)),"
        #expect(text.contains(written))
        text = text.replacingOccurrences(of: written, with: "\"type\":\"hand\",\"at\":\(WebJSON.number(at + 0.01)),")
        let moved = try #require(DeckReplay.phone(try DeckRecordingFile.read(Data(text.utf8))))
        #expect(moved.largest > 1e-4, "a hand's sample moved: heard")
        // one recorded sample changed
        var changed = try DeckRecordingFile.read(data)
        changed.phone?.audio[0][3_000] += 0.001
        let sample = try #require(DeckReplay.phone(changed))
        #expect(sample.largest > 0.0009 && !sample.withinTestB)
        // a block's now a sample later
        var later = try DeckRecordingFile.read(data)
        later.phone?.blocks[12].now += 1 / Self.rate
        let shifted = try #require(DeckReplay.phone(later))
        #expect(shifted.largest > 0, "a block's now is what the voice reads its path at")
    }

    /// Asked while the engine runs, a recording waits for the next start - the voice from rest - and stops at its
    /// seconds, the tap asked off.
    @Test func itBeginsAtAStartAndEndsAtItsSeconds() throws {
        let deck = try DeckCases.offlineDeck(rate: Self.rate)
        try deck.start()
        deck.post(.window(Self.window().voiceWindow(start: 0, rate: Self.rate)), keeping: Self.window())
        var done = 0
        func render(_ count: Int) throws {
            for _ in 0..<count {
                deck.setOfflineClock(frames: Double(done) - Double(deck.engine.manualRenderingSampleTime))
                _ = try deck.renderOffline(1_024)
                done += 1_024
            }
            deck.drainTap()
        }
        try render(4)
        deck.record(seconds: 0.5)
        try render(10)
        #expect(deck.recorder?.started == false, "running when asked: it waits for the next start")
        deck.stop()
        try deck.start()
        try render(40)
        #expect(deck.recordingDone)
        let recorder = try #require(deck.finishRecording())
        #expect(recorder.recordedSeconds >= 0.5 && recorder.recordedSeconds < 0.5 + 1_024 / Self.rate + 1e-9,
                "\(recorder.recordedSeconds) s: its seconds, to the block")
        #expect(deck.host.pointee.tapOn == false || audio_counters_load(deck.host.pointee.tapControl!, 0) == 0)
        #expect(deck.recorder == nil)
    }
}

extension DeckRealTimeTests {
    /// The render's 10,000 calls again (theRenderAllocatesNothing's schedule, shortened) with the tap on: every block
    /// and message into its ring, drained on the test's thread between calls - and for 200 calls not, so the rings fill
    /// and lose (counted). Not one allocation or free on the rendering thread.
    @Test func theRecordingRenderAllocatesNothing() throws {
        let rate = 48_000.0
        let deck = try DeckCases.offlineDeck(rate: rate)
        deck.host.pointee.offline = false
        deck.record(seconds: 1_000)
        deck.host.pointee.tapOn = true
        deck.tapBegun = true
        audio_counters_store(deck.host.pointee.tapControl!, 0, 1)
        let window = DeckRecordingTests.window()
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
        var frame = 0.0
        var failures = 0
        func call(_ frames: Int) {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                      mData: UnsafeMutableRawPointer(storage + c * 4_096))
            }
            time.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
            time.pointee.mSampleTime = frame
            time.pointee.mHostTime = UInt64((PlaybackEngine.hostSeconds() + 0.01) * ticksPerSecond)
            if DeckVoiceHost.render(deck.host, time, UInt32(frames), list.unsafeMutablePointer) != noErr { failures += 1 }
            frame += Double(frames)
        }
        func at() -> Double { PlaybackEngine.hostSeconds() }
        var schedule: [Int: [() -> Void]] = [:]
        func on(_ i: Int, _ post: @escaping () -> Void) { schedule[i, default: []].append(post) }
        on(10) { deck.post(.window(window.voiceWindow(start: 0, rate: rate)), keeping: window) }
        on(11) { deck.post(.take(at: 2, rate: 1, time: at(), until: .infinity), keeping: nil) }
        // (a post collects, and collecting drains: none from 4,000 to 4,200 either)
        for i in stride(from: 20, to: 9_000, by: 3) where !(4_000..<4_200).contains(i) { on(i) { deck.post(.hand(at: 2 + 0.3 * sin(Double(i) / 50), time: at()), keeping: nil) } }
        on(9_500) { deck.post(.stop, keeping: nil) }
        // drained every 10 calls, but not from 4,000 to 4,200 (the rings fill: blocks and messages lost, counted)
        for i in stride(from: 0, to: 10_000, by: 10) where !(4_000..<4_200).contains(i) { on(i) { deck.drainTap() } }
        DeckEngine.warm()
        _ = PlaybackEngine.hostSeconds()
        let counted = allocations { (pause: (() -> Void) -> Void) -> Void in
            for i in 0..<10_000 {
                if let posts = schedule[i] { pause { for post in posts { post() } } }
                call(i % 100 == 99 ? 4_096 : 512)
            }
        }
        deck.drainTap()
        let recorder = try #require(deck.recorder)
        print("Deck allocations with a recording under way: 10,000 render calls, "
              + "\(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted"); \(recorder.blocks.count) "
              + "blocks and \(recorder.applied.count) messages taken, \(recorder.lostBlocks) blocks and \(recorder.lostMessages) messages lost")
        #expect(failures == 0)
        #expect(recorder.lostBlocks > 0 && recorder.blocks.count + Int(recorder.lostBlocks) == 10_000)
        #if !DEBUG
        if let counted {
            #expect(counted.made == 0 && counted.freed == 0, "the render allocated \(counted.made), freed \(counted.freed)")
        }
        #endif
    }

    /// Through AVAudioEngine's real-time manual render, a recording under way from the start: 1,000 blocks counted.
    @Test func theFrameworksRenderWhileRecordingAllocatesNothing() throws {
        let rate = 48_000.0
        var settings = DeckEngine.Settings()
        settings.offline = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        settings.realtimeManual = true
        let deck = DeckEngine(settings: settings)
        deck.record(seconds: 1_000)
        try deck.start()
        defer { deck.stop() }
        let pcm = DeckRecordingTests.window(seconds: 16)
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
        var failed = 0
        func block(_ frames: Int) {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                      mData: UnsafeMutableRawPointer(storage + c * 4_096))
            }
            if render(AVAudioFrameCount(frames), list.unsafeMutablePointer, &error) != .success { failed += 1 }
        }
        for i in 0..<50 {
            block(512)
            if i % 10 == 9 { deck.drainTap() }
        }
        let counted = allocations { (pause: (() -> Void) -> Void) -> Void in
            for i in 0..<1_000 {
                if i % 10 == 9 { pause { deck.drainTap() } }
                block(i % 100 == 99 ? 4_096 : 512)
            }
        }
        deck.drainTap()
        let recorder = try #require(deck.recorder)
        print("Deck allocations through AVAudioEngine's real-time render, recording: "
              + "\(counted.map { "\($0.made) allocations and \($0.freed) frees" } ?? "not counted") in 1,000 blocks; "
              + "\(recorder.blocks.count) blocks recorded")
        #expect(failed == 0 && error == noErr)
        #expect(recorder.blocks.count == 1_050 && recorder.lostBlocks == 0)
        #if !DEBUG
        if let counted {
            #expect(counted.made == 0 && counted.freed == 0, "\(counted.made) allocations, \(counted.freed) frees")
        }
        #endif
    }
}
#endif
