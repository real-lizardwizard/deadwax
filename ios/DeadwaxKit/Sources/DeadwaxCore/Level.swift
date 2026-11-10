import Foundation

/// The level a queued song plays at under the player's Normalization (ui/src/lib/loudness.ts `Level`): its album's,
/// or its own. A queue entry without one (`nil`) plays as the file is - the setting Off.
///
/// Declared here for Up Next's `QueueTrack`, which carries it; the Normalization port (its `levelFor`, `relevel`,
/// the gain) declares the very same type in its own file, and where both meet only one of the two stays.
public enum Level: String, Codable, Sendable {
    case album, track
}
