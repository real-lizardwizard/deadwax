import Foundation

/// The play bar on the tab bar (15 Nov; notes/ios.md "The play bar on the tab bar"): the rules of its gestures, with no
/// view in them. It is the phone's own, with no web code to hold it to: the web's mini player has a Next button and
/// no gestures.
///
/// - A drag on the title (or the cover) is read for its direction once, as soon as the finger has moved
///   `decideAfter`: across is a skip, up opens Now Playing, down does nothing. It keeps that direction until let go.
/// - Across: left is the next song, right the song before, past `skipPast` or flicked past `flickPast`. Under them,
///   it goes back where it was. Toward a song that isn't there, the title moves `resistance` of the finger's way.
/// - Up: Now Playing opens on letting go, past `openPast` or flicked past `openFlickPast`.
/// - The seek line: a drag along it seeks once, where it is let go. A touch that never moved `seekSlop` across seeks
///   nowhere, since the line's touch area reaches over the title's top and the page's foot. VoiceOver moves it
///   `seekStep` at a time.
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
    /// The seek line's touch moved less than this across seeks nowhere.
    public static let seekSlop: Double = 4
    /// What VoiceOver's swipe up and down on the seek line move by.
    public static let seekStep: Double = 10

    /// A drag's direction, decided once.
    public enum Way: String, Sendable, Equatable {
        case across, up, down
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

    /// A touch on the seek line let go, `moved` the furthest it went across from where it went down: whether it seeks.
    public static func seeks(moved: Double) -> Bool {
        moved >= seekSlop
    }

    /// VoiceOver's adjust on the seek line: `seekStep` forward (increment) or back from `from`, never past the song's
    /// ends. Nil with no length yet.
    public static func adjusted(increment: Bool, from: Double, length: Double) -> Double? {
        guard length > 0 else { return nil }
        let at = Scrub.clamp(from, length)
        return Scrub.clamp(at + (increment ? seekStep : -seekStep), length)
    }
}
