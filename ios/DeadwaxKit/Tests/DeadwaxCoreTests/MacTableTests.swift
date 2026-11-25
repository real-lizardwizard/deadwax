import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac redesign's column lists (notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"): the
/// columns' widths, the stripes starting again under every heading, one row selected as the keys and the pointer move,
/// a vanished row's selection let go, and what Return and a double-click open. MacLook's sizes are held to dw.css by
/// tests/test_ios_mac_look.py; here, what they must hold together.
@Suite struct MacTableTests {
    @Test func theFixedColumnsKeepTheirWidthAndTheFlexibleShareTheRest() {
        // Albums as drawn: Album (the rest), Artist 150, Year 54, Songs 58 - in a list 700 wide
        let albums: [MacTable.Width] = [.flexible, .fixed(150), .fixed(54), .fixed(58)]
        #expect(MacTable.widths(albums, total: 700) == [438, 150, 54, 58])
        // two flexible columns share it equally
        #expect(MacTable.widths([.flexible, .fixed(100), .flexible], total: 500) == [200, 100, 200])
        // narrower than the fixed columns: the flexible one is 0, never negative, and the fixed ones keep theirs
        #expect(MacTable.widths(albums, total: 200) == [0, 150, 54, 58])
        // none flexible: each as it is, whatever the total
        #expect(MacTable.widths([.fixed(36), .fixed(58)], total: 900) == [36, 58])
        #expect(MacTable.widths([], total: 900) == [])
    }

    @Test func theStripesStartAgainUnderEveryHeading() {
        typealias Line = MacTable.Line<String>
        // a list with no headings: every other row, the first plain (the drawings' `i % 2 ? 'alt' : ''`)
        let plain: [Line] = ["a", "b", "c", "d", "e"].map { Line.row($0) }
        #expect(MacTable.stripes(plain) == [false, true, false, true, false])
        // under a heading the run starts again: a group of three, then a group whose first row is plain - never
        // striped because the group above ended on a plain row
        let grouped: [Line] = [.group("Downloading"), .row("a"), .row("b"), .row("c"),
                               .group("Waiting"), .row("d"), .row("e"),
                               .group("Done"), .row("f")]
        #expect(MacTable.stripes(grouped) == [false, false, true, false,
                                              false, false, true,
                                              false, false])
        // a heading is never striped, and two headings together start nothing
        #expect(MacTable.stripes([Line.group("A"), .group("B"), .row("x"), .row("y")]) == [false, false, false, true])
        #expect(MacTable.rows(grouped) == ["a", "b", "c", "d", "e", "f"])
    }

    @Test func theKeysMoveOneSelection() {
        let rows = ["a", "b", "c"]
        #expect(MacTable.moved("a", .down, in: rows) == "b")
        #expect(MacTable.moved("b", .up, in: rows) == "a")
        // at either end it stays
        #expect(MacTable.moved("c", .down, in: rows) == "c")
        #expect(MacTable.moved("a", .up, in: rows) == "a")
        #expect(MacTable.moved("b", .home, in: rows) == "a")
        #expect(MacTable.moved("b", .end, in: rows) == "c")
        // nothing selected - or a row no longer listed: down and Home the first, up and End the last
        for selected in [nil, "gone"] as [String?] {
            #expect(MacTable.moved(selected, .down, in: rows) == "a")
            #expect(MacTable.moved(selected, .home, in: rows) == "a")
            #expect(MacTable.moved(selected, .up, in: rows) == "c")
            #expect(MacTable.moved(selected, .end, in: rows) == "c")
        }
        // nothing to select
        for key in MacTable.Key.allCases {
            #expect(MacTable.moved("a", key, in: [String]()) == nil)
        }
    }

    @Test func aVanishedRowsSelectionBecomesNone() {
        #expect(MacTable.kept("b", in: ["a", "b", "c"]) == "b")
        // gone from the rows: none - never the row that took its place
        #expect(MacTable.kept("b", in: ["a", "c"]) == nil)
        #expect(MacTable.kept("b", in: []) == nil)
        #expect(MacTable.kept(nil as String?, in: ["a"]) == nil)
    }

    @Test func aClickSelectsAndADoubleClickOrReturnOpens() {
        #expect(MacTable.clicked("a", count: 1) == .select("a"))
        #expect(MacTable.clicked("a", count: 2) == .open("a"))
        #expect(MacTable.clicked("a", count: 3) == .open("a"))
        // Return opens the selected row while it is listed, and nothing otherwise
        #expect(MacTable.returned("b", in: ["a", "b"]) == "b")
        #expect(MacTable.returned("b", in: ["a"]) == nil)
        #expect(MacTable.returned(nil as String?, in: ["a"]) == nil)
    }
}

/// The redesign's sizes (MacLook), each dw.css's own - held there number by number by tests/test_ios_mac_look.py; here,
/// that they fit together in the Mac's window.
@Suite struct MacLookTests {
    @Test func theLooksSizesHoldTogether() {
        // a button sits in the toolbar with room above and below; a small one is smaller
        #expect(MacLook.buttonHeight < MacLook.toolbarHeight && MacLook.smallButtonHeight < MacLook.buttonHeight)
        // a field fits a field's row; a chip fits a row; the chosen tab stands over the strip's edge, inside the strip
        #expect(MacLook.fieldHeight <= MacLook.rowHeight && MacLook.chipHeight < MacLook.rowHeight)
        #expect(MacLook.tabHeight < MacLook.chosenTabHeight && MacLook.chosenTabHeight < MacLook.tabStripHeight)
        // Play's key is the bigger, and fits the bar with the ring round it
        #expect(MacLook.keySize < MacLook.bigKeySize && MacLook.bigKeySize + 8 <= MacLook.barHeight)
        // the smallest window still holds the sidebar, Edit an album's folder list and some of its editor
        #expect(MacLook.sidebarWidth + MacLook.folderListWidth < MacFrame.smallestWidth)
        // and the frame's chrome - the title strip, a toolbar, a header, the status bar and the bar - leaves rows to see
        let chrome = MacLook.titleHeight + MacLook.toolbarHeight + MacLook.headerHeight + MacLook.statusHeight
            + MacLook.barHeight
        #expect(MacFrame.smallestHeight - chrome >= 10 * MacLook.rowHeight)
        // a panel's column at the breakpoint still leaves a page wider than the sidebar beside it
        #expect(MacFrame.columnMin - MacLook.sidebarWidth - MacLook.panelWidth > MacLook.sidebarWidth)
    }
}
