#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation

/// Debug's "The record's engine beside the song" (notes/ios-specs/turntable.md 7.2, checks 0a-0c): the deck engine
/// playing a fixed run of the voice through its real render, beside whatever the song's engine plays - so James can hear
/// whether two engines play together on his phone, whether the deck's start or stop is ever heard in the song, and
/// whether `L` holds steady (the Clock row).
///
/// The run is made here, not recorded: a 6 s "record" (a chord, pulsing, with a tick every quarter second) at the
/// output's rate, and a 4 s loop of it: a take from 1 s at rate 1; at 1.5 s a hand grabbing it at speed and scratching
/// it back and forth twice over a second (`x(t) = 2.5 + sin(4 pi t) / 4 pi`, so the hand's speed at the grab and the
/// let-go is the record's, 1); let go at 2.5 s, a drive at rate 1; and from the loop's top again. Hand samples at
/// 120 Hz from a main-queue timer, stamped with the host's now, as the deck's rules will stamp them.
///
/// Main thread only. Without the deck's EQ (slice 3 gives the record the output's curve).
public final class DeckTrial {
    /// The loop, and where its parts begin.
    public static let loopS = 4.0
    static let grabS = 1.5
    static let letGoS = 2.5
    static let takeFrom = 1.0
    static let handHz = 120.0

    public let engine: DeckEngine
    private var timer: DispatchSourceTimer?
    private var window: DeckPCM?
    private var windowRate = 0.0
    /// the loop's top, in host seconds, and which parts of this loop were posted
    private var loopStart = 0.0
    private var letGoPosted = false
    private var stopping: DispatchWorkItem?

    public init(ioBuffer: @escaping () -> TimeInterval, latency: @escaping () -> TimeInterval) {
        var settings = DeckEngine.Settings()
        settings.eq = false
        engine = DeckEngine(settings: settings)
        engine.ioBuffer = ioBuffer
        engine.latency = latency
    }

    deinit {
        timer?.cancel()
        stopping?.cancel()
    }

    /// Playing the run (a stop's fade under way is called off).
    public var isRunning: Bool { timer != nil }

    /// The deck engine started, the window posted (made again at a new output rate), and the run from its top.
    public func start() throws {
        stopping?.cancel()
        stopping = nil
        try engine.start()
        let rate = engine.rate
        if window == nil || windowRate != rate {
            let made = Self.record(rate: rate)
            window = made
            windowRate = rate
            engine.post(.window(made.voiceWindow(start: 0, rate: rate)), keeping: made)
        }
        guard timer == nil else { return }
        loopStart = PlaybackEngine.hostSeconds()
        letGoPosted = false
        engine.post(.take(at: Self.takeFrom, rate: 1, time: loopStart, until: .infinity), keeping: nil)
        let made = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        made.schedule(deadline: .now(), repeating: 1 / Self.handHz, leeway: .nanoseconds(0))
        made.setEventHandler { [weak self] in self?.tick() }
        made.resume()
        timer = made
    }

    /// The run faded (30 ms) and the deck engine stopped after it - the voice keeps its window for the next start.
    public func stop() {
        timer?.cancel()
        timer = nil
        engine.post(.fade(seconds: 0.03), keeping: nil)
        let later = DispatchWorkItem { [weak self] in
            guard let self, self.timer == nil else { return }
            self.engine.post(.stop, keeping: nil)
            self.engine.stop()
            self.stopping = nil
        }
        stopping = later
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: later)
    }

    public func status() -> DeckEngineStatus { engine.status() }

    /// The hand's place `t` seconds into the loop, between the grab and the let-go.
    static func hand(_ t: Double) -> Double {
        let from = takeFrom + grabS
        return from + sin(4 * Double.pi * (t - grabS)) / (4 * Double.pi)
    }

    private func tick() {
        let now = PlaybackEngine.hostSeconds()
        var t = now - loopStart
        if t >= Self.loopS {
            // the loop's top: taken again from 1 s
            loopStart += Self.loopS * (t / Self.loopS).rounded(.down)
            t = now - loopStart
            letGoPosted = false
            engine.post(.take(at: Self.takeFrom, rate: 1, time: loopStart, until: .infinity), keeping: nil)
        }
        if t >= Self.grabS && t < Self.letGoS {
            engine.post(.hand(at: Self.hand(t), time: now), keeping: nil)
        } else if t >= Self.letGoS && !letGoPosted {
            letGoPosted = true
            engine.post(.drive(at: Self.hand(Self.letGoS), rate: 1, accel: nil, time: loopStart + Self.letGoS, until: .infinity),
                        keeping: nil)
        }
    }

    /// The record: 6 s, both channels - an A minor chord pulsing twice a second, and a tick every quarter second, at
    /// about -12 dBFS.
    static func record(rate: Double) -> DeckPCM {
        let frames = Int(6 * rate)
        let pcm = DeckPCM(channelCount: 2, capacity: frames)
        let chord = [220.0, 261.63, 329.63]
        var noise: UInt32 = 0x1234_5678
        let left = pcm.channel(0), right = pcm.channel(1)
        for i in 0..<frames {
            let t = Double(i) / rate
            let pulse = 0.55 + 0.45 * cos(2 * Double.pi * 2 * t)
            var v = chord.reduce(0.0) { $0 + sin(2 * Double.pi * $1 * t) } * 0.06 * pulse
            let sinceTick = t.truncatingRemainder(dividingBy: 0.25)
            if sinceTick < 0.02 {
                noise ^= noise << 13
                noise ^= noise >> 17
                noise ^= noise << 5
                v += (Double(noise) / Double(UInt32.max) * 2 - 1) * 0.15 * (1 - sinceTick / 0.02)
            }
            left[i] = Float(v)
            right[i] = Float(v * 0.9)
        }
        pcm.keep(frames)
        return pcm
    }
}
#endif
