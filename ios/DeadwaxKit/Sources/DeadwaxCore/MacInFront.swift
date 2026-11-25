import Foundation

// The page in front on the Mac (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and
// the shared pieces"): what the status bar shows (MacStatusItems) and what Info takes as selected (MacSelection) are
// the page in front's - the page that came on screen last of those still on it. A page pushed over another, or another
// tab chosen, takes the one under it off the screen (its onDisappear); as the page over it goes, the one under comes
// back (its onAppear) and is in front again.
//
// A page says something only while it is on screen. A page off the screen - a list under a pushed album, still holding
// its own selection and still able to change it - is not one of them: what it says then changes nothing, and it says
// it again as it comes back. Pure, and tested on Linux, because the SwiftUI side of it can't be.

public struct MacInFront<Page: Hashable & Sendable, Value: Equatable & Sendable>: Equatable, Sendable {
    private struct Shown: Equatable, Sendable {
        let page: Page
        var value: Value
    }

    /// The pages on screen that have said something, the one that came on last at the end.
    private var shown: [Shown] = []

    public init() {}

    /// The page in front's: what the page on screen that came on last says - none while no page that says anything is
    /// on screen.
    public var front: Value? { shown.last?.value }

    /// `page` came on screen saying `value`: it is in front now.
    public mutating func appeared(_ page: Page, saying value: Value) {
        shown.removeAll { $0.page == page }
        shown.append(Shown(page: page, value: value))
    }

    /// `page` says something new: where it is - in front, or on screen under the one in front. A page off the screen
    /// changes nothing (it is never put in front by it).
    public mutating func changed(_ page: Page, to value: Value) {
        guard let at = shown.firstIndex(where: { $0.page == page }) else { return }
        shown[at].value = value
    }

    /// `page` went from the screen: what it said goes with it.
    public mutating func gone(_ page: Page) {
        shown.removeAll { $0.page == page }
    }

    /// Whether `page` is on screen, as far as this knows.
    public func isShown(_ page: Page) -> Bool {
        shown.contains { $0.page == page }
    }
}
