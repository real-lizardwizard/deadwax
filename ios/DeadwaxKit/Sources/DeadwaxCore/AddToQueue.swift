import Foundation

/// Add to Queue (notes/ios.md "Add to Queue: the swipe, and the menus' one item"; 16 Nov, James: "Can we also add
/// swiping to add to queue" - "In fact I'd prefer if instead of next and last, we could just use 'add to queue' that
/// just puts it at the end of the queue" - and, asked whether the ••• menus should change too, "Only Add to Queue").
/// The phone's one way to queue: a song row's swipe from its leading edge, and the one item every ••• had Play Next and
/// Play Last in. It is the web's Play Last (`choice`: UpNext's withLast, QueueController.playLast) - after the songs
/// already added, still ahead of the rest of what plays (the album, the playlist, the shuffle). So with nothing added
/// the first song plays next, and each one after it in the order it was added, as Spotify's Add to queue.
///
/// The web app keeps Play Next and Play Last (ui/src/app/QueueMenu.tsx): this is where the phone departs from it,
/// held against the web's own words and calls in ScreenQueueTests, so a change on either side is looked at. Core's
/// Play Next (withNext, QueueController.playNext, QueueChoice.next) stays, unoffered - the engine's and the web's.
public enum AddToQueue {
    /// The swipe's button, the •••'s item and the row's VoiceOver action - in title case, as the menus' other words.
    public static let words = "Add to Queue"
    /// What it does: the web's Play Last - its call, its level, its notice ("Added to Up Next: Roads").
    public static let choice: QueueChoice = .last
    /// Its symbol, the menu's and the swipe's: Play Last's.
    public static let symbol = DownloadWords.playLastSymbol
    /// The swipe's purple, under a white symbol: the app's primary purple (PrimaryButton, theme.css --dw-primary-bg, at
    /// its foot - #8a2ee0, 5.9:1). The app's tint itself (#C084FC, --dw-accent) is the web's accent for text on black:
    /// under a white symbol it is 2.64:1, which is what James couldn't see on the album page's Play.
    public static let fill = PrimaryButton.bottom
    /// The symbol on it.
    public static let glyph = PrimaryButton.label

    /// What Add to Queue adds of a pick - a •••'s, or a row's (the same pick, the row's own •••) - and nil where it
    /// isn't offered: the ••• leaves it out, and the row has no swipe and no VoiceOver action. One rule for both, so
    /// the swipe is wherever the menu has the item. The pick, while deadwax can be reached; while it can't, or for an
    /// album gone from the collection (`gone`), only its songs on this phone (`here`, by song id), in their order -
    /// none of them here: nil. A pick of no songs: nil.
    public static func pick(_ pick: QueuePick<Song>, online: Bool, gone: Bool,
                            here: (String) -> Bool) -> QueuePick<Song>? {
        guard !pick.tracks.isEmpty else { return nil }
        guard !online || gone else { return pick }
        let songs = OfflineAlbum.playable(pick.tracks, here: here)
        guard !songs.isEmpty else { return nil }
        return QueuePick(label: pick.label, tracks: songs, albumIds: pick.albumIds, queuedAs: pick.queuedAs)
    }
}

/// The swipe drawn by hand, for the song rows outside a List (Songs, Search: a ScrollView's stack, where SwiftUI's
/// swipeActions do nothing) - made to look and act as a List's own leading swipe action does on an album's and a
/// playlist's page: the row slides right over the purple, one button; let go past half the row and it adds; let go
/// with the button half out or more and the row stands open on it; less, it closes. Every number and decision is
/// here, the app only draws (AddToQueueSwipe.swift).
public enum QueueSwipe {
    /// The open button's width, in points: a List's swipe action's.
    public static let button = 74.0
    /// A pan that starts this close to the screen's leading edge is the back swipe's, never the row's.
    public static let backEdge = 24.0
    /// Flung faster than this (points a second) the row goes the way it was flung: open rightwards, shut leftwards.
    public static let fling = 500.0
    /// The share of the row's width past which letting go adds (the full swipe).
    public static let fullShare = 0.5

    /// Where the full swipe begins: half the row - never before the button is well out.
    public static func fullAt(width: Double) -> Double {
        max(button * 2, width * fullShare)
    }

    /// Whether `offset` is past the full swipe: letting go there adds (the haptic's tick as it crosses).
    public static func full(_ offset: Double, width: Double) -> Bool {
        offset >= fullAt(width: width)
    }

    /// Whether a pan on a row is its swipe's, as it would begin: sideways more than up or down - rightwards, or either
    /// way while the row stands open (leftwards shuts it) - and not from the screen's leading edge (`startX`, where the
    /// pan began, from the screen's left), which is the back swipe's. A pan up or down is the list's scroll.
    public static func begins(dx: Double, dy: Double, startX: Double, open: Bool) -> Bool {
        guard startX >= backEdge, abs(dx) > abs(dy) else { return false }
        return dx > 0 || open
    }

    /// How far right the row stands for a pan of `dx` from where it stood (`from`: 0 shut, `button` open): never left of
    /// shut (the trailing edge has no swipe), never past the row's width.
    public static func moved(_ dx: Double, from: Double, width: Double) -> Double {
        min(max(from + dx, 0), max(width, 0))
    }

    /// What letting go does.
    public enum Release: Equatable, Sendable {
        /// past the full swipe: added, and the row shuts behind it
        case add
        /// the row stands open on the button
        case open
        case shut
    }

    /// Letting go at `offset`, moving at `velocity` (points a second, rightwards positive), on a row `width` wide.
    public static func release(at offset: Double, velocity: Double, width: Double) -> Release {
        if full(offset, width: width) { return .add }
        if offset <= 0 { return .shut }
        if velocity <= -fling { return .shut }
        if velocity >= fling { return .open }
        return offset >= button / 2 ? .open : .shut
    }
}
