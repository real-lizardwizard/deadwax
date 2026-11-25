import Foundation

// The Queue's own words on both devices (the redesign, slice R3b - notes/ios.md "The redesign, slice R3b: the Queue,
// Info and the EQ inside"; iQueue.dc.html): the time left at its foot, "8 songs · 33 min left", and the phone's
// list's heading. Read from UpNextView - the rows the page draws - so Core's UpNext and QueueController are
// as they were.

/// The time left at the Queue's foot (iQueue's "8 songs · 33 min left"), read from what the page draws.
public enum QueueTimeLeft {
    static let dot = " · "

    /// "8 songs · 33 min left": the songs still to come after the one playing - Playing Next's, the list's this time
    /// round, and those past its first `UpNext.drawn` (`more`) - and the time they take with what is left of the song
    /// playing, at `speed`. History never counts: it has played. Nil with nothing playing, or nothing to say.
    ///
    /// - The time is what is left of the song playing - its length less `position`, never below none, never the whole
    ///   song - and every song drawn after it, whole, to the minute rounded up; under a minute "under 1 min left", and
    ///   none left no time at all (never "0 min left").
    /// - A song of unknown length (0), or songs past the drawn ones, make it a least, to the minute rounded DOWN so it
    ///   never says more than is known: "over 33 min left" - and under a whole minute known, no time (never "over 0
    ///   min left", nor "under 1 min", which the songs not known could make untrue).
    /// - Under Repeat one the song playing plays until it is skipped, so no time is said: the songs alone, "8 songs".
    /// - Under Repeat all (R3b's review) only the rows still to come of the ONE time round the list draws count: the rest
    ///   of the round playing - or, at its last song, the next round whole, drawn as "Next from Wilco (The Album),
    ///   again" - and never the rounds after it (UpNextView: "neither Repeat One's copies nor the later times round"),
    ///   which are the view's `then` line, "Then Wilco (The Album) again from the top.", with no songs or time here.
    ///   So "1 song · 6 min left" is what is left of the round drawn, not of the music: Repeat All never ends.
    /// - With nothing after the song playing, its time alone: "3 min left".
    public static func words(_ view: UpNextView, position: Double, speed: Double = 1) -> String? {
        guard let playing = view.playing else { return nil }
        //? the rows drawn, the one round's: under Repeat All the later rounds are never in the view's rows
        let after = view.added + (view.list?.rows ?? [])
        let more = view.list?.more ?? 0
        let count = after.count + more
        let songs = count == 0 ? nil : count == 1 ? "1 song" : "\(count) songs"
        if view.repeatOne { return songs }
        let length = playing.duration.isFinite ? playing.duration : 0
        let heard = position.isFinite ? min(max(position, 0), max(length, 0)) : 0
        var seconds = max(length, 0) - heard
        var least = more > 0 || length <= 0
        for row in after {
            let each = row.track.duration
            if each.isFinite && each > 0 {
                seconds += each
            } else {
                least = true
            }
        }
        let rate = speed.isFinite && speed > 0 ? speed : 1
        let said = [songs, left(seconds / rate, least: least)].compactMap { $0 }
        return said.isEmpty ? nil : said.joined(separator: dot)
    }

    /// (R3b's review) The time part: "33 min left", "under 1 min left", a least's "over 33 min left" (rounded down) -
    /// nil with none left, or a least of under a whole minute.
    static func left(_ seconds: Double, least: Bool) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        if least {
            let minutes = Int((seconds / 60).rounded(.down))
            return minutes == 0 ? nil : "over " + span(Double(minutes) * 60) + " left"
        }
        return seconds < 60 ? "under 1 min left" : span(seconds) + " left"
    }

    /// A span of time to the minute, rounded up - what is left is never said as none while a song plays: "1 min",
    /// "33 min", "1 hr", "1 hr 12 min".
    public static func span(_ seconds: Double) -> String {
        let minutes = seconds.isFinite && seconds > 0 ? Int((seconds / 60).rounded(.up)) : 0
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}

/// The phone's Queue page's own words (iQueue): the list's heading, and which rows say their artist and album. (R3b's
/// review) No heading over the song playing, nor over Playing Next's: the sheet's top has said where the page is.
public enum QueuePageWords {
    /// What VoiceOver calls the top's ••• at the larger text sizes, History and Clear in it.
    public static let more = "More for the Queue"

    /// The list's heading: "Next from Wilco (The Album)" for the album's "From Wilco (The Album)" (", again" kept); any
    /// other list's title as it is ("Still to play", "Your library, shuffled").
    public static func heading(_ title: String) -> String {
        title.hasPrefix("From ") ? "Next from " + title.dropFirst("From ".count) : title
    }

    /// Whether a group's rows say their artist and album under their titles: not under an album's heading ("From …")
    /// when every row is that one album's, by one artist - the heading has said it, and iQueue's rows are their
    /// titles. Playing Next's songs, History's, a list of many albums: each says its own.
    public static func showsLines(_ rows: [UpNextRow], title: String) -> Bool {
        guard title.hasPrefix("From "), let first = rows.first?.track else { return true }
        return !rows.allSatisfy { $0.track.album == first.album && $0.track.artist == first.artist }
    }
}
