import Foundation
import Testing
@testable import DeadwaxCore

/// The Mac's Row Size (notes/ios.md "The Mac's Row Size (2026-11-25)"): View > Row Size's three sizes - each its row and
/// its cover, Requests' its own at Small - Small the default, ⌘+ and ⌘− a size at a time and stopping at the ends; the
/// menu's items, ticks, dimming and keys (⌘= the hidden second key of ⌘+); the album page's box added up at the chosen
/// height; and Large still fitting where the lists' fit tests already measure - the smallest window, and a 1280 window
/// beside the side panel.
@Suite struct MacRowSizeTests {
    // MARK: the sizes

    @Test func threeSizesEachItsRowAndItsCover() {
        #expect(MacRowSize.allCases == [.small, .medium, .large])
        #expect(MacRowSize.allCases.map(\.rowHeight) == [30, 40, 52])
        #expect(MacRowSize.allCases.map(\.cover) == [20, 28, 40])
        // Small is today's row - dw.css's .row, MacLook's own number, never a copy of it
        #expect(MacRowSize.small.rowHeight == MacLook.rowHeight)
        // Requests: Small its drawing's 34 with a 22 cover; Medium and Large every list's own
        #expect(MacRowSize.allCases.map(\.requestRowHeight) == [34, 40, 52])
        #expect(MacRowSize.allCases.map(\.requestCover) == [22, 28, 40])
        #expect(MacRowSize.small.requestRowHeight == RequestColumns.rowHeight
                && MacRowSize.small.requestCover == RequestColumns.cover)
        for size in MacRowSize.allCases {
            // a cover sits inside its row with room above and below, and each size is taller than the last
            #expect(size.cover < size.rowHeight && size.requestCover < size.requestRowHeight, "\(size)")
            #expect(size.rowHeight - size.cover >= 10 && size.requestRowHeight - size.requestCover >= 12, "\(size)")
            if let bigger = size.bigger {
                #expect(bigger.rowHeight > size.rowHeight && bigger.cover > size.cover, "\(size)")
                #expect(bigger.requestRowHeight > size.requestRowHeight && bigger.requestCover > size.requestCover)
            }
        }
        // the header and a heading's row aren't the rows': they never change
        #expect(MacLook.headerHeight == 24 && MacLook.groupRowHeight == 26)
    }

    @Test func theDefaultIsSmallTodaysRows() {
        #expect(MacRowSize.standard == .small)
        #expect(MacRowSize(saved: nil) == .small)
        #expect(MacRowSize(saved: "") == .small && MacRowSize(saved: "huge") == .small && MacRowSize(saved: "Large") == .small)
        for size in MacRowSize.allCases {
            #expect(MacRowSize(saved: size.rawValue) == size, "\(size) kept and read back")
        }
        #expect(MacRowSize.storageKey == "deadwax-mac-row-size")
        // the menu's own state starts at the default too
        #expect(MacMenu.State().rowSize == .small)
    }

    @Test func eachStepIsOneSizeAndStopsAtTheEnds() {
        #expect(MacRowSize.small.bigger == .medium && MacRowSize.medium.bigger == .large && MacRowSize.large.bigger == nil)
        #expect(MacRowSize.large.smaller == .medium && MacRowSize.medium.smaller == .small && MacRowSize.small.smaller == nil)
        // from either end, the steps walk every size once and stop - held to one step past the sizes
        var walked: [MacRowSize] = []
        var at: MacRowSize? = .small
        while let now = at, walked.count <= MacRowSize.allCases.count {
            walked.append(now)
            at = now.bigger
        }
        #expect(walked == [.small, .medium, .large])
        walked = []
        at = .large
        while let now = at, walked.count <= MacRowSize.allCases.count {
            walked.append(now)
            at = now.smaller
        }
        #expect(walked == [.large, .medium, .small])
        // each step undoes the other
        for size in MacRowSize.allCases {
            if let up = size.bigger { #expect(up.smaller == size) }
            if let down = size.smaller { #expect(down.bigger == size) }
        }
    }

    // MARK: the menu

    @Test func rowSizeIsThreeTicksThenTwoSteps() {
        let sections = MacMenu.rowSize(MacMenu.State())
        #expect(sections.map { $0.map(\.command) } == [[.smallRows, .mediumRows, .largeRows], [.biggerRows, .smallerRows]])
        #expect(sections.map { $0.map(\.words) } == [["Small", "Medium", "Large"], ["Make Bigger", "Make Smaller"]])
        #expect(MacMenu.Words.rowSize == "Row Size")
        #expect(MacMenu.Command.rowSizes == [.smallRows, .mediumRows, .largeRows])
        #expect(MacMenu.Command.allCases.filter { $0.rowSize != nil } == MacMenu.Command.rowSizes)
        #expect(MacMenu.Command.rowSizes.compactMap(\.rowSize) == MacRowSize.allCases)
        for size in MacRowSize.allCases {
            let state = MacMenu.State(rowSize: size)
            let items = MacMenu.rowSize(state).flatMap { $0 }
            // the one chosen ticked, alone; the steps never ticked
            #expect(items.filter(\.ticked).map(\.command.rowSize) == [size], "\(size)")
            // a size can always be chosen; a step only while there is one to take
            #expect(items.filter { $0.command.rowSize != nil }.allSatisfy { $0.enabled })
            #expect(MacMenu.item(.biggerRows, state).enabled == (size != .large), "\(size)")
            #expect(MacMenu.item(.smallerRows, state).enabled == (size != .small), "\(size)")
        }
        // never dimmed for a sheet, the sign-in, Now Playing or a field with the cursor: only the rows' height changes
        let covered = MacMenu.State(typing: true, tabs: false, nowPlaying: true, sheet: true, rowSize: .medium)
        for command in MacMenu.Command.rowSizes + [.biggerRows, .smallerRows] {
            #expect(MacMenu.item(command, covered).enabled, "\(command)")
        }
    }

    @Test func eachItemLeavesTheRowsAtItsSize() {
        for size in MacRowSize.allCases {
            #expect(MacMenu.rowSize(after: .smallRows, from: size) == .small)
            #expect(MacMenu.rowSize(after: .mediumRows, from: size) == .medium)
            #expect(MacMenu.rowSize(after: .largeRows, from: size) == .large)
            #expect(MacMenu.rowSize(after: .biggerRows, from: size) == size.bigger)
            #expect(MacMenu.rowSize(after: .smallerRows, from: size) == size.smaller)
        }
        // nothing else changes the rows
        for command in MacMenu.Command.allCases
        where !(MacMenu.Command.rowSizes + [.biggerRows, .smallerRows]).contains(command) {
            for size in MacRowSize.allCases {
                #expect(MacMenu.rowSize(after: command, from: size) == nil, "\(command)")
            }
            #expect(command.rowSize == nil)
        }
    }

    @Test func choosingASizeByNameKeepsThatSize() {
        // (after review) whatever this Mac kept - nothing, garbage, or any size - Small, Medium and Large by name are
        // kept as themselves
        for saved in [nil, "", "huge", "Large", "small", "medium", "large"] as [String?] {
            for (command, size) in zip(MacMenu.Command.rowSizes, MacRowSize.allCases) {
                let chosen = MacMenu.choose(command, saved: saved)
                #expect(chosen?.size == size && chosen?.keep == size.rawValue, "\(command) from \(String(describing: saved))")
                // and what is kept reads back as that size
                #expect(MacRowSize(saved: chosen?.keep) == size)
            }
        }
        // a step from what was kept - nothing or garbage read as Small - and none past an end, nothing kept for it
        #expect(MacMenu.choose(.biggerRows, saved: nil)?.keep == "medium")
        #expect(MacMenu.choose(.biggerRows, saved: "huge")?.keep == "medium")
        #expect(MacMenu.choose(.biggerRows, saved: "medium")?.keep == "large")
        #expect(MacMenu.choose(.biggerRows, saved: "large") == nil)
        #expect(MacMenu.choose(.smallerRows, saved: "large")?.keep == "medium")
        #expect(MacMenu.choose(.smallerRows, saved: "small") == nil && MacMenu.choose(.smallerRows, saved: "huge") == nil)
        // nothing else keeps a size
        for command in MacMenu.Command.allCases
        where !(MacMenu.Command.rowSizes + [.biggerRows, .smallerRows]).contains(command) {
            #expect(MacMenu.choose(command, saved: "medium") == nil, "\(command)")
        }
    }

    @Test func commandPlusAndMinusAsFinderDrawsThemAndCommandEqualsToo() {
        #expect(MacMenu.key(.biggerRows) == MacMenu.Shortcut(.character("+"), .command))
        #expect(MacMenu.key(.smallerRows) == MacMenu.Shortcut(.character("-"), .command))
        #expect(MacMenu.key(.biggerRows)?.said == "\u{2318}+" && MacMenu.key(.smallerRows)?.said == "\u{2318}-")
        // a field with the cursor keeps neither: they type nothing there
        #expect(!MacMenu.yieldsToTyping(.biggerRows) && !MacMenu.yieldsToTyping(.smallerRows))
        #expect(MacMenu.item(.biggerRows, MacMenu.State(typing: true)).shortcut == MacMenu.key(.biggerRows))
        // the three sizes have no key of their own
        for command in MacMenu.Command.rowSizes {
            #expect(MacMenu.key(command) == nil, "\(command)")
        }
        // ⌘= is Make Bigger's second key, the one ⌘+ is typed on without ⇧ - drawn nowhere, and no item's own key
        #expect(MacMenu.alternateKey(.biggerRows) == MacMenu.Shortcut(.character("="), .command))
        let keys = MacMenu.Command.allCases.compactMap(MacMenu.key)
        #expect(!keys.contains(MacMenu.Shortcut(.character("="), .command)))
        for command in MacMenu.Command.allCases where command != .biggerRows {
            #expect(MacMenu.alternateKey(command) == nil, "\(command)")
        }
        // and none of the three is any other item's: ⌘+, ⌘= and ⌘− once each
        for key in ["+", "-", "="] {
            let all = keys + MacMenu.Command.allCases.compactMap(MacMenu.alternateKey)
            #expect(all.filter { $0 == MacMenu.Shortcut(.character(Character(key)), .command) }.count == 1, "\(key)")
        }
    }

    // MARK: what adds rows up

    @Test func theAlbumsBoxAddsItsRowsUpAtTheChosenHeight() {
        for size in MacRowSize.allCases {
            // ten songs on two discs: the header, ten rows at this size, two headings at their own 26, the edge's 2
            #expect(size.boxHeight(rows: 10, headings: 2) == 24 + size.rowHeight * 10 + 26 * 2 + 2, "\(size)")
            #expect(size.boxHeight(rows: 10, headings: 0) == MacLook.headerHeight + size.rowHeight * 10 + 2)
            // at least the header and three rows - or the whole box, an album of one or two songs
            #expect(size.boxLeast(rows: 10, headings: 2) == MacLook.headerHeight + size.rowHeight * 3, "\(size)")
            #expect(size.boxLeast(rows: 1, headings: 0) == size.boxHeight(rows: 1, headings: 0), "\(size)")
            #expect(size.boxLeast(rows: 2, headings: 1) <= size.boxHeight(rows: 2, headings: 1))
            #expect(size.boxHeight(rows: 0, headings: 0) == MacLook.headerHeight + 2)
        }
        #expect(MacRowSize.large.boxHeight(rows: 12, headings: 0) == 24 + 52 * 12 + 2)
        #expect(MacRowSize.small.boxHeight(rows: 12, headings: 0) == 24 + 30 * 12 + 2)
    }

    /// (After review) The album page's content in a window `tall` high: less the title strip, the player bar, the
    /// page's toolbar and the status bar.
    private static func albumPage(_ tall: Double) -> Double {
        tall - MacLook.titleHeight - MacLook.barHeight - MacLook.toolbarHeight - MacLook.statusHeight
    }

    /// The page's own drawn numbers around the box (MacAlbumPage's Drawn: 20 down, 16 at the foot, the box 18 under the
    /// hero) and its hero, the cover's 132 at least.
    private static let edges = 20.0 + 16 + 18
    private static let hero = 132.0

    @Test func aShortWindowNeverPushesPropertiesOffThePage() {
        // the smallest window, 600 tall: 442 of page
        let short = Self.albumPage(MacFrame.smallestHeight)
        #expect(short == 442)
        // as the review measured it: Properties 100 to 112 tall, an album of 12 at Large - its least of three rows and
        // the header (180) was 24 to 36 past the page's foot
        for properties in stride(from: 100.0, through: 112.0, by: 1.0) {
            let around = Self.edges + Self.hero + properties
            let old = MacRowSize.large.boxLeast(rows: 12, headings: 0)
            #expect(old == 180 && around + old - short >= 24 && around + old - short <= 36)
            let room = MacRowSize.boxRoom(page: short, around: around)
            let least = MacRowSize.large.boxLeast(rows: 12, headings: 0, room: room)
            #expect(around + least <= short, "\(properties)")
            #expect(least == short - around, "what's left, and no less")
        }
        // whatever the size, the songs and Properties: never past the page's foot while the rest fits on it
        for size in MacRowSize.allCases {
            for rows in [1, 2, 3, 12, 40] {
                for properties in stride(from: 0.0, through: 250.0, by: 5.0) {
                    let around = Self.edges + Self.hero + properties
                    let least = size.boxLeast(rows: rows, headings: 1, room: MacRowSize.boxRoom(page: short, around: around))
                    #expect(least >= 0 && least <= size.boxLeast(rows: rows, headings: 1))
                    if around <= short { #expect(around + least <= short, "\(size) \(rows) \(properties)") }
                }
            }
        }
        // a window as it first opens (820 tall, a page of 662): the box's least as drawn at every size, Properties up
        // to 200 tall - the page at a usual height is as it was
        let opening = Self.albumPage(MacFrame.openingHeight)
        #expect(opening == 662)
        for size in MacRowSize.allCases {
            for rows in [1, 3, 12, 40] {
                for properties in stride(from: 0.0, through: 200.0, by: 10.0) {
                    let room = MacRowSize.boxRoom(page: opening, around: Self.edges + Self.hero + properties)
                    #expect(size.boxLeast(rows: rows, headings: 2, room: room) == size.boxLeast(rows: rows, headings: 2))
                }
            }
        }
        // not measured yet: the least as drawn; a page shorter than the rest: none at all, never below 0
        #expect(MacRowSize.boxRoom(page: 0, around: 300) == nil)
        #expect(MacRowSize.large.boxLeast(rows: 12, headings: 0, room: nil) == 180)
        #expect(MacRowSize.large.boxLeast(rows: 12, headings: 0, room: -40) == 0)
        #expect(MacRowSize.boxRoom(page: 442, around: 300) == 142)
    }

    // MARK: Large still fits

    /// The pages the lists' fit tests measure: the smallest window's (880, the side panel a drawer over the page), a
    /// 1280 window's beside the side panel as R3 drew it (MacLook's 400), and beside the web's panel (MacFrame's 470).
    private static let smallest = MacFrame.smallestWidth - MacLook.sidebarWidth
    private static let besideTheDock = MacFrame.columnMin - MacLook.sidebarWidth - MacLook.panelWidth - 1
    private static let narrowest = MacFrame.columnMin - MacLook.sidebarWidth - MacFrame.panelWidth - 1

    @Test func playlistsColumnsStillFitAtLarge() {
        #expect((Self.smallest, Self.besideTheDock, Self.narrowest) == (660, 659, 589))
        #expect(MacRowSize.allCases.map(MacAlbumFacts.playlistLeast) == [160, 168, 180])
        let every = MacAlbumFacts.PlaylistColumn.allCases
        for size in MacRowSize.allCases {
            // every column at the smallest window and beside the side panel - Large's 180 beside the rest's 478 is 658
            for page in [Self.smallest, Self.besideTheDock] {
                #expect(MacAlbumFacts.playlistColumns(width: page, size: size) == every, "\(size) at \(page)")
                #expect(page - MacAlbumFacts.fixedWidth(every) >= MacAlbumFacts.playlistLeast(size), "\(size) at \(page)")
            }
            // beside the web's wider panel, Whose and Changed go first, as at Small
            #expect(MacAlbumFacts.playlistColumns(width: Self.narrowest, size: size)
                    == [.playlist, .songs, .length, .onDevice], "\(size)")
            // the name's room in the least - its cell's 10 either side, the cover, 8 to the name - is Small's at every size
            #expect(MacAlbumFacts.playlistLeast(size) - 20 - size.cover - 8 == MacAlbumFacts.playlistLeast - 20 - 20 - 8)
            // and at every page from the narrowest up, Playlist keeps its least
            for width in stride(from: Self.narrowest, through: 1400.0, by: 1.0) {
                let shown = MacAlbumFacts.playlistColumns(width: width, size: size)
                #expect(width - MacAlbumFacts.fixedWidth(shown) >= MacAlbumFacts.playlistLeast(size), "\(size) at \(width)")
            }
        }
        // the default is Small's rule, as R5 left it
        #expect(MacAlbumFacts.playlistColumns(width: 637) == MacAlbumFacts.playlistColumns(width: 637, size: .small))
    }

    @Test func requestsTableStillFitsAtLarge() {
        #expect(MacRowSize.allCases.map(RequestColumns.albumLeast) == [160, 166, 178])
        #expect(RequestColumns.albumLeast(.small) == RequestColumns.albumLeast)
        // a window as it first opens (1280, a page of 1060) scrolls nothing sideways at any size - Large's least is 1020
        let page = MacFrame.openingWidth - MacLook.sidebarWidth
        for size in MacRowSize.allCases {
            #expect(RequestColumns.width(page, size: size) == page, "\(size)")
            let columns = RequestColumns.widths(page, size: size)
            #expect(columns.reduce(0, +) == page && columns[0] >= RequestColumns.albumLeast(size), "\(size)")
            // a narrower page keeps every column at its width and scrolls, as at Small: the smallest window, beside the
            // side panel
            for narrow in [Self.smallest, Self.besideTheDock, Self.narrowest] {
                let least = RequestColumns.width(narrow, size: size)
                #expect(least == 842 + RequestColumns.albumLeast(size) && least > narrow, "\(size) at \(narrow)")
                #expect(RequestColumns.widths(narrow, size: size)[0] == RequestColumns.albumLeast(size))
            }
            // the album's words keep Small's room in the least - its cell's 10 either side, the cover, 8 to the title
            #expect(RequestColumns.albumLeast(size) - 20 - size.requestCover - 8 == RequestColumns.albumLeast - 20 - 22 - 8)
        }
        #expect(RequestColumns.width(0, size: .large) == 1020 && RequestColumns.width(0) == 1002)
    }
}
