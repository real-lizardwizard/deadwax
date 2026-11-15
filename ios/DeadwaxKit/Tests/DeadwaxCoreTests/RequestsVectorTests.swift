import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/requests/requests-vectors.json: what the web's TypeScript (lib/requestsView.ts, lib/downloadOverlay.ts,
/// lib/speed.ts, lib/perPerson.ts, lib/myLibrary.ts's grantWords and partlyWords, lib/format.ts's formatSpeed) answers for
/// Phase 6's slice 1, with the words its components and the hook build inline read out of their source - written by
/// ios/scripts/export-requests-vectors.cjs, never by hand. The jobs in it are decoded by the real model (DownloadJob),
/// as /download/jobs sends them.
enum RequestsVectors {
    struct Vectors: Decodable {
        let numbers: Numbers
        let words: Words
        let ordinals: [Ordinal]
        let badges: [Badge]
        let speeds: [Speed]
        let ages: [Age]
        let partly: [Partly]
        let outcomes: [OutcomeCase]
        let problems: [ProblemCase]
        let people: [PersonCase]
        let sections: [SectionCase]
        let boards: [Board]
        let changes: [ChangesRun]
        let overlays: [OverlayCase]
        let speedTraces: [SpeedTrace]
        let watching: WatchingCases
        let looks: [LooksCase]
        let filed: [FiledRun]
    }

    struct Numbers: Decodable {
        let pollOpenMs, pollBackgroundMs, pollFilingMs, optimisticTtlMs, arrivingMax, donePrefetched: Int
        let doneScanSettleMs, doneFreshMs, doneRetryMs, doneRetryMaxMs: Int
    }

    struct Words: Decodable {
        struct Heading: Decodable { let section, title: String }
        struct Retry: Decodable { let said, words: String }
        struct Another: Decodable { let left: Int; let said: String }
        let tab, retryFailed, tryingAnother, sameSource, tryingSame, shared, nobody, getOff, tell: String
        let notInNavidrome, notInStore, notLookedUp, cantOpenUnset, cantOpenDown, cantOpenOffline: String
        let empty, emptyJoin, nothingYet, unreached, keepsAsking, keepsAskingBelow: String
        let untracked, untrackedText, untrackedRuns, sameRefused, nextRefused, retryBroke, enqueueBroke: String
        let keepIt, leave, cancelVerb, play, confirmCancel, confirmCancelNote, confirmCancelKey, gettingAlbums: String
        let sections: [Heading]
        let retryWords: [Retry]
        let anotherSource: [Another]
        let cancel: CancelWords
    }

    struct Ordinal: Decodable { let n: Int; let said: String }
    struct Badge: Decodable { let count: Int; let text, label: String }
    struct Speed: Decodable { let bytes: Double; let said: String }
    struct Age: Decodable { let iso: String?; let now: Int64; let said: String }
    struct Partly: Decodable { let error: String?; let said: String }

    /// A job as the small cases give it: only the fields the rule reads.
    struct PartJob: Decodable {
        let status: String?
        let progress: Double?
        let outcome: String?
        let error: String?
        let library: String?
        let mine: Bool?
        let shared: Bool?
        let requestedBy: [String]?

        enum CodingKeys: String, CodingKey {
            case status, progress, outcome, error, library, mine, shared
            case requestedBy = "requested_by"
        }

        var job: DownloadJob {
            DownloadJob(id: 0, status: status ?? "complete", error: error, outcome: outcome, progress: progress,
                        mine: mine, shared: shared, requestedBy: requestedBy, library: library)
        }
    }

    struct OutcomeCase: Decodable {
        let job: PartJob
        let text, tone: String
        /// Left out where the web's answer has none: a tell only when true.
        let tell: Bool?
        let detail: String?
    }

    /// A retry's problem: the route's own words, or the hook's sentence with the error's words beside it.
    struct Problem: Decodable {
        struct Said: Decodable { let text: String; let detail: String? }
        let problem: RetryProblem

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let words = try? container.decode(String.self) {
                problem = .words(words)
            } else {
                let said = try container.decode(Said.self)
                problem = .said(text: said.text, detail: said.detail)
            }
        }
    }

    struct ProblemCase: Decodable {
        let problem: Problem
        let personal: Bool
        let text, detail: String?
    }

    struct PersonCase: Decodable {
        let job: PartJob
        let askedBy: String?
        let cancel: CancelWords
        let leaves: Bool
    }

    struct SectionCase: Decodable {
        let job: PartJob
        let section: String
    }

    /// `[id, value]`, as the exporter writes a Map's entries.
    struct Entry<Value: Decodable>: Decodable {
        let id: Int
        let value: Value

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(Int.self)
            value = try container.decode(Value.self)
        }
    }

    struct Input: Decodable {
        let jobs: [DownloadJob]
        let pending: [PendingDownload]
        let speeds: [Entry<Double>]
        let cancelling, retrying, retryingSame: [Int]
        let retryProblems: [Entry<Problem>]
        let personal: Bool

        var input: RequestsInput {
            var speeds: [Int: Double] = [:]
            for each in self.speeds { speeds[each.id] = each.value }
            var problems: [Int: RetryProblem] = [:]
            for each in retryProblems { problems[each.id] = each.value.problem }
            return RequestsInput(jobs: jobs, pending: pending, speeds: speeds, cancelling: Set(cancelling),
                                 retrying: Set(retrying), retryingSame: Set(retryingSame), retryProblems: problems,
                                 personal: personal)
        }
    }

    /// A row as the web draws it - every field, the cover the Archive's own address.
    struct Row: Decodable, Equatable, CustomStringConvertible {
        struct NextPeer: Decodable, Equatable { let left: Int; let primary: Bool; let label: String }
        struct AskAgain: Decodable, Equatable { let label: String }
        let key: String
        let jobId: Int?
        let section, title, artist: String
        let cover: String?
        let line, lineTone: String
        let reason: String?
        let reasonTell: Bool
        let reasonDetail, problem, problemDetail: String?
        let progress: Double
        let data: String?
        let brief: String
        let cancel: String?
        let nextPeer: NextPeer?
        let askAgain: AskAgain?
        let busy, dimmed, arriving: Bool
        let album: String
        let release: String?
        let plays: Bool
        let askedBy: String?
        let cancelWords: CancelWords

        var description: String { "\(key) \(section) \(line)" }

        /// The phone's row as the web would have drawn it: its cover, a release id, made the Archive's address.
        init(_ row: RequestRow) {
            key = row.key
            jobId = row.jobId
            section = row.section.rawValue
            title = row.title
            artist = row.artist
            cover = row.cover.map { (id: String) -> String in
                "https://coverartarchive.org/release/\(TurntableGeometry.encodeURIComponent(id))/front-250"
            }
            line = row.line
            lineTone = row.lineTone.rawValue
            reason = row.reason
            reasonTell = row.reasonTell
            reasonDetail = row.reasonDetail
            problem = row.problem
            problemDetail = row.problemDetail
            progress = row.progress
            data = row.data
            brief = row.brief
            cancel = row.cancel?.rawValue
            nextPeer = row.nextPeer.map { NextPeer(left: $0.left, primary: $0.primary, label: $0.label) }
            askAgain = row.askAgain.map { AskAgain(label: $0.label) }
            busy = row.busy
            dimmed = row.dimmed
            arriving = row.arriving
            album = row.album
            release = row.release
            plays = row.plays
            askedBy = row.askedBy
            cancelWords = row.cancelWords
        }
    }

    struct Drawn: Decodable {
        struct Sections: Decodable { let downloading, waiting, attention, done: [Row] }
        let sections: Sections
        let arriving: [String]
        let clearable, empty: Bool

        func rows(_ section: RequestSection) -> [Row] {
            switch section {
            case .downloading: return sections.downloading
            case .waiting: return sections.waiting
            case .attention: return sections.attention
            case .done: return sections.done
            }
        }
    }

    struct Board: Decodable {
        let input: Input
        let now: Int64
        let board: Drawn
        let activeCount: Int
    }

    struct Gone: Decodable {
        let key: String
        let focus: String?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            key = try container.decode(String.self)
            focus = try container.decodeNil() ? nil : try container.decode(String.self)
        }
    }

    struct ChangesRun: Decodable {
        struct Step: Decodable { let said: String; let moved: [String]; let gone: [Gone] }
        let now: Int64
        let inputs: [Input]
        let steps: [Step]
    }

    struct OverlayCase: Decodable {
        struct Given: Decodable {
            let cancelling, cleared, retrying: [Int]
            let pending: [PendingDownload]
            var overlays: RequestOverlays {
                RequestOverlays(cancelling: Set(cancelling), cleared: Set(cleared), pending: pending, retrying: Set(retrying))
            }
        }
        struct Reconciled: Decodable {
            let cancelling, cleared, retrying: [Int]
            let pending: [String]
        }
        struct Outcome: Decodable {
            let jobId: Int?
            let error: String?
            let detail: String?
            var settled: RequestOverlays.Settled {
                if let jobId { return .job(jobId) }
                return .refused(error: error ?? "", detail: detail)
            }
        }
        struct Settle: Decodable { let key: String; let outcome: Outcome; let pending: [PendingDownload] }
        let jobs: [DownloadJob]
        let overlays: Given
        let reconciled: Reconciled
        let visibleJobs, finishedIds: [Int]
        let visiblePending, withoutRefused: [String]
        let activeCount: Int
        let settle: Settle
    }

    struct SpeedTrace: Decodable {
        struct Step: Decodable { let now: Double; let jobs: [DownloadJob]; let speeds: [Entry<Double>] }
        let steps: [Step]
    }

    struct WatchingCases: Decodable {
        struct Shows: Decodable { let shown: Bool; let tab: String; let depth: Int; let sheetOpen: Bool; let watching: String }
        struct Stalls: Decodable { let watching: String; let error: String?; let arriving: Int; let stalls: Bool }
        struct Asks: Decodable { let before, now: String; let asks: Bool }
        let shows: [Shows]
        let stalls: [Stalls]
        let asks: [Asks]
    }

    struct LooksCase: Decodable {
        struct Row: Decodable { let release: String; let since: Double }
        struct Pair<Value: Decodable>: Decodable {
            let key: String
            let value: Value
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                key = try container.decode(String.self)
                value = try container.decode(Value.self)
            }
        }
        struct Miss: Decodable { let count: Int; let at: Double }
        struct Held: Decodable {
            let ids: [Pair<String>]
            let asked: [Pair<Double>]
            let misses: [Pair<Miss>]
            let inFlight: [String]
            let activeSince: Double
            var held: DoneLooks.Held {
                var out = DoneLooks.Held(inFlight: Set(inFlight), activeSince: activeSince)
                for each in ids { out.ids[each.key] = each.value }
                for each in asked { out.asked[each.key] = each.value }
                for each in misses { out.misses[each.key] = DoneLooks.Miss(count: each.value.count, at: each.value.at) }
                return out
            }
        }
        let rows: [Row]
        let held: Held
        let now: Double
        let look, songs: [String]
        let nextIn: Double?
    }

    struct FiledRun: Decodable {
        struct Step: Decodable { let jobs: [DownloadJob]; let filed: [Int] }
        let steps: [Step]
    }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("requests/requests-vectors.json"))
    }
}

@Suite struct RequestsVectorTests {
    @Test func theFixtureIsRead() throws {
        let vectors = try RequestsVectors.load()
        #expect(vectors.boards.count == 100)
        #expect(vectors.changes.count == 30)
        #expect(!vectors.outcomes.isEmpty && !vectors.overlays.isEmpty && !vectors.looks.isEmpty)
    }

    @Test func theNumbersAreTheWebs() throws {
        let numbers = try RequestsVectors.load().numbers
        let open: Double = RequestsPolling.openSeconds * 1000
        let background: Double = RequestsPolling.backgroundSeconds * 1000
        let filing: Double = RequestsPolling.filingSeconds * 1000
        let ttl: Double = RequestOverlays.ttlSeconds * 1000
        #expect(open == Double(numbers.pollOpenMs))
        #expect(background == Double(numbers.pollBackgroundMs))
        #expect(filing == Double(numbers.pollFilingMs))
        #expect(ttl == Double(numbers.optimisticTtlMs))
        #expect(RequestWords.arrivingMax == numbers.arrivingMax)
        #expect(DoneLooks.prefetched == numbers.donePrefetched)
        #expect(DoneLooks.scanSettleMs == Double(numbers.doneScanSettleMs))
        #expect(DoneLooks.freshMs == Double(numbers.doneFreshMs))
        #expect(DoneLooks.retryMs == Double(numbers.doneRetryMs))
        #expect(DoneLooks.retryMaxMs == Double(numbers.doneRetryMaxMs))
    }

    @Test func theWordsAreTheWebs() throws {
        let words = try RequestsVectors.load().words
        #expect(RequestWords.tab == words.tab)
        for heading in words.sections {
            let section: RequestSection? = RequestSection(rawValue: heading.section)
            #expect(section != nil, "\(heading.section)")
            if let section { #expect(RequestWords.title(section) == heading.title) }
        }
        let order: [String] = RequestSection.allCases.map { (section: RequestSection) -> String in section.rawValue }
        #expect(order == words.sections.map { $0.section })
        #expect(RequestWords.retryFailed == words.retryFailed)
        #expect(RequestWords.retryWords.count == words.retryWords.count)
        for each in words.retryWords { #expect(RequestWords.retryWords[each.said] == each.words, "\(each.said)") }
        for each in words.anotherSource { #expect(RequestWords.anotherSource(each.left) == each.said) }
        #expect(RequestWords.tryingAnother == words.tryingAnother)
        #expect(RequestWords.sameSource == words.sameSource)
        #expect(RequestWords.tryingSame == words.tryingSame)
        #expect(PerPerson.cancelDefault == words.cancel)
        #expect(PerPerson.sharedText == words.shared)
        #expect(PerPerson.nobodyText == words.nobody)
        #expect(RequestWords.getOff == words.getOff)
        #expect(ErrorWords.tell == words.tell)
        #expect(RequestWords.notInNavidrome == words.notInNavidrome)
        #expect(RequestWords.notInStore == words.notInStore)
        #expect(RequestWords.notLookedUp == words.notLookedUp)
        #expect(RequestWords.cantOpenUnset == words.cantOpenUnset)
        #expect(RequestWords.cantOpenDown == words.cantOpenDown)
        #expect(RequestWords.cantOpenOffline == words.cantOpenOffline)
        #expect(RequestWords.empty == words.empty)
        #expect(RequestWords.emptyJoin == words.emptyJoin)
        #expect(RequestWords.nothingYet == words.nothingYet)
        #expect(RequestWords.unreached == words.unreached)
        #expect(RequestWords.keepsAsking == words.keepsAsking)
        #expect(RequestWords.keepsAskingBelow == words.keepsAskingBelow)
        #expect(RequestWords.untracked == words.untracked)
        #expect(RequestWords.untrackedText == words.untrackedText)
        #expect(RequestWords.untrackedRuns == words.untrackedRuns)
        #expect(RequestWords.sameRefused == words.sameRefused)
        #expect(RequestWords.nextRefused == words.nextRefused)
        #expect(RequestWords.retryBroke == words.retryBroke)
        #expect(RequestWords.enqueueBroke == words.enqueueBroke)
        #expect(RequestWords.keepIt == words.keepIt)
        #expect(RequestWords.confirmCancel == words.confirmCancel)
        #expect(RequestWords.confirmCancelNote == words.confirmCancelNote)
        #expect(ConfirmCancel.storageKey == words.confirmCancelKey)
        #expect(RequestWords.gettingAlbums == words.gettingAlbums)
        var row = RequestRow(key: "job-1", jobId: 1, section: .waiting, title: "Dummy \u{00B7} 2014 vinyl", artist: "Portishead")
        #expect(RequestWords.cancelLabel(row) == "\(words.cancelVerb) Dummy \u{00B7} 2014 vinyl")
        #expect(RequestWords.playLabel(row) == "\(words.play) Dummy \u{00B7} 2014 vinyl")
        row.cancelWords = CancelWords(question: "", action: "", leaves: true)
        #expect(RequestWords.cancelLabel(row) == "\(words.leave) Dummy \u{00B7} 2014 vinyl")
    }

    @Test func theSmallRulesAreTheWebs() throws {
        let vectors = try RequestsVectors.load()
        for each in vectors.ordinals { #expect(RequestWords.ordinal(each.n) == each.said, "\(each.n)") }
        for each in vectors.badges {
            #expect(RequestWords.badgeText(each.count) == each.text, "\(each.count)")
            #expect(RequestWords.badgeLabel("Requests", each.count) == each.label, "\(each.count)")
        }
        for each in vectors.speeds { #expect(RequestWords.speed(each.bytes) == each.said, "\(each.bytes)") }
        for each in vectors.ages {
            #expect(RequestWords.age(each.iso, now: each.now) == each.said, "\(each.iso ?? "null")")
        }
        for each in vectors.partly { #expect(PerPerson.partlyWords(each.error) == each.said, "\(each.error ?? "null")") }
        for each in vectors.sections {
            let section: RequestSection = RequestWords.section(each.job.job)
            #expect(section.rawValue == each.section, "\(each.job.job)")
        }
    }

    @Test func howADownloadEndedIsSaidAsTheWebSaysIt() throws {
        let vectors = try RequestsVectors.load()
        for each in vectors.outcomes {
            let said: RequestWords.Outcome = RequestWords.outcome(each.job.job)
            #expect(said.text == each.text, "\(each.job.job)")
            #expect(said.tone.rawValue == each.tone, "\(each.job.job)")
            #expect(said.tell == (each.tell == true), "\(each.job.job)")
            #expect(said.detail == each.detail, "\(each.job.job)")
        }
    }

    @Test func aRetrysProblemIsSaidAsTheWebSaysIt() throws {
        let vectors = try RequestsVectors.load()
        for each in vectors.problems {
            let said: (text: String?, detail: String?) = RequestWords.retryProblemWords(each.problem.problem, personal: each.personal)
            #expect(said.text == each.text, "\(each.problem.problem)")
            #expect(said.detail == each.detail, "\(each.problem.problem)")
        }
        let none: (text: String?, detail: String?) = RequestWords.retryProblemWords(nil)
        #expect(none.text == nil && none.detail == nil)
    }

    @Test func whoAskedIsSaidAsTheWebSaysIt() throws {
        let vectors = try RequestsVectors.load()
        for each in vectors.people {
            let job = each.job.job
            let asked: String? = PerPerson.askedByText(mine: job.mine, shared: job.shared, requestedBy: job.requestedBy)
            let words: CancelWords = PerPerson.cancelWords(mine: job.mine, shared: job.shared, requestedBy: job.requestedBy)
            let leaves: Bool = PerPerson.leavesOnCancel(shared: job.shared, requestedBy: job.requestedBy)
            #expect(asked == each.askedBy, "\(job)")
            #expect(words == each.cancel, "\(job)")
            #expect(leaves == each.leaves, "\(job)")
        }
    }

    @Test func everyBoardIsDrawnAsTheWebDrawsIt() throws {
        let vectors = try RequestsVectors.load()
        var rows = 0
        for (number, board) in vectors.boards.enumerated() {
            let view: RequestsView = RequestsView.make(board.input.input, now: board.now)
            for section in RequestSection.allCases {
                let mine: [RequestsVectors.Row] = view.rows(section).map { (row: RequestRow) -> RequestsVectors.Row in
                    RequestsVectors.Row(row)
                }
                let theirs: [RequestsVectors.Row] = board.board.rows(section)
                #expect(mine.map { $0.key } == theirs.map { $0.key }, "board \(number) \(section)")
                for (one, other) in zip(mine, theirs) {
                    #expect(one == other, "board \(number): \(one) / \(other)")
                    rows += 1
                }
            }
            let arriving: [String] = view.arriving.map { (row: RequestRow) -> String in row.key }
            #expect(arriving == board.board.arriving, "board \(number)")
            #expect(view.clearable == board.board.clearable, "board \(number)")
            #expect(view.empty == board.board.empty, "board \(number)")
            let overlays = RequestOverlays(cancelling: Set(board.input.cancelling), pending: board.input.pending,
                                           retrying: Set(board.input.retrying))
            let active: Int = overlays.activeCount(board.input.jobs)
            #expect(active == board.activeCount, "board \(number)")
        }
        #expect(rows > 400)
    }

    @Test func whatAScreenReaderHearsIsTheWebs() throws {
        let vectors = try RequestsVectors.load()
        var said = 0
        for (number, run) in vectors.changes.enumerated() {
            var before: RequestsView?
            for (step, input) in run.inputs.enumerated() {
                let now: RequestsView = RequestsView.make(input.input, now: run.now)
                let heard: RequestChanges.Said = RequestChanges.changes(before: before, now: now)
                let want = run.steps[step]
                #expect(heard.said == want.said, "run \(number) step \(step)")
                #expect(heard.moved == want.moved, "run \(number) step \(step)")
                let gone: [String] = heard.gone.map { $0.key }
                let focus: [String?] = heard.gone.map { $0.focus }
                #expect(gone == want.gone.map { $0.key }, "run \(number) step \(step)")
                #expect(focus == want.gone.map { $0.focus }, "run \(number) step \(step)")
                if !want.said.isEmpty { said += 1 }
                before = now
            }
        }
        #expect(said > 30)
    }

    @Test func theOverlaysAreTheWebs() throws {
        let vectors = try RequestsVectors.load()
        for (number, each) in vectors.overlays.enumerated() {
            let overlays: RequestOverlays = each.overlays.overlays
            let reconciled: RequestOverlays = overlays.reconcile(each.jobs)
            #expect(reconciled.cancelling == Set(each.reconciled.cancelling), "case \(number)")
            #expect(reconciled.cleared == Set(each.reconciled.cleared), "case \(number)")
            #expect(reconciled.retrying == Set(each.reconciled.retrying), "case \(number)")
            #expect(reconciled.pending.map { $0.key } == each.reconciled.pending, "case \(number)")
            let visible: [Int] = overlays.visibleJobs(each.jobs).map { (job: DownloadJob) -> Int in job.id }
            #expect(visible == each.visibleJobs, "case \(number)")
            let pending: [String] = overlays.visiblePending(each.jobs).map { (one: PendingDownload) -> String in one.key }
            #expect(pending == each.visiblePending, "case \(number)")
            #expect(overlays.activeCount(each.jobs) == each.activeCount, "case \(number)")
            #expect(RequestOverlays.finishedIds(each.jobs) == each.finishedIds, "case \(number)")
            let kept: [String] = overlays.withoutRefused().pending.map { (one: PendingDownload) -> String in one.key }
            #expect(kept == each.withoutRefused, "case \(number)")
            let settled: [PendingDownload] = overlays.settlePending(each.settle.key, each.settle.outcome.settled).pending
            #expect(settled == each.settle.pending, "case \(number)")
        }
    }

    @Test func theSpeedsAreMeasuredAsTheWebMeasuresThem() throws {
        let vectors = try RequestsVectors.load()
        var measured = 0
        for (number, trace) in vectors.speedTraces.enumerated() {
            var samples = SpeedSamples()
            for (step, each) in trace.steps.enumerated() {
                let speeds: [Int: Double] = samples.sample(each.jobs, now: each.now)
                var want: [Int: Double] = [:]
                for entry in each.speeds { want[entry.id] = entry.value }
                #expect(speeds == want, "trace \(number) step \(step)")
                measured += want.count
            }
        }
        #expect(measured > 50)
    }

    @Test func whatTheAppWatchesIsTheWebs() throws {
        let cases = try RequestsVectors.load().watching
        for each in cases.shows {
            let watching: Watching = RequestsWatch.watching(shown: each.shown, tab: each.tab, depth: each.depth,
                                                            sheetOpen: each.sheetOpen)
            #expect(watching.rawValue == each.watching, "\(each.tab) \(each.depth) \(each.sheetOpen) \(each.shown)")
        }
        for each in cases.stalls {
            let watching: Watching? = Watching(rawValue: each.watching)
            #expect(watching != nil)
            if let watching {
                let stalls: Bool = RequestsWatch.stallsOn(watching, error: each.error, arriving: each.arriving)
                #expect(stalls == each.stalls, "\(each.watching) \(each.error ?? "null") \(each.arriving)")
            }
        }
        for each in cases.asks {
            let before: Watching? = Watching(rawValue: each.before)
            let now: Watching? = Watching(rawValue: each.now)
            if let before, let now {
                let asks: Bool = RequestsWatch.asksAgain(before, now)
                #expect(asks == each.asks, "\(each.before) -> \(each.now)")
            } else {
                Issue.record("\(each.before) -> \(each.now)")
            }
        }
    }

    @Test func anAlbumJustFiledIsNoticedAsTheWebNoticesIt() throws {
        let vectors = try RequestsVectors.load()
        var noticed = 0
        for (number, run) in vectors.filed.enumerated() {
            var previous: [Int: String]?
            for (step, each) in run.steps.enumerated() {
                let filed: [Int] = RequestsWatch.newlyFiled(previous, each.jobs)
                #expect(filed == each.filed, "run \(number) step \(step)")
                noticed += filed.count
                previous = RequestsWatch.statuses(each.jobs)
            }
        }
        #expect(noticed > 10)
    }

    @Test func theDoneRowsAlbumsAreLookedForAsTheWebLooks() throws {
        let vectors = try RequestsVectors.load()
        var asked = 0
        for (number, each) in vectors.looks.enumerated() {
            let rows: [DoneLooks.Row] = each.rows.map { (row: RequestsVectors.LooksCase.Row) -> DoneLooks.Row in
                DoneLooks.Row(release: row.release, since: row.since)
            }
            let looks: DoneLooks.Looks = DoneLooks.looks(rows, held: each.held.held, now: each.now)
            #expect(looks.look == each.look, "case \(number)")
            #expect(looks.songs == each.songs, "case \(number)")
            #expect(looks.nextIn == each.nextIn, "case \(number)")
            asked += looks.look.count + looks.songs.count
        }
        #expect(asked > 50)
    }
}
