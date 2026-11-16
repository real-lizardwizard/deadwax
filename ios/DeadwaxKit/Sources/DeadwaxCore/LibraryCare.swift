import Foundation

// Library care on the phone (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; notes/ios.md "Library care on the
// phone"): Rescan, the bulk runs (Get covers · N, Get CD art · N, Get lyrics · N) and In nobody's library - the web's
// app/LibraryCare.tsx, app/useLibraryCare.ts and app/HeldByNobody.tsx, over ui/src/lib/libraryCare.ts, bulkTargets.ts and
// myLibrary.ts. Every rule and word here is the web's, held to it by Tests/DeadwaxCoreTests/Fixtures/care/
// library-care-vectors.json (ios/scripts/export-library-care-vectors.cjs runs the TypeScript as it is; ui/test/
// ioscare.sim.cjs checks it is current) - but for the phone's own few, said where they are: a run that stopped because the
// app went to the background, deadwax out of reach, the session ended or deadwax refused Edit albums (CareRuns.Stop),
// one run at a time, and a step that may have written without saying (BulkTargets.Step).

/// The bulk runs' rules (bulkTargets.ts): which albums each kind takes, what one album came to, a run's progress and its
/// words once it has finished.
public enum BulkTargets {
    /// A kind of run, in the order Library care draws them (`BULK_KINDS`).
    public enum Kind: String, Sendable, CaseIterable, Hashable, Decodable {
        case covers, disc, lyrics
    }

    /// `BULK_KINDS`.
    public static let kinds: [Kind] = [.covers, .disc, .lyrics]

    /// `hasOwnDiscArt`: a `disc*` image beside the tracks - deadwax's own CD art (a download's cd.jpg isn't).
    public static func hasOwnDiscArt(_ names: [String]) -> Bool {
        names.contains { JSText.lowercase($0).utf16.starts(with: "disc".utf16) }
    }

    /// `bulkTargets(kind, albums)`: the album folders a run of `kind` takes, in the order given - covers a release to ask
    /// the Archive about and no cover yet; CD art a release and none of deadwax's own; lyrics none on disk at all.
    public static func targets(_ kind: Kind, _ albums: [ScanAlbum]) -> [ScanAlbum] {
        switch kind {
        case .covers: return albums.filter { $0.art.isEmpty && !$0.releaseMbid.isEmpty }
        case .disc: return albums.filter { !$0.releaseMbid.isEmpty && !hasOwnDiscArt($0.discArt) }
        case .lyrics: return albums.filter { $0.lyricsCount == 0 }
        }
    }

    /// `BulkRun`: a run under way, or the last one's result - how far it got, and what came of each album (lyrics in
    /// tracks, covers and CD art in albums).
    public struct Run: Sendable, Equatable, Decodable {
        public var total: Int
        public var done: Int
        public var written: Int
        public var missing: Int
        public var failed: Int
        public var running: Bool

        public init(total: Int, done: Int = 0, written: Int = 0, missing: Int = 0, failed: Int = 0, running: Bool = true) {
            self.total = total
            self.done = done
            self.written = written
            self.missing = missing
            self.failed = failed
            self.running = running
        }
    }

    /// `BulkOutcome`: what one album came to (any count left out is none).
    public struct Outcome: Sendable, Equatable, Decodable {
        public let written: Int
        public let missing: Int
        public let failed: Int

        public init(written: Int = 0, missing: Int = 0, failed: Int = 0) {
            self.written = written
            self.missing = missing
            self.failed = failed
        }

        enum CodingKeys: String, CodingKey { case written, missing, failed }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            written = fields.looseField(Int.self, .written) ?? 0
            missing = fields.looseField(Int.self, .missing) ?? 0
            failed = fields.looseField(Int.self, .failed) ?? 0
        }
    }

    /// `startRun(total)`.
    public static func start(_ total: Int) -> Run {
        Run(total: total)
    }

    /// `addOutcome(run, outcome)`: one more album done, and what it came to.
    public static func adding(_ run: Run, _ outcome: Outcome) -> Run {
        var next = run
        next.done += 1
        next.written += outcome.written
        next.missing += outcome.missing
        next.failed += outcome.failed
        return next
    }

    // MARK: each album's step (useLibraryCare.ts STEPS)

    /// Lyrics' step answered: LRCLIB's summary in tracks - written or replaced, not on LRCLIB or instrumental, failed.
    public static func outcome(_ summary: LyricsSummary) -> Outcome {
        Outcome(written: summary.written + summary.replaced, missing: summary.missing + summary.instrumental,
                failed: summary.failed)
    }

    /// A step that threw, counted (runBulk's `failedAs`): every track of the album for lyrics, one album else.
    public static func failedAs(_ kind: Kind, _ album: ScanAlbum) -> Int {
        kind == .lyrics ? album.trackCount : 1
    }

    /// What a step's failure came to, as the web counts it - a cover's or CD art's 404 is none to find (a fact about the
    /// release), anything else failed (worth another go); lyrics' every track failed - and, the phone's own, whether it
    /// may have written all the same: deadwax refused it (a 4xx) and wrote nothing, or it never answered, timed out or
    /// answered a 5xx (`unanswered` - RetagFlow.outcome: the server carries on when the phone goes; a cancellation too,
    /// though nothing in the app cancels a run's request). And a 403, the phone's own: deadwax refused it because Edit
    /// albums is no longer this person's - counted as the web counts it (failed), and the run stops after it, where the
    /// web's carries on through every album left, each refused the same way (`forbidden`).
    public enum Step: Sendable, Equatable {
        case answered(Outcome)
        case unanswered(Outcome)
        case forbidden(Outcome)
    }

    /// The step a failure is (`pictureStep`'s catch, runBulk's for lyrics).
    public static func step(_ kind: Kind, _ album: ScanAlbum, failure error: any Error) -> Step {
        var status: Int?
        if case .answered(let answer)? = error as? APIFailure { status = answer.status }
        let outcome: Outcome
        if kind == .lyrics {
            outcome = Outcome(failed: failedAs(kind, album))
        } else if status == 404 {
            outcome = Outcome(missing: 1)
        } else {
            outcome = Outcome(failed: 1)
        }
        if status == 403 { return .forbidden(outcome) }
        return RetagFlow.outcome(of: error) == .refused ? .answered(outcome) : .unanswered(outcome)
    }

    // MARK: the words

    /// `bulkSummary(kind, run)`: what a finished run did, in sentences - none in the Cover Art Archive kept apart from
    /// failed, lyrics in tracks.
    public static func summary(_ kind: Kind, _ run: Run) -> String {
        let stopped = run.done < run.total
        func them(_ count: Int) -> String { count == 1 ? "it" : "them" }
        if kind == .lyrics {
            return [
                "Saved lyrics for \(run.written) \(run.written == 1 ? "track" : "tracks").",
                run.missing != 0
                    ? "\(run.missing) \(run.missing == 1 ? "isn't on LRCLIB or is" : "aren't on LRCLIB or are") instrumental."
                    : "",
                run.failed != 0
                    ? "\(run.failed) failed - try \(them(run.failed)) again from the album's own Get lyrics, in Edit album."
                    : "",
                stopped ? "Stopped at \(run.done) of \(run.total) albums." : "",
            ].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let head = kind == .covers
            ? "Got \(run.written) \(run.written == 1 ? "cover" : "covers")."
            : "Got CD art for \(run.written) \(run.written == 1 ? "album" : "albums")."
        return [
            head,
            run.missing != 0
                ? "\(run.missing) \(run.missing == 1 ? "has" : "have") \(kind == .covers ? "none in the Cover Art Archive" : "none to find")."
                : "",
            run.failed != 0 ? "\(run.failed) failed - run it again to try \(them(run.failed)) again." : "",
            stopped ? "Stopped at \(run.done) of \(run.total)." : "",
        ].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Library care's page (libraryCare.ts and LibraryCare.tsx): its words, the runs' narrowing and what each says it will
/// do, the scan's facts, and who sees which part.
public enum LibraryCare {
    /// The page's title (LibraryCare.tsx's large title) - Manage's row says the same (ManagingWords.label(.care)).
    public static let title = "Library care"
    /// The first read under way (the spinner's label).
    public static let reading = "Reading the library"
    public static let tryAgain = "Try again"
    /// Rescan's heading, and its button while nothing is under way and while ours is.
    public static let rescanTitle = "Rescan"
    public static let rescan = "Rescan"
    public static let rescanning = "Rescanning…"
    /// The runs' heading, the narrowing's label and its prompt.
    public static let runsTitle = "Covers, CD art and lyrics"
    public static let narrowTo = "Narrow to"
    public static let narrowPrompt = "Artist, album or folder"
    /// A kind's note (and the scope's) before a scan to trust, or while its run's writes are newer than the scan.
    public static let checking = "Checking the library…"

    /// `READ_FAILED`, `CHECK_FAILED`, `REREAD_FAILED`: the library's read failing, in a listener's words.
    public static let readFailed = "Couldn't read the library."
    public static let checkFailed = "Couldn't check the library just now."
    public static let rereadFailed = "Couldn't read the library just now."

    /// `CARE_LINE`: what the page is for, with both parts.
    public static let careLineAll = "Rescan the library after changing tags in another program, and fill in missing "
        + "covers, CD art and lyrics across many albums at once - one album at a time, and Stop ends a run after the "
        + "album it's on."

    /// `careLine(parts)`: what the page is for, naming only the parts it draws for this person.
    public static func careLine(rescan: Bool, bulk: Bool) -> String {
        if rescan && bulk { return careLineAll }
        if bulk {
            return "Fill in missing covers, CD art and lyrics across many albums at once - one album at a time, and Stop "
                + "ends a run after the album it's on."
        }
        return "Rescan reads every file of the library again - use it after changing tags in another program."
    }

    /// `RESCAN_WORDS`: why Rescan is there - when to use it first, then why.
    public static let rescanWords = "Use Rescan after editing tags in another program: deadwax spots a changed album by "
        + "its folder's date, and editing tags in place doesn't change it. Albums added from a download show up without it."

    /// `BULK_LABELS`: the button that starts a run.
    public static func label(_ kind: BulkTargets.Kind) -> String {
        switch kind {
        case .covers: return "Get covers"
        case .disc: return "Get CD art"
        case .lyrics: return "Get lyrics"
        }
    }

    /// `BULK_TITLES`: each run's heading.
    public static func heading(_ kind: BulkTargets.Kind) -> String {
        switch kind {
        case .covers: return "Covers"
        case .disc: return "CD art"
        case .lyrics: return "Lyrics"
        }
    }

    /// Start, with how many albums it takes: "Get covers · 14".
    public static func startLabel(_ kind: BulkTargets.Kind, count: Int) -> String {
        "\(label(kind)) · \(count)"
    }

    /// Stop, on the running run's button: the album being fetched (done + 1), as Stopping and Stopped say it.
    public static func stopLabel(_ run: BulkTargets.Run, stopping: Bool) -> String {
        stopping
            ? "Stopping after \(run.done + 1) of \(run.total)"
            : "Stop after this album · \(min(run.done + 1, run.total)) of \(run.total)"
    }

    // MARK: narrowing

    /// `narrowAlbums(albums, typed)`: every album, or those whose artist, album, edition or folder holds every word
    /// typed - accents and case aside (TypedMatch, the web's matchesTyped).
    public static func narrow(_ albums: [ScanAlbum], _ typed: String) -> [ScanAlbum] {
        guard !JSText.trim(typed).isEmpty else { return albums }
        return albums.filter { TypedMatch.matches("\($0.artist) \($0.album) \($0.edition) \($0.path)", typed: typed) }
    }

    /// `scopeWords(typed)`: " in the whole library", or " among the folders matching “x”".
    public static func scopeWords(_ typed: String) -> String {
        let text = JSText.trim(typed)
        return text.isEmpty ? " in the whole library" : " among the folders matching \u{201C}\(text)\u{201D}"
    }

    private static func folders(_ count: Int) -> String {
        "\(count) album folder\(count == 1 ? "" : "s")"
    }

    /// `scopeLine(inScope, all, typed)`: what the runs act on, said under the narrowing.
    public static func scopeLine(inScope: Int, all: Int, typed: String) -> String {
        let text = JSText.trim(typed)
        if text.isEmpty { return "The runs act on the whole library: \(folders(all))." }
        return inScope != 0
            ? "The runs act on \(inScope) of \(folders(all)): those matching \u{201C}\(text)\u{201D}."
            : "No album folder matches \u{201C}\(text)\u{201D}."
    }

    /// `planWords(kind, count, typed)`: what a run will do, said before it starts.
    public static func planWords(_ kind: BulkTargets.Kind, count: Int, typed: String) -> String {
        let at = scopeWords(typed)
        switch kind {
        case .covers:
            return count != 0
                ? "\(folders(count)) matched to a release with no cover\(at). Each cover comes from the Cover Art Archive, "
                    + "for the release the album is matched to, and is saved beside its tracks - nothing else about the "
                    + "album changes."
                : "No album matched to a release is missing its cover\(at)."
        case .disc:
            return count != 0
                ? "\(folders(count)) matched to a release with no disc picture from deadwax yet\(at). A picture of each "
                    + "disc comes from the Cover Art Archive (or fanart.tv, with a key in Server settings) and is saved "
                    + "beside the tracks - nothing else changes."
                : "Every album matched to a release has a disc picture from deadwax\(at)."
        case .lyrics:
            return count != 0
                ? "\(folders(count)) with no lyrics at all\(at). Each track's lyrics come from LRCLIB and are saved beside "
                    + "it - nothing else changes. An album with some lyrics is finished from its own Get lyrics, in Edit "
                    + "album."
                : "Every album has some lyrics\(at)."
        }
    }

    // MARK: the page's own (LibraryCare.tsx)

    /// `real`: a scan to trust - read, and not the saved one (the phone never reads a saved one; CareRuns.real adds a
    /// read begun since deadwax was last out of reach).
    public static func real(loaded: Bool, stale: Bool) -> Bool {
        loaded && !stale
    }

    /// `scanBusy`: Rescan refused while ours is out, or a plain read over a real scan is.
    public static func busy(rescanning: Bool, reading: Bool, stale: Bool = false) -> Bool {
        rescanning || (reading && !stale)
    }

    /// The albums a kind's run would take (`targets`): only from a scan to trust, and not while a run of the kind that
    /// wrote is newer than the scan in hand - nil, and the note says Checking the library….
    public static func targets(_ kind: BulkTargets.Kind, real: Bool, behind: Bool, inScope: [ScanAlbum]) -> [ScanAlbum]? {
        real && !behind ? BulkTargets.targets(kind, inScope) : nil
    }

    /// A kind's note: what its run will do, or Checking the library….
    public static func note(_ kind: BulkTargets.Kind, targets: [ScanAlbum]?, typed: String) -> String {
        guard let targets else { return checking }
        return planWords(kind, count: targets.count, typed: typed)
    }

    /// The scope's note under Narrow to.
    public static func scopeNote(real: Bool, inScope: Int, all: Int, typed: String) -> String {
        real ? scopeLine(inScope: inScope, all: all, typed: typed) : checking
    }

    // MARK: the scan's facts

    /// `scanTotals(albums)`: albums (several pressings of one album once - groupAlbums' key, artist and album in
    /// JavaScript's lower case), tracks, and size.
    public static func scanTotals(_ albums: [ScanAlbum]) -> String {
        var keys = Set<[UInt16]>()
        for album in albums {
            keys.insert(Array((JSText.lowercase(album.artist) + "\u{0}" + JSText.lowercase(album.album)).utf16))
        }
        let groups = keys.count
        let tracks = albums.reduce(0) { $0 + $1.trackCount }
        let size = Sources.size(albums.reduce(0.0) { $0 + $1.totalSize })
        return ["\(groups) album\(groups == 1 ? "" : "s")", "\(tracks) track\(tracks == 1 ? "" : "s")", size]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// format.ts `formatAge(unixSeconds, now)`: how long ago, roughly - "" when unknown (`now` in milliseconds).
    public static func formatAge(_ unixSeconds: Double?, now: Double) -> String {
        guard let unixSeconds, unixSeconds != 0, !unixSeconds.isNaN else { return "" }
        let seconds = max(0, JSMath.round(now / 1000 - unixSeconds))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(WebText.number((seconds / 60).rounded(.down))) min ago" }
        if seconds < 86400 { return "\(WebText.number((seconds / 3600).rounded(.down))) h ago" }
        let days = (seconds / 86400).rounded(.down)
        return "\(WebText.number(days)) day\(days == 1 ? "" : "s") ago"
    }

    /// `scanAge(scan, rescanning, now)`: how old the scan in hand is - or what is under way (`now` in milliseconds).
    public static func scanAge(loaded: Bool, stale: Bool, loading: Bool, scannedAt: Double?, scanSeconds: Double,
                               rescanning: Bool, now: Double) -> String {
        if !loaded { return "Reading the library…" }
        if rescanning { return "Rescanning - reading every file again…" }
        let age = formatAge(scannedAt, now: now)
        if stale { return "Saved scan from \(age.isEmpty ? "an earlier visit" : age)\(loading ? " · checking for changes" : "")" }
        guard let scannedAt, scannedAt != 0, !scannedAt.isNaN else { return "" }
        let took = scanSeconds != 0 && !scanSeconds.isNaN ? " in \(WebText.number(scanSeconds))s" : ""
        return "Scanned \(age)\(took)"
    }

    /// The facts under Rescan: the totals, then the age.
    public static func facts(_ albums: [ScanAlbum], loaded: Bool, stale: Bool = false, loading: Bool,
                             scannedAt: Double?, scanSeconds: Double, rescanning: Bool, now: Double) -> String {
        [scanTotals(albums), scanAge(loaded: loaded, stale: stale, loading: loading, scannedAt: scannedAt,
                                     scanSeconds: scanSeconds, rescanning: rescanning, now: now)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: the phone's own

    /// A run that stopped short for a reason of the phone's, said after the web's summary (its "Stopped at 14 of 60."):
    /// where to carry on - Start takes only the albums still without, since the run's own targets are asked again.
    public static func stopped(_ stop: CareRuns.Stop, kind: BulkTargets.Kind) -> String? {
        switch stop {
        case .pressed:
            return nil
        case .background:
            return "It stopped as the app went to the background - \(label(kind)) carries on."
        case .outOfReach:
            return "It stopped as deadwax went out of reach - \(label(kind)) carries on once it's back."
        case .notAllowed:
            return "It stopped: running it needs Edit albums, which an admin hasn't given you."
        case .sessionEnded:
            return "It stopped as your session ended - sign in again, and \(label(kind)) carries on."
        }
    }

    /// Kept on screen while a run is under way and its page is in front (isIdleTimerDisabled).
    public static let screenOnNote = "The screen stays on while a run is under way and this page shows."
    /// Another kind's run is under way: one run at a time on the phone.
    public static func waiting(for kind: BulkTargets.Kind) -> String {
        "One run at a time - this one can start once \(heading(kind)) has finished."
    }
}

/// Library care's runs, Rescan and the scan's freshness - every decision the page makes about them, the App only
/// carrying them out (CareRunModel): one run at a time, never begun before a read to trust nor over a kind still behind
/// the disk; each album asked for only through `next`, so a Stop, the app going to the background, deadwax going out of
/// reach or the permission going lands after the album out, never before; counted as the web counts it; a run that wrote,
/// or may have, leaves its kind behind until a read begun after it lands; and Needs a look's count told after each album
/// that wrote or may have, and after a rescan. Held by the app (useLibraryCare.ts's module store), so leaving the page
/// doesn't stop a run.
public struct CareRuns: Sendable, Equatable {
    /// Why a run stops before its last album - after the one out, never during it.
    public enum Stop: String, Sendable, Equatable {
        /// Stop pressed (`stopBulk`).
        case pressed
        /// The app went to the background (the phone's own: iOS suspends it soon after).
        case background
        /// deadwax went out of reach (the phone's own: nothing is asked while it is).
        case outOfReach
        /// Edit albums is no longer this person's - /me says so, or deadwax refused an album with a 403 (the phone's
        /// own).
        case notAllowed
        /// The session ended - the sign-in came over the app, or the app has no session to ask with (the phone's own:
        /// every album after would be refused).
        case sessionEnded
    }

    /// The run under way: its kind, the albums it takes (as worked out when Start was pressed), how far it has got, why
    /// it will stop after the album out, and the album out.
    public struct Under: Sendable, Equatable {
        public let kind: BulkTargets.Kind
        public let albums: [ScanAlbum]
        public fileprivate(set) var run: BulkTargets.Run
        public fileprivate(set) var stop: Stop?
        public fileprivate(set) var out: ScanAlbum?
        /// An album never answered, timed out or answered a 5xx: it may have written.
        public fileprivate(set) var maybe = false
    }

    /// A kind's last run once over: what it came to, and why it stopped short (nil when it didn't).
    public struct Ended: Sendable, Equatable {
        public let run: BulkTargets.Run
        public let stop: Stop?
    }

    /// What `next` says: the album to fetch now, or the run just ended (say its result), or nothing to do.
    public enum Next: Sendable, Equatable {
        case album(ScanAlbum)
        case ended(BulkTargets.Kind)
        case nothing
    }

    /// What a rescan came to (CareRunModel reads it from LibraryScanModel and RetagFlow.outcome).
    public enum Rescanned: Sendable, Equatable {
        /// It answered, with this many album folders.
        case landed(albums: Int)
        /// deadwax refused it (a 4xx): nothing changed.
        case refused
        /// No answer, a timeout or a 5xx: it may have finished - said, and the library read again.
        case unanswered
        /// Cancelled, or a newer read took over: nothing changed.
        case dropped
    }

    /// What the App does after a rescan: read the library again, then tell Needs a look's count; and say it may have
    /// finished.
    public struct AfterRescan: Sendable, Equatable {
        public let readAgain: Bool
        public let tell: Bool
        public let mayHaveFinished: Bool

        public static let nothing = AfterRescan(readAgain: false, tell: false, mayHaveFinished: false)
    }

    /// The run under way.
    public private(set) var under: Under?
    /// Each kind's last run once over - kept until the next of its kind starts.
    public private(set) var ended: [BulkTargets.Kind: Ended] = [:]
    /// The kinds a run that wrote (or may have) left behind the disk, each with how many reads had begun as it ended.
    public private(set) var behind: [BulkTargets.Kind: Int] = [:]
    /// Reads of the scan begun (a rescan is one), each numbered.
    public private(set) var reads = 0
    /// The newest read that landed.
    public private(set) var landed = 0
    /// Reads begun when deadwax last went out of reach: a read to trust began after it.
    public private(set) var gap = 0
    /// A rescan is out.
    public private(set) var rescanning = false
    /// The words typed to narrow the runs (kept with them).
    public var narrow = ""

    public init() {}

    // MARK: the scan

    /// A scan to trust: one landed that began since deadwax was last out of reach.
    public var real: Bool { landed > gap }

    /// A read of the scan begun: its number.
    public mutating func readBegan() -> Int {
        reads += 1
        return reads
    }

    /// Read `ticket` landed: the kinds whose runs ended before it began caught up.
    public mutating func readLanded(_ ticket: Int) {
        guard ticket > landed else { return }
        landed = ticket
        behind = behind.filter { $0.value >= ticket }
    }

    /// Whether the page reads the library now - when it shows, comes back into reach, a run ends or a rescan does: never
    /// out of reach, while a read is out or ours; the first read; one after deadwax was out of reach; one a kind left
    /// behind waits for; and, shown again, once underneath (LibraryCare.tsx's `wasLive`).
    public func readsNow(shown: Bool, online: Bool, again: Bool, loaded: Bool, reading: Bool) -> Bool {
        guard shown, online, !reading, !rescanning else { return false }
        return !loaded || !real || !behind.isEmpty || again
    }

    /// deadwax came into reach or went out of it: out, a read from before it isn't trusted, and a run stops after the
    /// album out.
    public mutating func reach(_ online: Bool) {
        guard !online else { return }
        gap = reads
        stopUnder(.outOfReach)
    }

    /// The app went to the background: a run stops after the album out.
    public mutating func suspended() {
        stopUnder(.background)
    }

    /// The session ended (the sign-in over the app): a run stops after the album out - the same person signing in
    /// again keeps its result, and Start carries on.
    public mutating func sessionEnded() {
        stopUnder(.sessionEnded)
    }

    private mutating func stopUnder(_ why: Stop) {
        guard var now = under, now.stop == nil else { return }
        now.stop = why
        under = now
    }

    // MARK: Rescan

    /// Rescan may be pressed: the person's part, in reach, no LIBRARY_PATH problem, nothing busy.
    public func rescanOpen(allowed: Bool, online: Bool, problem: Bool, reading: Bool) -> Bool {
        allowed && online && !problem && !LibraryCare.busy(rescanning: rescanning, reading: reading)
    }

    /// Rescan pressed: its read's number, or nil when it may not go now.
    public mutating func rescan(allowed: Bool, online: Bool, problem: Bool, reading: Bool) -> Int? {
        guard rescanOpen(allowed: allowed, online: online, problem: problem, reading: reading) else { return nil }
        rescanning = true
        return readBegan()
    }

    /// The rescan `ticket` came to `how`.
    public mutating func rescanEnded(_ ticket: Int, _ how: Rescanned) -> AfterRescan {
        rescanning = false
        switch how {
        case .landed(let albums):
            readLanded(ticket)
            //? what another program changed may move the count (the web announces it only when the scan lists albums)
            return AfterRescan(readAgain: false, tell: albums > 0, mayHaveFinished: false)
        case .unanswered:
            return AfterRescan(readAgain: true, tell: true, mayHaveFinished: true)
        case .refused, .dropped:
            return .nothing
        }
    }

    // MARK: the runs

    /// The albums a kind's run would take now: from a scan to trust, narrowed, and not while the kind is behind.
    public func targets(_ kind: BulkTargets.Kind, _ albums: [ScanAlbum]) -> [ScanAlbum]? {
        LibraryCare.targets(kind, real: real, behind: behind[kind] != nil, inScope: LibraryCare.narrow(albums, narrow))
    }

    /// Start may be pressed for `kind`: its part, in reach, no run under way, and albums to take.
    public func startOpen(_ kind: BulkTargets.Kind, _ albums: [ScanAlbum], allowed: Bool, online: Bool) -> Bool {
        guard allowed, online, under == nil, let targets = targets(kind, albums) else { return false }
        return !targets.isEmpty
    }

    /// Start pressed: the run begun over the albums it takes now (asked again each time - so Start carries on with only
    /// those still without) - false, and nothing begun, when it may not start.
    public mutating func start(_ kind: BulkTargets.Kind, _ albums: [ScanAlbum], allowed: Bool, online: Bool) -> Bool {
        guard startOpen(kind, albums, allowed: allowed, online: online), let targets = targets(kind, albums) else {
            return false
        }
        under = Under(kind: kind, albums: targets, run: BulkTargets.start(targets.count))
        ended[kind] = nil
        return true
    }

    /// Asked before each album (runBulk's `stopped()`): the album to fetch now - or the run over, when Stop was pressed,
    /// the app went to the background, deadwax is out of reach, the permission went, or every album is done. Nothing
    /// while an album is out.
    public mutating func next(allowed: Bool, online: Bool) -> Next {
        guard var now = under, now.out == nil else { return .nothing }
        if now.stop == nil, !allowed { now.stop = .notAllowed }
        if now.stop == nil, !online { now.stop = .outOfReach }
        if now.stop != nil || now.run.done >= now.run.total {
            finish(now)
            return .ended(now.kind)
        }
        let album = now.albums[now.run.done]
        now.out = album
        under = now
        return .album(album)
    }

    /// The album out came to `step`: counted as the web counts it - true when Needs a look's count is told (it wrote,
    /// or may have). A 403 stops the run after it: Edit albums is no longer this person's.
    @discardableResult
    public mutating func finished(_ step: BulkTargets.Step) -> Bool {
        guard var now = under, now.out != nil else { return false }
        now.out = nil
        let tell: Bool
        switch step {
        case .answered(let outcome):
            now.run = BulkTargets.adding(now.run, outcome)
            tell = outcome.written > 0
        case .unanswered(let outcome):
            now.run = BulkTargets.adding(now.run, outcome)
            now.maybe = true
            tell = true
        case .forbidden(let outcome):
            now.run = BulkTargets.adding(now.run, outcome)
            if now.stop == nil { now.stop = .notAllowed }
            tell = false
        }
        under = now
        return tell
    }

    /// Stop pressed on `kind`'s run: once, while it runs (`stopBulk`).
    @discardableResult
    public mutating func stop(_ kind: BulkTargets.Kind) -> Bool {
        guard let now = under, now.kind == kind, now.stop == nil else { return false }
        stopUnder(.pressed)
        return true
    }

    /// The run over: its result kept, and - had it written anything, or may have - its kind behind the disk.
    private mutating func finish(_ now: Under) {
        var run = now.run
        run.running = false
        ended[now.kind] = Ended(run: run, stop: run.done < run.total ? now.stop : nil)
        if run.written > 0 || now.maybe { behind[now.kind] = reads }
        under = nil
    }

    // MARK: what the page draws

    /// `kind`'s run, under way or the last one's.
    public func run(_ kind: BulkTargets.Kind) -> BulkTargets.Run? {
        if let under, under.kind == kind { return under.run }
        return ended[kind]?.run
    }

    /// Stop was pressed (or the run otherwise told to stop) on `kind`'s run under way.
    public func stopping(_ kind: BulkTargets.Kind) -> Bool {
        guard let under, under.kind == kind else { return false }
        return under.stop != nil
    }

    /// The running run's button: "Stop after this album · 4 of 60", "Stopping after 4 of 60" - nil while `kind` isn't
    /// running.
    public func stopLabel(_ kind: BulkTargets.Kind) -> String? {
        guard let under, under.kind == kind else { return nil }
        return LibraryCare.stopLabel(under.run, stopping: under.stop != nil)
    }

    /// What `kind`'s last run did, said as it ended and kept until the next ("" while none, and while one runs) - the
    /// web's summary, and the phone's word for a stop of its own.
    public func result(_ kind: BulkTargets.Kind) -> String {
        guard under?.kind != kind, let ended = ended[kind] else { return "" }
        let summary = BulkTargets.summary(kind, ended.run)
        guard let stop = ended.stop, let said = LibraryCare.stopped(stop, kind: kind) else { return summary }
        return summary + " " + said
    }

    /// The screen stays on: a run under way and its page in front.
    public func keepsScreenOn(visible: Bool) -> Bool {
        visible && under != nil
    }
}

/// The parts of Library care each person sees (permissions.ts `careParts`): Rescan and In nobody's library Look after
/// the library's, the runs Edit albums' - an admin has both.
extension Managing {
    public struct CareParts: Sendable, Equatable, Decodable {
        public let shown: Bool
        public let rescan: Bool
        public let held: Bool
        public let bulk: Bool

        public init(shown: Bool, rescan: Bool, held: Bool, bulk: Bool) {
            self.shown = shown
            self.rescan = rescan
            self.held = held
            self.bulk = bulk
        }
    }

    /// permissions.ts `careParts(perms)`.
    public static func careParts(_ permissions: Set<Access.Permission>) -> CareParts {
        let library = permissions.contains(.library), edit = permissions.contains(.edit)
        return CareParts(shown: library || edit, rescan: library, held: library, bulk: edit)
    }

    /// In nobody's library is drawn (LibraryCare.tsx): logins on, and Look after the library.
    public static func heldShown(loginsOn: Bool, parts: CareParts) -> Bool {
        loginsOn && parts.held
    }
}

// MARK: In nobody's library

/// In nobody's library (HeldByNobody.tsx, myLibrary.ts - personal libraries, an admin's with logins on): every album in
/// the store nobody has in their library, and the downloads flagged for a look - each given to those who asked (Add for
/// them) or put away (Dismiss). `GET /library/held`, `POST /library/held/flags/{id}/add` and `.../dismiss`.
public enum Held {
    /// `HELD_SHOWN`: how many albums are listed before Show all.
    public static let shown = 20

    public static let title = "In nobody's library"
    public static let loading = "Loading…"
    public static let readFailed = "Couldn't read who has which albums."
    public static let flagged = "Flagged downloads"
    public static let addForThem = "Add for them"
    public static let dismiss = "Dismiss"
    public static let addFailed = "Couldn't add it for them."
    public static let dismissFailed = "Couldn't dismiss it."
    public static let showFewer = "Show fewer"

    /// "Show all 37".
    public static func showAll(_ count: Int) -> String { "Show all \(count)" }

    /// myLibrary.ts `heldByNobodyLine(count)`.
    public static func line(_ count: Int) -> String {
        count != 0
            ? "\(count) \(count == 1 ? "album" : "albums") nobody has in their library"
            : "Every album in the collection is in somebody's library."
    }

    /// myLibrary.ts `listed`: "a", "a and b", "a, b and c".
    public static func listed(_ items: [String]) -> String {
        guard items.count >= 2 else { return items.first ?? "" }
        return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
    }

    /// myLibrary.ts `flagWords(flag)`: who asked, and why nobody was given it.
    public static func flagWords(_ flag: Flag) -> String {
        let who = flag.users.isEmpty ? "Nobody" : listed(flag.users)
        let path = flag.path ?? ""
        return "\(who) asked for it. Every file was already in \(path.isEmpty ? "its folder" : path), which holds another "
            + "pressing or an untagged copy - so nobody was given it."
    }

    /// A flag as its row names it: "Post · Björk", "Unknown album".
    public static func flagName(_ flag: Flag) -> String {
        name(album: flag.album, artist: flag.artist)
    }

    /// An album as its row names it.
    public static func albumName(_ album: UnheldAlbum) -> String {
        name(album: album.album, artist: album.artist)
    }

    static func name(album: String?, artist: String?) -> String {
        let title = (album ?? "").isEmpty ? "Unknown album" : album ?? ""
        return [title, artist ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The name a write says: the flag's, or "The flag" for one the list no longer holds.
    public static func saidName(_ flag: Flag?) -> String {
        flag.map(flagName) ?? "The flag"
    }

    /// What Add for them and Dismiss say once deadwax has answered.
    public static func added(_ name: String, users: [String]) -> String {
        users.isEmpty ? "\(name): nobody to give it to" : "\(name): given to \(users.joined(separator: ", "))"
    }

    public static func dismissed(_ name: String) -> String { "\(name): dismissed" }

    /// The albums listed: the first `shown`, or all of them.
    public static func listedAlbums(_ albums: [UnheldAlbum], all: Bool) -> [UnheldAlbum] {
        all ? albums : Array(albums.prefix(shown))
    }

    /// Show all / Show fewer: nil while there are no more than `shown`.
    public static func showLabel(all: Bool, count: Int) -> String? {
        guard count > shown else { return nil }
        return all ? showFewer : showAll(count)
    }

    // MARK: the answers

    /// `GET /library/held`.
    public struct Answer: Decodable, Sendable, Equatable {
        public let count: Int
        public let albums: [UnheldAlbum]
        public let flags: [Flag]

        enum CodingKeys: String, CodingKey { case count, albums, flags }

        public init(count: Int, albums: [UnheldAlbum] = [], flags: [Flag] = []) {
            self.count = count
            self.albums = albums
            self.flags = flags
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            albums = fields.looseList(UnheldAlbum.self, .albums) ?? []
            flags = fields.looseList(Flag.self, .flags) ?? []
            count = fields.looseField(Int.self, .count) ?? albums.count
        }
    }

    /// An album in the store nobody holds (held.py `_album`) - its id the store index's.
    public struct UnheldAlbum: Decodable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let path: String
        public let artist: String
        public let album: String
        public let edition: String
        public let year: String
        public let releaseMbid: String?
        public let formats: [String]
        public let trackCount: Int

        enum CodingKeys: String, CodingKey {
            case id, path, artist, album, edition, year, formats
            case releaseMbid = "release_mbid"
            case trackCount = "track_count"
        }

        public init(id: Int, path: String, artist: String = "", album: String = "", edition: String = "", year: String = "",
                    releaseMbid: String? = nil, formats: [String] = [], trackCount: Int = 0) {
            self.id = id
            self.path = path
            self.artist = artist
            self.album = album
            self.edition = edition
            self.year = year
            self.releaseMbid = releaseMbid
            self.formats = formats
            self.trackCount = trackCount
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = try fields.decode(Int.self, forKey: .id)
            path = fields.looseField(String.self, .path) ?? ""
            artist = fields.looseField(String.self, .artist) ?? ""
            album = fields.looseField(String.self, .album) ?? ""
            edition = fields.looseField(String.self, .edition) ?? ""
            year = fields.looseField(String.self, .year) ?? ""
            releaseMbid = fields.looseField(String.self, .releaseMbid)
            formats = fields.looseList(String.self, .formats) ?? []
            trackCount = fields.looseField(Int.self, .trackCount) ?? 0
        }
    }

    /// A download flagged for a look (held.py `_flag`): every file was already in a folder holding another pressing or
    /// an untagged copy, so nobody was given it.
    public struct Flag: Decodable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let albumId: Int?
        public let artist: String?
        public let album: String?
        public let path: String?
        public let releaseMbid: String?
        public let users: [String]
        public let createdAt: Double?

        enum CodingKeys: String, CodingKey {
            case id, artist, album, path, users
            case albumId = "album_id"
            case releaseMbid = "release_mbid"
            case createdAt = "created_at"
        }

        public init(id: Int, albumId: Int? = nil, artist: String? = nil, album: String? = nil, path: String? = nil,
                    releaseMbid: String? = nil, users: [String] = [], createdAt: Double? = nil) {
            self.id = id
            self.albumId = albumId
            self.artist = artist
            self.album = album
            self.path = path
            self.releaseMbid = releaseMbid
            self.users = users
            self.createdAt = createdAt
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = try fields.decode(Int.self, forKey: .id)
            albumId = fields.looseField(Int.self, .albumId)
            artist = fields.looseField(String.self, .artist)
            album = fields.looseField(String.self, .album)
            path = fields.looseField(String.self, .path)
            releaseMbid = fields.looseField(String.self, .releaseMbid)
            users = fields.looseList(String.self, .users) ?? []
            createdAt = fields.looseField(Double.self, .createdAt)
        }
    }

    /// `POST /library/held/flags/{id}/add`: given to those who asked (never the break-glass admin).
    public struct Added: Decodable, Sendable, Equatable {
        public let added: Bool
        public let users: [String]

        enum CodingKeys: String, CodingKey { case added, users }

        public init(added: Bool, users: [String]) {
            self.added = added
            self.users = users
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            added = fields.looseField(Bool.self, .added) ?? false
            users = fields.looseList(String.self, .users) ?? []
        }
    }

    /// `POST /library/held/flags/{id}/dismiss`.
    public struct Dismissed: Decodable, Sendable, Equatable {
        public let dismissed: Bool

        enum CodingKeys: String, CodingKey { case dismissed }

        public init(dismissed: Bool) { self.dismissed = dismissed }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            dismissed = fields.looseField(Bool.self, .dismissed) ?? false
        }
    }

    /// Add for them or Dismiss.
    public enum Write: Sendable, Equatable {
        case add
        case dismiss

        /// What didn't work, said when deadwax gave no words of its own.
        public var failed: String { self == .add ? Held.addFailed : Held.dismissFailed }
    }

    /// In nobody's library's writes and reads - every decision the page makes, the App carrying them out: one write at
    /// a time (`acting`, HeldByNobody.tsx's - a second tap asks nothing more), never out of reach, nor before a read to
    /// trust (one begun since deadwax was last out of reach), nor while a read is out; and the list read again after
    /// each, whatever came of it.
    public struct Flow: Sendable, Equatable {
        /// The flag being dealt with.
        public private(set) var acting: Int?
        public private(set) var reads = 0
        public private(set) var landed = 0
        public private(set) var gap = 0

        public init() {}

        /// A read to trust.
        public var real: Bool { landed > gap }

        public mutating func readBegan() -> Int {
            reads += 1
            return reads
        }

        public mutating func readLanded(_ ticket: Int) {
            landed = max(landed, ticket)
        }

        /// deadwax went out of reach: what is on screen is how it was.
        public mutating func outOfReach() {
            gap = reads
        }

        /// A flag's buttons are on: in reach, a read to trust, nothing being dealt with, and no read out - the one
        /// after a write included, so a flag the write put away can't be pressed again before the list says so.
        public func open(online: Bool, reading: Bool) -> Bool {
            online && real && acting == nil && !reading
        }

        /// Add for them or Dismiss pressed on `flag`: false, and nothing asked, when it may not go now.
        public mutating func begin(_ flag: Int, online: Bool, reading: Bool) -> Bool {
            guard open(online: online, reading: reading) else { return false }
            acting = flag
            return true
        }

        /// The write answered, failed or never answered: the list is read again, and the next may go once it has been.
        public mutating func ended() {
            acting = nil
        }
    }
}

// MARK: the routes

extension DeadwaxClient {
    /// Rescan (`POST /library/rescan?tracks=false`): the per-folder cache dropped and every file read again, answered as
    /// the scan is (`libraryScan`'s form, its ETag kept for the next read). No bound on the server - Routes.timeouts
    /// gives it 300 s, and one that never answers may have finished.
    public func rescan() async throws -> (answer: ScanAnswer, etag: String?) {
        let built = request(Routes.rescan, query: [("tracks", "false")])
        let response = try await answer(built)
        return (try decode(ScanAnswer.self, response).with(headers: response), response.header("ETag"))
    }

    /// In nobody's library (`GET /library/held`): the albums nobody holds, and the flagged downloads.
    public func heldByNobody() async throws -> Held.Answer {
        try await call(Routes.held)
    }

    /// Add for them (`POST /library/held/flags/{id}/add`).
    public func addFlagged(_ id: Int) async throws -> Held.Added {
        try await call(Routes.heldAdd, path: ["flag_id": String(id)])
    }

    /// Dismiss (`POST /library/held/flags/{id}/dismiss`).
    public func dismissFlag(_ id: Int) async throws -> Held.Dismissed {
        try await call(Routes.heldDismiss, path: ["flag_id": String(id)])
    }
}
