#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// The record's windows (notes/ios-specs/turntable.md 4.4, 4.5): a stretch of the song as the voice reads it, at the
/// voice's rate, made on the phone - from the file it already has (a download, the stream cache's whole copy), or,
/// for a song whose copy isn't whole yet, from `/scrub`'s answer, read the same way.
///
/// Each is made the way the song's lane plays it: decoded by FileSource (AVAudioFile, whose `framePosition` is
/// sample-exact for FLAC) from the window's start on the deck's 2 s grid less a 0.2 s pre-roll; levelled by
/// GainedSource at the entry's factor; converted, when the file's rate isn't the output's, by an AVAudioConverter set
/// as the lane's is (mastering, `.max`, prime method `.normal`) with the pre-roll's output dropped; one second of the
/// file at a time, straight into the window's own memory (DeckPCM). The newest asked only is answered.
///
/// Sendable by hand: its one changing value, the newest ticket, is read and written under its lock; the rest is let.
public final class DeckWindows: @unchecked Sendable {
    /// The file a window is decoded through, one second at a time.
    public static let pieceSeconds = 1.0

    private let queue = DispatchQueue(label: "deadwax.deck.window", qos: .userInitiated)
    private let lock = NSLock()
    private var ticket = 0
    /// Where `/scrub` answers are kept while their windows are made (Caches/deadwax/scrub).
    public let scrubFolder: URL
    /// Where answers are given: the main queue, or a test's own.
    private let answers: DispatchQueue

    public init(scrubFolder: URL? = nil, answerQueue: DispatchQueue = .main) {
        self.scrubFolder = scrubFolder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("deadwax", isDirectory: true).appendingPathComponent("scrub", isDirectory: true)
        self.answers = answerQueue
    }

    private func take() -> Int {
        lock.lock()
        defer { lock.unlock() }
        ticket += 1
        return ticket
    }

    private func current(_ asked: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return asked == ticket
    }

    /// `seconds` of the song from `from` out of `file`, levelled at `factor`, for a voice at `outputRate`; answered on
    /// the answer queue (the main one) - unless a newer window was asked meanwhile.
    public func make(file: URL, from: Double, seconds: Double, outputRate: Double, factor: Float?,
                     answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void) {
        let asked = take()
        queue.async {
            guard self.current(asked) else { return }
            let result = Result { () throws -> DeckWindow in
                try Self.window(of: file, from: from, seconds: seconds, outputRate: outputRate, factor: factor)
            }.mapError { (error: Error) -> DeckWindowError in Self.words(error) }
            self.answers.async { if self.current(asked) { answer(result) } }
        }
    }

    /// The same from `/scrub` (4.5): asked of deadwax, written to `scrubFolder`, made as a local file is, and deleted.
    /// A 204 - deadwax saw the request go away - is no answer at all, as a cancel is.
    public func make(scrub client: DeadwaxClient, songID: String, from: Double, seconds: Double, outputRate: Double,
                     factor: Float?, answer: @escaping (Result<DeckWindow, DeckWindowError>) -> Void) {
        let asked = take()
        let ask = DeckScrub.ask(from: from, seconds: seconds, outputRate: outputRate)
        let folder = scrubFolder
        Task.detached(priority: .userInitiated) {
            let got: Result<(flac: Data, header: DeckScrub.Header), DeckWindowError>?
            do {
                got = try await client.scrub(songID: songID, at: ask.at, seconds: ask.seconds)
            } catch is CancellationError {
                return
            } catch {
                got = .failure(.failed((error as? APIFailure)?.words ?? error.localizedDescription))
            }
            guard let got, self.current(asked) else { return }
            self.queue.async {
                guard self.current(asked) else { return }
                let result = got.flatMap { (answer: (flac: Data, header: DeckScrub.Header)) -> Result<DeckWindow, DeckWindowError> in
                    Result { () throws -> DeckWindow in
                        try Self.window(scrub: answer.flac, header: answer.header, songID: songID, folder: folder,
                                        from: from, seconds: seconds, outputRate: outputRate, factor: factor)
                    }.mapError { (error: Error) -> DeckWindowError in Self.words(error) }
                }
                self.answers.async { if self.current(asked) { answer(result) } }
            }
        }
    }

    /// No window asked is wanted any more: what is on its way is never answered.
    public func cancel() { _ = take() }

    static func words(_ error: Error) -> DeckWindowError {
        if let window = error as? DeckWindowError { return window }
        if let audio = error as? AudioFailure { return .undecodable(audio.description) }
        return .undecodable(error.localizedDescription)
    }

    // MARK: making one (on the caller's thread)

    /// A window out of a local file: the song's own frames from its frame 0.
    public static func window(of file: URL, from: Double, seconds: Double, outputRate: Double, factor: Float?,
                              preRoll: Double = DeckScrub.preRollS) throws -> DeckWindow {
        let began = PlaybackEngine.hostSeconds()
        let (rate, channels, length) = try probe(file)
        guard let plan = DeckScrub.plan(from: from, seconds: seconds, fileRate: rate, fileFrames: length,
                                        outputRate: outputRate, preRoll: preRoll)
        else { throw DeckWindowError.pastTheEnd }
        let pcm = try fill(file, plan: plan, fileStart: plan.decodeFrom, channels: channels, factor: factor)
        return DeckWindow(pcm: pcm, start: plan.start, end: plan.start + Double(pcm.frames) / outputRate, rate: outputRate,
                          source: .file, bytes: 0, madeIn: PlaybackEngine.hostSeconds() - began)
    }

    /// A window out of a `/scrub` answer: its file's frame 0 is the song's `header.first`; the window's end from
    /// `first + samples`.
    public static func window(scrub flac: Data, header: DeckScrub.Header, songID: String, folder: URL, from: Double,
                              seconds: Double, outputRate: Double, factor: Float?,
                              preRoll: Double = DeckScrub.preRollS) throws -> DeckWindow {
        let began = PlaybackEngine.hostSeconds()
        let (plan, skip) = try DeckScrub.plan(from: from, seconds: seconds, header: header, outputRate: outputRate,
                                              preRoll: preRoll).get()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(DeckScrub.fileName(songID: songID, first: header.first))
        do {
            try flac.write(to: file, options: .atomic)
        } catch {
            throw DeckWindowError.failed("this phone couldn't keep its answer: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let (rate, channels, _) = try probe(file)
        guard rate == Double(header.rate) else {
            throw DeckWindowError.failed("its answer is at \(Int(rate)) Hz, not the \(header.rate) it said")
        }
        let pcm = try fill(file, plan: plan, fileStart: skip, channels: channels, factor: factor)
        return DeckWindow(pcm: pcm, start: plan.start, end: plan.start + Double(pcm.frames) / outputRate, rate: outputRate,
                          source: .server, bytes: flac.count, madeIn: PlaybackEngine.hostSeconds() - began)
    }

    /// A file's rate, channels and length - and that it is a FLAC of one or two channels.
    static func probe(_ file: URL) throws -> (rate: Double, channels: Int, length: Int64) {
        let audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: file, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw DeckWindowError.undecodable("iOS couldn't open it: \(error.localizedDescription)")
        }
        let id = (audio.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value
        guard id == kAudioFormatFLAC else { throw DeckWindowError.notFlac("it isn't a FLAC file") }
        let channels = Int(audio.processingFormat.channelCount)
        guard channels == 1 || channels == 2 else { throw DeckWindowError.channels(channels) }
        return (audio.processingFormat.sampleRate, channels, audio.length)
    }

    /// The plan's frames: decoded from `fileStart` (the file's own frame), levelled, converted when it must be, the
    /// pre-roll's output dropped - a second of the file at a time, straight into the window.
    static func fill(_ file: URL, plan: DeckScrub.Plan, fileStart: Int64, channels: Int, factor: Float?) throws -> DeckPCM {
        let source = GainedSource.wrap(try FileSource(url: file, start: .frame(fileStart, rate: plan.fileRate)), factor: factor)
        defer { source.close() }
        let pcm = DeckPCM(channelCount: channels, capacity: plan.frames)
        let piece = AVAudioFrameCount((pieceSeconds * plan.fileRate).rounded())
        var filled = 0
        var dropping = plan.dropFrames

        /// output frames into the window, the pre-roll's first dropped
        func keep(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData else { return }
            var at = 0
            let count = Int(buffer.frameLength)
            if dropping > 0 {
                let dropped = min(dropping, count)
                dropping -= dropped
                at = dropped
            }
            let take = min(count - at, plan.frames - filled)
            guard take > 0 else { return }
            for c in 0..<channels { pcm.channel(c).advanced(by: filled).update(from: data[c] + at, count: take) }
            filled += take
        }

        if !plan.converts {
            while filled < plan.frames {
                let done = try autoreleasepool { () throws -> Bool in
                    switch try source.read(maxFrames: piece) {
                    case .frames(let buffer): keep(buffer); return false
                    case .waiting, .end: return true
                    }
                }
                if done { break }
            }
            pcm.keep(filled)
            return pcm
        }

        guard let input = source.format, let output = floatFormat(sampleRate: plan.outputRate, channels: input.channelCount),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw DeckWindowError.undecodable("iOS has no converter from \(Int(plan.fileRate)) Hz to \(Int(plan.outputRate)) Hz")
        }
        // the lane's (PlaybackEngine.laneFor): the output lines up with the input, frame 0 with frame 0
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.primeMethod = .normal
        let ratio = plan.outputRate / plan.fileRate
        var ended = false
        while filled < plan.frames && !ended {
            try autoreleasepool { () throws -> Void in
                switch try source.read(maxFrames: piece) {
                case .frames(let decoded): try convert(decoded, with: converter, ratio: ratio, into: keep)
                case .waiting, .end: ended = true
                }
            }
        }
        if filled < plan.frames {
            // the song's end: what the converter's filter still holds
            try flush(converter, output: output, into: keep)
        }
        pcm.keep(filled)
        return pcm
    }

    /// A decoded piece through the converter, as the lane's `convert` hands it over: as the converter asks.
    static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter, ratio: Double,
                        into keep: (AVAudioPCMBuffer) -> Void) throws {
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1_024
        var offset: AVAudioFrameCount = 0
        while offset < input.frameLength {
            guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
                throw DeckWindowError.undecodable("no memory for the window")
            }
            let before = offset
            var failure: NSError?
            let status = converter.convert(to: out, error: &failure) { (wanted: AVAudioPacketCount,
                                                                          inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
                let left = input.frameLength - offset
                guard left > 0, let piece = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: min(wanted, left)),
                      let from = input.floatChannelData, let into = piece.floatChannelData else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                let count = min(wanted, left)
                for channel in 0..<Int(input.format.channelCount) {
                    into[channel].update(from: from[channel] + Int(offset), count: Int(count))
                }
                piece.frameLength = count
                offset += count
                inputStatus.pointee = .haveData
                return piece
            }
            keep(out)
            if status == .error {
                throw DeckWindowError.undecodable("the converter failed: \(failure?.localizedDescription ?? "no reason given")")
            }
            if offset == before && out.frameLength == 0 { return }
        }
    }

    /// What the converter holds, at the song's end.
    static func flush(_ converter: AVAudioConverter, output: AVAudioFormat, into keep: (AVAudioPCMBuffer) -> Void) throws {
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4_096) else { return }
            var failure: NSError?
            let status = converter.convert(to: out, error: &failure) { (_: AVAudioPacketCount,
                                                                          inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
                inputStatus.pointee = .endOfStream
                return nil
            }
            keep(out)
            if status != .haveData || out.frameLength == 0 { return }
        }
    }
}
#endif
