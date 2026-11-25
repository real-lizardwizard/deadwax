import Foundation

// Requests' filter, its counts and its speed (the Mac and iPhone redesign, slice R8 - notes/ios.md "The redesign, slice
// R8: Requests"; the drawings Requests.dc.html and iRequests.dc.html). The Mac's Requests is a table under a toolbar's
// All | Active | Done, grouped Downloading, Waiting, Needs attention and Done, its status bar saying how many there are
// of each and how fast they come all together; the phone's is the same four headings over cards. What both draw from
// the board (RequestsView) is said here, tested on Linux:
//
// - which headings a filter shows - each only with a row under it, on both devices: never a heading over nothing;
// - how many rows each heading and each filter holds;
// - the speed summed: every downloading row's rate as measured here, never a finished download's (nor a waiting one's,
//   nor one being cancelled or filed, whose data line says no rate either);
// - the status bar's words, and the Mac's table as Requests.dc.html draws it.
//
// None of it is new data: the board's rows, and the rate RequestsModel already measures for each (RequestRow.speed).
//
// (R8's review) And what a row offers to be done (RequestAction - the Mac's buttons, its ••• and right-click, and
// VoiceOver's actions on both devices), what VoiceOver hears of a row as one element (RequestSpoken), the row a Cancel
// that asked first acts on (RequestFilter.cancellable - the row as it is now, never as it was when Cancel was clicked),
// and the Mac's toolbar folding to its page (RequestTools).

/// The Mac toolbar's All | Active | Done: which headings the table shows.
public enum RequestFilter: String, CaseIterable, Sendable, Hashable {
    /// Every heading.
    case all
    /// What isn't done yet - downloading, waiting, and needing attention: everything still to finish one way or another.
    case active
    /// Done alone.
    case done

    /// The segment's words.
    public var label: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .done: return RequestWords.title(.done)
        }
    }

    /// What VoiceOver calls the control.
    public static let spoken = "Show"

    /// The headings this filter takes, in the board's order.
    public var sections: [RequestSection] {
        switch self {
        case .all: return RequestSection.allCases
        case .active: return [.downloading, .waiting, .attention]
        case .done: return [.done]
        }
    }

    /// The headings drawn: this filter's, each only with a row under it.
    public func shown(_ board: RequestsView) -> [RequestSection] {
        sections.filter { (section: RequestSection) -> Bool in !board.rows(section).isEmpty }
    }

    /// What the Mac's table draws, line by line: each heading shown, then its rows by key (MacTable's lines - the
    /// stripes start again under each heading).
    public func lines(_ board: RequestsView) -> [MacTable.Line<String>] {
        shown(board).flatMap { (section: RequestSection) -> [MacTable.Line<String>] in
            [MacTable.Line<String>.group(RequestWords.title(section))]
                + board.rows(section).map { (row: RequestRow) -> MacTable.Line<String> in .row(row.key) }
        }
    }

    /// How many rows it shows.
    public func count(_ board: RequestsView) -> Int {
        sections.reduce(0) { (sum: Int, section: RequestSection) -> Int in sum + board.rows(section).count }
    }

    /// What the table says where this filter shows nothing, on a board that has something.
    public var nothing: String {
        switch self {
        case .all: return RequestWords.nothingYet
        case .active: return "Nothing on its way"
        case .done: return "Nothing done yet"
        }
    }

    // MARK: the speed

    /// A row's rate where it counts: a downloading row's, while it can be cancelled - not one being cancelled or filed
    /// (its data line says no rate then), nor a waiting, refused or finished one's, whatever was measured for it. Bytes
    /// a second; nil for none.
    public static func rate(_ row: RequestRow) -> Double? {
        guard row.section == .downloading, row.cancel == .ready, let speed = row.speed, speed.isFinite,
              speed > 0 else { return nil }
        return speed
    }

    /// The speed summed over the whole board: every row's rate that counts (`rate`) - bytes a second, 0 with none.
    public static func speed(_ board: RequestsView) -> Double {
        RequestSection.allCases
            .flatMap { (section: RequestSection) -> [RequestRow] in board.rows(section) }
            .compactMap { (row: RequestRow) -> Double? in rate(row) }
            .reduce(0, +)
    }

    /// A row's Speed column: its rate as the data line writes it ("244 KB/s"), or a dash for none.
    public static func speedText(_ row: RequestRow) -> String {
        rate(row).map { (speed: Double) -> String in RequestWords.speed(speed) } ?? RequestColumns.none
    }

    // MARK: a cancel that asked first

    /// (R8's review) The row a Cancel asked about, as the board has it now - while it can still be cancelled: a job
    /// downloading or waiting, its cancel ready. Nil once it has moved on (being filed, filed, refused, already being
    /// cancelled, gone), so a question answered late cancels nothing it didn't ask about: deadwax's cancel route takes
    /// a job whatever it is doing, and a filing cancelled, or an album filed marked cancelled, can't be put back.
    public static func cancellable(_ key: String, in board: RequestsView) -> RequestRow? {
        for section in [RequestSection.downloading, .waiting] {
            if let row = board.rows(section).first(where: { (row: RequestRow) -> Bool in row.key == key }) {
                return row.jobId != nil && row.cancel == .ready ? row : nil
            }
        }
        return nil
    }

    // MARK: the status bar

    /// The Mac's status bar: how many under each heading that has any - "1 downloading", "2 waiting", "1 needs
    /// attention", "3 done" - then the speed summed while anything comes ("244 KB/s"). Nothing for an empty board.
    public static func status(_ board: RequestsView) -> [String] {
        let counts = RequestCounts(board)
        var facts: [String] = []
        if counts.downloading > 0 { facts.append("\(counts.downloading) downloading") }
        if counts.waiting > 0 { facts.append("\(counts.waiting) waiting") }
        if counts.attention > 0 { facts.append("\(counts.attention) \(counts.attention == 1 ? "needs" : "need") attention") }
        if counts.done > 0 { facts.append("\(counts.done) done") }
        let speed = speed(board)
        if speed > 0 { facts.append(RequestWords.speed(speed)) }
        return facts
    }
}

/// How many rows are under each heading.
public struct RequestCounts: Equatable, Sendable {
    public var downloading: Int
    public var waiting: Int
    public var attention: Int
    public var done: Int

    public init(downloading: Int, waiting: Int, attention: Int, done: Int) {
        self.downloading = downloading
        self.waiting = waiting
        self.attention = attention
        self.done = done
    }

    /// The board's.
    public init(_ board: RequestsView) {
        self.init(downloading: board.rows(.downloading).count, waiting: board.rows(.waiting).count,
                  attention: board.rows(.attention).count, done: board.rows(.done).count)
    }

    /// Under one heading.
    public func of(_ section: RequestSection) -> Int {
        switch section {
        case .downloading: return downloading
        case .waiting: return waiting
        case .attention: return attention
        case .done: return done
        }
    }

    /// What a filter shows.
    public func of(filter: RequestFilter) -> Int {
        filter.sections.reduce(0) { (sum: Int, section: RequestSection) -> Int in sum + of(section) }
    }
}

/// The Mac's table as Requests.dc.html draws it: its columns, their words and widths, its rows' height and covers.
/// tests/test_ios_requests_look.py holds each drawn number to the drawing.
public enum RequestColumns {
    public enum Column: String, CaseIterable, Sendable {
        case album, artist, from, progress, speed, actions
    }

    /// A column's heading - none over the buttons.
    public static func title(_ column: Column) -> String {
        switch column {
        case .album: return "Album"
        case .artist: return "Artist"
        case .from: return "From"
        case .progress: return "Progress"
        case .speed: return "Speed"
        case .actions: return ""
        }
    }

    /// Each column's width, in Column's order: the album takes what the rest leave. The buttons' 240 holds a row's main
    /// action and its ••• (RequestAction.buttons): the app's own words, "Another source · 12 left", are longer than the
    /// drawing's "Next peer · 2 left", so the second way on goes in the ••• rather than the column growing past the page.
    public static let widths: [MacTable.Width] = [
        .flexible,      // drawn: Requests .cols > div.grow
        .fixed(160),    // drawn: Requests .cols > div width 2
        .fixed(124),    // drawn: Requests .cols > div width 3
        .fixed(226),    // drawn: Requests .cols > div width 4
        .fixed(92),     // drawn: Requests .cols > div width 5
        .fixed(240),    // drawn: Requests .cols > div width 6
    ]

    /// The album's least width: narrower than the columns need, the table scrolls sideways rather than squeeze them -
    /// in a window as it first opens (1280, the page 1060 beside the sidebar) it never does: 842 and 160 are 1002.
    public static let albumLeast: Double = 160

    /// The table's width in a page `total` wide: the page's, or the least the columns take where the page is narrower.
    public static func width(_ total: Double) -> Double {
        let fixed = widths.reduce(0.0) { (sum: Double, width: MacTable.Width) -> Double in
            if case .fixed(let points) = width { return sum + points }
            return sum
        }
        return max(total, fixed + albumLeast)
    }

    /// The columns' widths in a page `total` wide.
    public static func widths(_ total: Double) -> [Double] {
        MacTable.widths(widths, total: width(total))
    }

    /// A row (the drawing's 34, over dw.css's .row 30: a cover and a meter in it) and its cover.
    public static let rowHeight: Double = 34        // drawn: Requests .row height
    public static let cover: Double = 22            // drawn: Requests .cover width

    /// (R8's review) A download's meter, never narrower: its words beside it are cut short first (their whole in the
    /// help and in what VoiceOver hears) - dw.css's .meter has min-width 0, which in a cell would let a long line
    /// squeeze it away.
    public static let meterLeast: Double = 48

    /// A cell with nothing to say: a waiting row's speed, a done one's.
    public static let none = "\u{2014}"

    // MARK: the row's buttons

    /// A download's Cancel - Leave where it only withdraws your request (VoiceOver: RequestWords.cancelLabel).
    public static func cancel(_ row: RequestRow) -> String { row.cancelWords.leaves ? "Leave" : "Cancel" }
    /// A done row's: its album played from the first song, and its album opened.
    public static let play = "Play"
    public static let open = "Open"
}

/// (R8's review) What can be done to a row, each in the app's own words: the Mac's buttons, its ••• and right-click, and
/// VoiceOver's actions on a row (the Mac's) or a card (the phone's), each one element.
public enum RequestAction: String, CaseIterable, Sendable, Hashable {
    case cancel, nextPeer, askAgain, play, open

    /// Its words on `row`: Cancel or Leave; "Another source · 2 left" or "Trying another source…"; Same source again;
    /// Play; Open.
    public func words(_ row: RequestRow) -> String {
        switch self {
        case .cancel: return RequestColumns.cancel(row)
        case .nextPeer: return row.nextPeer?.label ?? RequestWords.anotherSource(0)
        case .askAgain: return row.askAgain?.label ?? RequestWords.sameSource
        case .play: return RequestColumns.play
        case .open: return RequestColumns.open
        }
    }

    /// What can be done to `row` now, in its buttons' order - VoiceOver's actions and the right-click's items: a cancel
    /// only while it can be (a job, not being cancelled or filed) and deadwax is in reach; the two ways on only with
    /// Get albums (`gets`) and while neither runs; Play where it plays; Open where it opens.
    public static func offered(_ row: RequestRow, gets: Bool, online: Bool) -> [RequestAction] {
        switch row.section {
        case .downloading, .waiting:
            return row.jobId != nil && row.cancel == .ready && online ? [.cancel] : []
        case .attention:
            guard gets, !row.busy else { return [] }
            return [row.nextPeer != nil ? .nextPeer : nil, row.askAgain != nil ? .askAgain : nil].compactMap { $0 }
        case .done:
            guard row.opens != nil else { return [] }
            return row.plays ? [.play, .open] : [.open]
        }
    }

    /// The Mac's buttons column (240): a row's main action - drawn, faded, while it can't be used (being cancelled, a
    /// way on running) - and a done row's Open beside its Play, as drawn (both fit). A refused row's second way on is
    /// its ••• (`more`).
    public static func buttons(_ row: RequestRow, gets: Bool) -> [RequestAction] {
        switch row.section {
        case .downloading, .waiting:
            return row.cancel != nil ? [.cancel] : []
        case .attention:
            guard gets else { return [] }
            if row.nextPeer != nil { return [.nextPeer] }
            return row.askAgain != nil ? [.askAgain] : []
        case .done:
            guard row.opens != nil else { return [] }
            return row.plays ? [.play, .open] : [.open]
        }
    }

    /// What the row's ••• holds: what it offers that its buttons don't show - a refused row's Same source again beside
    /// Another source. Nothing, and no •••, for every other row.
    public static func more(_ row: RequestRow, gets: Bool) -> [RequestAction] {
        let shown = buttons(row, gets: gets)
        return offered(row, gets: gets, online: true).filter { (action: RequestAction) -> Bool in !shown.contains(action) }
    }
}

/// (R8's review) What VoiceOver hears of a row read as one element - its words in the order they're drawn - with its
/// actions (RequestAction.offered) named after it. Nothing a row shows is left out of it: who asked and which try
/// included, which on the Mac are its help.
public enum RequestSpoken {
    /// A refusal's reason as the row says it: with "Tell whoever runs deadwax." where it would, for anyone else.
    public static func reason(_ row: RequestRow, runs: Bool) -> String? {
        row.reason.map { (reason: String) -> String in row.reasonTell && !runs ? "\(reason) \(ErrorWords.tell)" : reason }
    }

    /// The Mac's row, its columns in order: "Dummy, Portishead, from glassbeads, 3 of 11 files, 244 KB/s" - then which
    /// try and who asked. A done one says how it ended in full ("Downloaded, but not added to your library · 2 hours
    /// ago"), and `note` (why it couldn't open) after.
    public static func row(_ row: RequestRow, runs: Bool, note: String? = nil) -> String {
        var said: [String?] = [row.title, row.artist, row.from.map { (peer: String) -> String in "from \(peer)" }]
        switch row.section {
        case .downloading:
            said += [row.progressWords, RequestFilter.rate(row).map { (speed: Double) -> String in RequestWords.speed(speed) }]
        case .waiting:
            said.append(row.progressWords ?? row.brief)
        case .attention:
            said += [row.problem, reason(row, runs: runs)]
        case .done:
            said += [row.line, note]
        }
        said += [row.tries, row.askedBy]
        return joined(said)
    }

    /// The phone's card, its lines in order: the title, its line ("Portishead · from glassbeads · 2nd try"), who asked,
    /// a download's data line, a refusal's reason and a retry's refusal - without Get albums, the line saying so - and
    /// a done one's `filed` and `note`.
    public static func card(_ row: RequestRow, runs: Bool, gets: Bool, filed: String? = nil, note: String? = nil) -> String {
        var said: [String?] = [row.title, row.line, row.askedBy]
        switch row.section {
        case .downloading:
            said.append(row.data)
        case .waiting:
            break
        case .attention:
            said += [reason(row, runs: runs), row.problem,
                     !gets && (row.nextPeer != nil || row.askAgain != nil) ? RequestWords.getOff : nil]
        case .done:
            said += [filed, !runs && row.reasonTell ? ErrorWords.tell : nil, note]
        }
        return joined(said)
    }

    /// The Mac's help over a row's album: its whole title (the cell cuts it short), which try, and who asked - one a line.
    public static func help(_ row: RequestRow) -> String {
        [row.title, row.tries, row.askedBy].compactMap { $0 }.joined(separator: "\n")
    }

    static func joined(_ said: [String?]) -> String {
        said.compactMap { $0 }
            .map { (words: String) -> String in JSText.trim(words) }
            .filter { (words: String) -> Bool in !words.isEmpty }
            .joined(separator: ", ")
    }
}

/// (R8's review) The Mac's toolbar, folding to its page: as drawn where it fits (Search Soulseek's label, the fields
/// 170 and 210, Search, All | Active | Done, Clear done at the right - about 855 points); then without the label and
/// with narrower fields (`compact`, about 630 - the smallest window's page is 660); then with All | Active | Done and
/// Clear done folded into one pop-up (`folded`, about 440 - the least page beside a side panel's column is 589). The
/// page draws the first that fits (ViewThatFits); tests/test_ios_requests_look.py adds each up.
public enum RequestTools {
    public enum Fit: String, CaseIterable, Sendable {
        case full, compact, folded
    }

    /// The Artist field's width.
    public static func artistField(_ fit: Fit) -> Double {
        fit == .full ? 170 : 120    // drawn: Requests .bar .in width 1
    }

    /// The Album field's width.
    public static func albumField(_ fit: Fit) -> Double {
        fit == .full ? 210 : 140    // drawn: Requests .bar .in width 2
    }

    /// Whether "Search Soulseek" stands before the fields (the fields' prompts and VoiceOver name them without it).
    public static func labelled(_ fit: Fit) -> Bool { fit == .full }

    /// Whether All | Active | Done and Clear done are one pop-up, named for what it shows.
    public static func folds(_ fit: Fit) -> Bool { fit == .folded }
}
