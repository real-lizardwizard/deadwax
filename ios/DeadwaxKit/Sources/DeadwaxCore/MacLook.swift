import Foundation

// The Mac redesign's sizes (notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"; the build plan's
// section 2): the window as James approved it on the design canvas, "the web app's look, a touch more vintage" -
// dw.css, kept beside the app at ios/design/dw.css and held to these number by number by tests/test_ios_mac_look.py.
// In points, dw.css's CSS px.
//
// These are the Mac's alone: the iPhone draws none of them. MacFrame's web-held sizes (the sidebar 232, the panel 470,
// the bar 72) and their vectors stay as they are, the web's own; the Mac draws these instead, slice by slice - the
// sidebar from R1, the panel from R3's dock, the bar from R4's. MacFrame's breakpoint (1280) and smallest window
// (880 x 600) stay in use.

public enum MacLook {
    // MARK: the frame

    /// .side: the sidebar's width.
    public static let sidebarWidth: Double = 220
    /// The side panel's width, as the drawings draw it (the panel's inline 400px - not one of dw.css's rules).
    public static let panelWidth: Double = 400
    /// .player: the player bar's height.
    public static let barHeight: Double = 66
    /// .titlebar: the title strip's height, under the window's traffic lights.
    public static let titleHeight: Double = 28
    /// .bar: a page's toolbar.
    public static let toolbarHeight: Double = 40
    /// .status: the status bar under the page.
    public static let statusHeight: Double = 24
    /// Edit an album's folder list (the drawing's inline 398px, beside the editor).
    public static let folderListWidth: Double = 398

    // MARK: lists

    /// .cols: a list's column headers.
    public static let headerHeight: Double = 24
    /// .row: a list's row.
    public static let rowHeight: Double = 30
    /// .row.grp: a group's heading row inside a list.
    public static let groupRowHeight: Double = 26

    // MARK: the sidebar

    /// .nav: a sidebar row.
    public static let navRowHeight: Double = 26
    /// .find: a search field in its well - the sidebar's, a toolbar's Find.
    public static let findHeight: Double = 28

    // MARK: controls

    /// .btn and .btn.sm: a button, and a small one.
    public static let buttonHeight: Double = 26
    public static let smallButtonHeight: Double = 22
    /// .in: a text field.
    public static let fieldHeight: Double = 24
    /// .field > label: a field's label, right-aligned to its field.
    public static let labelWidth: Double = 84
    /// .seg button and .seg.lg button: a segment, and a large one (a toolbar's Grid | List).
    public static let segmentHeight: Double = 20
    public static let largeSegmentHeight: Double = 24
    /// .chip: a chip.
    public static let chipHeight: Double = 19
    /// .count: a count's badge (a sidebar row's).
    public static let countHeight: Double = 17
    /// .groove: the groove between a toolbar's groups.
    public static let grooveHeight: Double = 20

    // MARK: folder tabs

    /// .tabs: the strip folder tabs sit on.
    public static let tabStripHeight: Double = 35
    /// .tab and .tab.on: a tab, and the one chosen (taller, its foot over the strip's edge).
    public static let tabHeight: Double = 26
    public static let chosenTabHeight: Double = 29

    // MARK: the player's keys

    /// .key and .key.big: a transport key, and Play's.
    public static let keySize: Double = 34
    public static let bigKeySize: Double = 46
    /// .tog: Shuffle's and Repeat's toggles.
    public static let toggleSize: Double = 30
}
