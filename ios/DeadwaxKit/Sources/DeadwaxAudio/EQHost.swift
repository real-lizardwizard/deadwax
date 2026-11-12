#if canImport(AVFAudio)
import CAudioRing
import DeadwaxCore
import Foundation
import os

/// What hands the EQ's banks to its render (notes/ios-specs/eq.md 1.6), and reads back what the render counted.
///
/// - **Three slots, made up front** - a triple buffer over CAudioRing's one atomic word. A producer packs a bank into
///   the back slot and publishes it; the render, at a block's start, takes the newest and copies it into its own
///   memory at once (`EQRender.process`), so the slot goes back to the producers at the next exchange. Banks in
///   between are never seen: a drag's 120 a second coalesce into what the render can take.
/// - **Producers are serialised** by a lock the render never touches: the main thread (a change) and the engine's
///   queue (a start, `PlaybackEngine.eqStart`).
/// - **One output at a time**: the host keeps the output now (`setOutput`, written by whichever learns of a route
///   first), and a bank is published only if it was made for that output and from a settings version at least the
///   last one published (`EQBank.publishable`); any other is dropped and counted.
/// - **It outlives the unit's buffers** - and the unit itself: one host for the engine's life, a new unit attached to it
///   after a media services reset. It holds the newest bank, which it offers again when the unit allocates (every
///   start, eq.md 1.2), so the first block after a start installs it even when nothing new was published.
/// - **No floating point in C**: the slots' Doubles are written here in Swift and read by `EQRender` in Swift.
public final class EQHost: @unchecked Sendable {
    let triple: OpaquePointer
    /// three slots of `EQBank.packedCount` Doubles
    let slots: UnsafeMutablePointer<Double>
    /// what the render writes after every block (`EQCounter`)
    let counters: OpaquePointer
    let packedCount = EQBank.packedCount

    private struct State {
        var output: String?
        var lastVersion: Int?
        var newest: EQBank?
        var rate: Double?
        var channels: Int?
        var made = false
        var unmade: String?
        var allocations = 0
        var otherOutput = 0
        var older = 0
        var starting = false
        var publishedInStart: Double?
        var started: EQUnitStatus.Started?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {
        guard let triple = audio_triple_make(), let counters = audio_counters_make(EQCounter.count) else {
            fatalError("No memory for the EQ's ring")
        }
        self.triple = triple
        self.counters = counters
        slots = .allocate(capacity: 3 * EQBank.packedCount)
        slots.initialize(repeating: 0, count: 3 * EQBank.packedCount)
        Self.warm()
    }

    deinit {
        audio_triple_free(triple)
        audio_counters_free(counters)
        slots.deallocate()
    }

    // MARK: producers

    /// The output now (eq.md 1.6): set by the start hook from the route as the output starts, or by whatever hears of
    /// the route first. From now on only its banks are published.
    public func setOutput(_ key: String) {
        state.withLock { $0.output = key }
    }

    public var output: String? { state.withLock { $0.output } }

    /// The bank handed to the render, if it is for the output now and from a settings version at least the last one
    /// published; dropped and counted otherwise. On the main thread or the engine's queue - never the audio thread.
    ///
    /// And one more drop (the review): a bank of the same version as the last one published, made for another rate
    /// when that one was made for the rate the unit runs at, is the same settings made a moment too early - a change
    /// that read the old rate while a start at a new one made its own bank first. Taken, it would push the start's bank
    /// out of the ring for one the render can only ignore (1.6), and the settings would play Off until the next
    /// change. A newer version always goes in.
    @discardableResult
    public func publish(_ bank: EQBank) -> Bool {
        state.withLock { (s: inout State) -> Bool in
            guard EQBank.publishable(key: bank.key, version: bank.version, keyNow: s.output, lastPublished: s.lastVersion) else {
                if bank.key != s.output { s.otherOutput += 1 } else { s.older += 1 }
                return false
            }
            if bank.version == s.lastVersion, let rate = s.rate, bank.rate != rate, let newest = s.newest,
               newest.rate == rate, newest.key == bank.key {
                s.older += 1
                return false
            }
            s.lastVersion = bank.version
            s.newest = bank
            if s.starting { s.publishedInStart = PlaybackEngine.hostSeconds() }
            write(bank)
            return true
        }
    }

    /// The rate and channels the unit last allocated at - what a bank made now should be made for; nil before the
    /// output first started.
    public var rate: Double? { state.withLock { $0.rate } }
    public var channels: Int? { state.withLock { $0.channels } }

    /// The bank last published.
    public var newest: EQBank? { state.withLock { $0.newest } }

    /// Under the lock: packed into the back slot, then handed over.
    private func write(_ bank: EQBank) {
        let back = Int(audio_triple_back(triple))
        bank.pack(into: slots + back * packedCount)
        audio_triple_publish(triple)
    }

    // MARK: the unit and the engine

    /// The unit was made and attached to this host.
    func made() {
        state.withLock { (s: inout State) -> Void in
            s.made = true
            s.unmade = nil
        }
    }

    /// The unit couldn't be made: the engine plays on without it (eq.md 1.2), and Debug says why.
    func notMade(_ words: String) {
        state.withLock { (s: inout State) -> Void in
            s.made = false
            s.unmade = words
        }
    }

    /// The unit allocated its render's memory (every start: AVAudioEngine's stop releases it). The counters start
    /// again (but the asks for the render block, the unit's own), waiting for the first block; and the newest bank is
    /// offered again so the first block installs it - when it is for this rate and the output now. The render isn't
    /// running.
    func allocated(rate: Double, channels: Int) {
        state.withLock { (s: inout State) -> Void in
            s.rate = rate
            s.channels = channels
            s.allocations += 1
            for index in 0..<EQCounter.count where index != EQCounter.asked.rawValue {
                audio_counters_store(counters, index, 0)
            }
            audio_counters_store(counters, EQCounter.mode.rawValue, EQCounter.Mode.waiting.rawValue)
            if let newest = s.newest, newest.rate == rate, newest.key == s.output {
                if s.starting { s.publishedInStart = PlaybackEngine.hostSeconds() }
                write(newest)
            }
        }
    }

    /// The unit's memory let go (the output stopped).
    func deallocated() {
        audio_counters_store(counters, EQCounter.mode.rawValue, EQCounter.Mode.stopped.rawValue)
    }

    /// The engine is about to call `eqStart` and start the output.
    func outputStarting() {
        state.withLock { (s: inout State) -> Void in
            s.starting = true
            s.publishedInStart = nil
        }
    }

    /// The output started: what the start put in, and how long before.
    func outputStarted() {
        let now = PlaybackEngine.hostSeconds()
        state.withLock { (s: inout State) -> Void in
            s.starting = false
            if let at = s.publishedInStart, let bank = s.newest {
                s.started = EQUnitStatus.Started(key: bank.key, identity: bank.isIdentity, secondsBefore: max(now - at, 0))
            } else {
                s.started = EQUnitStatus.Started(key: nil, identity: true, secondsBefore: nil)
            }
        }
    }

    // MARK: Debug

    /// What Debug shows of the unit (eq.md 3.13).
    public func status() -> EQUnitStatus {
        let s = state.withLock { $0 }
        func load(_ counter: EQCounter) -> UInt64 { audio_counters_load(counters, counter.rawValue) }
        var status = EQUnitStatus()
        if !s.made {
            status.mode = .notMade(s.unmade ?? "")
        } else {
            switch EQCounter.Mode(rawValue: load(.mode)) ?? .stopped {
            case .stopped: status.mode = .stopped
            case .waiting: status.mode = .waiting
            case .passing: status.mode = .passing
            case .filtering: status.mode = .filtering
            case .crossfading: status.mode = .crossfading
            }
        }
        status.rate = s.rate
        status.channels = s.channels
        if let bank = s.newest {
            status.sections = max(bank.left.count, bank.right.count, bank.shared.count)
            status.newestIdentity = bank.isIdentity
            status.newestKey = bank.key
        }
        status.overs = Int(load(.overs))
        status.largest = Double(bitPattern: load(.largest))
        status.crossfades = Int(load(.crossfades))
        status.waited = Int(load(.waited))
        status.otherRate = Int(load(.otherRate))
        status.refused = Int(load(.refused))
        status.blocks = Int(load(.blocks))
        let seconds = Self.secondsPerTick
        if status.blocks > 0 {
            status.meanSeconds = Double(load(.ticks)) * seconds / Double(status.blocks)
            status.worstSeconds = Double(load(.worst)) * seconds
        }
        status.lastFrames = Int(load(.frames))
        status.renderBlockAsked = Int(load(.asked))
        status.otherOutput = s.otherOutput
        status.older = s.older
        status.allocations = s.allocations
        status.started = s.started
        return status
    }

    /// mach_absolute_time's tick, in seconds.
    static let secondsPerTick: Double = {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return Double(base.numer) / Double(base.denom) / 1e9
    }()

    // MARK: the warm-up (eq.md 1.5)

    /// Once a process, before any unit's first start: the render's entry run off the audio thread - 4,096 frames of
    /// silence, a bank change and its crossfade, through `EQRender.process` on a state of its own - so type metadata
    /// and the code's pages are touched here, never first on the audio thread. (A state's own pages are touched where
    /// `EQRender.make` fills them.)
    static func warm() { _ = warmed }

    private static let warmed: Bool = {
        let frames = 4_096
        let state = EQRender.make(rate: 48_000, channels: 2, maximumFrames: frames)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 2 * frames)
        samples.initialize(repeating: 0, count: 2 * frames)
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        channels[0] = samples
        channels[1] = samples + frames
        let bank = EQBank.make(rate: 48_000, key: "", version: 0, on: true, correction: [],
                               offsets: .zero, bands: [6, 0, 0, 0, 0, 0, 0, 0, 0, -6], preamp: nil).packed
        bank.withUnsafeBufferPointer { (offered: UnsafeBufferPointer<Double>) -> Void in
            EQRender.process(state, buffers: UnsafePointer(channels), frames: frames, offered: nil)
            EQRender.process(state, buffers: UnsafePointer(channels), frames: frames, offered: offered.baseAddress)
            EQRender.process(state, buffers: UnsafePointer(channels), frames: frames, offered: nil)
        }
        channels.deallocate()
        samples.deallocate()
        EQRender.free(state)
        return true
    }()
}

/// The words of the render's counters, in CAudioRing's order. Written by the render after every block, read by
/// `EQHost.status()` - and `asked`, written by the unit's getter as the framework asks for the render block (never
/// on the render), kept across allocations.
enum EQCounter: UInt32 {
    case overs, largest, crossfades, waited, otherRate, refused, mode, blocks, ticks, worst, frames, asked

    static let count: UInt32 = 12

    /// What the unit does now; `waiting`: allocated, and no block rendered yet.
    enum Mode: UInt64 {
        case stopped, passing, filtering, crossfading, waiting
    }
}

/// The EQ unit's state for Debug (eq.md 3.13): in the graph or not, what it does now, at what rate, and what its
/// render counted since the output last started.
public struct EQUnitStatus: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// iOS's words for why the unit couldn't be made
        case notMade(String)
        /// the output is stopped: the unit holds no render memory
        case stopped
        /// the unit's memory is made for a start, and no block has come through it yet - a moment, normally
        case waiting
        case passing
        case filtering
        case crossfading
    }

    /// What the last start put in: the bank's output and whether it was Off, and how long before the output started
    /// (nil: nothing was put in).
    public struct Started: Equatable, Sendable {
        public var key: String?
        public var identity: Bool
        public var secondsBefore: Double?
    }

    public var mode: Mode = .stopped
    public var rate: Double?
    public var channels: Int?
    /// the newest bank's sections a channel (its largest list), its output, and whether it is Off
    public var sections: Int?
    public var newestKey: String?
    public var newestIdentity = true
    public var overs = 0
    public var largest: Double = 0
    public var crossfades = 0
    public var waited = 0
    public var otherRate = 0
    public var refused = 0
    public var blocks = 0
    public var meanSeconds: Double = 0
    public var worstSeconds: Double = 0
    public var lastFrames = 0
    /// banks dropped as for another output, and as older than the last published
    public var otherOutput = 0
    public var older = 0
    /// render memory made, all told (one a start)
    public var allocations = 0
    /// how many times the framework asked this unit for its render block (eq.md 7: whether iOS takes the getter added
    /// through the Objective-C runtime, as macOS does - twice as it is made, once a start)
    public var renderBlockAsked = 0
    public var started: Started?

    public init() {}

    /// The render's counters, as Debug's words take them.
    public var counters: EQRenderCounters {
        var c = EQRenderCounters()
        c.overs = overs
        c.largest = largest
        c.crossfades = crossfades
        c.waited = waited
        c.otherRate = otherRate
        c.refused = refused
        return c
    }

    /// Debug's EQ rows that are the unit's (eq.md 3.13), in 3.13's order: Unit, At this rate, Changes, Started with,
    /// Over full scale, Render - and, after Unit, slice 2's Render block (whether the framework asked for it, eq.md 7).
    /// (Output, Key, Curve and Kept are the settings' - the slices that bring them.)
    public var rows: [EQDebugRow] {
        typealias W = EQWords.Debug
        let unit: String
        switch mode {
        case .notMade(let words): unit = W.notMade(words)
        case .stopped: unit = W.stopped
        case .waiting: unit = W.waiting
        case .passing: unit = W.passing
        case .filtering: unit = W.filtering
        case .crossfading: unit = W.crossfading
        }
        var rows = [EQDebugRow(label: "Unit", value: unit)]
        if case .notMade = mode { return rows }
        rows.append(EQDebugRow(label: "Render block", value: W.renderBlockAsked(renderBlockAsked)))
        guard let rate else {
            rows.append(EQDebugRow(label: "At this rate", value: W.notStarted))
            return rows
        }
        rows.append(EQDebugRow(label: "At this rate", value: W.atRate(rate, sections: sections ?? 0, leftOut: 0)))
        rows.append(EQDebugRow(label: "Changes", value: W.changes(counters)))
        let startedWith: String
        if let started {
            if let seconds = started.secondsBefore {
                let ms = seconds * 1_000
                if started.identity {
                    startedWith = W.startedOff(msBefore: ms)
                } else if started.key == EQTestCurve.key {
                    startedWith = W.startedWithTest(msBefore: ms)
                } else {
                    startedWith = W.startedWith(started.key ?? "", msBefore: ms)
                }
            } else {
                startedWith = W.startedWithNothing
            }
        } else {
            startedWith = W.notStarted
        }
        rows.append(EQDebugRow(label: "Started with", value: startedWith))
        rows.append(EQDebugRow(label: "Over full scale", value: W.overFullScale(counters)))
        if blocks > 0 {
            rows.append(EQDebugRow(label: "Render", value: W.render(
                meanMs: meanSeconds * 1_000, worstMs: worstSeconds * 1_000,
                blockMs: Double(lastFrames) / rate * 1_000, refused: refused)))
        }
        return rows
    }
}

/// One of Debug's rows: its label and its value.
public struct EQDebugRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Slice 2's test curve (eq.md 5.2, 3.13; check 0): a -24 dB high shelf at 2 kHz through the real unit, the same on
/// every output, so a phone with only the engine can hear the unit work. Debug's "Muffle what plays".
public enum EQTestCurve {
    /// the test curve's own output: it doesn't follow the route
    public static let key = "test"

    /// The test curve at `rate` - or, `on` false, Off.
    public static func bank(on: Bool, rate: Double, version: Int) -> EQBank {
        EQBank.make(rate: rate, key: key, version: version, on: on,
                    correction: [EQFilter(id: 1, kind: .highShelf, fc: 2_000, gain: -24)], offsets: .zero,
                    bands: EQGraphic.flat, preamp: nil)
    }
}
#endif
