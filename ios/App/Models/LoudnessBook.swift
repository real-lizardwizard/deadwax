import DeadwaxCore
import Foundation

/// deadwax's loudness answers as the engine's queue reads them (levels.md 4.2: "a synchronous, lock-protected
/// answer(albumId)"): each album's last answer, whether its last read failed, and which albums a level wait is
/// standing on (read every second while it does). It holds no decisions - those are each queue's LevelStore's.
final class LoudnessShelf: @unchecked Sendable {
    /// How long a waiting first song's ask to read its album every second holds after the gate last asked.
    static let hurryHolds = 2.0

    private let lock = NSLock()
    private var answers: [String: AlbumLoudness] = [:]
    private var failed: Set<String> = []
    private var hurriedAt: [String: Double] = [:]

    /// The album's last answer, and whether the last read of it failed.
    func answer(_ album: String) -> (answer: AlbumLoudness?, failed: Bool) {
        lock.withLock { (answers[album], failed.contains(album)) }
    }

    func keep(_ answer: AlbumLoudness, for album: String) {
        lock.withLock {
            answers[album] = answer
            failed.remove(album)
        }
    }

    func readFailed(_ album: String) {
        _ = lock.withLock { failed.insert(album) }
    }

    /// A first song is waiting on the album's answer.
    func hurry(_ album: String, at now: Double) {
        lock.withLock { hurriedAt[album] = now }
    }

    /// The albums a first song has waited on in the last moments.
    func hurried(at now: Double) -> Set<String> {
        lock.withLock { Set(hurriedAt.filter { now - $0.value < Self.hurryHolds }.keys) }
    }

    func clear() {
        lock.withLock {
            answers = [:]
            failed = []
            hurriedAt = [:]
        }
    }
}

/// When the app asks deadwax about an album's loudness (levels.md 4.2, Core's LoudnessAsking): for an album WANTED -
/// the album page shown last (when Normalization would level it: AlbumPageLines.warms), or the album of the entry
/// playing or of one of the next three levelled ones (LoudnessAsking.wanted) - a read first, then a warm when nothing
/// is measured, then a read every 5 s while it is being measured; nothing under Off, nothing for an album with no
/// FLAC. A measured or not-levelled answer is believed 10 minutes. At most one request in flight per album, no warm
/// sooner than 5 s after the last; a failed read leaves the answer as it was and is tried again 5 s on. An album a
/// first song is waiting on (`LoudnessShelf.hurry`) is read every second instead.
///
/// A read that finds the album not measured is held back from the shelf until the warm it leads to answers: a warm
/// saying "measuring" is kept as measuring (LoudnessAsking.warmed), so the first song waits on it - it would have
/// been decided "not measured yet" from the read in the moment between.
@MainActor
final class LoudnessBook {
    let shelf = LoudnessShelf()
    /// An album's answer kept (for Info: PlayerModel.loudness(albumID:)).
    var onAnswer: ((String, AlbumLoudness) -> Void)?
    /// How many album pages stay wanted after they were shown.
    static let pagesKept = 2

    private enum Step { case read, warm }

    private struct Asking {
        var step: Step = .read
        var dueAt: Double = 0
        var lastAt: Double = -.infinity
        var warmedAt: Double = -.infinity
        var flying = false
        /// A read's not-measured answer, kept back until the warm it leads to has answered.
        var pending: AlbumLoudness?
    }

    private let server: ServerModel
    private var pages: [String] = []
    private var queued: [String] = []
    private var asks: [String: Asking] = [:]
    private var timer: Timer?
    /// +1 at every reset: an answer to a request from before is dropped.
    private var round = 0

    init(server: ServerModel) {
        self.server = server
    }

    // MARK: what is wanted

    /// An album page was shown whose songs Normalization would level.
    func wantPage(_ album: String) {
        pages.removeAll { $0 == album }
        pages.insert(album, at: 0)
        if pages.count > Self.pagesKept { pages.removeLast(pages.count - Self.pagesKept) }
        run()
    }

    /// The album's page went (or the album did).
    func leavePage(_ album: String) {
        pages.removeAll { $0 == album }
        run()
    }

    /// The queue's albums wanted now (LoudnessAsking.wanted).
    func wantQueue(_ albums: [String]) {
        guard albums != queued else { return }
        queued = albums
        run()
    }

    /// The person changed: nothing asked or kept of theirs.
    func reset() {
        round += 1
        pages = []
        queued = []
        asks = [:]
        shelf.clear()
        timer?.invalidate()
        timer = nil
    }

    private var wanted: [String] {
        var all = queued
        for page in pages where !all.contains(page) { all.append(page) }
        return all
    }

    // MARK: asking

    private func run() {
        let wanted = self.wanted
        guard !wanted.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: LevelWait.pollSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.run() }
            }
        }
        guard let client = server.client else { return }
        let now = Monotonic.seconds()
        let hurried = shelf.hurried(at: now)
        for album in wanted {
            var asking = asks[album] ?? Asking()
            guard !asking.flying else { continue }
            var due = asking.dueAt
            if hurried.contains(album), asking.step == .read, !done(album) {
                due = min(due, asking.lastAt + LevelWait.pollSeconds)
            }
            guard now >= due else { continue }
            asking.flying = true
            asking.lastAt = now
            asks[album] = asking
            switch asking.step {
            case .read: read(album, client: client)
            case .warm: warm(album, client: client)
            }
        }
    }

    /// The album's answer in hand is one nothing more is asked for while it is believed.
    private func done(_ album: String) -> Bool {
        guard let answer = shelf.answer(album).answer else { return false }
        return LoudnessAsking.afterRead(answer) == .done
    }

    private func read(_ album: String, client: DeadwaxClient) {
        let round = self.round
        Task {
            do {
                let answer = try await client.call(Routes.loudness, as: AlbumLoudness.self, path: ["album_id": album])
                guard round == self.round else { return }
                read(album, answered: answer)
            } catch {
                guard round == self.round else { return }
                if APIFailure.isCancellation(error) {
                    asks[album]?.flying = false
                    return
                }
                readFailed(album)
            }
        }
    }

    private func read(_ album: String, answered answer: AlbumLoudness) {
        let now = Monotonic.seconds()
        var asking = asks[album] ?? Asking()
        asking.flying = false
        asking.pending = nil
        switch LoudnessAsking.afterRead(answer) {
        case .done:
            keep(answer, for: album)
            asking.step = .read
            asking.dueAt = now + LoudnessAsking.keptSeconds
        case .readAgain:
            keep(answer, for: album)
            asking.step = .read
            asking.dueAt = now + LoudnessAsking.againSeconds
        case .warm:
            asking.step = .warm
            asking.dueAt = max(now, asking.warmedAt + LoudnessAsking.againSeconds)
            if asking.dueAt <= now {
                // warmed at once: the read's "not measured" waits for the warm's answer
                asking.pending = answer
            } else {
                keep(answer, for: album)
            }
        }
        asks[album] = asking
        run()
    }

    private func readFailed(_ album: String) {
        shelf.readFailed(album)
        var asking = asks[album] ?? Asking()
        asking.flying = false
        asking.dueAt = Monotonic.seconds() + LoudnessAsking.againSeconds
        asks[album] = asking
    }

    private func warm(_ album: String, client: DeadwaxClient) {
        let round = self.round
        Task {
            let said: WarmAnswer?
            do {
                said = WarmAnswer(state: try await client.warmLevels(albumID: album))
            } catch {
                guard round == self.round else { return }
                if APIFailure.isCancellation(error) {
                    asks[album]?.flying = false
                    return
                }
                said = nil
            }
            guard round == self.round else { return }
            warmed(album, said: said)
        }
    }

    /// A warm answered (`said`), or failed (nil).
    private func warmed(_ album: String, said: WarmAnswer?) {
        let now = Monotonic.seconds()
        var asking = asks[album] ?? Asking()
        asking.flying = false
        asking.warmedAt = asking.lastAt
        let held = asking.pending
        asking.pending = nil
        if let said {
            let base = held ?? shelf.answer(album).answer
            if let kept = LoudnessAsking.warmed(base, said: said) {
                keep(kept, for: album)
            } else if let held {
                keep(held, for: album)
            }
            asking.step = LoudnessAsking.afterWarm(said) == .warm ? .warm : .read
        } else if let held {
            keep(held, for: album)
        }
        asking.dueAt = now + LoudnessAsking.againSeconds
        asks[album] = asking
    }

    private func keep(_ answer: AlbumLoudness, for album: String) {
        shelf.keep(answer, for: album)
        onAnswer?(album, answer)
    }
}
