import Foundation

/// The Release page's state, as rules (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 2 and 3.3): which answer
/// may draw, when a preview is due, when Apply is on, and what an apply that never answered leaves - the web's
/// MetadataEditor.tsx (its `latest()` requests, the 400 ms debounce, the Apply button's `disabled`) and section 2's
/// rules for a page that needs deadwax. Pure, so RetagModelTests holds it; the app's RetagModel drives it and draws.
///
/// NEWEST ANSWER. Each search, pressing load and preview takes the next number, and only the newest lands: a search
/// typed over another, a pressing picked while another loads, a preview sent before the fields changed again.
///
/// THE PREVIEW. Every change to what Apply would send - a field, the cover toggle, a pressing landing or failing, the
/// folder read again - is an edit; the preview of the newest edit is sent `Retag.previewDebounceMs` after it, unless
/// another came since, a pressing's tracklist is still on its way (a preview of a release with no tracklist would say
/// the opposite of what Apply does), or deadwax is out of reach.
///
/// APPLY. On only with a preview of the newest edit in hand that changes something, nothing loading or planning,
/// deadwax in reach, and the folder read since the last gap or apply. The plan's `problems` are warnings, as the web
/// draws them (a track count that differs, files the tracklist didn't reach) - never a refusal, as the web's Apply
/// isn't refused by them either.
///
/// THE LONG WAIT. An apply can hold its answer for minutes, and deadwax carries on when the phone goes; so an apply
/// whose answer never came (`unanswered`) - or came as a 5xx, deadwax failing after it may have written, or a proxy
/// giving up on the wait - is said as maybe finished, and the folder is read again before anything is offered - never
/// the same Apply on the old preview. The cover alone is the same (`beginCover`, `coverEnded`). A read of the folder
/// that fails ends the wait for it (`couldNotRead`): said, with Look again, and nothing offered until one lands.
///
/// BACK IN REACH. Everything is asked again (section 2): the folder read, a search that failed or never finished
/// searched again (`searchesOnReturn`), the tagged pressing's tracklist loaded if it never came (Retag.currentToLoad).
public struct RetagFlow: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// deadwax answered the write (with what it did, or with files it couldn't write).
        case applied
        /// deadwax refused it with a 4xx - nothing was written.
        case refused
        /// No answer that says nothing was written: none came (the phone went, the connection dropped, it took too
        /// long), or a 5xx - deadwax failing after the files were written and the folder moved, or a reverse proxy
        /// answering 502 or 504 while the scan wait runs on. deadwax may have finished.
        case unanswered
    }

    // MARK: newest answer

    public private(set) var searches = 0
    public private(set) var loads = 0
    /// Changes to what Apply would send - the newest is the only one a preview may describe.
    public private(set) var edits = 0
    /// The edit the preview in hand describes (nil: none in hand).
    public private(set) var planFor: Int?
    /// The edit whose preview failed - said, not retried until the next edit.
    public private(set) var failedFor: Int?

    // MARK: what's under way

    public private(set) var searching = false
    /// A search has finished, answered or failed (a cancelled one doesn't count).
    public private(set) var searched = false
    /// The newest search to finish failed - asked again when deadwax is back.
    public private(set) var searchFailed = false
    /// A pressing's tracklist is on its way: no preview, no Apply.
    public private(set) var loadingRelease = false
    public private(set) var applying = false
    /// The cover alone is being saved: no preview, no Apply, no second save.
    public private(set) var savingCover = false
    /// deadwax is in reach (Reachability).
    public private(set) var online = true
    /// The folder must be read again before Apply comes back: deadwax came back into reach, or a write ended.
    public private(set) var needsRead = false
    /// The read `needsRead` waits for failed: nothing is planning (the wait has ended, said with Look again), and
    /// nothing is offered until a read lands.
    public private(set) var readFailed = false
    /// The last write never answered: deadwax may have finished it - said until the folder is read again.
    public private(set) var mayHaveFinished = false

    public init(online: Bool = true) {
        self.online = online
    }

    // MARK: searching

    public mutating func beginSearch() -> Int {
        searches += 1
        searching = true
        return searches
    }

    /// Whether the search `ticket` may still draw.
    public func isNewest(search ticket: Int) -> Bool { ticket == searches }

    /// The search `ticket` is over (answered, or `failed`) - only the newest's end stops the spinner and counts.
    public mutating func searchEnded(_ ticket: Int, failed: Bool = false) {
        guard ticket == searches else { return }
        searching = false
        searched = true
        searchFailed = failed
    }

    /// The search `ticket` was cancelled: neither an answer nor a failure - the spinner stops, nothing else changes.
    public mutating func searchCancelled(_ ticket: Int) {
        if ticket == searches { searching = false }
    }

    /// Back in reach: whether to search again - the last search failed, or none ever finished on a page that searches
    /// as it opens (`atOnce`: Retag.searchesAtOnce). Never over one on its way.
    public func searchesOnReturn(atOnce: Bool) -> Bool {
        !searching && (searchFailed || (!searched && atOnce))
    }

    // MARK: a pressing's tracklist

    public mutating func beginLoad() -> Int {
        loads += 1
        loadingRelease = true
        return loads
    }

    /// The load `ticket` is over: true when it is the newest (its answer lands, and the change it makes is an edit -
    /// `changed()`); false when another pick has taken over.
    public mutating func loadEnded(_ ticket: Int) -> Bool {
        guard ticket == loads else { return false }
        loadingRelease = false
        return true
    }

    // MARK: the preview

    /// What Apply would send has changed: returns the edit's number, for the preview it schedules.
    @discardableResult
    public mutating func changed() -> Int {
        edits += 1
        return edits
    }

    /// The debounce's end: whether the preview of `edit` should go now - still the newest, nothing loading, in reach,
    /// no write under way, and the folder read since the last gap or write (a preview of the folder as it was would
    /// describe a path the apply may have moved).
    public func due(_ edit: Int) -> Bool {
        edit == edits && !loadingRelease && online && !needsRead && !applying && !savingCover
    }

    /// The preview of `edit` answered: true when it may draw (still the newest edit).
    public mutating func answered(_ edit: Int) -> Bool {
        guard edit == edits else { return false }
        planFor = edit
        failedFor = nil
        return true
    }

    /// The preview of `edit` failed: true when it is said (still the newest edit).
    public mutating func failed(_ edit: Int) -> Bool {
        guard edit == edits else { return false }
        failedFor = edit
        planFor = nil
        return true
    }

    /// A preview is due or on its way for what the page shows now (`planningLabel` says which step) - the old preview
    /// isn't drawn meanwhile. Never while a write runs (no preview goes then) or once the read it waits for has failed.
    public var planning: Bool {
        online && !applying && !readFailed && (loadingRelease || (planFor != edits && failedFor != edits))
    }

    /// The preview in hand describes what Apply would send now.
    public var current: Bool { planFor == edits && !loadingRelease }

    // MARK: Apply

    /// MetadataEditor's `disabled={!plan || plan.empty || planning || applying || loadingRelease}`, with section 2's
    /// rules: in reach, no cover being saved, and the folder read since the last gap or write.
    public func canApply(_ plan: RetagPlan?) -> Bool {
        guard let plan, !plan.empty else { return false }
        return current && !planning && !applying && !savingCover && !loadingRelease && online && !needsRead
    }

    /// Apply pressed: false when it isn't on.
    public mutating func beginApply(_ plan: RetagPlan?) -> Bool {
        guard canApply(plan) else { return false }
        applying = true
        mayHaveFinished = false
        return true
    }

    /// (Phase 8, slice 2) Tags' Apply - a tag edit's preview and apply are the same plan/execute pair, so the same
    /// flow: TrackTagEditor's `disabled={!plan || plan.empty || plan.problems.length > 0 || planning || applying ||
    /// problemCount > 0}` (TagEditWords.canApply), with section 2's rules - the preview the newest edit's, in reach, and
    /// the files read since the last gap or write. A plan's problems refuse the whole batch here, as the server does.
    public func canApply(_ plan: TagEditPlan?, problems: Int) -> Bool {
        TagEditWords.canApply(plan: plan, planning: planning, applying: applying, problems: problems)
            && current && !savingCover && online && !needsRead
    }

    /// Tags' Apply pressed: false when it isn't on.
    public mutating func beginApply(_ plan: TagEditPlan?, problems: Int) -> Bool {
        guard canApply(plan, problems: problems) else { return false }
        applying = true
        mayHaveFinished = false
        return true
    }

    /// The apply is over. Whatever came of it, the preview in hand no longer describes the folder: an answered one
    /// changed it (or some of it), and an unanswered one may have. Only a refusal - nothing written - keeps it.
    public mutating func applyEnded(_ outcome: Outcome) {
        applying = false
        wrote(outcome)
    }

    /// How a write's failure is taken (Apply's, the cover's): a 4xx - deadwax refusing before it wrote anything - is
    /// `refused`; anything else is `unanswered`, the write may have gone ahead on the server: nothing answering, or not
    /// in time, and every 5xx - `_retag_apply` answers 500 for an exception raised after the files are written and the
    /// folder moved, and a reverse proxy answers 502 or 504 while the scan wait runs on.
    public static func outcome(of error: any Error) -> Outcome {
        if case .answered(let answer)? = error as? APIFailure, (400..<500).contains(answer.status) { return .refused }
        return .unanswered
    }

    // MARK: the cover alone

    /// Replace cover only / Save cover only may be pressed: in reach, no write under way, the folder read since the last
    /// gap or write.
    public var canSaveCover: Bool { online && !applying && !savingCover && !needsRead }

    /// The cover alone pressed: false when it isn't on.
    public mutating func beginCover() -> Bool {
        guard canSaveCover else { return false }
        savingCover = true
        mayHaveFinished = false
        return true
    }

    /// The cover alone is over: as an apply's end - written or maybe written, the folder read again (its cover is
    /// part of what the preview describes); refused, nothing changed.
    public mutating func coverEnded(_ outcome: Outcome) {
        savingCover = false
        wrote(outcome)
    }

    private mutating func wrote(_ outcome: Outcome) {
        switch outcome {
        case .refused:
            return
        case .applied:
            needsRead = true
        case .unanswered:
            needsRead = true
            mayHaveFinished = true
        }
        readFailed = false
        planFor = nil
        changed()
    }

    /// Another part of Edit album wrote to the folder, or may have (Release's apply or its cover beside Tags, a tag
    /// edit beside Release): the preview in hand describes the files as they were, so nothing is offered until the
    /// folder has been read again - without this page's "may have finished", which is the writer's to say.
    public mutating func folderChanged() {
        needsRead = true
        readFailed = false
        planFor = nil
        changed()
    }

    // MARK: in and out of reach

    /// deadwax went out of reach: every write off, the page drawn as it was.
    public mutating func wentAway() {
        online = false
    }

    /// Back in reach: everything asked again before a control comes back on - never a write against an answer from
    /// before the gap.
    public mutating func cameBack() {
        guard !online else { return }
        online = true
        needsRead = true
        readFailed = false
        changed()
    }

    /// The folder was read again: Apply may come back once the preview of what it now holds is in.
    public mutating func read() {
        needsRead = false
        readFailed = false
        mayHaveFinished = false
        changed()
    }

    /// The read the folder needed failed: the wait for it ends - said, with Look again - and nothing is offered until a
    /// read lands. Nothing, when no read was needed.
    public mutating func couldNotRead() {
        guard needsRead else { return }
        readFailed = true
    }

    /// Where the album is after an apply that never answered (or after one that answered without saying where): the
    /// folder it was in while the scan still lists it, else the plan's target if the scan lists that - the rename
    /// went through - else where it was (the editor then says the scan doesn't list it yet).
    public static func whereAfter(_ scan: ScanAnswer, was path: String, target: String?) -> String {
        if scan.album(at: path) != nil { return path }
        if let target, !target.isEmpty, scan.album(at: target) != nil { return target }
        return path
    }
}

/// The Release page's words that are the web's (ui/src/lib/retagPlan.ts, run as it is by the exporter; and
/// components/MetadataEditor.tsx's own lines, read out of it by the exporter) - held by edit-vectors.json.
public enum RetagWords {
    // MARK: retagPlan.ts

    /// `planningLabel(loadingRelease)`.
    public static func planningLabel(loadingRelease: Bool) -> String {
        loadingRelease ? "Fetching the tracklist…" : "Working out the changes…"
    }

    public static let previewFailed = "Couldn't work out the changes."
    public static let applyFailed = "Couldn't apply the changes."

    /// `moveLabel(plan)`.
    public static func moveLabel(_ plan: RetagPlan) -> String { plan.merge ? "Merge" : "Folder" }

    /// `renameWaitWords(plan)`: the pause before the rename, said before the click - nil when there is none.
    public static func renameWait(_ plan: RetagPlan) -> String? {
        guard plan.moves, plan.renameWait != 0 else { return nil }
        if plan.renameBy == "navidrome" {
            return plan.changedFileCount == 0
                ? "The tags were written by an earlier apply. Renames the folder once Navidrome has scanned them, so "
                    + "Navidrome keeps this album's plays, ratings and favourites."
                : "Writes the tags first and renames the folder once Navidrome has scanned them (usually a few seconds), "
                    + "so Navidrome keeps this album's plays, ratings and favourites."
        }
        return "Writes the tags first and renames \(WebText.number(plan.renameWait))s later, so Navidrome keeps this "
            + "album's plays, ratings and favourites."
    }

    /// `discWords(discs)`: "disc 2", "discs 1, 2, 3".
    public static func discWords(_ discs: [Int]) -> String {
        "disc\(discs.count > 1 ? "s" : "") \(discs.map(String.init).joined(separator: ", "))"
    }

    /// `mergeWords(plan)`: what a merge moves where - nil for no merge.
    public static func merge(_ plan: RetagPlan) -> String? {
        guard plan.merge, let detail = plan.mergeDetail else { return nil }
        return "Moves \(discWords(detail.discsHere)) in beside \(discWords(detail.discsThere)), which "
            + "\(detail.discsThere.count > 1 ? "are" : "is") already there as the same release, and removes this folder "
            + "once it is empty."
            + (detail.keptBack.isEmpty ? ""
               : " \(detail.keptBack.joined(separator: ", ")) stays behind - there's one of that name already.")
    }

    public static let nothingToChange = "Nothing to change."

    /// `filesWord(n)`.
    public static func files(_ count: Int) -> String { "\(count) \(count == 1 ? "file" : "files")" }

    /// `changeSummary(plan)`.
    public static func changeSummary(_ plan: RetagPlan) -> String {
        "\(plan.changedFileCount) of \(files(plan.fileCount)) would change"
            + (plan.art.action == "download" ? ", the cover would be downloaded" : "")
            + (plan.art.action == "replace" ? ", the cover would be replaced" : "")
            + (plan.moves ? (plan.merge ? ", and the files would join the other disc" : ", and the folder would be renamed") : "")
    }

    /// `applyingLabel(plan)`.
    public static func applying(_ plan: RetagPlan?) -> String {
        guard let plan, plan.renameWait != 0 else { return "Applying" }
        return plan.renameBy == "navidrome" ? "Applying, waiting for Navidrome"
            : "Applying, renaming in \(WebText.number(plan.renameWait))s"
    }

    /// `writeFailedWords(failed)`.
    public static func writeFailed(_ failed: Int) -> String { "Couldn't write \(files(failed))." }

    /// `appliedWords(results)`: what an apply did, as one sentence.
    public static func applied(_ results: RetagResults) -> String {
        let parts = [
            results.tagged != 0 ? "updated the tags in \(files(results.tagged))" : "",
            (results.artWritten ?? "").isEmpty ? "" : "saved \(results.artWritten ?? "")",
            results.merged ? "moved it in beside the other discs"
                : (results.movedTo ?? "").isEmpty ? "" : "moved the folder to match its tags",
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        return upperFirst(parts) + "."
    }

    /// `.replace(/^./, c => c.toUpperCase())`: the first UTF-16 unit's character uppercased, as JavaScript does it.
    static func upperFirst(_ text: String) -> String {
        guard let first = text.unicodeScalars.first else { return text }
        //? `.` matches one code unit that isn't a line terminator; a scalar beyond the BMP is two, of which the first
        //? (a lone surrogate) has no uppercase - left as it is
        if first.value > 0xFFFF || [0x0A, 0x0D, 0x2028, 0x2029].contains(first.value) { return text }
        return String(first.properties.uppercaseMapping) + String(text.unicodeScalars.dropFirst())
    }

    // MARK: MetadataEditor.tsx's own

    public static let searching = "Searching MusicBrainz…"
    public static let noReleases = "No releases found for that search."
    public static let currentMissing = "The release this album is matched to isn't in these results."
    public static let notSearched = "Search to match this album to a release, or just edit the fields."
    /// The search's 503 (MusicBrainzUnavailable).
    public static let searchAway = "MusicBrainz is unreachable right now, so there's nothing to match against. "
        + "You can still correct the fields by hand."
    /// A pressing's tracklist's 503.
    public static let tracklistAway = "MusicBrainz couldn't be reached for that release's tracklist, so it can't be "
        + "applied yet. You can still correct the fields by hand."
    public static let searchFailed = "The search didn't work."
    public static let releaseFailed = "Couldn't load that release."
    public static let coverFailed = "Couldn't save the cover."
    public static let fieldsHint = "Blank fields are left alone rather than cleared. The folder is named after the "
        + "original year and the edition, so a remaster files under the album's own year."
    public static let current = "Current"
    public static let apply = "Apply"
    public static let fine = "It's fine as it is"
    public static let markingFine = "Marking it fine…"
    public static let askAgain = "Ask about it again"

    /// "Marked fine: …" - what was marked fine that the album still has, by the server's labels.
    public static func markedFine(_ labels: [String]) -> String {
        "Marked fine: \(labels.joined(separator: ", "))"
    }

    /// The Edition field's placeholder: what the preview says the edition will be, else how it is decided.
    public static func editionPlaceholder(_ plan: RetagPlan?) -> String {
        let label = plan?.editionLabel ?? ""
        return label.isEmpty ? "worked out from the release" : label
    }

    /// The Original year field's placeholder: the year, else "year".
    public static func originalPlaceholder(_ year: String) -> String { year.isEmpty ? "year" : year }

    /// The cover toggle's label: replacing the cover there, or downloading one.
    public static func coverToggle(existing: String?) -> String {
        (existing ?? "").isEmpty ? "Download cover art" : "Replace \(existing ?? "")"
    }

    /// The line under it, with the size the cover would be saved at.
    public static func coverHint(existing: String?, size: String?) -> String {
        ((existing ?? "").isEmpty ? "From the Cover Art Archive, saved into the album folder"
            : "This album already has a cover - only replace it if the new one is better")
            + ((size ?? "").isEmpty ? "" : " — \(size == "full" ? "at full size" : "at \(size ?? "") × \(size ?? "")")")
    }

    /// The cover-only button, and what it does.
    public static func coverOnly(hasArt: Bool) -> String { hasArt ? "Replace cover only" : "Save cover only" }
    public static func coverOnlyHint(hasArt: Bool) -> String {
        hasArt ? "Replace the cover on disk with this one, and change nothing else."
            : "Save this cover into the album folder, and change nothing else."
    }

    /// What the cover alone did: "Saved cover.jpg, replacing cover.png."
    public static func coverSaved(_ fetched: CoverFetched) -> String {
        "Saved \(fetched.written ?? "")\((fetched.replaced ?? "").isEmpty ? "" : ", replacing \(fetched.replaced ?? "")")."
    }

    // the comparison's (ArtComparison's open, MetadataEditor.tsx's full-size pair)
    public static let compareCurrent = "Current"
    public static let compareNoCover = "No cover on disk"
    public static let compareFromThis = "From this release"
    public static let compareFromTagged = "From the release it's tagged with"
    public static let compareArchiveNone = "The Cover Art Archive has no front cover for this release, or is unreachable"
    public static let comparePick = "Pick a release to see its cover"

    /// A preview's problem or an apply's, as a sentence (`asSentence`).
    public static func problem(_ text: String) -> String { ErrorWords.asSentence(text) }

    /// The search's failure: MusicBrainz away (the route's 503 - the web's MusicBrainzUnavailable) in the editor's own
    /// words, anything else as Edit album says a failure (`EditWords.said`).
    public static func searchError(_ error: any Error, admin: Bool) -> String {
        musicBrainzAway(error) ? searchAway : EditWords.said(error, failed: searchFailed, admin: admin)
    }

    /// A pressing's tracklist's failure, the same way.
    public static func tracklistError(_ error: any Error, admin: Bool) -> String {
        musicBrainzAway(error) ? tracklistAway : EditWords.said(error, failed: releaseFailed, admin: admin)
    }

    /// The MusicBrainz routes' 503 (api/musicbrainz.ts `asUnavailable`: any 503 from them).
    static func musicBrainzAway(_ error: any Error) -> Bool {
        if case .answered(let answer)? = error as? APIFailure { return answer.status == 503 }
        return false
    }

    /// An apply's problems that aren't the preview's (on screen already): MetadataEditor's `appliedProblems`.
    public static func newProblems(_ results: RetagResults, over plan: RetagPlan?) -> [String] {
        results.problems.filter { problem in !(plan?.problems ?? []).contains { WebText.same($0, problem) } }
    }
}

/// Edit album's words that are the phone's own - what only the phone does (a sheet, its Close, being out of reach,
/// an apply that never answered, pages where the web has one panel). Section 1: the app's sentence case.
public enum EditWords {
    /// The sheet's title (EditPanel.tsx's) and its Close.
    public static let title = "Edit album"
    public static let close = "Close"
    /// The album's ••• (its last section, after Album info) and its symbol.
    public static let menuItem = "Edit album"
    public static let symbol = "square.and.pencil"

    /// Opened while deadwax can't be reached.
    public static let needsDeadwax = "Managing needs deadwax. This opens once it's back."
    /// Gone out of reach while open: the banner.
    public static let outOfReach = "deadwax is out of reach - this is how it was, and nothing here can change until "
        + "it's back."
    /// An apply whose answer never came.
    public static let mayHaveFinished = "deadwax may have finished this - looking again"

    /// Several folders found by name: the only section until one is picked.
    public static let whichFolder = "Which folder is this album?"
    public static let folder = "Folder"
    public static let lookAgain = "Look again"
    public static let chooseFolder = "Choose the folder"
    /// Choose the folder's search field.
    public static let folderPrompt = "Folder, artist or album"

    /// Close with typed work.
    public static let discardTitle = "Discard changes?"
    public static let discard = "Discard"
    public static let keepEditing = "Keep editing"

    /// The root's sections and rows.
    public static let needsALook = "Needs a look"
    public static let edit = "Edit"
    public static let release = "Release"
    public static let notMatched = "Not matched to a release"
    public static let chooseRelease = "Choose a release"
    public static let compareCovers = "Compare covers…"
    public static let changes = "Changes"
    public static let whatApplyDoes = "What Apply does"
    public static let fields = "Fields"
    public static let cover = "Cover"
    public static let artist = "Artist"
    public static let album = "Album"
    public static let year = "Year"
    public static let originalYear = "Original year"
    public static let edition = "Edition"
    public static let coverFullScreen = "The cover, full screen"

    /// The editor slice 3 hasn't brought to the phone (Delete album…): a row that opens the album in the web app,
    /// saying so, until its own slice lands.
    public static let inWebApp = "In the web app"
    public static let inWebAppLine = "Delete album… opens the album in the web app, in Safari, until the app has it."
    public static let deleteAlbum = "Delete album…"

    /// A row's track count: "12 tracks".
    public static func tracks(_ count: Int) -> String { "\(count) \(count == 1 ? "track" : "tracks")" }

    /// The root's Artwork row: what the folder holds - "Cover, CD art", "Cover", "CD art", "No cover".
    public static func artworkValue(_ album: ScanAlbum) -> String {
        let parts = [album.art.isEmpty ? "" : "Cover", album.discArt.isEmpty ? "" : "CD art"].filter { !$0.isEmpty }
        return parts.isEmpty ? "No cover" : parts.joined(separator: ", ")
    }

    /// The root's Lyrics row: "8 of 12".
    public static func lyricsValue(_ album: ScanAlbum) -> String { "\(album.lyricsCount) of \(album.trackCount)" }

    /// The header's second line: artist · edition.
    public static func byline(_ album: ScanAlbum) -> String {
        [album.artist, album.edition].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The header's third line: formats and track count ("FLAC · 12 tracks · 2 discs").
    public static func facts(_ album: ScanAlbum) -> String {
        [album.formats.joined(separator: ", "), tracks(album.trackCount),
         album.discCount > 1 ? "\(album.discCount) discs" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The Release row's value: the pressing the folder is tagged with, as far as it is known.
    public static func releaseValue(_ album: ScanAlbum, pressing: PageRelease?) -> String {
        if let pressing, Retag.isCurrent(pressing, album.releaseMbid) {
            let described = Retag.describe(pressing)
            return described.isEmpty ? (pressing.title ?? "") : described
        }
        return album.releaseMbid.isEmpty ? notMatched : "Matched to MusicBrainz"
    }

    /// A row of Choose a release, read by VoiceOver as one: its title, artist, detail, track count and Current.
    public static func releaseRow(_ release: PageRelease, current: Bool) -> String {
        [release.title ?? "", Credits.name(release.artistCredit), Retag.detail(release), Retag.trackWords(release),
         current ? RetagWords.current : ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// After an apply moved the album to a new id in Navidrome, said over the page (announced).
    public static let followed = "The album page now shows the album as Navidrome has it after the change."

    /// The library's scan couldn't be read (libraryCare.ts READ_FAILED, the web's EditPanel's `failed`).
    public static let readFailed = "Couldn't read the library."
    /// A Managing page's words for a 403 (permissions.ts NO_PERMISSION): the server refused for itself.
    public static let noPermission = "This page needs a permission an admin hasn't given you - ask one if you need it."

    /// A Folder menu with no folder chosen yet.
    public static let pickOne = "Choose…"
    /// Choose the folder: the scan being read.
    public static let readingLibrary = "Reading the library…"
    /// A pressing's row while its tracklist loads (VoiceOver).
    public static let loadingTracklist = "Loading its tracklist"
    /// The cover alone being saved.
    public static let savingCover = "Saving the cover…"
    /// It's fine as it is, and Ask about it again, refused or unanswered (the web says nothing: its rejection goes
    /// unhandled).
    public static let markFineFailed = "Couldn't mark it fine."
    public static let askAgainFailed = "Couldn't put it back in Needs a look."
    /// A Choose a release row whose track count differs from the folder's (the web's amber `mismatch`), to VoiceOver.
    public static func countDiffers(_ album: ScanAlbum) -> String {
        "The folder has \(tracks(album.trackCount))."
    }

    /// A row of Choose the folder, read by VoiceOver as one: album, artist, path.
    public static func folderRow(_ album: ScanAlbum) -> String {
        [album.album, album.artist, album.path].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Edit album's way of saying a failure (notes/ios-specs/phase8-managing.md 2, "Errors"): a 403 as a Managing page
    /// says it (NO_PERMISSION); a refusal deadwax wrote words for, as it came - the managing pages show deadwax's words
    /// (CLAUDE.md), with its own why for whoever runs deadwax; everything else - nothing answered, a timeout, a 5xx with
    /// no words - in a listener's words (ErrorWords.notice, `failed` in place of what didn't work), the transport's own
    /// words in brackets only for whoever runs deadwax.
    public static func said(_ error: any Error, failed: String, admin: Bool) -> String {
        if case .answered(let answer)? = error as? APIFailure, answer.status != 401 {
            if answer.status == 403 { return noPermission }
            let detail = ErrorWords.trim(answer.detail ?? "")
            if !detail.isEmpty {
                let line = ErrorWords.asSentence(detail)
                let why = ErrorWords.trim(answer.why ?? "")
                return admin && !why.isEmpty && !ErrorWords.same(why, detail) ? "\(line) (\(why))" : line
            }
        }
        return ErrorWords.notice("", error, admin: admin, failed: failed)
    }

    /// What a write's failure says beside RetagFlow's outcome: a refusal (a 4xx) as `said`; one that may have gone ahead
    /// (`unanswered`: no answer, or a 5xx) says deadwax's own words when it sent some - an exception's, or the Cover Art
    /// Archive out of reach - and nothing more: the line over the page says it may have finished, and the folder is
    /// read again.
    public static func writeFailure(_ error: any Error, failed: String, admin: Bool) -> String? {
        if RetagFlow.outcome(of: error) == .refused { return said(error, failed: failed, admin: admin) }
        guard case .answered(let answer)? = error as? APIFailure, !ErrorWords.trim(answer.detail ?? "").isEmpty else {
            return nil
        }
        return said(error, failed: failed, admin: admin)
    }
}
