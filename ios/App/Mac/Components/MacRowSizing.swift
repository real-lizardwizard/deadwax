import DeadwaxCore
import SwiftUI

/// The rows' size every Mac list draws at (the Mac's Row Size - notes/ios.md "The Mac's Row Size (2026-11-25)"):
/// View > Row Size's Small, Medium or Large, as this Mac keeps it (Core's MacRowSize, MacCommands' MacRowSizeStore).
/// The desktop frame reads the kept choice once and hands it to everything under it, so each list - MacColumnList's rows
/// (Albums, Artists, an album's songs, Playlists, a playlist's songs), the covers its pages draw in them, and Requests'
/// table - reads the one value, and every list changes together as the menu, ⌘+ or ⌘− changes it. A view drawn outside
/// the frame (a sheet's own window on the Mac) reads Small, today's rows.
private struct MacRowSizeKey: EnvironmentKey {
    static let defaultValue: MacRowSize = .standard
}

extension EnvironmentValues {
    /// How tall the Mac's lists' rows are, and their covers (MacRowSize's rowHeight and cover - Requests' its own
    /// requestRowHeight and requestCover).
    var macRowSize: MacRowSize {
        get { self[MacRowSizeKey.self] }
        set { self[MacRowSizeKey.self] = newValue }
    }
}
