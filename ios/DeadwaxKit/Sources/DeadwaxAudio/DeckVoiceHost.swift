#if canImport(AVFAudio)
// AVFAudio for UnsafeMutableAudioBufferListPointer: AudioToolbox alone brings it on macOS, not on iOS (the device build)
import AVFAudio
import AudioToolbox
import CAudioRing
import DeadwaxCore

// The deck engine's render (notes/ios-specs/turntable.md 4.3): its state, reached through one pointer made before the
// engine starts, and the one function the source node's block calls. Nothing here allocates, locks, sends an
// Objective-C message or counts a Swift reference: the state is plain numbers and pointers (`_isPOD`, tested), the
// voice is DeckRender's concrete entries over PlatformMaths, and the rings are CAudioRing's. The review rule: this
// file imports CAudioRing, DeadwaxCore and AudioToolbox (for AudioBufferList and AudioTimeStamp, the block's own
// arguments) - nothing else.

/// What the render writes after each block, read by `DeckEngine.status()` (relaxed words; Doubles as their bits).
enum DeckCounter: UInt32, CaseIterable {
    case blocks, frames, messages, windowsReturned, windowsKept, reportsDropped, refused
    /// `L`, the last block's own lead, the largest over the window, the largest under the last sound (bits)
    case lead, latest, target, largestSounding
    /// the voice's now at the last block (bits), and whether the host time was valid (1) - offline it isn't
    case now, hostTime
    /// the EQ (eq.md 1.9): blocks it ran, and its render's counts as the unit's EQCounter has them
    case eqBlocks

    static var count: UInt32 { UInt32(allCases.count) }
}

/// The render's state, one struct behind one pointer. Every field is a number or a pointer.
struct DeckHostState {
    var voice: UnsafeMutablePointer<VoiceState>
    var lead: UnsafeMutablePointer<DeckLead>
    var rate: Double
    var maximumFrames: Int
    /// the two channels' pointers handed to the voice, set from the buffer list each block
    var outputs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    // the rings
    var messages: OpaquePointer
    var slots: UnsafeMutablePointer<DeckSlot>
    var returns: OpaquePointer
    var returned: UnsafeMutablePointer<UInt32>
    var reports: OpaquePointer
    var heard: UnsafeMutablePointer<DeckHeardSlot>
    var counters: OpaquePointer

    /// the window the voice has: its id (0, none)
    var window: UInt32 = 0
    /// a report the full ring refused, folded into the next (its held and peaks summed, its lowest the least)
    var foldHeld = 0.0, foldPeaks = 0.0, foldLowest = 1.0
    var folding = false

    var blocks: UInt64 = 0
    var frames: UInt64 = 0
    var applied: UInt64 = 0
    var windowsReturned: UInt64 = 0
    var windowsKept: UInt64 = 0
    var reportsDropped: UInt64 = 0
    var refused: UInt64 = 0

    // the clock (3.2)
    var secondsPerTick: Double
    /// offline (manual rendering: no host time): now = (sample time + `offlineFrames`) / rate - `offlineLead`
    var offline: Bool
    var offlineFrames: Double = 0
    var offlineLead: Double = 0
    /// the last block's presentation time and length, live: a block whose time stamp has no host time is placed
    /// after it (slice 2's review, question 1) - never on the sample-time clock, a different origin, which would
    /// jump the voice's `now` by the time since boot. -1: no block yet.
    var lastHostOut: Double = -1
    var lastSeconds: Double = 0

    // the EQ after the limiter (eq.md 1.9): its own render state, fed by the deck's EQHost's triple
    var eq: UnsafeMutablePointer<EQRenderState>?
    var eqTriple: OpaquePointer?
    var eqSlots: UnsafeMutablePointer<Double>?
    var eqCounters: OpaquePointer?
    var eqPacked: Int = 0
    var eqBlocks: UInt64 = 0
    /// the EQ's render time, host ticks: all of it and the longest block (slice 2's review, question 6 - the song's
    /// EQUnit counts its own the same way, so Debug's EQ rows read both alike)
    var eqTicks: UInt64 = 0
    var eqWorst: UInt64 = 0

    // Debug's recorder (turntable.md 6.3): every block the voice renders and every message it is told, into rings made
    // with the engine - a block's record and its samples in the slot's own stretch of `tapAudio`. On from a start
    // (`tapOn`, written while stopped, like the rest of this state) until the main side's word in `tapControl` asks it
    // off; a ring full loses the block or the message and counts it, never waits.
    var tapOn = false
    var tapBlocks: UnsafeMutablePointer<DeckTapBlock>?
    var tapAudio: UnsafeMutablePointer<Float>?
    var tapFifo: OpaquePointer?
    var tapMessages: UnsafeMutablePointer<DeckTapMessage>?
    var tapMessageFifo: OpaquePointer?
    var tapControl: OpaquePointer?
    var tapLostBlocks: UInt64 = 0
    var tapLostMessages: UInt64 = 0
    /// the engine's starts, counted by the main side before each (the voice is from rest at every one)
    var starts: UInt64 = 0
}

enum DeckVoiceHost {
    /// One block of the record's sound into `output`, presented at `timestamp`. The voice's now from the clock (3.2),
    /// the messages that came applied at the block's start - each a `voiceCommand`, as the web's worklet applies its
    /// port's between blocks - then the voice, its report, and the EQ after its limiter.
    static func render(_ h: UnsafeMutablePointer<DeckHostState>, _ timestamp: UnsafePointer<AudioTimeStamp>,
                       _ frameCount: UInt32, _ output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let entry = Double(mach_absolute_time()) * h.pointee.secondsPerTick
        let frames = Int(frameCount)
        let counters = h.pointee.counters
        let list = UnsafeMutableAudioBufferListPointer(output)
        let channels = Swift.min(list.count, 2)
        if frames > h.pointee.maximumFrames || channels < 1 {
            h.pointee.refused &+= 1
            audio_counters_store(counters, DeckCounter.refused.rawValue, h.pointee.refused)
            return kAudioUnitErr_TooManyFramesToProcess
        }
        for c in 0..<channels {
            guard let data = list[c].mData else { return kAudioUnitErr_NoConnection }
            h.pointee.outputs[c] = data.assumingMemoryBound(to: Float.self)
            list[c].mDataByteSize = UInt32(frames * MemoryLayout<Float>.stride)
        }
        let rate = h.pointee.rate
        let voice = h.pointee.voice

        // the recorder's tap: on until the main side's word says off
        var tapping = false
        if h.pointee.tapOn, let control = h.pointee.tapControl {
            if audio_counters_load(control, 0) == 0 { h.pointee.tapOn = false } else { tapping = true }
        }
        let windowBefore = h.pointee.window
        var told: UInt32 = 0
        var blockLead = 0.0

        // the clock: the voice's now, `L` behind the block's presentation
        let now: Double
        let stamp = timestamp.pointee
        let hostValid = stamp.mFlags.contains(.hostTimeValid) && stamp.mHostTime != 0
        if h.pointee.offline {
            now = (stamp.mSampleTime + h.pointee.offlineFrames) / rate - h.pointee.offlineLead
        } else if hostValid {
            let hostOut = Double(stamp.mHostTime) * h.pointee.secondsPerTick
            let lead = h.pointee.lead.pointee.block(hostOut: hostOut, frames: frames, rate: rate, entry: entry,
                                                     sounding: DeckRender.sounding(voice))
            now = hostOut - lead
            blockLead = lead
            h.pointee.lastHostOut = hostOut
            h.pointee.lastSeconds = Double(frames) / rate
        } else {
            // no host time on this block (slice 2's review, question 1): it is placed straight after the last one, at
            // the `L` the clock has - the lead isn't fed a guess. With no block before it, where a block entered now
            // would be presented: `L` ahead of the entry, so `now` is the entry itself.
            let lead = h.pointee.lead.pointee.value
            let hostOut = h.pointee.lastHostOut >= 0 ? h.pointee.lastHostOut + h.pointee.lastSeconds : entry + lead
            now = hostOut - lead
            blockLead = lead
            h.pointee.lastHostOut = hostOut
            h.pointee.lastSeconds = Double(frames) / rate
        }

        // the messages, in order
        var slot: UInt32 = 0
        while audio_fifo_peek(h.pointee.messages, &slot) {
            let message = h.pointee.slots + Int(slot)
            if message.pointee.replacesWindow {
                let old = h.pointee.window
                h.pointee.window = message.pointee.tag == DeckSlot.Tag.window.rawValue ? message.pointee.id : 0
                if old != 0 && old != h.pointee.window { giveBack(h, old) }
            }
            DeckRender.command(voice, message.pointee.message, now: now, rate: rate)
            if tapping { tapMessage(h, message.pointee) }
            told &+= 1
            audio_fifo_release(h.pointee.messages)
            h.pointee.applied &+= 1
        }

        // the voice
        let outputs = UnsafeMutableBufferPointer(start: h.pointee.outputs, count: channels)
        DeckRender.render(voice, outputs, frames: frames, rate: rate, now: now)
        if let heard = DeckRender.report(voice, frames: frames, rate: rate, now: now) { tell(h, heard) }
        if tapping {
            var record = DeckTapBlock()
            record.block = h.pointee.blocks
            record.starts = h.pointee.starts
            record.frames = frameCount
            record.channels = UInt32(channels)
            record.rate = rate
            record.now = now
            record.lead = blockLead
            record.hostTime = hostValid ? stamp.mHostTime : 0
            record.sampleTime = stamp.mSampleTime
            record.windowBefore = windowBefore
            record.window = h.pointee.window
            record.messages = told
            record.pos = voice.pointee.pos
            tapBlock(h, &record, frames: frames, channels: channels)
        }

        // the EQ, after the limiter: the newest bank offered at the block's start (eq.md 1.6)
        if let eq = h.pointee.eq, let triple = h.pointee.eqTriple, let slots = h.pointee.eqSlots {
            let offered: UnsafePointer<Double>? = audio_triple_take(triple)
                ? UnsafePointer(slots + Int(audio_triple_front(triple)) * h.pointee.eqPacked) : nil
            let began = mach_absolute_time()
            EQRender.process(eq, buffers: UnsafePointer(h.pointee.outputs), frames: frames, offered: offered)
            let took = mach_absolute_time() &- began
            h.pointee.eqBlocks &+= 1
            h.pointee.eqTicks &+= took
            if took > h.pointee.eqWorst { h.pointee.eqWorst = took }
            if let eqCounters = h.pointee.eqCounters {
                storeEQ(eq, eqCounters, h.pointee.eqBlocks, frames, ticks: h.pointee.eqTicks, worst: h.pointee.eqWorst)
            }
        }

        h.pointee.blocks &+= 1
        h.pointee.frames &+= UInt64(frames)
        let lead = h.pointee.lead.pointee
        audio_counters_store(counters, DeckCounter.blocks.rawValue, h.pointee.blocks)
        audio_counters_store(counters, DeckCounter.frames.rawValue, h.pointee.frames)
        audio_counters_store(counters, DeckCounter.messages.rawValue, h.pointee.applied)
        audio_counters_store(counters, DeckCounter.lead.rawValue, lead.value.bitPattern)
        audio_counters_store(counters, DeckCounter.latest.rawValue, lead.latest.bitPattern)
        audio_counters_store(counters, DeckCounter.target.rawValue, lead.target.bitPattern)
        audio_counters_store(counters, DeckCounter.largestSounding.rawValue, lead.largestSounding.bitPattern)
        audio_counters_store(counters, DeckCounter.now.rawValue, now.bitPattern)
        audio_counters_store(counters, DeckCounter.hostTime.rawValue, hostValid ? 1 : 0)
        audio_counters_store(counters, DeckCounter.eqBlocks.rawValue, h.pointee.eqBlocks)
        return noErr
    }

    /// The recorder's: a block's record and its samples (the voice's, before the EQ) into the tap ring - or, full, lost
    /// and counted.
    static func tapBlock(_ h: UnsafeMutablePointer<DeckHostState>, _ record: inout DeckTapBlock, frames: Int, channels: Int) {
        guard let fifo = h.pointee.tapFifo, let blocks = h.pointee.tapBlocks, let audio = h.pointee.tapAudio else { return }
        var slot: UInt32 = 0
        guard audio_fifo_reserve(fifo, &slot) else {
            h.pointee.tapLostBlocks &+= 1
            return
        }
        let stride = h.pointee.maximumFrames
        let to = audio + Int(slot) * 2 * stride
        var peak: Float = 0
        for c in 0..<2 {
            let from = h.pointee.outputs[Swift.min(c, channels - 1)]
            let into = to + c * stride
            for i in 0..<frames {
                let v = from[i]
                into[i] = v
                let size = v < 0 ? -v : v
                if size > peak { peak = size }
            }
        }
        record.peak = peak
        record.lostBlocks = h.pointee.tapLostBlocks
        record.lostMessages = h.pointee.tapLostMessages
        blocks[Int(slot)] = record
        audio_fifo_commit(fifo)
    }

    /// The recorder's: a message as the voice was told it, before which block - or, the ring full, lost and counted.
    static func tapMessage(_ h: UnsafeMutablePointer<DeckHostState>, _ message: DeckSlot) {
        guard let fifo = h.pointee.tapMessageFifo, let messages = h.pointee.tapMessages else { return }
        var slot: UInt32 = 0
        guard audio_fifo_reserve(fifo, &slot) else {
            h.pointee.tapLostMessages &+= 1
            return
        }
        messages[Int(slot)] = DeckTapMessage(block: h.pointee.blocks, slot: message)
        audio_fifo_commit(fifo)
    }

    /// A window the voice let go of, back to the main side - or, the ring full, kept (leaked until the engine stops,
    /// counted) rather than freed here.
    static func giveBack(_ h: UnsafeMutablePointer<DeckHostState>, _ id: UInt32) {
        var slot: UInt32 = 0
        if audio_fifo_reserve(h.pointee.returns, &slot) {
            h.pointee.returned[Int(slot)] = id
            audio_fifo_commit(h.pointee.returns)
            h.pointee.windowsReturned &+= 1
            audio_counters_store(h.pointee.counters, DeckCounter.windowsReturned.rawValue, h.pointee.windowsReturned)
        } else {
            h.pointee.windowsKept &+= 1
            audio_counters_store(h.pointee.counters, DeckCounter.windowsKept.rawValue, h.pointee.windowsKept)
        }
    }

    /// A report out - or, the ring full, folded into the next one, so a held or a peak is never lost (4.3's
    /// "overwritten" can't be done by the producer of a single-producer queue without racing its consumer).
    static func tell(_ h: UnsafeMutablePointer<DeckHostState>, _ report: VoiceHeard) {
        var heard = report
        if h.pointee.folding {
            heard.held += h.pointee.foldHeld
            heard.peaks += h.pointee.foldPeaks
            heard.lowest = Swift.min(heard.lowest, h.pointee.foldLowest)
        }
        var slot: UInt32 = 0
        if audio_fifo_reserve(h.pointee.reports, &slot) {
            h.pointee.heard[Int(slot)].heard = heard
            h.pointee.heard[Int(slot)].block = h.pointee.blocks
            audio_fifo_commit(h.pointee.reports)
            h.pointee.folding = false
            h.pointee.foldHeld = 0
            h.pointee.foldPeaks = 0
            h.pointee.foldLowest = 1
        } else {
            h.pointee.folding = true
            h.pointee.foldHeld = heard.held
            h.pointee.foldPeaks = heard.peaks
            h.pointee.foldLowest = heard.lowest
            h.pointee.reportsDropped &+= 1
            audio_counters_store(h.pointee.counters, DeckCounter.reportsDropped.rawValue, h.pointee.reportsDropped)
        }
    }

    /// The EQ's render counts, where the deck's EQHost reads them (as EQUnit's render writes them).
    static func storeEQ(_ eq: UnsafeMutablePointer<EQRenderState>, _ counters: OpaquePointer, _ blocks: UInt64,
                        _ frames: Int, ticks: UInt64, worst: UInt64) {
        let counted = eq.pointee.counters
        audio_counters_store(counters, EQCounter.overs.rawValue, UInt64(counted.overs))
        audio_counters_store(counters, EQCounter.largest.rawValue, counted.largest.bitPattern)
        audio_counters_store(counters, EQCounter.crossfades.rawValue, UInt64(counted.crossfades))
        audio_counters_store(counters, EQCounter.waited.rawValue, UInt64(counted.waited))
        audio_counters_store(counters, EQCounter.otherRate.rawValue, UInt64(counted.otherRate))
        audio_counters_store(counters, EQCounter.refused.rawValue, UInt64(counted.refused))
        let passes = eq.pointee.passesThrough
        let mode: EQCounter.Mode = passes ? .passing : (eq.pointee.isCrossfading ? .crossfading : .filtering)
        audio_counters_store(counters, EQCounter.mode.rawValue, mode.rawValue)
        audio_counters_store(counters, EQCounter.blocks.rawValue, blocks)
        audio_counters_store(counters, EQCounter.ticks.rawValue, ticks)
        audio_counters_store(counters, EQCounter.worst.rawValue, worst)
        audio_counters_store(counters, EQCounter.frames.rawValue, UInt64(frames))
    }
}
#endif
