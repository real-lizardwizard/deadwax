import Foundation

/// Debug's own words that name the device (an admin's page - App/You/DebugView.swift), moved here from the App's
/// literals in the Mac app's slice 4 (notes/ios.md "The Mac app, slice 4: the Mac's words") so both devices' are
/// tested: each is the iPhone's word for word, and the Mac's says this Mac.
public enum DebugWords {
    /// The page's last footer: "deadwax for iPhone 0.13 (13)", "deadwax for Mac 0.13 (13)".
    public static func footer(version: String, device: Device) -> String {
        "deadwax for \(device == .mac ? "Mac" : "iPhone") \(version)"
    }

    /// A test song's row, downloaded: "on the phone", "on the Mac".
    public static func onThe(_ device: Device) -> String { "on the \(device.noun)" }

    /// Test sounds' footer, the turntable's trial after it (`trial`: TurntableDebugRows.trialFooter).
    public static func testSoundsFooter(trial: String, device: Device) -> String {
        "Songs 1 to 8 are three beeps each: tap one to play the album from it and count the beeps - all three, every "
            + "time? Songs 9 and 10 are one tone cut in two: played one into the other, the tone should never break. A "
            + "song downloaded to this \(device.noun) plays from there, as every song does; \"Stream even when "
            + "downloaded\" (under Downloads) streams it instead, to hear the two side by side. \(trial)"
    }

    /// The engine log's footer: `capacity` lines kept, `total` so far. The phone's are read in Console on a Mac,
    /// with the iPhone chosen; the Mac's own, with this Mac chosen.
    public static func engineLogFooter(capacity: Int, total: Int, device: Device) -> String {
        let console = device == .mac
            ? "Console shows them too, as they happen: choose this Mac"
            : "Console on a Mac shows them too, as they happen: choose the iPhone"
        return "The engine's last \(capacity) lines, the newest last (\(total) so far); once there are \(capacity), the "
            + "oldest go as new ones come, so the lines move up while you read - Copy keeps them as they are. Each line "
            + "starts with a time in seconds on the \(device.noun)'s clock: the gaps between lines are what count. "
            + "\(console), turn on Action > Include Info Messages, press Start, then search for "
            + "subsystem:net.lizardlounge.deadwax."
    }
}
