#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// A downloaded copy's sound, checked (notes/ios-specs/phase2-downloads.md 8.4): the FLAC decoded once **with the
/// decoder playback uses** - AVAudioFile at the file's own rate in Float32, exactly as FileSource opens it - each sample
/// turned back to its integer, packed as FLAC hashes it (Core's FLACMD5) and the MD5 of it all compared with STREAMINFO's.
/// That proves the bytes, and that iOS reads them as the encoder meant. Reading only: nothing here plays, and nothing
/// here touches the engine.
public enum FLACVerifier {
    /// What the decode found.
    public enum Outcome: Equatable, Sendable {
        /// The decoded sound is what the encoder hashed.
        case matched
        /// It isn't: the copy is deleted, and is a try.
        case mismatch
        /// There's nothing to compare: not a FLAC, an all-zero MD5, or more than 24 bits (Float32 can't hold it exactly).
        case bySize
        /// iOS couldn't open or decode it - the system's words, for Debug.
        case unreadable(String)
        /// `stop` said to stop (the app going away): checked again later. Never a try.
        case stopped
    }

    /// Frames decoded at a time.
    static let chunk: AVAudioFrameCount = 32_768

    /// Checks the FLAC at `url` against `info` (its STREAMINFO, read by Core's FLACStreamInfo; nil when it isn't one).
    /// `stop` is asked between chunks. Runs where it is called - the App calls it at utility priority, one song at a time.
    public static func verify(_ url: URL, info: FLACStreamInfo?, stop: () -> Bool = { false }) -> Outcome {
        guard let info, DownloadRules.checkAfterLength(info) == .unchecked else { return .bySize }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            return .unreadable("iOS couldn't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let format = file.processingFormat
        guard Int(format.channelCount) == info.channels else { return .mismatch }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            return .unreadable("No memory for a buffer of \(chunk) frames.")
        }
        var hash = MD5()
        var packed: [UInt8] = []
        var frames: Int64 = 0
        while file.framePosition < file.length {
            if stop() { return .stopped }
            do {
                try file.read(into: buffer, frameCount: chunk)
            } catch {
                return .unreadable("iOS couldn't decode \(url.lastPathComponent): \(error.localizedDescription)")
            }
            let count = Int(buffer.frameLength)
            guard count > 0, let data = buffer.floatChannelData else { break }
            let channels = (0..<Int(format.channelCount)).map { UnsafePointer(data[$0]) }
            packed.removeAll(keepingCapacity: true)
            FLACMD5.pack(channels, frames: count, bits: info.bitsPerSample, into: &packed)
            hash.update(packed)
            frames += Int64(count)
        }
        if info.totalSamples > 0 && frames != info.totalSamples { return .mismatch }
        return FLACMD5.verdict(hash.finish(), info) == .matched ? .matched : .mismatch
    }

    /// `verify`, with how long it took in seconds (Debug shows the time each check took: the plan's R9).
    public static func timed(_ url: URL, info: FLACStreamInfo?, stop: () -> Bool = { false }) -> (Outcome, Double) {
        let began = Date()
        let outcome = verify(url, info: info, stop: stop)
        return (outcome, Date().timeIntervalSince(began))
    }
}
#endif
