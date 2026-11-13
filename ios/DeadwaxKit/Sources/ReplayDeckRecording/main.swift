// replay-deck-recording (notes/ios-specs/turntable.md 6.3; slice 4): a recording of the record's sound - Debug's file
// from the phone, or the web's from Safari or Chrome - played again through the Swift voice on the Mac, and held to
// what the recording heard, within -100 dB (7.0's test B).
//
//   swift run --package-path ios/DeadwaxKit replay-deck-recording <recording.json>
//       the phone's: it carries its windows' samples, and which messages the voice was told before which block
//   swift run --package-path ios/DeadwaxKit replay-deck-recording <recording.json> --song <file> [--window <start> <s>]
//       the web's: its windows come from the song, decoded here at the recording's rate (the browser's own decode of a
//       song at another rate is its own resampling, which no replay matches - compare a 48 kHz song in a 48 kHz
//       context); --window is the window the voice already had as the recording began (song seconds from, seconds
//       long), which the web's file doesn't carry
//
// Exit 0 within test B, 1 outside it, 2 when it couldn't be replayed.

import DeadwaxCore
import Foundation
#if canImport(AVFAudio)
import AVFAudio
#endif

func fail(_ words: String) -> Never {
    FileHandle.standardError.write(Data("replay-deck-recording: \(words)\n".utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, count: Int) -> [String]? {
    guard let at = arguments.firstIndex(of: name) else { return nil }
    guard at + count < arguments.count else { fail("\(name) needs \(count) value\(count == 1 ? "" : "s")") }
    let values = Array(arguments[(at + 1)...(at + count)])
    arguments.removeSubrange(at...(at + count))
    return values
}
let songPath = option("--song", count: 1)?.first
let windowAt = option("--window", count: 2).map { (values: [String]) -> (Double, Double) in
    guard let start = Double(values[0]), let seconds = Double(values[1]) else { fail("--window takes two numbers") }
    return (start, seconds)
}
guard arguments.count == 1 else {
    fail("usage: replay-deck-recording <recording.json> [--song <file>] [--window <start> <seconds>]")
}

let file: DeckRecordingFile
do {
    file = try DeckRecordingFile.read(try Data(contentsOf: URL(fileURLWithPath: arguments[0])))
} catch {
    fail("\(arguments[0]): \(error)")
}

/// The song's channels at the recording's rate, from song second 0.
func decode(_ path: String, rate: Double) -> [[Float]] {
    #if canImport(AVFAudio)
    do {
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = audio.processingFormat
        guard let read = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.length)) else {
            fail("\(path): no memory for it")
        }
        try audio.read(into: read)
        var buffer = read
        if format.sampleRate != rate {
            FileHandle.standardError.write(Data(("replay-deck-recording: the song is at \(format.sampleRate) Hz, the recording "
                + "at \(rate) Hz - converted here, which isn't the browser's own resampling: expect differences\n").utf8))
            guard let to = AVAudioFormat(standardFormatWithSampleRate: rate, channels: format.channelCount),
                  let converter = AVAudioConverter(from: format, to: to),
                  let out = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: AVAudioFrameCount(Double(read.frameLength) * rate / format.sampleRate) + 4_096)
            else { fail("\(path): can't be converted to \(rate) Hz") }
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            var given = false
            var problem: NSError?
            _ = converter.convert(to: out, error: &problem) { (_: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
                if given {
                    status.pointee = .endOfStream
                    return nil
                }
                given = true
                status.pointee = .haveData
                return read
            }
            if let problem { fail("\(path): \(problem.localizedDescription)") }
            buffer = out
        }
        guard let data = buffer.floatChannelData else { fail("\(path): not floats") }
        return (0..<Int(buffer.format.channelCount)).map { (c: Int) -> [Float] in
            Array(UnsafeBufferPointer(start: data[c], count: Int(buffer.frameLength)))
        }
    } catch {
        fail("\(path): \(error.localizedDescription)")
    }
    #else
    fail("--song needs AVFAudio: run this on the Mac")
    #endif
}

func say(_ outcome: DeckReplayOutcome) {
    func db(_ x: Double) -> String { x == -.infinity ? "-inf" : String(format: "%.1f", x) }
    print("blocks replayed: \(outcome.blocks), compared: \(outcome.compared > 0 ? String(outcome.compared) : "-")")
    print("samples compared: \(outcome.samples)")
    if let lead = outcome.lead {
        print(String(format: "messages told %.1f ms after they were posted; the path's worst miss against the voice's reports %.3g song s",
                     lead * 1_000, outcome.worstMiss ?? .nan))
    }
    if let lag = outcome.lag { print("the tap sits \(lag) samples from where its block times put it") }
    if outcome.peaksCompared > 0 || file.phone == nil {
        print("16-bit samples rounded differently: \(outcome.steps) (largest \(outcome.largestStep) step)")
        print("blocks' loudest samples: \(outcome.peaksCompared), largest difference \(db(outcome.peaksDB)) dB")
        print("largest float difference \(db(outcome.largestDB)) dB (16 bits round to within -96.3 dB)")
    } else {
        print("largest difference \(db(outcome.largestDB)) dB, RMS \(db(outcome.rmsDB)) dB")
    }
    for note in Set(outcome.notes).sorted() { print("note: \(note)") }
    print(outcome.withinTestB ? "within test B (-100 dB): the Swift voice played what the recording heard"
                              : "NOT within test B (-100 dB)")
}

if file.phone != nil {
    guard let outcome = DeckReplay.phone(file) else { fail("the phone's keys couldn't be read") }
    say(outcome)
    exit(outcome.withinTestB ? 0 : 1)
}

let song = songPath.map { decode($0, rate: file.sampleRate) }
if song == nil {
    FileHandle.standardError.write(Data("replay-deck-recording: no --song - the windows are silence, so only the path is held to the reports\n".utf8))
}
func cut(_ start: Double, _ length: Int) -> [[Float]]? {
    guard let song else { return nil }
    let first = Int((start * file.sampleRate).rounded())
    return song.map { (channel: [Float]) -> [Float] in
        (0..<length).map { (i: Int) -> Float in first + i >= 0 && first + i < channel.count ? channel[first + i] : 0 }
    }
}
let atStart = windowAt.flatMap { (start: Double, seconds: Double) -> DeckReplay.WindowAtStart? in
    cut(start, Int((seconds * file.sampleRate).rounded())).map {
        DeckReplay.WindowAtStart(channels: $0, start: start, rate: file.sampleRate)
    }
}
let outcome = DeckReplay.web(file, windowAtStart: atStart) { (start: Double, _: Double, length: Int) -> [[Float]]? in cut(start, length) }
say(outcome)
exit(outcome.withinTestB ? 0 : 1)
