import Foundation

/// The audio engine's own words, line by line (PlaybackEngine's `trace`), kept for You > Debug: the last `capacity`
/// lines in memory, the oldest let go first, behind one lock - the engine's queue appends, Debug's screen reads. Nothing
/// is kept on disk; the app sends each line to os_log as well (EngineTrace), for Console.app on the Mac.
///
/// Every line is scrubbed as it comes in (`scrub`), before it is kept or sent anywhere: no session cookie, password,
/// token, salt or Subsonic auth parameter may reach a log a person copies and pastes. None is known to reach the
/// engine's words (notes/ios.md, "Debug's engine log": the stream's URL carries only the song's id and format, and
/// deadwax's session goes as a Cookie header no failure repeats); the scrub is there so a new note can't change that.
public final class EngineLog: @unchecked Sendable {
    /// How many lines are kept: at the engine's busiest steady rate (a buffer played every 0.5 s, 2 lines a second)
    /// about four minutes of playing, and far longer around a pause, a skip or a failure.
    public static let defaultCapacity = 500

    public let capacity: Int
    private let lock = NSLock()
    private var ring: [String] = []
    /// Where the next line goes once the ring is full: its oldest.
    private var oldest = 0
    private var appended = 0

    public init(capacity: Int = EngineLog.defaultCapacity) {
        self.capacity = max(capacity, 1)
        ring.reserveCapacity(self.capacity)
    }

    /// Keeps `line`, scrubbed, and answers it as kept (what the app sends to os_log).
    @discardableResult
    public func append(_ line: String) -> String {
        let clean = Self.scrub(line)
        lock.lock()
        defer { lock.unlock() }
        if ring.count < capacity {
            ring.append(clean)
        } else {
            ring[oldest] = clean
            oldest = (oldest + 1) % capacity
        }
        appended += 1
        return clean
    }

    /// Every line ever appended (the lines kept are the last `capacity` of them): a screen asks again only when it
    /// has moved.
    public var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return appended
    }

    /// The lines kept, oldest first and the newest last, numbered from the first line ever appended.
    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let lines = ring.count < capacity ? ring : Array(ring[oldest...] + ring[..<oldest])
        return Snapshot(lines: lines, total: appended)
    }

    public struct Snapshot: Sendable, Equatable {
        /// Oldest first, the newest last.
        public let lines: [String]
        /// Every line ever appended.
        public let total: Int

        public static let empty = Snapshot(lines: [], total: 0)

        public init(lines: [String], total: Int) {
            self.lines = lines
            self.total = total
        }

        /// The number of the first line kept (0 for the first line ever appended): `first + i` names line `i` for as
        /// long as it is kept, however many come after it.
        public var first: Int { total - lines.count }

        /// The whole log as text, a line each, for Copy and Share.
        public var text: String { lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }
    }

    // MARK: the scrub

    /// `line` with the usual forms of anything that could sign someone in taken out:
    /// - a Cookie, Set-Cookie or Authorization header - all that follows it on the line;
    /// - a Bearer token;
    /// - a URL's user and password (`http://user:pass@host`);
    /// - the value of a key whose name is one of `secretKeys` (Subsonic's u, t, s and p; token, salt, password,
    ///   deadwax's session cookie...), standing on its own, given with "=" or ":" - `t=abc`, `token: abc`,
    ///   `x-deadwax-session: abc`, JSON's `"password":"hunter2"`: a value in quotes all of it, else up to the next
    ///   separator.
    /// A line holding none of them comes back as it is - a secret written as bare words ("password hunter2") is not
    /// recognised: the scrub guards against a new note quoting a URL, a header or a request, not against prose.
    public static func scrub(_ line: String) -> String {
        guard mayHoldSecret(line) else { return line }
        var out = line
        for rule in Rules.shared.rules {
            out = rule.pattern.stringByReplacingMatches(in: out, options: [], range: NSRange(out.startIndex..., in: out),
                                                        withTemplate: rule.template)
        }
        return out
    }

    /// What `scrub` puts in place of a secret.
    public static let scrubbed = "[scrubbed]"

    /// The keys whose values are scrubbed, matched without regard to case: Subsonic's auth parameters (u, t, s, p, and
    /// apiKey), deadwax's session cookie, and the usual names of a secret.
    public static let secretKeys = ["u", "t", "s", "p", "apikey", "api_key", "token", "salt", "password", "passwd", "pwd",
                                    "pass", "secret", "jwt", "auth", "session", "deadwax_session", "jimbrainz_session"]

    /// A cheap first look, one pass over the line's UTF-8 - nearly every line the engine writes has no "=" or "@",
    /// no ":" after a secret's key, and no header's or Bearer's name (in any case), and skips the patterns.
    /// Foundation's `contains` and `range(of:options: .caseInsensitive)` took about 17 µs a line here; this, well
    /// under one. Every engine line has a ":" ("lane 44100 Hz: ..."), so a ":" only counts after a key (`keyEnds`).
    static func mayHoldSecret(_ line: String) -> Bool {
        var line = line
        return line.withUTF8 { bytes in
            for (at, byte) in bytes.enumerated() {
                switch byte {
                case UInt8(ascii: "="), UInt8(ascii: "@"):
                    return true
                case UInt8(ascii: ":"):
                    if keyEnds(bytes, before: at) { return true }
                case UInt8(ascii: "c"), UInt8(ascii: "C"), UInt8(ascii: "a"), UInt8(ascii: "A"), UInt8(ascii: "b"),
                     UInt8(ascii: "B"):
                    for word in Self.headerWords where startsWith(bytes, at: at, word) { return true }
                default:
                    continue
                }
            }
            return false
        }
    }

    /// The names `mayHoldSecret` looks for, lower case.
    private static let headerWords: [[UInt8]] = ["cookie", "authorization", "bearer"].map { Array($0.utf8) }

    /// `secretKeys` as bytes, for `keyEnds`.
    private static let keyBytes: [[UInt8]] = secretKeys.map { Array($0.utf8) }

    /// Whether `bytes` holds `word` (lower-case ASCII letters) at `at`, in any case.
    private static func startsWith(_ bytes: UnsafeBufferPointer<UInt8>, at: Int, _ word: [UInt8]) -> Bool {
        guard at + word.count <= bytes.count else { return false }
        for (offset, letter) in word.enumerated() where bytes[at + offset] | 0x20 != letter { return false }
        return true
    }

    /// Whether one of `secretKeys` ends just before the ":" at `colon`, as the patterns read a key: the key standing on
    /// its own (no letter, digit or "_" before it), then perhaps a quote, then perhaps spaces.
    private static func keyEnds(_ bytes: UnsafeBufferPointer<UInt8>, before colon: Int) -> Bool {
        var end = colon
        while end > 0, bytes[end - 1] == UInt8(ascii: " ") || bytes[end - 1] == UInt8(ascii: "\t") { end -= 1 }
        if end > 0, bytes[end - 1] == UInt8(ascii: "\"") || bytes[end - 1] == UInt8(ascii: "'") { end -= 1 }
        keys: for key in keyBytes {
            let start = end - key.count
            guard start >= 0, start == 0 || !isWordByte(bytes[start - 1]) else { continue }
            for (offset, letter) in key.enumerated() where lowered(bytes[start + offset]) != letter { continue keys }
            return true
        }
        return false
    }

    private static func lowered(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    /// A letter, a digit or "_": what the patterns' `[A-Za-z0-9_]` takes as part of a longer name.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    /// The patterns, made once. NSRegularExpression is immutable and safe to use from any thread (Apple's
    /// documentation), so one set serves every caller.
    private struct Rules: @unchecked Sendable {
        let rules: [(pattern: NSRegularExpression, template: String)]

        static let shared = Rules()

        init() {
            let keys = EngineLog.secretKeys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            // a key standing on its own (not the end of a longer word), perhaps quoted, then "=" or ":"
            let key = #"(?i)(^|[^A-Za-z0-9_])("# + keys + #")(["']?\s*[:=]\s*)"#
            let made: [(String, String)] = [
                // a header, and all after it on the line (Set-Cookie before Cookie, so its name is kept whole)
                (#"(?i)\b(set-cookie|cookie|authorization)(\s*[:=]\s*).*$"#, "$1$2\(EngineLog.scrubbed)"),
                // a Bearer token - before the keys, so "token: Bearer abc" loses "abc" too
                (#"(?i)\b(bearer)\s+[^\s,;"')\]}]+"#, "$1 \(EngineLog.scrubbed)"),
                // a URL's user and password
                (#"(?i)\b([a-z][a-z0-9+.-]*://)[^/\s@]+@"#, "$1\(EngineLog.scrubbed)@"),
                // a key's value in quotes, all of it, the quotes kept (JSON's "password":"x y")
                (key + #""[^"]*""#, "$1$2$3\"\(EngineLog.scrubbed)\""),
                (key + #"'[^']*'"#, "$1$2$3'\(EngineLog.scrubbed)'"),
                // a key's value not in quotes, up to the next separator (a quoted one, scrubbed above, starts with
                // a quote, so it isn't matched again)
                (key + #"[^&\s;,"')\]}]+"#, "$1$2$3\(EngineLog.scrubbed)"),
            ]
            rules = made.map { pattern, template in
                // the patterns are this file's own: one that doesn't compile is a mistake the tests catch
                (try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), template)
            }
        }
    }
}
