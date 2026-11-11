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
///
/// **A read returns a buffer the caller owns**: a source never reuses or touches again a buffer it
/// has returned, so a wrapper (GainedSource) may change its samples in place.
public protocol PCMSource: AnyObject {
    /// The decoded format - nil until a stream's header has arrived.
    var format: AVAudioFormat? { get }
    /// The next stretch of samples, at most `maxFrames`.
    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead
    /// Lets go of files and decoders.
    func close()
    /// After a `.waiting`: true when the source has more in hand to work through at once (a seek
    /// still dropping the frames before it, with bytes that have arrived), so the engine reads again
    /// straight away rather than after its retry delay. False: it is waiting for bytes.
    var busy: Bool { get }
}

public extension PCMSource {
    var busy: Bool { false }
}

/// The decoded format the engine wants for a file's own rate and channels.
func floatFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat? {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)
}

/// Why a song couldn't be played: in words (Debug's - the listener's sentence is the app's, chosen
/// by `kind`), what kind of failure it was, and deadwax's http status when the failure was its
/// answer.
public struct AudioFailure: Error, CustomStringConvertible, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// The connection dropped, or the song stopped arriving (cut short included).
        case network
        /// The bytes came, and iOS couldn't decode them.
        case decode
        /// What came isn't audio iOS can play: no audio found in it, a kind of file it can't decode,
        /// or an answer that wasn't the song (an http status other than 200 and 401).
        case unsupported
        /// deadwax said this phone isn't signed in (401).
        case signedOut
        /// Anything else: the phone's own disk or memory, iOS refusing to start the audio.
        case other
    }

    public let description: String
    public let kind: Kind
    /// deadwax's status for the song, when the failure was its answer.
    public let status: Int?

    public init(_ description: String, kind: Kind = .other, status: Int? = nil) {
        self.description = description
        self.kind = kind
        self.status = status
    }

    /// `error` as a failure: itself when it is one, else its words as `kind`.
    public static func from(_ error: Error, kind: Kind = .other) -> AudioFailure {
        (error as? AudioFailure) ?? AudioFailure(String(describing: error), kind: kind)
    }
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
            throw AudioFailure("iOS couldn't open \(url.lastPathComponent) to play: \(error.localizedDescription)",
                               kind: .unsupported)
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
        do {
            try file.read(into: buffer, frameCount: maxFrames)
        } catch {
            throw AudioFailure("iOS couldn't decode \(file.url.lastPathComponent): \(error.localizedDescription)",
                               kind: .decode)
        }
        return buffer.frameLength == 0 ? .end : .frames(buffer)
    }

    public func close() {}
}
#endif
