import Testing
@testable import DeadwaxCore

// The tab bar's foot (15 Nov, TabBarFoot): the tabs brought down into the home indicator's room, clear of it, and a
// small margin where there is none.
@Suite struct TabBarFootTests {
    @Test func onAFaceIDPhoneTheTabsComeDownFourteenPoints() {
        #expect(TabBarFoot.below(home: 34) == 20)
    }

    @Test func theTabsStayClearOfTheHomeIndicator() {
        // the indicator's top about 13 points off the edge (5 tall, its foot about 8 up): the tabs' foot well over it
        #expect(TabBarFoot.below(home: 34) - 13 >= 6)
    }

    @Test func withNoHomeIndicatorTheyKeepASmallMargin() {
        #expect(TabBarFoot.below(home: 0) == 6)
        #expect(TabBarFoot.below(home: 15) == 6)
        #expect(TabBarFoot.below(home: -1) == 6)
        #expect(TabBarFoot.below(home: .nan) == 6)
    }

    @Test func thePagesRoomIsTheBarOverTheHomeIndicator() {
        // 100 points of play bar and tabs, 20 under them, 34 of it the home indicator's: 86 over it
        #expect(TabBarFoot.room(content: 100, home: 34) == 86)
        // a Home button's phone: the whole bar, its margin with it
        #expect(TabBarFoot.room(content: 100, home: 0) == 106)
        #expect(TabBarFoot.room(content: 0, home: 34) == 0)
        #expect(TabBarFoot.room(content: 100, home: .nan) == 106)
    }
}
