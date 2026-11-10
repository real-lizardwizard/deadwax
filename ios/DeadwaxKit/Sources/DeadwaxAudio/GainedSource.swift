#if canImport(AVFAudio)
import Accelerate
import AVFAudio
import Foundation

/// A song's audio at a fixed gain: Normalization's one multiply (notes/ios.md, "Gain").
///
/// Each decoded buffer is multiplied in place by `factor`, channel by channel, at the file's own rate
/// - before a lane's rate converter, which is linear - and handed on. The multiply is in the source
/// rather than in the engine's scheduling so it is done exactly once per sample on every path: a
/// buffer the engine parks and schedules later, a lane that runs dry and goes on, are the same buffer,
/// read once. `.waiting`, `.end`, the format and `busy` pass through.
///
/// - The factor is decided once per queue entry by the app (Core's gain rule, as a Float) and never
///   changes while the source is read: every later open of the entry (a seek, a resume, a new route)
///   wraps with the same one.
/// - No clamp, no limiter: the gain rule holds the song's peak at or under full scale.
/// - Off (and a song played as it is) is `wrap(source, factor: nil)`, which is the source itself:
///   no wrapper, no multiply, the decode bit for bit. A factor of exactly 1 is the same.
public final class GainedSource: PCMSource {
    /// The linear multiplier: never 1, never nil (`wrap` gives the source itself for those).
    public let factor: Float
    let inner: PCMSource

    private init(_ inner: PCMSource, factor: Float) {
        self.inner = inner
        self.factor = factor
    }

    /// `source` at `factor` - or `source` itself, untouched, when the factor is nil or exactly 1.
    public static func wrap(_ source: PCMSource, factor: Float?) -> PCMSource {
        guard let factor, factor != 1 else { return source }
        return GainedSource(source, factor: factor)
    }

    public var format: AVAudioFormat? { inner.format }
    public var busy: Bool { inner.busy }

    public func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        let result = try inner.read(maxFrames: maxFrames)
        guard case .frames(let buffer) = result, let channels = buffer.floatChannelData else { return result }
        let count = vDSP_Length(buffer.frameLength)
        var multiplier = factor
        // non-interleaved Float32: each channel's samples are contiguous (stride 1)
        for channel in 0..<Int(buffer.format.channelCount) {
            vDSP_vsmul(channels[channel], 1, &multiplier, channels[channel], 1, count)
        }
        return result
    }

    public func close() { inner.close() }
}
#endif
