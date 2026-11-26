import DeadwaxCore
import SwiftUI

/// A column of a list (MacColumnList): its header's words and its width - a fixed number of points, or a share of what
/// the fixed ones leave (Core's MacTable.Width, the drawings' `grow`).
struct MacListColumn: Equatable {
    let title: String
    let width: MacTable.Width
}

/// A column list (dw.css's .cols and .row - the redesign, slice R2, notes/ios.md "The redesign, slice R2: Albums and
/// Artists, and the Library's top"): the Albums and Artists pages' rows, as the design's Albums.dc.html and
/// Artists.dc.html draw them.
///
/// - The header strip (.cols): 24 tall, its gradient, the label colour at 11.5 semibold, each column's cell 10 in from
///   its edges with a rule between, the frame's rule under it.
/// - Each row (.row) on the row line's rule, its cells as the header's, every other row striped (.row.alt, Core's
///   MacTable.stripes); the selected one (.row.on) in the selection's fill, its purple edge inset and its words. (The
///   Mac's Row Size) As tall as View > Row Size says - 30, 40 or 52 (MacRowSize.rowHeight, the environment's
///   `macRowSize`) - its words centred in it at their own size; the header (24) and a heading's row (26) never change.
/// - Widths from Core's MacTable.widths over the list's own width. Catalyst can't resize or reorder a column (the build
///   plan's section 4).
/// - A click selects a row; a double-click opens it (MacTable.clicked). With the list focused (a click gives it the
///   keyboard), ↑ and ↓ move the selection, Home and End go to either end (MacTable.moved), and Return opens the row
///   selected (MacTable.returned) - Platform's `listKeys`, the one place the list hears a key. Space is never the
///   list's. The selection follows the rows: kept while its row is listed, else none (MacTable.kept), never another row
///   in its place; brought into view as it moves. (Its review) ⌘↑ and ⌘↓ go to the ends; another modified key isn't
///   the list's.
/// - (Its review) What the page hangs on each row, `menu` - Albums' right-click, the album page's •••'s items
///   (AlbumRightClick, as the tiles' and the rows' before R2 had it): applied to the whole row, its whole height and
///   every column, so a right-click anywhere on it is the row's.
/// - VoiceOver reads a row as one element, its cells in order, selected when it is; its action opens it.
/// - (R5's review) `lines`, for a list with headings - an album's discs: each a heading's row (.row.grp, 26 tall, the
///   label's words 10 in, a header for VoiceOver) or a row by its id, in order; the stripes start again under each
///   heading (MacTable.stripes), and only the rows are selected, moved through or opened. nil: the rows alone.
/// - (R6's review - notes/ios.md "The redesign, slice R6: an artist") Three things a page may ask, each nothing unless
///   it does, so every other list draws and answers as before:
///   - `controls`, the columns whose cells hold buttons (an artist's Play, Open and Get; an album's •••): a double-click
///     there is the button's own, never the row's (MacTable.opens) - the row opens from its other columns.
///   - `voice`, a row read as one element of its own words, its buttons its actions (`.ignore`, the words, the
///     actions), for a row whose buttons `.combine` would read into its label (an artist's discography).
///   - `flow`, the list as a section of a page that scrolls itself (an artist's, three lists long): no box and no scroll
///     view of its own - its header and rows lines of the page's lazy stack, made only as they come into view (and only
///     then their covers asked). The page lays the columns over its own width and hears the keys (MacListFlow).
struct MacColumnList<Row: Identifiable, Cell: View, Menu: ViewModifier>: View where Row.ID == String {
    let columns: [MacListColumn]
    let rows: [Row]
    var lines: [MacTable.Line<String>]? = nil
    /// (R6's review) The columns whose cells hold buttons: a double-click there is the button's. None: the whole row.
    var controls: Set<Int> = []
    /// (R6's review) A row read as one element of its own words and actions. nil: its cells in order (`.combine`).
    var voice: ((Row) -> MacRowVoice)? = nil
    /// (R6's review) The list as a section of the page's own lazy stack. nil: the list's own box, scrolling itself.
    var flow: MacListFlow? = nil
    @Binding var selected: String?
    /// A row opened - Return, a double-click, VoiceOver's action.
    let open: (Row) -> Void
    /// (Its review) What the page hangs on a row: its right-click (AlbumRightClick), or nothing (EmptyModifier).
    let menu: (Row) -> Menu
    /// Each row's cell in the column at that index.
    @ViewBuilder let cell: (Row, Int) -> Cell

    @FocusState private var focused: Bool
    /// (The Mac's Row Size) How tall each row is: View > Row Size's, as this Mac keeps it.
    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        if let flow {
            flowing(flow)
        } else {
            box
        }
    }

    /// The list in a box of its own - every page's but a page that scrolls itself: the body before R6's review, as it was.
    @ViewBuilder private var box: some View {
        let drawn = lines ?? rows.map { (row: Row) -> MacTable.Line<String> in .row(row.id) }
        // the keys move through the rows alone, in the order drawn
        let ids = lines.map { (given: [MacTable.Line<String>]) -> [String] in MacTable.rows(given) }
            ?? rows.map { (row: Row) -> String in row.id }
        let stripes = MacTable.stripes(drawn)
        let byID = Dictionary(rows.map { (row: Row) -> (String, Row) in (row.id, row) },
                              uniquingKeysWith: { (first: Row, _: Row) -> Row in first })
        GeometryReader { (room: GeometryProxy) in
            let widths = MacTable.widths(columns.map { (column: MacListColumn) -> MacTable.Width in column.width },
                                         total: Double(room.size.width))
            VStack(spacing: 0) {
                header(widths)
                ScrollViewReader { (proxy: ScrollViewProxy) in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(drawn.enumerated()), id: \.element) { (at: Int, item: MacTable.Line<String>) in
                                switch item {
                                case .group(let title):
                                    heading(title)
                                case .row(let id):
                                    if let row = byID[id] {
                                        line(row, striped: at < stripes.count && stripes[at], widths: widths)
                                            .modifier(menu(row))
                                            .id(row.id)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: selected) { (_: String?, now: String?) -> Void in
                        guard let now else { return }
                        proxy.scrollTo(now)
                    }
                    // (the Mac's Row Size, after review) rows taller or shorter move the one selected: brought back
                    // into view
                    .onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in
                        guard let selected else { return }
                        proxy.scrollTo(selected)
                    }
                }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .listKeys { (key: ListKey) -> KeyPress.Result in pressed(key, ids: ids) }
        .onChange(of: ids) { (_: [String], now: [String]) -> Void in
            let kept = MacTable.kept(selected, in: now)
            if kept != selected { selected = kept }
        }
    }

    // MARK: a section of a page (R6's review)

    /// The header and the lines, each a line of the page's own lazy stack - no box, no scroll view, no GeometryReader:
    /// the columns over the page's width (`flow.width`), each line found in the page's scroll view by its key - the
    /// ForEach's own identity, which a lazy stack scrolls to before the row is made. The page hears the keys, keeps the
    /// selection among the rows and brings it into view (MacListFlow); a click here tells it (`flow.clicked`).
    @ViewBuilder private func flowing(_ flow: MacListFlow) -> some View {
        let drawn = lines ?? rows.map { (row: Row) -> MacTable.Line<String> in .row(row.id) }
        let stripes = MacTable.stripes(drawn)
        let byID = Dictionary(rows.map { (row: Row) -> (String, Row) in (row.id, row) },
                              uniquingKeysWith: { (first: Row, _: Row) -> Row in first })
        let widths = MacTable.widths(columns.map { (column: MacListColumn) -> MacTable.Width in column.width },
                                     total: flow.width)
        let keyed = drawn.enumerated().map { (at: Int, item: MacTable.Line<String>) -> MacListFlow.Keyed in
            MacListFlow.Keyed(id: flow.key(item, at: at), at: at, item: item)
        }
        header(widths)
        ForEach(keyed) { (entry: MacListFlow.Keyed) in
            switch entry.item {
            case .group(let title):
                heading(title)
            case .row(let id):
                if let row = byID[id] {
                    line(row, striped: entry.at < stripes.count && stripes[entry.at], widths: widths)
                        .modifier(menu(row))
                }
            }
        }
    }

    // MARK: the header

    private func header(_ widths: [Double]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { (index: Int) in
                Text(columns[index].title)
                    .lineLimit(1)
                    // .cols > div: padding 0 10px
                    .padding(.horizontal, 10)
                    .frame(width: CGFloat(index < widths.count ? widths[index] : 0), alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        // .cols > div's rule, none after the last (:last-child)
                        if index < columns.count - 1 {
                            DWRule(colour: MacPalette.columnsRule, vertical: true)
                        }
                    }
            }
        }
        .font(Typeface.Mac.text(.label).weight(.semibold))
        .foregroundStyle(DWPalette.label)
        .frame(height: CGFloat(MacLook.headerHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacPalette.columnsFace)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: a heading (R5's review)

    /// A heading's row (.row.grp): its words 10 in, the label's colour at 11.5 semibold, on its own ground and the row
    /// line's rule - never striped, selected or opened; a header for VoiceOver.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(DWPalette.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: CGFloat(MacLook.groupRowHeight))
            .background(MacPalette.groupRowFace)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: a row

    private func line(_ row: Row, striped: Bool, widths: [Double]) -> some View {
        let on = row.id == selected
        // (25 Nov) the cells on one first text baseline: a readout's (Courier Prime's) shorter line would sit it higher
        // in a centred row
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(columns.indices, id: \.self) { (index: Int) in
                cell(row, index)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // .row > div: padding 0 10px
                    .padding(.horizontal, 10)
                    .frame(width: CGFloat(index < widths.count ? widths[index] : 0), alignment: .leading)
            }
        }
        .font(Typeface.Mac.text(.base))
        .foregroundStyle(on ? DWPalette.selt : DWPalette.head)
        .frame(height: CGFloat(rowSize.rowHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if on {
                // .row.on: the selection's fill, its edge inset (box-shadow: inset 0 0 0 1px var(--selbd))
                Rectangle()
                    .fill(DWPalette.selbg)
                    .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
            } else if striped {
                MacPalette.rowStripe
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
        .contentShape(Rectangle())
        .onTapGesture {
            click(MacTable.clicked(row.id, count: 1), row: row)
        }
        // (R6's review) a double-click on a cell's button is the button's: the row opens from its other columns
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { (tap: SpatialTapGesture.Value) -> Void in
            guard MacTable.opens(at: Double(tap.location.x), widths: widths, controls: controls) else { return }
            click(MacTable.clicked(row.id, count: 2), row: row)
        })
        .modifier(MacRowVoicing(voice: voice?(row), selected: on) { open(row) })
    }

    // MARK: doing

    /// A click: the row selected and the keyboard the list's - and, a double-click, the row opened.
    private func click(_ click: MacTable.Click<String>, row: Row) {
        focused = true
        // (R6's review) a section of a page: the page's keyboard, for this list
        flow?.clicked()
        switch click {
        case .select(let id):
            selected = id
        case .open(let id):
            selected = id
            open(row)
        }
    }

    /// A key on the focused list (Platform's ListKey, as Requests' table takes it): ↑ ↓ Home End move the selection,
    /// Return opens it.
    private func pressed(_ key: ListKey, ids: [String]) -> KeyPress.Result {
        switch MacListKeys.pressed(key, selected: selected, in: ids) {
        case .moved(let now):
            selected = now
            return .handled
        case .open(let id):
            guard let row = rows.first(where: { (row: Row) -> Bool in row.id == id }) else { return .ignored }
            open(row)
            return .handled
        case .ignored:
            return .ignored
        }
    }
}

/// (R6's review) A list's keys, wherever they are heard - MacColumnList's own, and a page's that flows its lists into its
/// own scroll view (an artist's): ↑ ↓ Home End move the selection through the rows (MacTable.moved), Return opens the
/// one selected while it is listed (MacTable.returned).
enum MacListKeys {
    enum Answer: Equatable {
        case moved(String?)
        case open(String)
        case ignored
    }

    static func pressed(_ key: ListKey, selected: String?, in ids: [String]) -> Answer {
        let move: MacTable.Key
        switch key {
        case .up: move = .up
        case .down: move = .down
        case .home: move = .home
        case .end: move = .end
        case .open:
            guard let id = MacTable.returned(selected, in: ids) else { return .ignored }
            return .open(id)
        }
        return .moved(MacTable.moved(selected, move, in: ids))
    }
}

/// (R6's review) A list drawn as a section of a page that scrolls itself (MacColumnList's `flow`): the width its columns
/// are laid over - the page's own - its name among the page's lists, by which its lines are found in the page's scroll
/// view (`key`), and what a click on a row tells the page: that this list has the keyboard. The page hears ↑ ↓ Home End
/// and Return for that list (MacListKeys), keeps its selection among its rows (MacTable.kept) and brings it into view
/// with its own ScrollViewReader - the row's key the ForEach's identity, so a row not yet made is scrolled to as well.
struct MacListFlow {
    let width: Double
    let name: String
    let clicked: () -> Void

    /// A row's key in the page's scroll view.
    func key(_ id: String) -> String { Self.key(name, id) }

    static func key(_ name: String, _ id: String) -> String { "\(name):\(id)" }

    /// A line's: a row's by its id, a heading's by its place.
    func key(_ line: MacTable.Line<String>, at: Int) -> String {
        switch line {
        case .row(let id): return key(id)
        case .group: return "\(name)#\(at)"
        }
    }

    /// A line as the section draws it, by its key.
    struct Keyed: Identifiable {
        let id: String
        let at: Int
        let item: MacTable.Line<String>
    }
}

/// (R6's review) A row read as one element (MacColumnList's `voice`): its words, and its buttons as its actions.
struct MacRowVoice {
    let label: String
    let actions: [MacRowAction]
}

/// One of a row's actions to VoiceOver: the button's words, and what it does - in the tap, as the button's own.
struct MacRowAction: Identifiable {
    let words: String
    let run: () -> Void

    var id: String { words }
}

/// How VoiceOver reads a row: its cells in order (`.combine`), as every list did before - or, with `voice`, as one
/// element of its own words, its buttons its actions. A button either way, selected when it is; its action opens it.
private struct MacRowVoicing: ViewModifier {
    let voice: MacRowVoice?
    let selected: Bool
    let open: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if let voice {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voice.label)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { open() }
                .accessibilityActions {
                    ForEach(voice.actions) { (action: MacRowAction) in
                        Button(action.words, action: action.run)
                    }
                }
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { open() }
        }
    }
}
