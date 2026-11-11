import Foundation

/// The level a queued song plays at under the player's Normalization (ui/src/lib/loudness.ts `Level`): its album's,
/// or its own. A queue entry without one (`nil`) plays as the file is - the setting Off.
///
/// Declared here for Up Next's `QueueTrack`, which carries it; the Normalization port (branch p1/levels, Levels.swift:
/// its `levelFor`, `relevel`, the gain) declares the very same type, conformances included, and where both meet
/// Levels.swift's is kept and this file deleted.
public enum Level: String, Codable, Sendable, CaseIterable {
    case album, track
}
