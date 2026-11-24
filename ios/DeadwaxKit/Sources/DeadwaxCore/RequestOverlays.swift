import Foundation

// The Requests tab's overlays, speeds and per-person words (phase6-get-requests.md 2.2-2.4): ui/src/lib/
// downloadOverlay.ts, ui/src/lib/speed.ts, ui/src/lib/perPerson.ts and myLibrary.ts's grantWords and partlyWords, each
// ported to the character and held to them by Fixtures/requests/requests-vectors.json.

// MARK: the overlays (downloadOverlay.ts)

/// A download asked for and not yet a job: its row is up from the tap, and becomes the real row when the job shows in a
/// poll (`jobId` set and seen) - or says why when it was refused (`error` set), staying until Clear done.
public struct PendingDownload: Sendable, Equatable, Decodable {
    public var key: String
    public var artist: String
    public var album: String
    public var username: String
    public var jobId: Int?
    /// Refused: why, in a listener's words - its being here is what makes the row a refusal.
    public var error: String?
    /// ...and the error's own words, for whoever runs deadwax.
    public var detail: String?
    /// (The phone's own - slice 2's review, finding 2) What the request was for - its pressing and its folder - and the
    /// jobs listed as it was asked, so a poll can find its job when deadwax's answer never came (`claimed`). Nil in the
    /// web's vectors, which have none of it.
    public var releaseMbid: String?
    public var directory: String?
    public var listedBefore: [Int]?
    /// The phone stopped waiting for deadwax's answer (`RequestOverlays.unanswered`): the row stays "starting…" while
    /// the poll looks for its job - and, given up on after `unansweredSeconds`, says it may have started.
    public var unanswered: Bool?
    /// (Manual search, slice A1) Asked for from Search Soulseek: its row marked "manual search" from the tap, as its job's
    /// will be. Nil in the web's vectors.
    public var manual: Bool?

    public init(key: String, artist: String, album: String, username: String, jobId: Int? = nil, error: String? = nil,
                detail: String? = nil, releaseMbid: String? = nil, directory: String? = nil, listedBefore: [Int]? = nil,
                unanswered: Bool? = nil, manual: Bool? = nil) {
        self.key = key
        self.artist = artist
        self.album = album
        self.username = username
        self.jobId = jobId
        self.error = error
        self.detail = detail
        self.releaseMbid = releaseMbid
        self.directory = directory
        self.listedBefore = listedBefore
        self.unanswered = unanswered
        self.manual = manual
    }

    /// Given up on with no answer: it may have started all the same (`RequestOverlays.gaveUp`).
    public var mayHaveStarted: Bool { unanswered == true && error != nil }

    /// Still waiting on slskd - it counts as active; a refused one doesn't.
    public var isWaiting: Bool { error == nil }
}

/// Predictions laid over the polled jobs, never edits of them - each dropped the moment a poll agrees (`reconcile`), or
/// after `RequestOverlays.ttlSeconds` when it never does.
public struct RequestOverlays: Sendable, Equatable {
    /// Cancels asked for, not yet confirmed.
    public var cancelling: Set<Int>
    /// Finished jobs taken away by Clear done, not yet gone from the server's list.
    public var cleared: Set<Int>
    /// Downloads asked for that aren't jobs yet, newest first.
    public var pending: [PendingDownload]
    /// Failed or cancelled jobs starting again, until a poll shows them active.
    public var retrying: Set<Int>

    public init(cancelling: Set<Int> = [], cleared: Set<Int> = [], pending: [PendingDownload] = [], retrying: Set<Int> = []) {
        self.cancelling = cancelling
        self.cleared = cleared
        self.pending = pending
        self.retrying = retrying
    }

    public static let none = RequestOverlays()

    /// How long an overlay the server never confirms stands (useDownloadJobs.ts OPTIMISTIC_TTL_MS).
    public static let ttlSeconds: Double = 15

    /// A request's answer: its job, or why it was refused.
    public enum Settled: Sendable, Equatable {
        case job(Int)
        case refused(error: String, detail: String?)
    }

    public func withPending(_ pending: PendingDownload) -> RequestOverlays {
        var next = self
        next.pending.insert(pending, at: 0)
        return next
    }

    /// slskd's answer recorded on one request.
    public func settlePending(_ key: String, _ outcome: Settled) -> RequestOverlays {
        var next = self
        next.pending = pending.map { (each: PendingDownload) -> PendingDownload in
            guard each.key == key else { return each }
            var settled = each
            switch outcome {
            case .job(let id):
                settled.jobId = id
            case .refused(let error, let detail):
                settled.error = error
                if let detail { settled.detail = detail }
            }
            return settled
        }
        return next
    }

    /// Clear done takes the refused requests with it; the ones still waiting stay.
    public func withoutRefused() -> RequestOverlays {
        var next = self
        next.pending = pending.filter { $0.isWaiting }
        return next
    }

    /// The jobs to draw: the cleared ones gone. A cancelling one stays - it really is running until slskd stops it.
    public func visibleJobs(_ jobs: [DownloadJob]) -> [DownloadJob] {
        cleared.isEmpty ? jobs : jobs.filter { !cleared.contains($0.id) }
    }

    /// The old badge's count: active jobs not being cancelled, failed ones being retried, requests still asking.
    public func activeCount(_ jobs: [DownloadJob]) -> Int {
        jobs.filter { (job: DownloadJob) -> Bool in
            job.isActive ? !cancelling.contains(job.id) : retrying.contains(job.id)
        }.count + pending.filter { $0.isWaiting }.count
    }

    /// The requests to draw: not yet a job in the list.
    public func visiblePending(_ jobs: [DownloadJob]) -> [PendingDownload] {
        guard !pending.isEmpty else { return [] }
        let ids = Set(jobs.map { $0.id })
        return pending.filter { (each: PendingDownload) -> Bool in each.jobId.map { !ids.contains($0) } ?? true }
    }

    /// Every overlay the freshly polled jobs now agree with, dropped: a cancel once its job stops being active or goes, a
    /// clear once it goes, a retry once it is moving again or gone, a request once its job is listed.
    public func reconcile(_ jobs: [DownloadJob]) -> RequestOverlays {
        var byId: [Int: DownloadJob] = [:]
        for job in jobs { byId[job.id] = job }
        var next = self
        next.cancelling = cancelling.filter { (id: Int) -> Bool in byId[id]?.isActive == true }
        next.cleared = cleared.filter { byId[$0] != nil }
        next.retrying = retrying.filter { (id: Int) -> Bool in
            guard let job = byId[id] else { return false }
            return !job.isActive
        }
        next.pending = pending.filter { (each: PendingDownload) -> Bool in
            each.jobId.map { byId[$0] == nil } ?? true
        }
        return next
    }

    /// The finished jobs Clear done would remove.
    public static func finishedIds(_ jobs: [DownloadJob]) -> [Int] {
        jobs.filter { !$0.isActive }.map { $0.id }
    }

    /// The jobs a Clear done takes now: the finished ones still drawn (`finishedIds` of `visibleJobs`). A clear's own
    /// rows, hidden while it waits for a poll to agree, aren't taken again, so a second Clear done that fails gives
    /// back only what it took - not the first clear's rows (slice 1's review, finding 5). The phone's own rule: the
    /// web's clearFinished (useDownloadJobs.ts) takes `finishedIds` of every job polled, and a second clear that fails
    /// there brings the first one's rows back until the next poll.
    public func toClear(_ polled: [DownloadJob]) -> [Int] {
        Self.finishedIds(visibleJobs(polled))
    }
}

// MARK: a Get whose answer never came - the phone's own (slice 2's review, finding 2)

/// deadwax puts no bound on an enqueue: it waits for the release's lock, then for slskd's enqueue, which answers only once
/// the peer is reached - and the web's fetch waits as long. The phone's request can't wait for ever, and when it gives
/// up the download may well have started: so the row isn't settled as refused. It stays "starting…" while the poll
/// looks for its job (`claimed`), and only after `unansweredSeconds` from the tap says it may have started
/// (`gaveUp`). The web has no such case - its request has no time limit - so these are held by hand (GetTests).
extension RequestOverlays {
    /// How long from its tap a Get whose answer never came is looked for, before its row says it may have started.
    public static let unansweredSeconds: Double = 600

    /// An enqueue's failure that leaves its outcome unknown - the phone stopped waiting, or a proxy between gave up (a
    /// 408 or 504) - rather than a refusal (`ErrorWords.kind` .timeout).
    public static func unanswered(_ error: any Error) -> Bool { ErrorWords.kind(of: error) == .timeout }

    /// The phone stopped waiting for `key`'s answer: still "starting…", now looked for in every poll.
    public func stoppedWaiting(_ key: String) -> RequestOverlays {
        var next = self
        next.pending = pending.map { (each: PendingDownload) -> PendingDownload in
            guard each.key == key, each.jobId == nil, each.error == nil else { return each }
            var waiting = each
            waiting.unanswered = true
            return waiting
        }
        return next
    }

    /// `unansweredSeconds` on, no job found for `key`: its row says it may have started (RequestWords.mayHaveStarted),
    /// under Needs attention, until Clear done - or its job shows after all.
    public func gaveUp(_ key: String) -> RequestOverlays {
        var next = self
        next.pending = pending.map { (each: PendingDownload) -> PendingDownload in
            guard each.key == key, each.jobId == nil, each.error == nil, each.unanswered == true else { return each }
            var given = each
            given.error = RequestWords.mayHaveStarted
            return given
        }
        return next
    }

    /// A request whose answer never came is still being looked for: the poll goes on for it, though nothing else is
    /// active.
    public var looksForAJob: Bool {
        pending.contains { $0.jobId == nil && $0.error == nil && $0.unanswered == true }
    }

    /// Requests whose answer never came, given their job once a poll lists one: a job not listed when the request was
    /// asked, for the same pressing - the one of its own folder from its own peer first, else any (with logins on, the
    /// download somebody else asked for, which deadwax joined). A job goes to one request; once given, `reconcile` drops
    /// the row for it, as it would for an answer.
    public func claimed(_ jobs: [DownloadJob]) -> RequestOverlays {
        guard pending.contains(where: { $0.jobId == nil && $0.unanswered == true }) else { return self }
        var taken = Set(pending.compactMap(\.jobId))
        var next = self
        next.pending = pending.map { (each: PendingDownload) -> PendingDownload in
            guard each.jobId == nil, each.unanswered == true, let release = each.releaseMbid, !release.isEmpty else {
                return each
            }
            let before = Set(each.listedBefore ?? [])
            let new = jobs.filter { (job: DownloadJob) -> Bool in
                !before.contains(job.id) && !taken.contains(job.id) && WebText.same(job.releaseMbid ?? "", release)
            }
            let own = new.first { (job: DownloadJob) -> Bool in
                WebText.same(job.directory ?? "", each.directory ?? "") && WebText.same(job.username ?? "", each.username)
            }
            guard let job = own ?? new.first else { return each }
            taken.insert(job.id)
            var found = each
            found.jobId = job.id
            found.error = nil
            return found
        }
        return next
    }
}

// MARK: speeds (speed.ts)

/// A real transfer rate from byte counts. slskd's `averageSpeed` is cumulative and never says what is happening now, so
/// the rate is measured here over a window of a second or more, the last one kept across quiet polls for 6 s.
public struct SpeedSamples: Sendable, Equatable {
    struct Sample: Sendable, Equatable {
        var bytes: Double
        var at: Double
        var rate: Double?
        var rateAt: Double
    }

    /// How long the last measured rate is still said once the counter goes quiet (wall time, not polls).
    public static let staleRateMs: Double = 6000
    /// The shortest window a rate is measured over - and so how often the figure changes.
    public static let updateMs: Double = 1000

    var samples: [Int: Sample] = [:]

    public init() {}

    /// Nothing measured.
    public var isEmpty: Bool { samples.isEmpty }

    public mutating func clear() { samples.removeAll() }

    /// `sampleSpeeds`: a fresh poll folded in (`now` in milliseconds on a clock that only goes forward), and the rates
    /// it supports, by job id. A job missing has no measurable rate yet; one no longer active starts afresh.
    public mutating func sample(_ jobs: [DownloadJob], now: Double) -> [Int: Double] {
        var speeds: [Int: Double] = [:]
        var live = Set<Int>()
        for job in jobs {
            guard job.isActive else {
                samples[job.id] = nil
                continue
            }
            live.insert(job.id)
            let bytes = job.bytesTransferred ?? 0
            guard let previous = samples[job.id] else {
                samples[job.id] = Sample(bytes: bytes, at: now, rate: nil, rateAt: now)
                continue
            }
            let elapsed = now - previous.at
            let delta = bytes - previous.bytes
            //? a negative delta: slskd restarted or requeued it - everything known about it dropped
            if elapsed <= 0 || delta < 0 {
                samples[job.id] = Sample(bytes: bytes, at: now, rate: nil, rateAt: now)
                continue
            }
            //? nothing new to publish yet: the window's anchor kept, so the next bytes are measured over all of it
            if elapsed < Self.updateMs || delta == 0 {
                if let rate = previous.rate, now - previous.rateAt <= Self.staleRateMs { speeds[job.id] = rate }
                continue
            }
            let rate = delta / (elapsed / 1000)
            samples[job.id] = Sample(bytes: bytes, at: now, rate: rate, rateAt: now)
            speeds[job.id] = rate
        }
        //? jobs gone from the answer altogether
        for id in Array(samples.keys) where !live.contains(id) { samples[id] = nil }
        return speeds
    }
}

// MARK: who asked (perPerson.ts, myLibrary.ts)

/// What the ✕'s question says, and its answer's button - and whether the cancel only LEAVES the download.
public struct CancelWords: Sendable, Equatable, Decodable {
    public let question: String
    public let action: String
    public let leaves: Bool

    public init(question: String, action: String, leaves: Bool) {
        self.question = question
        self.action = action
        self.leaves = leaves
    }
}

/// Downloads per person: who asked, what a cancel does, what a filing gave them. With logins off the server sends none of
/// `mine`, `shared`, `requested_by` or `library`, and every word is the one it always was.
public enum PerPerson {
    public static let sharedText = "Someone else asked for it too"
    public static let nobodyText = "Nobody is waiting for this any more"

    public static let cancelDefault = CancelWords(
        question: "Cancel this download? You'll lose your place in their queue.", action: "Cancel download", leaves: false)

    /// "a", "a and b", "a, b and c".
    static func listed(_ items: [String]) -> String {
        if items.count < 2 { return items.first ?? "" }
        return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
    }

    /// A cancel only withdraws your request: somebody else waits for it too, and you're no admin (an admin's rows carry
    /// `requested_by`).
    public static func leavesOnCancel(shared: Bool?, requestedBy: [String]?) -> Bool {
        shared == true && requestedBy == nil
    }

    /// Who asked, on an admin's row ("Asked by ethan", "Asked by you and ethan"); a user's shared row
    /// `sharedText`; a row nobody waits for `nobodyText`; else nil.
    public static func askedByText(mine: Bool?, shared: Bool?, requestedBy: [String]?) -> String? {
        guard let others = requestedBy else { return shared == true ? sharedText : nil }
        if others.isEmpty { return mine == true ? nil : nobodyText }
        return "Asked by \(listed(mine == true ? ["you"] + others : others))"
    }

    /// The ✕'s question for a row.
    public static func cancelWords(mine: Bool?, shared: Bool?, requestedBy: [String]?) -> CancelWords {
        guard shared == true else { return cancelDefault }
        if leavesOnCancel(shared: shared, requestedBy: requestedBy) {
            return CancelWords(question: "Leave this download? Someone else asked for it too, so it carries on for them.",
                               action: "Leave it", leaves: true)
        }
        let names = listed(requestedBy ?? [])
        return CancelWords(
            question: "Cancel this download for everyone? \(names.isEmpty ? "Someone else" : names) asked for it\(mine == true ? " too" : "").",
            action: "Cancel for everyone", leaves: false)
    }

    /// "2 files couldn't be added", from a partly filed download's words; "some files couldn't be added" without a count.
    public static func partlyWords(_ error: String?) -> String {
        let text = JSText.trim(error ?? "")
        let digits = text.unicodeScalars.prefix { $0.value >= 0x30 && $0.value <= 0x39 }
        guard !digits.isEmpty,
              String(text.unicodeScalars.dropFirst(digits.count)).utf16.starts(with: " file(s) failed to organize".utf16)
        else { return "some files couldn't be added" }
        let number = Double(String(String.UnicodeScalarView(digits))) ?? 0
        let n = RequestWords.webNumber(number)
        return "\(n) \(number == 1 ? "file couldn't" : "files couldn't") be added"
    }

    /// What a finished download's filing gave those who asked (logins on) - nil for the words it always had.
    public static func grantWords(_ job: DownloadJob) -> (text: String, tone: RequestTone, detail: String?)? {
        let whose = job.mine == false ? "their" : "your"
        if job.outcome == "filed" && job.library == "added" {
            return (job.mine == false ? "In their library" : "In your library", .plain, nil)
        }
        if job.outcome == "already_there" {
            if job.library == "added" { return ("Already in the collection, added to \(whose) library", .plain, nil) }
            if job.library == "flagged" {
                return ("Not added - the collection's copy may be another pressing, so an admin has been asked to check it", .warning, nil)
            }
            if job.library == "looked" {
                return ("Not added - the collection's copy may be another pressing; an admin has checked it", .warning, nil)
            }
        }
        if job.outcome == "partly_filed" && job.library == "incomplete" {
            let error = job.error ?? ""
            return ("In \(whose) library - \(partlyWords(job.error))", .warning, error.isEmpty ? nil : error)
        }
        return nil
    }
}
