import Foundation

/// Where a window of the song comes from, in frames (notes/ios-specs/turntable.md 4.4, 4.5) - the arithmetic the
/// window maker (DeadwaxAudio's DeckWindows.swift) runs on, kept here so it is tested on Linux too: the window's place
/// on the deck's 2 s grid and its pre-roll, its length at the voice's rate, and - for a song whose copy isn't whole on
/// the phone yet - what `/scrub` is asked, how its `X-Deadwax-Window` reads and what its statuses mean.
public enum DeckScrub {
    /// The route's bound on `seconds` (src/routes/navidrome.py SCRUB_MAX_SECONDS) - tests/test_ios_contract.py holds
    /// the two together.
    public static let maxSeconds = 60
    /// Decoded before the window's start and dropped (4.4, step 4), so the converter's filter is full by the first
    /// frame kept: 0.2 s is a whole number of frames at every rate a multiple of 5 Hz - 2205 at 11.025 kHz, 60 of the
    /// 147-frame cycles of 44.1 to 48 kHz - so the grid start less it is too.
    public static let preRollS = 0.2
    /// The most frames a window holds: 40 s at 48 kHz (DeckConstants.windowS), the same bytes at a faster output -
    /// 20 s at 96 kHz, 10 s at 192 kHz (4.4).
    public static let maxFrames = 40 * 48_000
    /// What `/scrub` is asked for beyond the window and its pre-roll: deadwax starts its answer at a FLAC frame (or a
    /// fragment of about a second) at or before `at` (src/flac_window.py).
    public static let slackS = 1.0

    /// A window planned (4.4): where it starts in the song, where decoding starts, what of the converter's output is
    /// the pre-roll's, and how many frames at the voice's rate it holds.
    public struct Plan: Equatable, Sendable {
        /// the window's first frame, at the file's rate
        public var startFrame: Int64
        /// where decoding begins: `startFrame` less the pre-roll (0 near the song's start)
        public var decodeFrom: Int64
        /// output frames the pre-roll converts to, dropped
        public var dropFrames: Int
        /// output frames the window holds (the song's end permitting)
        public var frames: Int
        public var fileRate: Double
        public var outputRate: Double

        /// file frames decoded before the window's start
        public var preRollFrames: Int64 { startFrame - decodeFrom }
        /// the window's start, song seconds
        public var start: Double { Double(startFrame) / fileRate }
        /// its end, song seconds: from its frames, not from what was asked
        public var end: Double { start + Double(frames) / outputRate }
        /// whether its frames come through a converter (else a copy, times the level)
        public var converts: Bool { fileRate != outputRate }
    }

    /// `seconds` of the song from `from` (the deck's grid: `keep()` places a window at a multiple of 2 s), from a file
    /// at `fileRate` holding `fileFrames` frames of the song (nil: as far as it goes), for a voice at `outputRate`. Nil
    /// when nothing of the song is left from `from`.
    public static func plan(from: Double, seconds: Double, fileRate: Double, fileFrames: Int64?, outputRate: Double,
                            preRoll: Double = preRollS) -> Plan? {
        guard fileRate > 0, outputRate > 0, from.isFinite, seconds.isFinite, seconds > 0 else { return nil }
        let startFrame = Int64((Swift.max(0, from) * fileRate).rounded())
        let preRollFrames = Swift.min(startFrame, Int64((Swift.max(0, preRoll) * fileRate).rounded()))
        let drop = Int((Double(preRollFrames) * outputRate / fileRate).rounded())
        var frames = Swift.min(Int((seconds * outputRate).rounded(.down)), maxFrames)
        if let fileFrames {
            let left = fileFrames - startFrame
            guard left > 0 else { return nil }
            frames = Swift.min(frames, Int((Double(left) * outputRate / fileRate).rounded(.down)))
        }
        guard frames > 0 else { return nil }
        return Plan(startFrame: startFrame, decodeFrom: startFrame - preRollFrames, dropFrames: drop, frames: frames,
                    fileRate: fileRate, outputRate: outputRate)
    }

    // MARK: - /scrub (4.5)

    /// What `/scrub` is asked for a window of `seconds` from `from` for a voice at `outputRate` - before the file's
    /// rate is known: `at` is the grid start less the pre-roll, `seconds` the window's length (as the maker will cap
    /// it) plus the pre-roll and `slackS`, at most `maxSeconds`.
    public static func ask(from: Double, seconds: Double, outputRate: Double,
                           preRoll: Double = preRollS) -> (at: Double, seconds: Double) {
        let start = Swift.max(0, from)
        let at = Swift.max(0, start - preRoll)
        let window = Swift.min(seconds, Double(maxFrames) / Swift.max(outputRate, 1))
        return (at, Swift.min(Double(maxSeconds), window + (start - at) + slackS))
    }

    /// The query `ask` makes: `at` and `seconds` only - no `max_rate`, no `level`: the original's own frames.
    public static func query(at: Double, seconds: Double) -> [(String, String)] {
        [("at", JSNumber.string(at)), ("seconds", JSNumber.string(seconds))]
    }

    /// `X-Deadwax-Window: <first>/<samples>/<rate>` - where the answer's first frame is in the song, how many it holds,
    /// at what rate.
    public struct Header: Equatable, Sendable {
        public var first: Int64
        public var samples: Int64
        public var rate: Int

        public init(first: Int64, samples: Int64, rate: Int) {
            self.first = first
            self.samples = samples
            self.rate = rate
        }

        /// Nil unless it is three whole numbers, the rate above 0.
        public static func parse(_ text: String?) -> Header? {
            guard let parts = text?.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false),
                  parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
                  let first = Int64(parts[0]), let samples = Int64(parts[1]), let rate = Int(parts[2]), rate > 0
            else { return nil }
            return Header(first: first, samples: samples, rate: rate)
        }

        /// The song frame after its last.
        public var end: Int64 { first + samples }
    }

    /// A `/scrub` answer's window: the plan at the answer's own rate, its end from `first + samples` (deadwax cuts at
    /// 8 MB, so a hi-res song's comes back shorter than asked), and the answer's frames to skip to reach the pre-roll.
    public static func plan(from: Double, seconds: Double, header: Header, outputRate: Double,
                            preRoll: Double = preRollS) -> Result<(plan: Plan, skip: Int64), DeckWindowError> {
        guard let plan = plan(from: from, seconds: seconds, fileRate: Double(header.rate), fileFrames: header.end,
                              outputRate: outputRate, preRoll: preRoll)
        else { return .failure(.pastTheEnd) }
        let skip = plan.decodeFrom - header.first
        guard skip >= 0 else { return .failure(.failed("its window began after where it was asked")) }
        return .success((plan, skip))
    }

    /// What a `/scrub` status means (deck.ts:2346-2352): 415 the song refused for good, in deadwax's words; 416 past
    /// the end; 204 (the server's answer to a request it saw go away) no window and no error - nil, as a cancel;
    /// anything else `words`, tried again after RETRY_MS.
    public static func failure(status: Int, detail: String?, words: String) -> DeckWindowError? {
        switch status {
        case 204: return nil
        case 415: return .notFlac(detail)
        case 416: return .pastTheEnd
        default: return .failed(words)
        }
    }

    /// Where an answer is kept while its window is made: `<song id>-<first>.flac`, the id kept to letters, digits,
    /// `-` and `_`.
    public static func fileName(songID: String, first: Int64) -> String {
        let safe = String(songID.unicodeScalars.map { (s: Unicode.Scalar) -> Character in
            (s.isASCII && (s.properties.isAlphabetic || ("0"..."9").contains(s) || s == "-" || s == "_")) ? Character(s) : "_"
        })
        return "\(safe.isEmpty ? "song" : safe)-\(first).flac"
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
