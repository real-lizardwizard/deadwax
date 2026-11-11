import DeadwaxCore
import Foundation

/// Plays told to Navidrome (D6): one listen at a time, kept by Core's ListenTracker - "now playing" once a listen is
/// heard, a play once it crosses the rule (a song longer than 30 s, heard for half of it or 4 minutes, whichever is
/// less) - each sent to deadwax's scrobble route, a play with its `time` (the moment its listen began). A send that
/// fails is dropped: the music never waits on it and nothing is sent twice.
///
/// The model tells it: `newListen` at every song change it made (and a restart, a queue put back from where it was
/// left), `join` when the engine ran into the next song by itself, `seeked` at every seek and retry, `began` when the
/// entry heard is playing, `tick` from the ticker, `stop` at a stop or a new person.
@MainActor
final class PlayReporter {
    private let server: ServerModel
    private var tracker = ListenTracker()
    /// The entry the listen is of (the engine's key, unique across queues), or nil.
    private(set) var listening: Int?

    init(server: ServerModel) {
        self.server = server
    }

    /// How much of the song has been heard in this listen (Repeat's top-up reads it).
    var heard: Double { tracker.listen.heard }

    func newListen(entry: Int, songID: String, from position: Double = 0) {
        listening = entry
        tracker.newListen(songID: songID, at: Monotonic.seconds(), from: position)
    }

    func seeked() {
        tracker.seeked()
    }

    func stop() {
        tracker.stop()
        listening = nil
    }

    /// The entry heard is playing (its first sample on a running output): "now playing", once per listen.
    func began(entry: Int) {
        guard entry == listening, let report = tracker.began(wallMs: ListenTracker.wallMs()) else { return }
        send(report)
    }

    func tick(position: Double, duration: Double) {
        guard let report = tracker.tick(position: position, monotonic: Monotonic.seconds(), duration: duration) else { return }
        send(report)
    }

    /// The engine ran on into `entry` by itself (a gapless join): the old song's rest counted to it, and a new
    /// listen for the new one with what is heard of it already.
    func join(entry: Int, songID: String, oldLength: Double, newPosition: Double, newDuration: Double) {
        listening = entry
        let reports = tracker.join(into: songID, oldLength: oldLength, newPosition: newPosition,
                                   monotonic: Monotonic.seconds(), newDuration: newDuration, wallMs: ListenTracker.wallMs())
        for report in reports { send(report) }
    }

    private func send(_ report: PlayReport) {
        guard let client = server.client else { return }
        let request = client.request(Routes.scrobble, path: ["song_id": report.songID], query: report.query)
        Task { _ = try? await client.answer(request) }
    }
}
