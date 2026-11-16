import UIKit

/// The screen kept on while a long run goes and its page is in front (Phase 8, slices 7 and 8): Library care's runs
/// (CareRunModel) and Re-time saved lyrics (ServerSettingsModel) each say whether they want it, and it stays on while
/// either does - one place setting the idle timer, so one run ending never lets the screen sleep under the other.
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
        UIApplication.shared.isIdleTimerDisabled = !wanted.isEmpty
    }
}
