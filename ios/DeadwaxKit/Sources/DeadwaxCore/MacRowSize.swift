import Foundation

// The Mac's Row Size (notes/ios.md "The Mac's Row Size (2026-11-25)"): how tall every Mac list's rows are - View > Row
// Size's Small, Medium and Large, ⌘+ and ⌘− a size at a time (MacMenu) - James, 25 Nov: "I need something on mac to
// resize the row height". Only a row's height and its cover change: the words keep their size, centred in the row; a
// list's column headers (MacLook.headerHeight, 24) and its group headings (MacLook.groupRowHeight, 26) never change.
// Kept on this Mac alone (UserDefaults, `storageKey`), as the Mac keeps its sidebar's side and the Library's order; the
// iPhone has no such choice and draws none of it. Pure, so the lists still to come (Songs, Search, the artist window)
// read the very same sizes.

public enum MacRowSize: String, CaseIterable, Sendable, Hashable {
    case small, medium, large

    /// The size a Mac starts at, and the one an unknown saved value reads as: today's rows.
    public static let standard: MacRowSize = .small

    /// Where this Mac keeps the choice.
    public static let storageKey = "deadwax-mac-row-size"

    /// The size kept: Small with none kept, or one this build doesn't know.
    public init(saved: String?) {
        self = saved.flatMap { (raw: String) -> MacRowSize? in MacRowSize(rawValue: raw) } ?? Self.standard
    }

    /// A list's row: Small is dw.css's .row (MacLook.rowHeight, 30), Medium the drawings' 40 (Playlists.dc.html's
    /// rows), Large 52.
    public var rowHeight: Double {
        switch self {
        case .small: return MacLook.rowHeight
        case .medium: return 40
        case .large: return 52
        }
    }

    /// A row's cover - an album's, a playlist's, an artist's round picture: 20 (Albums.dc.html's), 28 (Playlists.dc.html's)
    /// and 40 - each 10 or 12 short of its row, so it sits inside it with room above and below.
    public var cover: Double {
        switch self {
        case .small: return 20
        case .medium: return 28
        case .large: return 40
        }
    }

    /// Requests' row: Small is its drawing's 34 (RequestColumns.rowHeight - a cover and a meter in it, over .row's 30);
    /// Medium and Large are every list's own, 40 and 52.
    public var requestRowHeight: Double {
        self == .small ? RequestColumns.rowHeight : rowHeight
    }

    /// Requests' cover: Small its drawing's 22 (RequestColumns.cover), Medium and Large every list's own, 28 and 40.
    public var requestCover: Double {
        self == .small ? RequestColumns.cover : cover
    }

    /// ⌘+: the next size up - nil at Large, where it stops.
    public var bigger: MacRowSize? {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return nil
        }
    }

    /// ⌘−: the next size down - nil at Small, where it stops.
    public var smaller: MacRowSize? {
        switch self {
        case .small: return nil
        case .medium: return .small
        case .large: return .medium
        }
    }

    /// A list's box as tall as its lines (an album's songs, R5): the header (MacLook.headerHeight), each row at this
    /// size, each heading's row at its own (MacLook.groupRowHeight), and the box's 1 point edge above and below.
    public func boxHeight(rows: Int, headings: Int) -> Double {
        MacLook.headerHeight + rowHeight * Double(max(rows, 0)) + MacLook.groupRowHeight * Double(max(headings, 0)) + 2
    }

    /// The least that box is asked to be: the header and three rows at this size - or the whole box, when that is
    /// shorter still (an album of one or two songs).
    public func boxLeast(rows: Int, headings: Int) -> Double {
        min(MacLook.headerHeight + rowHeight * 3, boxHeight(rows: rows, headings: headings))
    }

    /// (After review) The least the box is asked to be on a page with `room` points left for it - the page's height
    /// less everything else on it (its edges, the hero, the gap above the box, Properties): the least above while it
    /// fits, else the room left, never below 0 - so a short window (600 tall at Large: three 52 rows and the header
    /// are 180) never pushes Properties under the status bar and the player bar. With nothing measured yet (nil), the
    /// least above. At a window's usual heights the room is more than the least, and the page is as drawn.
    public func boxLeast(rows: Int, headings: Int, room: Double?) -> Double {
        let least = boxLeast(rows: rows, headings: headings)
        guard let room else { return least }
        return min(least, max(room, 0))
    }

    /// The room the album page leaves its songs box: a page `page` tall less `around` - the page's own edges and the
    /// gap above the box (the drawing's numbers) and the hero and Properties as they are drawn now. nil until the
    /// page is measured (0 tall).
    public static func boxRoom(page: Double, around: Double) -> Double? {
        page > 0 ? page - around : nil
    }

    /// How much wider a row's cover is than Small's: what a column holding one keeps on top of its least, so its words
    /// keep the room they had (Playlists' Playlist, Requests' Album).
    public var coverGrowth: Double { cover - Self.small.cover }

    /// Requests' own: its cover's growth over its drawing's 22.
    public var requestCoverGrowth: Double { requestCover - Self.small.requestCover }
}
