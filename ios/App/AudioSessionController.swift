import AVFAudio
import Foundation

/// The app's AVAudioSession: playback, long-form audio (so iOS treats it as music - the lock
/// screen, AirPlay 2 and the AirPods' controls), active from the first play. And what iOS says
/// about interruptions and routes, handed to the model.
///
/// Background audio is UIBackgroundModes `audio` in Info.plist - a key, not an entitlement, so a
/// free Apple account has it.
@MainActor
final class AudioSessionController {
    /// A call, Siri or an alarm began (true) or ended (false, with whether iOS says to resume).
    var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?
    /// The output in use went away: AirPods out of the ears or taken off, headphones unplugged.
    var onOldDeviceGone: (() -> Void)?
    /// iOS reset its media services: everything audio is made again (the category is set again
    /// before this is called; the model activates the session when it was playing).
    var onReset: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                let resume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                self?.onInterruption?(type == .began, resume)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let raw, AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                self?.onOldDeviceGone?()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                try? self?.configure()
                self?.onReset?()
            }
        })
    }

    func configure() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
    }

    /// Before the first play (and again after an interruption).
    func activate() throws {
        try Self.activateShared()
    }

    /// The same, from where the controller isn't to hand: the turntable's deck engine before it starts (turntable.md
    /// 4.6 - a press on a paused record takes the sound as pressing Play would), Debug's record engine. The category is
    /// the one `configure()` sets, so it is never changed - only made active. Idempotent.
    nonisolated static func activateShared() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try session.setActive(true)
    }

    /// The route has an AirPlay output: the record makes no sound there (turntable.md 2.8, question 5).
    nonisolated static func onAirPlay() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { (port: AVAudioSessionPortDescription) -> Bool in
            port.portType == .airPlay
        }
    }

    /// How far ahead a song started from silence is scheduled: the output's latency and one IO
    /// buffer, so its first sample lands on an output that is already live. Read on the engine's
    /// queue; AVAudioSession's properties may be read from any thread.
    nonisolated static func startLead() -> TimeInterval {
        let session = AVAudioSession.sharedInstance()
        return session.outputLatency + session.ioBufferDuration
    }

    /// The output's IO buffer: a song started on an output already running is started this far past the
    /// engine's last render (as a sample time), so the start never lands inside a render under way. Read on
    /// the engine's queue.
    nonisolated static func ioBuffer() -> TimeInterval {
        AVAudioSession.sharedInstance().ioBufferDuration
    }

    /// How far the ear is behind the engine's render: the same sum, read at every position the
    /// engine gives (the lock screen, the scrubber, a pause, a new route), so each is what is heard -
    /// tens of milliseconds on the speaker, more on AirPods, about 2 s on AirPlay (iOS's own figure,
    /// unmeasured here). Read on the engine's queue.
    nonisolated static func latency() -> TimeInterval {
        let session = AVAudioSession.sharedInstance()
        return session.outputLatency + session.ioBufferDuration
    }

    /// The output's rate and its name, for the Hi-res readout.
    var outputRate: Double { AVAudioSession.sharedInstance().sampleRate }
    var outputName: String? { AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName }
}
