import Foundation

/// The redesign's slice R7 (notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)"): Search's rows
/// as the Mac's table draws them (Search.dc.html) - its columns, what each row says in them, the buttons it offers and
/// the status bar's counts - and the words the Get page and Sources add on both devices (Get.dc.html, iGet.dc.html,
/// iSources.dc.html). Pure: SearchScreen, MacSearchPage, GroupView, MacGetPage and SourcesSheet draw them.
public enum SearchTable {
    // MARK: the columns

    public enum Column: String, CaseIterable, Sendable {
        case name, kind, artist, year, place, actions
    }

    /// A column's heading - none over the buttons.
    public static func title(_ column: Column) -> String {
        switch column {
        case .name: return "Name"
        case .kind: return "Kind"
        case .artist: return "Artist"
        case .year: return "Year"
        case .place: return "In your library"
        case .actions: return ""
        }
    }

    /// A column's width: the name takes what the rest leave.
    public static func width(_ column: Column) -> MacTable.Width {
        switch column {
        case .name: return .flexible        // drawn: Search .cols > div.grow
        case .kind: return .fixed(100)      // drawn: Search .cols > div width 2
        case .artist: return .fixed(190)    // drawn: Search .cols > div width 3
        case .year: return .fixed(64)       // drawn: Search .cols > div width 4
        case .place: return .fixed(200)     // drawn: Search .cols > div width 5
        case .actions: return .fixed(170)   // drawn: Search .cols > div width 6
        }
    }

    /// The name's least width, as Requests' album's (RequestColumns.albumLeast).
    public static let nameLeast: Double = 160

    /// The name's least at a row size: its cover's growth on top of the 160, so the title keeps the room it has at Small.
    public static func nameLeast(_ size: MacRowSize) -> Double {
        nameLeast + size.requestCoverGrowth
    }

    /// The columns given up, in this order, where the page is too narrow for every one beside the name's least: the
    /// year, then the kind, then the artist - the place and the buttons are what a row is for, and never go. A window
    /// as it first opens (1280, the page 1060) shows them all (724 and 160 are 884); at 880 (the page 660), or beside the
    /// side panel at 1280 (589), the name, the place and the buttons.
    public static let givenUp: [Column] = [.year, .kind, .artist]

    /// The columns shown in a page `total` wide, at the rows' size.
    public static func columns(_ total: Double, size: MacRowSize = .standard) -> [Column] {
        var shown = Column.allCases
        for column in givenUp where fixed(shown) + nameLeast(size) > total {
            shown.removeAll { $0 == column }
        }
        return shown
    }

    /// The fixed columns' room.
    static func fixed(_ columns: [Column]) -> Double {
        columns.reduce(0.0) { (sum: Double, column: Column) -> Double in
            if case .fixed(let points) = width(column) { return sum + points }
            return sum
        }
    }

    /// The table's width in a page `total` wide: the page's, or the least its columns take where the page is narrower
    /// still - there, and only there, it scrolls sideways.
    public static func tableWidth(_ columns: [Column], _ total: Double, size: MacRowSize = .standard) -> Double {
        max(total, fixed(columns) + nameLeast(size))
    }

    /// The columns' widths in a page `total` wide, in `columns`' order.
    public static func widths(_ columns: [Column], _ total: Double, size: MacRowSize = .standard) -> [Double] {
        MacTable.widths(columns.map(width), total: tableWidth(columns, total, size: size))
    }

    // MARK: a row's cells

    /// What a row says in the columns beside its name: its kind, its artist, its year, and where it is - "in your
    /// library", "2 albums in your library", "maybe in your library", "not in your library" - with `held` saying the
    /// place is drawn as the green chip (Search.dc.html's), not in the third colour.
    public struct Cells: Sendable, Equatable {
        public let kind: String
        public let artist: String
        public let year: String
        public let place: String
        public let held: Bool
        /// What the name's help adds: a MusicBrainz artist's line ("UK trip hop band, Group, GB").
        public let about: String

        public init(kind: String, artist: String, year: String, place: String, held: Bool, about: String = "") {
            self.kind = kind
            self.artist = artist
            self.year = year
            self.place = place
            self.held = held
            self.about = about
        }
    }

    /// Not held, said only once the library has answered (`marks.index`): before then nothing is claimed.
    public static let notHeld = "not in your library"

    /// A row's cells, the place as its line says it (SearchList.line) - a MusicBrainz album or song the library has
    /// answered for and holds none of is "not in your library", as the album you don't have says it.
    public static func cells(_ row: SearchRow, _ marks: SearchMarks) -> Cells {
        let place = SearchList.line(row, marks).place
        let answered = marks.index != nil
        func unheld(_ place: String) -> String {
            place.isEmpty && answered ? notHeld : place
        }
        switch row {
        case .artist:
            return Cells(kind: "Artist", artist: "", year: "", place: place, held: !place.isEmpty)
        case .album(let album):
            return Cells(kind: "Album", artist: album.artist ?? "", year: year(album.year), place: place,
                         held: !place.isEmpty)
        case .song(let song):
            return Cells(kind: "Song", artist: song.artist ?? "", year: year(song.year), place: place, held: !place.isEmpty)
        case .group(let group):
            let held = SearchAlbums.held(marks.index, group.id)
            return Cells(kind: SearchAlbums.kind(group), artist: Credits.name(group.artistCredit),
                         year: SearchAlbums.year(group) ?? "", place: unheld(place), held: held)
        case .mbArtist(let match):
            return Cells(kind: "Artist", artist: "", year: "", place: "", held: false, about: match.line)
        case .mbSong(let song):
            let (album, _) = SongSearch.namedAlbum(song, marks.index, marks.evidence)
            return Cells(kind: "Song", artist: song.credit, year: SongSearch.yearOf(album.date), place: unheld(place),
                         held: !place.isEmpty)
        case .songAlbum(_, let album):
            return Cells(kind: album.kind.isEmpty ? "Album" : album.kind, artist: album.credit,
                         year: SongSearch.yearOf(album.date), place: unheld(place), held: !place.isEmpty)
        }
    }

    private static func year(_ year: Int?) -> String {
        guard let year, year > 0 else { return "" }
        return String(year)
    }

    // MARK: a row's buttons

    /// What a row's buttons do (Search.dc.html's Play, Open and Get): a song played from its album, a page opened -
    /// yours, or the album you don't have to get.
    public enum Action: String, CaseIterable, Sendable {
        case play, open, get

        public var words: String {
            switch self {
            case .play: return "Play"
            case .open: return "Open"
            case .get: return "Get"
            }
        }

        /// VoiceOver's name for it on a row: "Play Roads", "Get Portishead".
        public func spoken(_ title: String) -> String {
            title.isEmpty ? words : "\(words) \(title)"
        }
    }

    /// A row's buttons, its main one first - the one its double-click and VoiceOver's own action take. A song plays when
    /// its album's songs are in hand (`plays`), and opens its album whether or not; an album or an artist of the
    /// library's opens; MusicBrainz's opens what you hold (yours, by the id bridge) and gets what you don't - the album
    /// you don't have, where Get the album is. Nothing for a row that can do nothing (a song on no album).
    /// (A library album has no Play: its songs aren't in hand on Search, and the plan asks for no new asks.)
    public static func actions(_ row: SearchRow, plays: Bool, held: Bool, opens: Bool = true) -> [Action] {
        switch row {
        case .song:
            return (plays ? [.play] : []) + (opens ? [.open] : [])
        case .artist, .album, .mbArtist:
            return [.open]
        case .group, .songAlbum, .mbSong:
            return [held ? .open : .get]
        }
    }

    // MARK: the rows in order

    /// A row's line on the Mac's table: its key - Top results' kept apart, the same artist or album drawn again in its
    /// section being a line of its own to select.
    public static func lineID(_ row: SearchRow, top: Bool) -> String {
        top ? "top|\(row.key)" : row.key
    }

    /// The All view's lines in the order the table draws them, for ↑ ↓ Home End: Top results', then each section's -
    /// MusicBrainz's left out while deadwax can't be reached, as the list leaves them out. A song's albums, opened under
    /// it, are clicked, never moved through.
    public static func order(_ drawn: SearchList.Drawn, online: Bool) -> [String] {
        func shown(_ rows: [SearchRow]) -> [SearchRow] {
            SearchList.drawable(online ? rows : rows.filter { !$0.isMusicBrainz })
        }
        let top = shown(drawn.top).map { lineID($0, top: true) }
        let sections = (drawn.sections ?? []).flatMap { shown($0.rows).map { lineID($0, top: false) } }
        return top + sections
    }

    /// A kind view's lines in the order drawn: the library's, then (deadwax in reach) what's saved, MusicBrainz's and
    /// what landed below them.
    public static func order(_ kind: KindView, online: Bool) -> [String] {
        var rows = kind.libraryRows
        if online {
            rows += kind.savedRows
            if case .rows(let found)? = kind.foot { rows += found }
            rows += kind.below
        }
        return SearchList.drawable(rows).map { lineID($0, top: false) }
    }

    /// (R7's review) The All view's rows striped on the table, by their lines (`lineID`): every other row through Top
    /// results and through each section, starting again only under a heading - Search.dc.html's `k = 0` at each group,
    /// as MacTable.stripes counts - never at a run's end within one. A song's albums, opened under it, take its stripe.
    public static func striped(_ drawn: SearchList.Drawn, online: Bool) -> Set<String> {
        func shown(_ rows: [SearchRow]) -> [SearchRow] {
            SearchList.drawable(online ? rows : rows.filter { !$0.isMusicBrainz })
        }
        var lines: [MacTable.Line<String>] = [.group(SearchWords.topResults)]
        lines += shown(drawn.top).map { (row: SearchRow) -> MacTable.Line<String> in .row(lineID(row, top: true)) }
        for section in drawn.sections ?? [] {
            lines.append(.group(SearchWords.section(section.kind)))
            lines += shown(section.rows).map { (row: SearchRow) -> MacTable.Line<String> in .row(lineID(row, top: false)) }
        }
        return stripedLines(lines)
    }

    /// (R7's review) A kind view's: one run under its heading, through the library's, what's saved, MusicBrainz's and
    /// what landed below them - drawn as separate runs, striped as one.
    public static func striped(_ kind: KindView, online: Bool) -> Set<String> {
        let rows = order(kind, online: online).map { (id: String) -> MacTable.Line<String> in .row(id) }
        return stripedLines([.group(SearchWords.section(kind.kind))] + rows)
    }

    private static func stripedLines(_ lines: [MacTable.Line<String>]) -> Set<String> {
        var striped: Set<String> = []
        for (line, stripe) in zip(lines, MacTable.stripes(lines)) {
            if stripe, case .row(let id) = line { striped.insert(id) }
        }
        return striped
    }

    // MARK: the status bar

    /// The status bar's counts (Search.dc.html: "2 artists · 5 albums · 6 songs · 5 in your library"): the rows drawn by
    /// kind, a MusicBrainz row with yours, and how many of them are held - nothing while none are drawn. With a library of
    /// your own, "in your library" counts only yours, never the collection's.
    public static func status(_ rows: [SearchRow], _ marks: SearchMarks) -> [String] {
        guard !rows.isEmpty else { return [] }
        var counts: [SearchKind: Int] = [:]
        var held = 0
        for row in rows {
            counts[row.kind, default: 0] += 1
            let cells = cells(row, marks)
            if cells.held && cells.place.hasSuffix(Whose.inYourLibrary) && !cells.place.hasPrefix("maybe") { held += 1 }
        }
        var said: [String] = []
        for (kind, one, many) in [(SearchKind.artists, "artist", "artists"), (.albums, "album", "albums"),
                                  (.songs, "song", "songs")] {
            if let count = counts[kind], count > 0 { said.append("\(count) \(count == 1 ? one : many)") }
        }
        if held > 0 { said.append("\(held) \(Whose.inYourLibrary)") }
        return said
    }

    // MARK: the toolbar

    /// "Results for “portishead”" - or Search's own name with nothing typed.
    public static func heading(_ query: String) -> String {
        let typed = JSText.trim(query)
        return typed.isEmpty ? SearchWords.title : "Results for \u{201C}\(typed)\u{201D}"
    }

    /// The toolbar's way to Requests' manual search (Search.dc.html): a search of Soulseek by the words you type there.
    public static let byHand = "Search Soulseek by hand\u{2026}"
}

/// The album you don't have's own words, on both devices (iGet.dc.html, Get.dc.html).
public enum GetPageWords {
    /// "7 pressings" - "1 pressing".
    public static func pressings(_ count: Int) -> String {
        "\(count) \(count == 1 ? "pressing" : "pressings")"
    }

    /// The mono line under the pressing: the chosen pressing's facts and how many pressings there are
    /// ("Official · Cat. no. 539 189-2 · 7 pressings") - its facts alone for one pressing, "" for none.
    public static func factsLine(_ facts: String, pressings count: Int) -> String {
        [facts, count > 1 ? pressings(count) : ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// The tracklist's count beside its heading (iGet's "11 songs · 49 min"): its tracks, and their lengths added up
    /// when every one has a length - "" for no tracks.
    public static func songsLine(_ tracks: [PressingTrack]) -> String {
        guard !tracks.isEmpty else { return "" }
        let count = "\(tracks.count) \(tracks.count == 1 ? "song" : "songs")"
        // not `let seconds = tracks.map { seconds(...) }`: Swift 6.3 (GitHub's macOS runner, Xcode 26.6) reads the
        // name inside the closure as the array being declared, and Core stops compiling there; 6.4 doesn't
        let lengths = tracks.map { Self.seconds($0.length) }
        guard !lengths.contains(nil) else { return count }
        let total = lengths.compactMap { $0 }.reduce(0, +)
        return "\(count) \u{00B7} \(minutes(total))"
    }

    /// "4:38" as seconds - nil for "" or anything that isn't m:ss (h:mm:ss too).
    static func seconds(_ length: String) -> Int? {
        let parts = length.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        var total = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCIIDigitCharacter), let value = Int(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// A total in whole minutes, rounded: "49 min", "1 hr 12 min" - under half a minute, "1 min".
    static func minutes(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let left = minutes % 60
        return left == 0 ? "\(hours) hr" : "\(hours) hr \(left) min"
    }

    /// The Mac's tracklist's columns (Get.dc.html): the number, the title, how it compares with the usual tracklist,
    /// its length.
    public static let number = "#"
    public static let title = "Title"
    public static let againstUsual = "Against the usual tracklist"
    public static let length = "Length"
    /// A track as the usual tracklist has it (Get.dc.html's "the same").
    public static let same = "the same"

    /// What the Mac's third column says of a track: its mark's note ("Only on this pressing") beside its chip - else
    /// "the same" where there is a usual tracklist to compare it with (`compared`), and nothing where there isn't.
    public static func against(_ mark: PressingTrack.Mark?, compared: Bool) -> String {
        if let mark { return mark.note }
        return compared ? same : ""
    }

    /// The Mac's columns' widths: # 46, the title what's left, 210 and 66.
    public static let widths: [MacTable.Width] = [.fixed(46), .flexible, .fixed(210), .fixed(66)]
    /// The Mac's toolbar: the credited artist's page.
    public static let openArtist = "Open artist"
    /// The Mac's status bar (Get.dc.html "11 songs · 49 min · CD · 1997 · Europe"): the tracklist's count, then the
    /// pressing - nothing until the pressings are in.
    public static func status(_ tracks: [PressingTrack], pressing: String) -> [String] {
        [songsLine(tracks), pressing].filter { !$0.isEmpty }
    }
}

/// Sources' own words on the phone and in the Mac's dock (iSources.dc.html, Get.dc.html).
public enum SourcesLook {
    /// The phone's sheet's way out (iSources' "Close", where it said Cancel): the search let go as it closes.
    public static let close = "Close"
    /// "14 found" - the folders Soulseek gave, before the chips.
    public static func found(_ count: Int) -> String {
        "\(count) found"
    }
    /// (R7's review) What the sort line says of them: "14 found" while every one is shown, "3 of 14" while the filters
    /// hide some - the very two numbers the line under the cards gives (Sources.searchedLine: "14 sources, 3 match your
    /// filters").
    public static func found(_ count: Int, shown: Int) -> String {
        shown < count ? "\(shown) of \(count)" : found(count)
    }
    /// The sort's label beside its pop-up.
    public static let sort = "Sort"

    /// (R7's review) A floor of the sample-rate pop-up beside the sort (iSources', Get.dc.html's "Sample rate ▾"): the
    /// least a folder's WORST file's sample rate may be, in Hz - 0 for any - in the web's words for its desktop panel
    /// (getSettings.ts SAMPLE_RATE_FLOORS). A folder whose client reported no sample rate never passes one
    /// (Sources.passes, the web's own rule: many clients report none, and one that might be 44.1 must not pass "96 kHz+").
    public struct SampleRate: Sendable, Equatable, Identifiable {
        public let value: Double
        /// The menu's words: "48 kHz or more".
        public let label: String
        /// The pop-up's own while it is the one chosen: "48 kHz+".
        public let chip: String
        public var id: Double { value }
    }

    /// The pop-up's floors, in the menu's order (`SAMPLE_RATE_FLOORS`).
    public static let sampleRates: [SampleRate] = [
        SampleRate(value: 0, label: "Any sample rate", chip: "Sample rate"),
        SampleRate(value: 44100, label: "44.1 kHz or more", chip: "44.1 kHz+"),
        SampleRate(value: 48000, label: "48 kHz or more", chip: "48 kHz+"),
        SampleRate(value: 88200, label: "88.2 kHz or more", chip: "88.2 kHz+"),
        SampleRate(value: 96000, label: "96 kHz or more", chip: "96 kHz+"),
    ]

    /// The pop-up, as VoiceOver names it.
    public static let sampleRateLabel = "Sample rate"

    /// The floor `rate` is, or any: the pop-up's words and VoiceOver's value for the floor chosen.
    public static func sampleRate(_ rate: Double) -> SampleRate {
        sampleRates.first { (floor: SampleRate) -> Bool in floor.value == rate } ?? sampleRates[0]
    }

    /// The chips as the candidates' filters, the sample-rate floor laid on (getSettings.ts candidateFilters'
    /// `minSampleRate`): what the cards, the best match and a pick all go by.
    public static func filters(_ chips: SourceFilters, minSampleRate: Double) -> CandidateFilters {
        var chosen = GetSettings.candidateFilters(chips)
        chosen.quality.minSampleRate = minSampleRate
        return chosen
    }

    /// How many filters are on - the chips pressed, and the floor one more while it is set (getSettings.ts
    /// pressedCount's): Clear filters shows only when some are.
    public static func pressed(_ chips: SourceFilters, minSampleRate: Double) -> Int {
        GetSettings.pressedCount(chips) + (minSampleRate > 0 ? 1 : 0)
    }

    /// (R7's review) The Mac's foot under the cards (Get.dc.html's panel): what the cards' speeds are. The drawing's
    /// words while every one shown is the peer's own average (slskd's word for them, Sources.speedFact's `advertised`);
    /// a card showing what deadwax measured from that peer before (`measured`) makes them untrue, so then they say both.
    public static func speeds(_ shown: [Candidate]) -> String {
        let measured = shown.contains { (candidate: Candidate) -> Bool in Sources.speedFact(candidate).kind == .measured }
        return measured ? speedsMeasured : speedsOwn
    }
    public static let speedsOwn = "Speeds are each peer's own average."
    public static let speedsMeasured = "Speeds are what you got from a peer before, else its own average."
}

extension SearchWords {
    /// (R7's review) The phone's field's ✕, as VoiceOver names it - iOS's own search field's clear button's words.
    public static let clear = "Clear text"
}

private extension Character {
    var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}
