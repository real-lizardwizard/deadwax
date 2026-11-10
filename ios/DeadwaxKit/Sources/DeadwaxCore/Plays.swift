import Foundation

// Plays, counted as the web counts them (docs/player.md "How plays are counted"; ui/src/lib/playQueue.ts and
// lib/streamPlan.ts's splitAcrossJoin, and the bookkeeping ui/src/player/usePlayer.ts does with them): "now
// playing" once a listen has really begun, a play once the time actually HEARD - never the position - crosses
// Last.fm's rule, dated from when the listen began. Pure, so it is tested on Linux; the app feeds a
// `ListenTracker` from the engine and sends what it returns through its one PlayReporter.
// Fixtures/levels/plays-vectors.json holds the rule to the TypeScript's own answers.

/// The rule itself.
public enum PlayRule {
    /// A song this long or shorter never counts (countsAsPlayed: its duration must be MORE than this).
    public static let longerThan: Double = 30
    /// Heard for half its length, or this long, whichever comes first.
    public static let atMost: Double = 240
    /// How far past the clock a step may run and still count in full (LISTEN_SLACK_SECONDS): the position
    /// and the clock are read a moment apart.
    public static let slack: Double = 0.5

    /// Whether this much LISTENING makes a song a play (countsAsPlayed): longer than 30 s, and heard for half
    /// of it or four minutes, whichever is less. An unknown length (0, NaN) never counts.
    public static func countsAsPlayed(listened: Double, duration: Double) -> Bool {
        guard duration > longerThan else { return false }
        return listened >= min(duration / 2, atMost)
    }

    /// How much listening one step from `previous` to `now` (seconds into the song) adds, `elapsed` seconds
    /// of the clock apart (listenedStep): nothing across a seek or backwards; a step forward in full, but no
    /// more than the clock allows at this rate plus the slack - so a locked phone's sparse updates still count.
    public static func listenedStep(previous: Double, now: Double, elapsed: Double, rate: Double = 1, seeked: Bool) -> Double {
        let step = now - previous
        if seeked || !(step > 0) { return 0 }
        let pace = rate > 0 ? rate : 1
        let allowed = max(0, elapsed) * pace + slack
        return min(step, allowed)
    }

    /// The listening between two readings that a join falls between (splitAcrossJoin): the OLD song's rest
    /// from `previous` to `oldLength`, and the NEW song's start up to `now` (song-relative) - nothing across a
    /// seek, and the two together no more than the clock allows, taken off the new song first.
    public static func splitAcrossJoin(previous: Double, oldLength: Double, now: Double, elapsed: Double, rate: Double = 1,
                                       seeked: Bool) -> (before: Double, after: Double) {
        if seeked { return (0, 0) }
        let pace = rate > 0 ? rate : 1
        let allowed = max(0, elapsed) * pace + slack
        var before = max(0, oldLength - previous)
        var after = max(0, now)
        if before + after > allowed {
            after = max(0, allowed - before)
            before = min(before, allowed)
        }
        return (before, after)
    }
}

/// One hearing of a song, from a load or a restart to the next of either (the web's Listen): pausing and
/// carrying on is the same listen; "previous" restarting the song, or playing it again once it has ended, is
/// a new one and counts again.
public struct Listen: Equatable, Sendable {
    /// seconds actually heard
    public var heard: Double
    /// when it began playing, ms since the epoch; nil until it has (the web's 0)
    public var startedAt: Int64?
    /// whether Navidrome has been told it was played
    public var submitted: Bool

    public static let new = Listen(heard: 0, startedAt: nil, submitted: false)

    public init(heard: Double, startedAt: Int64?, submitted: Bool) {
        self.heard = heard
        self.startedAt = startedAt
        self.submitted = submitted
    }

    /// It began playing (listenStarted): the first time in a listen is when it started, and when Navidrome
    /// hears what's playing; after that - a pause carried on from, waiting on the network - nothing new.
    public func started(atMs now: Int64) -> (listen: Listen, nowPlaying: Bool) {
        if startedAt != nil { return (self, false) }
        var next = self
        next.startedAt = now
        return (next, true)
    }

    /// More of it heard (listenHeard): `submit` is true for the one step that made it a play.
    public func hearing(_ seconds: Double, of duration: Double) -> (listen: Listen, submit: Bool) {
        var next = self
        next.heard = heard + seconds
        let submit = !submitted && PlayRule.countsAsPlayed(listened: next.heard, duration: duration)
        next.submitted = submitted || submit
        return (next, submit)
    }
}

/// What the app tells deadwax (`POST /deadwax/navidrome/scrobble/{song_id}`), each through its one
/// PlayReporter: what's playing now, or a play and when it began.
public enum PlayReport: Equatable, Sendable {
    case nowPlaying(songID: String)
    case played(songID: String, atMs: Int64)

    public var songID: String {
        switch self {
        case .nowPlaying(let id), .played(let id, _): return id
        }
    }

    /// The query it is sent with: `submission=false` for now playing; `submission=true&time=<ms>` for a play
    /// (the server's `time` is a whole number of milliseconds, and a play always carries one).
    public var query: [(String, String)] {
        switch self {
        case .nowPlaying: return [("submission", "false")]
        case .played(_, let atMs): return [("submission", "true"), ("time", String(atMs))]
        }
    }
}

/// The listen bookkeeping usePlayer does around the rule, apart from any engine, so it is tested on Linux:
/// the song heard, its listen, and the last reading (position in the song's seconds, the monotonic clock in
/// seconds - one that runs while the phone sleeps). The app calls it from the engine's events:
///
///  - `newListen` at every song change (next, previous to another song, a tap, an auto-advance, a skip after a
///    failure, a queue put back), at a restart (previous past 3 s, play on a song that has ended) and at each
///    time round of Repeat (a new entry) - `from` where it starts when that isn't 0 (a queue put back at 1:35),
///    so the jump from 0 isn't heard. A failure retried from where it stopped is the SAME listen: `seeked()`.
///  - `seeked()` at every seek, whoever asked: the next step counts nothing.
///  - `began` when the engine says the entry is playing (its first sample scheduled on a running output) -
///    "now playing" once per listen.
///  - `tick` from the app's ticker and the engine's buffer completions: the heard position and the song's
///    length (decoded frames over its rate once known, else Navidrome's duration, else 0, which never counts).
///  - `join` when the ticker first sees the next song of a gapless join: the old song's rest goes to the OLD
///    song (and its play, if that crosses the rule, under its id and its listen's start), then a new listen
///    for the new song with what was already heard of it, and its "now playing".
///  - `stop()` at a stop, a sign-out or a new queue: the listen is dropped as it is, nothing sent.
///
/// Nothing heard counts before the listen has begun (the web counts only on `timeupdate`, which comes while
/// playing), so a play always has its time.
public struct ListenTracker: Sendable, Equatable {
    public private(set) var songID: String?
    public private(set) var listen: Listen = .new
    public private(set) var lastPosition: Double = 0
    public private(set) var lastAt: Double = 0
    public private(set) var seekedSince = false

    public init() {}

    public mutating func newListen(songID: String, at monotonic: Double, from position: Double = 0) {
        self.songID = songID
        listen = .new
        lastPosition = position
        lastAt = monotonic
        seekedSince = false
    }

    public mutating func seeked() {
        seekedSince = true
    }

    public mutating func stop() {
        self = ListenTracker()
    }

    public mutating func began(wallMs: Int64) -> PlayReport? {
        guard let songID else { return nil }
        let (next, nowPlaying) = listen.started(atMs: wallMs)
        listen = next
        return nowPlaying ? .nowPlaying(songID: songID) : nil
    }

    public mutating func tick(position: Double, monotonic: Double, duration: Double) -> PlayReport? {
        guard let songID else { return nil }
        let step = PlayRule.listenedStep(previous: lastPosition, now: position, elapsed: monotonic - lastAt, seeked: seekedSince)
        lastPosition = position
        lastAt = monotonic
        seekedSince = false
        guard let startedAt = listen.startedAt else { return nil }
        let (next, submit) = listen.hearing(step, of: duration)
        listen = next
        return submit ? .played(songID: songID, atMs: startedAt) : nil
    }

    public mutating func join(into newSongID: String, oldLength: Double, newPosition: Double, monotonic: Double,
                              newDuration: Double, wallMs: Int64) -> [PlayReport] {
        var reports: [PlayReport] = []
        let split = PlayRule.splitAcrossJoin(previous: lastPosition, oldLength: oldLength, now: newPosition,
                                             elapsed: monotonic - lastAt, seeked: seekedSince)
        if let songID, let startedAt = listen.startedAt {
            let (old, submit) = listen.hearing(split.before, of: oldLength)
            listen = old
            if submit { reports.append(.played(songID: songID, atMs: startedAt)) }
        }
        songID = newSongID
        //? what was heard of the new song already counts; whether it made a play is not asked (it is at most a
        //? second or so - the web drops that `submit` too)
        listen = Listen.new.hearing(split.after, of: newDuration).listen
        lastPosition = newPosition
        lastAt = monotonic
        seekedSince = false
        if let now = began(wallMs: wallMs) { reports.append(now) }
        return reports
    }

    /// The wall clock as a play's time: whole milliseconds since the epoch (the server's `time` is an integer
    /// and refuses a fraction with 422).
    public static func wallMs(_ date: Date = Date()) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
