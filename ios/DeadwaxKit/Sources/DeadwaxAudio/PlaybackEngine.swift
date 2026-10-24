#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// One song for the engine: the song, and how to open its audio at a point in it (its beginning, a
/// seek's seconds, or the exact frame it was left at) - the source turns that into a frame at the
/// file's own rate (`StartPoint.frame(at:)`).
public struct EngineTrack {
    public let song: Song
    public let open: (StartPoint) throws -> PCMSource

    public init(song: Song, open: @escaping (StartPoint) throws -> PCMSource) {
        self.song = song
        self.open = open
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
        case failed(String)
    }

    public var phase: Phase = .idle
    /// The song heard (an index into the tracks played).
    public var index: Int?
    /// The heard song's own rate and channels - what it was decoded at.
    public var fileRate: Double?
    public var fileChannels: Int?
    /// The rate the engine's output runs at (the route's). The engine's main mixer converts each
    /// song to it when the rates differ - see the class comment.
    public var outputRate: Double?
    /// The start time asked of the last song started from silence: output latency plus one IO buffer.
    public var lastStartLead: Double?

    public init() {}
}

/// The audio engine (notes/ios.md, the plan's section 3): AVAudioEngine with one AVAudioPlayerNode
/// per format "lane", fed by the app's own decoding at each file's own rate.
///
/// - Gapless: the next song's first buffer is scheduled straight after the last song's last buffer
///   on the same node, so within a format the samples run on unbroken - nothing trimmed, nothing
///   crossfaded. A song in another format goes on its own lane, started at the moment the first
///   lane's last sample plays.
/// - Nothing is processed but what an output needs: no gain, the decoder's int-to-float (exact),
///   and the main mixer at unity. Each lane is connected to the main mixer in its file's own format
///   and the mixer's output runs at the route's rate (48 kHz on the speaker and AirPods), so when
///   they differ - a 44.1 kHz CD, a 96 or 192 kHz file - THE MIXER, inside the app's own engine,
///   converts the rate. Any app must convert for a 48 kHz output; how well this one does is
///   measured by EngineRenderTests' `theMixersRateConversionMeasured` (notes/ios.md), and if it
///   falls short a lane can convert with its own AVAudioConverter at its best quality instead.
/// - The output is started once and kept running across songs and pauses, so a song is scheduled
///   onto an output that is already live - never a new output on a tap. A song started from silence
///   is scheduled `startLead` ahead (the output's latency and one IO buffer), so the output is
///   live when its first sample plays. A pause longer than `idleStopSeconds` stops the engine.
/// - When iOS stops the engine itself (a call, a new route, media services reset), the node's clock
///   is gone before the engine hears of it, so where the song was is the last position read while it
///   played (`Lane.lastSample`, read at least every buffer), and play goes on from there.
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
        /// A pause this long stops the engine, to save battery.
        public var idleStopSeconds: Double = 60
        /// After a configuration change (a new route), how long the engine waits before playing on,
        /// so a pause for the same change - the old output gone: AirPods out, headphones unplugged,
        /// which the app hears as a route change on another queue - comes first and wins.
        public var changeSettleSeconds: Double = 0.3
        /// Offline manual rendering in this format (the tests' render), instead of the device.
        public var offline: AVAudioFormat?

        public init() {}
    }

    /// The lead before a song started from silence plays: the app sets it from AVAudioSession
    /// (outputLatency + ioBufferDuration). Zero plays at once.
    public var startLead: () -> TimeInterval = { 0 }
    public var onChange: ((EngineState) -> Void)?

    private let settings: Settings
    private let queue = DispatchQueue(label: "deadwax.engine", qos: .userInitiated)
    private var engine: AVAudioEngine
    private var observer: NSObjectProtocol?

    private final class Lane {
        let node: AVAudioPlayerNode
        let format: AVAudioFormat
        var timeline = LaneTimeline()
        var pending = 0
        var started = false
        /// The node's sample count when it was last read playing - where the song was when iOS
        /// stops the engine (its clock reads nil then).
        var lastSample: Int64?
        /// Offline only: the render's sample count when the node started.
        var renderStart: AVAudioFramePosition?

        init(node: AVAudioPlayerNode, format: AVAudioFormat) {
            self.node = node
            self.format = format
        }

        /// Nothing scheduled, not started (the node itself is stopped by the caller).
        func clear() {
            timeline.reset()
            pending = 0
            started = false
            lastSample = nil
        }
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
        let index: Int
        let source: PCMSource
        /// Where the source was opened at; its frame once the decoded format is known.
        let start: StartPoint
        var startFrame: Int64?
        /// Frames decoded and scheduled since.
        var decoded: Int64 = 0
        var lane: LaneKey?
        var entry: Int?
        /// A buffer decoded but held back: its lane still holds songs that play before the one
        /// scheduled last (see `schedule`). Scheduled first when the feed goes on.
        var parked: AVAudioPCMBuffer?

        init(index: Int, source: PCMSource, start: StartPoint) {
            self.index = index
            self.source = source
            self.start = start
        }

        /// Where the next frame decoded sits in the song.
        func reached(at rate: Double) -> StartPoint {
            guard let startFrame else { return start }
            return .frame(startFrame + decoded, rate: rate)
        }
    }

    /// A song and a point in it: where the engine is, or was left.
    typealias Spot = (index: Int, at: StartPoint)

    private var lanes: [LaneKey: Lane] = [:]
    private var heardLane: LaneKey?
    /// The lane the song scheduled last went on: the one that plays last.
    private var tail: LaneKey?
    private var tracks: [EngineTrack] = []
    private var current: Int?
    private var feed: Feed?
    private var entryTrack: [Int: Int] = [:]
    private var nextEntry = 1
    private var generation = 0
    private var wantsPlay = false
    private var asleep = true
    private var held: Spot?
    private var idle: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var restart: DispatchWorkItem?
    private var state = EngineState()

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
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.configurationChanged() }
        }
    }

    // MARK: the calls

    /// Plays `tracks` from `index`, `seconds` in.
    public func play(_ tracks: [EngineTrack], from index: Int, at seconds: Double = 0) {
        queue.async {
            self.tracks = tracks
            self.wantsPlay = true
            self.begin(at: index, from: seconds > 0 ? .seconds(seconds) : .beginning)
        }
    }

    /// Replaces what comes after the song heard, keeping it playing (the tracks are the same up to
    /// and including it).
    public func replaceTracks(_ tracks: [EngineTrack]) {
        queue.async { self.tracks = tracks }
    }

    public func pause() {
        queue.async { self.pauseNow() }
    }

    public func resume() {
        queue.async { self.resumeNow() }
    }

    /// Another song of the tracks, from its start.
    public func skip(to index: Int) {
        queue.async { self.begin(at: index, from: .beginning) }
    }

    /// `seconds` into the song heard - turned into a frame by the song's source, at the file's own
    /// rate, so a seek before the song has been heard (paused, or still loading) lands where it says.
    public func seek(to seconds: Double) {
        queue.async {
            guard let at = self.heard() else { return }
            self.begin(at: at.index, from: .seconds(seconds))
        }
    }

    public func stop() {
        queue.async {
            self.wantsPlay = false
            self.reset()
            self.current = nil
            self.held = nil
            self.publish(.idle)
            self.armIdle()
        }
    }

    /// The song heard and how far in, in seconds.
    public func position() -> (index: Int, seconds: Double)? {
        queue.sync {
            guard let at = heard() else { return nil }
            return (at.index, at.at.seconds)
        }
    }

    /// After AVAudioSession's media services were reset: a new engine, and on from where it was.
    public func rebuild() {
        queue.async {
            let at = self.heard()
            let playing = self.wantsPlay
            self.reset()
            for lane in self.lanes.values { self.engine.detach(lane.node) }
            self.lanes.removeAll()
            self.heardLane = nil
            self.engine.stop()
            self.engine = AVAudioEngine()
            do {
                try self.configure(self.engine)
            } catch {
                self.fail("iOS couldn't make a new audio engine: \(error.localizedDescription)")
                return
            }
            self.asleep = true
            self.resumeFrom(at, playing: playing)
        }
    }

    // MARK: offline rendering (tests)

    /// Renders `frames` frames offline. Only with `Settings.offline`.
    public func renderOffline(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        try queue.sync {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames) else {
                throw AudioFailure("No memory for \(frames) frames.")
            }
            var done: AVAudioFrameCount = 0
            let chunk = engine.manualRenderingMaximumFrameCount
            guard let piece = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk),
                  let into = buffer.floatChannelData, let from = piece.floatChannelData else {
                throw AudioFailure("No memory for the render.")
            }
            while done < frames {
                let wanted = min(chunk, frames - done)
                let status = try engine.renderOffline(wanted, to: piece)
                guard status == .success else { throw AudioFailure("Offline render: \(status.rawValue)") }
                for channel in 0..<Int(buffer.format.channelCount) {
                    (into[channel] + Int(done)).update(from: from[channel], count: Int(piece.frameLength))
                }
                done += piece.frameLength
            }
            buffer.frameLength = done
            return buffer
        }
    }

    /// Waits until everything queued on the engine has run (tests).
    public func settle() { queue.sync {} }

    /// Tests: the phase now, without waiting for `onChange` on the main queue.
    var phase: EngineState.Phase { queue.sync { state.phase } }

    /// Tests: iOS stopping the engine (a call, a new route) - and, with `change`, the configuration
    /// change it posts, handled as the notification's would be.
    func systemStopped(change: Bool) {
        queue.sync {
            engine.stop()
            if change { configurationChanged() }
        }
    }

    // MARK: on the queue

    private func begin(at index: Int, from start: StartPoint) {
        reset()
        guard tracks.indices.contains(index) else {
            finish()
            return
        }
        current = index
        held = (index, start)
        do {
            feed = Feed(index: index, source: try tracks[index].open(start), start: start)
        } catch {
            fail(String(describing: error))
            return
        }
        guard ensureRunning() else { return }
        // loaded while paused (a skip or a seek): it waits, paused, for play
        publish(wantsPlay ? .loading : .paused)
        if !wantsPlay { armIdle() }
        pump()
    }

    @discardableResult
    private func ensureRunning() -> Bool {
        idle?.cancel()
        idle = nil
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
            asleep = false
            return true
        } catch {
            fail("iOS wouldn't start the audio: \(error.localizedDescription)")
            return false
        }
    }

    private func reset() {
        generation += 1
        retry?.cancel()
        retry = nil
        restart?.cancel()
        restart = nil
        for lane in lanes.values {
            lane.node.stop()
            lane.clear()
        }
        heardLane = nil
        tail = nil
        feed?.source.close()
        feed = nil
        entryTrack.removeAll()
    }

    private func frames(_ seconds: Double, _ rate: Double) -> Int64 { Int64(seconds * rate) }

    private func laneFor(_ format: AVAudioFormat) -> Lane {
        let key = LaneKey(format)
        if let lane = lanes[key] { return lane }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        let lane = Lane(node: node, format: format)
        lanes[key] = lane
        return lane
    }

    /// The node's own sample count now, once it is playing - kept as the lane's `lastSample`. Nil
    /// when the engine isn't running (iOS stopped it, or it is asleep) or the node isn't playing.
    private func sample(of lane: Lane) -> Int64? {
        guard lane.started, let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return nil }
        lane.lastSample = playerTime.sampleTime
        return playerTime.sampleTime
    }

    private func ahead(_ lane: Lane) -> Int64 {
        lane.timeline.end - max(sample(of: lane) ?? 0, 0)
    }

    /// Decodes and schedules until the feed's lane holds `aheadSeconds` past what is heard.
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
                    fail(String(describing: error))
                    return
                }
            }
            switch result {
            case .waiting:
                scheduleRetry()
                startLanesIfReady()
                return
            case .end:
                endFeed()
            case .frames(let buffer):
                guard schedule(buffer, feed: &feeding) else {
                    // held until the lane's earlier songs have played (its last buffer's completion
                    // pumps again)
                    feeding.parked = buffer
                    feed = feeding
                    startLanesIfReady()
                    return
                }
                feed = feeding
            }
        }
        startLanesIfReady()
    }

    /// Schedules a decoded buffer on its format's lane - or, returning false, doesn't: a song that
    /// begins on a lane still holding songs that play BEFORE the one scheduled last (44.1 kHz, then a
    /// short 96 kHz song on its own lane, then 44.1 kHz again while the first is still playing) would
    /// be laid straight after the first song, ahead of the one between. It waits for that lane to run
    /// out instead (`played` clears it), and then goes on it to start when the last lane ends.
    private func schedule(_ decoded: AVAudioPCMBuffer, feed feeding: inout Feed) -> Bool {
        let key = LaneKey(decoded.format)
        let beginning = feeding.lane != key || feeding.entry == nil
        if beginning, let busy = lanes[key], !busy.timeline.isEmpty,
           let last = tail, last != key, let lastLane = lanes[last], !lastLane.timeline.isEmpty {
            return false
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
            entryTrack[id] = feeding.index
            lane.timeline.begin(id: id, songOffset: (feeding.startFrame ?? 0) + feeding.decoded)
        }
        guard let id = feeding.entry else { return true }
        lane.timeline.extend(id: id, frames: Int64(buffer.frameLength))
        feeding.decoded += Int64(buffer.frameLength)
        lane.pending += 1
        let generation = self.generation
        lane.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.played(generation: generation, lane: key) }
        }
        return true
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
    /// be scheduled straight after on the same lane when its format is the same.
    private func endFeed() {
        guard let ended = feed else { return }
        if let key = ended.lane, let id = ended.entry { lanes[key]?.timeline.close(id: id) }
        ended.source.close()
        feed = nil
        let next = ended.index + 1
        guard tracks.indices.contains(next) else { return }
        do {
            feed = Feed(index: next, source: try tracks[next].open(.beginning), start: .beginning)
        } catch {
            // the song heard plays to its end; the queue stops there
            feed = nil
        }
    }

    /// Starts each lane that has something scheduled and isn't playing: from silence with the
    /// start lead, or - a song in another format next - at the moment the heard lane runs out.
    private func startLanesIfReady() {
        // A node played on a stopped engine raises an exception that ends the app. iOS stops the
        // engine on its own (a call, a new route) a moment before its notification is handled, and
        // a retry or a buffer's completion can land here in that gap.
        guard wantsPlay, engine.isRunning else { return }
        // the song heard first: its lane starts from silence (or is already playing)
        if heardLane == nil, let key = laneHolding(current), let lane = lanes[key], !lane.started, ready(lane, key) {
            playFromSilence(lane)
            lane.renderStart = settings.offline != nil ? engine.manualRenderingSampleTime : nil
            lane.started = true
            heardLane = key
            publish(.playing)
        }
        // then a song in another format after it: its lane starts when the heard lane runs out
        guard let heardKey = heardLane, let heard = lanes[heardKey], heard.started, heard.pending > 0 else { return }
        for (key, lane) in lanes where key != heardKey && !lane.started && !lane.timeline.isEmpty && ready(lane, key) {
            guard let when = time(whenEnds: heard) else { continue }
            lane.node.play(at: when)
            lane.renderStart = settings.offline != nil && when.isSampleTimeValid ? when.sampleTime : nil
            lane.started = true
        }
    }

    /// Starts a node from silence, `startLead` ahead so its first sample lands on a live output.
    private func playFromSilence(_ lane: Lane) {
        let lead = settings.offline == nil ? max(startLead(), 0) : 0
        if lead > 0 {
            lane.node.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead)))
        } else {
            lane.node.play()
        }
        state.lastStartLead = lead
    }

    /// Enough is scheduled on the lane to start it: `startSeconds`, or all there is.
    private func ready(_ lane: Lane, _ key: LaneKey) -> Bool {
        feed?.lane != key || lane.timeline.end >= frames(settings.startSeconds, lane.format.sampleRate)
    }

    /// The lane that has the song `index` scheduled on it.
    private func laneHolding(_ index: Int?) -> LaneKey? {
        guard let index else { return nil }
        return lanes.first(where: { _, lane in
            lane.timeline.entries.contains { entry in entryTrack[entry.id] == index }
        })?.key
    }

    /// When the last sample scheduled on `lane` will play, as a time another node can start at.
    private func time(whenEnds lane: Lane) -> AVAudioTime? {
        if let offline = settings.offline, let start = lane.renderStart {
            // rendering offline there is no clock: the render's own sample count, from where it started
            let frames = Double(lane.timeline.end) * offline.sampleRate / lane.format.sampleRate
            return AVAudioTime(sampleTime: start + AVAudioFramePosition(frames.rounded()), atRate: offline.sampleRate)
        }
        guard let nodeTime = lane.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = lane.node.playerTime(forNodeTime: nodeTime) else { return nil }
        let remaining = Double(max(lane.timeline.end - playerTime.sampleTime, 0)) / playerTime.sampleRate
        if nodeTime.isHostTimeValid {
            return AVAudioTime(hostTime: nodeTime.hostTime + AVAudioTime.hostTime(forSeconds: remaining))
        }
        return AVAudioTime(sampleTime: nodeTime.sampleTime + AVAudioFramePosition(remaining * nodeTime.sampleRate),
                           atRate: nodeTime.sampleRate)
    }

    private func scheduleRetry() {
        guard retry == nil else { return }
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            self.retry = nil
            self.pump()
        }
        retry = work
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// A buffer has been played: keep the lane fed, follow the song heard, and notice a lane that
    /// ran dry - at its end, or mid-song (a stream that didn't keep up).
    private func played(generation: Int, lane key: LaneKey) {
        guard generation == self.generation, let lane = lanes[key] else { return }
        lane.pending = max(lane.pending - 1, 0)
        if lane.pending == 0 {
            if var feeding = feed, feeding.lane == key, let id = feeding.entry, let entry = lane.timeline.entry(id: id) {
                // ran dry mid-song: start the lane again from the frame it reached, once buffered
                let songFrame = entry.songOffset + entry.frames
                lane.node.stop()
                lane.clear()
                heardLane = nil
                let next = nextEntry
                nextEntry += 1
                feeding.entry = next
                entryTrack[next] = feeding.index
                lane.timeline.begin(id: next, songOffset: songFrame)
                tail = key
                feed = feeding
                current = feeding.index
                held = (feeding.index, .frame(songFrame, rate: lane.format.sampleRate))
                publish(.loading)
            } else {
                // this lane's songs are all heard
                lane.node.stop()
                lane.clear()
                if heardLane == key {
                    heardLane = lanes.first(where: { $0.key != key && $0.value.started })?.key
                }
                if heardLane == nil {
                    if let waiting = lanes.values.first(where: { !$0.started && !$0.timeline.isEmpty }),
                       let first = waiting.timeline.entries.first, let index = entryTrack[first.id] {
                        // a lane scheduled but never started (its start time couldn't be read): now
                        current = index
                        held = (index, .frame(first.songOffset, rate: waiting.format.sampleRate))
                    } else if let feeding = feed {
                        current = feeding.index
                        held = (feeding.index, feeding.reached(at: feeding.source.format?.sampleRate ?? lane.format.sampleRate))
                        publish(.loading)
                    } else {
                        finish()
                        return
                    }
                }
            }
        }
        if let at = heard(), at.index != current {
            current = at.index
        }
        let phase: EngineState.Phase = wantsPlay ? (heardLane == nil ? .loading : .playing) : .paused
        publish(phase)
        pump()
    }

    /// The song heard and the frame of it, from the heard lane's node - or, when its clock can't be
    /// read (iOS stopped the engine before telling it), the last sample read while it played - or
    /// where it was left.
    private func heard() -> Spot? {
        if let key = heardLane, let lane = lanes[key], let now = sample(of: lane) ?? lane.lastSample,
           let found = lane.timeline.locate(now), let index = entryTrack[found.entry.id] {
            return (index, .frame(found.songFrame, rate: lane.format.sampleRate))
        }
        if let held { return held }
        if let current { return (current, .beginning) }
        return nil
    }

    private func pauseNow() {
        guard wantsPlay else { return }
        held = heard()
        wantsPlay = false
        if engine.isRunning {
            for lane in lanes.values where lane.started { lane.node.pause() }
        } else {
            // iOS stopped the engine (a call): nothing to pause; play starts again from `held`
            reset()
            asleep = true
        }
        publish(.paused)
        armIdle()
    }

    private func resumeNow() {
        if wantsPlay { return }
        if state.phase == .ended, let current {
            wantsPlay = true
            begin(at: current, from: .beginning)
            return
        }
        let started = lanes.values.filter { $0.started }
        let loaded = feed != nil || lanes.values.contains { !$0.timeline.isEmpty }
        if asleep || !engine.isRunning || started.count > 1 || !loaded {
            // the engine slept or iOS stopped it, a pause caught a change of lanes, or nothing is
            // loaded (after a failure, or a stop): start again from the frame left - or, with
            // nothing to go on from, stay idle
            let at = heard()
            reset()
            resumeFrom(at, playing: true)
            return
        }
        wantsPlay = true
        guard ensureRunning() else { return }
        if let lane = started.first {
            playFromSilence(lane)
            publish(.playing)
        } else {
            publish(.loading)
        }
        startLanesIfReady()
        pump()
    }

    private func resumeFrom(_ at: Spot?, playing: Bool) {
        guard let at else {
            wantsPlay = false
            publish(.idle)
            armIdle()
            return
        }
        wantsPlay = playing
        begin(at: at.index, from: at.at)
        if !playing {
            held = at
            publish(.paused)
        }
    }

    private func configurationChanged() {
        // the engine was stopped by a new route or hardware format (AirPods connecting, AirPlay):
        // connect the lanes again and go on from the frame reached
        let at = heard()
        let playing = wantsPlay
        reset()
        for lane in lanes.values {
            engine.disconnectNodeOutput(lane.node)
            engine.connect(lane.node, to: engine.mainMixerNode, format: lane.format)
        }
        asleep = true
        held = at
        guard playing, at != nil else {
            publish(state.phase == .idle ? .idle : .paused)
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

    private func armIdle() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wantsPlay else { return }
            self.held = self.heard()
            self.reset()
            self.engine.stop()
            self.asleep = true
            self.publish(self.state.phase)
        }
        idle = work
        queue.asyncAfter(deadline: .now() + settings.idleStopSeconds, execute: work)
    }

    private func finish() {
        wantsPlay = false
        for lane in lanes.values {
            lane.node.stop()
            lane.clear()
        }
        heardLane = nil
        publish(.ended)
        armIdle()
    }

    private func fail(_ words: String) {
        // kept, so play after a failure (a stream cut off) goes on from where it stopped
        held = heard() ?? held
        wantsPlay = false
        reset()
        publish(.failed(words))
        armIdle()
    }

    private func publish(_ phase: EngineState.Phase) {
        var next = state
        next.phase = phase
        next.index = current
        if let key = heardLane ?? feed?.lane, let lane = lanes[key] {
            next.fileRate = lane.format.sampleRate
            next.fileChannels = Int(lane.format.channelCount)
        } else if let format = feed?.source.format {
            next.fileRate = format.sampleRate
            next.fileChannels = Int(format.channelCount)
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
