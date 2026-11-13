import DeadwaxCore
import Foundation
import Testing

// The replay of a web recording (notes/ios-specs/turntable.md 6.3, slice 4): Fixtures/recording/web-script.json is
// deck.ts's own file, made by its own recorder over the web's main-thread voice (ios/scripts/export-deck-recording.cjs)
// - a scratch of a playing record and its let-go, 1.5 s. Played through the Swift voice at the timing the lab works out
// from the voice's own reports, it is what the web's voice wrote: every 16-bit sample as deck.ts rounded it, and every
// tapped block's loudest sample (a float in the file) within -100 dB - 7.0's test B.

@Suite struct DeckReplayTests {
    /// export-deck-recording.cjs's window: the recipe's sweep, seed 5, two channels.
    static func sweep(_ ch: Int, _ length: Int) -> [Float] {
        var out = [Float](repeating: 0, count: length)
        var phase = 0
        for i in 0..<length {
            phase = (phase + 1 + ((i >> 7) % 600) * (ch + 1)) & 0xffff
            let v = phase < 32768 ? phase * 2 - 32768 : (65535 - phase) * 2 - 32767
            out[i] = Float(v) / 32768
        }
        return out
    }

    static func file() throws -> DeckRecordingFile {
        try DeckRecordingFile.read(Data(contentsOf: Fixtures.url("recording/web-script.json")))
    }

    static func window(_: Double, _: Double, _ length: Int) -> [[Float]]? { [sweep(0, length), sweep(1, length)] }

    @Test func theWebsRecordingReplaysThroughTheSwiftVoice() throws {
        let file = try Self.file()
        #expect(file.voice == "script" && file.sampleRate == 48_000 && file.tapBlock == 4_096 && file.phone == nil)
        let outcome = DeckReplay.web(file, windowFor: Self.window)
        print("Web recording replayed: \(outcome.blocks) blocks, \(outcome.samples) samples from the first take, "
              + "lag \(outcome.lag.map(String.init) ?? "-"), lead \(outcome.lead ?? -1) s, worst miss \(outcome.worstMiss ?? -1) s; "
              + "\(outcome.steps) samples a step apart (largest \(outcome.largestStep)); largest float difference "
              + "\(outcome.largestDB) dB (the 16 bits' own rounding); blocks' peaks \(outcome.peaksCompared), largest "
              + "difference \(outcome.peaksDB) dB; \(outcome.notes)")
        #expect(outcome.samples > 40_000, "most of the 1.5 s compared")
        #expect(outcome.steps == 0, "every sample as deck.ts rounded it")
        #expect(outcome.peaksCompared >= 5 && outcome.peaksDB <= -100)
        #expect(outcome.withinTestB)
        #expect((outcome.worstMiss ?? .infinity) < 1e-9, "the timing found fits the voice's own reports")
        #expect(outcome.notes.isEmpty)
    }

    /// Held to the file: another window, or a take told a block late, and it says so.
    @Test func theReplayNoticesAnotherWindowOrTiming() throws {
        let file = try Self.file()
        let other = DeckReplay.web(file, windowFor: { (_: Double, _: Double, length: Int) -> [[Float]]? in
            [Self.sweep(1, length), Self.sweep(0, length)]
        })
        #expect(other.steps > 1_000 && !other.withinTestB)
        var late = file
        let take = try #require(late.messages.firstIndex { $0["type"] == .string("take") })
        guard case .object(var fields) = late.messages[take], case .number(let time)? = fields["time"] else {
            Issue.record("no take")
            return
        }
        fields["time"] = .number(time + 1_024 / 48_000)
        fields["until"] = .number(time + 1_024 / 48_000 + 0.12)
        late.messages[take] = .object(fields)
        let moved = DeckReplay.web(late, windowFor: Self.window)
        #expect(!moved.withinTestB)
    }
}
