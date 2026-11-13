import DeadwaxCore
import Foundation
import MediaPlayer
import UIKit

/// The lock screen and Control Center (MPNowPlayingInfoCenter), and the controls that reach the
/// app from there and from AirPods (MPRemoteCommandCenter: a squeeze or a double tap arrives as
/// one of these commands).
@MainActor
final class NowPlayingController {
    struct Actions {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (Double) -> Void
    }

    private var connected = false

    func connect(_ actions: Actions) {
        guard !connected else { return }
        connected = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in onMain { actions.play() }; return .success }
        center.pauseCommand.addTarget { _ in onMain { actions.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in onMain { actions.toggle() }; return .success }
        center.nextTrackCommand.addTarget { _ in onMain { actions.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in onMain { actions.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            onMain { actions.seek(time) }
            return .success
        }
        let unused: [MPRemoteCommand] = [center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand,
                                          center.seekBackwardCommand, center.changeRepeatModeCommand, center.changeShuffleModeCommand]
        for command in unused { command.isEnabled = false }
    }

    /// What the lock screen shows: the entry heard - its title, artist and album as the queue has them, and its
    /// length (the engine's decoded length once known, else Navidrome's). iOS runs the clock on from `elapsed` at
    /// `rate`, so this is set when something changes, not every second. `elapsed` is what is heard (the engine takes
    /// the output's latency off), in the song's own seconds at any speed. No queue index or count since 0.2: Repeat's
    /// copies and Up Next's edits make them mean nothing a listener could use.
    ///
    /// The speed (turntable.md 5.2, app 0.7): playing, the rate is the speed - so the lock screen's scrubber moves at
    /// it, the web's "the lock screen's scrubber moves at the speed" - and 0 paused; the default rate stays 1.0, the
    /// song's own speed (Apple's meaning: the normal rate).
    func show(title: String, artist: String?, album: String?, duration: Double?, elapsed: Double, playing: Bool,
              rate: Double, artwork: UIImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The paused state published again (turntable.md 4.6): rate 0 at `elapsed`, the rest as it stands - for the
    /// turntable's deck engine stopping after the song had paused (a wind-down), as iOS goes by the app's running
    /// output and may not have taken the pause while the deck's still ran. Nothing when nothing is shown.
    static func republishPaused(elapsed: Double) {
        let center = MPNowPlayingInfoCenter.default()
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        center.nowPlayingInfo = info
    }
}

/// The remote commands' handlers come on the main thread in practice; this holds whatever thread
/// they come on.
private func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
