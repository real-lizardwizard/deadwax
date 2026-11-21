import Foundation

/// The room the Library's own top leaves over its row, under the status bar and the Dynamic Island (15 Nov, James, a
/// second time: "the library's top still doesn't clear the dynamic island"; notes/ios.md "The Library's top, measured").
///
/// The row was laid out in SwiftUI's safe area - an inset on the pager, then a VStack - and on his iPhone 17 Pro on iOS
/// 27.2 it still stood in the island's strip both times: whatever the safe area its views are given there, it isn't the
/// screen's. So the row no longer trusts it. It measures where its own top is in its window, and comes down by whatever
/// of that window's top safe area (the status bar's and the island's room, about 62 points on an iPhone 17 Pro, 20 with
/// a Home button) that top doesn't already clear - the window's, the one source that is the screen's own. Laid out as
/// it should be, under the status bar, the row comes down 0.
///
/// After Now Playing (18 Nov, James: "after pulling up the play screen and going back to library, the top bar is back
/// inside the Dynamic Island"; notes/ios.md "The Library's top after Now Playing"): the room kept no longer has a floor
/// from before. Under a presentation - a sheet can draw the screen beneath it smaller, or move it - the row keeps the
/// room it has; with nothing presented it is measured afresh, so a stale room, too large or too small, never sticks.
///
/// Not mid-move (20 Nov, James: "well now the whole screen is too low", "It's after I leave the player, but not first
/// when I open the app"; notes/ios.md "The Library's top, too low after Now Playing"): his phone's Debug read "row -117.3
/// · window 62 · down 124 · nothing presented · SwiftUI -117.3, safe 0 · after window" - the tabs back in the window
/// from under Now Playing's cover, the row 117 points above its top edge for that moment, and 18 Nov's rule brought it
/// down the whole way, twice the inset; the row then settled at the edge with nothing telling it, 62 points too low. A
/// row above its window's top edge is mid-way through something, never a layout to follow: it keeps the room it has, as
/// under a presentation (`settled`), and the probe reads again once it has settled.
///
/// Pure, so it is tested on Linux; LibraryTop pads its row by it, from what its UIKit probe reads.
public enum TopClearance {
    /// How far the row's contents come down, its top at `top` points from its window's top edge, in a window whose top
    /// safe area is `windowTop` points: the part of `windowTop` below `top` - never more than the inset, a top above the
    /// edge read as at it. 0 with no window inset, or a number that isn't one.
    public static func extra(top: Double, windowTop: Double) -> Double {
        guard top.isFinite, windowTop.isFinite, windowTop > 0 else { return 0 }
        return max(windowTop - max(top, 0), 0)
    }

    /// How far above its window's top edge a row can be read and still be laid out - a point's rounding.
    public static let edge = 1.0

    /// A row laid out, not mid-way through something: its top a number, and no more than `edge` above its window's top
    /// edge. One higher - 117 points above it, the tabs just back from under Now Playing (20 Nov) - is mid-move.
    public static func settled(top: Double) -> Bool {
        top.isFinite && top >= -edge
    }

    /// The room the row has after a reading - its top at `top` in its window, the window's top safe area `windowTop`,
    /// having come down `kept`: with something presented over the window (`presented`), or the row mid-move (not
    /// `settled`), the room it has, as it is; otherwise `extra` afresh, whatever it had before.
    public static func room(kept: Double, top: Double, windowTop: Double, presented: Bool) -> Double {
        if presented || !settled(top: top) { return kept.isFinite ? max(kept, 0) : 0 }
        return extra(top: top, windowTop: windowTop)
    }

    /// The row's last reading, as Settings > Debug shows it: where its top was in its window, the window's top safe
    /// area, the room it came down, whether something was presented over the window, what asked for the reading - and
    /// what SwiftUI said of the row at the time (its top in SwiftUI's own global space and the top safe area SwiftUI
    /// gave it), so a phone where it still stands in the island says which of the two is short.
    public struct Reading: Equatable, Sendable {
        /// The row's top in its window's coordinates, points.
        public var top: Double
        /// That window's top safe area.
        public var windowTop: Double
        /// The room the row came down.
        public var room: Double
        /// Something was presented over the window: the room was kept as it was.
        public var presented: Bool
        /// What asked for the reading - "window", "layout", "appear", "presentation gone" and the like.
        public var cause: String
        /// SwiftUI's own numbers, nil before SwiftUI has said: the row's top in its global space, and its top safe area.
        public var swiftTop: Double?
        public var swiftSafe: Double?

        public init(top: Double, windowTop: Double, room: Double, presented: Bool, cause: String,
                    swiftTop: Double? = nil, swiftSafe: Double? = nil) {
            self.top = top
            self.windowTop = windowTop
            self.room = room
            self.presented = presented
            self.cause = cause
            self.swiftTop = swiftTop
            self.swiftSafe = swiftSafe
        }

        /// Debug's line, its parts between middle dots: "row 0", "window 62", "down 62", "nothing presented" (or why the
        /// room was kept: "kept, something presented", "kept, row above the window"), "SwiftUI 0, safe 0" (once SwiftUI
        /// has said), "after layout".
        public var line: String {
            let held = presented ? "kept, something presented"
                : TopClearance.settled(top: top) ? "nothing presented" : "kept, row above the window"
            var parts = ["row \(Self.points(top))", "window \(Self.points(windowTop))", "down \(Self.points(room))", held]
            if let swiftTop, let swiftSafe {
                parts.append("SwiftUI \(Self.points(swiftTop)), safe \(Self.points(swiftSafe))")
            }
            parts.append("after \(cause)")
            return parts.joined(separator: " \u{00B7} ")
        }

        /// Points as Debug says them: whole when whole, else to a tenth ("62", "61.7", "-30").
        static func points(_ value: Double) -> String {
            guard value.isFinite else { return "?" }
            let tenths = (value * 10).rounded() / 10
            if abs(tenths) < 1e9, tenths == tenths.rounded() { return String(Int(tenths)) }
            return String(format: "%.1f", tenths)
        }
    }
}
