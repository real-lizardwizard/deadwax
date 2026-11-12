import Foundation

// Resume what was playing, the app's half - ui/src/app/useResume.ts as a state machine over the player, deadwax
// and a clock, each reached through a protocol here, so it is tested on Linux against fakes on a virtual clock as
// ui/test/resume.sim.cjs tests the hook. The app makes one per signed-in person (logins off: one), on the main
// thread, and calls it for everything below; Resume.swift holds the rules it acts on.
//
// PUTTING BACK. Started with the player's queue empty, it asks deadwax for the person's play queue and puts back
// what resumed() makes of it with the player's restoreQueue - paused, at the second it stopped, nothing loaded or
// fetched: the next play starts it, in its tap. The answer is used only while the queue is still the one it was
// asked for (a tap meanwhile wins) and nothing plays. Coming back to the front (at most every RESUME_RECHECK_MS,
// never while playing) it asks again: an empty queue, or one put back and untouched since, takes what is newer; a
// queue paused after playing here takes only what another device of deadwax's or another app saved since this one
// last did, and only with logins on (with them off everyone shares one queue, and a paused player never takes
// somebody else's); with changes not yet saved it saves them instead, and asks nothing. The notice says where it
// came from, once. (The web then asks for the song's album, for Info; the phone doesn't - D5.)
//
// SAVING follows this phone's own playing - a queue merely put back is the baseline, so opening the app writes
// nothing: a FULL save (POST /queue) when the songs or Up Next changed, RESUME_FULL_WAIT_MS after the last change; a
// POSITION save (POST /queue/at, against the full save's ids_rev) at a song change RESUME_AT_WAIT_MS after, at a
// pause at once, every RESUME_EVERY_S of playing counted by the player's own position reports (not a timer of its
// own), and after a scrub while paused; and whatever is due as the app goes to the background. One request at a
// time (a save due meanwhile waits for it; going to the background sends at once); a failure is tried again at the
// next trigger, at most every 30 s; a 409 or 422 on a position save, a full save now; a 401 stops saving until
// someone signs in again; an answer of no rev (the break-glass admin, who keeps no queue) for good.
//
// Where the phone differs from the page: no window focus or its grace (a foregrounded app shows before a tap can
// land), no sendBeacon or keepalive budget - every save is an ordinary request, answered and counted in flight (the
// app keeps each alive in the background with beginBackgroundTask) - and no album asked after a pick-up.
//
// KEPT ON THE PHONE (Phase 2, phase2-downloads.md 7.5, 7.6; given a ResumeKeeper - without one, all of this is off
// and the controller is the web's). The queue this phone last saved or took is kept in the person's download store
// (QueueKept): written as each save is sent - `unsent` until deadwax answers it, then sent - and as a queue is put
// back. The app opened with deadwax out of reach (the open's ask not answered, whatever the failure) puts it back,
// paused, as an answer would be put back, and says nothing - it is this phone's own. While a save is kept unsent and
// none is out, the next open or return to the front asks deadwax FIRST: a queue another device or app saved since this
// phone last saved or took (`newer`, and not the answer it already took) wins, as a position save's 409 has it
// (resume.md Open question 4) - taken as resume takes one, the kept save let go; else the phone's own is put back
// (into an empty player) and sent at once. Only open and return wait for that ask: a save due while playing, a pause,
// a wait or the background goes as Phase 1's do - the queue playing here is the present. A 401 holds the kept save
// for the same person (its store; saving resumes when the session moves); someone else's controller has their own.

/// What of the player resume reads, and its one action.
public protocol ResumePlayer: AnyObject {
    /// Seconds into the song playing as the engine says it now - a queue put back paused answers its parked second.
    func position() -> Double
    /// The queue put back paused at `position` seconds into its song (QueueController.restoreQueue): fitted to this
    /// device's Repeat, nothing loaded or played. Nil - nothing done - while the listener means music to play.
    func restoreQueue(_ queue: UpNextQueue, position: Double) -> UpNextQueue?
}

/// Why a request to deadwax didn't give resume its answer: deadwax's status (401 signed out, 409 the queue changed
/// on another device, 422 a body it refused, 502 Navidrome, 503 no record), or nothing that answered at all.
public enum ResumeFailure: Error, Sendable, Equatable {
    case status(Int)
    case unanswered

    /// From what the app's client says of a failure: deadwax's status where it answered one (an APIFailure's
    /// `status`), else nothing that answered - unreachable, timed out, an answer that couldn't be read.
    public init(status: Int?) {
        self = status.map(ResumeFailure.status) ?? .unanswered
    }
}

/// deadwax's three queue routes, as the app reaches them. Each calls `done` once, on the main thread, when it is
/// answered - or never, for a request the app gave up on (a sign-out).
public protocol ResumeServer: AnyObject {
    /// GET /deadwax/navidrome/queue
    func queue(_ done: @escaping (Result<QueueAnswer, ResumeFailure>) -> Void)
    /// POST /deadwax/navidrome/queue
    func save(_ body: QueueSaveBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void)
    /// POST /deadwax/navidrome/queue/at
    func saveAt(_ body: QueueAtBody, _ done: @escaping (Result<SavedQueue, ResumeFailure>) -> Void)
}

/// A wait that can be let go of.
public protocol ResumeWait: AnyObject {
    func cancel()
}

/// Time, as resume reads it: ms on a clock that only goes forward (only differences are read), a wait, and "soon" -
/// after the call making it has returned, before any wait comes due (the web's microtask; the app's next turn of
/// the main queue).
public protocol ResumeClock: AnyObject {
    var now: Int64 { get }
    func after(_ ms: Int64, _ work: @escaping () -> Void) -> ResumeWait
    func soon(_ work: @escaping () -> Void)
}

/// The person's queue kept on this phone (Phase 2: the download store's queue_pending row) - read as the controller
/// is made, written as the queue is saved or taken. Called on the main thread.
public protocol ResumeKeeper: AnyObject {
    func read() -> QueueKept?
    /// nil forgets it
    func write(_ kept: QueueKept?)
    /// Navidrome's size of a song, where the app knows it - kept with the queue, for the stream cache's whole-copy
    /// check offline.
    func size(of songID: String) -> Int64?
}

public extension ResumeKeeper {
    func size(of songID: String) -> Int64? { nil }
}

public final class ResumeController {
    public enum Why: Sendable { case open, front }

    /// This phone's id (DeviceID) and label in deadwax's record.
    public let device: String
    public let label: String

    private let player: ResumePlayer
    private let server: ResumeServer
    private let clock: ResumeClock
    private let session: () -> Int
    private let normalization: () -> Normalization
    private let say: (String) -> Void

    /// The queue and play state as last observed.
    private var queue: UpNextQueue?
    private var playing = false
    /// What saveDue reads.
    public private(set) var saves = SaveClock()
    /// The rev this phone last saved, or took; whether the queue is everyone's (logins off), as deadwax last said.
    private var lastRev: Int?
    private var shared: Bool?
    /// A queue put back, while nothing has been done to it.
    private var parked: (queue: UpNextQueue, position: Double)?
    /// What was put back last; when deadwax was last asked.
    private var taken: String?
    private var askedAt: Int64?
    /// Saves out now, and the last one sent while any is out.
    public private(set) var flying = 0
    private var lastSent: (queue: UpNextQueue, position: Double, kind: SaveKind)?
    /// Where the notice last said a queue came from, and that queue's songs.
    private var said: (from: String, ids: String)?
    /// What came while a request was out, asked again once it is answered - the most pressing first.
    private var owed = Set<SaveTrigger>()
    /// deadwax keeps no queue for whoever this is (the break-glass admin): nothing is saved for the controller's life.
    public private(set) var off = false
    /// A 401 under this session generation: nothing saved until it changes.
    private var signedOutUnder: Int?
    private var fullWait: ResumeWait?
    private var atWait: ResumeWait?
    /// The newest GET's number: only its answer is read (CLAUDE.md, "only the newest answer draws").
    private var asks = 0
    /// Inside the player's restoreQueue: what it reports of the queue it puts back is recorded, not a change.
    private var restoring = false
    private var stopped = false
    /// The person's queue kept on this phone, and what it holds as last read or written (Phase 2).
    private let keeper: ResumeKeeper?
    public private(set) var kept: QueueKept?
    /// One more at every write: a save's answer marks the row sent only while it is still that save's.
    private var keptWrites = 0

    /// - Parameters:
    ///   - session: the app's sign-in generation, +1 at every sign-in - a 401 stops saving until it moves.
    ///   - normalization: the phone's Normalization, read at each pick-up.
    ///   - say: the app's notice ("Picked up from your Mac").
    ///   - keeper: the person's queue kept on this phone (Phase 2) - nil: nothing kept, the web's rules alone.
    public init(device: String, label: String = Resume.label, player: ResumePlayer, server: ResumeServer,
                clock: ResumeClock, session: @escaping () -> Int, normalization: @escaping () -> Normalization,
                say: @escaping (String) -> Void, keeper: ResumeKeeper? = nil) {
        self.device = device
        self.label = label
        self.player = player
        self.server = server
        self.clock = clock
        self.session = session
        self.normalization = normalization
        self.say = say
        self.keeper = keeper
        //? what this phone last saved or took, as it knew deadwax then: what an answer is judged newer than
        if let row = keeper?.read() {
            kept = row
            lastRev = row.rev
            taken = row.seen
        }
    }

    // MARK: what the app tells it

    /// The player's queue or play state may have changed - called whenever either does (the web reads them at every
    /// render), the first time before `start()`. Bookkeeping only: what it asks for is sent after this returns.
    public func observe(queue next: UpNextQueue, playing nowPlaying: Bool) {
        guard !stopped else { return }
        let was = queue
        let wasPlaying = playing
        queue = next
        playing = nowPlaying
        guard let was, !restoring else { return }
        if let held = parked, next != held.queue || nowPlaying { parked = nil }
        if next != was {
            saves.changedAt = clock.now
            //? the wait is chosen against what was last SAVED, not the last observation: an edit not yet saved, then
            //? a song change inside its 2 s, is still a change of the songs - its full wait armed again from now
            wait(changedSince(saves.saved, next, position: player.position()) == .songs ? .full : .at)
        }
        if nowPlaying && !wasPlaying { saves.countFrom = clock.now }
        if !nowPlaying && wasPlaying { clock.soon { [weak self] in self?.consider(.pause) } }
    }

    /// The engine's position report: the app's ticker while playing (twice a second; it runs while locked and
    /// playing), and every seek, paused or put back, too. The 30 s saves are counted by these, never by a timer.
    public func position(_ seconds: Double) {
        guard !stopped else { return }
        if let held = parked, abs(seconds - held.position) > 0.5 { parked = nil }
        clock.soon { [weak self] in
            guard let self, !self.stopped else { return }
            if self.playing {
                self.consider(.position)
            } else if let saved = self.saves.saved, abs(self.player.position() - saved.position) > 1 {
                self.wait(.at)
            }
        }
    }

    /// Signed in (or logins off) and the first queue observed: with it empty, deadwax is asked what was playing.
    public func start() {
        guard !stopped, let queue, queue.current == nil else { return }
        ask(.open)
    }

    /// The app went to the background: whatever is due is saved at once.
    public func background() {
        consider(.hidden)
    }

    /// The app came back to the front.
    public func foreground() {
        front()
    }

    /// A sign-out, or a sign-in as someone else: answers still out are let go, the waits too, and nothing more is
    /// done - the app makes a new controller for whoever is next.
    public func stop() {
        stopped = true
        asks += 1
        fullWait?.cancel()
        atWait?.cancel()
    }

    // MARK: saving

    private func wait(_ kind: SaveKind) {
        let delay = (kind == .full ? Resume.fullWaitMs : Resume.atWaitMs) + Resume.marginMs
        let work: () -> Void = { [weak self] in self?.consider(.wait) }
        if kind == .full {
            fullWait?.cancel()
            fullWait = clock.after(delay, work)
        } else {
            atWait?.cancel()
            atWait = clock.after(delay, work)
        }
    }

    private func consider(_ trigger: SaveTrigger) {
        guard !stopped, !off, let queue else { return }
        if let under = signedOutUnder {
            if session() == under { return }
            signedOutUnder = nil
        }
        let position = player.position()
        let now = clock.now
        guard let due = saveDue(saves, queue, position: position, playing: playing, now: now, trigger: trigger) else { return }
        if flying > 0 {
            //? one at a time - but going to the background sends what it must at once (unless the very same save
            //? is already out: the app may hear of the background twice)
            guard trigger == .hidden else {
                owed.insert(trigger)
                return
            }
            if let last = lastSent, last.queue == queue, last.position == position, last.kind == due { return }
        }
        send(due, queue, position, now)
    }

    private func send(_ kind: SaveKind, _ sending: UpNextQueue, _ position: Double, _ now: Int64) {
        lastSent = (sending, position, kind)
        //? kept before it goes, unsent: the app may be closed, or the network gone, before deadwax answers
        let made: Saving? = keeper == nil ? nil : toSave(sending, position: position)
        if let made { keep(sending, position: position, saving: made, unsent: true, seen: kept?.seen ?? taken) }
        let write = keptWrites
        if kind == .at, let saved = saves.saved, let idsRev = saves.idsRev {
            let body = QueueAtBody(ids_rev: idsRev, index: sending.index - saved.start, position: Resume.sent(position),
                                   device: device, label: label)
            let baseline = SaveBaseline(tracks: sending.tracks, upNext: sending.upNext, index: sending.index,
                                        position: position, start: saved.start, count: saved.count)
            flying += 1
            server.saveAt(body) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let answer): self.answered(baseline, answer, sentAt: now, full: false, write: write)
                case .failure(let failure): self.refused(failure, position: true)
                }
                self.settled()
            }
            return
        }
        let saving = made ?? toSave(sending, position: position)
        let body = QueueSaveBody(ids: saving.ids, index: saving.index, position: Resume.sent(position), device: device,
                                 label: label, snapshot: saving.snapshot)
        let baseline = SaveBaseline(tracks: sending.tracks, upNext: sending.upNext, index: sending.index,
                                    position: position, start: saving.start, count: saving.ids.count)
        flying += 1
        server.save(body) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let answer): self.answered(baseline, answer, sentAt: now, full: true, write: write)
            case .failure(let failure): self.refused(failure, position: false)
            }
            self.settled()
        }
    }

    /// - Parameter write: the kept row's write this save made - marked sent only while it is still that one (a newer
    ///   save kept meanwhile is still unsent).
    private func answered(_ baseline: SaveBaseline, _ answer: SavedQueue, sentAt: Int64, full: Bool, write: Int) {
        guard let rev = answer.rev else {
            off = true
            //? deadwax keeps no queue for whoever this is: nothing kept for them either
            if keeper != nil { rewrite(nil) }
            return
        }
        saves.saved = baseline
        saves.failedAt = nil
        saves.countFrom = sentAt
        lastRev = rev
        if full { saves.idsRev = answer.ids_rev }
        if write == keptWrites, var row = kept, row.unsent {
            row.unsent = false
            row.rev = rev
            //? GET /queue's answer for this save, as resume signs one: the same answer later is nothing new
            row.seen = "kept:\(rev)"
            rewrite(row)
        }
    }

    private func refused(_ failure: ResumeFailure, position: Bool) {
        if failure == .status(401) {
            signedOutUnder = session()
            return
        }
        //? (a position save) the ids changed elsewhere, or aren't the ones kept: saved in full, now
        if position && (failure == .status(409) || failure == .status(422)) {
            saves.idsRev = nil
            owed.insert(.pause)
            return
        }
        saves.failedAt = clock.now
    }

    private func settled() {
        flying -= 1
        if flying == 0 { lastSent = nil }
        guard flying == 0, !owed.isEmpty else { return }
        let triggers = Resume.owedOrder.filter { owed.contains($0) }
        owed.removeAll()
        for trigger in triggers {
            consider(trigger)
            if flying > 0 { return }
        }
    }

    // MARK: putting back

    /// Whether deadwax holds a queue saved since this phone's last save, by another of the person's devices or apps.
    private func newer(_ answer: QueueAnswer) -> Bool {
        if let kept = answer.kept { return kept.device != device && kept.rev > (lastRev ?? 0) }
        return !answer.changed_by.isEmpty && answer.changed_by != Resume.deadwaxClient
    }

    /// What an answer was, to tell a newer one from the one taken last.
    private func signature(_ answer: QueueAnswer) -> String {
        if let kept = answer.kept { return "kept:\(kept.rev)" }
        let index = answer.index.map(String.init) ?? "null"
        return "\(answer.changed_by)|\(index)|\(answer.position)|\(answer.tracks.map(\.id).joined(separator: ","))"
    }

    private func take(_ answer: QueueAnswer, _ why: Why) {
        guard let queue else { return }
        guard let back = resumed(answer, setting: normalization(), device: device) else { return }
        let sign = signature(answer)
        let untouched = parked.map { $0.queue == queue } ?? false
        if why == .front {
            if sign == taken { return }
            if queue.current != nil && !untouched && (answer.shared || !newer(answer)) { return }
        }
        restoring = true
        let restored = player.restoreQueue(back.queue, position: back.position)
        restoring = false
        guard let put = restored else { return }
        taken = sign
        let position = player.position()
        parked = (put, position)
        //? a queue merely put back is the baseline: nothing is saved for it
        saves.saved = SaveBaseline(tracks: put.tracks, upNext: put.upNext, index: put.index, position: position,
                                   start: 0, count: put.tracks.count)
        //? a position save is made against deadwax's ids only while the queue put back is exactly them (fitting it
        //? to this device's Repeat can change them - then the first save is a full one)
        if let record = answer.kept, back.exact, put.tracks.map(\.id) == record.ids {
            saves.idsRev = record.ids_rev
        } else {
            saves.idsRev = nil
        }
        saves.changedAt = nil
        saves.failedAt = nil
        saves.countFrom = nil
        if let record = answer.kept { lastRev = record.rev }
        fullWait?.cancel()
        atWait?.cancel()
        if keeper != nil { keep(put, position: position, unsent: false, seen: sign) }
        //? said once: a queue put back and untouched, taken again from where the notice said with the same songs -
        //? the other device playing on in them - is the same pick-up, its second moved
        let from: String? = back.from.map {
            switch $0 {
            case .device(let label): return "device:\(label)"
            case .app(let name): return "app:\(name)"
            }
        }
        let songs = put.tracks.map(\.id).joined(separator: ",")
        let again = why == .front && untouched && said?.from == from && said?.ids == songs
        if !again, let words = pickedUpWords(back.from, shared: answer.shared) { say(words) }
        said = from.map { ($0, songs) }
    }

    private func ask(_ why: Why) {
        let asked = queue
        askedAt = clock.now
        asks += 1
        let number = asks
        server.queue { [weak self] result in
            guard let self, !self.stopped, number == self.asks else { return }
            //? Navidrome or deadwax not answering: nothing of theirs put back - asked again at the next foreground. As
            //? the app opens, the queue kept on this phone is put back in its place (Phase 2, 7.5)
            guard case .success(let answer) = result else {
                if why == .open, self.queue == asked, !self.playing, let row = self.kept { self.putBack(row) }
                return
            }
            self.shared = answer.shared
            //? a tap since wins: the queue has changed, or music plays
            if self.queue != asked || self.playing { return }
            if self.holdsUnsent {
                self.settleKept(answer, why)
            } else {
                self.take(answer, why)
            }
        }
    }

    private func front() {
        guard !stopped, let queue, !playing else { return }
        if let askedAt, clock.now - askedAt < Resume.recheckMs { return }
        //? (Phase 2) a save kept unsent: deadwax is asked first - a queue saved elsewhere since wins - and only then
        //? is it sent
        if holdsUnsent {
            ask(.front)
            return
        }
        if queue.current != nil && changedSince(saves.saved, queue, position: player.position()) != nil {
            consider(.pause)
            return
        }
        let untouched = parked.map { $0.queue == queue } ?? false
        //? logins off: a paused player never takes somebody else's queue - nothing to ask for
        if queue.current != nil && !untouched && shared == true { return }
        ask(.front)
    }

    // MARK: kept on the phone (Phase 2)

    /// A save kept that deadwax hasn't answered, and none out now: the next open or return asks deadwax first.
    private var holdsUnsent: Bool {
        kept?.unsent == true && flying == 0
    }

    /// The queue in the player kept as this phone's last - `unsent` while deadwax hasn't answered for it.
    private func keep(_ queue: UpNextQueue, position: Double, saving: Saving? = nil, unsent: Bool, seen: String?) {
        guard let keeper else { return }
        rewrite(QueueKept(queue: queue, position: position, saving: saving, device: device, label: label, rev: lastRev,
                          idsRev: saves.idsRev, shared: shared ?? false, seen: seen, unsent: unsent,
                          size: { keeper.size(of: $0) }))
    }

    private func rewrite(_ row: QueueKept?) {
        kept = row
        keptWrites += 1
        keeper?.write(row)
    }

    /// A save kept unsent, and deadwax's answer in hand (`holdsUnsent` when it was asked): a queue another device or
    /// app saved since this phone last saved or took - newer, and not the one it already took - wins, taken as resume
    /// takes one (by its own rules: into an empty player, or a queue put back and untouched; a paused one only with
    /// logins on), and the kept save is let go. Else this phone's own is put back into an empty player and sent now.
    private func settleKept(_ answer: QueueAnswer, _ why: Why) {
        guard let row = kept else { return }
        if signature(answer) != taken && newer(answer) {
            take(answer, why)
            if var left = kept, left.unsent {
                left.unsent = false
                rewrite(left)
            }
            return
        }
        if queue?.current == nil { putBack(row) }
        sendKept()
    }

    /// The queue kept on this phone put back into an empty player, paused at its second, as resume puts back deadwax's
    /// (resumed(), then the player's restoreQueue) - with no notice: it is this phone's own. It is the baseline, as a
    /// queue put back is: nothing is saved for it until it is played or changed (a kept save not sent goes once deadwax
    /// has been asked). Its ids_rev isn't believed: the first save after is a full one.
    private func putBack(_ row: QueueKept) {
        guard let queue, queue.current == nil,
              let back = resumed(row.answer, setting: normalization(), device: device) else { return }
        restoring = true
        let restored = player.restoreQueue(back.queue, position: back.position)
        restoring = false
        guard let put = restored else { return }
        let position = player.position()
        parked = (put, position)
        saves.saved = SaveBaseline(tracks: put.tracks, upNext: put.upNext, index: put.index, position: position,
                                   start: 0, count: put.tracks.count)
        saves.idsRev = nil
        saves.changedAt = nil
        saves.failedAt = nil
        saves.countFrom = nil
        fullWait?.cancel()
        atWait?.cancel()
    }

    /// The kept save sent now, as the queue is in the player: a position save where saveDue would make one, else in
    /// full - unless a 401 still holds saving under this session, or deadwax keeps no queue for this person.
    private func sendKept() {
        guard !stopped, !off, flying == 0, let queue, queue.current != nil else { return }
        if let under = signedOutUnder {
            if session() == under { return }
            signedOutUnder = nil
        }
        saves.failedAt = nil
        let position = player.position()
        let now = clock.now
        let kind = saveDue(saves, queue, position: position, playing: playing, now: now, trigger: .pause) ?? .full
        send(kind, queue, position, now)
    }
}
