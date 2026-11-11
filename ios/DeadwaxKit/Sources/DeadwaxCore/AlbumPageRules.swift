import Foundation

/// The playing song's mark on an album page's row - ui/src/player/AlbumPage.tsx's `isCurrent` and
/// ui/src/player/icons.tsx's PlayingBars, ported as written: the row of the song the player has (`player.track?.id
/// === song.id` - by the song's id, so the album's song is marked whichever queue is playing it) draws three bars in
/// place of its number, still while paused, and names them for VoiceOver as the web's aria-label does.
///
/// Held by hand (Tests/DeadwaxCoreTests/AlbumPageRulesTests.swift): the two words are icons.tsx's literals, and the
/// comparison is one `===` on two strings - there is no rule in them for a vector to exercise.
public enum PlayingBars {
    /// The bars' name: "playing", or "paused" while the player holds the song paused (icons.tsx's aria-label).
    public static func label(paused: Bool) -> String { paused ? "paused" : "playing" }

    /// Whether `song`'s row is the one the player has: the queue entry heard is this song (by id). Nothing queued,
    /// nothing marked.
    public static func marks(_ song: Song, heard: QueueTrack?) -> Bool {
        guard let heard else { return false }
        return WebText.same(heard.id, song.id)
    }
}

/// An album page whose album isn't there - the PHONE'S OWN rule, with no TypeScript behind it.
///
/// Gone is Navidrome answering `{}` for the id (DeadwaxClient.album's nil) or deadwax answering 404 (Navidrome's code
/// 70, "Navidrome has nothing by that id" - ErrorWords' not-found, which the page says as `ErrorWords.albumGone`).
/// The web draws the first as an empty album ("0 songs") and, for both, goes on drawing whose it is from a bridge that
/// can only answer for an id Navidrome doesn't have with no release - so a personal user read "In the collection" and
/// "This album can't be added from here - make it a favourite in another music app" of an album that is gone. The
/// phone draws a gone album as what opened it and the gone line alone: no badge, no mine block, no Play.
public enum AlbumGone {
    /// Whether the album's answer says it is gone: `empty` (the `{}` answer), or a failure ErrorWords reads as
    /// not-found. Any other failure isn't gone - the page says it in ErrorWords' words and draws whose it is as the
    /// web does (Whose.albumMine's `albumFailed`).
    public static func isGone(empty: Bool, failure: (any Error)?) -> Bool {
        if empty { return true }
        guard let failure else { return false }
        return ErrorWords.kind(of: failure) == .notFound
    }
}
