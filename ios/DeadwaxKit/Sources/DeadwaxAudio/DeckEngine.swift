#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAudioRing
import DeadwaxCore
import Foundation

/// What Debug shows of the deck engine (turntable.md 6.2): whether it runs, at what rate, its clock, and what its
/// render and rings counted.
public struct DeckEngineStatus: Sendable, Equatable {
    public var running = false
    public var rate: Double = 0
    public var blocks = 0
    public var frames = 0
    /// messages the render applied, and those the full ring refused (4.3: "Messages dropped")
    public var messages = 0
    public var dropped = 0
    public var reportsFolded = 0
    public var windowsLive = 0
    public var windowsReturned = 0
    /// windows a full return ring kept (leaked until `reset`)
    public var windowsKept = 0
    /// blocks refused: more frames than the render was made for
    public var refused = 0
    /// `L`, the last block's own lead, the largest over 1.5 s, the largest under the last sound - nil before a block
    /// with a host time (offline there is none)
    public var lead: Double?
    public var latest: Double?
    public var target: Double?
    public var largestSounding: Double?
    /// the voice's now at the last block
    public var now: Double?
    public var starts = 0
    public var stops = 0
    /// how long the last start took (prepare and start), seconds
    public var lastStartSeconds: Double?
    /// why the last start failed, in the engine's words
    public var failure: String?
    /// the EQ's blocks on the deck (eq.md 1.9)
    public var eqBlocks = 0
    /// Messages dropped because their time had passed: posted while the engine was stopped, or left unapplied by a
    /// stop (slice 2's review, questions 3 and 4). Not the full ring's `dropped`.
    public var stale = 0

    /// Debug's Clock row (6.2).
    public var clockRow: InfoRow {
        TurntableDebugRows.clockRow(lead: lead, largest: (largestSounding ?? 0) > 0 ? largestSounding : target,
                                    underHand: (largestSounding ?? 0) > 0)
    }
}

/// The record's own engine (notes/ios-specs/turntable.md 4.3): a second AVAudioEngine, an AVAudioSourceNode of two
/// non-interleaved Float32 channels at the output's rate into its main mixer at unity, to its output - the voice and
/// nothing else in its render (DeckVoiceHost). A second engine because the song's stops its output on every pause,
/// which is exactly when the record's sound runs.
///
/// One thread posts and reads (the main thread; a test's own): `post` writes the message ring, `collect` reads the
/// return and report rings. The voice's state is touched from here only while the engine is stopped (`reset`).
/// Offline (`Settings.offline`), the engine renders by manual rendering for the tests, and the voice's clock is the
/// sample time (`offlineFrames`, `offlineLead`).
public final class DeckEngine {
    public struct Settings {
        /// Offline manual rendering in this format (the tests' render), instead of the device.
        public var offline: AVAudioFormat?
        /// The EQ after the voice's limiter (eq.md 1.9), with a host of its own.
        public var eq = true
        /// The most frames a block may ask (iOS asks 4,096 with the screen locked).
        public var maximumFrames = 4_096
        /// The message ring's depth (a test replaying a long trace from its middle asks more).
        public var messageCapacity = DeckEngine.messageCapacity
        /// With `offline`: AVAudioEngine's real-time manual rendering instead of offline - the framework's own
        /// real-time render path, for the allocation test (`manualRenderingBlock`).
        public var realtimeManual = false
        public init() {}
    }

    /// The message ring's depth (4.3): 2 s of a hand's samples at 120 Hz, the drives beside them.
    public static let messageCapacity: UInt32 = 256
    /// Windows on their way back: more than can be in flight (one in use, one on its way, a refresh).
    public static let returnCapacity: UInt32 = 8
    /// Reports waiting to be read: 2 s of the voice's 30 a second.
    public static let reportCapacity: UInt32 = 64

    /// The output's IO buffer (AVAudioSession's ioBufferDuration): `L` starts at twice it (3.2). The app sets it.
    public var ioBuffer: () -> TimeInterval = { 0 }
    /// The deck engine's own `outputLatency + ioBufferDuration` - its part of `D` (3.5). The app sets it.
    public var latency: () -> TimeInterval = { 0 }
    /// At every start, between prepare and start (eq.md 1.8): the deck's EQ host, its rate and channels - the app
    /// publishes the output's curve here, as it does for the song's engine.
    public var eqStart: (_ host: EQHost, _ rate: Double, _ channels: Int) -> Void = { _, _, _ in }
    /// The voice's window is gone - its rate no longer the output's (a route change, a start at a new rate) - so the
    /// deck's rules must ask for it again (DeckRules.windowDropped). On the main queue, after the call that dropped it.
    public var windowDropped: () -> Void = {}
    /// The deck's EQ host (eq.md 1.9): banks published here are rendered after the voice's limiter. Nil with
    /// `Settings.eq` false.
    public let eq: EQHost?

    let engine = AVAudioEngine()
    private(set) var node: AVAudioSourceNode?
    let settings: Settings
    let host: UnsafeMutablePointer<DeckHostState>
    /// What the render's output pointers hold before the first block binds them (the render rebinds them to each
    /// block's buffers, so this, not `outputs[0]`, is what is freed)
    private let scratch: UnsafeMutablePointer<Float>
    /// the windows posted that the voice hasn't let go of, by the id their message carried
    private(set) var live: [UInt32: DeckPCM] = [:]
    private var nextID: UInt32 = 1
    private var dropped = 0
    private var heard: [VoiceHeard] = []
    private var starts = 0
    private var stops = 0
    private var lastStart: Double?
    private var failure: String?
    /// started and not stopped by `stop()` - the system may have stopped the engine meanwhile (a configuration change)
    private var started = false
    /// the newest window posted while stopped, or left in the ring by a stop: applied at the next start's first block
    private var pending: (slot: DeckSlot, pcm: DeckPCM)?
    private var stale = 0
    private let windowQueue = DispatchQueue(label: "deadwax.deck.windows", qos: .utility)

    public init(settings: Settings = Settings()) {
        self.settings = settings
        eq = settings.eq ? EQHost() : nil
        guard let messages = audio_fifo_make(settings.messageCapacity), let returns = audio_fifo_make(Self.returnCapacity),
              let reports = audio_fifo_make(Self.reportCapacity), let counters = audio_counters_make(DeckCounter.count)
        else { fatalError("No memory for the deck's rings") }
        let voice = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        voice.initialize(to: DeckRender.newState())
        let lead = UnsafeMutablePointer<DeckLead>.allocate(capacity: 1)
        lead.initialize(to: DeckLead(floor: 0))
        let slots = UnsafeMutablePointer<DeckSlot>.allocate(capacity: Int(settings.messageCapacity))
        slots.initialize(repeating: DeckSlot(), count: Int(settings.messageCapacity))
        let returned = UnsafeMutablePointer<UInt32>.allocate(capacity: Int(Self.returnCapacity))
        returned.initialize(repeating: 0, count: Int(Self.returnCapacity))
        let heard = UnsafeMutablePointer<DeckHeardSlot>.allocate(capacity: Int(Self.reportCapacity))
        heard.initialize(repeating: DeckHeardSlot(), count: Int(Self.reportCapacity))
        let outputs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        scratch.initialize(to: 0)
        self.scratch = scratch
        outputs.initialize(repeating: scratch, count: 2)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        host = .allocate(capacity: 1)
        host.initialize(to: DeckHostState(
            voice: voice, lead: lead, rate: settings.offline?.sampleRate ?? 48_000, maximumFrames: settings.maximumFrames,
            outputs: outputs, messages: messages, slots: slots, returns: returns, returned: returned, reports: reports,
            heard: heard, counters: counters, secondsPerTick: Double(timebase.numer) / Double(timebase.denom) / 1e9,
            offline: settings.offline != nil))
        if let eq {
            host.pointee.eqTriple = eq.triple
            host.pointee.eqSlots = eq.slots
            host.pointee.eqCounters = eq.counters
            host.pointee.eqPacked = eq.packedCount
            eq.made()
        }
        if let format = settings.offline {
            do {
                try engine.enableManualRenderingMode(settings.realtimeManual ? .realtime : .offline, format: format,
                                                     maximumFrameCount: AVAudioFrameCount(settings.maximumFrames))
            } catch {
                failure = "offline rendering refused: \(error.localizedDescription)"
            }
        }
    }

    deinit {
        engine.stop()
        let h = host.pointee
        h.voice.pointee.deallocate()
        h.voice.deinitialize(count: 1)
        h.voice.deallocate()
        h.lead.pointee.deallocate()
        h.lead.deallocate()
        h.slots.deallocate()
        h.returned.deallocate()
        h.heard.deallocate()
        scratch.deallocate()
        h.outputs.deallocate()
        audio_fifo_free(h.messages)
        audio_fifo_free(h.returns)
        audio_fifo_free(h.reports)
        audio_counters_free(h.counters)
        if let eqState = h.eq { EQRender.free(eqState) }
        host.deinitialize(count: 1)
        host.deallocate()
    }

    public var isRunning: Bool { engine.isRunning }
    /// The voice's rate: the output's, at the last start (offline, the format's).
    public var rate: Double { host.pointee.rate }

    // MARK: start and stop

    /// Prepared and started, at the output's rate - the source node made again, and the voice reset, when that rate
    /// changed (a new route: a window at the old rate is dropped and made again, 4.4). Warmed first, once, off the
    /// audio thread (4.3).
    public func start() throws {
        if started && engine.isRunning { return }
        // stopped by the system (its configuration changed, 4.6): settled as a stop of ours first
        if started { stop() }
        Self.warm()
        let began = PlaybackEngine.hostSeconds()
        let rate: Double
        if let format = settings.offline {
            rate = format.sampleRate
        } else {
            let hardware = engine.outputNode.outputFormat(forBus: 0).sampleRate
            rate = hardware > 0 ? hardware : 48_000
        }
        if node == nil || rate != host.pointee.rate {
            let changed = node != nil
            if let old = node {
                engine.disconnectNodeOutput(old)
                engine.detach(old)
            }
            if changed {
                let had = host.pointee.window != 0 || pending != nil
                resetStopped()
                if had { tellWindowDropped() }
            }
            host.pointee.rate = rate
            host.pointee.lead.pointee.restart(floor: 2 * ioBuffer())
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                failure = "no format at \(rate) Hz"
                throw AudioFailure(failure ?? "")
            }
            let h = host
            let made = AVAudioSourceNode(format: format) {
                (_: UnsafeMutablePointer<ObjCBool>, timestamp: UnsafePointer<AudioTimeStamp>, frames: AVAudioFrameCount,
                 list: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
                DeckVoiceHost.render(h, timestamp, frames, list)
            }
            engine.attach(made)
            engine.connect(made, to: engine.mainMixerNode, format: format)
            made.volume = 1
            engine.mainMixerNode.outputVolume = 1
            node = made
        }
        if let eq {
            // made again at every start, as the song's EQUnit makes its render memory at every allocation (eq.md 1.6,
            // 1.9): its first block installs the newest bank - states zeroed, no crossfade - rather than crossfading
            // from the bank and the filters' state of the run before the stop. The render isn't running.
            if let old = host.pointee.eq { EQRender.free(old) }
            host.pointee.eq = EQRender.make(rate: rate, channels: 2, maximumFrames: settings.maximumFrames)
            eq.allocated(rate: rate, channels: 2)
            eq.outputStarting()
            eqStart(eq, rate, 2)
        }
        // the clock starts afresh (a block with no host time is placed after the last one, which a stop has made old),
        // and the window posted while it rested goes in first
        host.pointee.lastHostOut = -1
        if let waiting = pending {
            pending = nil
            if post(waiting.slot, keeping: waiting.pcm) == false { windowQueue.async { _ = waiting.pcm.capacity } }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            failure = error.localizedDescription
            eq?.deallocated()
            throw error
        }
        started = true
        eq?.outputStarted()
        failure = nil
        starts += 1
        lastStart = PlaybackEngine.hostSeconds() - began
    }

    /// Stopped: the voice keeps its window, as the web's suspended context does, and goes quiet - the sound it was
    /// making went with the output, and its knots' times will have passed by the next start. So nothing timed waits
    /// for that start (slice 2's review, questions 3 and 4): a message the voice hadn't applied is dropped here, and
    /// one posted while stopped is dropped as it comes (both counted, `stale`) - except a window, the newest of which
    /// is kept aside and applied at the next start's first block, outside the ring, so no number of posts while
    /// stopped can fill it. The DeckController starts the engine before it posts a sound (4.6), so the deck's rules
    /// post only windows and stops while it rests. At a new rate the next start makes the voice again, the window
    /// with it (it was made at the old rate), and says so (`windowDropped`).
    public func stop() {
        guard started else { return }
        started = false
        if engine.isRunning { engine.stop() }
        eq?.deallocated()
        stops += 1
        settleStopped()
        collect()
    }

    /// A route change (4.6; slice 2's review, question 2): the voice stopped - quiet, then the engine - and `L` started
    /// again from its floor on the new route, whatever its rate. When the output's rate is no longer the voice's, the
    /// voice is made again now, its window dropped (`windowDropped`), and the source node remade at the next start.
    /// True when the rate changed.
    @discardableResult
    public func routeChanged() -> Bool {
        stop()
        host.pointee.lead.pointee.restart(floor: 2 * ioBuffer())
        guard settings.offline == nil, let old = node else { return false }
        let hardware = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard hardware > 0, hardware != host.pointee.rate else { return false }
        let had = host.pointee.window != 0 || pending != nil
        resetStopped()
        engine.disconnectNodeOutput(old)
        engine.detach(old)
        node = nil
        host.pointee.rate = hardware
        if had { tellWindowDropped() }
        return true
    }

    /// The voice quiet, and the ring emptied of what it hadn't applied: a window kept aside for the next start, the
    /// rest dropped as stale. Only while stopped.
    private func settleStopped() {
        var slot: UInt32 = 0
        while audio_fifo_peek(host.pointee.messages, &slot) {
            let message = host.pointee.slots[Int(slot)]
            if message.tag == DeckSlot.Tag.window.rawValue, let pcm = live.removeValue(forKey: message.id) {
                keepAside(message, pcm)
            } else {
                stale += 1
            }
            audio_fifo_release(host.pointee.messages)
        }
        // quiet: a voice made afresh round the window it had - no knot, no gain, and the limiter's lookahead and the DC
        // blocker empty, so the next start doesn't play the last 1.5 ms of the sound the stop cut (a fade wouldn't
        // reach those: they are already past the gain)
        let voice = host.pointee.voice
        let window = voice.pointee.window
        voice.pointee.deallocate()
        voice.pointee = DeckRender.newState()
        voice.pointee.window = window
    }

    /// The newest window waiting for a start; the one it replaces freed off the main thread.
    private func keepAside(_ slot: DeckSlot, _ pcm: DeckPCM) {
        if let older = pending { windowQueue.async { _ = older.pcm.capacity } }
        pending = (slot, pcm)
    }

    private func tellWindowDropped() {
        DispatchQueue.main.async { [weak self] in self?.windowDropped() }
    }

    /// The voice made again, every window let go of and freed, the rings emptied - only while stopped (the deck gone,
    /// a new rate).
    public func reset() {
        precondition(!engine.isRunning, "the voice is reset only while the deck engine is stopped")
        resetStopped()
    }

    private func resetStopped() {
        var slot: UInt32 = 0
        while audio_fifo_peek(host.pointee.messages, &slot) { audio_fifo_release(host.pointee.messages) }
        if let waiting = pending { windowQueue.async { _ = waiting.pcm.capacity } }
        pending = nil
        collect()
        let voice = host.pointee.voice
        voice.pointee.deallocate()
        voice.pointee = DeckRender.newState()
        host.pointee.window = 0
        let gone = live
        live.removeAll()
        windowQueue.async { _ = gone.count }
    }

    // MARK: messages

    /// A message for the voice, as the deck posts it. False when the ring was full (dropped and counted), or when the
    /// engine is stopped and it isn't a window (dropped as stale - see `stop()`); a window posted while stopped waits
    /// for the next start, the newest only.
    @discardableResult
    public func post(_ message: DeckPost) -> Bool {
        if !(started && engine.isRunning) {
            guard case .window(let window) = message else {
                stale += 1
                return false
            }
            let pcm = window.pcm ?? DeckPCM(window.channels)
            keepAside(DeckSlot(.window(pcm.voiceWindow(start: window.start, rate: window.rate))), pcm)
            return true
        }
        switch message {
        case .window(let window):
            let pcm = window.pcm ?? DeckPCM(window.channels)
            return post(.window(pcm.voiceWindow(start: window.start, rate: window.rate)), keeping: pcm)
        case let .take(at, rate, time, until): return post(.take(at: at, rate: rate, time: time, until: until), keeping: nil)
        case let .drive(at, rate, accel, time, until):
            return post(.drive(at: at, rate: rate, accel: accel, time: time, until: until), keeping: nil)
        case let .hand(at, time): return post(.hand(at: at, time: time), keeping: nil)
        case .fade(let seconds): return post(.fade(seconds: seconds), keeping: nil)
        case .stop: return post(.stop, keeping: nil)
        }
    }

    /// A voice message straight into the ring, running or not (the tests' and the warm-up's way in); a window's PCM
    /// kept alive until the voice lets go of it.
    @discardableResult
    func post(_ message: VoiceMessage, keeping pcm: DeckPCM?) -> Bool {
        post(DeckSlot(message), keeping: pcm)
    }

    @discardableResult
    private func post(_ message: DeckSlot, keeping pcm: DeckPCM?) -> Bool {
        collect()
        var slot: UInt32 = 0
        guard audio_fifo_reserve(host.pointee.messages, &slot) else {
            dropped += 1
            return false
        }
        var made = message
        made.id = 0
        if let pcm {
            made.id = nextID
            nextID = nextID == UInt32.max ? 1 : nextID + 1
            live[made.id] = pcm
        }
        host.pointee.slots[Int(slot)] = made
        audio_fifo_commit(host.pointee.messages)
        return true
    }

    /// Windows the voice let go of, freed on the window queue; reports kept for `reports()`.
    func collect() {
        var slot: UInt32 = 0
        var freed: [DeckPCM] = []
        while audio_fifo_peek(host.pointee.returns, &slot) {
            if let pcm = live.removeValue(forKey: host.pointee.returned[Int(slot)]) { freed.append(pcm) }
            audio_fifo_release(host.pointee.returns)
        }
        if !freed.isEmpty { windowQueue.async { _ = freed.count } }
        while audio_fifo_peek(host.pointee.reports, &slot) {
            heard.append(host.pointee.heard[Int(slot)].heard)
            audio_fifo_release(host.pointee.reports)
        }
        // kept for `reports()` as the ring keeps them, the newest 2 s: every post collects, so with no one reading them
        // (Debug's run) they would otherwise pile up for as long as it plays
        if heard.count > Int(Self.reportCapacity) { heard.removeFirst(heard.count - Int(Self.reportCapacity)) }
    }

    /// The voice's reports since the last call, oldest first.
    public func reports() -> [VoiceHeard] {
        collect()
        defer { heard.removeAll(keepingCapacity: true) }
        return heard
    }

    // MARK: offline

    /// Offline only: the voice's now is `(sample time + frames) / rate - lead` (3.2: the test's base and `L`).
    public func setOfflineClock(frames: Double, lead: Double = 0) {
        host.pointee.offlineFrames = frames
        host.pointee.offlineLead = lead
    }

    /// Real-time manual rendering only (`Settings.realtimeManual`): the framework's block, as the output pulls it.
    var manualRenderingBlock: AVAudioEngineManualRenderingBlock { engine.manualRenderingBlock }

    /// Offline only: `frames` of the deck engine's output.
    public func renderOffline(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames) else {
            throw AudioFailure("no buffer for \(frames) frames")
        }
        let status = try engine.renderOffline(frames, to: buffer)
        guard status == .success else { throw AudioFailure("the deck's offline render answered \(status.rawValue)") }
        return buffer
    }

    // MARK: Debug

    public func status() -> DeckEngineStatus {
        collect()
        let counters = host.pointee.counters
        func load(_ counter: DeckCounter) -> Int { Int(audio_counters_load(counters, counter.rawValue)) }
        func double(_ counter: DeckCounter) -> Double { Double(bitPattern: audio_counters_load(counters, counter.rawValue)) }
        var status = DeckEngineStatus()
        status.running = engine.isRunning
        status.rate = host.pointee.rate
        status.blocks = load(.blocks)
        status.frames = load(.frames)
        status.messages = load(.messages)
        status.dropped = dropped
        status.reportsFolded = load(.reportsDropped)
        status.windowsLive = live.count
        status.windowsReturned = load(.windowsReturned)
        status.windowsKept = load(.windowsKept)
        status.refused = load(.refused)
        if status.blocks > 0 {
            status.now = double(.now)
            if load(.hostTime) == 1 {
                status.lead = double(.lead)
                status.latest = double(.latest)
                status.target = double(.target)
                status.largestSounding = double(.largestSounding)
            }
        }
        status.starts = starts
        status.stops = stops
        status.lastStartSeconds = lastStart
        status.failure = failure
        status.eqBlocks = load(.eqBlocks)
        status.stale = stale
        return status
    }

    // MARK: the warm-up (4.3)

    /// Every lazy first-time thing the render reaches - the voice's specialised code, the sinc's table and the
    /// limiter's lines faulted in, the EQ's first call - done once, on a queue of its own, before the first start: 1,024
    /// frames of silence and each message kind through the same entry, on a state made and freed for it.
    static func warm() { _ = warmed }

    private static let warmed: Bool = {
        DispatchQueue(label: "deadwax.deck.warm", qos: .userInitiated).sync {
            let deck = DeckEngine(settings: { () -> Settings in
                var s = Settings()
                s.offline = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
                return s
            }())
            let rate = 48_000.0
            deck.host.pointee.eq = EQRender.make(rate: rate, channels: 2, maximumFrames: deck.settings.maximumFrames)
            let pcm = DeckPCM(channelCount: 2, capacity: Int(rate))
            for i in 0..<pcm.capacity { pcm.channel(0)[i] = Float(sin(Double(i) * 0.05) * 0.25); pcm.channel(1)[i] = pcm.channel(0)[i] }
            let left = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 1_024)
            left.initialize(repeating: 0, count: 2 * 1_024)
            let list = AudioBufferList.allocate(maximumBuffers: 2)
            let time = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
            time.initialize(to: AudioTimeStamp())
            time.pointee.mFlags = .sampleTimeValid
            defer {
                left.deallocate()
                free(list.unsafeMutablePointer)
                time.deallocate()
            }
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            func block() {
                for c in 0..<2 {
                    list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 1_024 * 4, mData: UnsafeMutableRawPointer(left + c * 1_024))
                }
                // live, a host time 10 ms ahead, as a device's
                time.pointee.mHostTime = mach_absolute_time() + UInt64(0.01 * 1e9 * Double(timebase.denom) / Double(timebase.numer))
                _ = DeckVoiceHost.render(deck.host, time, 1_024, list.unsafeMutablePointer)
                time.pointee.mSampleTime += 1_024
            }
            // each message kind, on the sample clock and then on the host's (the clock's lead, quiet and sounding)
            for live in [false, true] {
                deck.host.pointee.offline = !live
                time.pointee.mFlags = live ? [.sampleTimeValid, .hostTimeValid] : .sampleTimeValid
                let at = live ? Double(mach_absolute_time()) * deck.host.pointee.secondsPerTick : 0
                block()
                let messages: [VoiceMessage] = [
                    .take(at: 0.5, rate: 1, time: at, until: at + 0.1), .drive(at: 0.5, rate: 1, accel: -1, time: at + 0.02, until: at + 0.5),
                    .hand(at: 0.51, time: at + 0.03), .hand(at: 0.52, time: at + 0.04), .fade(seconds: 0.03), .stop, .window(nil),
                ]
                deck.post(.window(pcm.voiceWindow(start: 0, rate: rate)), keeping: pcm)
                block()
                for message in messages {
                    deck.post(message, keeping: nil)
                    block()
                    block()
                }
                deck.collect()
            }
            return true
        }
    }()
}
#endif
