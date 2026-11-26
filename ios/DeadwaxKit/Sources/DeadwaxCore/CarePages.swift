import Foundation

// The redesign, slice R13 (notes/ios.md "The redesign, slice R13: Library care and the Event log"): Library care and the
// event log as iLibraryCare and iEventLog draw them on the phone - flat - and as LibraryCare.dc.html and EventLog.dc.html
// draw them on the Mac, in its toolbar and boxes. What they draw that is a rule or a word of its own is here, pure and
// tested on Linux (CarePagesTests); every decision about a run, a read or the log's lines stays CareRuns', Held.Flow's
// and EventLog.State's, unchanged.

// MARK: Library care's rows and toolbar

extension LibraryCare {
    /// iLibraryCare's third group: In nobody's library and Flagged downloads.
    public static let collection = "The collection"
    /// The Mac's toolbar: Rescan, named for what it does (LibraryCare.dc.html's).
    public static let rescanLibrary = "Rescan the library"
    /// The Mac's Rescan box: the scan's facts (LibraryCare.dc.html's `kv`).
    public static let lastRead = "Last read"
    /// Under the runs, on both: one album at a time, and what a run never touches.
    public static let oneAtATime = "One album at a time, and nothing else about an album changes."
    /// The Mac's folded toolbar: the three Gets in one pop-up.
    public static let getMenu = "Get"
    /// The Mac's narrowest toolbar: everything the page does, in one pop-up.
    public static let menuLabel = "Library care"

    /// The note under the three, as iLibraryCare words it: one album at a time, then the screen kept on.
    public static var runsNote: String { "\(oneAtATime) \(screenOnNote)" }

    /// A kind's line beside its name (iLibraryCare's `.s.q`): how many albums its Get would take, said short - the long
    /// words (planWords) are its hint - or Checking the library… while the scan in hand isn't one to trust.
    public static func rowLine(_ kind: BulkTargets.Kind, count: Int?) -> String {
        guard let count else { return checking }
        let albums = "\(count) album\(count == 1 ? "" : "s")"
        switch kind {
        case .covers: return count != 0 ? "\(albums) without a cover" : "Every matched album has its cover"
        case .disc: return count != 0 ? "\(albums) without CD art" : "Every matched album has CD art"
        case .lyrics: return count != 0 ? "\(albums) without lyrics" : "Every album has some lyrics"
        }
    }

    /// A kind's Get on the phone's row, short (iLibraryCare's "Get · 37"); VoiceOver hears startLabel's whole words.
    public static func getShort(count: Int) -> String {
        "Get · \(count)"
    }

    /// The running kind's Stop on the phone's row, short; VoiceOver hears stopLabel's whole words.
    public static func stopShort(stopping: Bool) -> String {
        stopping ? "Stopping…" : "Stop"
    }

    /// Where the run under way is, under its meter: the album being fetched (done + 1, as Stop says it) of how many,
    /// and that album - "4 of 14 · Post · Björk". Between two albums (none out), the count alone.
    public static func runLine(_ under: CareRuns.Under) -> String {
        let at = runCount(under.run)
        guard let album = runAlbum(under) else { return at }
        return "\(at) · \(album)"
    }

    /// The run's count alone, beside the Mac's meter: "4 of 14" - the album being fetched, as Stop says it.
    public static func runCount(_ run: BulkTargets.Run) -> String {
        "\(min(run.done + 1, run.total)) of \(run.total)"
    }

    /// The album out, under the Mac's meter: "Post · Björk" - none between two albums.
    public static func runAlbum(_ under: CareRuns.Under) -> String? {
        under.out.map { (out: ScanAlbum) -> String in Held.name(album: out.album, artist: out.artist) }
    }

    /// How far the meter is along: the albums done of the run's.
    public static func runFraction(_ run: BulkTargets.Run) -> Double {
        run.total > 0 ? Double(run.done) / Double(run.total) : 0
    }

    /// The Mac's toolbar, the running kind's lit button: "Getting covers · 4 of 14".
    public static func getting(_ kind: BulkTargets.Kind, _ run: BulkTargets.Run) -> String {
        let doing: String
        switch kind {
        case .covers: doing = "Getting covers"
        case .disc: doing = "Getting CD art"
        case .lyrics: doing = "Getting lyrics"
        }
        return "\(doing) · \(min(run.done + 1, run.total)) of \(run.total)"
    }

    /// The Mac's toolbar's Stop: "Stop after this album", then "Stopping after 4 of 14" (stopLabel's) once pressed.
    public static func toolbarStop(_ run: BulkTargets.Run, stopping: Bool) -> String {
        stopping ? stopLabel(run, stopping: true) : "Stop after this album"
    }

    /// What VoiceOver reads of a kind's row, once: its name, then its line or where its run is.
    public static func spokenRow(_ kind: BulkTargets.Kind, line: String) -> String {
        "\(heading(kind)), \(line)"
    }

    /// The Mac's status bar (LibraryCare.dc.html's): the album folders the runs act on, and what each kind would take
    /// - the very counts the Gets carry (`counts`, each kind's targets now: nil while checking) - and, at its right, the
    /// run under way.
    public static func status(folders all: Int, inScope: Int, typed: String, loaded: Bool,
                              counts: [BulkTargets.Kind: Int?], under: CareRuns.Under?) -> (leading: [String], trailing: [String]) {
        guard loaded else { return ([reading], []) }
        let folders = JSText.trim(typed).isEmpty ? "\(all) album folder\(all == 1 ? "" : "s")"
            : "\(inScope) of \(all) album folder\(all == 1 ? "" : "s")"
        var leading = [folders]
        let known = BulkTargets.kinds.compactMap { (kind: BulkTargets.Kind) -> (BulkTargets.Kind, Int)? in
            guard let count = counts[kind] ?? nil else { return nil }
            return (kind, count)
        }
        if known.count < BulkTargets.kinds.count {
            leading.append(checking)
        } else {
            for (kind, count) in known {
                switch kind {
                case .covers: leading.append("\(count) without a cover")
                case .disc: leading.append("\(count) without CD art")
                case .lyrics: leading.append("\(count) without lyrics")
                }
            }
        }
        guard let under else { return (leading, []) }
        return (leading, ["Run: \(min(under.run.done + 1, under.run.total)) of \(under.run.total)"])
    }

    /// (R13's review) The scan's facts beside the phone's Rescan the library, short - iLibraryCare's "140 albums · 2 min
    /// ago": the albums and how old the scan is, or what is under way. `facts`' whole line (the tracks, the size, how long
    /// it took) is too long for a line beside the button in the readout face (about 450 points of a row's 200), so it is
    /// VoiceOver's - and the Mac's Last read.
    public static func shortFacts(_ albums: [ScanAlbum], loaded: Bool, scannedAt: Double?, rescanning: Bool,
                                  now: Double) -> String {
        if !loaded { return reading + "…" }
        if rescanning { return "Reading every file again…" }
        var keys = Set<[UInt16]>()
        for album in albums {
            keys.insert(Array((JSText.lowercase(album.artist) + "\u{0}" + JSText.lowercase(album.album)).utf16))
        }
        let groups = "\(keys.count) album\(keys.count == 1 ? "" : "s")"
        let age = formatAge(scannedAt, now: now)
        return age.isEmpty ? groups : "\(groups) · \(age)"
    }

    /// (R13's review) What the Mac's Library care draws from the scan, worked out once a render - the runs' scope
    /// narrowed once, and each kind's targets and Start from it - where the status bar, the toolbar's three ways and the
    /// rows each narrowed the scan again (some 40 times a render). The same answers as CareRuns' `targets` and
    /// `startOpen` (CarePagesTests holds them equal).
    public struct Snapshot: Sendable, Equatable {
        /// The album folders the runs act on (Narrow to's), and all of them.
        public let inScope: Int
        public let all: Int
        private let kinds: [BulkTargets.Kind: [ScanAlbum]]
        private let opens: Set<BulkTargets.Kind>

        public init(_ runs: CareRuns, _ albums: [ScanAlbum], allowed: Bool, online: Bool) {
            let scope = LibraryCare.narrow(albums, runs.narrow)
            inScope = scope.count
            all = albums.count
            var kinds: [BulkTargets.Kind: [ScanAlbum]] = [:]
            var opens: Set<BulkTargets.Kind> = []
            for kind in BulkTargets.kinds {
                guard let targets = LibraryCare.targets(kind, real: runs.real, behind: runs.behind[kind] != nil,
                                                        inScope: scope) else { continue }
                kinds[kind] = targets
                if allowed, online, runs.under == nil, !targets.isEmpty { opens.insert(kind) }
            }
            self.kinds = kinds
            self.opens = opens
        }

        /// The albums `kind`'s run would take now - nil: Checking the library… (CareRuns' `targets`).
        public func targets(_ kind: BulkTargets.Kind) -> [ScanAlbum]? {
            kinds[kind]
        }

        /// Start may be pressed for `kind` (CareRuns' `startOpen`).
        public func startOpen(_ kind: BulkTargets.Kind) -> Bool {
            opens.contains(kind)
        }

        /// Each kind's count, for the status bar (nil while checking).
        public var counts: [BulkTargets.Kind: Int?] {
            var counts: [BulkTargets.Kind: Int?] = [:]
            // updateValue: a subscript set to an optional chain that came to nothing would drop the key, not keep nil
            for kind in BulkTargets.kinds { counts.updateValue(kinds[kind]?.count, forKey: kind) }
            return counts
        }
    }
}

// MARK: In nobody's library, as rows

extension Held {
    /// The Mac's tables' headings (LibraryCare.dc.html's `.cols`): In nobody's library's Album and Artist, Flagged
    /// downloads' Album and The flag.
    public static let columnAlbum = "Album"
    public static let columnArtist = "Artist"
    public static let columnFlag = "The flag"

    /// Who asked for a flagged download, under its name: "Asked for by alex and robin".
    public static func askedBy(_ flag: Flag) -> String {
        flag.users.isEmpty ? "Nobody asked for it" : "Asked for by \(listed(flag.users))"
    }

    /// Why nobody was given it, short (the Mac's "The flag" column): where every file already was. flagWords' whole
    /// sentence is its help and VoiceOver's.
    public static func flagShort(_ flag: Flag) -> String {
        let path = flag.path ?? ""
        return "Already in \(path.isEmpty ? "its folder" : path)"
    }

    /// A row of the collection with its count (Library care's In nobody's library, Flagged downloads), to VoiceOver:
    /// "In nobody's library, 37" - the count the badge shows, which is hidden from it.
    public static func spokenRow(_ title: String, count: Int?) -> String {
        guard let count else { return title }
        return "\(title), \(count)"
    }

    /// (R13's review) The Mac's Album cell: the album alone - its artist is the next column's, so an untagged one is
    /// "Unknown album", never "Unknown album · Björk" beside "Björk".
    public static func albumCell(_ album: UnheldAlbum) -> String {
        album.album.isEmpty ? name(album: nil, artist: nil) : album.album
    }

    /// (R13's review) The Album cell's help, the whole of what a cut cell hides: the album and its artist, then its folder.
    public static func albumHelp(_ album: UnheldAlbum) -> String {
        [albumName(album), album.path].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// MARK: the event log's levels, Find and Copy

extension EventLog {
    /// The level strip (iEventLog's `.chips`, EventLog.dc.html's `.seg.lg`): every line, the warnings and the errors -
    /// **Warnings is warnings and worse**, never one that leaves an error out - or the errors alone.
    public enum Shown: String, Sendable, CaseIterable, Hashable {
        case everything, warnings, errors
    }

    /// What VoiceOver calls the strip.
    public static let levels = "Levels"
    /// The Mac's Clear (EventLog.dc.html's): this view only - deadwax keeps its lines.
    public static let clearView = "Clear this view"
    /// Clear's hint on both, and its help on the Mac: what pageLine said under the bar.
    public static let clearHint = "Empties this view only - deadwax keeps its lines, and new ones still come."
    /// The Mac's Find in the toolbar.
    public static let findPrompt = "Find in the log"
    /// The Mac's column headings (EventLog.dc.html's `.cols`).
    public static let columns = ["Time", "Level", "From", "What happened"]
    /// Copy's hint on the Mac, and its help: what it copies (copyShown).
    public static let copyHint = "Copies the lines selected, or every line shown when none is."

    /// A level's words.
    public static func label(_ shown: Shown) -> String {
        switch shown {
        case .everything: return "Everything"
        case .warnings: return "Warnings"
        case .errors: return "Errors"
        }
    }

    /// Whether `line` shows under `shown`.
    public static func shows(_ shown: Shown, _ line: Line) -> Bool {
        switch shown {
        case .everything: return true
        case .warnings: return level(line.eventType) != .info
        case .errors: return level(line.eventType) == .error
        }
    }

    /// Whether `line` holds every word typed into Find - its words, the part that said it and its level, accents and
    /// case aside (TypedMatch, as every Find in the app).
    public static func finds(_ line: Line, typed: String) -> Bool {
        TypedMatch.matches("\(line.eventContent) \(line.src ?? "") \(line.eventType)", typed: typed)
    }

    /// The lines shown: those `shown` takes that Find finds, newest first as held.
    public static func shown(_ lines: [Line], _ shown: Shown, find typed: String = "") -> [Line] {
        lines.filter { (line: Line) -> Bool in shows(shown, line) && finds(line, typed: typed) }
    }

    /// How many lines `shown` takes of `lines` - the strip's count beside its words, never a different count from what
    /// it shows.
    public static func count(_ lines: [Line], _ shown: Shown) -> Int {
        lines.reduce(0) { (sum: Int, line: Line) -> Int in shows(shown, line) ? sum + 1 : sum }
    }

    /// A level's words on the phone's strip: Warnings and Errors with how many lines each shows, when there are any
    /// ("Warnings 2"); Everything never counted.
    public static func stripWords(_ shown: Shown, count: Int) -> String {
        shown == .everything || count == 0 ? label(shown) : "\(label(shown)) \(count)"
    }

    /// What VoiceOver hears of a level on the strip: "Warnings, 2 lines".
    public static func stripSaid(_ shown: Shown, count: Int) -> String {
        shown == .everything ? label(shown) : "\(label(shown)), \(count) line\(count == 1 ? "" : "s")"
    }

    /// What Copy puts on the clipboard: the lines selected still shown (the Mac's), else every line shown - nil with
    /// none (Copy dimmed).
    public static func copyShown(_ selected: Set<Line.ID>, of shown: [Line], in zone: TimeZone = .current) -> String? {
        let chosen = shown.contains { (line: Line) -> Bool in selected.contains(line.id) }
            ? selected : Set(shown.map(\.id))
        return copyText(chosen, of: shown, in: zone)
    }

    /// (R13's review) The selection as the lines shown leave it: a line a level or Find hides - or that went, cleared or
    /// the oldest let go - is let go of, so Copy and Edit > Copy act on what is selected and shown, and a hidden line
    /// never comes back selected when the level changes again.
    public static func keptSelection(_ selected: Set<Line.ID>, shown ids: [Line.ID]) -> Set<Line.ID> {
        guard !selected.isEmpty else { return selected }
        return selected.intersection(ids)
    }

    /// (R13's review) Whether the Mac's row of `line` is striped: by something of the line's own - its number from
    /// deadwax, else the page's count of lines taken - never its place, so a line coming in at the top leaves every
    /// stripe below where it was. (MacTable.stripes counts places: right for a list that holds still, not a live one.)
    public static func striped(_ line: Line) -> Bool {
        (line.seq ?? line.id.taken) % 2 == 0
    }

    /// What VoiceOver says once Copy has copied: "Copied 12 lines".
    public static func copied(_ count: Int) -> String {
        "Copied \(count) line\(count == 1 ? "" : "s")"
    }

    /// Where the stream stands, on the chip in the bar (iEventLog's `.chip.green` "Live"): short - the line's whole words
    /// (`words(_:)`) are its VoiceOver label.
    public static func chipWords(_ state: StreamState) -> String {
        switch state {
        case .connecting: return "Connecting…"
        case .live: return "Live"
        case .lost: return "Reconnecting…"
        case .stopped: return "Not live"
        }
    }

    /// None of the lines held shows: what `shown` and Find took them all away for.
    public static func noneShown(_ shown: Shown, find typed: String) -> String {
        if !JSText.trim(typed).isEmpty { return "No line holds \u{201C}\(JSText.trim(typed))\u{201D}." }
        switch shown {
        case .everything: return emptyNever
        case .warnings: return "No warnings or errors in this view."
        case .errors: return "No errors in this view."
        }
    }

    /// The Mac's status bar (EventLog.dc.html's): the lines kept in this view, its warnings and its errors - each level
    /// on its own, whatever is shown - and, at its right, where the stream stands, newest first.
    public static func status(_ lines: [Line], stream: StreamState) -> (leading: [String], trailing: [String]) {
        var warnings = 0
        var errors = 0
        for line in lines {
            switch level(line.eventType) {
            case .warning: warnings += 1
            case .error: errors += 1
            case .info: break
            }
        }
        return (["\(lines.count) line\(lines.count == 1 ? "" : "s") kept",
                 "\(warnings) warning\(warnings == 1 ? "" : "s")",
                 "\(errors) error\(errors == 1 ? "" : "s")"],
                ["\(chipWords(stream)) · newest first"])
    }
}
