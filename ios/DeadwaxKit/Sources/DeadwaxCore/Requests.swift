import Foundation

// The Requests tab (Phase 6, slice 1 - notes/ios-specs/phase6-get-requests.md 2.1): every download you asked for, under
// the web's four headings with the web's words - ui/src/lib/requestsView.ts, ported to the character and held to it by
// Tests/DeadwaxCoreTests/Fixtures/requests/requests-vectors.json (ios/scripts/export-requests-vectors.cjs, checked
// current by ui/test/iosrequests.sim.cjs). The overlays, the speeds and who asked are RequestOverlays.swift's; what the
// app watches, the poll and the Done rows' looks are RequestsWatch.swift's.

// MARK: what /download/jobs answers

/// A row of `GET /deadwax/download/jobs` (src/routes/download.py `jobs`): a download, as deadwax keeps it, with slskd's
/// live progress merged in. Only the id and the status are always there; the rest is read when sent (an older row, a
/// field sent only with logins on). Never `speed` for a rate: it is slskd's cumulative average (SpeedSamples).
public struct DownloadJob: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let artist: String?
    public let album: String?
    public let year: String?
    public let username: String?
    public let directory: String?
    /// queued, downloading, organizing, organized, complete, failed, cancelled - kept as sent, so one deadwax adds later
    /// is drawn as the web draws it (under Done).
    public let status: String
    public let error: String?
    public let createdAt: String?
    /// When its status last changed (ISO 8601, UTC) - a Done row's "12 minutes ago".
    public let updatedAt: String?
    /// The pressing it is for: its cover, and the album a Done row opens.
    public let releaseMbid: String?
    public let releaseGroupMbid: String?
    /// The edition set by hand, else MusicBrainz's disambiguation; nil for none.
    public let edition: String?
    /// How it ended (src/poller.py job_outcome): filed, already_there, partly_filed, interrupted, failed, not_filed - nil
    /// while it is going.
    public let outcome: String?
    /// Its place in the peer's queue - only for a queued download slskd knows of.
    public let queuePosition: Int?
    /// 0-100, over the files asked for.
    public let progress: Double?
    public let state: String?
    public let speed: Double?
    public let bytesTransferred: Double?
    public let filesDone: Int?
    public let filesTotal: Int?
    /// Files stopped for good without arriving.
    public let filesFailed: Int?
    public let failureReason: String?
    public let matched: Bool?
    /// How many other sources Another source could still move it to - sent only where a retry can move it.
    public let alternativesLeft: Int?
    /// Which try this is: 1 for the source first picked.
    public let attempt: Int?
    /// (logins on) The asker is waiting for it.
    public let mine: Bool?
    /// (logins on) Somebody else is waiting for it too.
    public let shared: Bool?
    /// (logins on, an admin's rows) The others waiting for it, in the order they asked.
    public let requestedBy: [String]?
    /// (logins on) What its filing gave those who asked: added, incomplete, flagged, looked.
    public let library: String?

    enum CodingKeys: String, CodingKey {
        case id, artist, album, year, username, directory, status, error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case edition, outcome
        case queuePosition = "queue_position"
        case progress, state, speed
        case bytesTransferred = "bytes_transferred"
        case filesDone = "files_done"
        case filesTotal = "files_total"
        case filesFailed = "files_failed"
        case failureReason = "failure_reason"
        case matched
        case alternativesLeft = "alternatives_left"
        case attempt, mine, shared
        case requestedBy = "requested_by"
        case library
    }

    public init(id: Int, status: String, artist: String? = nil, album: String? = nil, year: String? = nil,
                username: String? = nil, directory: String? = nil, error: String? = nil, createdAt: String? = nil,
                updatedAt: String? = nil, releaseMbid: String? = nil, releaseGroupMbid: String? = nil,
                edition: String? = nil, outcome: String? = nil, queuePosition: Int? = nil, progress: Double? = nil,
                state: String? = nil, speed: Double? = nil, bytesTransferred: Double? = nil, filesDone: Int? = nil,
                filesTotal: Int? = nil, filesFailed: Int? = nil, failureReason: String? = nil, matched: Bool? = nil,
                alternativesLeft: Int? = nil, attempt: Int? = nil, mine: Bool? = nil, shared: Bool? = nil,
                requestedBy: [String]? = nil, library: String? = nil) {
        self.id = id
        self.status = status
        self.artist = artist
        self.album = album
        self.year = year
        self.username = username
        self.directory = directory
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.edition = edition
        self.outcome = outcome
        self.queuePosition = queuePosition
        self.progress = progress
        self.state = state
        self.speed = speed
        self.bytesTransferred = bytesTransferred
        self.filesDone = filesDone
        self.filesTotal = filesTotal
        self.filesFailed = filesFailed
        self.failureReason = failureReason
        self.matched = matched
        self.alternativesLeft = alternativesLeft
        self.attempt = attempt
        self.mine = mine
        self.shared = shared
        self.requestedBy = requestedBy
        self.library = library
    }

    /// Read leniently but for the id and the status: a field of a shape this app doesn't know is none, so one odd value
    /// from slskd never takes the whole list away - the web, in JavaScript, would draw the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        artist = c.looseField(String.self, .artist)
        album = c.looseField(String.self, .album)
        year = c.looseField(String.self, .year)
        username = c.looseField(String.self, .username)
        directory = c.looseField(String.self, .directory)
        error = c.looseField(String.self, .error)
        createdAt = c.looseField(String.self, .createdAt)
        updatedAt = c.looseField(String.self, .updatedAt)
        releaseMbid = c.looseField(String.self, .releaseMbid)
        releaseGroupMbid = c.looseField(String.self, .releaseGroupMbid)
        edition = c.looseField(String.self, .edition)
        outcome = c.looseField(String.self, .outcome)
        queuePosition = c.looseField(Int.self, .queuePosition)
        progress = c.looseField(Double.self, .progress)
        state = c.looseField(String.self, .state)
        speed = c.looseField(Double.self, .speed)
        bytesTransferred = c.looseField(Double.self, .bytesTransferred)
        filesDone = c.looseField(Int.self, .filesDone)
        filesTotal = c.looseField(Int.self, .filesTotal)
        filesFailed = c.looseField(Int.self, .filesFailed)
        failureReason = c.looseField(String.self, .failureReason)
        matched = c.looseField(Bool.self, .matched)
        alternativesLeft = c.looseField(Int.self, .alternativesLeft)
        attempt = c.looseField(Int.self, .attempt)
        mine = c.looseField(Bool.self, .mine)
        shared = c.looseField(Bool.self, .shared)
        requestedBy = c.looseList(String.self, .requestedBy)
        library = c.looseField(String.self, .library)
    }

    /// Work is outstanding (lib/jobs.ts ACTIVE_STATUSES): queued, downloading or being filed.
    public var isActive: Bool { DownloadJob.activeStatuses.contains(status) }

    public static let activeStatuses: Set<String> = ["queued", "downloading", "organizing"]
}

/// `GET /deadwax/download/jobs`: the rows, and whether deadwax can keep track of downloads at all (false: its database
/// can't be written - downloads still arrive, untracked).
public struct JobsAnswer: Decodable, Sendable, Equatable {
    public let jobs: [DownloadJob]
    public let trackingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case jobs
        case trackingEnabled = "tracking_enabled"
    }

    public init(jobs: [DownloadJob], trackingEnabled: Bool = true) {
        self.jobs = jobs
        self.trackingEnabled = trackingEnabled
    }
}

/// What a cancel answers: `left` - only your request withdrawn (a download somebody else waits for too), or the
/// download itself cancelled.
public struct CancelAnswer: Decodable, Sendable, Equatable {
    public let left: Bool?
    public let cancelled: Int?
    public let partialsRemoved: Int?
    public let partialsProblem: String?

    enum CodingKeys: String, CodingKey {
        case left, cancelled
        case partialsRemoved = "partials_removed"
        case partialsProblem = "partials_problem"
    }
}

/// Another source's answer (`/retry`): `moved`, or why not - 200 either way.
public struct RetryAnswer: Decodable, Sendable, Equatable {
    public let moved: Bool
    public let problem: String?
    public let left: Int?
}

/// Same source again's answer (`/retry_same`): `retried`, or why not - 200 either way.
public struct RetrySameAnswer: Decodable, Sendable, Equatable {
    public let retried: Bool
    public let problem: String?
}

/// Clear done's answer: how many left the asker's list.
public struct ClearAnswer: Decodable, Sendable, Equatable {
    public let removed: Int?
}

// MARK: the board

/// The four headings, in the board's order.
public enum RequestSection: String, Sendable, CaseIterable, Hashable {
    case downloading, waiting, attention, done
}

/// A line in the ordinary grey, the warning amber, or the failure red.
public enum RequestTone: String, Sendable, Equatable {
    case plain, warning, danger
}

/// Why a retry didn't start: deadwax's own words, or a sentence with the error's own beside it.
public enum RetryProblem: Sendable, Equatable {
    case words(String)
    case said(text: String, detail: String?)
}

/// A download as the board draws it - every field the web's RequestRow has, but `cover`: the release's id, for the
/// Cover Art Archive relay (the web makes the Archive's own address of it, `jobCoverUrl`).
public struct RequestRow: Sendable, Equatable, Identifiable {
    public enum Cancel: String, Sendable, Equatable { case ready, cancelling }
    public struct NextPeer: Sendable, Equatable {
        public var left: Int
        public var primary: Bool
        public var label: String
    }
    public struct AskAgain: Sendable, Equatable {
        public var label: String
    }

    /// Stable across polls: "job-<id>", or a request's own key.
    public var key: String

    /// A job's row's key: "job-<id>" (requestsView.ts jobRow's).
    public static func key(job id: Int) -> String { "job-\(id)" }
    /// The job, for cancel and retry; nil for a request not yet a job.
    public var jobId: Int?
    public var section: RequestSection
    /// The album and its edition: "Dummy · 2014 vinyl".
    public var title: String
    public var artist: String
    /// The release whose front is the row's cover - nil for the plain tile.
    public var cover: String?
    public var line: String
    public var lineTone: RequestTone
    public var reason: String?
    public var reasonTell: Bool
    public var reasonDetail: String?
    public var problem: String?
    public var problemDetail: String?
    /// The bar, 0-100.
    public var progress: Double
    public var data: String?
    public var brief: String
    public var cancel: Cancel?
    public var nextPeer: NextPeer?
    public var askAgain: AskAgain?
    public var busy: Bool
    public var dimmed: Bool
    public var arriving: Bool
    public var album: String
    public var release: String?
    public var plays: Bool
    public var askedBy: String?
    public var cancelWords: CancelWords

    public var id: String { key }

    init(key: String, jobId: Int?, section: RequestSection, title: String, artist: String, album: String = "") {
        self.key = key
        self.jobId = jobId
        self.section = section
        self.title = title
        self.artist = artist
        cover = nil
        line = ""
        lineTone = .plain
        reason = nil
        reasonTell = false
        reasonDetail = nil
        problem = nil
        problemDetail = nil
        progress = 0
        data = nil
        brief = ""
        cancel = nil
        nextPeer = nil
        askAgain = nil
        busy = false
        dimmed = false
        arriving = false
        self.album = album
        release = nil
        plays = false
        askedBy = nil
        cancelWords = PerPerson.cancelDefault
    }
}

/// What the board is made from: the polled jobs (the cleared ones left out - RequestOverlays.visibleJobs), the
/// requests not yet jobs (`visiblePending`), the measured speeds and the overlays' sets - exactly what useDownloadJobs
/// hands the web's board.
public struct RequestsInput: Sendable, Equatable {
    public var jobs: [DownloadJob]
    public var pending: [PendingDownload]
    public var speeds: [Int: Double]
    public var cancelling: Set<Int>
    public var retrying: Set<Int>
    public var retryingSame: Set<Int>
    public var retryProblems: [Int: RetryProblem]
    /// Logins on with libraries of their own: what the server calls "your library" is the collection.
    public var personal: Bool

    public init(jobs: [DownloadJob] = [], pending: [PendingDownload] = [], speeds: [Int: Double] = [:],
                cancelling: Set<Int> = [], retrying: Set<Int> = [], retryingSame: Set<Int> = [],
                retryProblems: [Int: RetryProblem] = [:], personal: Bool = false) {
        self.jobs = jobs
        self.pending = pending
        self.speeds = speeds
        self.cancelling = cancelling
        self.retrying = retrying
        self.retryingSame = retryingSame
        self.retryProblems = retryProblems
        self.personal = personal
    }
}

/// The board: every download under its heading, what the badge counts, and whether there is anything to clear.
public struct RequestsView: Sendable, Equatable {
    public var sections: [RequestSection: [RequestRow]]
    /// What the badge counts, in the board's order.
    public var arriving: [RequestRow]
    /// Clear done has something to clear: a finished, failed or cancelled job, or a refused request.
    public var clearable: Bool
    /// Nothing at all to show.
    public var empty: Bool

    public static let nothing = RequestsView(sections: [:], arriving: [], clearable: false, empty: true)

    /// A heading's rows (none when it has none).
    public func rows(_ section: RequestSection) -> [RequestRow] { sections[section] ?? [] }

    /// `requestsView`: every download, under its heading, with its words. `now` (milliseconds since 1970) is for
    /// "12 minutes ago".
    public static func make(_ input: RequestsInput, now: Int64) -> RequestsView {
        let jobs = input.jobs
        var byId: [Int: DownloadJob] = [:]
        for job in jobs { byId[job.id] = job }
        let rows = jobs.map { (job: DownloadJob) -> RequestRow in RequestWords.jobRow(job, input, now: now) }
        let pending = input.pending.map { (each: PendingDownload) -> RequestRow in
            RequestWords.pendingRow(each, personal: input.personal)
        }
        func of(_ section: RequestSection, _ list: [RequestRow]) -> [RequestRow] {
            list.filter { $0.section == section }
        }
        let done = of(.done, rows).sorted { (a: RequestRow, b: RequestRow) -> Bool in
            let jobA = a.jobId.flatMap { byId[$0] }
            let jobB = b.jobId.flatMap { byId[$0] }
            let atA = RequestWords.updatedAt(jobA), atB = RequestWords.updatedAt(jobB)
            if atA != atB { return atA > atB }
            return (jobA?.id ?? 0) > (jobB?.id ?? 0)
        }
        var attention = of(.attention, pending) + of(.attention, rows)
        //? one solid purple button on the screen: the first Another source, and the rest tinted
        if let first = attention.firstIndex(where: { $0.nextPeer != nil }) {
            attention[first].nextPeer?.primary = true
        }
        let downloading = of(.downloading, rows)
        let waiting = of(.waiting, pending) + of(.waiting, rows)
        let arriving = (downloading + waiting + attention).filter { $0.arriving }
        return RequestsView(
            sections: [.downloading: downloading, .waiting: waiting, .attention: attention, .done: done],
            arriving: arriving,
            clearable: jobs.contains { !$0.isActive } || input.pending.contains { $0.error != nil },
            empty: jobs.isEmpty && input.pending.isEmpty)
    }
}

// MARK: the words

/// Every word the board says, and the small rules that say them - requestsView.ts's, Requests.tsx's and JobCard.tsx's,
/// the hook's refusals (useDownloadJobs.ts) and You's Confirm before cancelling.
public enum RequestWords {
    public static let tab = "Requests"
    public static let titles: [RequestSection: String] = [
        .downloading: "Downloading", .waiting: "Waiting", .attention: "Needs attention", .done: "Done",
    ]
    public static func title(_ section: RequestSection) -> String { titles[section] ?? "" }

    /// How many cards Home's Arriving shows - kept with the web's numbers; the phone has no Home.
    public static let arrivingMax = 3

    public static let clearDone = "Clear done"
    public static let nothingYet = "Nothing requested yet"
    /// Requests with nothing in it, for someone who can Get...
    /// (The Mac app, slice 5) "click Get" on a Mac.
    public static func empty(_ device: Device) -> String {
        "Albums you get show here while they download, and once they've arrived - find one in Search and \(device == .mac ? "click" : "tap") Get."
    }
    /// ...and for anyone else, who can only join (Requests.tsx REQUESTS_EMPTY_JOIN).
    public static let emptyJoin = getOff
    /// The empty board's line.
    public static func emptyLine(gets: Bool, device: Device) -> String { gets ? empty(device) : emptyJoin }

    /// Over a failed look - the rows below as the last answer had them.
    public static let unreached = "Can't update your requests right now"
    public static let keepsAsking = "It keeps asking while this tab is open."
    public static let keepsAskingBelow = "It keeps asking while this tab is open; what's below is from the last answer."
    /// The failed look's last line, by whether there are rows below it.
    public static func keepsAsking(empty: Bool) -> String { empty ? keepsAsking : keepsAskingBelow }

    /// deadwax can't keep track of downloads: the heading, and what anyone but whoever runs deadwax reads under it.
    public static let untracked = "Downloads aren't being kept track of"
    public static let untrackedText = "Requests can't be shown right now: deadwax can't keep track of downloads. \(ErrorWords.tell)"
    /// ...and what whoever runs deadwax reads (DB_PATH in the web's monospace).
    public static let untrackedRuns = "deadwax can't write its database. Downloads still arrive in slskd's folder, but they can't be listed here or added to your library. Check DB_PATH."

    /// (the phone's own, phase6-get-requests.md question 4) deadwax out of reach: nothing of the last answer drawn.
    public static let offline = "Requests show once deadwax is back."

    // a Done row that can't open (Requests.tsx)
    public static let notInNavidrome = "Not ready to play yet - it may still be scanning."
    public static let notInStore = "Can't find this album to open it - it may have moved, or isn't matched to a pressing."
    /// (Slice 5) "click to try again" on a Mac.
    public static func notLookedUp(_ device: Device) -> String { "Couldn't open it - \(device == .mac ? "click" : "tap") to try again." }
    public static let cantOpenUnset = "Can't open this album yet - the music server isn't set up."
    public static let cantOpenDown = "Can't open this album right now - the music server can't be reached. Try again in a minute."
    public static let cantOpenOffline = "Can't open this album right now - can't connect to deadwax. Check your connection, then try again."

    /// Why Navidrome can't be asked for an album just now (App.tsx `navidromeProblem`): unknown (nil) until a check is
    /// in, nil when it answers.
    public static func cantOpen(_ checked: NavidromeGate.Checked?) -> String? {
        guard let checked else { return nil }
        if !checked.status.configured { return cantOpenUnset }
        if checked.offline { return cantOpenOffline }
        if !checked.status.ok { return cantOpenDown }
        return nil
    }

    /// Why a Done row's album couldn't be opened, from the bridge's answer (Requests.tsx `noteFor`): the music server's
    /// problem first, else a folder held but Navidrome not having it yet, else no folder tagged with the release.
    public static func note(present: Bool, navidromeProblem: String?) -> String {
        navidromeProblem ?? (present ? notInNavidrome : notInStore)
    }

    // the cards (JobCard.tsx)
    public static let keepIt = "Keep it"
    /// The ✕'s name: "Leave Dummy" for a cancel that only withdraws your request, else "Cancel Dummy".
    public static func cancelLabel(_ row: RequestRow) -> String { "\(row.cancelWords.leaves ? "Leave" : "Cancel") \(row.title)" }
    /// A Done row's ▶.
    public static func playLabel(_ row: RequestRow) -> String { "Play \(row.title)" }
    /// Without Get albums, in a card that would have had Another source or Same source again.
    public static let getOff = "Getting albums is off for you - ask an admin."

    // the hook's (useDownloadJobs.ts): a retry refused without words, a request that broke
    public static let sameRefused = "They refused - try another source."
    public static let nextRefused = "No other source would send it."
    public static let retryBroke = "That didn't work."
    public static let enqueueBroke = "The download couldn't be started."
    /// THE PHONE'S OWN (slice 2's review, finding 2): a Get whose answer never came, given up on after
    /// RequestOverlays.unansweredSeconds - its line's state, and why, in place of a refusal's. deadwax puts no bound on
    /// an enqueue, so it may well have started.
    public static let noAnswer = "no answer"
    public static let mayHaveStarted =
        "deadwax didn't answer in time, so this may have started anyway. If it doesn't appear here soon, get it again."

    // You > Getting albums (ConfirmCancelChoice.tsx, You.tsx)
    public static let gettingAlbums = "Getting albums"
    public static let confirmCancel = "Confirm before cancelling"
    public static let confirmCancelNote = "The \u{2715} on a download in Requests asks first. Kept on this device."

    /// What a retry that couldn't start is said with when its words aren't fit for a listener's line.
    public static let retryFailed = "The download couldn't be started."

    /// The retry routes' own words (src/poller.py) that name slskd or a peer, in a listener's.
    public static let retryWords: [String: String] = [
        "slskd is still stopping the last attempt - try again in a moment": "The last try is still stopping - try again in a moment.",
        "no other peers to try - search again for more": "No other source to try - Get it again to search for more.",
        "this download has already moved on - it's been retried or restarted meanwhile": "It's already been tried again meanwhile.",
        "this download has been cleared from the list - search again to download it": "It's been cleared from the list - Get it again to download it.",
    ]

    /// The retry routes' words that carry a name or a path, by how they start, in a listener's.
    static func retryWordsStarting(_ problem: String, personal: Bool) -> String? {
        if problem.utf16.starts(with: "already downloading from ".utf16) { return "It's already downloading." }
        if problem.utf16.starts(with: "already downloaded from ".utf16) { return "It's already downloaded, and being added now." }
        if problem.utf16.starts(with: "already in your library".utf16) {
            return personal ? "It's already in the collection." : "It's already in your library."
        }
        return nil
    }

    public static func anotherSource(_ left: Int) -> String { "Another source \u{00B7} \(left) left" }
    public static let tryingAnother = "Trying another source\u{2026}"
    public static let sameSource = "Same source again"
    public static let tryingSame = "Trying again\u{2026}"

    /// A retry's problem as the row says it, and its own words where they weren't fit to be.
    public static func retryProblemWords(_ problem: RetryProblem?, personal: Bool = false) -> (text: String?, detail: String?) {
        guard let problem else { return (nil, nil) }
        switch problem {
        case .said(let text, let detail):
            return (text, detail)
        case .words(let words):
            if let known = retryWords[words] ?? retryWordsStarting(words, personal: personal) { return (known, words) }
            let safe = ErrorWords.safeWords(words, fallback: retryFailed)
            //? fit as they are: the retry route's own words (and the hook's), kept as written
            return safe.detail == nil ? (words, nil) : (safe.text, safe.detail)
        }
    }

    /// "12 minutes ago", from an ISO timestamp; "" when it can't be read. Never in the future.
    public static func age(_ iso: String?, now: Int64) -> String {
        guard let iso, !iso.isEmpty, let then = AlbumTime.ms(iso) else { return "" }
        let seconds = Swift.max(0, JSMath.round(Double(now - then) / 1000))
        if seconds < 60 { return "just now" }
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    /// How a finished download ended, in words, from the server's `outcome` - `tell`: only whoever runs deadwax can put
    /// it right; `detail`: the job's own words, for them.
    public struct Outcome: Sendable, Equatable {
        public let text: String
        public let tone: RequestTone
        public let tell: Bool
        public let detail: String?
    }

    /// `outcomeWords`.
    public static func outcome(_ job: DownloadJob) -> Outcome {
        //? (logins on) what its filing gave those who asked, where the server says
        if let granted = PerPerson.grantWords(job) {
            return Outcome(text: granted.text, tone: granted.tone, tell: false, detail: granted.detail)
        }
        let error = job.error ?? ""
        switch job.outcome {
        case "filed":
            return Outcome(text: "In your library", tone: .plain, tell: false, detail: nil)
        case "already_there":
            return Outcome(text: "You already had it", tone: .plain, tell: false, detail: nil)
        case "partly_filed":
            return Outcome(text: "In your library - \(PerPerson.partlyWords(job.error))", tone: .warning, tell: false,
                           detail: error.isEmpty ? nil : error)
        case "interrupted":
            return Outcome(text: "Stopped while being added to your library", tone: .warning, tell: true,
                           detail: error.isEmpty ? nil : error)
        default:
            if error.isEmpty {
                return Outcome(text: "Downloaded, but not added to your library", tone: .warning, tell: true, detail: nil)
            }
            let why = ErrorWords.jobErrorWords(job.error)
            return Outcome(text: why.text, tone: .warning, tell: why.tell, detail: why.detail)
        }
    }

    /// The badge's number: none at zero, and "99+" past 99.
    public static func badgeText(_ count: Int) -> String {
        guard count > 0 else { return "" }
        return count > 99 ? "99+" : String(count)
    }

    /// What VoiceOver hears for the Requests tab with its badge: "Requests, 2 arriving".
    public static func badgeLabel(_ tab: String, _ count: Int) -> String {
        count > 0 ? "\(tab), \(count) arriving" : tab
    }

    /// "2nd", "3rd", "11th", "21st".
    public static func ordinal(_ count: Int) -> String {
        let tens = count % 100
        let suffix: String
        if tens >= 11 && tens <= 13 { suffix = "th" }
        else if count % 10 == 1 { suffix = "st" }
        else if count % 10 == 2 { suffix = "nd" }
        else if count % 10 == 3 { suffix = "rd" }
        else { suffix = "th" }
        return "\(count)\(suffix)"
    }

    /// A rate as the web writes it (lib/format.ts formatSpeed): "512 KB/s", "1.8 MB/s"; "unknown" for none.
    public static func speed(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond != 0, !bytesPerSecond.isNaN else { return "unknown" }
        let kb = bytesPerSecond / 1024
        if kb < 1024 { return "\(webNumber(JSMath.round(kb))) KB/s" }
        return "\(jsFixed(kb / 1024, 1)) MB/s"
    }

    /// A whole number as JavaScript writes it in a template.
    static func webNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return WebText.number(value)
    }

    /// Which heading a job goes under.
    public static func section(_ job: DownloadJob) -> RequestSection {
        if job.status == "downloading" || job.status == "organizing" { return .downloading }
        //? bytes moving before the poller has moved it on from queued
        if job.status == "queued" { return (job.progress ?? 0) > 0 ? .downloading : .waiting }
        if retryable.contains(job.status) { return .attention }
        //? (logins on) downloaded, and nothing of it could be filed: it needs a look
        if job.outcome == "not_filed" { return .attention }
        return .done
    }

    static let retryable: Set<String> = ["failed", "cancelled"]
    /// The endings whose album is in the library: a Done row of one opens it...
    static let inTheLibrary: Set<String> = ["filed", "partly_filed", "already_there"]
    /// ...and the ones this download filed, which its ▶ plays.
    static let filed: Set<String> = ["filed", "partly_filed"]

    /// JS's `||` on a string: an empty one is none.
    static func said(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    static func who(_ artist: String, _ username: String?, _ more: String?...) -> String {
        ([artist, said(username).map { "from \($0)" } ?? ""] + more.map { $0 ?? "" })
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }

    static func tryText(_ job: DownloadJob) -> String? {
        guard let attempt = job.attempt, attempt > 1 else { return nil }
        return "\(ordinal(attempt)) try"
    }

    static func titleOf(_ album: String?, _ edition: String?) -> String {
        "\(said(album) ?? "Unknown album")\(said(edition).map { " \u{00B7} \($0)" } ?? "")"
    }

    static func files(_ done: Int, _ total: Int) -> String {
        "\(done) of \(total) \(total == 1 ? "file" : "files")"
    }

    static func updatedAt(_ job: DownloadJob?) -> Int64 {
        AlbumTime.ms(job?.updatedAt) ?? 0
    }

    static func jobRow(_ job: DownloadJob, _ input: RequestsInput, now: Int64) -> RequestRow {
        let section = self.section(job)
        var row = RequestRow(key: RequestRow.key(job: job.id), jobId: job.id, section: section,
                             title: titleOf(job.album, job.edition), artist: job.artist ?? "", album: job.album ?? "")
        row.cover = said(job.releaseMbid)
        row.askedBy = PerPerson.askedByText(mine: job.mine, shared: job.shared, requestedBy: job.requestedBy)
        row.cancelWords = PerPerson.cancelWords(mine: job.mine, shared: job.shared, requestedBy: job.requestedBy)
        let cancelling = input.cancelling.contains(job.id)
        //? a cancel that only withdraws your request says so while it is out
        let going = row.cancelWords.leaves ? "leaving\u{2026}" : "cancelling\u{2026}"
        let done = job.filesDone ?? 0
        let total = job.filesTotal ?? 0

        switch section {
        case .downloading:
            let organizing = job.status == "organizing"
            let speed = input.speeds[job.id]
            row.line = who(row.artist, job.username, tryText(job))
            row.progress = organizing ? 100 : JSMath.min(100, JSMath.max(0, job.progress ?? 0))
            if cancelling {
                row.data = going
            } else if organizing {
                row.data = "\(files(done, total)) \u{00B7} adding to your library\u{2026}"
            } else {
                let failed = (job.filesFailed ?? 0) != 0 ? "\(job.filesFailed ?? 0) failed" : nil
                let rate = (speed ?? 0) != 0 ? self.speed(speed) : nil
                row.data = [files(done, total), failed, rate].compactMap { $0 }.joined(separator: " \u{00B7} ")
            }
            row.brief = cancelling ? going : organizing ? "adding\u{2026}" : "\(done) of \(total)"
            //? nothing in slskd is left to cancel once it is being filed, and the filing can't be stopped
            row.cancel = organizing ? nil : cancelling ? .cancelling : .ready
            row.dimmed = cancelling
            row.arriving = !cancelling
        case .waiting:
            let place = job.queuePosition
            let state = cancelling ? going : place.map { "\(ordinal($0)) in their queue" } ?? "starting"
            //? files the peer already refused while the rest wait in its queue, said now, in amber
            let failed = !cancelling && (job.filesFailed ?? 0) != 0 ? "\(job.filesFailed ?? 0) failed" : nil
            row.line = who(row.artist, job.username, state, failed, tryText(job))
            if failed != nil { row.lineTone = .warning }
            row.brief = cancelling ? going : place.map { "\(ordinal($0)) in line" } ?? "starting"
            row.cancel = cancelling ? .cancelling : .ready
            row.dimmed = cancelling
            row.arriving = !cancelling
        case .attention:
            let retrying = input.retrying.contains(job.id)
            let same = retrying && input.retryingSame.contains(job.id)
            let left = job.alternativesLeft ?? 0
            row.line = who(row.artist, job.username, tryText(job))
            let why = ErrorWords.jobErrorWords(job.error)
            row.reason = said(why.text) ?? (job.status == "cancelled" ? "Cancelled" : "It stopped without saying why")
            row.reasonTell = why.tell
            row.reasonDetail = why.detail
            let retried = retryProblemWords(input.retryProblems[job.id], personal: input.personal)
            row.problem = retried.text
            row.problemDetail = retried.detail
            row.nextPeer = left > 0
                ? RequestRow.NextPeer(left: left, primary: false, label: retrying && !same ? tryingAnother : anotherSource(left))
                : nil
            //? the same peer again is for a download that stopped - not one filing couldn't use (not_filed)
            row.askAgain = job.outcome == "not_filed" ? nil : RequestRow.AskAgain(label: same ? tryingSame : sameSource)
            row.busy = retrying
            row.brief = retrying ? "retrying\u{2026}" : ""
            row.arriving = retrying
        case .done:
            let outcome = self.outcome(job)
            let age = self.age(job.updatedAt, now: now)
            row.line = age.isEmpty ? outcome.text : "\(outcome.text) \u{00B7} \(age)"
            row.lineTone = outcome.tone
            row.reasonTell = outcome.tell
            row.reasonDetail = outcome.detail
            row.progress = 100
            //? the album it brought, where the library has it: the row opens it, and plays what was filed
            let release = JSText.trim(job.releaseMbid ?? "")
            if !release.isEmpty, let ending = job.outcome, inTheLibrary.contains(ending) {
                row.release = release
                row.plays = filed.contains(ending)
            }
        }
        return row
    }

    static func pendingRow(_ pending: PendingDownload, personal: Bool) -> RequestRow {
        let refused = pending.error != nil
        var row = RequestRow(key: pending.key, jobId: nil, section: refused ? .attention : .waiting,
                             title: titleOf(pending.album, nil), artist: pending.artist, album: pending.album)
        if pending.mayHaveStarted {
            //? the phone's own: no answer, not a refusal - so not said as one (RequestOverlays.gaveUp)
            row.line = who(row.artist, pending.username, RequestWords.noAnswer)
            row.reason = RequestWords.mayHaveStarted
            return row
        }
        if let error = pending.error {
            row.line = who(row.artist, pending.username, "didn't start")
            //? /enqueue's 409 is already_have's words, said as a retry's refusal is, the route's own kept
            let known = error.isEmpty ? nil : retryWordsStarting(error, personal: personal)
            row.reason = known ?? (said(error) ?? retryFailed)
            row.reasonDetail = known != nil ? error : pending.detail
            return row
        }
        row.line = who(row.artist, pending.username, "starting\u{2026}")
        row.brief = "starting\u{2026}"
        row.arriving = true
        return row
    }
}
