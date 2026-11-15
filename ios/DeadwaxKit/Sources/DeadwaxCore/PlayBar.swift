import Foundation

/// The play bar on the tab bar (15 Nov; notes/ios.md "The play bar on the tab bar"): the rules of its gestures, with no
/// view in them. It is the phone's own, with no web code to hold it to: the web's mini player has a Next button and
/// no gestures.
///
/// - A drag on the bar is read once, as soon as the finger has moved `decideAfter`: its way (across, up or down) and,
///   from where it began, what it does (`role`) - kept until it is let go. A tap is never a drag: it is the cover's,
///   the title's or Play/Pause's, wherever on them it lands.
/// - Across from the bar's top `seekReach` (the seek line, and the room above the title's letters): a seek, once,
///   where it is let go. Across from the title or the cover below that: a skip - left the next song, right the song
///   before, past `skipPast` or flicked past `flickPast`; under them it goes back where it was, and toward a song that
///   isn't there the title moves `resistance` of the finger's way. Across from Play/Pause: nothing.
/// - Up, from anywhere on the bar: Now Playing opens on letting go, past `openPast` or flicked past `openFlickPast`.
/// - A seek or a skip begun on one song and let go on another does nothing (`atLetGo`), as the scrubber drops its drag.
/// - VoiceOver moves the seek line `seekStep` at a time.
///
/// Distances are points; `dy` and its prediction are negative upward, as SwiftUI's translation is.
public enum PlayBar {
    /// How far a finger moves before its drag is read for a direction.
    public static let decideAfter: Double = 10
    /// A drag across this far skips, if it is let go still going that way.
    public static let skipPast: Double = 50
    /// A flick across that would carry the title this far skips.
    public static let flickPast: Double = 120
    /// A drag up this far opens Now Playing, if it is let go still going up.
    public static let openPast: Double = 40
    /// A flick up that would carry the finger this far opens Now Playing.
    public static let openFlickPast: Double = 120
    /// Pulled toward a song that isn't there, the title moves this much of the finger's way.
    public static let resistance: Double = 1.0 / 3
    /// The seek line's reach into the bar from its top edge: a drag across that starts within it seeks. The line is
    /// the top 2 pt; the title's capitals begin about 15 pt down at the standard text size (lower as it grows), so
    /// a swipe on the words is a skip. Nothing above the bar is the line's: the page there keeps its taps and scrolls.
    public static let seekReach: Double = 14
    /// What VoiceOver's swipe up and down on the seek line move by.
    public static let seekStep: Double = 10

    /// A drag's direction, decided once.
    public enum Way: String, Sendable, Equatable {
        case across, up, down
    }

    /// What a drag on the bar does, read once with its way.
    public enum Role: String, Sendable, Equatable {
        case seek, skip, open, nothing
    }

    /// A drag's role from its way and where it began: across within `seekReach` of the bar's top a seek, across from
    /// the title or the cover (`onTitle`) a skip, across from Play/Pause nothing; up, from anywhere, Now Playing; down
    /// nothing.
    public static func role(_ way: Way, startY: Double, onTitle: Bool) -> Role {
        switch way {
        case .across: return startY < seekReach ? .seek : (onTitle ? .skip : .nothing)
        case .up: return .open
        case .down: return .nothing
        }
    }

    /// A drag let go: what it still does. A seek or a skip begun on the entry `began` does nothing once another
    /// (`now`) is playing - the song changed under the finger - so a swipe across a join never skips twice. Opening
    /// Now Playing doesn't depend on the song.
    public static func atLetGo(_ role: Role, began: Int, now: Int?) -> Role {
        guard role == .seek || role == .skip, began != now else { return role }
        return .nothing
    }

    /// Which way a drag on the title goes: nil until the finger has moved `decideAfter`, then across when it has moved
    /// more across than up or down, else up or down.
    public static func way(dx: Double, dy: Double) -> Way? {
        guard (dx * dx + dy * dy).squareRoot() >= decideAfter else { return nil }
        if abs(dx) > abs(dy) { return .across }
        return dy < 0 ? .up : .down
    }

    /// Where a skip goes: the next song, or the one before.
    public enum Skip: String, Sendable, Equatable {
        case next, before
    }

    /// A drag across let go, `dx` from where it began and `predicted` where it would come to rest: the next song for a
    /// drag left, the song before for a drag right - past `skipPast` and still going that way, or flicked past
    /// `flickPast`. Nil: the title goes back where it was.
    public static func skip(dx: Double, predicted: Double) -> Skip? {
        let toward: Double
        if abs(dx) >= skipPast && dx * predicted > 0 {
            toward = dx
        } else if abs(predicted) >= flickPast && (dx == 0 || dx * predicted > 0) {
            toward = predicted
        } else {
            return nil
        }
        return toward < 0 ? .next : .before
    }

    /// The title's offset under a finger `dx` across: the finger's, or a part of it toward a song that isn't there.
    public static func followed(dx: Double, songThere: Bool) -> Double {
        songThere ? dx : dx * resistance
    }

    /// Whether a skip that way has a song to go to: the next song (`after`) for a drag left, the one before
    /// (`before`) for a drag right.
    public static func songThere(dx: Double, before: Bool, after: Bool) -> Bool {
        dx < 0 ? after : before
    }

    /// A drag up let go, `dy` from where it began and `predicted` where it would come to rest: Now Playing opens past
    /// `openPast` while still going up, or flicked past `openFlickPast`.
    public static func opens(dy: Double, predicted: Double) -> Bool {
        (-dy >= openPast && predicted < 0) || -predicted >= openFlickPast
    }

    /// VoiceOver's adjust on the seek line: `seekStep` forward (increment) or back from `from`, never past the song's
    /// ends. Nil with no length yet.
    public static func adjusted(increment: Bool, from: Double, length: Double) -> Double? {
        guard length > 0 else { return nil }
        let at = Scrub.clamp(from, length)
        return Scrub.clamp(at + (increment ? seekStep : -seekStep), length)
    }
}
