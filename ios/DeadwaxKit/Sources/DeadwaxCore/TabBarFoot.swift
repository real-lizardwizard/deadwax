import Foundation

/// The room under the tab bar's words (15 Nov, James: "there might be a little too much space below the bottom tab bar";
/// notes/ios.md "The tab bar, lower").
///
/// The bar was laid out above the home indicator's whole room - 34 points of a Face ID iPhone's foot, as iOS's own bar
/// before iOS 26 lays out its items - with the words a few points above that, their baseline about 40 points off the
/// screen's edge. The tabs now come down `drop` points into that room. The home indicator is a 5-point bar whose foot
/// is about 8 points off the edge, so its top is about 13 up; the tabs' foot at 20 puts the words' line (about 2.5
/// points of the tab's slack under it) about 22 up and their baseline about 26 - some 9 points of clear room over the
/// indicator. A phone with a Home button has no such room (0): there the tabs keep `least` off the edge, where they
/// were flush with it.
///
/// Pure, so it is tested on Linux; the app's AppTabBar pads its tabs by `below` and MainTabs gives the pages `room`.
public enum TabBarFoot {
    /// How far into the home indicator's room the tabs come down: 14 of a Face ID iPhone's 34.
    public static let drop = 14.0
    /// The least room under the tabs, to the screen's edge: a phone with no home indicator's room.
    public static let least = 6.0

    /// The room under the tabs, to the screen's edge, over a home indicator's room of `home` points (the window's
    /// bottom safe area: 34 on a Face ID iPhone, 0 with a Home button).
    public static func below(home: Double) -> Double {
        guard home.isFinite, home > 0 else { return least }
        return max(home - drop, least)
    }

    /// The room the pages and the notice leave for the bar over the home indicator's own: the bar's `content` (the play
    /// bar and the tabs, `below` not counted) and the room under it, less the home indicator's - never below 0.
    public static func room(content: Double, home: Double) -> Double {
        let indicator = home.isFinite ? max(home, 0) : 0
        return max(content + below(home: home) - indicator, 0)
    }
}
