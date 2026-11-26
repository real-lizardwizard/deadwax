import Foundation
import Testing
@testable import DeadwaxCore

/// The redesign, slice R13 (notes/ios.md "The redesign, slice R13: Library care and the Event log"): CarePages.swift's
/// rules, on Linux - a kind's row and its short buttons, the run's line and meter, the Mac's toolbar and status bar, the
/// collection's rows, and the event log's levels (Warnings taking errors too), Find, Copy, the chip and its status bar.
@Suite struct CarePagesTests {
    private static let zone = TimeZone(identifier: "UTC")!

    private static func album(_ path: String, art: String = "", release: String = "mbid", lyrics: Int = 0,
                              artist: String = "Björk", name: String = "Post") -> ScanAlbum {
        ScanAlbum(path: path, artist: artist, album: name, releaseMbid: release, art: art, trackCount: 10,
                  lyricsCount: lyrics, discArt: [])
    }

    private static func ready() -> CareRuns {
        var runs = CareRuns()
        runs.readLanded(runs.readBegan())
        return runs
    }

    private static func state(_ lines: [(String, String, String?)]) -> EventLog.State {
        // newest first, as the page holds them
        EventLog.State(lines: lines.enumerated().map { (at: Int, line: (String, String, String?)) -> LogLine in
            LogLine(eventType: line.0, eventContent: line.1, src: line.2, seq: lines.count - at, time: 1763300000, boot: "b")
        }, boot: "b", last: lines.count, gap: nil, cleared: false)
    }

    private static let mixed = state([("INFO", "Dummy: 3 of 11 files", "poller"), ("WARNING", "blueberry_jam refused", "slskd"),
                                      ("ERROR", "The scan failed", "library"), ("CRITICAL", "Out of disk", "organizer"),
                                      ("DEBUG", "asked", "musicbrainz"), ("WARN", "The Archive took 31 s", "coverart")])

    // MARK: Library care

    @Test func aKindsRowSaysWhatItsGetWouldTakeShort() {
        #expect(LibraryCare.rowLine(.covers, count: 14) == "14 albums without a cover")
        #expect(LibraryCare.rowLine(.disc, count: 1) == "1 album without CD art")
        #expect(LibraryCare.rowLine(.lyrics, count: 22) == "22 albums without lyrics")
        #expect(LibraryCare.rowLine(.covers, count: 0) == "Every matched album has its cover")
        #expect(LibraryCare.rowLine(.disc, count: 0) == "Every matched album has CD art")
        #expect(LibraryCare.rowLine(.lyrics, count: 0) == "Every album has some lyrics")
        // a scan not to trust: no count is said, the page's own word for it
        #expect(LibraryCare.rowLine(.covers, count: nil) == LibraryCare.checking)
        #expect(LibraryCare.getShort(count: 37) == "Get · 37")
        #expect(LibraryCare.stopShort(stopping: false) == "Stop" && LibraryCare.stopShort(stopping: true) == "Stopping…")
        #expect(LibraryCare.spokenRow(.disc, line: "37 albums without CD art") == "CD art, 37 albums without CD art")
        #expect(LibraryCare.runsNote == "One album at a time, and nothing else about an album changes. "
                + "The screen stays on while a run is under way and this page shows.")
    }

    @Test func theRunsLineIsTheAlbumOutAndTheMeterTheAlbumsDone() {
        var runs = Self.ready()
        let albums = [Self.album("Björk/Post"), Self.album("Björk/Debut", name: "Debut"),
                      Self.album("Bowie/Low", artist: "David Bowie", name: "Low")]
        _ = runs.start(.covers, albums, allowed: true, online: true)
        // started, nothing out yet: the count alone
        #expect(runs.under.map(LibraryCare.runLine) == "1 of 3")
        #expect(runs.under.flatMap(LibraryCare.runAlbum) == nil)
        _ = runs.next(allowed: true, online: true)
        #expect(runs.under.map(LibraryCare.runLine) == "1 of 3 · Post · Björk")
        #expect(runs.under.map { LibraryCare.runFraction($0.run) } == 0)
        runs.finished(.answered(.init(written: 1)))
        _ = runs.next(allowed: true, online: true)
        #expect(runs.under.map(LibraryCare.runLine) == "2 of 3 · Debut · Björk")
        #expect(runs.under.map { LibraryCare.runFraction($0.run) } == 1.0 / 3)
        // the Mac's two lines beside and under its meter: the count, then the album out
        #expect(runs.under.map { LibraryCare.runCount($0.run) } == "2 of 3")
        #expect(runs.under.flatMap(LibraryCare.runAlbum) == "Debut · Björk")
        // the Mac's lit button and its Stop, Stop's once pressed - pressed, the album out still finishes
        let under = runs.under!
        #expect(LibraryCare.getting(.covers, under.run) == "Getting covers · 2 of 3")
        #expect(LibraryCare.getting(.lyrics, under.run) == "Getting lyrics · 2 of 3")
        #expect(LibraryCare.toolbarStop(under.run, stopping: false) == "Stop after this album")
        runs.stop(.covers)
        #expect(LibraryCare.toolbarStop(runs.under!.run, stopping: runs.stopping(.covers)) == "Stopping after 2 of 3")
        #expect(runs.next(allowed: true, online: true) == .nothing, "Stop waits for the album out")
        #expect(runs.under?.out?.path == "Björk/Debut")
        runs.finished(.answered(.init(written: 1)))
        #expect(runs.next(allowed: true, online: true) == .ended(.covers))
        // an empty run's meter is empty, never NaN
        #expect(LibraryCare.runFraction(BulkTargets.Run(total: 0)) == 0)
        // a run past its last album never says more than its total
        #expect(LibraryCare.getting(.disc, BulkTargets.Run(total: 3, done: 3)) == "Getting CD art · 3 of 3")
    }

    @Test func theMacsStatusBarCountsWhatTheGetsCarry() {
        let counts: [BulkTargets.Kind: Int?] = [.covers: 14, .disc: 37, .lyrics: 22]
        let idle = LibraryCare.status(folders: 140, inScope: 140, typed: "", loaded: true, counts: counts, under: nil)
        #expect(idle.leading == ["140 album folders", "14 without a cover", "37 without CD art", "22 without lyrics"])
        #expect(idle.trailing.isEmpty)
        // narrowed: of how many
        let narrowed = LibraryCare.status(folders: 140, inScope: 12, typed: " bjork ", loaded: true, counts: counts, under: nil)
        #expect(narrowed.leading.first == "12 of 140 album folders")
        // a kind checking: no count of any said
        let checking = LibraryCare.status(folders: 1, inScope: 1, typed: "", loaded: true,
                                          counts: [.covers: 3, .disc: nil, .lyrics: 2], under: nil)
        #expect(checking.leading == ["1 album folder", LibraryCare.checking])
        #expect(LibraryCare.status(folders: 0, inScope: 0, typed: "", loaded: false, counts: [:], under: nil).leading
                == [LibraryCare.reading])
        // a run under way: at the right
        var runs = Self.ready()
        _ = runs.start(.disc, [Self.album("a"), Self.album("b")], allowed: true, online: true)
        _ = runs.next(allowed: true, online: true)
        #expect(LibraryCare.status(folders: 2, inScope: 2, typed: "", loaded: true, counts: counts, under: runs.under).trailing
                == ["Run: 1 of 2"])
    }

    @Test func theCollectionsRowsSayTheirCountAndAFlagShort() {
        #expect(Held.spokenRow(Held.title, count: 37) == "In nobody's library, 37")
        #expect(Held.spokenRow(Held.flagged, count: nil) == "Flagged downloads")
        let flag = Held.Flag(id: 3, artist: "Billy Joel", album: "The Stranger", path: "Billy Joel/The Stranger (1977)",
                             users: ["alex", "robin"])
        #expect(Held.askedBy(flag) == "Asked for by alex and robin")
        #expect(Held.flagShort(flag) == "Already in Billy Joel/The Stranger (1977)")
        let nobody = Held.Flag(id: 4)
        #expect(Held.askedBy(nobody) == "Nobody asked for it" && Held.flagShort(nobody) == "Already in its folder")
        // the Mac's tables' headings, as LibraryCare.dc.html's `.cols`
        #expect([Held.columnAlbum, Held.columnArtist, Held.columnFlag] == ["Album", "Artist", "The flag"])
    }

    // MARK: the event log

    @Test func warningsTakesErrorsTooAndErrorsTheErrorsAlone() {
        let lines = Self.mixed.lines
        #expect(EventLog.shown(lines, .everything).count == 6)
        // warnings and worse: never a level that leaves an error out
        #expect(EventLog.shown(lines, .warnings).map(\.eventContent)
                == ["blueberry_jam refused", "The scan failed", "Out of disk", "The Archive took 31 s"])
        #expect(EventLog.shown(lines, .errors).map(\.eventContent) == ["The scan failed", "Out of disk"])
        for line in lines where EventLog.shows(.errors, line) {
            #expect(EventLog.shows(.warnings, line), "an error shows under Warnings")
        }
        // the strip's count is what each shows
        for shown in EventLog.Shown.allCases {
            #expect(EventLog.count(lines, shown) == EventLog.shown(lines, shown).count)
        }
        #expect(EventLog.stripWords(.warnings, count: 4) == "Warnings 4")
        #expect(EventLog.stripWords(.errors, count: 0) == "Errors" && EventLog.stripWords(.everything, count: 6) == "Everything")
        #expect(EventLog.stripSaid(.errors, count: 1) == "Errors, 1 line" && EventLog.stripSaid(.everything, count: 6) == "Everything")
    }

    @Test func findTakesEveryWordAcrossTheWordsThePartAndTheLevel() {
        let lines = Self.mixed.lines
        #expect(EventLog.shown(lines, .everything, find: "SLSKD").map(\.eventContent) == ["blueberry_jam refused"])
        #expect(EventLog.shown(lines, .everything, find: "archive coverart").map(\.eventContent) == ["The Archive took 31 s"])
        #expect(EventLog.shown(lines, .errors, find: "critical").map(\.eventContent) == ["Out of disk"])
        #expect(EventLog.shown(lines, .everything, find: "  ").count == 6)
        #expect(EventLog.shown(lines, .errors, find: "poller").isEmpty)
        #expect(EventLog.noneShown(.errors, find: "") == "No errors in this view.")
        #expect(EventLog.noneShown(.warnings, find: "") == "No warnings or errors in this view.")
        #expect(EventLog.noneShown(.everything, find: " poller ") == "No line holds \u{201C}poller\u{201D}.")
    }

    @Test func copyTakesTheSelectionShownElseEveryLineShown() {
        let lines = Self.mixed.lines
        let errors = EventLog.shown(lines, .errors)
        // nothing selected: every line shown, newest first
        #expect(EventLog.copyShown([], of: errors, in: Self.zone) == EventLog.copyText(Set(errors.map(\.id)), of: errors, in: Self.zone))
        #expect(EventLog.copyShown([], of: errors, in: Self.zone)?.components(separatedBy: "\n").count == 2)
        // a selection among those shown: that alone
        let one = EventLog.copyShown([errors[1].id], of: errors, in: Self.zone)
        #expect(one == EventLog.copyText(errors[1], in: Self.zone))
        // a selection the level hides: every line shown, never a hidden one
        let hidden = lines[0].id
        #expect(EventLog.copyShown([hidden], of: errors, in: Self.zone)?.contains("Dummy") == false)
        #expect(EventLog.copyShown([], of: [], in: Self.zone) == nil)
        #expect(EventLog.copied(1) == "Copied 1 line" && EventLog.copied(12) == "Copied 12 lines")
    }

    @Test func clearedLinesNeverComeBackUnderAnyLevel() {
        // Clear empties the view; the history read again brings back nothing it had - whichever level is shown
        var state = Self.mixed.emptied()
        let recent = RecentLog(lines: Self.mixed.lines.reversed().map(\.line), last: 6, boot: "b")
        state = state.joining(history: recent)
        for shown in EventLog.Shown.allCases {
            #expect(EventLog.shown(state.lines, shown).isEmpty, "\(shown)")
        }
        // a new line after it shows
        state = state.joining(LogLine(eventType: "ERROR", eventContent: "new", seq: 7, boot: "b"))
        #expect(EventLog.shown(state.lines, .warnings).map(\.eventContent) == ["new"])
    }

    @Test func theChipAndTheMacsStatusBar() {
        #expect(EventLog.chipWords(.live) == "Live" && EventLog.chipWords(.lost) == "Reconnecting…")
        #expect(EventLog.chipWords(.connecting) == "Connecting…" && EventLog.chipWords(.stopped) == "Not live")
        // each level counted on its own, whatever is shown
        let status = EventLog.status(Self.mixed.lines, stream: .live)
        #expect(status.leading == ["6 lines kept", "2 warnings", "2 errors"])
        #expect(status.trailing == ["Live · newest first"])
        #expect(EventLog.status([], stream: .lost).leading == ["0 lines kept", "0 warnings", "0 errors"])
        #expect(EventLog.status(Array(Self.mixed.lines.prefix(1)), stream: .connecting).leading.first == "1 line kept")
        #expect(EventLog.Shown.allCases.map(EventLog.label) == ["Everything", "Warnings", "Errors"])
        #expect(EventLog.columns == ["Time", "Level", "From", "What happened"])
    }

    // MARK: after the review

    @Test func theFactsBesideRescanAreTheDrawingsShortOnes() {
        let albums = [Self.album("Björk/Post"), Self.album("Björk/Debut", name: "Debut"),
                      Self.album("Björk/Debut (disc 2)", name: "debut")]
        let scanned = 1763300000.0
        // iLibraryCare's "140 albums · 2 min ago": the albums (a release in two folders is one) and the scan's age
        #expect(LibraryCare.shortFacts(albums, loaded: true, scannedAt: scanned, rescanning: false,
                                       now: (scanned + 150) * 1000) == "2 albums · 2 min ago")
        #expect(LibraryCare.shortFacts(Array(albums.prefix(1)), loaded: true, scannedAt: scanned, rescanning: false,
                                       now: scanned * 1000) == "1 album · just now")
        #expect(LibraryCare.shortFacts(albums, loaded: true, scannedAt: nil, rescanning: false, now: 0) == "2 albums")
        #expect(LibraryCare.shortFacts([], loaded: false, scannedAt: nil, rescanning: false, now: 0) == "Reading the library…")
        #expect(LibraryCare.shortFacts(albums, loaded: true, scannedAt: scanned, rescanning: true, now: 0)
                == "Reading every file again…")
        // the whole line is longer, and VoiceOver's
        let whole = LibraryCare.facts(albums, loaded: true, loading: false, scannedAt: scanned, scanSeconds: 0.8,
                                      rescanning: false, now: (scanned + 150) * 1000)
        #expect(whole.hasPrefix("2 albums · 30 tracks") && whole.hasSuffix("Scanned 2 min ago in 0.8s"))
    }

    @Test func theMacsSnapshotAnswersAsCareRunsDo() {
        let albums = [Self.album("Björk/Post"), Self.album("Björk/Debut", art: "cover.jpg", name: "Debut"),
                      Self.album("Bowie/Low", lyrics: 3, artist: "David Bowie", name: "Low")]
        func same(_ runs: CareRuns, allowed: Bool = true, online: Bool = true, _ said: String) {
            let snapshot = LibraryCare.Snapshot(runs, albums, allowed: allowed, online: online)
            #expect(snapshot.all == albums.count, "\(said)")
            #expect(snapshot.inScope == LibraryCare.narrow(albums, runs.narrow).count, "\(said)")
            for kind in BulkTargets.kinds {
                #expect(snapshot.targets(kind) == runs.targets(kind, albums), "\(said): \(kind)")
                #expect(snapshot.startOpen(kind) == runs.startOpen(kind, albums, allowed: allowed, online: online),
                        "\(said): \(kind)")
                #expect(snapshot.counts[kind] == runs.targets(kind, albums)?.count, "\(said): \(kind)")
            }
        }
        same(CareRuns(), "no read to trust")
        var runs = Self.ready()
        same(runs, "ready")
        same(runs, allowed: false, "not allowed")
        same(runs, online: false, "out of reach")
        runs.narrow = "bowie"
        same(runs, "narrowed")
        runs.narrow = ""
        _ = runs.start(.covers, albums, allowed: true, online: true)
        same(runs, "a run under way")
        _ = runs.next(allowed: true, online: true)
        runs.finished(.answered(.init(written: 1)))
        while case .album = runs.next(allowed: true, online: true) { runs.finished(.answered(.init(written: 1))) }
        #expect(runs.behind[.covers] != nil)
        same(runs, "covers behind the disk")
        #expect(LibraryCare.Snapshot(runs, albums, allowed: true, online: true).targets(.covers) == nil)
    }

    @Test func theAlbumCellNamesTheAlbumAloneItsHelpTheWhole() {
        let untagged = Held.UnheldAlbum(id: 1, path: "Björk/untitled", artist: "Björk")
        #expect(Held.albumCell(untagged) == "Unknown album", "never Unknown album · Björk beside Björk")
        #expect(Held.albumName(untagged) == "Unknown album · Björk")
        #expect(Held.albumHelp(untagged) == "Unknown album · Björk\nBjörk/untitled")
        let tagged = Held.UnheldAlbum(id: 2, path: "Björk/Post", artist: "Björk", album: "Post")
        #expect(Held.albumCell(tagged) == "Post" && Held.albumHelp(tagged) == "Post · Björk\nBjörk/Post")
    }

    @Test func aSelectionTheLevelOrFindHidesIsLetGo() {
        let lines = Self.mixed.lines
        let info = lines[0].id
        let errors = EventLog.shown(lines, .errors)
        // an INFO line selected, Errors picked: let go of, so Copy takes every error and Edit > Copy agrees
        var selected = EventLog.keptSelection([info], shown: errors.map(\.id))
        #expect(selected.isEmpty)
        // Everything again: it doesn't come back selected
        selected = EventLog.keptSelection(selected, shown: lines.map(\.id))
        #expect(selected.isEmpty)
        #expect(EventLog.copyShown(selected, of: lines) == EventLog.copyShown([], of: lines))
        // a line still shown stays selected, the hidden one goes; Find the same
        let both: Set<EventLog.Line.ID> = [info, errors[0].id]
        #expect(EventLog.keptSelection(both, shown: errors.map(\.id)) == [errors[0].id])
        let found = EventLog.shown(lines, .everything, find: "scan")
        #expect(EventLog.keptSelection(both, shown: found.map(\.id)) == [errors[0].id])
        // cleared: nothing stays selected
        #expect(EventLog.keptSelection(both, shown: []).isEmpty)
    }

    @Test func aRowsStripeIsItsOwnAsLinesComeIn() {
        var state = Self.mixed
        let before = Dictionary(uniqueKeysWithValues: state.lines.map { ($0.id, EventLog.striped($0)) })
        // every other line, newest first
        #expect(state.lines.map(EventLog.striped) == [true, false, true, false, true, false])
        // a line in at the top: every stripe below stays where it was
        state = state.joining(LogLine(eventType: "INFO", eventContent: "new", seq: 7, boot: "b"))
        #expect(state.lines.count == 7)
        for line in state.lines.dropFirst() {
            #expect(EventLog.striped(line) == before[line.id], "\(line.eventContent)")
        }
        #expect(EventLog.striped(state.lines[0]) != EventLog.striped(state.lines[1]))
        // a line of a deadwax that numbered none: the page's own count of lines taken
        let unnumbered = EventLog.State().joining(LogLine(eventType: "INFO", eventContent: "old"))
            .joining(LogLine(eventType: "INFO", eventContent: "older"))
        #expect(unnumbered.lines.map(EventLog.striped) == [true, false])
    }
}
