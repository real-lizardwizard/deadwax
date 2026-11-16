import Testing
@testable import DeadwaxCore

// The Library's top, measured (15 Nov, TopClearance): the row comes down by what of the window's top safe area its own
// top doesn't clear, and keeps it.
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
        #expect(TopClearance.extra(top: 0, windowTop: .nan) == 0)
        #expect(TopClearance.extra(top: .nan, windowTop: 62) == 0)
        #expect(TopClearance.extra(top: .infinity, windowTop: 62) == 0)
        // above the screen's top, mid-way through something: never more than the whole inset
        #expect(TopClearance.extra(top: -30, windowTop: 62) == 62)
    }

    @Test func theRowKeepsWhatItCameDownUnderASheet() {
        // measured lower under a sheet (its screen drawn smaller): it stays where it came down to
        #expect(TopClearance.kept(62, now: 0, windowChanged: false) == 62)
        #expect(TopClearance.kept(0, now: 62, windowChanged: false) == 62)
        // a new window inset starts afresh
        #expect(TopClearance.kept(62, now: 0, windowChanged: true) == 0)
        #expect(TopClearance.kept(.nan, now: 10, windowChanged: false) == 10)
        #expect(TopClearance.kept(5, now: .nan, windowChanged: false) == 5)
    }
}
