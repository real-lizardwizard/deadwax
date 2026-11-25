import DeadwaxCore
import Testing

/// The page in front (MacInFront): the status bar's facts and Info's selection are the page in front's, and a page off
/// the screen never puts itself there (R1's review, finding 5).
struct MacInFrontTests {
    @Test func thePageThatCameOnLastIsInFront() {
        var front = MacInFront<String, String>()
        #expect(front.front == nil)
        front.appeared("albums", saying: "140 albums")
        #expect(front.front == "140 albums")
        front.appeared("requests", saying: "3 on their way")
        #expect(front.front == "3 on their way")
        // as the one over it goes, the one under it is in front again
        front.gone("requests")
        #expect(front.front == "140 albums")
        front.gone("albums")
        #expect(front.front == nil)
    }

    @Test func aPageChangesWhatItSaysWhereItIs() {
        var front = MacInFront<String, String>()
        front.appeared("albums", saying: "140 albums")
        front.appeared("panel", saying: "Info")
        // the page under the one in front changes: in its own place, not in front
        front.changed("albums", to: "141 albums")
        #expect(front.front == "Info")
        front.gone("panel")
        #expect(front.front == "141 albums")
        // a page coming on again goes in front with what it says now
        front.appeared("panel", saying: "Info")
        front.appeared("albums", saying: "142 albums")
        #expect(front.front == "142 albums")
    }

    @Test func aPageOffTheScreenIsNeverPutInFront() {
        // a list (A) with a row selected; an album (B) pushed over it, which selects nothing - A goes from the screen
        var front = MacInFront<String, String?>()
        front.appeared("A", saying: "Back in Black")
        front.appeared("B", saying: nil)
        front.gone("A")
        #expect(front.front == .some(nil))
        // A, under B, changes its selection: nothing changes, and A is not B's owner
        front.changed("A", to: "Highway to Hell")
        #expect(front.front == .some(nil))
        #expect(!front.isShown("A"))
        // B goes; A isn't on screen until it comes back - then with what it selects now
        front.gone("B")
        #expect(front.front == nil)
        front.changed("A", to: "Powerage")
        #expect(front.front == nil)
        front.appeared("A", saying: "Powerage")
        #expect(front.front == .some("Powerage"))
    }

    @Test func aPageSaysOnceHoweverOftenItComesOn() {
        var front = MacInFront<Int, Int>()
        front.appeared(1, saying: 10)
        front.appeared(2, saying: 20)
        front.appeared(1, saying: 11)
        #expect(front.front == 11)
        front.gone(1)
        #expect(front.front == 20)
        front.gone(2)
        #expect(front.front == nil)
    }
}
