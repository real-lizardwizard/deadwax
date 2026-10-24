#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// What a read of a song's audio gave.
public enum PCMRead {
    /// Decoded samples: Float32, non-interleaved, at the file's own rate and channel count.
    case frames(AVAudioPCMBuffer)
    /// Nothing yet - a stream whose next bytes haven't arrived. Ask again shortly.
    case waiting
    /// The song's audio has all been read.
    case end
}

/// A song's audio, decoded by the app itself at the file's own rate: never resampled, never
/// mixed down. 16- and 24-bit samples are exact in Float32's 24-bit mantissa, so the conversion to
/// float loses nothing. Used from the engine's own queue only.
public protocol PCMSource: AnyObject {
    /// The decoded format - nil until a stream's header has arrived.
    var format: AVAudioFormat? { get }
    /// The next stretch of samples, at most `maxFrames`.
    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead
    /// Lets go of files and decoders.
    func close()
}

/// The decoded format the engine wants for a file's own rate and channels.
func floatFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat? {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)
}

/// Why a song couldn't be decoded, in words.
public struct AudioFailure: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// A song from a complete file on the phone - downloaded, or a stream that has finished arriving.
/// AVAudioFile decodes it (AudioToolbox has decoded FLAC since iOS 11, 24/96 and 24/192 included)
/// into Float32 at its own rate, and a seek is sample-exact through `framePosition` - the start
/// point's frame at the file's own rate.
public final class FileSource: PCMSource {
    let file: AVAudioFile
    public var format: AVAudioFormat? { file.processingFormat }

    public init(url: URL, start: StartPoint = .beginning) throws {
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioFailure("iOS couldn't open \(url.lastPathComponent) to play: \(error.localizedDescription)")
        }
        file.framePosition = min(start.frame(at: file.processingFormat.sampleRate), file.length)
    }

    /// The song's length in frames.
    public var length: AVAudioFramePosition { file.length }

    public func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        if file.framePosition >= file.length { return .end }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxFrames) else {
            throw AudioFailure("No memory for a buffer of \(maxFrames) frames.")
        }
        try file.read(into: buffer, frameCount: maxFrames)
        return buffer.frameLength == 0 ? .end : .frames(buffer)
    }

    public func close() {}
}
#endif
