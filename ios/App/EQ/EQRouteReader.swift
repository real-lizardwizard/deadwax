import AVFAudio
import DeadwaxCore
import Foundation

/// The route as Core's EQOutputs reads it (eq.md 3.12): AVAudioSession's outputs, each port's kind in deadwax's own
/// words (so Core needs nothing of AVFoundation), and the output they are. Read on the main thread (EQModel) and on the
/// engine's queue (the start hook): AVAudioSession's properties may be read from any thread.
enum EQRouteReader {
    /// The route's ports now.
    nonisolated static func ports() -> [EQRoutePort] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { (p: AVAudioSessionPortDescription) -> EQRoutePort in
            EQRoutePort(port: port(p.portType), portType: p.portType.rawValue, name: p.portName, uid: p.uid)
        }
    }

    /// The output now - the speaker for a route with no output (between two, a moment).
    nonisolated static func output() -> EQOutput {
        EQOutputs.output(ports()) ?? EQOutputs.speaker
    }

    /// The output's rate as the session gives it - the unit's own once it has started (`EQHost.rate`).
    nonisolated static func rate() -> Double {
        let rate = AVAudioSession.sharedInstance().sampleRate
        return rate > 0 ? rate : 48_000
    }

    nonisolated static func port(_ p: AVAudioSession.Port) -> EQPort {
        switch p {
        case .builtInSpeaker: return .builtInSpeaker
        case .headphones: return .headphones
        case .bluetoothA2DP: return .bluetoothA2DP
        case .bluetoothLE: return .bluetoothLE
        case .usbAudio: return .usbAudio
        case .carAudio: return .carAudio
        case .airPlay: return .airPlay
        case .HDMI: return .hdmi
        case .lineOut: return .lineOut
        default: return .other
        }
    }
}
