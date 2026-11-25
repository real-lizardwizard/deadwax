import Foundation

// The Mac redesign's column lists (the build plan's section 2, "Column list"; notes/ios.md "The Mac redesign, slice R1:
// the frame and the shared pieces"): Albums, Artists, an album's tracks, Requests, the folder list - a strip of column
// headers over rows 30 tall, every other row faintly striped, one row selected in the web's purple edge. SwiftUI's
// Table can style none of that, so the Mac draws its own list (MacColumnList, R2) and its rules are here, tested on
// Linux: the columns' widths, the stripes, which row is selected as the keys and the pointer move, and what opens.
//
// One row is selected at a time (a single selection, as the drawings have it), by its id. A list is drawn as lines - a
// group's heading or a row - and only rows are ever selected, striped or opened.

public enum MacTable {
    /// A column's width: a fixed number of points, or a share of what the fixed ones leave (the drawings' `grow`).
    public enum Width: Equatable, Sendable {
        case fixed(Double)
        case flexible
    }

    /// Each column's width in a list `total` points wide: a fixed column as it is; the flexible ones share what is left
    /// equally - none of them narrower than 0, so a list narrower than its fixed columns overflows rather than draws a
    /// negative width.
    public static func widths(_ columns: [Width], total: Double) -> [Double] {
        let fixed = columns.reduce(0.0) { (sum: Double, column: Width) -> Double in
            if case .fixed(let points) = column { return sum + points }
            return sum
        }
        let shares = columns.filter { $0 == .flexible }.count
        let each = shares > 0 ? max(0, (total - fixed) / Double(shares)) : 0
        return columns.map { (column: Width) -> Double in
            if case .fixed(let points) = column { return points }
            return each
        }
    }

    /// A line of a list as drawn: a group's heading (Requests' Downloading, Search's Albums...) or a row, by its id.
    public enum Line<ID: Hashable & Sendable>: Hashable, Sendable {
        case group(String)
        case row(ID)

        /// The row's id; none for a heading.
        public var row: ID? {
            if case .row(let id) = self { return id }
            return nil
        }
    }

    /// Whether each line is striped (.row.alt): every other row, the first under each heading plain - the stripes start
    /// again under every heading, so a group never begins on a stripe because of the group above it. A heading is never
    /// striped.
    public static func stripes<ID>(_ lines: [Line<ID>]) -> [Bool] {
        var run = 0
        return lines.map { (line: Line<ID>) -> Bool in
            switch line {
            case .group:
                run = 0
                return false
            case .row:
                defer { run += 1 }
                return run % 2 == 1
            }
        }
    }

    /// The rows of a list, in order, its headings left out: what the keys move through.
    public static func rows<ID>(_ lines: [Line<ID>]) -> [ID] {
        lines.compactMap(\.row)
    }

    /// A key that moves the selection.
    public enum Key: String, Sendable, CaseIterable {
        case up, down, home, end
    }

    /// The row selected after `key`, from `selected` in `rows`: ↓ the next row and ↑ the one before, staying put at
    /// either end; Home the first and End the last. With nothing selected - or a selection no longer listed - ↓ and Home
    /// take the first row, ↑ and End the last, as a Mac's lists do. Nothing to select in an empty list.
    public static func moved<ID: Hashable>(_ selected: ID?, _ key: Key, in rows: [ID]) -> ID? {
        guard let first = rows.first, let last = rows.last else { return nil }
        switch key {
        case .home: return first
        case .end: return last
        case .up, .down:
            guard let selected, let at = rows.firstIndex(of: selected) else { return key == .down ? first : last }
            let next = key == .down ? min(at + 1, rows.count - 1) : max(at - 1, 0)
            return rows[next]
        }
    }

    /// The selection once the rows change (a new answer, a filter, a row gone): the same row while it is still listed,
    /// else none - never another row in its place, which Return or Play would then act on unseen.
    public static func kept<ID: Hashable>(_ selected: ID?, in rows: [ID]) -> ID? {
        guard let selected, rows.contains(selected) else { return nil }
        return selected
    }

    /// What a click does.
    public enum Click<ID: Hashable & Sendable>: Hashable, Sendable {
        /// A click selects the row.
        case select(ID)
        /// A double-click opens it (and it is selected).
        case open(ID)
    }

    /// A click of `count` on a row: one selects it, two (or more) open it.
    public static func clicked<ID: Hashable & Sendable>(_ id: ID, count: Int) -> Click<ID> {
        count >= 2 ? .open(id) : .select(id)
    }

    /// Return: the selected row opens, while it is still listed; nothing selected, nothing opens.
    public static func returned<ID: Hashable>(_ selected: ID?, in rows: [ID]) -> ID? {
        kept(selected, in: rows)
    }
}
