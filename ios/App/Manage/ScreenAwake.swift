import UIKit

/// The screen kept on while a long run goes and its page is in front (Phase 8, slices 7 and 8): Library care's runs
/// (CareRunModel) and Re-time saved lyrics (ServerSettingsModel) each say whether they want it, and it stays on while
/// either does - one place setting the idle timer, so one run ending never lets the screen sleep under the other.
///
/// (The Mac app, slice 5) On the iPhone the idle timer, exactly as before; on the Mac the display - one ProcessInfo
/// activity (idle display sleep off, user initiated) held while either wants it and ended when neither does
/// (Platform.keepDisplayOn).
@MainActor
enum ScreenAwake {
    /// Who wants the screen on now.
    enum Reason: Hashable {
        case libraryCare
        case retime
    }

    private static var wanted: Set<Reason> = []

    /// `reason` wants the screen on, or no longer does.
    static func keep(_ on: Bool, for reason: Reason) {
        if on {
            wanted.insert(reason)
        } else {
            wanted.remove(reason)
        }
        Platform.keepDisplayOn(!wanted.isEmpty)
    }
}

/// (The Mac app, slice 5) Work a hidden window mustn't slow - App Nap kept off while it runs, on the Mac. Each says
/// whether it is under way, whether its page is in front or not: a Library care run (CareRunModel), Re-time saved
/// lyrics (ServerSettingsModel), a download (DownloadModel's tasks out) - and each request held through the background
/// (BackgroundHold: Edit album's applies, a care run's album, a save). One activity for the runs and the holds (user
/// initiated: short, and asked for), another for downloads (user initiated, the Mac's idle sleep still allowed - a
/// MacBook downloading a whole library may sleep as it would, rather than be held awake on battery for hours), each
/// held while anything wants it and ended when nothing does (Platform.keepWorking). Nothing on the iPhone, where
/// beginBackgroundTask stays as it is everywhere.
@MainActor
enum WorkAwake {
    /// What is under way.
    enum Reason: Hashable {
        case libraryCare
        case retime
        case downloads
    }

    private static var wanted: Set<Reason> = []
    /// BackgroundHolds not yet ended.
    private static var holds = 0

    /// `reason` is under way, or no longer is.
    static func keep(_ on: Bool, for reason: Reason) {
        let was = wanted
        if on {
            wanted.insert(reason)
        } else {
            wanted.remove(reason)
        }
        if wanted != was { held() }
    }

    /// A request held through the background began (true) or ended (false).
    static func hold(_ on: Bool) {
        holds = max(0, holds + (on ? 1 : -1))
        held()
    }

    private static func held() {
        Platform.keepWorking(.runs, holds > 0 || wanted.contains(.libraryCare) || wanted.contains(.retime))
        Platform.keepWorking(.downloads, wanted.contains(.downloads))
    }
}
