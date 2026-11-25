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
struct MacColumnList<Row: Identifiable, Cell: View, Menu: ViewModifier>: View where Row.ID == String {
    let columns: [MacListColumn]
    let rows: [Row]
    var lines: [MacTable.Line<String>]? = nil
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
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            click(MacTable.clicked(row.id, count: 2), row: row)
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { open(row) }
    }

    // MARK: doing

    /// A click: the row selected and the keyboard the list's - and, a double-click, the row opened.
    private func click(_ click: MacTable.Click<String>, row: Row) {
        focused = true
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
        let move: MacTable.Key
        switch key {
        case .up: move = .up
        case .down: move = .down
        case .home: move = .home
        case .end: move = .end
        case .open:
            guard let id = MacTable.returned(selected, in: ids),
                  let row = rows.first(where: { (row: Row) -> Bool in row.id == id }) else { return .ignored }
            open(row)
            return .handled
        }
        selected = MacTable.moved(selected, move, in: ids)
        return .handled
    }
}
