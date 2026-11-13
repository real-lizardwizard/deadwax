// The questions slice 2's review left for slice 3 (notes/ios-specs/turntable.md, "Slice 3, built"): a block with no
// host time placed after the last one rather than on the sample clock (1); a route change restarting `L` from its
// floor, whatever its rate (2); nothing timed waiting through a stop - a window kept aside, every timed message
// dropped and counted, the voice quiet - so a stop's doc and its code agree and no number of posts fills the ring
// (3, 4); the deck's EQ time counted as the song's is (6); a newer /scrub ask cancelling the fetch before it (6).
#if canImport(AVFAudio)
import AVFAudio
@testable import DeadwaxAudio
@testable import DeadwaxCore
import CAudioRing
import Foundation
import Testing

@Suite(.serialized) struct DeckReviewTests {
    static let rate = 48_000.0

    /// A live (not offline) call of the render entry, as DeckEngineRenderTests' clock test makes it.
    final class LiveCall {
        let deck: DeckEngine
        let frames: Int
        let storage: UnsafeMutablePointer<Float>
        let list: UnsafeMutableAudioBufferListPointer
        let time: UnsafeMutablePointer<AudioTimeStamp>
        let ticksPerSecond: Double

        init(_ deck: DeckEngine, frames: Int = 512) {
            self.deck = deck
            self.frames = frames
            deck.host.pointee.offline = false
            storage = .allocate(capacity: 2 * frames)
            storage.initialize(repeating: 0, count: 2 * frames)
            list = AudioBufferList.allocate(maximumBuffers: 2)
            time = .allocate(capacity: 1)
            time.initialize(to: AudioTimeStamp())
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        }

        deinit {
            storage.deallocate()
            free(list.unsafeMutablePointer)
            time.deallocate()
        }

        /// One block: presented `ahead` after now, or with no host time at all (`ahead` nil) and a sample time far from
        /// it. The voice's now after it.
        func call(ahead: Double?) -> Double {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(storage + c * frames))
            }
            if let ahead {
                time.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
                time.pointee.mHostTime = UInt64((PlaybackEngine.hostSeconds() + ahead) * ticksPerSecond)
            } else {
                time.pointee.mFlags = [.sampleTimeValid]
                time.pointee.mHostTime = 0
            }
            time.pointee.mSampleTime = 9_000_000
            _ = DeckVoiceHost.render(deck.host, time, UInt32(frames), list.unsafeMutablePointer)
            return deck.status().now ?? .nan
        }

        var output: [Float] { Array(UnsafeBufferPointer(start: storage, count: frames)) }
    }

    /// Question 1: a block whose time stamp has no host time is placed straight after the last block, at the `L` the
    /// clock has - not on the sample clock (here 9,000,000 frames: a jump of minutes) - and the lead isn't fed it.
    @Test func aBlockWithNoHostTimeFollowsTheLast() throws {
        let deck = try DeckCases.offlineDeck(rate: Self.rate, maximumFrames: 512, eq: false)
        let live = LiveCall(deck)
        var last = 0.0
        for _ in 0..<10 { last = live.call(ahead: 0.010) }
        let lead = deck.host.pointee.lead.pointee.value
        let block = 512 / Self.rate
        let next = live.call(ahead: nil)
        #expect(abs(next - (last + block)) < 0.002, "after the last block: \(next - last) s on, a block is \(block)")
        let again = live.call(ahead: nil)
        #expect(abs(again - (next + block)) < 1e-9, "and the next after that, exactly a block on")
        #expect(deck.host.pointee.lead.pointee.value == lead, "the lead isn't fed a guess")
        // the first block of a start with none before it: where a block entered now would be presented, less `L`
        let fresh = try DeckCases.offlineDeck(rate: Self.rate, maximumFrames: 512, eq: false)
        let first = LiveCall(fresh).call(ahead: nil)
        #expect(abs(first - PlaybackEngine.hostSeconds()) < 0.5, "now, not the sample clock: \(first)")
    }

    /// Questions 3 and 4: a stop leaves the voice quiet and nothing timed waiting - a take posted and not yet rendered
    /// is dropped at the stop, one posted while stopped as it comes (both `stale`, not the full ring's `dropped`) -
    /// while the newest window is kept aside and is the first thing the next start applies, however many came.
    @Test func nothingTimedWaitsThroughAStop() throws {
        let deck = try DeckCases.offlineDeck(rate: Self.rate, eq: false, messageCapacity: 16)
        try deck.start()
        let loud = DeckPCM([[Float](repeating: 0.25, count: 96_000), [Float](repeating: 0.25, count: 96_000)])
        func window(_ pcm: DeckPCM) -> DeckPost {
            .window(DeckWindow(pcm: pcm, start: 0, end: 2, rate: Self.rate, source: .file, bytes: 0, madeIn: 0))
        }
        deck.setOfflineClock(frames: 0)
        #expect(deck.post(window(loud)))
        #expect(deck.post(.take(at: 0.5, rate: 1, time: 0, until: .infinity)))
        _ = try deck.renderOffline(1_024)
        #expect(DeckRender.sounding(deck.host.pointee.voice), "sounding before the stop")
        // a drive posted and never rendered, then the stop
        #expect(deck.post(.drive(at: 1, rate: 1, accel: nil, time: 0.03, until: .infinity)))
        deck.stop()
        var status = deck.status()
        #expect(status.stale == 1 && status.dropped == 0, "\(status)")
        #expect(!DeckRender.sounding(deck.host.pointee.voice) && deck.host.pointee.voice.pointee.gain == 0, "quiet at the stop")
        // while stopped: forty takes, hands and drives - each dropped as it comes - and three windows, the newest kept
        for i in 0..<40 {
            #expect(!deck.post(i % 2 == 0 ? .hand(at: 1, time: 0.1) : .take(at: 1, rate: 1, time: 0.1, until: .infinity)))
        }
        let a = DeckPCM([[Float](repeating: 0.1, count: 4_800)]), b = DeckPCM([[Float](repeating: 0.2, count: 4_800)])
        let newest = DeckPCM([[Float](repeating: 0.3, count: 4_800)])
        for pcm in [a, b, newest] { #expect(deck.post(window(pcm))) }
        status = deck.status()
        #expect(status.stale == 41 && status.dropped == 0, "none reached the ring: \(status)")
        // the start: the newest window in, and nothing else - the voice silent until something is taken
        let applied = status.messages
        try deck.start()
        defer { deck.stop() }
        let out = try deck.renderOffline(1_024)
        status = deck.status()
        #expect(status.messages == applied + 1, "one message applied: the window (\(status.messages - applied))")
        deck.collect()
        #expect(deck.live.values.contains { (pcm: DeckPCM) -> Bool in pcm === newest }, "the newest window is the voice's")
        #expect(!deck.live.values.contains { (pcm: DeckPCM) -> Bool in pcm === a || pcm === b }, "the older ones let go")
        let left = try #require(out.floatChannelData?[0])
        #expect((0..<1_024).allSatisfy { left[$0] == 0 }, "silent: no stale knot played")
    }

    /// Question 2: a route change stops the voice and starts `L` again from twice the IO buffer, whatever the rate;
    /// offline (no hardware to ask) it reports no new rate, and the window is kept.
    @Test func aRouteChangeRestartsTheClockFromItsFloor() throws {
        let deck = try DeckCases.offlineDeck(rate: Self.rate, maximumFrames: 512, eq: false)
        deck.ioBuffer = { 0.0213 }
        let live = LiveCall(deck)
        for _ in 0..<20 { _ = live.call(ahead: 0.004) }
        #expect(abs(deck.host.pointee.lead.pointee.value - (0.004 + 512 / Self.rate)) < 0.002)
        let dropped = Locked(0)
        deck.windowDropped = { dropped.set(dropped.get() + 1) }
        #expect(!deck.routeChanged())
        #expect(deck.host.pointee.lead.pointee.value == 2 * 0.0213, "from its floor")
        let main = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { main.signal() }
        _ = main.wait(timeout: .now() + 1)
        #expect(dropped.get() == 0, "the same rate: the window kept")
    }

    /// Question 6: the deck's EQ counts its render time as the song's EQUnit does - ticks and the longest block.
    @Test func theDecksEQCountsItsTime() throws {
        let deck = try DeckCases.offlineDeck(rate: Self.rate, eq: true)
        try deck.start()
        defer { deck.stop() }
        for _ in 0..<20 { _ = try deck.renderOffline(1_024) }
        let counters = try #require(deck.host.pointee.eqCounters)
        let ticks = audio_counters_load(counters, EQCounter.ticks.rawValue)
        let worst = audio_counters_load(counters, EQCounter.worst.rawValue)
        #expect(ticks > 0 && worst > 0 && worst <= ticks, "ticks \(ticks), worst \(worst)")
        #expect(deck.host.pointee.eqBlocks == 20)
    }

    /// Question 6: a newer ask cancels the /scrub fetch before it - the fetch itself, not only its answer.
    @Test func aNewerAskCancelsTheScrubFetch() throws {
        let server = HeldServer()
        let client = DeadwaxClient(server: ServerAddress(base: try #require(URL(string: "http://deadwax.test:8080"))), transport: server)
        try withFolder { (folder: URL) -> Void in
            let windows = DeckWindows(scrubFolder: folder, answerQueue: DispatchQueue(label: "deck-review.answers"))
            windows.make(scrub: client, songID: "first", from: 2, seconds: 40, outputRate: Self.rate, factor: nil) { _ in }
            #expect(server.entered.wait(timeout: .now() + 10) == .success, "the first fetch is on its way")
            #expect(windows.fetching)
            windows.make(file: folder.appendingPathComponent("none.flac"), from: 0, seconds: 1, outputRate: Self.rate, factor: nil) { _ in }
            server.release.signal()
            #expect(server.finished.wait(timeout: .now() + 10) == .success)
            #expect(server.cancelled.get(), "the first fetch saw its cancel")
            #expect(!windows.fetching)
        }
    }

    /// A `/scrub` that holds its first request until released, and says whether its task was cancelled meanwhile.
    final class HeldServer: HTTPTransport, @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let cancelled = Locked(false)

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            entered.signal()
            release.wait()
            cancelled.set(Task.isCancelled)
            finished.signal()
            try Task.checkCancellation()
            return HTTPResponse(status: 204, headers: [:], body: Data())
        }
    }

    func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deck-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
#endif
