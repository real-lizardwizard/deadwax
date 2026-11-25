import Foundation
import Testing
@testable import DeadwaxCore

/// Requests' filter, counts and summed speed (the redesign, slice R8 - notes/ios.md "The redesign, slice R8: Requests"):
/// which headings All, Active and Done show - never one over nothing - how many each holds, the speed summed from the
/// downloading rows alone, the status bar's words, the rows' From, Speed and Progress, the Mac's table as drawn, and the
/// meter's share of its track. (R8's review) And a cancel that asked first acting only on the row as it is now, what each
/// row offers, what VoiceOver hears of it, the done chip's few words, the table fitting its page and the toolbar folding.
@Suite struct RequestFilterTests {
    static let now: Int64 = 1_795_564_800_000     // 25 Nov 2026, midnight UTC

    /// A board of every kind: two downloading (one cancelling), one organizing, two waiting, one refused, two done - one
    /// of them with a rate still measured for it.
    static func board(cancelling: Set<Int> = [8], speeds: [Int: Double]? = nil) -> RequestsView {
        let jobs = [
            DownloadJob(id: 1, status: "downloading", artist: "Portishead", album: "Dummy", username: "glassbeads",
                        progress: 40, filesDone: 3, filesTotal: 11),
            DownloadJob(id: 8, status: "downloading", artist: "Massive Attack", album: "Mezzanine", username: "teardrop",
                        progress: 10, filesDone: 1, filesTotal: 11),
            DownloadJob(id: 2, status: "organizing", artist: "Tricky", album: "Maxinquaye", username: "hell",
                        progress: 100, filesDone: 12, filesTotal: 12),
            DownloadJob(id: 3, status: "queued", artist: "Beth Gibbons", album: "Lives Outgrown", username: "rustin",
                        queuePosition: 4, progress: 0, filesDone: 0, filesTotal: 10),
            DownloadJob(id: 4, status: "failed", artist: "Goldfrapp", album: "Felt Mountain", username: "lovely",
                        failureReason: "rejected", alternativesLeft: 2),
            DownloadJob(id: 5, status: "completed", artist: "Lamb", album: "Fear of Fours", username: "joga",
                        updatedAt: "2026-11-24T10:00:00+00:00", outcome: "filed"),
            DownloadJob(id: 6, status: "completed", artist: "Sneaker Pimps", album: "Becoming X", username: "six",
                        updatedAt: "2026-11-24T09:00:00+00:00", outcome: "filed"),
        ]
        let pending = [PendingDownload(key: "p1", artist: "Morcheeba", album: "Big Calm", username: "trigger")]
        let rates = speeds ?? [1: 249_856, 8: 100_000, 2: 50_000, 3: 70_000, 5: 1_000_000]
        return RequestsView.make(RequestsInput(jobs: jobs, pending: pending, speeds: rates, cancelling: cancelling),
                                 now: now)
    }

    // MARK: the filters

    @Test func allShowsEveryHeadingActiveNeverDoneAndDoneAlone() {
        #expect(RequestFilter.all.sections == [.downloading, .waiting, .attention, .done])
        #expect(RequestFilter.active.sections == [.downloading, .waiting, .attention])
        #expect(!RequestFilter.active.sections.contains(.done))
        #expect(RequestFilter.done.sections == [.done])
        #expect(RequestFilter.allCases.map { $0.label } == ["All", "Active", "Done"])
        let board = Self.board()
        #expect(RequestFilter.all.shown(board) == [.downloading, .waiting, .attention, .done])
        #expect(RequestFilter.active.shown(board) == [.downloading, .waiting, .attention])
        #expect(RequestFilter.done.shown(board) == [.done])
    }

    @Test func aHeadingIsShownOnlyOverRows() {
        // nothing refused, nothing done: two headings, not four
        let jobs = [DownloadJob(id: 1, status: "downloading", artist: "A", album: "B", username: "c", progress: 5,
                                filesDone: 0, filesTotal: 4),
                    DownloadJob(id: 2, status: "queued", artist: "D", album: "E", username: "f", queuePosition: 1)]
        let board = RequestsView.make(RequestsInput(jobs: jobs), now: Self.now)
        #expect(RequestFilter.all.shown(board) == [.downloading, .waiting])
        #expect(RequestFilter.done.shown(board) == [])
        #expect(RequestFilter.done.lines(board) == [])
        for filter in RequestFilter.allCases {
            let lines = filter.lines(board)
            // every heading drawn has a row straight under it
            for (index, line) in lines.enumerated() {
                if case .group = line {
                    #expect(index + 1 < lines.count && lines[index + 1].row != nil, "a heading over nothing: \(filter)")
                }
            }
        }
        #expect(RequestFilter.all.shown(.nothing) == [])
        #expect(RequestFilter.all.lines(.nothing) == [])
    }

    @Test func theTablesLinesAreEachHeadingThenItsRows() {
        let board = Self.board()
        let lines = RequestFilter.all.lines(board)
        #expect(lines == [
            .group("Downloading"), .row("job-1"), .row("job-8"), .row("job-2"),
            .group("Waiting"), .row("p1"), .row("job-3"),
            .group("Needs attention"), .row("job-4"),
            .group("Done"), .row("job-5"), .row("job-6"),
        ])
        // the stripes start again under each heading
        #expect(MacTable.stripes(lines) == [false, false, true, false, false, false, true, false, false, false, false, true])
        #expect(RequestFilter.done.lines(board) == [.group("Done"), .row("job-5"), .row("job-6")])
        #expect(RequestFilter.active.lines(board).compactMap { $0.row }.allSatisfy { !["job-5", "job-6"].contains($0) })
    }

    @Test func theCountsAreEachHeadingsAndEachFiltersRows() {
        let board = Self.board()
        let counts = RequestCounts(board)
        #expect(counts == RequestCounts(downloading: 3, waiting: 2, attention: 1, done: 2))
        #expect(counts.of(filter: .all) == 8 && counts.of(filter: .active) == 6 && counts.of(filter: .done) == 2)
        for filter in RequestFilter.allCases { #expect(filter.count(board) == counts.of(filter: filter)) }
        for section in RequestSection.allCases { #expect(counts.of(section) == board.rows(section).count) }
        #expect(RequestCounts(.nothing) == RequestCounts(downloading: 0, waiting: 0, attention: 0, done: 0))
    }

    // MARK: the speed

    @Test func theSpeedIsTheDownloadingRowsAloneNeverAFinishedOnes() {
        let board = Self.board()
        // job 1 alone: 8 is being cancelled, 2 filed, 3 waiting, 5 done - each with a rate measured, none counted
        #expect(RequestFilter.speed(board) == 249_856)
        #expect(RequestFilter.rate(board.rows(.done)[0]) == nil)
        #expect(board.rows(.done)[0].speed == 1_000_000, "the done row was measured: the filter is what leaves it out")
        #expect(RequestFilter.rate(board.rows(.waiting)[1]) == nil)
        // two downloading at once add up
        let both = Self.board(cancelling: [])
        #expect(RequestFilter.speed(both) == 349_856)
        // nothing measured, nothing summed; a nonsense rate is none
        #expect(RequestFilter.speed(Self.board(speeds: [:])) == 0)
        #expect(RequestFilter.speed(Self.board(cancelling: [], speeds: [1: .nan, 8: -5])) == 0)
        #expect(RequestFilter.speed(.nothing) == 0)
    }

    @Test func aRowsSpeedIsTheDataLinesRateOrADash() {
        let board = Self.board()
        let first = board.rows(.downloading)[0]
        #expect(RequestFilter.speedText(first) == "244 KB/s")
        #expect(first.data == "3 of 11 files \u{00B7} 244 KB/s", "the very rate the card's data line says")
        #expect(RequestFilter.speedText(board.rows(.done)[0]) == "\u{2014}")
        #expect(RequestFilter.speedText(board.rows(.downloading)[1]) == "\u{2014}", "cancelling: no rate")
    }

    @Test func theStatusBarSaysEachHeadingsCountThenTheSpeed() {
        #expect(RequestFilter.status(Self.board())
                == ["3 downloading", "2 waiting", "1 needs attention", "2 done", "244 KB/s"])
        let two = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 4, status: "failed", artist: "A", album: "B", username: "c"),
            DownloadJob(id: 5, status: "cancelled", artist: "D", album: "E", username: "f"),
        ]), now: Self.now)
        #expect(RequestFilter.status(two) == ["2 need attention"])
        #expect(RequestFilter.status(.nothing) == [])
    }

    // MARK: the rows' columns

    @Test func eachRowSaysWhoItComesFromAndWhatItsDoing() {
        let board = Self.board()
        let first = board.rows(.downloading)[0]
        #expect(first.from == "glassbeads" && first.progressWords == "3 of 11 files")
        #expect(first.speed == 249_856)
        #expect(board.rows(.downloading)[1].progressWords == "cancelling\u{2026}")
        #expect(board.rows(.downloading)[2].progressWords == "12 of 12 files \u{00B7} adding to your library\u{2026}")
        let waiting = board.rows(.waiting)
        #expect(waiting[0].from == "trigger" && waiting[0].progressWords == "starting\u{2026}")
        #expect(waiting[1].from == "rustin" && waiting[1].progressWords == "4th in their queue")
        // a refused row says itself otherwise; a finished one how it ended, and how long ago apart from it
        #expect(board.rows(.attention)[0].progressWords == nil && board.rows(.attention)[0].when == nil)
        let done = board.rows(.done)[0]
        #expect(done.from == "joga" && done.progressWords == "In your library" && done.when == "14 hours ago")
        #expect(done.line == "In your library \u{00B7} 14 hours ago", "the line's two halves")
        #expect(board.rows(.downloading)[0].when == nil)
        // no peer named, none drawn
        let unnamed = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 1, status: "queued", artist: "A", album: "B", username: ""),
        ]), now: Self.now)
        #expect(unnamed.rows(.waiting)[0].from == nil)
    }

    // MARK: the Mac's table

    @Test func theMacsColumnsAreTheDrawings() {
        #expect(RequestColumns.Column.allCases.map { RequestColumns.title($0) }
                == ["Album", "Artist", "From", "Progress", "Speed", ""])
        #expect(RequestColumns.widths.count == RequestColumns.Column.allCases.count)
        #expect(RequestColumns.widths.filter { $0 == .flexible }.count == 1 && RequestColumns.widths[0] == .flexible)
        #expect(Array(RequestColumns.widths[1...5]) == [.fixed(160), .fixed(124), .fixed(226), .fixed(92), .fixed(240)])
        #expect(RequestColumns.rowHeight == 34 && RequestColumns.cover == 22)
        // a wide page gives the album what's left; a narrow one keeps every column and scrolls
        let wide = RequestColumns.widths(1400)
        #expect(wide.reduce(0, +) == 1400 && wide[0] == 1400 - 842)
        let narrow = RequestColumns.widths(600)
        #expect(narrow[0] == RequestColumns.albumLeast && Array(narrow[1...]) == [160, 124, 226, 92, 240])
        #expect(RequestColumns.width(600) == 1002 && RequestColumns.width(2000) == 2000)
        #expect(RequestColumns.meterLeast == 48)
    }

    @Test func theTableFitsTheWindowAsItFirstOpens() {
        // (R8's review) the window as it opens, beside the sidebar: the page's own width, nothing to scroll sideways
        let page = MacFrame.openingWidth - MacLook.sidebarWidth
        #expect(page == 1060)
        #expect(RequestColumns.width(page) == page)
        let columns = RequestColumns.widths(page)
        #expect(columns.reduce(0, +) == page && columns[0] >= RequestColumns.albumLeast)
        // the least it takes, and the room that leaves
        #expect(RequestColumns.width(0) == 1002 && RequestColumns.width(0) <= page)
    }

    @Test func theToolbarFoldsToItsPage() {
        // as drawn, then narrower without the label, then with the filter and Clear done in one pop-up
        #expect(RequestTools.Fit.allCases == [.full, .compact, .folded])
        #expect((RequestTools.artistField(.full), RequestTools.albumField(.full)) == (170, 210))
        for fit in [RequestTools.Fit.compact, .folded] {
            #expect((RequestTools.artistField(fit), RequestTools.albumField(fit)) == (120, 140))
        }
        #expect(RequestTools.Fit.allCases.map { RequestTools.labelled($0) } == [true, false, false])
        #expect(RequestTools.Fit.allCases.map { RequestTools.folds($0) } == [false, false, true])
    }

    // MARK: a cancel that asked first

    @Test func aCancelThatAskedActsOnTheRowAsItIsNow() {
        let board = Self.board()
        // downloading or waiting, its cancel ready: the row as the board has it now
        #expect(RequestFilter.cancellable("job-1", in: board) == board.rows(.downloading)[0])
        #expect(RequestFilter.cancellable("job-3", in: board)?.key == "job-3")
        // being cancelled, being filed, refused, done, not yet a job, gone: nothing to cancel
        for key in ["job-8", "job-2", "job-4", "job-5", "p1", "job-99"] {
            #expect(RequestFilter.cancellable(key, in: board) == nil, "\(key)")
        }
        // the question asked over job 1 downloading, answered once it moved on: nothing is cancelled
        func moved(_ status: String, outcome: String? = nil) -> RequestsView {
            RequestsView.make(RequestsInput(jobs: [
                DownloadJob(id: 1, status: status, artist: "Portishead", album: "Dummy", username: "glassbeads",
                            outcome: outcome, progress: 100, filesDone: 11, filesTotal: 11),
            ]), now: Self.now)
        }
        #expect(RequestFilter.cancellable("job-1", in: moved("organizing")) == nil, "a filing can't be cancelled")
        #expect(RequestFilter.cancellable("job-1", in: moved("completed", outcome: "filed")) == nil, "nor one filed")
        #expect(RequestFilter.cancellable("job-1", in: moved("failed")) == nil)
        #expect(RequestFilter.cancellable("job-1", in: .nothing) == nil)
    }

    // MARK: what a row offers

    @Test func eachRowOffersWhatItsButtonsDoInTheAppsWords() {
        let board = Self.board()
        let first = board.rows(.downloading)[0], going = board.rows(.downloading)[1], filing = board.rows(.downloading)[2]
        let refused = board.rows(.attention)[0]
        // a done row whose album is in the library: it opens, and plays what was filed
        let done = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 5, status: "completed", artist: "Lamb", album: "Fear of Fours", username: "joga",
                        releaseMbid: "a1b2", outcome: "filed"),
        ]), now: Self.now).rows(.done)[0]
        #expect(done.opens != nil && done.plays)
        #expect(RequestAction.offered(board.rows(.done)[0], gets: true, online: true) == [], "one that opens nothing")
        #expect(RequestAction.offered(first, gets: true, online: true) == [.cancel])
        #expect(RequestAction.offered(first, gets: true, online: false) == [], "nothing cancels out of reach")
        #expect(RequestAction.offered(going, gets: true, online: true) == [], "already being cancelled")
        #expect(RequestAction.offered(filing, gets: true, online: true) == [], "a filing can't be cancelled")
        #expect(RequestAction.offered(refused, gets: true, online: true) == [.nextPeer, .askAgain])
        #expect(RequestAction.offered(refused, gets: false, online: true) == [], "without Get albums")
        var busy = refused
        busy.busy = true
        #expect(RequestAction.offered(busy, gets: true, online: true) == [], "while a way on runs")
        #expect(RequestAction.offered(done, gets: false, online: true) == [.play, .open])
        // the buttons column: the main one (faded while it can't be used), a done row's two; the rest in its •••
        #expect(RequestAction.buttons(going, gets: true) == [.cancel])
        #expect(RequestAction.buttons(filing, gets: true) == [])
        #expect(RequestAction.buttons(refused, gets: true) == [.nextPeer])
        #expect(RequestAction.more(refused, gets: true) == [.askAgain])
        #expect(RequestAction.buttons(done, gets: true) == [.play, .open] && RequestAction.more(done, gets: true) == [])
        #expect(RequestAction.more(first, gets: true) == [])
        // the words: the app's own
        #expect(RequestAction.allCases.map { $0.words(refused) }
                == ["Cancel", "Another source \u{00B7} 2 left", "Same source again", "Play", "Open"])
    }

    // MARK: what VoiceOver hears

    @Test func aRowIsReadAsOneWithEverythingItShows() {
        let board = Self.board()
        #expect(RequestSpoken.row(board.rows(.downloading)[0], runs: false)
                == "Dummy, Portishead, from glassbeads, 3 of 11 files, 244 KB/s")
        #expect(RequestSpoken.row(board.rows(.waiting)[1], runs: false)
                == "Lives Outgrown, Beth Gibbons, from rustin, 4th in their queue")
        #expect(RequestSpoken.row(board.rows(.done)[0], runs: false, note: "It's not in the library yet")
                == "Fear of Fours, Lamb, from joga, In your library \u{00B7} 14 hours ago, It's not in the library yet")
        let refused = board.rows(.attention)[0]
        #expect(RequestSpoken.row(refused, runs: true).hasPrefix("Felt Mountain, Goldfrapp, from lovely, "))
        // which try, and who asked: the row's help on the Mac, said here
        let shared = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 7, status: "queued", artist: "Lamb", album: "Lamb", username: "joga", queuePosition: 2,
                        attempt: 2, mine: true, shared: true, requestedBy: ["Ethan"]),
        ]), now: Self.now).rows(.waiting)[0]
        #expect(shared.tries == "2nd try" && shared.askedBy == "Asked by you and Ethan")
        #expect(RequestSpoken.row(shared, runs: false)
                == "Lamb, Lamb, from joga, 2nd in their queue, 2nd try, Asked by you and Ethan")
        #expect(Self.board().rows(.downloading)[0].tries == nil, "a first try says none")
        #expect(RequestSpoken.help(shared) == "Lamb\n2nd try\nAsked by you and Ethan")
        #expect(RequestSpoken.help(board.rows(.downloading)[0]) == "Dummy")
        // the phone's card, its lines as drawn
        #expect(RequestSpoken.card(board.rows(.downloading)[0], runs: false, gets: true)
                == "Dummy, Portishead \u{00B7} from glassbeads, 3 of 11 files \u{00B7} 244 KB/s")
        #expect(RequestSpoken.card(refused, runs: false, gets: false).hasSuffix(RequestWords.getOff))
        #expect(RequestSpoken.card(board.rows(.done)[0], runs: false, gets: true, filed: "Filed by its own tags")
                == "Fear of Fours, In your library \u{00B7} 14 hours ago, Filed by its own tags")
    }

    @Test func aRefusalSaysToTellWhoeverRunsDeadwaxOnlyToEveryoneElse() {
        var row = Self.board().rows(.attention)[0]
        row.reason = "It broke"
        row.reasonTell = true
        #expect(RequestSpoken.reason(row, runs: false) == "It broke \(ErrorWords.tell)")
        #expect(RequestSpoken.reason(row, runs: true) == "It broke")
    }

    // MARK: how one done ended, in a chip

    @Test func theDoneChipSaysWhatMattersFirstInAFewWords() {
        func chip(_ outcome: String?, mine: Bool? = nil, library: String? = nil, error: String? = nil) -> String {
            RequestWords.chipWords(DownloadJob(id: 1, status: "completed", error: error, outcome: outcome, mine: mine,
                                               library: library))
        }
        #expect(chip("filed") == "In your library")
        #expect(chip("filed", mine: false, library: "added") == "In their library")
        #expect(chip("already_there") == "You already had it")
        #expect(chip("already_there", mine: true, library: "added") == "Added to your library")
        #expect(chip("already_there", mine: false, library: "added") == "Added to their library")
        #expect(chip("already_there", library: "flagged") == "Not added" && chip("already_there", library: "looked") == "Not added")
        #expect(chip("partly_filed", error: "3 files couldn't be added") == "Partly in your library")
        #expect(chip("partly_filed", mine: false, library: "incomplete") == "Partly in their library")
        #expect(chip("interrupted") == "Stopped")
        #expect(chip(nil) == "Not added" && chip("not_filed", error: "disk full") == "Not added")
        // a chip's few words fit the Progress column (206 across): never more than 23 letters
        let every = [chip("filed"), chip("filed", mine: false, library: "added"), chip("already_there"),
                     chip("already_there", mine: false, library: "added"), chip("partly_filed"),
                     chip("partly_filed", mine: false, library: "incomplete"), chip("interrupted"), chip(nil)]
        #expect(every.allSatisfy { $0.count <= 23 }, "\(every)")
        // the row: the chip, the sentence in full beside it in its help and what VoiceOver hears
        let row = Self.board().rows(.done)[0]
        #expect(row.chip == "In your library" && row.progressWords == "In your library")
        let warned = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 9, status: "completed", artist: "A", album: "B", username: "c", outcome: "not_filed"),
        ]), now: Self.now)
        let notAdded = (warned.rows(.done) + warned.rows(.attention))[0]
        #expect(notAdded.section != .done || notAdded.chip == "Not added")
        let stopped = RequestsView.make(RequestsInput(jobs: [
            DownloadJob(id: 9, status: "completed", artist: "A", album: "B", username: "c", outcome: "interrupted"),
        ]), now: Self.now).rows(.done)[0]
        #expect(stopped.chip == "Stopped" && stopped.progressWords == "Stopped while being added to your library")
        #expect(stopped.lineTone == .warning)
    }

    @Test func theMacsButtonsSayWhatTheyDo() {
        let first = Self.board().rows(.downloading)[0]
        #expect(RequestColumns.cancel(first) == "Cancel")
        var leaving = first
        leaving.cancelWords = CancelWords(question: "Leave it?", action: "Leave it", leaves: true)
        #expect(RequestColumns.cancel(leaving) == "Leave")
        #expect(RequestColumns.play == "Play" && RequestColumns.open == "Open" && RequestFilter.spoken == "Show")
        #expect(RequestFilter.allCases.map { $0.nothing } == ["Nothing requested yet", "Nothing on its way", "Nothing done yet"])
    }

    // MARK: the meter

    @Test func aMetersFillNeverPassesItsTrack() {
        #expect(DWLook.meterShare(0.4) == 0.4)
        #expect(DWLook.meterShare(1) == 1 && DWLook.meterShare(0) == 0)
        #expect(DWLook.meterShare(1.04) == 1)
        #expect(DWLook.meterShare(-0.03) == 0)
        #expect(DWLook.meterShare(.nan) == 0 && DWLook.meterShare(.infinity) == 0 && DWLook.meterShare(-.infinity) == 0)
        // a row's progress is 0-100, and organizing's a whole bar
        let board = Self.board()
        #expect(board.rows(.downloading).map { DWLook.meterShare($0.progress / 100) } == [0.4, 0.1, 1])
    }

    @Test func theMetersHeightIsDwCssOnEachDevice() {
        #expect(DWLook.of(.mac).meterHeight == 6)
        #expect(DWLook.of(.iPhone).meterHeight == 8)
        // the phone's grows with the text, the Mac's is exact
        #expect(DWLook.of(.iPhone).grows && !DWLook.of(.mac).grows)
    }
}
