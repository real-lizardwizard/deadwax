#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// One entry of the queue for the engine: Up Next's key for it, what it decodes to, the song, and
/// how to open its audio at a point in it (its beginning, a seek's seconds, or the exact frame it
/// was left at) - the source turns that into a frame at the file's own rate (`StartPoint.frame(at:)`).
public struct EngineTrack {
    /// Up Next's key for the entry (its Mark's): unique in the queue, and what the engine reports
    /// the song heard by, so an index from an older list is never acted on.
    public let key: Int
    /// What the entry decodes to: `"<song id>|<level, or off>"` (`audio(songID:level:)`). Two
    /// entries with the same `audio` give the same samples at the same gain, so an edit that keeps
    /// it - Repeat One's copies, Shuffle turned off re-keying the same songs - keeps what is scheduled.
    public let audio: String
    public let song: Song
    /// Opens the entry's audio: the app's source, wrapped at the entry's gain (`GainedSource.wrap`),
    /// decided once for the entry and the same at every open.
    public let open: (StartPoint) throws -> PCMSource

    public init(key: Int, audio: String, song: Song, open: @escaping (StartPoint) throws -> PCMSource) {
        self.key = key
        self.audio = audio
        self.song = song
        self.open = open
    }

    /// `"<song id>|<level>"`, or `"<song id>|off"` with no level.
    public static func audio(songID: String, level: String?) -> String {
        "\(songID)|\(level ?? "off")"
    }
}

/// What the engine is doing, for the screen and the lock screen.
public struct EngineState: Equatable {
    public enum Phase: Equatable {
        case idle
        case loading
        case playing
        case paused
        case ended
        /// Debug's words; `EngineState.failure` says what kind of failure it was.
        case failed(String)
    }

    public var phase: Phase = .idle
    /// The entry heard (its key), and where it is in the CURRENT tracks.
    public var key: Int?
    public var index: Int?
    /// The heard song's own rate and channels - what it was decoded at.
    public var fileRate: Double?
    public var fileChannels: Int?
    /// The rate the engine's output runs at (the route's). A song's lane converts it to this when
    /// the rates differ - see the class comment.
    public var outputRate: Double?
    /// The start time asked of the last song started from silence: output latency plus one IO buffer.
    public var lastStartLead: Double?
    /// The output's latency the positions are taken back by (seconds).
    public var latency: Double?
    /// With `.failed`: the failure, its kind and deadwax's status - the app's words come from them.
    public var failure: AudioFailure?
    /// How many failures the engine has said, all told: one more at each. A song asked for again that fails in the
    /// very same way (a retry, play after a failure) is a new failure, and this is what makes its state a new one -
    /// published, where the same phase, key and words would have been dropped as no change.
    public var failures = 0

    public init() {}
}

/// Where the listener is: the entry heard, its index in the current tracks, how far in (seconds of
/// the song's own, the output's latency behind the render), and its exact length once its decode has
/// ended (Navidrome's `duration` is whole seconds).
public struct EnginePosition: Equatable {
    public let key: Int
    public let index: Int
    public let seconds: Double
    public let length: Double?

    public init(key: Int, index: Int, seconds: Double, length: Double?) {
        self.key = key
        self.index = index
        self.seconds = seconds
        self.length = length
    }
}

/// What Debug shows of the engine (plan R8): its lanes, the output, and the last start.
public struct EngineDebug: Equatable {
    public struct Lane: Equatable {
        /// The songs' own rate and channels.
        public let rate: Double
        public let channels: Int
        /// The rate the lane's node runs at - the output's.
        public let nodeRate: Double
        /// The lane converts the songs' rate to the output's.
        public let converting: Bool
        /// Scheduled past what the render has reached, in seconds.
        public let aheadSeconds: Double
        public let pendingBuffers: Int
        public let started: Bool
        /// The lane the song heard is on.
        public let heard: Bool
    }

    public var lanes: [Lane] = []
    public var outputRate: Double?
    public var latency: Double = 0
    public var lastStartLead: Double?
    /// From the last play (or resume) asked for to its first sample heard, in seconds.
    public var lastStartSeconds: Double?
    public var outputRunning = false
    public var asleep = true
    public var phase: EngineState.Phase = .idle
    public var key: Int?
    /// The entry being decoded (the one heard, or the next once the heard one's decode has ended).
    public var feedKey: Int?

    public init() {}
}

/// The audio engine (notes/ios.md, the plan's section 3): AVAudioEngine with one AVAudioPlayerNode
/// per format "lane", fed by the app's own decoding at each file's own rate.
///
/// - Gapless: the next song's first buffer is scheduled straight after the last song's last buffer
///   on the same node, so within a format the samples run on unbroken - nothing trimmed, nothing
///   crossfaded. A song in another format goes on its own lane, started at the moment the first
///   lane's last sample plays.
/// - Nothing is processed but what an output needs: the gain of the entry when the app asks for one
///   (its source's own multiply, GainedSource - the engine itself multiplies nothing), the decoder's
///   int-to-float (exact), the main mixer at unity, and - only when a file's rate isn't the output's
///   (48 kHz on the speaker and AirPods: a 44.1 kHz CD, a 96 or 192 kHz file) - the lane's own
///   AVAudioConverter at its best quality (the mastering algorithm, `.max`), one per lane and kept
///   across its songs so a join stays continuous. Every node runs at the output's rate, so the mixer
///   itself converts nothing. (The mixer's own conversion was measured first and failed: a 30 kHz
///   tone in a 192 kHz file came out at -21.8 dB, aliased - EngineRenderTests'
///   `theRateConversionMeasured`.)
/// - The output is started once and kept running across songs, so a song is scheduled onto an
///   output that is already live. A song started from silence is scheduled `startLead` ahead (the
///   output's latency and one IO buffer), so the output is live when its first sample plays. A pause
///   (or a stop, a failure) stops the output at once (`idleStopSeconds`, 0): iOS counts an app whose
///   output runs as playing, whatever its now-playing rate says. The queue's end stops it once its
///   last samples have been heard. Play then starts the output again and goes on from the frame left.
/// - One position for every reader - the lock screen, the scrubber, the plays rule, a pause's
///   resume point: the frame HEARD, the output's `latency` behind the render (Core's HeardEstimate).
///   A song change is said when it is heard.
/// - When iOS stops the engine itself (a call, a new route, media services reset), the node's clock
///   is gone before the engine hears of it, so where the song was is estimated from the last reading
///   taken while it played (read at least every buffer), carried on to the moment it is noticed, less
///   the old route's latency - and play goes on from there.
/// - The queue is followed by Up Next's keys (`EngineTrack.key`), not indices: an edit of what comes
///   after the song heard (`replaceUpcoming`) is taken when nothing it changes is on a node yet, and
///   refused - held by the app until the next song - when it would change a song already scheduled.
///   The song heard is never touched.
///
/// Every call hops onto the engine's own serial queue; `onChange` is called on the main queue.
public final class PlaybackEngine {
    public struct Settings {
        /// One scheduled buffer.
        public var bufferSeconds: Double = 0.5
        /// How much is kept scheduled ahead of what is heard (about four buffers).
        public var aheadSeconds: Double = 2.0
        /// How much is scheduled before a node starts from silence.
        public var startSeconds: Double = 1.0
        /// How long a pause keeps the output running: none. iOS reads a running output as playing
        /// (notes/ios.md, "The pause the lock screen didn't see"); it was 60 s, for a quicker play.
        public var idleStopSeconds: Double = 0
        /// The queue's end: the output stops this long after its last sample has been heard.
        public var endLingerSeconds: Double = 0.1
        /// After a configuration change (a new route), how long the engine waits before playing on,
        /// so a pause for the same change - the old output gone: AirPods out, headphones unplugged,
        /// which the app hears as a route change on another queue - comes first and wins.
        public var changeSettleSeconds: Double = 0.3
        /// How long to wait before reading a stream again that had nothing yet.
        public var retrySeconds: Double = 0.05
        /// Offline manual rendering in this format (the tests' render), instead of the device.
        public var offline: AVAudioFormat?

        public init() {}
    }

    /// The lead before a song started from silence plays: the app sets it from AVAudioSession
    /// (outputLatency + ioBufferDuration). Zero plays at once.
    public var startLead: () -> TimeInterval = { 0 }
    /// How far the ear is behind the render: the app sets it from AVAudioSession (outputLatency +
    /// ioBufferDuration). Read on the engine's queue at each position read.
    public var latency: () -> TimeInterval = { 0 }
    /// The output's IO buffer (AVAudioSession's ioBufferDuration): a node started on an output already
    /// running starts this far past its last render, so the start is never in a render already under way.
    public var ioBuffer: () -> TimeInterval = { 0 }
    public var onChange: ((EngineState) -> Void)?
    /// What the engine does, line by line, on its queue - each line starts with the render's sample
    /// count offline, the host time in seconds on the phone. Debug keeps the last lines for a log.
    public var trace: ((String) -> Void)?

    private let settings: Settings
    private let queue = DispatchQueue(label: "deadwax.engine", qos: .userInitiated)
    private var engine: AVAudioEngine
    private var observer: NSObjectProtocol?

    private final class Lane {
        let node: AVAudioPlayerNode
        /// The songs' own format, as decoded. The timeline counts in its frames.
        let format: AVAudioFormat
        /// The format the node is connected in: the output's rate, the songs' channels - the songs'
        /// own format itself when the rates agree.
        let nodeFormat: AVAudioFormat
        /// From `format` to `nodeFormat`, when the rates differ; nil when they don't (nothing done).
        let converter: AVAudioConverter?
        var timeline = LaneTimeline()
        /// Where each buffer scheduled and not yet called back ends on the node (its frames since it
        /// started), in order: one per completion to come.
        var ends: [Int64] = []
        var pending: Int { ends.count }
        var started = false
        /// Frames scheduled on the node since it started, at the node's rate.
        var nodeFrames: Int64 = 0
        /// The converter holds frames it hasn't given out yet (its filter's look-ahead): given out by
        /// `flush` when the lane's songs end.
        var holding = false
        /// The render's position when the node was last read playing (the songs' frames), when, and
        /// the output's latency then - where the song was when iOS stops the engine (its clock reads
        /// nil then).
        var lastRead: HeardReading?
        /// The frame heard, estimated once iOS had stopped the engine: kept, so later reads don't
        /// carry the estimate on.
        var stopped: Int64?
        /// The node time (the render's sample count) its count of frames played starts from: the sample time
        /// it was started at (`playFromSilence`, `startLanesIfReady`). Nil when it was started at once or at a
        /// host time (no render time to start from), where its clock says it.
        var origin: AVAudioFramePosition?
        /// What its node's render time read as the output last started: left from before the stop, never a
        /// time to start at (`renderTime`). Kept across `clear`, which can come before this run's first render.
        var renderAtStart: AVAudioFramePosition?
        /// Tests, offline: reads of its render time still to give `staleReading` (`staleRenderReads`).
        var staleReads = 0
        var staleReading: RenderTime?
        /// Buffers scheduled on the node since the lane last began (`clear`), and the completions
        /// AVAudioEngine has called back of them (`calls`, counted on its own thread, of this beginning
        /// only - `epoch`): all called back, and the node has rendered everything on it, whatever its
        /// clock says (notes/ios.md "The hold on the callbacks").
        var scheduled = 0
        let calls = Calls()
        var epoch = 0

        init(node: AVAudioPlayerNode, format: AVAudioFormat, nodeFormat: AVAudioFormat, converter: AVAudioConverter?) {
            self.node = node
            self.format = format
            self.nodeFormat = nodeFormat
            self.converter = converter
        }

        /// A count of the node's samples in the songs' frames.
        func songFrames(_ nodeSamples: Int64) -> Int64 {
            guard converter != nil else { return nodeSamples }
            return Int64((Double(nodeSamples) * format.sampleRate / nodeFormat.sampleRate).rounded(.down))
        }

        /// Where on the node the last frame scheduled will have played: exact once the converter has
        /// given out all it holds, estimated from the songs' frames before.
        var nodeEnd: Int64 {
            guard holding else { return nodeFrames }
            return Int64((Double(timeline.end) * nodeFormat.sampleRate / format.sampleRate).rounded())
        }

        /// Nothing scheduled, not started (the node itself is stopped by the caller). The converter
        /// keeps what it holds: `resetConverter` lets it go.
        func clear() {
            timeline.reset()
            ends.removeAll()
            started = false
            nodeFrames = 0
            lastRead = nil
            stopped = nil
            origin = nil
            scheduled = 0
            epoch = calls.begin()
        }

        /// The input frames the converter holds (what went in less what came out), none without one.
        var converterHolds: Int64 {
            guard converter != nil, holding else { return 0 }
            return max(timeline.end - songFrames(nodeFrames), 0)
        }

        func resetConverter() {
            converter?.reset()
            holding = false
        }
    }

    /// A lane's completions AVAudioEngine has called back, counted on its own thread for one beginning of
    /// the lane: a callback of a buffer scheduled before `begin` (a stop lets every buffer go, called back
    /// later) is not counted.
    final class Calls {
        private let lock = NSLock()
        private var epoch = 0
        private var count = 0
        func begin() -> Int { lock.lock(); defer { lock.unlock() }; epoch += 1; count = 0; return epoch }
        func add(_ of: Int) { lock.lock(); if of == epoch { count += 1 }; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// A node's render time as read: its sample time, and its host time in seconds when it has one. On a real
    /// output the host time is stamped ahead of now (24.8 ms on this Mac's): it is when the render's first
    /// sample is presented, the time line a play(at:) host time is read on.
    struct RenderTime: Equatable {
        let sample: AVAudioFramePosition
        let host: Double?
    }

    private struct LaneKey: Hashable {
        let rate: Double
        let channels: AVAudioChannelCount

        init(_ format: AVAudioFormat) {
            rate = format.sampleRate
            channels = format.channelCount
        }
    }

    /// The song being decoded and scheduled - the one heard, or the next one once the heard one's
    /// decode has ended.
    private struct Feed {
        var key: Int
        let source: PCMSource
        /// Where the source was opened at; its frame once the decoded format is known.
        let start: StartPoint
        var startFrame: Int64?
        /// Frames decoded and scheduled since.
        var decoded: Int64 = 0
        var lane: LaneKey?
        var entry: Int?
        /// A buffer decoded but held back, and why (`Wait`, see `schedule`). Scheduled first when the
        /// feed goes on.
        var parked: AVAudioPCMBuffer?
        var parkedFor: Wait?

        init(key: Int, source: PCMSource, start: StartPoint) {
            self.key = key
            self.source = source
            self.start = start
        }

        /// Where the next frame decoded sits in the song.
        func reached(at rate: Double) -> StartPoint {
            guard let startFrame else { return start }
            return .frame(startFrame + decoded, rate: rate)
        }
    }

    /// Why a decoded buffer waits (`Feed.parked`) rather than going on its lane's node now. A completion
    /// on the lane pumps again, and the buffer goes on once the wait is over.
    private enum Wait {
        /// The lane still holds songs that play before the one scheduled last (44.1 kHz, a short 96 kHz
        /// song, 44.1 kHz again): laid on now, it would play ahead of the song between.
        case earlierSongs
        /// The lane's node has played everything put on it - AVAudioEngine has called every buffer back -
        /// and its last completion hasn't been handled (`ranOut`): laid on now, it would play after the
        /// silence while the count has it straight on.
        case ranOut
    }

    /// The next song failed while the one heard was still playing: the heard one plays to its end,
    /// and the failure is said then, at that song.
    private struct FailedNext {
        var key: Int
        let failure: AudioFailure
        let at: StartPoint
    }

    /// An entry (by its key) and a point in its song: where the engine is, or was left.
    typealias Spot = (key: Int, at: StartPoint)

    private var lanes: [LaneKey: Lane] = [:]
    private var heardLane: LaneKey?
    /// The lane the song scheduled last went on: the one that plays last.
    private var tail: LaneKey?
    private var tracks: [EngineTrack] = []
    /// Each entry's index in `tracks`, by its key.
    private var indexOf: [Int: Int] = [:]
    /// The entry heard (its key).
    private var current: Int?
    private var feed: Feed?
    private var failedNext: FailedNext?
    /// Each timeline entry's queue entry: entry id -> key.
    private var entryKey: [Int: Int] = [:]
    /// Each entry's exact length in seconds, once its decode has ended.
    private var lengths: [Int: Double] = [:]
    private var nextEntry = 1
    private var generation = 0
    private var wantsPlay = false
    private var asleep = true
    private var held: Spot?
    /// The entry `state.fileRate` was read for. A skip, a seek or a queue put back while paused opens
    /// nothing, so the rate of the song before must not be said for the one shown.
    private var rateOf: Int?
    private var lastFailure: AudioFailure?
    /// Every failure said (EngineState.failures).
    private var failureCount = 0
    /// The output's latency as last read, kept with every reading of a node.
    private var lastLatency: Double = 0
    /// When the last play or resume was asked (host seconds), until its first sample is heard.
    private var playAsked: Double?
    private var lastStartSeconds: Double?
    private var idle: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var restart: DispatchWorkItem?
    private var songChange: DispatchWorkItem?
    private var state = EngineState()
    /// Buffers scheduled, and completions handled (any generation, ignored or not) - the tests wait on
    /// the difference (`callbacksOutstanding`).
    private var buffersScheduled = 0
    private var callbacksHandled = 0
    /// When the queue's end was said and when the output last stopped (tests: `endedAt`, `outputStoppedAt`).
    private var ended: Double?
    private var stoppedOutput: Double?
    /// Completions AVAudioEngine has called back, counted on its own thread (tests: `callbacksArrived`).
    private final class Arrivals {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private let arrivals = Arrivals()
    /// Tests: how long after AVAudioEngine calls a buffer back the engine handles it - its completion
    /// thread starved, as on ios.yml's macOS runner, made certain (notes/ios.md "The engine's tests under
    /// load"). Set before `play`.
    var completionLag: TimeInterval = 0
    /// Tests: AVAudioEngine's own completion thread held off - each callback comes this long late, in order,
    /// 20 ms apart (so the first is handled before the next is counted). Set before `play`.
    var callbackLag: TimeInterval = 0
    private let callbackQueue = DispatchQueue(label: "deadwax.engine.callback-lag", qos: .userInitiated)
    /// Tests: how long after the engine asks AVAudioPlayerNode to schedule a buffer the node takes it - its
    /// CommandQueue slow, as on ios.yml's runner, made certain: each scheduleBuffer is performed this much
    /// later, in order, and drained before any node or engine stops (as AVAudioPlayerNode's StopImpl does).
    /// Set before `play`.
    var scheduleLag: TimeInterval = 0
    private let scheduleQueue = DispatchQueue(label: "deadwax.engine.schedule-lag", qos: .userInitiated)
    private func drainScheduling() { if scheduleLag > 0 { scheduleQueue.sync {} } }
    /// Tests: the offline settle taken out (a mutation, for the test that shows it is needed).
    var offlineSettle: TimeInterval = PlaybackEngine.offlineScheduleSettle
    /// Offline (tests) only: when a buffer last went onto a node, or a node was last started (host seconds);
    /// a render waits until `offlineSettle` after it (`renderOffline`).
    private var lastScheduledAt: Double?
    /// AVAudioPlayerNode performs scheduleBuffer on a serial queue of its own for a node attached while the
    /// engine runs (every lane): a render begun before that has run plays the buffer a render late while
    /// the node's clock counts it on time. The phone's output never renders that soon after a buffer it
    /// needs; offline a render can come microseconds after one (notes/ios.md "A node's buffers, taken late").
    /// A bound, not a fence (there is none): 10 ms covered only about 5 ms of a node's queue held off (8 ms
    /// failed every run here), so 30 ms - about 7 s more on the Audio suite - and ios.yml's second run holds
    /// it with every buffer taken 10 ms late.
    static let offlineScheduleSettle: Double = 0.030
    /// The output was started and no song has been started on it since: the next start from silence takes
    /// the start lead. A start on an output already running plays at the next render.
    private var outputFresh = false
    /// When this run of the output was started (host seconds): a render time from before it - left from the
    /// run before a stop - is no time to start a node at.
    private var outputStartedAt: Double?
    /// Tests: a node started from silence offline counts its clock this many frames ahead of its samples,
    /// as one started with play(at:) on a real output does (245-651 frames on this Mac's output, the hold
    /// review's finding 1): played at a time that many frames past, it plays from its first frame at once.
    var clockAhead: AVAudioFramePosition = 0
    /// Tests: no render time for a start from silence, as on an output that hasn't rendered yet - it waits for
    /// one (`renderWaitSeconds`), then falls back to a host time (or at once), as before sample-time starts.
    var noRenderTime = false
    /// Tests, offline: as the output starts, each lane already made reads its render time this many times as a
    /// live node does just after engine.start() until this run's first render (5-12 ms on this Mac's output):
    /// the reading it had before the stop, `staleRenderBehind` frames behind the render's count, stamped 10 ms
    /// after the start (a stop of a few ms, a timestamp ahead of its render). Only `ofThisRun` tells it apart.
    var staleRenderReads = 0
    var staleRenderBehind: AVAudioFramePosition = 0
    /// Tests, offline: the render's time carries a host time this far ahead of now, as a real output's does
    /// (24.8 ms on this Mac's) - so the start lead is counted as a play(at:) host time counts it.
    var renderHostAhead: Double?
    /// Tests, offline: the render time a join reads is this many frames behind the render's count - a live
    /// node's last render time is that render's FIRST sample, so with a render larger than the margin
    /// (`ioBuffer`), every callback can be in while the end is still ahead of it (the `!ranOut(heard)` guard).
    var joinRenderBehind: AVAudioFramePosition = 0
    /// A start from silence waiting for this run's first render (`playFromSilence`): when it was first asked
    /// (host seconds) - the moment its lead counts from - and the wait's next look.
    private var startAsked: Double?
    private var renderWait: DispatchWorkItem?
    /// How long a start from silence waits for a render of this run of the output before it starts at a host
    /// time (or one IO buffer's four, if longer); and how often it looks.
    static let renderWaitSeconds = 0.1
    static let renderPollSeconds = 0.002
    /// Tests: the lead each start from silence took (what the phone's play(at:) would have waited).
    private var startLeads: [Double] = []
    var leadsTaken: [Double] { queue.sync { startLeads } }
    /// Tests: each lane's buffers scheduled since it began and the callbacks AVAudioEngine made of them, its
    /// completions to come, and its node's clock - said when a wait for completions gives up.
    var lanesSaid: String {
        queue.sync {
            lanes.values.map { lane -> String in
                let clock = lane.node.lastRenderTime.flatMap { lane.node.playerTime(forNodeTime: $0) }.map { "\($0.sampleTime)" } ?? "nil"
                return "lane \(Int(lane.format.sampleRate)) Hz: started \(lane.started), scheduled \(lane.scheduled), called back \(lane.calls.value), ends \(lane.ends), nodeFrames \(lane.nodeFrames), clock \(clock)"
            }.joined(separator: "; ")
        }
    }

    public init(settings: Settings = Settings()) throws {
        self.settings = settings
        engine = AVAudioEngine()
        try configure(engine)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func configure(_ engine: AVAudioEngine) throws {
        if let format = settings.offline {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        }
        _ = engine.mainMixerNode
        if let observer { NotificationCenter.default.removeObserver(observer) }
        // posted on AVAudioEngine's own thread: nothing there holds the engine (see `enqueue`)
        let queue = self.queue
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: nil) { [weak self] _ in
            queue.async { self?.configurationChanged() }
        }
    }

    // MARK: the calls

    /// Plays `tracks` from `index`, `seconds` in.
    public func play(_ tracks: [EngineTrack], from index: Int, at seconds: Double = 0) {
        let asked = Self.hostSeconds()
        queue.async {
            self.setTracks(tracks, fresh: true)
            self.wantsPlay = true
            self.playAsked = asked
            self.begin(at: index, from: seconds > 0 ? .seconds(seconds) : .beginning)
        }
    }

    /// A queue put back paused (resume what was playing): `index`, `seconds` in, shown and held -
    /// nothing opened, fetched or played, the output left off. Play opens it from there.
    public func restoreQueue(_ tracks: [EngineTrack], at index: Int, seconds: Double) {
        queue.async {
            self.setTracks(tracks, fresh: true)
            self.wantsPlay = false
            self.begin(at: index, from: seconds.isFinite && seconds > 0 ? .seconds(seconds) : .beginning)
        }
    }

    /// Up Next changed what comes after the song heard (the tracks up to and including it are the
    /// same, by key). True: the engine follows `tracks` from here. False: nothing changed - the edit
    /// would change a song already scheduled on a node (the next one, in the last seconds of the song
    /// heard), or the song heard isn't where it was in them - and the app holds it, to make it again
    /// after the next song change against the queue as it is then. The song heard is never touched.
    /// Waits on the engine's queue, like `position()`.
    public func replaceUpcoming(_ tracks: [EngineTrack]) -> Bool {
        queue.sync { replaceUpcomingNow(tracks) }
    }

    public func pause() {
        queue.async { self.pauseNow() }
    }

    public func resume() {
        let asked = Self.hostSeconds()
        queue.async { self.resumeNow(asked: asked) }
    }

    /// Another entry of the tracks, from its start. Paused, it stays paused there.
    public func skip(to index: Int) {
        queue.async { self.begin(at: index, from: .beginning) }
    }

    /// `seconds` into the song heard - turned into a frame by the song's source, at the file's own
    /// rate, so a seek before the song has been heard (paused, or still loading) lands where it says.
    /// Paused, nothing loads: play opens it there.
    public func seek(to seconds: Double) {
        queue.async {
            guard let at = self.heard(), let index = self.indexOf[at.key] else { return }
            self.begin(at: index, from: .seconds(seconds))
        }
    }

    public func stop() {
        queue.async {
            self.wantsPlay = false
            self.reset()
            self.current = nil
            self.held = nil
            self.lastFailure = nil
            self.publish(.idle)
            self.armIdle()
        }
    }

    /// The entry heard, its index in the current tracks, and how far in - what the listener hears.
    /// While a seek waits for its bytes, the seek's target.
    public func position() -> EnginePosition? {
        queue.sync {
            guard let at = heard(), let index = indexOf[at.key] else { return nil }
            return EnginePosition(key: at.key, index: index, seconds: at.at.seconds, length: lengths[at.key])
        }
    }

    /// What Debug shows.
    public func debug() -> EngineDebug {
        queue.sync {
            var debug = EngineDebug()
            debug.lanes = lanes.sorted { ($0.key.rate, $0.key.channels) < ($1.key.rate, $1.key.channels) }.map { key, lane in
                let rendered = lane.started ? max(sample(of: lane) ?? lane.lastRead?.frame ?? 0, 0) : 0
                return EngineDebug.Lane(rate: lane.format.sampleRate, channels: Int(lane.format.channelCount),
                                        nodeRate: lane.nodeFormat.sampleRate, converting: lane.converter != nil,
                                        aheadSeconds: Double(max(lane.timeline.end - rendered, 0)) / lane.format.sampleRate,
                                        pendingBuffers: lane.pending, started: lane.started, heard: heardLane == key)
            }
            debug.outputRate = state.outputRate
            debug.latency = lastLatency
            debug.lastStartLead = state.lastStartLead
            debug.lastStartSeconds = lastStartSeconds
            debug.outputRunning = engine.isRunning
            debug.asleep = asleep
            debug.phase = state.phase
            debug.key = current
            debug.feedKey = feed?.key
            return debug
        }
    }

    /// After AVAudioSession's media services were reset: the old engine and its nodes are dead, and
    /// nothing is asked of them - a new engine, and on from where the song was heard when it was
    /// playing. Paused, ended or failed, it stays so (a failure with its words), as after a new route.
    public func rebuild() {
        queue.async {
            let at = self.heard(readingNodes: false)
            let playing = self.wantsPlay
            self.reset(touchingNodes: false)
            self.lanes.removeAll()
            self.heardLane = nil
            self.engine = AVAudioEngine()
            self.note("media services reset: a new engine")
            do {
                try self.configure(self.engine)
            } catch {
                self.held = at
                self.fail(AudioFailure("iOS couldn't make a new audio engine: \(error.localizedDescription)"))
                return
            }
            self.asleep = true
            self.held = at
            guard playing else {
                // as after a new route: ended stays ended (play still starts the queue's own rule, not
                // the end frame again) and a failure keeps its words; a pause stays a pause
                self.publish(self.state.phase == .playing || self.state.phase == .loading ? .paused : self.state.phase)
                return
            }
            self.resumeFrom(at, playing: true)
        }
    }

    // MARK: offline rendering (tests)

    /// Renders `frames` frames offline. Only with `Settings.offline`.
    public func renderOffline(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        try queue.sync {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames) else {
                throw AudioFailure("No memory for \(frames) frames.")
            }
            if let scheduled = lastScheduledAt {
                // a buffer just put on, or a node just started: the node takes it on its own queue first
                let wait = scheduled + offlineSettle - Self.hostSeconds()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                lastScheduledAt = nil
            }
            var done: AVAudioFrameCount = 0
            var silent: AVAudioFrameCount = 0
            let chunk = engine.manualRenderingMaximumFrameCount
            guard let piece = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk),
                  let into = buffer.floatChannelData, let from = piece.floatChannelData else {
                throw AudioFailure("No memory for the render.")
            }
            while done < frames {
                let wanted = min(chunk, frames - done)
                guard engine.isRunning else {
                    // a stopped output (paused, the queue ended) plays nothing, as on the phone
                    for channel in 0..<Int(buffer.format.channelCount) {
                        (into[channel] + Int(done)).update(repeating: 0, count: Int(wanted))
                    }
                    done += wanted
                    silent += wanted
                    continue
                }
                let status = try engine.renderOffline(wanted, to: piece)
                guard status == .success else { throw AudioFailure("Offline render: \(status.rawValue)") }
                for channel in 0..<Int(buffer.format.channelCount) {
                    (into[channel] + Int(done)).update(from: from[channel], count: Int(piece.frameLength))
                }
                done += piece.frameLength
            }
            buffer.frameLength = done
            // said, so a render that comes out silent says whether the output was stopped (ios.yml's
            // aJoinIsTheTwoSongsLaidEndToEnd: silent throughout, once)
            if silent > 0 { note("rendered \(silent) of \(frames) frames as silence: the output is stopped") }
            return buffer
        }
    }

    /// Waits until everything queued on the engine has run (tests).
    public func settle() { queue.sync {} }

    /// Tests: the phase now, without waiting for `onChange` on the main queue.
    var phase: EngineState.Phase { queue.sync { state.phase } }

    /// Tests: the state now, without waiting for `onChange`.
    var stateNow: EngineState { queue.sync { state } }

    /// Tests: whether the output is running - what iOS goes by to call the app playing.
    var outputRunning: Bool { queue.sync { engine.isRunning } }

    /// Tests: buffers the render has passed whose completions the engine hasn't handled yet. AVAudioEngine
    /// calls them back on its own thread after the render, so a test rendering in pieces waits for this
    /// to be 0 before the next piece - the phone has them long before its render needs them, 2 s ahead.
    var completionsDue: Int {
        queue.sync {
            lanes.values.reduce(0) { due, lane in
                guard lane.started, let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
                      let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return due }
                return due + lane.ends.prefix { $0 <= playerTime.sampleTime }.count
            }
        }
    }

    /// Tests: buffers scheduled whose completions haven't been handled yet, whatever called them back - a
    /// render, or a stop letting them go (AVAudioEngine calls back every buffer still scheduled then).
    var callbacksOutstanding: Int { queue.sync { buffersScheduled - callbacksHandled } }

    /// Tests: completions AVAudioEngine has called back so far, handled or not.
    var callbacksArrived: Int { arrivals.value }

    /// Tests: completions the engine has handled so far (any generation, ignored or not).
    var callbacksDone: Int { queue.sync { callbacksHandled } }

    /// Tests: a configuration change's restart waits (`changeSettleSeconds`) and hasn't been let go.
    var restartWaiting: Bool { queue.sync { restart != nil } }

    /// Tests: when the queue's end was said, and when the output last stopped (host seconds) - the
    /// linger between them is the engine's own clock's, whatever the test's thread was doing.
    var endedAt: Double? { queue.sync { ended } }
    var outputStoppedAt: Double? { queue.sync { stoppedOutput } }

    /// Tests: iOS stopping the engine (a call, a new route) - and, with `change`, the configuration
    /// change it posts, handled as the notification's would be.
    func systemStopped(change: Bool) {
        queue.sync {
            drainScheduling()
            engine.stop()
            if change { configurationChanged() }
        }
    }

    // MARK: on the queue

    static func hostSeconds() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

    private func setTracks(_ new: [EngineTrack], fresh: Bool) {
        tracks = new
        var index: [Int: Int] = [:]
        for (at, track) in new.enumerated() where index[track.key] == nil { index[track.key] = at }
        indexOf = index
        if fresh {
            lengths.removeAll()
            rateOf = nil
        } else {
            lengths = lengths.filter { index[$0.key] != nil }
        }
    }

    private func begin(at index: Int, from start: StartPoint) {
        reset()
        lastFailure = nil
        guard tracks.indices.contains(index) else {
            finish()
            return
        }
        let key = tracks[index].key
        current = key
        held = (key, start)
        guard wantsPlay else {
            // a skip, a seek or a queue put back while paused: nothing opens and the output stays off
            // (iOS would count it as playing) - play opens it from `held`
            sleep()
            publish(.paused)
            return
        }
        do {
            feed = Feed(key: key, source: try tracks[index].open(start), start: start)
        } catch {
            fail(error)
            return
        }
        guard ensureRunning() else { return }
        publish(.loading)
        pump()
    }

    @discardableResult
    private func ensureRunning() -> Bool {
        idle?.cancel()
        idle = nil
        if engine.isRunning { return true }
        matchOutput()
        engine.prepare()
        do {
            outputStartedAt = Self.hostSeconds()
            try engine.start()
            for lane in lanes.values {
                if settings.offline == nil {
                    lane.renderAtStart = lane.node.lastRenderTime.map { $0.sampleTime }
                } else {
                    // tests: the reading a live node has just after a start, left from the run before
                    lane.staleReads = staleRenderReads
                    lane.staleReading = staleRenderReads > 0
                        ? RenderTime(sample: engine.manualRenderingSampleTime - staleRenderBehind, host: (outputStartedAt ?? 0) + 0.010)
                        : nil
                    lane.renderAtStart = lane.staleReading?.sample
                }
            }
            asleep = false
            outputFresh = true
            note("the output started")
            return true
        } catch {
            fail(AudioFailure("iOS wouldn't start the audio: \(error.localizedDescription)"))
            return false
        }
    }

    /// The output stopped and marked asleep: play makes everything again from `held`.
    private func sleep() {
        idle?.cancel()
        idle = nil
        if engine.isRunning {
            drainScheduling()
            engine.stop()
            stoppedOutput = Self.hostSeconds()
            note("the output stopped")
        }
        outputFresh = false
        asleep = true
    }

    /// The main mixer connected to the output at the hardware's rate - which a new route can change
    /// (AirPlay, a USB DAC) - before lanes are made for it, so iOS's output never converts a second
    /// time after a lane's own converter. Lanes made for another rate are made again. Only on a
    /// stopped engine, never offline.
    private func matchOutput() {
        guard settings.offline == nil, !engine.isRunning else { return }
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0 else { return }
        let mixer = engine.mainMixerNode.outputFormat(forBus: 0)
        if mixer.sampleRate != hardware.sampleRate {
            let channels = mixer.channelCount > 0 ? mixer.channelCount : min(max(hardware.channelCount, 1), 2)
            if let format = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: channels) {
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
                note("the mixer reconnected to the output at \(Int(hardware.sampleRate)) Hz")
            }
        }
        let rate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        for (key, lane) in lanes where lane.nodeFormat.sampleRate != rate && lane.timeline.isEmpty {
            drainScheduling()
            engine.detach(lane.node)
            lanes[key] = nil
        }
    }

    /// Everything scheduled let go: the nodes stopped (unless they belong to a dead engine, after a
    /// media services reset), the feed closed, every wait cancelled.
    private func reset(touchingNodes: Bool = true) {
        generation += 1
        retry?.cancel()
        retry = nil
        restart?.cancel()
        restart = nil
        songChange?.cancel()
        songChange = nil
        renderWait?.cancel()
        renderWait = nil
        startAsked = nil
        drainScheduling()
        for lane in lanes.values {
            if touchingNodes { lane.node.stop() }
            lane.clear()
            lane.resetConverter()
        }
        heardLane = nil
        tail = nil
        feed?.source.close()
        feed = nil
        failedNext = nil
        entryKey.removeAll()
    }

    private func frames(_ seconds: Double, _ rate: Double) -> Int64 { Int64(seconds * rate) }

    /// The rate the main mixer runs at - the output's, or the offline render's.
    private var outputRate: Double {
        settings.offline?.sampleRate ?? engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
    }

    private func laneFor(_ format: AVAudioFormat) -> Lane {
        let key = LaneKey(format)
        if let lane = lanes[key] { return lane }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        let output = outputRate
        var nodeFormat = format
        var converter: AVAudioConverter?
        if output > 0, output != format.sampleRate,
           let converted = floatFormat(sampleRate: output, channels: format.channelCount),
           let made = AVAudioConverter(from: format, to: converted) {
            made.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
            made.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            // the output lines up with the input, frame 0 with frame 0: nothing ahead of the song
            made.primeMethod = .normal
            nodeFormat = converted
            converter = made
        }
        engine.connect(node, to: engine.mainMixerNode, format: nodeFormat)
        let lane = Lane(node: node, format: format, nodeFormat: nodeFormat, converter: converter)
        lanes[key] = lane
        note("lane \(Int(format.sampleRate)) Hz x \(format.channelCount): its node at \(Int(nodeFormat.sampleRate)) Hz")
        return lane
    }

    /// One line for `trace`.
    private func note(_ words: @autoclosure () -> String) {
        guard let trace else { return }
        let at = settings.offline != nil ? "\(engine.manualRenderingSampleTime) " : String(format: "%.3f ", Self.hostSeconds())
        trace(at + words())
    }

    /// The output's latency now, kept for the readings that follow.
    private func currentLatency() -> Double {
        let read = latency()
        lastLatency = read.isFinite ? max(read, 0) : 0
        return lastLatency
    }

    /// The render's position on the lane's node now, in the songs' frames, once it is playing - kept
    /// as the lane's `lastRead`, with the output's latency read now (`lastLatency` after it). Nil when
    /// the engine isn't running (iOS stopped it, or it is asleep) or the node isn't playing.
    private func sample(of lane: Lane) -> Int64? {
        guard lane.started, let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return nil }
        let frame = lane.songFrames(playerTime.sampleTime)
        var at: Double?
        if settings.offline == nil {
            at = nodeTime.isHostTimeValid ? AVAudioTime.seconds(forHostTime: nodeTime.hostTime) : Self.hostSeconds()
        }
        // the latency of the route this reading was taken on, read with it: the estimate after iOS stops
        // the engine takes it back from the frame. It was the latency read before - offline 0 until a
        // buffer's completion had read one, and on the phone the old route's for the first reading on a
        // new one (notes/ios.md "The engine's tests under load")
        lane.lastRead = HeardReading(frame: frame, at: at, latency: currentLatency())
        lane.stopped = nil
        return frame
    }

    /// The frame heard on the lane: the output's latency behind the render - or, when the node's clock
    /// can't be read because iOS stopped the engine before telling it (or it is dead), estimated from
    /// the last reading, once, and kept.
    private func heardFrame(of lane: Lane, readingNodes: Bool = true) -> Int64? {
        let rate = lane.format.sampleRate
        if readingNodes, let rendered = sample(of: lane) {
            return HeardEstimate.heard(rendered: rendered, latency: lastLatency, rate: rate)
        }
        if let stopped = lane.stopped { return stopped }
        guard let reading = lane.lastRead else { return nil }
        let stoppedByIOS = !readingNodes || !engine.isRunning
        let now = stoppedByIOS && settings.offline == nil ? Self.hostSeconds() : nil
        let estimate = HeardEstimate.atStop(reading, now: now, rate: rate, end: lane.timeline.end)
        if stoppedByIOS {
            lane.stopped = estimate
            note("the clock gone: heard at frame \(estimate), from a reading at \(reading.frame)")
        }
        return estimate
    }

    private func ahead(_ lane: Lane) -> Int64 {
        lane.timeline.end - max(sample(of: lane) ?? 0, 0)
    }

    /// Decodes and schedules until the feed's lane holds `aheadSeconds` past what is rendered.
    private func pump() {
        while var feeding = feed {
            if let key = feeding.lane, let lane = lanes[key],
               ahead(lane) >= frames(settings.aheadSeconds, lane.format.sampleRate) {
                break
            }
            let result: PCMRead
            if let parked = feeding.parked {
                feeding.parked = nil
                result = .frames(parked)
            } else {
                let rate = feeding.source.format?.sampleRate ?? 48_000
                let size = AVAudioFrameCount(max(frames(settings.bufferSeconds, rate), 1024))
                do {
                    result = try feeding.source.read(maxFrames: size)
                } catch {
                    feedFailed(error)
                    return
                }
            }
            switch result {
            case .waiting:
                // a seek working through what has arrived goes on at once; a stream waits for bytes
                scheduleRetry(soon: feeding.source.busy)
                flushBeforeRunningOut()
                startLanesIfReady()
                return
            case .end:
                endFeed()
            case .frames(let buffer):
                if let wait = schedule(buffer, feed: &feeding) {
                    // held until the wait is over (a completion on the lane pumps again)
                    if wait != feeding.parkedFor {
                        switch wait {
                        case .earlierSongs:
                            note("entry \(feeding.key) parked: its lane still holds songs before the one scheduled last")
                        case .ranOut:
                            note("entry \(feeding.key) held: its lane's node has played all on it, its last completion to come")
                        }
                    }
                    feeding.parked = buffer
                    feeding.parkedFor = wait
                    feed = feeding
                    startLanesIfReady()
                    return
                }
                feeding.parkedFor = nil
                feed = feeding
            }
        }
        if endIfNothingLeft() { return }
        startLanesIfReady()
    }

    /// Nothing scheduled and nothing left to decode (a song with no audio in it at the queue's end, or a
    /// next one that wouldn't open after it): no completion will come to say so - the queue ends here, or
    /// the next song's failure is said. True when it did.
    private func endIfNothingLeft() -> Bool {
        guard feed == nil, wantsPlay, !lanes.values.contains(where: { !$0.timeline.isEmpty }) else { return false }
        if let failed = failedNext {
            failedNext = nil
            current = failed.key
            held = (failed.key, failed.at)
            fail(failed.failure)
        } else {
            finish()
        }
        return true
    }

    /// The feed's source failed. When it is the next song and the one heard is still playing, the
    /// heard one plays to its end and the failure is said there, at the song that failed (so a 401
    /// on the next song's stream stops the queue at that song, not seconds before it); otherwise now.
    private func feedFailed(_ error: Error) {
        let failure = AudioFailure.from(error)
        guard let feeding = feed else {
            fail(failure)
            return
        }
        let rate = feeding.source.format?.sampleRate ?? 0
        let othersPlaying = heardLane != nil && wantsPlay && lanes.values.contains { lane in
            lane.timeline.entries.contains { entry in entry.frames > 0 && entryKey[entry.id] != feeding.key }
        }
        guard feeding.key != current, othersPlaying else {
            fail(failure)
            return
        }
        note("the next song failed (\(failure.description)): said when the song heard ends")
        failedNext = FailedNext(key: feeding.key, failure: failure, at: feeding.reached(at: rate))
        feeding.source.close()
        feed = nil
        if let last = tail, let lane = lanes[last] { flush(lane, key: last) }
        startLanesIfReady()
    }

    /// Schedules a decoded buffer on its format's lane (nil) - or doesn't, and says why it waits:
    /// - a song that begins on a lane still holding songs that play BEFORE the one scheduled last
    ///   (44.1 kHz, then a short 96 kHz song on its own lane, then 44.1 kHz again while the first is
    ///   still playing) would be laid straight after the first song, ahead of the one between. It waits
    ///   for that lane to run out instead (`played` clears it), and then goes on it to start when the
    ///   last lane ends.
    /// - a lane whose node has played all on it (every buffer called back), its last completion not
    ///   handled yet (`ranOut`): the node's clock runs on through the silence, so what went on now would
    ///   play after it while the count - the position, every resume point, the next lane's start - had
    ///   it straight on, ahead by the silence for the rest of the lane. It waits for that completion, which starts the lane
    ///   again from the frame it reached (`played`, the stream-behind path).
    private func schedule(_ decoded: AVAudioPCMBuffer, feed feeding: inout Feed) -> Wait? {
        let key = LaneKey(decoded.format)
        let beginning = feeding.lane != key || feeding.entry == nil
        if beginning, let last = tail, last != key, let lastLane = lanes[last] {
            // the lane scheduled last has had its last song for now: what its converter holds goes on
            flush(lastLane, key: last)
        }
        if beginning, let busy = lanes[key], !busy.timeline.isEmpty,
           let last = tail, last != key, let lastLane = lanes[last], !lastLane.timeline.isEmpty {
            return .earlierSongs
        }
        if let target = lanes[key], ranOut(target) {
            return .ranOut
        }
        let lane = laneFor(decoded.format)
        let buffer = conform(decoded, to: lane.format)
        if feeding.startFrame == nil {
            // the same frame the source started at: it turned the start point into a frame at
            // this same rate, its own
            feeding.startFrame = feeding.start.frame(at: decoded.format.sampleRate)
        }
        if beginning {
            let id = nextEntry
            nextEntry += 1
            feeding.lane = key
            feeding.entry = id
            tail = key
            entryKey[id] = feeding.key
            lane.timeline.begin(id: id, songOffset: (feeding.startFrame ?? 0) + feeding.decoded)
        }
        guard let id = feeding.entry else { return nil }
        lane.timeline.extend(id: id, frames: Int64(buffer.frameLength))
        feeding.decoded += Int64(buffer.frameLength)
        if let converter = lane.converter {
            convert(buffer, with: converter, on: lane, key: key)
        } else {
            enqueue(buffer, on: lane, key: key)
        }
        return nil
    }

    /// The lane's node has played everything put on it and its last completion is still to be handled:
    /// late (a busy phone, a starved thread - made certain with `completionLag`), or beaten by a stream's
    /// retry that has just found bytes. The node's clock is past the count until that completion starts
    /// the lane again or clears it (notes/ios.md "The engine's tests under load", "The hold on the
    /// callbacks").
    ///
    /// Told by the callbacks, never the clock: AVAudioEngine has called back every buffer put on the node
    /// since it began - each `.dataRendered`, the render having taken its last sample - and the engine has
    /// not handled them all. The node's clock can't say it: a node started with play(at:) on a real output
    /// counts from the time asked while its first sample lands on a render's edge, and a buffer taken late
    /// by the node's own queue is counted on time - the clock reads "played all" while frames are still to
    /// come (the hold review's finding 1: 580-1092 frames on this Mac's output), and a buffer held then
    /// became a rebuffer where scheduling straight on was seamless.
    ///
    /// One backstop reads the clock, past any error it has: the node's clock a quarter of a second past all
    /// on it (`ranOutBackstopSeconds`). It covers AVAudioEngine's own completion thread held off for longer
    /// than what is ahead: its callbacks then come in a burst, and the first one handled can pump before the
    /// others are counted.
    private func ranOut(_ lane: Lane) -> Bool {
        guard lane.started, !lane.ends.isEmpty, engine.isRunning else { return false }
        if lane.calls.value >= lane.scheduled { return true }
        guard let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return false }
        return playerTime.sampleTime - lane.nodeFrames > frames(Self.ranOutBackstopSeconds, lane.nodeFormat.sampleRate)
    }

    /// Far past what a node's clock is ever off by: a play(at:) start's render edge (under 1.5 IO buffers;
    /// 85 ms each when locked), a buffer the node took a render late.
    static let ranOutBackstopSeconds = 0.25

    /// One buffer onto the lane's node. Its completion is `.dataRendered`: the moment the render
    /// has taken the buffer's last sample, which is what the engine's bookkeeping needs (the lane fed,
    /// the next lane started in time, a lane known to be done). `.dataPlayedBack` comes the output's
    /// latency later - offline, later than a half-second song in another format lasted (ios.yml's
    /// first macOS run), so the song after it started late.
    ///
    /// The completion comes on AVAudioPlayerNode's own completion queue, and nothing there holds the
    /// engine: were its last reference released there, AVAudioEngine's dealloc would stop these nodes
    /// on that queue, which traps (a test's engine let go with completions on their way, under load).
    private func enqueue(_ buffer: AVAudioPCMBuffer, on lane: Lane, key: LaneKey) {
        guard buffer.frameLength > 0 else { return }
        lane.nodeFrames += Int64(buffer.frameLength)
        lane.ends.append(lane.nodeFrames)
        lane.scheduled += 1
        buffersScheduled += 1
        let generation = self.generation
        let queue = self.queue
        let lag = completionLag
        let arrivals = self.arrivals
        let calls = lane.calls
        let epoch = lane.epoch
        let delivery = callbackLag > 0 ? callbackQueue : nil
        let deliveryLag = callbackLag
        let completion: AVAudioPlayerNodeCompletionHandler = { [weak self] _ in
            let body = {
                arrivals.add()
                calls.add(epoch)
                let handle: () -> Void = { self?.played(generation: generation, lane: key) }
                if lag > 0 {
                    queue.asyncAfter(deadline: .now() + lag, execute: handle)
                } else {
                    queue.async(execute: handle)
                }
            }
            guard let delivery else { return body() }
            // AVAudioEngine's completion thread held off: its callbacks come late, in a burst, one by one
            delivery.asyncAfter(deadline: .now() + deliveryLag) {
                body()
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        if scheduleLag > 0 {
            let node = lane.node
            let due = Self.hostSeconds() + scheduleLag
            scheduleQueue.async {
                let wait = due - Self.hostSeconds()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                // a node detached meanwhile takes nothing (scheduling on one is an exception)
                guard node.engine != nil else { return }
                node.scheduleBuffer(buffer, completionCallbackType: .dataRendered, completionHandler: completion)
            }
        } else {
            lane.node.scheduleBuffer(buffer, completionCallbackType: .dataRendered, completionHandler: completion)
        }
        if settings.offline != nil { lastScheduledAt = Self.hostSeconds() }
    }

    /// A decoded buffer through the lane's converter, and what comes out onto its node. The input is
    /// handed over as the converter asks for it, so none of it is left behind in the converter's
    /// keeping between calls; what its filter still needs to see more of, it holds until the next
    /// buffer, or `flush`.
    private func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter, on lane: Lane, key: LaneKey) {
        let ratio = lane.nodeFormat.sampleRate / lane.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1_024
        var offset: AVAudioFrameCount = 0
        while offset < input.frameLength {
            guard let out = AVAudioPCMBuffer(pcmFormat: lane.nodeFormat, frameCapacity: capacity) else { return }
            let before = offset
            var failure: NSError?
            let status = converter.convert(to: out, error: &failure) { wanted, inputStatus in
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
            lane.holding = true
            enqueue(out, on: lane, key: key)
            if status == .error {
                note("the converter failed: \(failure?.localizedDescription ?? "no reason given")")
                return
            }
            // nothing taken and nothing given: the converter is stuck - never spin on it
            if offset == before && out.frameLength == 0 { return }
        }
    }

    /// What the lane's converter holds, given out onto its node: the lane's last song for now has
    /// all been decoded. The converter starts afresh for the lane's next song.
    private func flush(_ lane: Lane, key: LaneKey) {
        guard let converter = lane.converter, lane.holding else { return }
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: lane.nodeFormat, frameCapacity: 4_096) else { break }
            var failure: NSError?
            let status = converter.convert(to: out, error: &failure) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            enqueue(out, on: lane, key: key)
            if status != .haveData || out.frameLength == 0 { break }
        }
        lane.resetConverter()
        note("lane \(Int(lane.format.sampleRate)) Hz flushed: \(lane.nodeFrames) frames on its node")
    }

    /// The lane scheduled last converts, its converter holds the end of its last song (12-13 ms: what its
    /// filter still needs more input to give out, kept so the next song in its format joins through one
    /// converter), that song's decode is over and the next song hasn't begun - its bytes not come - and the node
    /// is about to play out all on it: what the converter holds goes on now, so the song plays to its end on
    /// time. Left in, it went on only once the node had run out - a gap, the song's last 13 ms alone, then the
    /// rebuffer's silence (the verifiers' tail scrap). The next song then begins through a converter started
    /// afresh, as a song after a rebuffer does; come in these last moments, its join is the one place that
    /// loses the single converter. Looked at on every retry while the next song waits (`retrySeconds`), so the
    /// window is a retry, two IO buffers and 20 ms more; the node's clock, if ahead, only makes it sooner.
    private func flushBeforeRunningOut() {
        guard let feeding = feed, feeding.entry == nil, let key = tail, let lane = lanes[key], lane.started,
              lane.holding, lane.converter != nil, !ranOut(lane),
              let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return }
        let window = frames(settings.retrySeconds + 2 * max(ioBuffer(), 0) + 0.02, lane.nodeFormat.sampleRate)
        guard lane.nodeFrames - playerTime.sampleTime <= window else { return }
        note("lane \(Int(lane.format.sampleRate)) Hz about to play out all on it, the next song not here: its converter's last frames on now")
        flush(lane, key: key)
    }

    /// The same samples in the lane's own AVAudioFormat object, when the decoder's differs only in
    /// its channel layout - a player node takes only buffers in the format it is connected with.
    private func conform(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        if buffer.format.isEqual(format) { return buffer }
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let from = buffer.floatChannelData, let into = copy.floatChannelData else { return buffer }
        for channel in 0..<Int(format.channelCount) {
            into[channel].update(from: from[channel], count: Int(buffer.frameLength))
        }
        copy.frameLength = buffer.frameLength
        return copy
    }

    /// The feed's song has all been decoded: close its entry and open the next song, which will
    /// be scheduled straight after on the same lane when its format is the same. (A next song in
    /// another format flushes this lane's converter when its first buffer is scheduled - not before,
    /// so a next song let go by an edit before then leaves the converter unbroken for its successor.)
    private func endFeed() {
        guard let ended = feed else { return }
        if let key = ended.lane, let id = ended.entry { lanes[key]?.timeline.close(id: id) }
        if let startFrame = ended.startFrame, let rate = ended.source.format?.sampleRate, rate > 0 {
            lengths[ended.key] = Double(startFrame + ended.decoded) / rate
        }
        ended.source.close()
        feed = nil
        openAfter(ended.key, lane: ended.lane)
    }

    /// Opens the entry after `key` from its beginning, as the feed - or, with none (the queue's
    /// end), or one that won't open, lets `laneKey`'s converter give out what it holds.
    private func openAfter(_ key: Int, lane laneKey: LaneKey?) {
        let flushEnded = {
            if let laneKey, let lane = self.lanes[laneKey] { self.flush(lane, key: laneKey) }
        }
        guard let at = indexOf[key], tracks.indices.contains(at + 1) else {
            flushEnded()
            return
        }
        let next = tracks[at + 1]
        do {
            feed = Feed(key: next.key, source: try next.open(.beginning), start: .beginning)
        } catch {
            // the song heard plays to its end; the failure is said there
            feed = nil
            failedNext = FailedNext(key: next.key, failure: AudioFailure.from(error), at: .beginning)
            flushEnded()
        }
    }

    /// Starts each lane that has something scheduled and isn't playing: from silence with the
    /// start lead, or - a song in another format next - at the moment the heard lane runs out.
    private func startLanesIfReady() {
        // A node played on a stopped engine raises an exception that ends the app. iOS stops the
        // engine on its own (a call, a new route) a moment before its notification is handled, and
        // a retry or a buffer's completion can land here in that gap.
        guard wantsPlay, engine.isRunning else { return }
        if heardLane == nil, !lanes.values.contains(where: { $0.started }), moveOnFromNothingLeft() { return }
        // the song heard first: its lane starts from silence (or is already playing)
        if heardLane == nil, let key = laneHolding(current), let lane = lanes[key], !lane.started, ready(lane, key) {
            // false: it waits for this run's first render
            guard playFromSilence(lane) else { return }
            lane.started = true
            heardLane = key
            note("lane \(Int(lane.format.sampleRate)) Hz started from silence \(lane.origin.map { "at \($0)" } ?? "at a host time: no render of this run in \(Int(renderWaitBound() * 1000)) ms")")
            publish(.playing)
        }
        // then a song in another format after it: its lane starts at the very sample the heard lane's last one
        // plays at, a node SAMPLE time (exact once its converter has given out all it holds) - a host time
        // overlapped the two by 238-723 frames on this Mac's output (notes/ios.md "Starts at a sample time")
        // - never at an end already rendered: a node played at a time past counts from it, so its count
        // runs ahead and the song after it overlaps its end (the hold review's finding 5). It waits for
        // the heard lane's last completion, and starts from silence (`played`).
        // - and only the lane whose song comes next: a song in a third format, decoded while the heard lane
        // still plays (the one between shorter than what is scheduled ahead), waits for that one to be heard,
        // or it started at the same end and played over it
        guard let heardKey = heardLane, let heard = lanes[heardKey], heard.started, heard.pending > 0,
              !heard.holding, !ranOut(heard), let end = endTime(of: heard),
              let now = renderTime(heard).map({ $0.sample - joinRenderBehind }) else { return }
        guard !lanes.contains(where: { $0.key != heardKey && $0.value.started }) else { return }
        let waiting = lanes.filter { $0.key != heardKey && !$0.value.started && !$0.value.timeline.isEmpty }
        guard let (key, lane) = waiting.min(by: { ($0.value.timeline.entries.first?.id ?? .max) < ($1.value.timeline.entries.first?.id ?? .max) }),
              ready(lane, key) else { return }
        guard end >= now + margin() else {
            note("lane \(Int(lane.format.sampleRate)) Hz not started at \(end): the render is at \(now) already")
            return
        }
        lane.node.play(at: AVAudioTime(sampleTime: end, atRate: outputRate))
        if settings.offline != nil { lastScheduledAt = Self.hostSeconds() }
        lane.origin = end
        lane.started = true
        note("lane \(Int(lane.format.sampleRate)) Hz to start at \(end), when lane \(Int(heard.format.sampleRate)) Hz ends")
    }

    /// Where the render is, in the lane's node time, and the host time of it: offline, the render's own count (a
    /// node's time there, across a stop too); live, the node's own last render - one of this run of the output
    /// only, never the one it still reads just after a start, left from before the stop (`renderAtStart`, and a
    /// host time before `outputStartedAt`): a start at that time would be in the past. Never the main mixer's:
    /// after a stop and start it counts from 0 again while the nodes' time runs on (notes/ios.md "Starts at a
    /// sample time"). Nil with none yet.
    private func renderTime(_ lane: Lane) -> RenderTime? {
        let read: RenderTime
        if settings.offline != nil {
            if lane.staleReads > 0, let stale = lane.staleReading {
                lane.staleReads -= 1
                read = stale
            } else {
                read = RenderTime(sample: engine.manualRenderingSampleTime, host: renderHostAhead.map { Self.hostSeconds() + $0 })
            }
        } else {
            guard let time = lane.node.lastRenderTime, time.isSampleTimeValid else { return nil }
            read = RenderTime(sample: time.sampleTime, host: time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : nil)
        }
        guard let sample = Self.ofThisRun(read.sample, host: read.host, atStart: lane.renderAtStart, startedAt: outputStartedAt) else {
            return nil
        }
        return RenderTime(sample: sample, host: read.host)
    }

    /// A node's render time (`sample`, and its host time in seconds) if it is one of this run of the output:
    /// not the reading the node had as the output started (`atStart`) and not stamped before the start
    /// (`startedAt`). Just after a stop and start this Mac's output still read the last run's, 505 ms old.
    static func ofThisRun(_ sample: AVAudioFramePosition, host: Double?, atStart: AVAudioFramePosition?,
                          startedAt: Double?) -> AVAudioFramePosition? {
        if sample == atStart { return nil }
        if let host, let startedAt, host < startedAt { return nil }
        return sample
    }

    /// How far past the last render a node is started on an output already running: one IO buffer, so the
    /// start is never inside a render under way. None offline, where nothing renders until asked.
    private func margin() -> AVAudioFramePosition {
        settings.offline != nil ? 0 : frames(max(ioBuffer(), 0), outputRate)
    }

    /// How long a start from silence waits for a render of this run: `renderWaitSeconds`, or four IO buffers
    /// (the screen locked: 85 ms each).
    private func renderWaitBound() -> Double {
        max(Self.renderWaitSeconds, 4 * max(ioBuffer(), 0))
    }

    /// Looks again for this run's first render in `renderPollSeconds` (`playFromSilence`).
    private func waitForRender() {
        guard renderWait == nil else { return }
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.renderWait = nil
            self.startLanesIfReady()
        }
        renderWait = work
        queue.asyncAfter(deadline: .now() + Self.renderPollSeconds, execute: work)
    }

    /// The node time the last sample scheduled on `lane` plays at: where its count starts (the sample time it
    /// was started at, else read off its clock) plus what is on its node.
    private func endTime(of lane: Lane) -> AVAudioFramePosition? {
        let scale = outputRate / lane.nodeFormat.sampleRate
        let end = AVAudioFramePosition((Double(lane.nodeEnd) * scale).rounded())
        if let origin = lane.origin { return origin + end }
        guard let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return nil }
        return nodeTime.sampleTime - AVAudioFramePosition((Double(playerTime.sampleTime) * scale).rounded()) + end
    }

    /// Starts a node from silence at a SAMPLE time, so its first sample lands exactly there and the node's count
    /// with it (`origin`); a host time had the count 245-1030 frames ahead of the samples on this Mac's output
    /// (notes/ios.md "Starts at a sample time").
    /// - On an output just started, at the moment the start lead (output latency and an IO buffer) after it was
    ///   asked, mapped onto the node's samples by its render's own timestamp - the moment 307384f's play(at:) a
    ///   host time asked, which Phase 0 heard lose no start on AirPods - and never before the next render. A
    ///   render's host time runs ahead of now (24.8 ms on this Mac's output), so the lead counted from its
    ///   sample was that much later (the verifiers' finding: 224.8 ms after the call for a 0.2 s lead).
    /// - On an output already running (a lane begun again after running dry, a skip, a seek while playing), at
    ///   the next render: one IO buffer past the last (`margin`).
    /// - With no render of this run of the output yet - play after a pause: the song's second is decoded before
    ///   the output's first render, 5-12 ms after its start on this Mac - it waits for one, looking every 2 ms
    ///   (`renderPollSeconds`), and returns false: starting at a host time there had the count, and the position,
    ///   12-22 ms ahead of the ear and a song in another format over its end (the verifiers' first finding).
    ///   After `renderWaitBound` with none, it starts as before sample-time starts: the lead ahead at a host time
    ///   on an output just started, else at once (exact, if two renders later than a host time - see the notes).
    /// A node a pause left paused (`idleStopSeconds`) goes on at once, its clock saying where it is.
    private func playFromSilence(_ lane: Lane) -> Bool {
        let lead = outputFresh ? max(startLead(), 0) : 0
        let asked = startAsked ?? Self.hostSeconds()
        let rate = outputRate
        var ahead = lead
        if lane.started {
            lane.node.play()
            lane.origin = nil
        } else if !noRenderTime, let now = renderTime(lane) {
            var at = now.sample + margin()
            if clockAhead > 0 {
                at = now.sample - clockAhead
            } else if lead > 0, let host = now.host {
                at = max(at, now.sample + AVAudioFramePosition(((asked + lead - host) * rate).rounded()))
            } else if lead > 0 {
                at = now.sample + frames(lead, rate)
            }
            lane.node.play(at: AVAudioTime(sampleTime: at, atRate: rate))
            lane.origin = at
            let after = Double(at - now.sample) / rate
            ahead = max(now.host.map { $0 + after - Self.hostSeconds() } ?? after, 0)
            if startAsked != nil {
                note(String(format: "lane %d Hz: this run's first render after %.1f ms", Int(lane.format.sampleRate), (Self.hostSeconds() - asked) * 1000))
            }
        } else if Self.hostSeconds() - asked < renderWaitBound() {
            if startAsked == nil { note("lane \(Int(lane.format.sampleRate)) Hz: no render of this run of the output yet, waiting for one") }
            startAsked = asked
            waitForRender()
            return false
        } else {
            // the lead's moment, if it is still to come; once it is past, at once - exact, where a host time
            // already past had the count ahead of the samples
            let left = asked + lead - Self.hostSeconds()
            if lead > 0, left > 0, settings.offline == nil {
                lane.node.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: left)))
            } else {
                lane.node.play()
            }
            lane.origin = nil
        }
        outputFresh = false
        startAsked = nil
        if settings.offline != nil {
            startLeads.append(lead)
            lastScheduledAt = Self.hostSeconds()
        }
        state.lastStartLead = lead
        if let asked = playAsked, settings.offline == nil {
            // its first sample heard: the lead, and the output's latency after it
            lastStartSeconds = Self.hostSeconds() + ahead + currentLatency() - asked
        }
        playAsked = nil
        return true
    }

    /// Enough is scheduled on the lane to start it: `startSeconds`, or all there is - and something. A
    /// node started with nothing on it plays silence with its clock running, and what goes on it after
    /// plays later than the count says (a lane run dry and begun again, with a `startSeconds` of 0).
    /// Something is on the NODE, not only counted: frames a converter still holds are counted on the
    /// timeline but aren't on the node yet, and a converter's tail flushed onto it is on the node but
    /// on no timeline (the hold review's findings 4 and 10: a lane begun again with only its
    /// converter's tail left never started, silent for good).
    private func ready(_ lane: Lane, _ key: LaneKey) -> Bool {
        guard lane.nodeFrames > 0 else { return false }
        return feed?.lane != key || lane.timeline.end >= frames(settings.startSeconds, lane.format.sampleRate)
    }

    /// The song `current` names has nothing left to play - nothing of it on a node or in a converter, its
    /// decode over (its lane begun again at its very last frame, a seek or a resume at its very end) - and
    /// no lane is playing, so no completion will come to move the queue on (the hold review's findings 2
    /// and 11, and a seek to a song's very end). The queue goes on to the first song scheduled after it,
    /// the one decoding, or ends. True when it ended or failed.
    private func moveOnFromNothingLeft() -> Bool {
        guard let key = current, feed?.key != key, failedNext?.key != key else { return false }
        var ended: Spot?
        if let laneKey = laneHolding(key), let lane = lanes[laneKey] {
            // nothing of it on the node, in the converter or counted: only a beginning with no frames
            guard !lane.started, lane.nodeFrames == 0, !lane.holding, lane.timeline.end == 0 else { return false }
            ended = lastSpot(of: lane)
            for entry in lane.timeline.entries { entryKey[entry.id] = nil }
            lane.clear() // never started, nothing on its node: nothing to stop or call back
        }
        let firsts = lanes.values.compactMap { lane in lane.timeline.entries.first.map { (lane, $0) } }
        if let found = firsts.min(by: { $0.1.id < $1.1.id }), let next = entryKey[found.1.id] {
            current = next
            held = (next, .frame(found.1.songOffset, rate: found.0.format.sampleRate))
            note("entry \(key) has nothing left to play: on to entry \(next)")
        } else if let feeding = feed {
            current = feeding.key
            held = (feeding.key, feeding.reached(at: feeding.source.format?.sampleRate ?? 48_000))
            note("entry \(key) has nothing left to play: on to entry \(feeding.key), decoding")
            publish(.loading)
        } else {
            if let ended {
                held = ended
            }
            note("entry \(key) has nothing left to play, and nothing after it")
            return endIfNothingLeft()
        }
        return false
    }

    /// The lane that has the entry `key` scheduled on it.
    private func laneHolding(_ key: Int?) -> LaneKey? {
        guard let key else { return nil }
        return lanes.first(where: { _, lane in
            lane.timeline.entries.contains { entry in entryKey[entry.id] == key }
        })?.key
    }

    private func scheduleRetry(soon: Bool = false) {
        guard retry == nil else { return }
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.retry = nil
            self.pump()
        }
        retry = work
        if soon {
            queue.async(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + settings.retrySeconds, execute: work)
        }
    }

    /// A buffer has been played: keep the lane fed, follow the song heard, and notice a lane that
    /// ran dry - at its end, or mid-song (a stream that didn't keep up).
    private func played(generation: Int, lane key: LaneKey) {
        callbacksHandled += 1
        guard generation == self.generation, let lane = lanes[key] else { return }
        // A stopped output renders nothing. When iOS stops the engine itself - a call, before the app
        // hears of the interruption - AVAudioEngine calls back every buffer still scheduled at once,
        // and taken as rendered they ran the lane dry: the song "ended" at the last frame scheduled,
        // and the call came back to the queue's end (ios.yml's macOS runner, where those callbacks
        // won the race with the pause; notes/ios.md "A stop is not the song ending"). Those samples
        // were let go, not heard. Every way on from such a stop - play, a new route, a media services
        // reset - lets the lanes go and starts again from the frame heard, so nothing waits on them.
        guard engine.isRunning else { return }
        if !lane.ends.isEmpty { lane.ends.removeFirst() }
        note("lane \(Int(lane.format.sampleRate)) Hz: a buffer rendered, \(lane.pending) to go")
        if lane.pending == 0, lane.holding, feed?.lane != key, let last = lane.timeline.entries.last,
           let song = entryKey[last.id] {
            // its songs are done but the converter still holds their last frames, and the node has played
            // all on it: laid on now they'd play after silence, counted straight on. The lane starts
            // again with them, counted from the frame they begin at (the song's last few ms).
            let kept = min(lane.converterHolds, last.frames)
            let from = last.songOffset + last.frames - kept
            note("lane \(Int(lane.format.sampleRate)) Hz ran dry with its converter holding \(kept) frames: on again with them")
            drainScheduling()
            lane.node.stop()
            lane.clear()
            if heardLane == key { heardLane = nil }
            let next = nextEntry
            nextEntry += 1
            entryKey[next] = song
            lane.timeline.begin(id: next, songOffset: from)
            lane.timeline.extend(id: next, frames: kept)
            lane.timeline.close(id: next)
            current = song
            held = (song, .frame(from, rate: lane.format.sampleRate))
            flush(lane, key: key)
        }
        if lane.pending == 0 {
            if var feeding = feed, feeding.lane == key, let id = feeding.entry, let entry = lane.timeline.entry(id: id) {
                // ran dry mid-song: start the lane again from the frame it reached, once buffered. The
                // converter keeps what it holds, so the song goes on unbroken from it - and those frames
                // play first, so the count begins where they do, not at what went in (the hold review's
                // findings 3 and 6: 12-13 ms ahead).
                // Every restart waits for `startSeconds` again, the race's (its bytes read before the last
                // completion was handled) included: a stream that has just run dry may still be slow, and
                // one gap is better than a scrap of sound and another.
                let kept = min(lane.converterHolds, entry.frames)
                let songFrame = entry.songOffset + entry.frames - kept
                note("lane \(Int(lane.format.sampleRate)) Hz ran dry mid-song: on again from frame \(songFrame) once buffered\(kept > 0 ? " (\(kept) frames of it still in its converter)" : "")")
                drainScheduling()
                lane.node.stop()
                lane.clear()
                heardLane = nil
                let next = nextEntry
                nextEntry += 1
                feeding.entry = next
                entryKey[next] = feeding.key
                lane.timeline.begin(id: next, songOffset: songFrame)
                if kept > 0 { lane.timeline.extend(id: next, frames: kept) }
                tail = key
                feed = feeding
                current = feeding.key
                held = (feeding.key, .frame(songFrame, rate: lane.format.sampleRate))
                publish(.loading)
            } else {
                // this lane's songs are all heard
                let ended = lastSpot(of: lane)
                drainScheduling()
                lane.node.stop()
                lane.clear()
                lane.resetConverter()
                if heardLane == key {
                    heardLane = lanes.first(where: { $0.key != key && $0.value.started })?.key
                }
                if heardLane == nil {
                    if let waiting = lanes.values.first(where: { !$0.started && !$0.timeline.isEmpty }),
                       let first = waiting.timeline.entries.first, let next = entryKey[first.id] {
                        // a lane scheduled but never started (its start time couldn't be read): now
                        current = next
                        held = (next, .frame(first.songOffset, rate: waiting.format.sampleRate))
                    } else if let feeding = feed {
                        current = feeding.key
                        held = (feeding.key, feeding.reached(at: feeding.source.format?.sampleRate ?? lane.format.sampleRate))
                        publish(.loading)
                    } else if let failed = failedNext {
                        // the next song failed while this one played: said now, at it
                        failedNext = nil
                        current = failed.key
                        held = (failed.key, failed.at)
                        fail(failed.failure)
                        return
                    } else {
                        if let ended {
                            current = ended.key
                            held = ended
                        }
                        finish()
                        return
                    }
                }
            }
        }
        followHeard()
        forgetPlayed()
        let phase: EngineState.Phase = wantsPlay ? (heardLane == nil ? .loading : .playing) : .paused
        publish(phase)
        pump()
    }

    /// The last entry on `lane` and the frame at its end - where the queue was when it ran out.
    private func lastSpot(of lane: Lane) -> Spot? {
        guard let last = lane.timeline.entries.last, let key = entryKey[last.id] else { return nil }
        return (key, .frame(last.songOffset + last.frames, rate: lane.format.sampleRate))
    }

    /// `current` follows the song heard. When the render is already in a later song than the ear
    /// (the output's latency), the change is said when the ear gets there.
    private func followHeard() {
        songChange?.cancel()
        songChange = nil
        guard let laneKey = heardLane, let lane = lanes[laneKey], let rendered = sample(of: lane) else { return }
        let rate = lane.format.sampleRate
        let heardAt = HeardEstimate.heard(rendered: rendered, latency: lastLatency, rate: rate)
        guard let heardEntry = lane.timeline.locate(heardAt) else { return }
        if let key = entryKey[heardEntry.entry.id], key != current { current = key }
        guard let renderedEntry = lane.timeline.locate(rendered), renderedEntry.entry.id != heardEntry.entry.id,
              heardEntry.entry.end > heardAt else { return }
        let wait = Double(heardEntry.entry.end - heardAt) / rate
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.songChange = nil
            self.followHeard()
            self.publish(self.state.phase)
        }
        songChange = work
        queue.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// The entries played and heard are forgotten (a long shuffle, an endless Repeat One, on one lane),
    /// a second and the latency behind the render.
    private func forgetPlayed() {
        for lane in lanes.values where lane.timeline.entries.count > 2 {
            guard let rendered = lane.lastRead?.frame else { continue }
            let behind = HeardEstimate.frames(lastLatency + 1, rate: lane.format.sampleRate)
            let before = lane.timeline.entries.map(\.id)
            lane.timeline.forget(before: rendered - behind)
            let kept = Set(lane.timeline.entries.map(\.id))
            for id in before where !kept.contains(id) { entryKey[id] = nil }
        }
    }

    /// The song heard and the frame of it, from the heard lane - the output's latency behind its
    /// render, or estimated when its clock can't be read (`heardFrame`) - or where it was left.
    private func heard(readingNodes: Bool = true) -> Spot? {
        if let laneKey = heardLane, let lane = lanes[laneKey],
           let frame = heardFrame(of: lane, readingNodes: readingNodes),
           let found = lane.timeline.locate(frame), let key = entryKey[found.entry.id] {
            return (key, .frame(found.songFrame, rate: lane.format.sampleRate))
        }
        if let held { return held }
        if let current { return (current, .beginning) }
        return nil
    }

    // MARK: Up Next's edits

    /// What comes after the entry `heardKey` in the order it plays, each with whether any of it is on a
    /// node: the lanes' entries by id (ids ascend in scheduling order, across lanes), then the feed, or
    /// a next song that failed. Nil when there is something scheduled and the entry heard isn't in it.
    private func upcoming(after heardKey: Int) -> [(key: Int, committed: Bool)]? {
        let entries = lanes.values.flatMap { $0.timeline.entries }.sorted { $0.id < $1.id }
        var items: [(key: Int, committed: Bool)] = []
        for entry in entries {
            guard let key = entryKey[entry.id] else { continue }
            if let last = items.last, last.key == key {
                if entry.frames > 0 { items[items.count - 1].committed = true }
                continue
            }
            items.append((key, entry.frames > 0))
        }
        if let feeding = feed {
            if items.last?.key != feeding.key { items.append((feeding.key, false)) }
        } else if let failed = failedNext, items.last?.key != failed.key {
            items.append((failed.key, false))
        }
        if items.isEmpty { return [] }
        guard let at = items.lastIndex(where: { $0.key == heardKey }) else { return nil }
        return Array(items[(at + 1)...])
    }

    private func replaceUpcomingNow(_ new: [EngineTrack]) -> Bool {
        guard let heardKey = heard()?.key else {
            // nothing heard or held: a queue nothing plays from yet
            setTracks(new, fresh: false)
            return true
        }
        // the song heard, where it was, with everything before it the same
        guard let at = indexOf[heardKey], at < new.count, new[at].key == heardKey, new[at].audio == tracks[at].audio,
              zip(tracks[..<at], new[..<at]).allSatisfy({ $0.key == $1.key }) else {
            note("an edit without the song heard where it was: refused")
            return false
        }
        guard let later = upcoming(after: heardKey) else {
            note("an edit while the song heard isn't among what is scheduled: refused")
            return false
        }
        // what is scheduled or decoding after it is kept while the new list has the same audio there
        var kept = 0
        while kept < later.count {
            let place = at + 1 + kept
            guard place < new.count, let old = indexOf[later[kept].key], new[place].audio == tracks[old].audio else { break }
            kept += 1
        }
        if kept < later.count, later[kept].committed {
            note("an edit held: entry \(later[kept].key) is on a node already")
            return false
        }
        if current != heardKey {
            current = heardKey
        }
        // the kept take the new list's keys (Shuffle turned off makes new entries of the same songs)
        var renamed: [Int: Int] = [:]
        for (offset, item) in later.prefix(kept).enumerated() where item.key != new[at + 1 + offset].key {
            renamed[item.key] = new[at + 1 + offset].key
        }
        rekey(renamed)
        setTracks(new, fresh: false)
        let lastKept = kept > 0 ? new[at + kept].key : heardKey
        if kept < later.count {
            // the next song, on no node yet, let go of: the new list's in its place, straight after
            note("an edit: entry \(later[kept].key) let go of; on after entry \(lastKept)")
            retry?.cancel()
            retry = nil
            feed?.source.close()
            feed = nil
            failedNext = nil
            openAfter(lastKept, lane: tail)
            pump()
        } else if feed == nil, failedNext == nil, wantsPlay, engine.isRunning,
                  lanes.values.contains(where: { !$0.timeline.isEmpty }) {
            // the queue's last song decoded with nothing after it: what was added goes on after it
            if let index = indexOf[lastKept], tracks.indices.contains(index + 1) {
                note("an edit: added after the queue's end")
                openAfter(lastKept, lane: nil)
                pump()
            }
        }
        publish(state.phase)
        return true
    }

    /// Entries' keys changed by an edit (`renamed[old] = new`), wherever the engine holds them.
    private func rekey(_ renamed: [Int: Int]) {
        guard !renamed.isEmpty else { return }
        for (id, key) in entryKey {
            if let to = renamed[key] { entryKey[id] = to }
        }
        if let key = feed?.key, let to = renamed[key] { feed?.key = to }
        if let key = failedNext?.key, let to = renamed[key] { failedNext?.key = to }
        if let key = current, let to = renamed[key] { current = to }
        if let key = rateOf, let to = renamed[key] { rateOf = to }
        if let spot = held, let to = renamed[spot.key] { held = (to, spot.at) }
        var moved: [Int: Double] = [:]
        for (key, length) in lengths { moved[renamed[key] ?? key] = length }
        lengths = moved
    }

    // MARK: pause, play, and iOS's own stops

    private func pauseNow() {
        guard wantsPlay else { return }
        held = heard()
        wantsPlay = false
        if settings.idleStopSeconds > 0, engine.isRunning {
            for lane in lanes.values where lane.started { lane.node.pause() }
            publish(.paused)
            armIdle()
            return
        }
        // the output off at once (iOS counts a running one as playing); play goes on from `held`,
        // the last sample heard
        reset()
        sleep()
        publish(.paused)
    }

    private func resumeNow(asked: Double) {
        if wantsPlay { return }
        playAsked = asked
        if state.phase == .ended, let current, let index = indexOf[current] {
            wantsPlay = true
            begin(at: index, from: .beginning)
            return
        }
        let started = lanes.values.filter { $0.started }
        let loaded = feed != nil || lanes.values.contains { !$0.timeline.isEmpty }
        if asleep || !engine.isRunning || started.count > 1 || !loaded {
            // the engine slept or iOS stopped it, a pause caught a change of lanes, or nothing is
            // loaded (after a failure, a stop, a queue put back): start again from the frame left -
            // or, with nothing to go on from, stay idle
            let at = heard()
            reset()
            resumeFrom(at, playing: true)
            return
        }
        wantsPlay = true
        guard ensureRunning() else { return }
        if let lane = started.first {
            // a node a pause left paused: on at once, always
            _ = playFromSilence(lane)
            publish(.playing)
        } else {
            publish(.loading)
        }
        startLanesIfReady()
        pump()
    }

    private func resumeFrom(_ at: Spot?, playing: Bool) {
        guard let at, let index = indexOf[at.key] else {
            wantsPlay = false
            publish(.idle)
            armIdle()
            return
        }
        wantsPlay = playing
        begin(at: index, from: at.at)
    }

    private func configurationChanged() {
        // the engine was stopped by a new route or hardware format (AirPods connecting, AirPlay):
        // make the lanes again and go on from the frame heard - estimated from the last reading,
        // less the old route's latency (its samples went with it)
        note("a configuration change: the output \(engine.isRunning ? "running" : "stopped"), \(wantsPlay ? "playing" : "not playing")")
        let at = heard()
        let playing = wantsPlay
        reset()
        // the output's rate may be another now: the lanes are made again, converting to it
        for lane in lanes.values { engine.detach(lane.node) }
        lanes.removeAll()
        matchOutput()
        sleep()
        held = at
        guard playing, at != nil else {
            // ended stays ended and a failure keeps its words; only what was playing is paused
            publish(state.phase == .playing || state.phase == .loading ? .paused : state.phase)
            return
        }
        // The same change can be the old output going away (AirPods out), which the app hears as a
        // route change on the main queue and answers with pause(): wait a moment, so that pause
        // comes first and the song never goes on out of the speaker. A pause (or any new play,
        // skip or seek) in the meantime wins.
        publish(.loading)
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation, self.wantsPlay else { return }
            self.restart = nil
            self.resumeFrom(self.held, playing: true)
        }
        restart = work
        if settings.changeSettleSeconds > 0 {
            queue.asyncAfter(deadline: .now() + settings.changeSettleSeconds, execute: work)
        } else {
            work.perform()
        }
    }

    /// Stops the output `after` seconds unless play comes first (`idleStopSeconds` by default).
    private func armIdle(after seconds: Double? = nil) {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wantsPlay else { return }
            self.held = self.heard() ?? self.held
            self.reset()
            self.sleep()
            self.publish(self.state.phase)
        }
        idle = work
        queue.asyncAfter(deadline: .now() + (seconds ?? settings.idleStopSeconds), execute: work)
    }

    private func finish() {
        wantsPlay = false
        drainScheduling()
        for lane in lanes.values {
            lane.node.stop()
            lane.clear()
        }
        heardLane = nil
        ended = Self.hostSeconds()
        publish(.ended)
        // the samples rendered are still on their way to the ear: the output stops once they are heard
        armIdle(after: lastLatency + settings.endLingerSeconds)
    }

    private func fail(_ error: Error) {
        let failure = AudioFailure.from(error)
        // kept, so play after a failure (a stream cut off) goes on from where it stopped
        held = heard() ?? held
        wantsPlay = false
        reset()
        lastFailure = failure
        failureCount += 1
        note("failed: \(failure.description)")
        publish(.failed(failure.description))
        armIdle()
    }

    private func publish(_ phase: EngineState.Phase) {
        var next = state
        next.phase = phase
        next.key = current
        next.index = current.flatMap { indexOf[$0] }
        if case .failed = phase {
            next.failure = lastFailure
        } else {
            next.failure = nil
        }
        next.failures = failureCount
        next.latency = lastLatency
        if let key = heardLane ?? feed?.lane, let lane = lanes[key] {
            next.fileRate = lane.format.sampleRate
            next.fileChannels = Int(lane.format.channelCount)
            rateOf = current
        } else if let format = feed?.source.format {
            next.fileRate = format.sampleRate
            next.fileChannels = Int(format.channelCount)
            rateOf = current
        } else if current == nil || rateOf != current {
            // nothing open, and the rate kept was another entry's (a skip or a queue put back while
            // paused, a stop): not known until play opens it. A pause keeps its song's.
            next.fileRate = nil
            next.fileChannels = nil
        }
        let output = engine.outputNode.outputFormat(forBus: 0).sampleRate
        next.outputRate = settings.offline?.sampleRate ?? (output > 0 ? output : nil)
        guard next != state else { return }
        state = next
        if let onChange {
            DispatchQueue.main.async { onChange(next) }
        }
    }
}
#endif
