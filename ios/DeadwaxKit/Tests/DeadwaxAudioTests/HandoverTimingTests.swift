#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The handover's timing (notes/ios-specs/turntable.md 3.5, 7.2): the song's engine and the deck engine both offline,
// rendered in lockstep on one shared sample clock - the clock 3.5 calls "heard" (a render's time, latency 0 here). At
// the let-go the song is sought to the plan's place and the voice given the plan; the song's engine is resumed at
// `r = planEnd + D - E`, with `E` the offline engine's own start (frames rendered from a resume to its first sound, the
// median of three) and `D` Core's (HandoverTiming.voiceDelay). The song's first sample lands where the voice sounds the
// plan's end, within one render quantum - and a click in the song comes out of both engines at the same frame. It
// tests the arithmetic and the order of the calls, not the phone's `E`, which only the phone has (checks 0a-0c).

@Suite(.serialized) struct HandoverTimingTests {
    static let rate = 48_000.0
    /// the render quantum both engines are rendered in, in step: small, so the resume lands within 32 frames of `r`
    /// and a mistake of the limiter's 72 frames shows
    static let quantum = 32

    /// The song: a 1 kHz tone at 0.05 (never exactly 0 at a frame), and from 2 s a click of 0.8 every 0.1 s.
    static func song(seconds: Double = 4) -> [[Float]] {
        let frames = Int(seconds * rate)
        let one = (0..<frames).map { (n: Int) -> Float in
            let tone = 0.05 * sin(2 * Double.pi * 1_000 * Double(n) / rate + 1)
            let click = n >= 96_000 && n % 4_800 == 0 ? 0.8 : 0
            return Float(tone + click)
        }
        return [one, one]
    }

    /// `frames` of the song's engine's channel 0, a piece at a time, its completions handled between.
    static func render(_ engine: PlaybackEngine, _ frames: Int) throws -> [Float] {
        let buffer = try engine.renderOffline(AVAudioFrameCount(frames))
        try completionsHandled(engine)
        return samples(buffer, channel: 0)
    }

    /// The frames from a resume to the song's first sound: rendered a quantum at a time until one isn't silent.
    static func startFrames(_ engine: PlaybackEngine, seekingTo place: Double) throws -> Int {
        engine.seek(to: place)
        engine.settle()
        engine.resume()
        engine.settle()
        var done = 0
        while done < Int(2 * rate) {
            let out = try render(engine, quantum)
            if let first = out.firstIndex(where: { $0 != 0 }) {
                engine.pause()
                engine.settle()
                return done + first
            }
            done += quantum
        }
        Issue.record("no sound within 2 s of a resume")
        return done
    }

    @Test func theSongComesInWhereTheVoiceSoundsThePlansEnd() throws {
        let rate = Self.rate, q = Self.quantum
        let song = Self.song()
        let engine = try offlineEngine(rate: rate, channels: 2)
        // a start from silence scheduled 0.3 s ahead, so that E is more than D and the resume is moved earlier
        engine.startLead = { 0.3 }
        engine.play([entry(song, rate: rate, key: 0, id: "song")], from: 0)
        engine.settle()
        _ = try Self.render(engine, 4_800)
        engine.pause()
        engine.settle()

        // E: the engine's own start, three times
        let planX = 2.05
        let starts = try (0..<3).map { (_: Int) -> Int in try Self.startFrames(engine, seekingTo: planX) }
        let e = Double(starts.sorted()[1]) / rate
        let clockLead = 0.0213
        let d = HandoverTiming.voiceDelay(clockLead: clockLead, latency: 0)
        let lead = HandoverTiming.lead(predicted: e, voiceDelay: d)
        try #require(e > d, "E (\(e)) more than D (\(d)): the resume is moved earlier")

        // the deck: the song itself as its window, its clock the shared one less L
        let deck = try DeckCases.offlineDeck(rate: rate, eq: false)
        deck.setOfflineClock(frames: 0, lead: clockLead)
        try deck.start()
        defer { deck.stop() }
        let window = DeckPCM(song)
        #expect(deck.post(.window(window.voiceWindow(start: 0, rate: rate)), keeping: window))

        // the let-go at 0.5 s: a plan of 0.3 s at rate 1 ending at planX
        let letGo = 0.5, planSeconds = 0.3
        let planEnd = letGo + planSeconds
        let r = planEnd - lead
        let until = Int(((planEnd + d + 0.15) * rate).rounded(.up))
        var songOut = [Float](repeating: 0, count: until + q), deckOut = [Float](repeating: 0, count: until + q)
        var resumedAt: Int?
        var n = 0
        while n < until {
            let now = Double(n) / rate
            if n == Int(letGo * rate) {
                engine.seek(to: planX)
                engine.settle()
                #expect(deck.post(.take(at: planX - planSeconds, rate: 1, time: letGo, until: .infinity), keeping: nil))
            }
            if resumedAt == nil, now >= r {
                engine.resume()
                engine.settle()
                resumedAt = n
            }
            let voice = try deck.renderOffline(AVAudioFrameCount(q))
            deckOut.replaceSubrange(n..<(n + q), with: samples(voice, channel: 0))
            if resumedAt != nil {
                songOut.replaceSubrange(n..<(n + q), with: try Self.render(engine, q))
            }
            n += q
        }
        let resumed = try #require(resumedAt)
        let first = try #require(songOut.indices.first { songOut[$0] != 0 })
        let heardAt = planEnd + d
        let seam = Double(first) / rate - heardAt
        // the 2.1 s click, 0.05 s past planX: in the song, and in the voice
        let expectedClick = Int(((heardAt + 0.05) * rate).rounded())
        let around = (expectedClick - 1_500)..<(expectedClick + 1_500)
        let songClick = try #require(around.max { abs(songOut[$0]) < abs(songOut[$1]) })
        let voiceClick = try #require(around.max { abs(deckOut[$0]) < abs(deckOut[$1]) })
        let frames = starts.map { (s: Int) -> String in String(s) }.joined(separator: "/")
        print(String(format: "Handover: E %.1f ms (", e * 1_000) + frames
              + String(format: " frames), D %.1f ms, lead %.1f ms; the resume asked at %.4f s, made at %.4f s; ", d * 1_000, lead * 1_000,
                       r, Double(resumed) / rate)
              + String(format: "the song's first sample %.2f ms from planEnd + D; ", seam * 1_000)
              + "its 2.1 s click at frame \(songClick), the voice's at \(voiceClick) (\(songClick - voiceClick) apart)")
        #expect(abs(seam) <= Double(q) / rate, "the song's first sample within a quantum of where the voice sounds the plan's end")
        #expect(abs(songClick - voiceClick) <= q + 2, "the same moment of the song out of both engines, within a quantum")
        #expect(abs(songOut[songClick]) > 0.7 && abs(deckOut[voiceClick]) > 0.5, "the clicks found")
    }
}
#endif
