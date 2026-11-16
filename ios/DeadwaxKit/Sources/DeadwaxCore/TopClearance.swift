import Foundation

/// The room the Library's own top leaves over its row, under the status bar and the Dynamic Island (15 Nov, James, a
/// second time: "the library's top still doesn't clear the dynamic island"; notes/ios.md "The Library's top, measured").
///
/// The row was laid out in SwiftUI's safe area - an inset on the pager, then a VStack - and on his iPhone 17 Pro on iOS
/// 27.2 it still stood in the island's strip both times: whatever the safe area its views are given there, it isn't the
/// screen's. So the row no longer trusts it. It measures where its own top is on the screen, and comes down by whatever
/// of the window's top safe area (the status bar's and the island's room, about 62 points on an iPhone 17 Pro, 20 with
/// a Home button) that top doesn't already clear - the window's, as the tab bar's foot is (TabBarFoot), the one source
/// that is the screen's own. Laid out as it should be, under the status bar, the row comes down 0.
///
/// Pure, so it is tested on Linux; LibraryTop pads its row by it.
public enum TopClearance {
    /// How far the row's contents come down, its top at `top` points from the screen's top edge, under a window whose top
    /// safe area is `windowTop` points: the part of `windowTop` above `top`. 0 with no window inset yet, or a top that
    /// isn't a number.
    public static func extra(top: Double, windowTop: Double) -> Double {
        guard top.isFinite, windowTop.isFinite, windowTop > 0 else { return 0 }
        return max(windowTop - max(top, 0), 0)
    }

    /// What the row keeps, measured again at `now`, having come down `kept`: the more of the two. Measured lower than it
    /// stands - its screen drawn smaller under a sheet as iOS presents one - it doesn't climb back into the strip for
    /// the moment the sheet is up, and jump down as it goes; a new window inset (`windowChanged`) starts it afresh.
    public static func kept(_ kept: Double, now: Double, windowChanged: Bool) -> Double {
        let now = now.isFinite ? max(now, 0) : 0
        guard !windowChanged, kept.isFinite else { return now }
        return max(kept, now)
    }
}
