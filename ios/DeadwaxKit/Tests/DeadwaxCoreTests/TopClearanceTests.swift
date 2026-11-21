import Testing
@testable import DeadwaxCore

// The Library's top, measured (15 Nov, TopClearance): the row comes down by what of its window's top safe area its own
// top doesn't clear. After Now Playing (18 Nov): measured afresh whenever nothing is presented - no floor from before -
// and kept as it is under a presentation. (20 Nov) A row above its window's top edge is mid-move: its room kept too.
@Suite struct TopClearanceTests {
    @Test func aRowLaidOutAtTheScreensTopComesDownUnderTheIsland() {
        // an iPhone 17 Pro's 62 points of status bar and island, the row drawn from the top edge
        #expect(TopClearance.extra(top: 0, windowTop: 62) == 62)
        // part of the way down already: the rest
        #expect(TopClearance.extra(top: 20, windowTop: 62) == 42)
    }

    @Test func aRowAlreadyUnderTheStatusBarComesDownNothing() {
        #expect(TopClearance.extra(top: 62, windowTop: 62) == 0)
        #expect(TopClearance.extra(top: 80, windowTop: 62) == 0)
        // a Home button's phone: 20 of status bar
        #expect(TopClearance.extra(top: 20, windowTop: 20) == 0)
        #expect(TopClearance.extra(top: 0, windowTop: 20) == 20)
    }

    @Test func noWindowInsetOrNoNumberIsNoRoom() {
        #expect(TopClearance.extra(top: 0, windowTop: 0) == 0)
        #expect(TopClearance.extra(top: -30, windowTop: 0) == 0)
        #expect(TopClearance.extra(top: 0, windowTop: -5) == 0)
        #expect(TopClearance.extra(top: 0, windowTop: .nan) == 0)
        #expect(TopClearance.extra(top: .nan, windowTop: 62) == 0)
        #expect(TopClearance.extra(top: .infinity, windowTop: 62) == 0)
        #expect(TopClearance.extra(top: -.infinity, windowTop: 62) == 0)
        // and nothing presented changes none of it: no inset, no room, whatever was kept
        #expect(TopClearance.room(kept: 62, top: 0, windowTop: 0, presented: false) == 0)
    }

    @Test func aRowAboveTheWindowsEdgeIsMidMoveAndKeepsItsRoom() {
        // 20 Nov, James's phone after Now Playing: "row -117.3 · window 62 · down 124 · nothing presented" - the tabs
        // back in the window, the row above its top edge for that moment. Not a layout to follow: the room is kept as it
        // is, whatever it was, never twice the inset
        #expect(TopClearance.room(kept: 62, top: -117.3, windowTop: 62, presented: false) == 62)
        #expect(TopClearance.room(kept: 0, top: -117.3, windowTop: 62, presented: false) == 0)
        #expect(TopClearance.room(kept: 62, top: -30, windowTop: 62, presented: false) == 62)
        #expect(TopClearance.room(kept: 62, top: -.infinity, windowTop: 62, presented: false) == 62)
        #expect(TopClearance.room(kept: .nan, top: -117.3, windowTop: 62, presented: false) == 0)
        #expect(!TopClearance.settled(top: -117.3) && !TopClearance.settled(top: -1.5) && !TopClearance.settled(top: .nan))
        // a point's rounding above the edge is laid out: read as at the edge, the inset and no more
        #expect(TopClearance.settled(top: -1) && TopClearance.settled(top: 0) && TopClearance.settled(top: 62))
        #expect(TopClearance.room(kept: 124, top: -0.4, windowTop: 62, presented: false) == 62)
        // and `extra` never comes down more than the inset, however high the top
        #expect(TopClearance.extra(top: -30, windowTop: 62) == 62)
        #expect(TopClearance.extra(top: -1e12, windowTop: 20) == 20)
        // once it has settled, read afresh: at the edge the inset, under the status bar nothing
        #expect(TopClearance.room(kept: 124, top: 0, windowTop: 62, presented: false) == 62)
        #expect(TopClearance.room(kept: 124, top: 62, windowTop: 62, presented: false) == 0)
    }

    @Test func aStaleRoomNeverSticksOnceNothingIsPresented() {
        // a room left too large (124, from a reading mid-way through something) and the row now drawn under the status
        // bar: it goes back up to nothing - no floor from before, as `kept` had
        #expect(TopClearance.room(kept: 124, top: 62, windowTop: 62, presented: false) == 0)
        // too small (0, from a reading of another window's inset, or none): the row comes down the inset again
        #expect(TopClearance.room(kept: 0, top: 0, windowTop: 62, presented: false) == 62)
        // part of the way: whatever this reading says
        #expect(TopClearance.room(kept: 62, top: 20, windowTop: 62, presented: false) == 42)
        #expect(TopClearance.room(kept: .nan, top: 0, windowTop: 62, presented: false) == 62)
    }

    @Test func underAPresentationTheRowKeepsTheRoomItHas() {
        // a sheet drawing the screen beneath it smaller (the row lower than it stands) or moving it: kept as it is, in
        // either direction
        #expect(TopClearance.room(kept: 62, top: 40, windowTop: 62, presented: true) == 62)
        #expect(TopClearance.room(kept: 62, top: -100, windowTop: 62, presented: true) == 62)
        #expect(TopClearance.room(kept: 0, top: 0, windowTop: 62, presented: true) == 0)
        // nonsense kept is nothing
        #expect(TopClearance.room(kept: .nan, top: 0, windowTop: 62, presented: true) == 0)
        #expect(TopClearance.room(kept: -10, top: 0, windowTop: 62, presented: true) == 0)
    }

    @Test func debugsLineSaysTheReading() {
        let plain = TopClearance.Reading(top: 0, windowTop: 62, room: 62, presented: false, cause: "layout")
        #expect(plain.line == "row 0 \u{00B7} window 62 \u{00B7} down 62 \u{00B7} nothing presented \u{00B7} after layout")
        let full = TopClearance.Reading(top: -30, windowTop: 61.666, room: 61.666, presented: true,
                                        cause: "presentation gone", swiftTop: 0, swiftSafe: 0)
        #expect(full.line == "row -30 \u{00B7} window 61.7 \u{00B7} down 61.7 \u{00B7} kept, something presented "
            + "\u{00B7} SwiftUI 0, safe 0 \u{00B7} after presentation gone")
        let above = TopClearance.Reading(top: -117.3, windowTop: 62, room: 62, presented: false, cause: "window")
        #expect(above.line == "row -117.3 \u{00B7} window 62 \u{00B7} down 62 \u{00B7} kept, row above the window "
            + "\u{00B7} after window")
        #expect(TopClearance.Reading.points(.nan) == "?")
        #expect(TopClearance.Reading.points(-0.04) == "0")
        #expect(TopClearance.Reading.points(1e12) == "1000000000000.0")
    }
}
