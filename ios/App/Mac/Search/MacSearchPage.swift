import DeadwaxCore
import SwiftUI

/// Search on the Mac (the redesign, slice R7 - Search.dc.html; notes/ios.md "The redesign, slice R7: Search, Get and
/// Sources (2026-11-25)"): SearchScreen's own list drawn as one grouped table, SearchScreen keeping the model's every
/// ask, stand-down and resume (its `desk`, from MacSearch.root()). The words are the sidebar's field's, as before.
///
/// - The toolbar (.bar): "Results for “portishead”", the groove, the kinds - All, Artists, Albums, Songs (DWSegmented,
///   each `search.choose`, the query narrowed as the phone's chips narrow it; the kind in use always shown) - then
///   **Search Soulseek by hand…** at its end for whoever may get albums: Requests' toolbar, its Artist field with the
///   cursor (AppNavigation.manualSearch). Folded where it doesn't fit: the kinds in one pop-up named for the kind in use.
///   The drawing's Yours first | Only yours is left out: the list has no such choice to make.
/// - The table: the columns' strip (Name, Kind, Artist, Year, In your library, the buttons), then the list as the phone
///   draws it - Top results and each section a heading's row (.row.grp), each row its cover and name, its kind, artist,
///   year, the green chip of where it is in your library ("not in your library" in the third colour for what the
///   library answered for and holds none of), and its buttons: **Play** (a song whose album is in hand), **Open** (a
///   page of yours) or **Get** (the album you don't have). The asking lines, slots, failures and Mores between the rows,
///   as on the phone. The year, then the kind, then the artist give way where the page is narrow (SearchTable.columns):
///   880's page, and 1280's beside the side panel, keep the name, the place and the buttons, and nothing scrolls
///   sideways. Rows at View > Row Size's height (Requests' 34 at Small).
/// - A click selects a row, a double-click (or Return) does its first button's - (R7's review) a double-click on one of
///   its buttons being that button's alone (MacTable.opens, as MacColumnList's rows); ↑ ↓ Home End move through the rows
///   (MacListKeys, a song's albums, opened under it, are clicked); a right-click is the row's ••• (a song's, an
///   album's). VoiceOver reads a row as one element, its buttons its actions, its own action its first button's.
/// - (R7's review) Striped every other row through the table, starting again only under a heading (SearchTable.striped);
///   back to the top as the kind or the words change, and as Search is chosen again (the phone's three).
/// - The status bar: the rows drawn by kind, and how many are in your library.
struct MacSearchPage: View {
    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    /// (The Mac's Row Size) The rows' height and their cover, and the name's least - View > Row Size's.
    @Environment(\.macRowSize) private var rowSize
    @State private var table = MacSearchTable()
    /// The table has the keyboard: ↑ ↓ Home End and Return are its.
    @FocusState private var focused: Bool

    /// The toolbar as drawn, or folded.
    private enum Fit {
        case full, folded
    }

    var body: some View {
        let state = search.state
        MacPage {
            ViewThatFits(in: .horizontal) {
                tools(.full)
                tools(.folded)
            }
        } content: {
            if state.query.isEmpty {
                Text(SearchWords.hint(personal: search.personal))
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MacSearchLook.notePadding)
            } else {
                list
            }
        }
        .macStatus(MacStatusItems.Items(leading: SearchTable.status(drawnRows, search.marks)))
        .environment(table)
        .onChange(of: table.clicks) { (_: Int, _: Int) -> Void in focused = true }
        .onChange(of: order) { (_: [String], now: [String]) -> Void in
            // the selection follows the rows: kept while its row is drawn, else none - never another in its place
            table.selected = MacTable.kept(table.selected, in: now)
        }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ fit: Fit) -> some View {
        let state = search.state
        HStack(spacing: 6) {
            if fit == .full {
                Text(SearchTable.heading(state.query))
                    .font(Typeface.Mac.text(.base).weight(.bold))
                    .foregroundStyle(DWPalette.head)
                    .lineLimit(1)
                    .help(SearchTable.heading(state.query))
            }
            if !state.query.isEmpty {
                if fit == .full {
                    MacGroove()
                    DWSegmented(options: SearchView.allCases, words: SearchWords.chip, chosen: kind,
                                spoken: SearchWords.chipsLabel, large: true)
                } else {
                    DWPopUp(words: SearchWords.chip(state.view)) {
                        Picker(SearchWords.chipsLabel, selection: kind) {
                            ForEach(SearchView.allCases) { (view: SearchView) in
                                Text(SearchWords.chip(view)).tag(view)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .accessibilityLabel(SearchWords.chipsLabel)
                    .accessibilityValue(SearchWords.chip(state.view))
                }
            }
            Spacer(minLength: 0)
            if server.access.can(.request) {
                // Requests' toolbar, its Artist field with the cursor - the way it already opens
                Button(SearchTable.byHand) { navigation.manualSearch() }
                    .buttonStyle(DWButtonStyle())
                    .fixedSize()
            }
        }
    }

    /// The kind chosen: the query narrowed, never the results (`search.choose`, as the phone's chips).
    private var kind: Binding<SearchView> {
        Binding(get: { search.state.view }, set: { (view: SearchView) -> Void in search.choose(view) })
    }

    // MARK: the table

    private var list: some View {
        GeometryReader { (page: GeometryProxy) in
            let total = Double(page.size.width)
            let columns = SearchTable.columns(total, size: rowSize)
            let widths = SearchTable.widths(columns, total, size: rowSize).map { CGFloat($0) }
            let width = SearchTable.tableWidth(columns, total, size: rowSize)
            let state = search.state
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(columns, widths)
                    ScrollViewReader { (proxy: ScrollViewProxy) in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // (R7's review) the list's top, for the kind or the words changing, and Search again
                                Color.clear
                                    .frame(height: 0)
                                    .id(ShelfAnchor.top)
                                // SearchScreen's own list, each row and heading the table's
                                SearchContent()
                                    .environment(\.searchTable, desk)
                            }
                            // the notes 10 in, as a cell's words; the rows and headings span the table (SearchLook.side)
                            .padding(.horizontal, SearchLook.side)
                            .padding(.bottom, MacSearchLook.bottom)
                        }
                        .onChange(of: table.selected) { (_: String?, now: String?) -> Void in
                            // a row the keys moved to, brought into view
                            if let now { proxy.scrollTo(now) }
                        }
                        .onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in
                            if let selected = table.selected { proxy.scrollTo(selected) }
                        }
                        // (R7's review) the phone's three: Search chosen again at its root, the kind, the words
                        .onChange(of: navigation.searchScrollToTop) { (_: Int, _: Int) -> Void in
                            withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
                        }
                        .onChange(of: state.view) { (_: SearchView, _: SearchView) -> Void in jump(proxy) }
                        .onChange(of: state.drawn?.text) { (_: String?, _: String?) -> Void in jump(proxy) }
                    }
                }
                .frame(width: CGFloat(width), height: page.size.height)
                .environment(\.macSearchColumns, MacSearchColumns(columns: columns, widths: widths, striped: striped))
            }
            .scrollDisabled(width <= total)
        }
        // the table takes the keyboard once a row is clicked: ↑ ↓ Home End move the selection, Return does its button's
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .listKeys { (key: ListKey) -> KeyPress.Result in pressed(key) }
    }

    /// (R7's review) To the list's top at once, as the phone's list jumps.
    private func jump(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
    }

    /// The table's drawing of SearchScreen's rows and headings (SearchTableDesk): each row a MacSearchTableRow, each
    /// heading a MacSearchGroupLine, Top results' empty place a row's height.
    private var desk: SearchTableDesk {
        SearchTableDesk(row: { (row: SearchTableRow) -> AnyView in AnyView(MacSearchTableRow(row: row)) },
                        heading: { (title: String) -> AnyView in AnyView(MacSearchGroupLine(title: title)) },
                        rowHeight: rowSize.requestRowHeight, indent: MacSearchLook.indent)
    }

    /// The columns' strip (.cols): its gradient, the frame's rule under it, each heading 10 in with a rule after it.
    private func header(_ columns: [SearchTable.Column], _ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element) { (index: Int, column: SearchTable.Column) in
                Text(SearchTable.title(column))
                    .font(Typeface.Mac.text(.label).weight(.semibold))
                    .foregroundStyle(DWPalette.label)
                    .lineLimit(1)
                    .padding(.horizontal, MacSearchLook.cellSide)
                    .frame(width: widths[index], alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        if index < widths.count - 1 {
                            DWRule(colour: MacPalette.columnsRule, vertical: true)
                        }
                    }
            }
        }
        .frame(height: CGFloat(MacLook.headerHeight))
        .background(MacPalette.columnsFace)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }
        .accessibilityHidden(true)
    }

    /// The rows as drawn, for the status bar's counts: the All view's or the kind's, MusicBrainz's left out offline.
    private var drawnRows: [SearchRow] {
        let state = search.state
        let online = reachability.online
        func shown(_ rows: [SearchRow]) -> [SearchRow] {
            online ? rows : rows.filter { (row: SearchRow) -> Bool in !row.isMusicBrainz }
        }
        if state.query.isEmpty { return [] }
        if state.view.kind != nil {
            guard let kind = search.kindView else { return [] }
            var rows = kind.libraryRows
            if online {
                rows += kind.savedRows
                if case .rows(let found)? = kind.foot { rows += found }
                rows += kind.below
            }
            return SearchList.drawable(rows)
        }
        guard let drawn = state.drawn else { return [] }
        // each row once, though Top results draws it again in its section
        return SearchList.drawable(shown(drawn.top) + (drawn.sections ?? []).flatMap { shown($0.rows) })
    }

    /// The lines ↑ and ↓ move through, in the order drawn.
    private var order: [String] {
        let state = search.state
        if state.query.isEmpty { return [] }
        if state.view.kind != nil {
            return search.kindView.map { SearchTable.order($0, online: reachability.online) } ?? []
        }
        return state.drawn.map { SearchTable.order($0, online: reachability.online) } ?? []
    }

    /// (R7's review) The rows striped, by their lines: every other through the table, starting again under a heading.
    private var striped: Set<String> {
        let state = search.state
        if state.query.isEmpty { return [] }
        if state.view.kind != nil {
            return search.kindView.map { SearchTable.striped($0, online: reachability.online) } ?? []
        }
        return state.drawn.map { SearchTable.striped($0, online: reachability.online) } ?? []
    }

    /// A key on the table (MacListKeys, MacColumnList's own): a move through its rows, or Return doing the row
    /// selected's first button's.
    private func pressed(_ key: ListKey) -> KeyPress.Result {
        let rows = order
        switch MacListKeys.pressed(key, selected: table.selected, in: rows) {
        case .moved(let now):
            guard !rows.isEmpty else { return .ignored }
            table.selected = now
            return .handled
        case .open(let id):
            table.open(id)
            return .handled
        case .ignored:
            return .ignored
        }
    }
}

/// The table's own numbers (Search.dc.html's).
enum MacSearchLook {
    static var cellSide: CGFloat { SearchLook.macSide }   // drawn: Search .row > div padding-left (the list's own side)
    static let coverGap: CGFloat = 8            // drawn: Search name cell gap
    static let buttonGap: CGFloat = 6           // drawn: Search buttons cell gap
    static let notePadding: CGFloat = 20        // own: a page's note, as Requests'
    static let bottom: CGFloat = 16             // own: the table's foot
    /// A song's album, opened under it: its name cell's indent.
    static let indent: CGFloat = 22             // own: a song's albums under it, by a cover's width
}

/// The table's selection, and a Return asked of the row selected: the page's, shared with its rows.
@MainActor @Observable final class MacSearchTable {
    var selected: String?
    /// One more for every click on a row: the table takes the keyboard.
    private(set) var clicks = 0
    /// The row Return asked to do its first button's, one more for each ask.
    private(set) var opened: (id: String, ask: Int)?

    func clicked(_ id: String) {
        selected = id
        clicks += 1
    }

    func open(_ id: String) {
        opened = (id, (opened?.ask ?? 0) + 1)
    }
}

/// The columns shown and their widths, for the rows under the table's header - (R7's review) and the rows striped.
struct MacSearchColumns: Equatable {
    let columns: [SearchTable.Column]
    let widths: [CGFloat]
    /// The lines striped (SearchTable.striped).
    var striped: Set<String> = []

    func width(_ column: SearchTable.Column) -> CGFloat? {
        columns.firstIndex(of: column).map { widths[$0] }
    }
}

extension EnvironmentValues {
    /// (R7) The Search table's columns, for its rows - nil outside the Mac's table (the phone's list).
    @Entry var macSearchColumns: MacSearchColumns? = nil
}

/// A heading's row in the table (.row.grp): its words 10 in, on its own ground, 26 tall.
struct MacSearchGroupLine: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(DWPalette.label)
            .lineLimit(1)
            .padding(.horizontal, MacSearchLook.cellSide)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CGFloat(DWLook.here.groupRowHeight))
            .background(MacPalette.groupRowFace)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
            .padding(.horizontal, -SearchLook.side)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row of SearchScreen's list as the table draws it (SearchTableDesk's row): a MacSearchRow, its name cell the row's
/// picture - a chip's corners on its 1 point edge at the row size's cover, round for an artist - and its title; a
/// MusicBrainz song's disclosure triangle before them (its toggle VoiceOver's action too), a song's album in by a cover's
/// width under it.
struct MacSearchTableRow: View {
    let row: SearchTableRow

    @Environment(\.macRowSize) private var rowSize
    @Environment(\.macSearchColumns) private var layout

    var body: some View {
        // (R7's review) striped by its place in the table, a song's album by its song's
        let striped = layout?.striped.contains(row.stripedAs ?? row.id) ?? false
        MacSearchRow(id: row.id, title: row.title, cells: row.cells, actions: row.actions, spoken: row.spoken,
                     striped: striped, dimmed: row.dimmed, busy: row.busy, disabled: row.disabled, act: row.act) {
            name
        }
        .accessibilityActions {
            // VoiceOver's: the disclosure is the row's own action, as the triangle is the click's
            if let disclosure = row.disclosure {
                Button(SongSearch.disclosureHint(open: disclosure.open)) { disclosure.toggle() }
            }
        }
    }

    private var name: some View {
        let side = CGFloat(rowSize.requestCover)
        return HStack(spacing: MacSearchLook.coverGap) {
            if let disclosure = row.disclosure {
                Button {
                    disclosure.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(Typeface.Mac.text(.small).weight(.semibold))
                        .foregroundStyle(DWPalette.t2)
                        .rotationEffect(.degrees(disclosure.open ? 90 : 0))
                        .frame(minWidth: MacSearchLook.coverGap * 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            picture(side)
                .accessibilityHidden(true)
            Text(row.title)
                .font(Typeface.Mac.text(.base))
                .lineLimit(1)
        }
        .padding(.leading, row.indented ? MacSearchLook.indent : 0)
    }

    @ViewBuilder private func picture(_ side: CGFloat) -> some View {
        switch row.picture {
        case .archive(let group):
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: group), size: ArchiveCoverSize.row)
                .frame(width: side, height: side)
                .clipShape(DWCorners.chipShape)
                .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
        case .cover(let cover, let round):
            if round {
                ArtistPicture(id: cover, side: side, pixels: CoverSize.row)
            } else {
                LibraryCover(id: cover, pixels: CoverSize.row)
                    .frame(width: side, height: side)
                    .clipShape(DWCorners.chipShape)
                    .overlay(DWCorners.chipShape.strokeBorder(MacPalette.coverEdge, lineWidth: 1))
            }
        }
    }
}

/// One row of the table (Search.dc.html's .row): the name cell (the page's - its cover and title), the kind, artist,
/// year and place cells (SearchTable.Cells), and the buttons - every action the row's own (`act`), carried out by
/// SearchScreen's row as its tap is on the phone. As tall as View > Row Size says, striped as the table says, selected
/// in the selection's colours; one element for VoiceOver, its buttons its actions and its own action the first's.
struct MacSearchRow<Name: View>: View {
    let id: String
    let title: String
    let cells: SearchTable.Cells
    let actions: [SearchTable.Action]
    let spoken: String
    var striped = false
    var dimmed = false
    var busy = false
    var disabled = false
    let act: (SearchTable.Action) -> Void
    @ViewBuilder let name: Name

    @Environment(MacSearchTable.self) private var table: MacSearchTable?
    @Environment(\.macSearchColumns) private var layout
    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        let on = table?.selected == id
        let columns = layout?.columns ?? SearchTable.Column.allCases
        // (R7's review) the cells' widths from the row's leading edge, and the buttons' column, whose double-click is
        // the button's (MacTable.opens)
        let widths = (layout?.widths ?? []).map { (width: CGFloat) -> Double in Double(width) }
        let controls = Set(columns.firstIndex(of: .actions).map { [$0] } ?? [])
        // every cell on the one first text baseline, as MacColumnList's and Requests' rows (Courier Prime's year would sit
        // high centred beside Libre Franklin - test_ios_readout_rows.py); the cover centred on its title in its own cell
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(columns, id: \.self) { (column: SearchTable.Column) in
                cell(column, on: on)
                    .padding(.horizontal, MacSearchLook.cellSide)
                    .frame(width: layout?.width(column), alignment: column == .actions ? .trailing : .leading)
                    .frame(maxWidth: layout == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .frame(height: CGFloat(rowSize.requestRowHeight))
        .foregroundStyle(on ? DWPalette.selt : DWPalette.head)
        .background {
            if on {
                Rectangle()
                    .fill(DWPalette.selbg)
                    .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
            } else if striped {
                MacPalette.rowStripe
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
        .opacity(dimmed ? DWPalette.off : 1)
        .contentShape(Rectangle())
        .onTapGesture { clicked(count: 1) }
        // (R7's review) a double-click on a button is the button's: the row does its first button's from its other cells
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { (tap: SpatialTapGesture.Value) -> Void in
            guard MacTable.opens(at: Double(tap.location.x), widths: widths, controls: controls) else { return }
            clicked(count: 2)
        })
        .padding(.horizontal, -SearchLook.side)
        .id(id)
        .onChange(of: table?.opened?.ask) { (_: Int?, _: Int?) -> Void in
            // Return on the table, this row selected: its first button's
            if table?.opened?.id == id { main() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(busy ? SearchWords.loading : "")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        // (R7's review) its default action its first button's, as MacColumnList's rows open on theirs
        .accessibilityAction { main() }
        .accessibilityActions {
            if !disabled {
                ForEach(actions, id: \.self) { (action: SearchTable.Action) in
                    Button(action.spoken(title)) { act(action) }
                }
            }
        }
    }

    private func clicked(count: Int) {
        switch MacTable.clicked(id, count: count) {
        case .select:
            table?.clicked(id)
        case .open:
            table?.clicked(id)
            main()
        }
    }

    /// The row's first button's - its double-click, Return and VoiceOver's own.
    private func main() {
        guard !disabled, let first = actions.first else { return }
        act(first)
    }

    @ViewBuilder private func cell(_ column: SearchTable.Column, on: Bool) -> some View {
        switch column {
        case .name:
            HStack(spacing: MacSearchLook.coverGap) {
                name
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .help(cells.about.isEmpty ? title : "\(title) \u{2014} \(cells.about)")
        case .kind:
            words(cells.kind, on: on)
        case .artist:
            words(cells.artist, on: on)
        case .year:
            Text(cells.year)
                .font(Typeface.Mac.mono(.small))
                .foregroundStyle(on ? DWPalette.selt : DWPalette.t2)
                .lineLimit(1)
        case .place:
            if cells.held {
                DWChip(words: cells.place, tone: .good)
                    .help(cells.place)
            } else if !cells.place.isEmpty {
                Text(cells.place)
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(on ? DWPalette.selt : DWPalette.t3)
                    .lineLimit(1)
                    .help(cells.place)
            }
        case .actions:
            HStack(spacing: MacSearchLook.buttonGap) {
                ForEach(actions, id: \.self) { (action: SearchTable.Action) in
                    button(action)
                }
            }
            .fixedSize()
        }
    }

    private func words(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(on ? DWPalette.selt : DWPalette.t2)
            .lineLimit(1)
            .help(text)
    }

    @ViewBuilder private func button(_ action: SearchTable.Action) -> some View {
        Button {
            act(action)
        } label: {
            if action == .play {
                HStack(spacing: 4) {
                    SharpSymbol(.play)
                        .font(Typeface.symbol(.caption2))
                    Text(action.words)
                }
            } else {
                Text(action.words)
            }
        }
        .buttonStyle(DWButtonStyle(kind: action == .get ? .on : .normal, size: .small))
        .disabled(disabled)
        .accessibilityLabel(action.spoken(title))
    }
}
