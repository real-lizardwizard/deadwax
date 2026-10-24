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

    /// What the lock screen shows. iOS runs the clock on from `elapsed` at `rate`, so this is set
    /// when something changes, not every second.
    func show(song: Song, index: Int, count: Int, elapsed: Double, playing: Bool, artwork: UIImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist = song.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = song.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = song.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
