#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation

/// A song decoded while it arrives: its bytes through AudioFileStream (which finds the packets)
/// and AudioConverter (which decodes them) into Float32 at the file's own rate - the same path
/// AudioStreaming takes for FLAC (AudioFileStreamProcessor.swift), without its 44.1 kHz output.
///
/// It pulls: each `read` parses as many of the bytes that have arrived as it needs, so a reader
/// can start at the top of a song still being fetched (a seek waits for its bytes, decoding and
/// dropping the frames before it). Used from the engine's queue only.
public final class StreamSource: PCMSource {
    private let bytes: ByteSource
    private var offset = 0
    private var exhausted = false
    private var flushed = false
    private var stream: AudioFileStreamID?
    private var converter: AudioConverterRef?
    private var sourceFormat = AudioStreamBasicDescription()
    private var haveFormat = false
    private var cookie: [UInt8]?
    private var packets: [Chunk] = []
    private var head = 0
    /// Where to start, and the frames before it still to drop - its frame at the file's own rate,
    /// known once the stream's header has arrived.
    private let start: StartPoint
    private var skip: AVAudioFramePosition = 0
    private var ended = false
    public private(set) var format: AVAudioFormat?

    /// The packet handed to the converter, kept alive until its next input call.
    private var held: UnsafeMutableRawPointer?
    private var heldCapacity = 0
    private let heldDescription = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)

    struct Chunk {
        let data: Data
        let packets: UInt32
        let description: AudioStreamPacketDescription?
    }

    static let chunkBytes = 64 * 1024
    /// The input proc's "nothing more yet": the converter returns what it decoded so far.
    static let needMore: OSStatus = 0x6D6F_7265 // 'more'
    /// The input proc's "the bytes stopped": the fetch failed.
    static let broken: OSStatus = 0x6272_6B6E // 'brkn'

    public init(bytes: ByteSource, typeHint: AudioFileTypeID, start: StartPoint = .beginning) throws {
        self.bytes = bytes
        self.start = start
        let context = Unmanaged.passUnretained(self).toOpaque()
        var opened: AudioFileStreamID?
        let status = AudioFileStreamOpen(context, streamPropertyListener, streamPacketsListener, typeHint, &opened)
        guard status == noErr, let opened else {
            throw AudioFailure("iOS couldn't start reading the stream (AudioFileStreamOpen \(status)).")
        }
        stream = opened
    }

    deinit {
        close()
        heldDescription.deallocate()
    }

    public func close() {
        if let stream { _ = AudioFileStreamClose(stream) }
        stream = nil
        if let converter { _ = AudioConverterDispose(converter) }
        converter = nil
        held?.deallocate()
        held = nil
        heldCapacity = 0
    }

    // MARK: reading

    public func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        if ended { return .end }
        if !haveFormat {
            while !haveFormat, parseMore() {}
            if !haveFormat {
                if let failure = bytes.failure { throw AudioFailure(failure) }
                if exhausted { throw AudioFailure("iOS couldn't find audio it can play in this file.") }
                return .waiting
            }
        }
        if converter == nil { try makeConverter() }
        guard let converter, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else {
            throw AudioFailure("No memory for a buffer of \(maxFrames) frames.")
        }
        // a few tries, so a seek's dropped frames don't come back as an empty read
        for _ in 0..<64 {
            buffer.frameLength = maxFrames
            var frames = maxFrames
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = AudioConverterFillComplexBuffer(converter, converterInput, context, &frames,
                                                         buffer.mutableAudioBufferList, nil)
            if status == Self.broken {
                throw AudioFailure(bytes.failure ?? "The song stopped arriving.")
            }
            if status != noErr && status != Self.needMore {
                throw AudioFailure("iOS couldn't decode this song (AudioConverter \(status)).")
            }
            buffer.frameLength = frames
            compact()
            if frames == 0 {
                if status == noErr {
                    ended = true
                    return .end
                }
                return .waiting
            }
            if skip > 0 {
                let dropped = min(AVAudioFramePosition(frames), skip)
                skip -= dropped
                if dropped == AVAudioFramePosition(frames) { continue }
                drop(Int(dropped), from: buffer)
            }
            return .frames(buffer)
        }
        return .waiting
    }

    private func drop(_ count: Int, from buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let kept = Int(buffer.frameLength) - count
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            _ = memmove(samples, samples.advanced(by: count), kept * MemoryLayout<Float>.size)
        }
        buffer.frameLength = AVAudioFrameCount(kept)
    }

    /// Parses the next chunk of the bytes that have arrived. False when there were none.
    @discardableResult
    private func parseMore() -> Bool {
        guard let stream else { return false }
        let complete = bytes.isComplete
        let data = bytes.bytes(at: offset, count: Self.chunkBytes)
        if data.isEmpty {
            if complete || bytes.failure != nil {
                exhausted = true
                if !flushed {
                    // the end of the stream: one call with no data flushes the last packet (FLAC's
                    // packets end at the next sync word, so the last one waits for this)
                    flushed = true
                    _ = AudioFileStreamParseBytes(stream, 0, nil, [])
                    return true
                }
            }
            return false
        }
        offset += data.count
        data.withUnsafeBytes { raw in
            _ = AudioFileStreamParseBytes(stream, UInt32(raw.count), raw.baseAddress, [])
        }
        return true
    }

    private func compact() {
        if head > 256, head * 2 > packets.count {
            packets.removeFirst(head)
            head = 0
        }
    }

    private func makeConverter() throws {
        let channels = AVAudioChannelCount(sourceFormat.mChannelsPerFrame)
        guard channels == 1 || channels == 2 else {
            throw AudioFailure("This song has \(channels) channels; Phase 0 plays mono and stereo only.")
        }
        guard let out = floatFormat(sampleRate: sourceFormat.mSampleRate, channels: channels) else {
            throw AudioFailure("iOS has no float format for \(sourceFormat.mSampleRate) Hz.")
        }
        var input = sourceFormat
        var output = out.streamDescription.pointee
        var made: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &made)
        guard status == noErr, let made else {
            throw AudioFailure("iOS can't decode this kind of file (AudioConverterNew \(status)).")
        }
        if var cookie, !cookie.isEmpty {
            _ = AudioConverterSetProperty(made, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), &cookie)
        }
        converter = made
        format = out
        skip = start.frame(at: sourceFormat.mSampleRate)
    }

    // MARK: AudioFileStream's callbacks

    fileprivate func property(_ stream: AudioFileStreamID, _ id: AudioFileStreamPropertyID) {
        guard id == kAudioFileStreamProperty_ReadyToProducePackets else { return }
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr else { return }
        sourceFormat = description
        var cookieSize: UInt32 = 0
        if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, nil) == noErr,
           cookieSize > 0 {
            var bytes = [UInt8](repeating: 0, count: Int(cookieSize))
            if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &bytes) == noErr {
                cookie = Array(bytes.prefix(Int(cookieSize)))
            }
        }
        haveFormat = true
    }

    fileprivate func received(bytes count: UInt32, packets packetCount: UInt32, data: UnsafeRawPointer,
                              descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        if let descriptions {
            for index in 0..<Int(packetCount) {
                var description = descriptions[index]
                let start = Int(description.mStartOffset)
                let size = Int(description.mDataByteSize)
                guard size > 0, start + size <= Int(count) else { continue }
                description.mStartOffset = 0
                packets.append(Chunk(data: Data(bytes: data.advanced(by: start), count: size), packets: 1,
                                     description: description))
            }
        } else {
            // constant bytes per packet (PCM): the bytes as they came, as many packets as they hold
            let per = Int(sourceFormat.mBytesPerPacket)
            guard per > 0 else { return }
            let whole = (Int(count) / per) * per
            guard whole > 0 else { return }
            packets.append(Chunk(data: Data(bytes: data, count: whole), packets: UInt32(whole / per), description: nil))
        }
    }

    // MARK: AudioConverter's input

    fileprivate func supply(_ ioPackets: UnsafeMutablePointer<UInt32>, _ ioData: UnsafeMutablePointer<AudioBufferList>,
                            _ outDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        while head >= packets.count, parseMore() {}
        guard head < packets.count else {
            ioPackets.pointee = 0
            if exhausted, bytes.failure != nil, !bytes.isComplete { return Self.broken }
            return exhausted ? noErr : Self.needMore
        }
        let chunk = packets[head]
        head += 1
        if heldCapacity < chunk.data.count {
            held?.deallocate()
            held = UnsafeMutableRawPointer.allocate(byteCount: chunk.data.count, alignment: 16)
            heldCapacity = chunk.data.count
        }
        guard let held else { return Self.broken }
        chunk.data.copyBytes(to: held.assumingMemoryBound(to: UInt8.self), count: chunk.data.count)
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = held
        ioData.pointee.mBuffers.mDataByteSize = UInt32(chunk.data.count)
        ioData.pointee.mBuffers.mNumberChannels = sourceFormat.mChannelsPerFrame
        ioPackets.pointee = chunk.packets
        if let description = chunk.description {
            heldDescription.pointee = description
            outDescription?.pointee = heldDescription
        } else {
            outDescription?.pointee = nil
        }
        return noErr
    }
}

// The C callbacks: they can't capture, so the source rides in the context pointer.

private func streamPropertyListener(_ context: UnsafeMutableRawPointer, _ stream: AudioFileStreamID,
                                    _ property: AudioFileStreamPropertyID,
                                    _ flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    Unmanaged<StreamSource>.fromOpaque(context).takeUnretainedValue().property(stream, property)
}

private func streamPacketsListener(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32,
                                   _ data: UnsafeRawPointer,
                                   _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
    Unmanaged<StreamSource>.fromOpaque(context).takeUnretainedValue()
        .received(bytes: byteCount, packets: packetCount, data: data, descriptions: descriptions)
}

private func converterInput(_ converter: AudioConverterRef, _ ioPackets: UnsafeMutablePointer<UInt32>,
                            _ ioData: UnsafeMutablePointer<AudioBufferList>,
                            _ outDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                            _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return StreamSource.broken }
    return Unmanaged<StreamSource>.fromOpaque(context).takeUnretainedValue().supply(ioPackets, ioData, outDescription)
}

/// The AudioFileStream hint for a file's suffix (it reads the bytes regardless; the hint helps
/// with formats whose first bytes are ambiguous).
public func audioFileType(forSuffix suffix: String) -> AudioFileTypeID {
    switch suffix.lowercased() {
    case "flac": return kAudioFileFLACType
    case "mp3": return kAudioFileMP3Type
    case "m4a", "mp4", "alac": return kAudioFileM4AType
    case "aac": return kAudioFileAAC_ADTSType
    case "wav": return kAudioFileWAVEType
    case "aif", "aiff": return kAudioFileAIFFType
    case "caf": return kAudioFileCAFType
    default: return 0
    }
}
#endif
