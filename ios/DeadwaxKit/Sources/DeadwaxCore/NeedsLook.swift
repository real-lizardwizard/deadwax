import Foundation

// Needs a look on the phone (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; notes/ios.md "Needs a look on the
// phone"): the web's review queue - ui/src/lib/needsLook.ts and metadataQueue.ts run as they are, app/NeedsALook.tsx's
// own rules (what the page draws from them) and app/useQueueSummary.ts's (the count) read out of their source - held by
// Tests/DeadwaxCoreTests/Fixtures/care/care-vectors.json (ios/scripts/export-care-vectors.cjs, which
// ui/test/ioscare.sim.cjs runs with --check). Pure: the App's NeedsLookModel asks and keeps, QueueCountModel asks the
// count; every rule they follow is here.

/// needsLook.ts: the list, its facets, a session's rows and marks, the steps through it, and the page's words.
public enum NeedsLook {
    // MARK: the facets

    /// `NEW_FACET`: new imports - not an issue code (the scan's codes are snake_case words, never this).
    public static let newFacet = "new"
    /// `IGNORED_FACET`: albums whose issues were all accepted as they are - not an issue code either.
    public static let ignoredFacet = "ignored"
    /// `MARKED_FINE`: the Marked fine facet's words, and a row's mark for an album accepted as it is.
    public static let markedFine = "Marked fine"
    /// `IGNORED_HINT`: the Marked fine facet's hint.
    public static let ignoredHint = "Albums you marked fine as they are, with \u{201C}It's fine as it is\u{201D}"

    /// `isIgnoredOnly`: every issue found on it accepted - one found issue at least is marked fine, and none is
    /// outstanding. What Marked fine lists: the one way back to such an album's editor when Navidrome doesn't list it.
    public static func isIgnoredOnly(_ album: ScanAlbum) -> Bool {
        album.issues.contains { code in album.ignoredIssues.contains { WebText.same($0, code) } }
            && MetadataQueue.outstanding(album).isEmpty
    }

    /// A facet (the web's chip): what it narrows to (nil: All), its words, how many albums it has, and its hint.
    public struct Facet: Sendable, Equatable, Hashable, Identifiable {
        public let id: String?
        public let label: String
        public let count: Int
        public let hint: String?

        public init(id: String?, label: String, count: Int, hint: String? = nil) {
            self.id = id
            self.label = label
            self.count = count
            self.hint = hint
        }
    }

    /// `summaryTotal`: how many albums All lists - what the count says over the same scan.
    public static func summaryTotal(_ albums: [ScanAlbum]) -> Int {
        MetadataQueue.queueAlbums(albums, nil).count
    }

    /// `facets`: All N; Newly added N, only when there is one; one per kind of issue with an album outstanding, the
    /// most albums first, then by label (localeCompare); last, Marked fine N, only when there is one - never in All.
    public static func facets(_ albums: [ScanAlbum], _ issueTypes: [String: MetadataIssueType]) -> [Facet] {
        let waiting = MetadataQueue.queueAlbums(albums, nil)
        let fresh = waiting.filter(MetadataQueue.isNewImport).count
        //? a JS Map: its keys by code unit, in the order first set
        var order: [String] = []
        var counts: [[UInt16]: Int] = [:]
        for album in waiting {
            for code in MetadataQueue.outstanding(album) {
                let key = Array(code.utf16)
                if counts[key] == nil { order.append(code) }
                counts[key, default: 0] += 1
            }
        }
        let issues = order.enumerated().map { (offset, code) -> (Int, Facet) in
            let hint = issueTypes[code]?.hint ?? ""
            return (offset, Facet(id: code, label: MetadataQueue.label(code, issueTypes), count: counts[Array(code.utf16)] ?? 0,
                                  hint: hint.isEmpty ? nil : hint))
        }.sorted { (one, other) -> Bool in
            let (a, b) = (one.1, other.1)
            if a.count != b.count { return b.count - a.count < 0 }
            let label = WebCollation.compare(a.label, b.label)
            if label != 0 { return label < 0 }
            return one.0 < other.0
        }.map(\.1)
        let ignored = albums.filter(isIgnoredOnly).count
        return [Facet(id: nil, label: "All", count: waiting.count)]
            + (fresh > 0 ? [Facet(id: newFacet, label: "Newly added", count: fresh)] : [])
            + issues
            + (ignored > 0 ? [Facet(id: ignoredFacet, label: markedFine, count: ignored, hint: ignoredHint)] : [])
    }

    /// `facetAlbums`: the albums a facet lists, in queueAlbums' order - the new imports, one kind of issue, or the albums
    /// whose issues were all accepted, by artist then album.
    public static func facetAlbums(_ albums: [ScanAlbum], _ facet: String?) -> [ScanAlbum] {
        if let facet, WebText.same(facet, newFacet) {
            return MetadataQueue.queueAlbums(albums, nil).filter(MetadataQueue.isNewImport)
        }
        if let facet, WebText.same(facet, ignoredFacet) {
            return albums.enumerated().filter { isIgnoredOnly($0.element) }.sorted { (one, other) -> Bool in
                let artist = WebCollation.compare(one.element.artist, other.element.artist)
                if artist != 0 { return artist < 0 }
                let name = WebCollation.compare(one.element.album, other.element.album)
                if name != 0 { return name < 0 }
                return one.offset < other.offset
            }.map(\.element)
        }
        return MetadataQueue.queueAlbums(albums, facet)
    }

    /// `facetShown`: the facet asked for while it has albums, else All - a facet emptied falls back.
    public static func facetShown(_ chips: [Facet], _ facet: String?) -> String? {
        guard let facet else { return nil }
        return chips.contains { chip in chip.id.map { WebText.same($0, facet) } == true && chip.count > 0 } ? facet : nil
    }

    // MARK: a session

    /// What became of an album during a session, said in its row (`RowMark`).
    public enum RowMark: String, Sendable, Equatable, Hashable {
        case fixed, ignored, deleted

        /// `MARK_WORDS`.
        public var words: String {
            switch self {
            case .fixed: return "Fixed"
            case .ignored: return markedFine
            case .deleted: return "Deleted"
            }
        }
    }

    /// A session's row (`SessionRow`): where the album lives now, the album as last known, as listed when the session
    /// began, its mark, and whether a write has told the page of it.
    public struct SessionRow: Sendable, Equatable {
        public var path: String
        public var album: ScanAlbum
        public let listed: ScanAlbum
        public var mark: RowMark?
        public var heard: Bool

        public init(path: String, album: ScanAlbum, listed: ScanAlbum, mark: RowMark? = nil, heard: Bool = false) {
            self.path = path
            self.album = album
            self.listed = listed
            self.mark = mark
            self.heard = heard
        }
    }

    /// `LookSession`: the list as shown when a row was opened, fixed - its rows, the current one, and the facet.
    public struct Session: Sendable, Equatable {
        public var rows: [SessionRow]
        public var index: Int
        public let facet: String?

        public init(rows: [SessionRow], index: Int, facet: String?) {
            self.rows = rows
            self.index = index
            self.facet = facet
        }

        /// The current row.
        public var current: SessionRow? { rows.indices.contains(index) ? rows[index] : nil }
    }

    /// `startSession`: a session from the list as shown, the row at `path` current - nil when it isn't listed.
    public static func startSession(_ list: [ScanAlbum], path: String, facet: String?) -> Session? {
        guard let index = list.firstIndex(where: { WebText.same($0.path, path) }) else { return nil }
        return Session(rows: list.map { SessionRow(path: $0.path, album: $0, listed: $0) }, index: index, facet: facet)
    }

    /// `markFor`: a row's mark once the album changed, judged against what put it in the list - Fixed (every issue it had
    /// gone, none marked fine), Marked fine (gone, some accepted); nothing while anything is outstanding, nor for a clean
    /// new import.
    public static func markFor(listed: ScanAlbum, after: ScanAlbum) -> RowMark? {
        let was = MetadataQueue.outstanding(listed)
        guard !was.isEmpty, MetadataQueue.outstanding(after).isEmpty else { return nil }
        return was.contains { code in after.ignoredIssues.contains { WebText.same($0, code) } } ? .ignored : .fixed
    }

    /// `FolderChange`: what the editor says became of an album it was opened on from the page - the path it had, the
    /// album as its read has it (nil: not found, or deleted), and whether it was deleted.
    public struct FolderChange: Sendable, Equatable {
        public let from: String
        public let album: ScanAlbum?
        public let deleted: Bool

        public init(from: String, album: ScanAlbum?, deleted: Bool = false) {
            self.from = from
            self.album = album
            self.deleted = deleted
        }
    }

    /// `rowChanged`: the session after a write to one of its albums - the row found by the path it had (the current row
    /// first), followed to the path it has now, its album and mark brought up to date. Its place never changes.
    public static func rowChanged(_ session: Session, _ change: FolderChange) -> Session {
        //? the current row first: after a disc folder merges into another row's folder two rows share a path
        let at: Int
        if let here = session.current, WebText.same(here.path, change.from) {
            at = session.index
        } else if let found = session.rows.firstIndex(where: { WebText.same($0.path, change.from) }) {
            at = found
        } else {
            return session
        }
        var row = session.rows[at]
        if change.deleted {
            row.mark = .deleted
            row.heard = true
        } else if let album = change.album {
            row.path = album.path
            row.album = album
            row.mark = markFor(listed: row.listed, after: album)
            row.heard = true
        } else {
            return session
        }
        var next = session
        next.rows[at] = row
        return next
    }

    /// What going to another row comes to (`StepTarget`).
    public enum StepTarget: Sendable, Equatable {
        /// Nothing: the row it is on, or past either end.
        case stay
        /// The session ends - the album stepped to is gone - `leaving` marked reviewed.
        case end(leaving: String?)
        /// On to the row, `leaving` marked reviewed.
        case step(Session, leaving: String?)
    }

    /// `stepTarget`: from the current row to row `index`. `leaving` is the album to mark reviewed - the one left,
    /// unless it was deleted. `present` says whether the newest scan lists a path; a row a write has told the page of is
    /// taken as there whatever a scan says (it may predate a rename), a deleted one never.
    public static func stepTarget(_ session: Session, to index: Int, present: (String) -> Bool) -> StepTarget {
        guard index != session.index, index >= 0, index < session.rows.count else { return .stay }
        let leaving = session.current.flatMap { $0.mark == .deleted ? nil : $0.path }
        let there = session.rows[index]
        if there.mark == .deleted || (!there.heard && !present(there.path)) { return .end(leaving: leaving) }
        var next = session
        next.index = index
        return .step(next, leaving: leaving)
    }

    /// `leavingAtEnd`: the album to mark reviewed as a session ends (the editor closing is stepping away too).
    public static func leavingAtEnd(_ session: Session) -> String? {
        session.current.flatMap { $0.mark == .deleted ? nil : $0.path }
    }

    // MARK: the words

    /// `NEEDS_LOOK_LINE`: what the page is for and what to do there.
    public static let line = "Albums whose tags, folder or cover need fixing, albums Navidrome doesn't list, and new "
        + "downloads nobody has looked at yet. Open one to fix it, or to mark it fine as it is."
    /// `NEEDS_LOOK_LINE_NO_EDIT`: the same, for someone without Edit albums.
    public static let lineNoEdit = "Albums whose tags, folder or cover need fixing, albums Navidrome doesn't list, and "
        + "new downloads nobody has looked at yet. Open one to see what it has, or to delete it."
    /// permissions.ts `NEEDS_EDIT`: said under the line without Edit albums.
    public static let needsEdit = "Fixing it needs Edit albums, which an admin hasn't given you."
    /// `IGNORES_UNSAVED`.
    public static let ignoresUnsavedWords = "deadwax can't save to its database (check DB_PATH), so an album you mark "
        + "\u{201C}It's fine as it is\u{201D} will come back."

    /// `ignoresUnsaved`: the library's answer says review tracking is off (once a read has landed), or the count's route
    /// does (`summaryTracking` - nil until it has answered). Either is deadwax saying it has no job store.
    public static func ignoresUnsaved(loaded: Bool, reviewTracking: Bool, summaryTracking: Bool?) -> Bool {
        (loaded && !reviewTracking) || summaryTracking == false
    }

    /// `NAVIDROME_UNSET`, `NAVIDROME_SCANNING`, `NAVIDROME_WAITING`.
    public static let navidromeUnset = "Navidrome isn't set up, so no album is checked against what it lists. It's set "
        + "up in Server settings (Connections)."
    public static let navidromeScanning = "Navidrome was scanning when last asked, so only albums found missing before "
        + "are marked \u{201C}Not in Navidrome\u{201D}."
    public static let navidromeWaiting = "Navidrome hasn't answered yet, so no album is checked against it until the "
        + "library is read again."

    /// `navidromeFailed`: why, as deadwax said it, only for whoever runs deadwax (`detail`); anyone else what to do.
    public static func navidromeFailed(_ problem: String?, detail: Bool) -> String {
        if detail, let problem, !problem.isEmpty { return "Couldn't ask Navidrome which albums it has: \(problem)" }
        return "Couldn't ask Navidrome which albums it has - try again in a minute."
    }

    /// `navidromeNote`: what the page says once about the albums' check against Navidrome - nil when there is nothing
    /// to say (checked, or no answer at all).
    public static func navidromeNote(_ check: NavidromeCheck?, detail: Bool) -> String? {
        switch check?.state {
        case "unset": return navidromeUnset
        case "failed": return navidromeFailed(check?.problem, detail: detail)
        case "scanning": return navidromeScanning
        case "checking": return navidromeWaiting
        default: return nil
        }
    }

    /// `needsLookLabel`: what VoiceOver hears for "Needs a look" with its count - "Needs a look, 3 albums".
    public static func label(_ label: String, count: Int?) -> String {
        guard let count, count > 0 else { return label }
        return "\(label), \(count) album\(count == 1 ? "" : "s")"
    }
}

// MARK: the page (app/NeedsALook.tsx's own rules)

extension NeedsLook {
    /// A row as drawn (NeedsALook.tsx's DrawnRow): the key it keeps for the session, the album, what became of it.
    public struct DrawnRow: Sendable, Equatable, Identifiable {
        /// The album's path as listed - kept through a session whatever a write does to the folder.
        public let key: String
        public let album: ScanAlbum
        public let mark: RowMark?

        public var id: String { key }

        public init(key: String, album: ScanAlbum, mark: RowMark?) {
            self.key = key
            self.album = album
            self.mark = mark
        }
    }

    /// A session just ended (NeedsALook.tsx's Ending): its rows and facets held on screen until a fresh scan lands.
    public struct Ending: Sendable, Equatable {
        public let rows: [DrawnRow]
        public let chips: [Facet]
        public let facet: String?
        public var read: Bool

        public init(rows: [DrawnRow], chips: [Facet], facet: String?, read: Bool = false) {
            self.rows = rows
            self.chips = chips
            self.facet = facet
            self.read = read
        }
    }

    /// A session's end as held on screen (`{ rows: sessionRows(was), chips: heldNow.current ?? libraryChips.current,
    /// facet: was.facet, read: false }`): its rows, the facets as it began, its facet - until a fresh read lands.
    public static func ending(_ session: Session, held: [Facet]?, live: [Facet]) -> Ending {
        Ending(rows: sessionRows(session), chips: held ?? live, facet: session.facet)
    }

    /// The held rows let go (`ending?.read && !library.loading`): the ending's own read answered, and none still out.
    public static func released(_ ending: Ending?, reading: Bool) -> Bool {
        ending?.read == true && !reading
    }

    /// A read the page can trust (`library.loaded && !library.stale && !library.error`).
    public static func real(loaded: Bool, stale: Bool, failed: Bool) -> Bool {
        loaded && !stale && !failed
    }

    /// The facet chosen given up for All (`allowed && shown && real && !session && !ending && facet !== null && showing
    /// === null`): it has emptied, so it doesn't spring back when an album comes into it later.
    public static func facetGivenUp(allowed: Bool, shown: Bool, real: Bool, session: Bool, ending: Bool, facet: String?,
                                    showing: String?) -> Bool {
        allowed && shown && real && !session && !ending && facet != nil && showing == nil
    }

    /// Shown again after the first time with nothing under way: the library read again underneath (`allowed && shown &&
    /// !wasShown.current && library.loaded && !sessionNow.current && !ending`).
    public static func readsAgain(allowed: Bool, shown: Bool, wasShown: Bool, loaded: Bool, session: Bool,
                                  ending: Bool) -> Bool {
        allowed && shown && !wasShown && loaded && !session && !ending
    }

    /// `asRows`: the list as drawn, each keyed by its path.
    public static func asRows(_ albums: [ScanAlbum]) -> [DrawnRow] {
        albums.map { DrawnRow(key: $0.path, album: $0, mark: nil) }
    }

    /// `sessionRows`: a session's rows as drawn, each keyed by the path it was listed at.
    public static func sessionRows(_ session: Session) -> [DrawnRow] {
        session.rows.map { DrawnRow(key: $0.listed.path, album: $0.album, mark: $0.mark) }
    }

    /// The facets drawn: All always, the rest with an album (`chips.filter(chip => chip.id === null || chip.count > 0)`).
    public static func drawn(_ chips: [Facet]) -> [Facet] {
        chips.filter { $0.id == nil || $0.count > 0 }
    }

    /// The facets as the page holds them: while a session lasts, as it began (`heldChips`); while its rows are held,
    /// the ending's; else the live ones.
    public static func chips(session: Session?, held: [Facet]?, ending: Ending?, live: [Facet]) -> [Facet] {
        if session != nil { return held ?? live }
        if let ending { return ending.chips }
        return live
    }

    /// The facet the list is narrowed by: the session's, else the one chosen while it has albums (`facetShown`).
    public static func showing(session: Session?, live: [Facet], facet: String?) -> String? {
        if let session { return session.facet }
        return facetShown(live, facet)
    }

    /// The facet drawn chosen: the session's, then the ending's, else the one shown.
    public static func pressed(session: Session?, ending: Ending?, showing: String?) -> String? {
        if let session { return session.facet }
        if let ending { return ending.facet }
        return showing
    }

    /// The facet drawn chosen, as one of `chips`: the facet's, All's for none - nil when it isn't among them.
    public static func chip(_ chips: [Facet], pressed: String?) -> Facet? {
        chips.first { chip in
            switch (chip.id, pressed) {
            case (nil, nil): return true
            case (let id?, let chosen?): return WebText.same(id, chosen)
            default: return false
            }
        }
    }

    /// Whether the scan lists a path, as go()'s `new Set(albums.map(album => album.path)).has(path)` - code unit by
    /// code unit, never by Unicode's canonical equivalence (a Swift String's ==).
    public static func lists(_ albums: [ScanAlbum]) -> (String) -> Bool {
        let paths = Set(albums.map { Array($0.path.utf16) })
        return { paths.contains(Array($0.utf16)) }
    }

    /// The rows drawn: the session's, else the ending's held, else the list.
    public static func rows(session: Session?, ending: Ending?, albums: [ScanAlbum]) -> [DrawnRow] {
        if let session { return sessionRows(session) }
        if let ending { return ending.rows }
        return asRows(albums)
    }

    /// A row's first line: the album, else its folder (`album.album || album.path`).
    public static func title(_ album: ScanAlbum) -> String {
        album.album.isEmpty ? album.path : album.album
    }

    /// A row's second line: the artist and the folder's discs, else its edition (`[album.artist, album.disc_label ||
    /// album.edition].filter(Boolean).join(' · ')`).
    public static func byline(_ album: ScanAlbum) -> String {
        let edition = album.discLabel.isEmpty ? album.edition : album.discLabel
        return [album.artist, edition].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A row's words after its lines (its chips): its mark once a session has one; else "New" for a new import, each
    /// outstanding issue's label, and - under Marked fine - "Marked fine" for an album whose every issue was accepted.
    public static func chipWords(_ row: DrawnRow, pressed: String?, issueTypes: [String: MetadataIssueType]) -> [String] {
        if let mark = row.mark { return [mark.words] }
        let album = row.album
        return (MetadataQueue.isNewImport(album) ? [newWord] : [])
            + MetadataQueue.outstanding(album).map { MetadataQueue.label($0, issueTypes) }
            + (pressed.map { WebText.same($0, ignoredFacet) } == true && isIgnoredOnly(album) ? [markedFine] : [])
    }

    /// The Marked fine chip's title: "Marked fine: No cover art, Not in MusicBrainz".
    public static func markedFineTitle(_ album: ScanAlbum, issueTypes: [String: MetadataIssueType]) -> String {
        "\(markedFine): \(MetadataQueue.markedFine(album).map { MetadataQueue.label($0, issueTypes) }.joined(separator: ", "))"
    }

    /// The line at the page's top, by Edit albums.
    public static func lead(canEdit: Bool) -> String { canEdit ? line : lineNoEdit }

    /// The page's words (NeedsALook.tsx's own).
    public static let title = "Needs a look"
    public static let newWord = "New"
    public static let nothing = "Nothing needs a look."
    public static let checking = "Checking the library\u{2026}"
    public static let reading = "Reading the library"
    public static let tryAgain = "Try again"
    /// libraryCare.ts `READ_FAILED` (a first read failed) and `CHECK_FAILED` (a read again failed, the list on screen).
    public static let readFailed = "Couldn't read the library."
    public static let checkFailed = "Couldn't check the library just now."
    /// The facets' group (the web's `aria-label="Show"`) - the phone's menu.
    public static let show = "Show"

    /// The page's state before its list (NeedsALook.tsx's ladder): LIBRARY_PATH's problem said plainly; nothing read
    /// yet (the spinner); a failed first read with nothing to show (Try again); else the list.
    public enum State: Sendable, Equatable {
        case problem(String)
        case reading
        case failed
        case list
    }

    public static func state(problem: String?, loaded: Bool, failed: Bool, albums: Int) -> State {
        if let problem, !problem.isEmpty { return .problem(problem) }
        if !loaded { return .reading }
        if failed && albums == 0 { return .failed }
        return .list
    }

    /// The status line over the list (always there, one line): a failed read again (with Try again), the library being
    /// read again, else what the Navidrome check says - nil for nothing.
    public enum Status: Sendable, Equatable {
        case failed
        case checking
        case navidrome(String)
    }

    /// `checking` is `library.loaded && (library.stale || library.loading)`.
    public static func status(failed: Bool, loaded: Bool, stale: Bool, reading: Bool, navidrome: String?) -> Status? {
        if failed { return .failed }
        if loaded && (stale || reading) { return .checking }
        return navidrome.map { .navidrome($0) }
    }
}

// MARK: the editor in queue mode, and the phone's own words

extension NeedsLook {
    /// Where the editor is in the session (MetadataEditor.tsx's queue nav): "2 of 9", ‹ off at the first, the way on
    /// off at the last - Skip until a write was told of the album, then Next album (the web's Apply becoming it).
    public struct Nav: Sendable, Equatable {
        public let position: Int
        public let total: Int
        public let back: Bool
        public let on: Bool
        /// A write was told of the album, or it was deleted: "Next album ›" - else "Skip ›".
        public let done: Bool

        public init(_ session: Session) {
            position = session.index + 1
            total = session.rows.count
            back = position > 1
            on = position < total
            done = session.current.map { $0.heard || $0.mark != nil } ?? false
        }

        /// `{queue.position} of {queue.total}`.
        public var place: String { "\(position) of \(total)" }
        /// Next album in Skip's place (`applied && queue && queue.position < queue.total`): done, and not the last - the
        /// last keeps Skip, off, as the web's keeps its plain buttons.
        public var nextAlbum: Bool { done && on }
        public var forward: String { nextAlbum ? NeedsLookWords.nextAlbum : NeedsLookWords.skip }
        public var forwardSpoken: String { nextAlbum ? NeedsLookWords.nextAlbumSpoken : NeedsLookWords.skipSpoken }
    }

    /// The editor's request for a session's current album: its folder, alone (`folderOnly` - no bridge, no name guess).
    public static func folder(_ session: Session) -> String? { session.current?.path }
}

/// The phone's own words for Needs a look (a menu where the web has chips, a toolbar where it has a footer).
public enum NeedsLookWords {
    /// A facet in the Show menu: "All 12" (the web's chip, its count beside its label).
    public static func facet(_ chip: NeedsLook.Facet) -> String { "\(chip.label) \(chip.count)" }
    /// The facet to VoiceOver: "All, 12 albums".
    public static func facetSpoken(_ chip: NeedsLook.Facet) -> String {
        "\(chip.label), \(chip.count) album\(chip.count == 1 ? "" : "s")"
    }
    /// The list's header: the facet shown and how many it has ("Newly added · 3").
    public static func header(_ chip: NeedsLook.Facet?) -> String {
        guard let chip else { return NeedsLook.show }
        return "\(chip.label) · \(chip.count)"
    }
    /// The Show menu's symbol, filled while a facet other than All narrows the list.
    public static func showSymbol(narrowed: Bool) -> String {
        narrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }
    /// The Show menu to VoiceOver: "Show, Newly added".
    public static func showSpoken(_ chip: NeedsLook.Facet?) -> String {
        "\(NeedsLook.show), \(chip?.label ?? "All")"
    }

    /// The editor's bottom toolbar in queue mode (the web's ◁, "2 of 9", Skip ▷ / Next album ▷).
    public static let previous = "Previous album"
    public static let skip = "Skip \u{203A}"
    public static let nextAlbum = "Next album \u{203A}"
    public static let skipSpoken = "Skip"
    public static let nextAlbumSpoken = "Next album"
    /// Skip's hint (the web's title on it).
    public static let skipHint = "Leave this one for now and move on"
    /// Said as the editor steps to another album: "3 of 9: The Slow Rush".
    public static func stepped(_ nav: NeedsLook.Nav, album: String) -> String { "\(nav.place): \(album)" }

    /// A row to VoiceOver, read once: its title, its byline, and its chips or mark - "The Slow Rush, Tame Impala,
    /// New, No cover art".
    public static func row(_ row: NeedsLook.DrawnRow, chips: [String], current: Bool) -> String {
        ([NeedsLook.title(row.album), NeedsLook.byline(row.album)] + chips + (current ? [currentWord] : []))
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
    public static let currentWord = "Open"
}

// MARK: the count (app/useQueueSummary.ts)

/// `GET /deadwax/library/queue/summary`: how many albums need a look, from the saved scan alone - `total` the count,
/// `tracking_enabled` whether deadwax can keep what was marked fine. Read loosely; `tracking_enabled` absent is true
/// (the web's `answer.tracking_enabled !== false`).
public struct QueueSummary: Decodable, Sendable, Equatable {
    public let known: Bool
    public let needsAttention: Int
    public let newImports: Int
    public let total: Int
    public let unscannedImports: Int
    public let trackingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case known, total
        case needsAttention = "needs_attention"
        case newImports = "new_imports"
        case unscannedImports = "unscanned_imports"
        case trackingEnabled = "tracking_enabled"
    }

    public init(known: Bool = true, needsAttention: Int = 0, newImports: Int = 0, total: Int,
                unscannedImports: Int = 0, trackingEnabled: Bool = true) {
        self.known = known
        self.needsAttention = needsAttention
        self.newImports = newImports
        self.total = total
        self.unscannedImports = unscannedImports
        self.trackingEnabled = trackingEnabled
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        known = fields.looseField(Bool.self, .known) ?? false
        needsAttention = fields.looseField(Int.self, .needsAttention) ?? 0
        newImports = fields.looseField(Int.self, .newImports) ?? 0
        total = fields.looseField(Int.self, .total) ?? 0
        unscannedImports = fields.looseField(Int.self, .unscannedImports) ?? 0
        trackingEnabled = fields.looseField(Bool.self, .trackingEnabled) ?? true
    }
}

/// `POST /deadwax/library/queue/reviewed`'s answer: the album noted as looked at.
public struct QueueReviewed: Decodable, Sendable, Equatable {
    public let reviewed: Bool
    public let albumPath: String

    enum CodingKeys: String, CodingKey {
        case reviewed
        case albumPath = "album_path"
    }

    public init(reviewed: Bool, albumPath: String) {
        self.reviewed = reviewed
        self.albumPath = albumPath
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        reviewed = fields.looseField(Bool.self, .reviewed) ?? false
        albumPath = fields.looseField(String.self, .albumPath) ?? ""
    }
}

/// The count's state (useQueueSummary.ts): one request in flight, and one more after it when asked meanwhile, so the
/// answer that lands last is the newest question's; a failure keeps the last number (nil until one landed - nothing is
/// drawn over a count nobody knows); never asked without Look after the library (`asksQueueSummary` - the server
/// answers 403). No timer: nothing polls.
public struct QueueCount: Sendable, Equatable {
    /// The count deadwax last said - nil until it has.
    public private(set) var server: Int?
    /// Whether deadwax can keep what was marked fine, as the route last said - nil until it has.
    public private(set) var tracking: Bool?
    /// A request is out.
    public private(set) var asking = false
    /// Asked again while one was out: one more goes once it is over.
    public private(set) var again = false

    public init() {}

    /// Asked: true when a request goes now (`ask`); false when one is out (`again` set) or it may not be asked.
    public mutating func ask(allowed: Bool) -> Bool {
        guard allowed else { return false }
        if asking {
            again = true
            return false
        }
        asking = true
        return true
    }

    /// The request answered - true when another goes now (asked meanwhile).
    public mutating func answered(_ summary: QueueSummary) -> Bool {
        server = summary.total
        tracking = summary.trackingEnabled
        return over()
    }

    /// The request failed, or was called off: the last number kept - true when another goes now.
    public mutating func failed() -> Bool { over() }

    private mutating func over() -> Bool {
        asking = false
        guard again else { return false }
        again = false
        asking = true
        return true
    }

    /// The Manage row's value (You.tsx's `badgeText(needsLook ?? 0)`): nothing for none or not yet known, "99+" past 99.
    public var value: String { RequestWords.badgeText(server ?? 0) }

    /// The row to VoiceOver (`needsLook ? needsLookLabel('Needs a look', needsLook) : …`).
    public var spoken: String { NeedsLook.label(ManagingWords.label(.queue), count: server) }
}

// MARK: the routes

extension DeadwaxClient {
    /// How many albums need a look (`GET /library/queue/summary`) - from the saved scan alone, never the disk.
    public func queueSummary() async throws -> QueueSummary {
        try await call(Routes.queueSummary, as: QueueSummary.self)
    }

    /// The album looked at (`POST /library/queue/reviewed`) - what clears a new import. Not an ignore: its issues stay.
    public func markReviewed(path: String) async throws -> QueueReviewed {
        try await call(Routes.queueReviewed, sending: QueueMarkBody(albumPath: path, issues: nil))
    }
}
