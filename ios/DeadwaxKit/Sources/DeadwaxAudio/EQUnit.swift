#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAudioRing
import DeadwaxCore
import Foundation

/// The EQ (notes/ios-specs/eq.md 1.2): an in-process AUAudioUnit between the main mixer and the output, one input bus
/// and one output bus of the same format - Float32, non-interleaved, any rate, 1 to 8 channels. Registered once a
/// process with `AUAudioUnit.registerSubclass`, so it needs no app extension, and made as
/// `AVAudioUnitEffect(audioComponentDescription:)` (`EQUnit.node()`).
///
/// - Its curve comes through its host's ring (`EQHost`), never as AU parameters (no AUParameterTree: Objective-C
///   observation has no place on the render). `shouldBypassEffect` and AVAudioUnitEffect's `bypass` are never set:
///   the identity bank is its bypass, every sample passed through untouched (1.7).
/// - `latency` 0 (IIR filters have none), `tailTime` 0 (a pause stops the output at once; a ring-out would be cut
///   with the song's own last samples either way), `canProcessInPlace`.
/// - Its render memory is made in `allocateRenderResources` (off the audio thread: AVAudioEngine allocates at
///   prepare and start, and its stop releases, so every start allocates afresh) for `maximumFramesToRender` - set to
///   4,096 before allocation (`PlaybackEngine.configure`) - and a block larger than that is answered
///   `kAudioUnitErr_TooManyFramesToProcess`, counted, never overrun.
/// - Its render block is made once, here in `init`, capturing only a pointer to a header made here too and never
///   moved; the header points at what each allocation makes. What the block runs (`EQUnitRender.render`) allocates
///   nothing, takes no lock, sends no Objective-C message and reads no Swift class, global or static - 1.5's rules.
/// - **That block is an Objective-C block whose pull is one too** (`EQRenderBlock`), handed to the framework by an
///   `internalRenderBlock` getter added through the Objective-C runtime at registration - not a Swift
///   `override var internalRenderBlock`. A Swift override returns a Swift closure, which the framework gets wrapped in
///   a block that turns its pull block into a Swift closure on every call: one allocation and one free a render, measured
///   (EQRealTimeTests.theRenderAllocatesNothing, release; a stored `@convention(block)` returned from the override
///   made three). Here the pull arrives as the block it is and is called as one. What a render costs beyond the
///   arithmetic: one swift_retain/release of the closure's context and one _Block_copy/_Block_release of the
///   framework's pull (a heap block, measured) - atomic counts on objects that outlive the call, no allocation, no
///   lock and no message (EQRealTimeTests.theFrameworksOwnRenderAllocatesNothing, through AVAudioEngine's own
///   real-time render).
public final class EQUnit: AUAudioUnit {
    /// `aufx` / `dweq` / `Dwax` (Apple keeps all-lowercase manufacturer codes for itself).
    public static let component = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: fourCharacters("dweq"),
        componentManufacturer: fourCharacters("Dwax"), componentFlags: 0, componentFlagsMask: 0)

    /// The largest block the render takes: what iOS renders with the screen locked.
    public static let maximumFrames: AUAudioFrameCount = 4_096

    private static let registered: Bool = {
        // the getter the framework asks for the render block: this unit's own block, as it was made, the ask counted.
        // Asked through -[AUAudioUnit renderBlock], never on the render: as the unit is made, as AVAudioEngine attaches
        // it, and at each allocation (measured, eq.md's "Slice 2, built", Review). Its type encoding is AUAudioUnit's
        // own getter's.
        let selector = #selector(getter: AUAudioUnit.internalRenderBlock)
        let getter: @convention(block) (EQUnit) -> AnyObject = { (unit: EQUnit) -> AnyObject in unit.renderBlockAsked() }
        guard let inherited = class_getInstanceMethod(AUAudioUnit.self, selector) else {
            preconditionFailure("AUAudioUnit has no internalRenderBlock getter")
        }
        let added = class_addMethod(EQUnit.self, selector, imp_implementationWithBlock(getter),
                                    method_getTypeEncoding(inherited))
        precondition(added, "EQUnit's render block getter couldn't be added")
        AUAudioUnit.registerSubclass(EQUnit.self, as: component, name: "deadwax: EQ", version: 1)
        return true
    }()

    /// Registers the subclass, once a process.
    public static func register() { _ = registered }

    /// The unit as AVAudioEngine hosts it: `AVAudioUnitEffect(audioComponentDescription:)`, synchronous, which hands back
    /// this subclass in-process (eq.md 1.7, EQEngineTests.theUnitIsOurs). If it ever doesn't, the fallback 1.2 names:
    /// `AVAudioUnit.instantiate(with:options:)` (`.loadInProcess` on macOS), waited for at most a second.
    public static func node() throws -> AVAudioUnit {
        register()
        let effect = AVAudioUnitEffect(audioComponentDescription: component)
        if effect.auAudioUnit is EQUnit { return effect }
        let done = DispatchSemaphore(value: 0)
        let answer = Answer()
        // `.loadInProcess` is macOS's alone; iOS has no such option, and a subclass registered in this process is made
        // in it either way
        #if os(macOS)
        let options: AudioComponentInstantiationOptions = .loadInProcess
        #else
        let options: AudioComponentInstantiationOptions = []
        #endif
        AVAudioUnit.instantiate(with: component, options: options) { (unit: AVAudioUnit?, error: Error?) -> Void in
            answer.set(unit, error)
            done.signal()
        }
        guard done.wait(timeout: .now() + 1) == .success else {
            throw AudioFailure("iOS took more than a second to make the EQ.")
        }
        let (unit, error) = answer.get()
        guard let unit, unit.auAudioUnit is EQUnit else {
            throw AudioFailure(error?.localizedDescription ?? "iOS made another kind of unit for the EQ.")
        }
        return unit
    }

    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var unit: AVAudioUnit?
        private var error: Error?
        func set(_ unit: AVAudioUnit?, _ error: Error?) {
            lock.withLock { () -> Void in
                self.unit = unit
                self.error = error
            }
        }
        func get() -> (AVAudioUnit?, Error?) { lock.withLock { (unit, error) } }
    }

    private let header: UnsafeMutablePointer<EQUnitHeader>
    /// the render block (`EQRenderBlock`), kept as the object the getter hands out
    let renderObject: AnyObject
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    /// Where banks come from and counters go: attached before the unit is first allocated.
    private(set) var host: EQHost?

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        // the getter must be in place before the framework first asks this unit for its block
        Self.register()
        let header = UnsafeMutablePointer<EQUnitHeader>.allocate(capacity: 1)
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: EQLimits.channels)
        // never read before a block's own pointers are written into it; something valid meanwhile
        channels.initialize(repeating: UnsafeMutablePointer(bitPattern: 0x10)!, count: EQLimits.channels)
        header.initialize(to: EQUnitHeader(
            channels: channels, packedCount: EQBank.packedCount,
            buffersOffset: MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) ?? 8))
        self.header = header
        let render: EQRenderBlock = { flags, timestamp, frames, _, output, _, pull in
            EQUnitRender.render(header, flags, timestamp, frames, output, pull)
        }
        // a block is an Objective-C object: kept, and handed out, as one
        renderObject = unsafeBitCast(render, to: AnyObject.self)
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = AUAudioChannelCount(EQLimits.channels)
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.maximumChannelCount = AUAudioChannelCount(EQLimits.channels)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = Self.maximumFrames
    }

    deinit {
        freeRenderMemory()
        header.pointee.channels.deallocate()
        header.deinitialize(count: 1)
        header.deallocate()
    }

    /// The host this unit renders for: its ring, its slots and its counters. Before the first allocation. The asks
    /// for the render block so far (the framework's first is as the unit is made) go into the host's count, which
    /// is this unit's from now on.
    func attach(_ host: EQHost) {
        self.host = host
        header.pointee.triple = host.triple
        header.pointee.slots = host.slots
        header.pointee.counters = host.counters
        audio_counters_store(host.counters, EQCounter.asked.rawValue, header.pointee.asked)
    }

    /// The getter's work (never on the render): the block, the ask counted - Debug's "Render block" row says whether
    /// iOS asks for it as macOS does (eq.md 7).
    fileprivate func renderBlockAsked() -> AnyObject {
        header.pointee.asked &+= 1
        if let counters = header.pointee.counters {
            audio_counters_store(counters, EQCounter.asked.rawValue, header.pointee.asked)
        }
        return renderObject
    }

    public override var inputBusses: AUAudioUnitBusArray { inputs }
    public override var outputBusses: AUAudioUnitBusArray { outputs }
    public override var canProcessInPlace: Bool { true }
    public override var latency: TimeInterval { 0 }
    public override var tailTime: TimeInterval { 0 }
    /// As many channels out as in, any number.
    public override var channelCapabilities: [NSNumber]? { [-1, -1] }

    /// Float32, non-interleaved, 1 to 8 channels, any rate - and AUAudioUnit's own rule (not while allocated).
    public override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              (1...AVAudioChannelCount(EQLimits.channels)).contains(format.channelCount), format.sampleRate > 0 else {
            return false
        }
        return super.shouldChange(to: format, for: bus)
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let input = inputBus.format, output = outputBus.format
        guard input.channelCount == output.channelCount, input.sampleRate == output.sampleRate,
              (1...AVAudioChannelCount(EQLimits.channels)).contains(output.channelCount) else {
            super.deallocateRenderResources()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        freeRenderMemory()
        // never less than iOS's locked-screen block, whatever a host left the property at
        let frames = Int(max(maximumFramesToRender, Self.maximumFrames))
        let channels = Int(output.channelCount)
        let own = UnsafeMutablePointer<Float>.allocate(capacity: channels * frames)
        own.initialize(repeating: 0, count: channels * frames)
        let h = header
        h.pointee.state = EQRender.make(rate: output.sampleRate, channels: channels, maximumFrames: frames)
        h.pointee.own = own
        h.pointee.maximumFrames = frames
        h.pointee.channelCount = channels
        h.pointee.blocks = 0
        h.pointee.ticks = 0
        h.pointee.worst = 0
        host?.allocated(rate: output.sampleRate, channels: channels)
    }

    public override func deallocateRenderResources() {
        freeRenderMemory()
        host?.deallocated()
        super.deallocateRenderResources()
    }

    /// The render's memory let go (the render isn't running).
    private func freeRenderMemory() {
        if let state = header.pointee.state { EQRender.free(state) }
        header.pointee.state = nil
        header.pointee.own?.deallocate()
        header.pointee.own = nil
    }

    private static func fourCharacters(_ code: String) -> FourCharCode {
        code.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

/// `AURenderPullInputBlock` as the framework hands it: an Objective-C block, called as one.
typealias EQPullBlock = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                            UnsafePointer<AudioTimeStamp>, AUAudioFrameCount, Int,
                                            UnsafeMutablePointer<AudioBufferList>) -> AUAudioUnitStatus

/// `AUInternalRenderBlock` as the framework calls it - the same arguments, an Objective-C block taking the pull as an
/// Objective-C block, so nothing is converted on a call.
typealias EQRenderBlock = @convention(block) (UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                              UnsafePointer<AudioTimeStamp>, AUAudioFrameCount, Int,
                                              UnsafeMutablePointer<AudioBufferList>, UnsafePointer<AURenderEvent>?,
                                              EQPullBlock?) -> AUAudioUnitStatus

/// What the render block reaches (eq.md 1.2): made in the unit's init, freed in its deinit, never moved. Its pointers
/// are to what `allocateRenderResources` made and to the host's ring - never to a Swift object.
struct EQUnitHeader {
    /// the render's memory, while allocated
    var state: UnsafeMutablePointer<EQRenderState>?
    /// each channel's samples for the block, as `EQRender.process` takes them (8, made in init)
    var channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    /// the unit's own buffers (channels x maximumFrames), for a host that hands none
    var own: UnsafeMutablePointer<Float>?
    var maximumFrames = 0
    var channelCount = 0
    /// the host's ring, slots and counters
    var triple: OpaquePointer?
    var slots: UnsafeMutablePointer<Double>?
    var counters: OpaquePointer?
    /// `EQBank.packedCount`, copied: the render reads no static
    var packedCount: Int
    /// where `mBuffers` starts in an AudioBufferList
    var buffersOffset: Int
    /// the render's own timing since the allocation, in mach ticks
    var blocks: UInt64 = 0
    var ticks: UInt64 = 0
    var worst: UInt64 = 0
    /// how many times the framework asked for the render block (the getter, never the render)
    var asked: UInt64 = 0

    init(channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, packedCount: Int, buffersOffset: Int) {
        self.channels = channels
        self.packedCount = packedCount
        self.buffersOffset = buffersOffset
    }
}

/// The render (eq.md 1.5-1.7). One entry, concrete, over pointers: pull the mixer's samples into the output buffers,
/// take the newest bank from the ring, run `EQRender.process` on them in place, write the counters. With the identity
/// live and no crossfade running, `process` only reads the last two samples of each channel: what the mixer rendered
/// is what goes out, untouched.
enum EQUnitRender {
    static func render(_ h: UnsafeMutablePointer<EQUnitHeader>,
                       _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                       _ timestamp: UnsafePointer<AudioTimeStamp>, _ frameCount: AUAudioFrameCount,
                       _ output: UnsafeMutablePointer<AudioBufferList>,
                       _ pull: EQPullBlock?) -> AUAudioUnitStatus {
        guard let state = h.pointee.state, let triple = h.pointee.triple, let slots = h.pointee.slots,
              let counters = h.pointee.counters else { return kAudioUnitErr_Uninitialized }
        let frames = Int(frameCount)
        let channels = h.pointee.channelCount
        if frames > h.pointee.maximumFrames {
            // counted by the render's own counters; nothing pulled, nothing touched
            EQRender.process(state, buffers: UnsafePointer(h.pointee.channels), frames: frames, offered: nil)
            audio_counters_store(counters, EQCounter.refused.rawValue, UInt64(state.pointee.counters.refused))
            return kAudioUnitErr_TooManyFramesToProcess
        }
        guard let pull else { return kAudioUnitErr_NoConnection }
        guard Int(output.pointee.mNumberBuffers) == channels else { return kAudioUnitErr_FormatNotSupported }
        let buffers = (UnsafeMutableRawPointer(output) + h.pointee.buffersOffset).assumingMemoryBound(to: AudioBuffer.self)
        let bytes = UInt32(frames * MemoryLayout<Float>.stride)
        for c in 0..<channels {
            // no buffer handed: the unit's own, and the pull renders there - in place either way
            if buffers[c].mData == nil, let own = h.pointee.own {
                buffers[c].mData = UnsafeMutableRawPointer(own + c * h.pointee.maximumFrames)
            }
            buffers[c].mDataByteSize = bytes
        }
        let pulled = pull(flags, timestamp, frameCount, 0, output)
        if pulled != noErr { return pulled }
        for c in 0..<channels {
            guard let data = buffers[c].mData else { return kAudioUnitErr_NoConnection }
            h.pointee.channels[c] = data.assumingMemoryBound(to: Float.self)
        }
        let offered: UnsafePointer<Double>? = audio_triple_take(triple)
            ? UnsafePointer(slots + Int(audio_triple_front(triple)) * h.pointee.packedCount) : nil

        let began = mach_absolute_time()
        EQRender.process(state, buffers: UnsafePointer(h.pointee.channels), frames: frames, offered: offered)
        let took = mach_absolute_time() &- began

        let passes = state.pointee.passesThrough
        if !passes {
            // filtering: a silent input still has the filters' ring-out after it, so the mixer's "silence" no longer holds
            flags.pointee = AudioUnitRenderActionFlags(
                rawValue: flags.pointee.rawValue & ~AudioUnitRenderActionFlags.unitRenderAction_OutputIsSilence.rawValue)
        }
        h.pointee.blocks &+= 1
        h.pointee.ticks &+= took
        if took > h.pointee.worst { h.pointee.worst = took }

        let counted = state.pointee.counters
        audio_counters_store(counters, EQCounter.overs.rawValue, UInt64(counted.overs))
        audio_counters_store(counters, EQCounter.largest.rawValue, counted.largest.bitPattern)
        audio_counters_store(counters, EQCounter.crossfades.rawValue, UInt64(counted.crossfades))
        audio_counters_store(counters, EQCounter.waited.rawValue, UInt64(counted.waited))
        audio_counters_store(counters, EQCounter.otherRate.rawValue, UInt64(counted.otherRate))
        audio_counters_store(counters, EQCounter.refused.rawValue, UInt64(counted.refused))
        let mode: EQCounter.Mode = passes ? .passing : (state.pointee.isCrossfading ? .crossfading : .filtering)
        audio_counters_store(counters, EQCounter.mode.rawValue, mode.rawValue)
        audio_counters_store(counters, EQCounter.blocks.rawValue, h.pointee.blocks)
        audio_counters_store(counters, EQCounter.ticks.rawValue, h.pointee.ticks)
        audio_counters_store(counters, EQCounter.worst.rawValue, h.pointee.worst)
        audio_counters_store(counters, EQCounter.frames.rawValue, UInt64(frames))
        return noErr
    }
}
#endif
