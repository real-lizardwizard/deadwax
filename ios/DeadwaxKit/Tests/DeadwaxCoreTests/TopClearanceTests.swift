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

    // (25 Nov) Settled above the window: James's phone as the app opened, "row -15 · window 62 · down 0 · kept, row above
    // the window · SwiftUI -15, safe 0 · after scene active, again" - the row standing 15 points above its window's edge,
    // read again and again, and 20 Nov's rule keeping its 0. Read the same twice, a read again apart, it is followed.

    /// The readings `tops` in turn, a read again (a quarter second) apart, nothing presented - each one's room, from 0.
    private func rooms(_ tops: [Double], windowTop: Double = 62, gap: Double = 0.25) -> [Double] {
        var still = TopClearance.Stillness()
        var room = 0.0
        return tops.enumerated().map { (each: (offset: Int, element: Double)) -> Double in
            let stood = still.read(top: each.element, at: 100 + Double(each.offset) * gap, presented: false)
            room = TopClearance.room(kept: room, top: each.element, windowTop: windowTop, presented: false, stood: stood)
            return room
        }
    }

    @Test func aRowSettledAboveItsWindowIsFollowedOnceTwoReadsAgree() {
        // the first reading keeps what it has; the read again finds it where it was: down the inset and the 15 it stands
        // above the edge, so its contents sit under the 62 - and it stays so while it stands there
        #expect(rooms([-15, -15, -15, -15]) == [0, 77, 77, 77])
        var still = TopClearance.Stillness()
        #expect(still.read(top: -15, at: 10, presented: false) == nil)
        #expect(still.read(top: -15, at: 10.25, presented: false) == -15)
        #expect(-15 + TopClearance.room(kept: 0, top: -15, windowTop: 62, presented: false, stood: -15) == 62)
        #expect(TopClearance.holds(top: -15, windowTop: 62, presented: false, stood: -15))
        // within a point of where it stood is standing there, the room from where it stood - so it holds still
        #expect(rooms([-15, -15.6, -14.2, -15.9]) == [0, 77, 77, 77])
        // a Home button's phone, its 20 of status bar
        #expect(rooms([-8, -8], windowTop: 20) == [0, 28])
        // nothing presented, nothing standing still: the old rules, unchanged - kept above the edge, afresh at it
        #expect(TopClearance.room(kept: 0, top: -15, windowTop: 62, presented: false, stood: nil) == 0)
        #expect(TopClearance.room(kept: 62, top: -15, windowTop: 62, presented: false, stood: nil) == 62)
        #expect(TopClearance.room(kept: 77, top: 0, windowTop: 62, presented: false, stood: 0) == 62)
        // read within a point's rounding of the edge, it is at the edge - afresh, the inset - even where it stood a
        // little higher
        #expect(TopClearance.room(kept: 0, top: -0.6, windowTop: 62, presented: false, stood: -1.5) == 62)
        #expect(!TopClearance.holds(top: -0.6, windowTop: 62, presented: false, stood: -1.5))
        // laid out right, under the status bar, a row followed comes back down nothing (15 Nov's rule)
        #expect(TopClearance.room(kept: 77, top: 62, windowTop: 62, presented: false, stood: 62) == 0)
        #expect(rooms([-15, -15, 62, 62]) == [0, 77, 0, 0])
        // and no inset, no room, standing still or not
        #expect(TopClearance.room(kept: 0, top: -15, windowTop: 0, presented: false, stood: -15) == 0)
        #expect(!TopClearance.follows(top: -15, windowTop: 0) && !TopClearance.follows(top: -15, windowTop: .nan))
    }

    @Test func aRowThatKeepsMovingIsNeverFollowed() {
        // 20 Nov's tabs back from under Now Playing: -117.3 for a moment, then at the edge - never 179 on the way, the
        // inset once it is laid out
        #expect(rooms([-117.3, 0, 0, 0], windowTop: 62) == [0, 62, 62, 62])
        #expect(rooms([-117.3, 0, 0]).allSatisfy { (room: Double) -> Bool in room <= 62 })
        // nor standing there, more than a whole inset above the edge
        #expect(rooms([-117.3, -117.3, -117.3]) == [0, 0, 0])
        #expect(!TopClearance.follows(top: -117.3, windowTop: 62) && !TopClearance.follows(top: -62.5, windowTop: 62))
        #expect(TopClearance.follows(top: -62, windowTop: 62) && TopClearance.follows(top: -1.5, windowTop: 62))
        // a point's rounding above the edge is at it, never followed: `settled`'s
        #expect(!TopClearance.follows(top: -1, windowTop: 62))
        // a top that keeps changing between reads, by more than a point from where it stood, never stands still
        #expect(rooms([-15, -30, -45, -60]) == [0, 0, 0, 0])
        // one creeping stands still only within a point of where it first read: gone further, it stands afresh, so the
        // room is from where it stood - never followed on the move between
        var creeping = TopClearance.Stillness()
        let tops = [-15.0, -15.75, -16.5, -17.25, -18]
        let stood = tops.enumerated().map { (each: (offset: Int, element: Double)) -> Double? in
            creeping.read(top: each.element, at: Double(each.offset) * 0.25, presented: false)
        }
        #expect(stood == [nil, -15, nil, -16.5, nil])
        #expect(rooms(tops) == [0, 77, 77, 78.5, 78.5])
        // two readings in one turn of the main loop - a move UIKit hasn't finished - are never standing still
        #expect(rooms([-30, -30, -30], gap: 0.01) == [0, 0, 0])
        var quick = TopClearance.Stillness()
        #expect(quick.read(top: -30, at: 5, presented: false) == nil)
        #expect(quick.read(top: -30, at: 5.19, presented: false) == nil)
        #expect(quick.read(top: -30, at: 5.2, presented: false) == -30)
        // a clock read going back, or no number, starts it afresh
        #expect(quick.read(top: -30, at: 4, presented: false) == nil)
        #expect(quick.read(top: -30, at: 4.2, presented: false) == -30)
        #expect(quick.read(top: .nan, at: 4.5, presented: false) == nil)
        #expect(quick.read(top: -30, at: 4.7, presented: false) == nil)
        #expect(quick.read(top: -30, at: .infinity, presented: false) == nil && quick.top == nil)
    }

    @Test func underAPresentationARowStandingAboveTheEdgeKeepsItsRoom() {
        // 18 Nov's rule holds over the new one: presented, the room as it is, standing still or not
        #expect(TopClearance.room(kept: 62, top: -15, windowTop: 62, presented: true, stood: -15) == 62)
        #expect(TopClearance.room(kept: 0, top: -15, windowTop: 62, presented: true, stood: -15) == 0)
        #expect(!TopClearance.holds(top: -15, windowTop: 62, presented: true, stood: -15))
        // and a reading under one starts the standing afresh: the two after it, a read again apart, are needed
        var still = TopClearance.Stillness()
        #expect(still.read(top: -15, at: 1, presented: false) == nil)
        #expect(still.read(top: -15, at: 1.25, presented: true) == nil && still.top == nil)
        #expect(still.read(top: -15, at: 1.5, presented: false) == nil)
        #expect(still.read(top: -15, at: 1.75, presented: false) == -15)
    }

    @Test func aRowThatMovesWithItsOwnRoomStopsAndStaysBounded() {
        // the loop: a container that moves the row up by `k` of whatever its room grows - 0 laid out from the top, a
        // half centred (a VStack too tall or too short for its place), the whole bottom-anchored - read a quarter second
        // apart for 10 s. Followed only while no more than a whole inset above the edge, the room is never more than
        // twice the inset, it settles (the last 2 s unchanged), and it never shrinks along the way
        for base in [-15.0, -1.5, 0, 20] {
            for k in [0.0, 0.25, 0.5, 1, 2] {
                var still = TopClearance.Stillness()
                var room = 0.0
                var seen: [Double] = []
                for read in 0 ..< 40 {
                    let top = base - k * room
                    let stood = still.read(top: top, at: Double(read) * 0.25, presented: false)
                    room = TopClearance.room(kept: room, top: top, windowTop: 62, presented: false, stood: stood)
                    seen.append(room)
                }
                #expect(seen.allSatisfy { (each: Double) -> Bool in each >= 0 && each <= 124 }, "base \(base), k \(k)")
                #expect(Set(seen.suffix(8)).count == 1, "base \(base), k \(k): \(seen)")
                #expect(zip(seen, seen.dropFirst()).allSatisfy { (pair: (Double, Double)) -> Bool in pair.1 >= pair.0 },
                        "base \(base), k \(k): \(seen)")
            }
        }
        // laid out from the top (k 0), James's -15: once, 77, its contents at 62
        #expect(rooms([-15, -15, -15]) == [0, 77, 77])
        // centred (k a half): 77 lifts it to -53.5, 115.5 to -72.75 - over a whole inset above the edge, so kept there
        var still = TopClearance.Stillness()
        var room = 0.0
        var steps: [Double] = []
        for read in 0 ..< 12 {
            let top = -15 - room / 2
            room = TopClearance.room(kept: room, top: top, windowTop: 62, presented: false,
                                     stood: still.read(top: top, at: Double(read) * 0.25, presented: false))
            if steps.last != room { steps.append(room) }
        }
        #expect(steps == [0, 77, 115.5])
    }

    @Test func debugSaysARowFollowedAboveTheWindowIsHeld() {
        let held = TopClearance.Reading(top: -15, windowTop: 62, room: 77, presented: false, held: true,
                                        cause: "scene active, again", swiftTop: -15, swiftSafe: 0)
        #expect(held.line == "row -15 \u{00B7} window 62 \u{00B7} down 77 \u{00B7} held, row settled above the window "
            + "\u{00B7} SwiftUI -15, safe 0 \u{00B7} after scene active, again")
        // still moving, as 20 Nov's words; presented and laid out as they were, whatever `held` says
        let moving = TopClearance.Reading(top: -15, windowTop: 62, room: 0, presented: false, cause: "scene active, again")
        #expect(moving.line.contains("down 0 \u{00B7} kept, row above the window \u{00B7}"))
        #expect(TopClearance.Reading(top: -15, windowTop: 62, room: 62, presented: true, held: true, cause: "layout")
            .line.contains("kept, something presented"))
        #expect(TopClearance.Reading(top: 0, windowTop: 62, room: 62, presented: false, held: true, cause: "layout")
            .line.contains("down 62 \u{00B7} nothing presented"))
    }
}
