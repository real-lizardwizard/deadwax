import Foundation

// Lyrics on Now Playing (app 0.4, notes/app-lyrics.md sections 2 and 4) - James: "I want to make sure you can view
// lyrics as well", like Apple Music: synced, the line being sung lit and kept in view, a tap on a line to play from
// there; plain lyrics just scroll.
//
// The web app's ui/src/lib/lyricsView.ts, ported: its words (LyricsWords) and every rule its view and its answers
// follow (Lyrics) - which line is lit, the dots in a break, when the view follows the song and when the listener's
// own scroll holds it, the Lyrics button's names - held to what the TypeScript answers by
// Tests/DeadwaxCoreTests/Fixtures/lyrics/lyrics-vectors.json, written by ios/scripts/export-lyrics-vectors.cjs (never
// by hand; ui/test/ioslyrics.sim.cjs runs it with --check). The keyboard's rules (tabStop, lineAfterKey,
// SCROLL_KEYS) aren't ported: a phone has no tab stop to rove.
//
// The phone's own rules, with no TypeScript to hold them to, follow in their own section: the button's state offline
// (`have(_:online:)`), what the face shows (`Face`), the backdrop and the dim lines' contrast, and the hold - the
// listener's scroll and VoiceOver's focus as a value the view keeps (`LyricsHold`).

// MARK: - the answer

/// One line of a song's lyrics - `time` seconds into the song (synced), nil for plain lyrics; `text` "" for a break
/// between verses (synced only).
public struct LyricLine: Codable, Sendable, Equatable, Hashable {
    public let time: Double?
    public let text: String

    public init(time: Double?, text: String) {
        self.time = time
        self.text = text
    }
}

/// `GET /deadwax/navidrome/lyrics/{song_id}`'s answer (server 2.1.5, src/lyrics.py song_lyrics): deadwax's own shape
/// of what Navidrome has for the song. Three cases and only three: synced (every line timed, in time order), plain
/// (every time nil, in the file's order), none (not synced, no lines - a fact about the song, not a failure).
public struct SongLyrics: Codable, Sendable, Equatable {
    public let synced: Bool
    public let lines: [LyricLine]

    public init(synced: Bool, lines: [LyricLine]) {
        self.synced = synced
        self.lines = lines
    }
}

/// The lyrics route's answer as deadwax sent it - read, and its body kept as it came (a downloaded song's lyrics are
/// kept with it, notes/app-lyrics.md 4.7).
public struct LyricsAnswer: Sendable, Equatable {
    public let lyrics: SongLyrics
    public let body: Data

    public init(lyrics: SongLyrics, body: Data) {
        self.lyrics = lyrics
        self.body = body
    }
}

// MARK: - the words (2.1, verbatim)

public enum LyricsWords {
    /// The Lyrics button's name, off and on ("on" is VoiceOver's "Selected"), and the lyrics' own name as VoiceOver
    /// enters them.
    public static let lyrics = "Lyrics"
    /// ...when the song playing has none: dimmed while lyrics are off, selected while they're on.
    public static let none = "Lyrics - none for this song"
    /// ...offline, with none kept on this phone for the song.
    public static let notKept = "Lyrics - not on this phone"
    /// The spinner's name, while asking.
    public static let loading = "Loading lyrics"
    /// None, where a place must say something (the web's desktop panel; the phone shows the cover instead).
    public static let noLyrics = "No lyrics for this song."
    /// The web's desktop panel with nothing playing.
    public static let nothingPlaying = "Nothing playing"
    /// Plain lyrics, above the first line.
    public static let notSynced = "These lyrics aren't synced to the song."
    /// A failure: ErrorWords.of's `failed`, said in place of an unreachable's or an other's sentence.
    public static let failed = "Couldn't load the lyrics."
    /// A 404: the song isn't the music server's any more (a queue older than a rescan), or isn't theirs - ErrorWords.of's
    /// `gone`, in the album's words - and no Try again, which can't find it.
    public static let songGone = "This song isn't here any more - it may have been moved or deleted."
    /// A synced line's VoiceOver hint.
    public static let lineHint = "Plays from here."
    /// The VoiceOver action on every line but the lit one.
    public static let goToLit = "Go to the line being sung"

    /// The Lyrics button's name - the same off and on, its state said by VoiceOver's "Selected" (lyricsLabel).
    public static func label(_ have: LyricsHave) -> String {
        switch have {
        case .empty: return none
        case .notKept: return notKept
        case .unknown, .some: return lyrics
        }
    }

    /// `83.4` -> "1:23": how a synced line's time is said (lib/lyrics.ts lyricTime) - its numbers through JavaScript's
    /// Math, as the web's.
    public static func time(_ seconds: Double) -> String {
        let whole = JSNumber.max(0, seconds.rounded(.down))
        return "\(JSNumber.string((whole / 60).rounded(.down))):"
            + JSNumber.padTwo(JSNumber.string(whole.truncatingRemainder(dividingBy: 60)))
    }

    /// A line's VoiceOver value: its time - "1:23", the lit one "1:23, now" (lineValue).
    public static func lineValue(_ time: Double, lit: Bool) -> String {
        lit ? "\(self.time(time)), now" : self.time(time)
    }
}

// MARK: - the rules (2.2-2.7)

/// What is known of the song playing's lyrics (LyricsHave): not yet (not asked, being asked, or the ask failed), some
/// (synced or plain), none - and, the phone's alone, none kept on it for the song while deadwax can't be reached.
public enum LyricsHave: String, Sendable, Equatable, CaseIterable {
    case unknown
    case some
    /// none for this song
    case empty = "none"
    case notKept = "not-kept"
}

/// The lines lit: inclusive indices - one line, or several written at one time (a duet written once per voice).
public struct LitRange: Sendable, Equatable, Hashable {
    public let first: Int
    public let last: Int

    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }

    public func contains(_ index: Int) -> Bool { index >= first && index <= last }
}

/// What the view draws as the clock moves: the lines lit and the lit break's dots (0 to 3). Two moments draw the same
/// when they are equal (sameLit).
public struct Lit: Sendable, Equatable, Hashable {
    public let range: LitRange?
    public let dots: Int

    public init(range: LitRange?, dots: Int) {
        self.range = range
        self.dots = dots
    }

    /// Nothing lit (plain lyrics, an intro short of the dots, before the first line).
    public static let unlit = Lit(range: nil, dots: 0)
}

public enum Lyrics {
    // MARK: the numbers

    /// Where the line being sung is held: this share of the lyrics' height from their top (2.5).
    public static let anchor = 0.3
    /// How long after the listener's last scroll - or VoiceOver's focus leaving the lyrics - following comes back,
    /// while the song plays (2.5), in milliseconds.
    public static let followAgainMs = 4000.0
    /// The shortest gap between a break and the next line sung that draws the three dots - an intro too (2.4).
    public static let gapDotsSeconds = 4.0
    /// The next song's lyrics are asked for once the song playing has this long left, while the lyrics show (2.6).
    public static let nextLyricsSeconds = 20.0
    /// How many songs' answers are kept in memory, the least recently used going first (2.6).
    public static let kept = 50

    // MARK: the button (2.7)

    /// What an answer says of the song: none is an answer with no lines (lyricsHave).
    public static func have(_ lyrics: SongLyrics?) -> LyricsHave {
        guard let lyrics else { return .unknown }
        return lyrics.lines.isEmpty ? .empty : .some
    }

    /// Dimmed (disabled, its tap nothing) only while off, and only when it is known it would open nothing: a button
    /// that is on can always be turned off, and while an answer is on its way it is enabled (lyricsDimmed).
    public static func dimmed(_ have: LyricsHave, on: Bool) -> Bool {
        !on && (have == .empty || have == .notKept)
    }

    // MARK: the clock (2.2)

    /// The web's clock (lyricsClock): the element's own time (`raw`) unless the reported position is further from it
    /// than a seek lands within - a seek on its way, and its target. The phone's clock is PlayerModel.clock(), which
    /// knows its seek on its way (Scrub.PendingSeek) and needs no guess; this is ported so the two apps' rules are one
    /// table.
    public static func clock(raw: Double, reported: Double) -> Double {
        abs(raw - reported) > Scrub.landedWithin ? reported : raw
    }

    /// Whether the view's clock runs - ten times a second on the phone - or stands, redrawing only on a seek: only
    /// while the lyrics show, the song plays, nothing is over them and the app is in view (clockRuns).
    public static func clockRuns(shows: Bool, playing: Bool, covered: Bool, visible: Bool) -> Bool {
        shows && playing && !covered && visible
    }

    // MARK: the lit line (2.3) and the dots (2.4)

    /// The lines whose time is the greatest not after `t`. None before the first timed line (an intro), and none at
    /// all in plain lyrics. The lines are sorted (the server's rule); a binary search (litRange).
    public static func litRange(_ lines: [LyricLine], at t: Double) -> LitRange? {
        guard let head = lines.first, head.time != nil else { return nil }
        var low = 0
        var high = lines.count - 1
        var found = -1
        while low <= high {
            let middle = (low + high) >> 1
            if let time = lines[middle].time, time <= t {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard found >= 0 else { return nil }
        let at = lines[found].time
        var first = found
        while first > 0, lines[first - 1].time == at { first -= 1 }
        return LitRange(first: first, last: found)
    }

    /// A line with words - every other line of synced lyrics is a break between verses (sung).
    public static func sung(_ line: LyricLine?) -> Bool {
        guard let line else { return false }
        return !line.text.isEmpty
    }

    /// The lines as the view draws them: an intro of `gapDotsSeconds` or more before the first line sung gets a break
    /// at 0, so it draws the dots as a break does - never a second one when the lyrics already start with a break.
    public static func withIntro(_ lines: [LyricLine]) -> [LyricLine] {
        guard let first = lines.first, let time = first.time, sung(first), time >= gapDotsSeconds else { return lines }
        return [LyricLine(time: 0, text: "")] + lines
    }

    /// The three dots of break `i` at `t`, 0 to 3: how many are lit - 0 when none are drawn. Only a break drawing them:
    /// the lit one, with the next line sung at least `gapDotsSeconds` after it (an outro draws none). The first lights
    /// at the break's start, the second a third of the way to the next line, the third two thirds (gapDots).
    public static func gapDots(_ lines: [LyricLine], _ i: Int, at t: Double) -> Int {
        guard lines.indices.contains(i), !sung(lines[i]), let start = lines[i].time else { return 0 }
        var next: Double?
        for j in (i + 1)..<lines.count where sung(lines[j]) && lines[j].time != nil {
            next = lines[j].time
            break
        }
        guard let next else { return 0 }
        let gap = next - start
        let into = t - start
        if gap < gapDotsSeconds || into < 0 || t >= next { return 0 }
        if into >= (gap * 2) / 3 { return 3 }
        if into >= gap / 3 { return 2 }
        return 1
    }

    /// The view's lit lines at `t` (over withIntro's lines) (litAt).
    public static func litAt(_ lines: [LyricLine], at t: Double) -> Lit {
        let range = litRange(lines, at: t)
        return Lit(range: range, dots: range.map { gapDots(lines, $0.first, at: t) } ?? 0)
    }

    // MARK: following (2.5)

    /// Where the lyrics scroll to put a line whose top is `lineTop` at the anchor of a view `height` tall (followTop).
    public static func followTop(_ lineTop: Double, height: Double) -> Double {
        JSNumber.max(0, lineTop - height * anchor)
    }

    /// The room after the last line, so it can be followed to the anchor too (endRoom).
    public static func endRoom(_ height: Double) -> Double {
        JSNumber.max(0, jsRound(height * (1 - anchor)))
    }

    /// Whether the view follows the song (follows): not while the listener's finger or VoiceOver's focus is on the
    /// lyrics (`focused` - the web's keyboard focus); else always, until the listener's own scroll holds it (`heldAt`,
    /// ms) - and then again `followAgainMs` after it, while the song plays. Paused, it stays where the listener put it.
    public static func follows(now: Double, heldAt: Double?, playing: Bool, focused: Bool = false) -> Bool {
        if focused { return false }
        guard let heldAt else { return true }
        return playing && now - heldAt >= followAgainMs
    }

    // MARK: asking (2.6)

    /// Whether the next song's lyrics are due: the song playing has `nextLyricsSeconds` or less left (and a known
    /// length) (asksAhead).
    public static func asksAhead(position: Double, duration: Double) -> Bool {
        duration > 0 && duration - position <= nextLyricsSeconds
    }

    /// JavaScript's Math.round: the nearest whole number, a half going up (toward +infinity).
    static func jsRound(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let down = value.rounded(.down)
        return value - down >= 0.5 ? down + 1 : down
    }
}

/// The answers kept in memory (keptLyrics, keepLyrics): by song id, the least recently used going first past `most`.
/// A JavaScript Map's insertion order, kept as an array of ids - fifty at most.
public struct LyricsKept<Value: Sendable>: Sendable {
    private var values: [String: Value] = [:]
    /// Least recently used first.
    public private(set) var order: [String] = []
    public let most: Int

    public init(most: Int = Lyrics.kept) {
        self.most = most
    }

    /// The answer kept for `id`, made the most recently used (keptLyrics).
    public mutating func take(_ id: String) -> Value? {
        guard let value = values[id] else { return nil }
        order.removeAll { $0 == id }
        order.append(id)
        return value
    }

    /// The answer kept for `id`, its place unchanged (the web's `kept.get`, `kept.has`).
    public func peek(_ id: String) -> Value? { values[id] }

    /// `value` kept for `id`, the least recently used going first past `most` (keepLyrics).
    public mutating func keep(_ id: String, _ value: Value) {
        order.removeAll { $0 == id }
        values[id] = value
        order.append(id)
        while order.count > most, let oldest = order.first {
            order.removeFirst()
            values[oldest] = nil
        }
    }

    public mutating func removeAll() {
        values = [:]
        order = []
    }
}

// MARK: - the phone's own (4.2-4.7)

extension Lyrics {
    /// What is known of the song playing's lyrics on the phone: its answer's, else - none in hand - not yet while
    /// deadwax can be reached (it is asked, or will be), or not kept on this phone while it can't (2.7's last row).
    public static func have(_ lyrics: SongLyrics?, online: Bool) -> LyricsHave {
        if lyrics != nil { return have(lyrics) }
        return online ? .unknown : .notKept
    }

    /// Lyrics on take the cover's place - unless the song has none, or none kept here offline: then the cover, the
    /// button still selected and named for it (2.7, 3.1).
    public static func shows(_ have: LyricsHave, on: Bool) -> Bool {
        on && have != .empty && have != .notKept
    }

    /// What the lyrics' place shows while lyrics are on (3.2, 4.2).
    public enum Face: Sendable, Equatable {
        /// the spinner, "Loading lyrics" - only with nothing in hand to draw
        case loading
        /// the failure in a listener's words and - unless the song is gone (a 404: nothing to try) - Try again
        case failed(tryAgain: Bool)
        /// synced lines: lit, followed, a tap plays from one
        case synced
        /// plain lines under the note, nothing lit, nothing moving on its own
        case plain
        /// none for this song: the cover
        case cover
    }

    /// What the lyrics' place shows for the song's answer in hand, an ask on its way, and the last ask's failure (nil
    /// when it didn't fail). An answer in hand is drawn over a failure - a revalidation that failed is no news.
    public static func face(_ lyrics: SongLyrics?, asking: Bool, failure: (any Error)?) -> Face {
        if let lyrics {
            if lyrics.lines.isEmpty { return .cover }
            return lyrics.synced ? .synced : .plain
        }
        if let failure, !asking { return .failed(tryAgain: ErrorWords.kind(of: failure) != .notFound) }
        return .loading
    }

    /// A failed ask as the face says it. A 404 is the song gone (its own sentence, no Try again) only when deadwax's
    /// lyrics route said so, in its words - a song Navidrome won't give the asker. FastAPI's bare "Not Found" (or no
    /// words at all) is a deadwax with no lyrics route - one older than 2.1.5, the phone's server being whatever it
    /// is - and is said as the lyrics not loading, never as the song gone: a song that plays isn't gone.
    public static func failure(_ error: any Error) -> any Error {
        guard let failure = error as? APIFailure, case .answered(let answer) = failure, answer.status == 404 else {
            return error
        }
        let words = (answer.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.isEmpty || words.caseInsensitiveCompare("Not Found") == .orderedSame else { return error }
        return APIFailure.other("deadwax has no lyrics route (\(answer.method) \(answer.path) answered 404) - lyrics need "
            + "deadwax 2.1.5 or later.")
    }

    // MARK: the look (4.3)

    /// Now Playing's backdrop - the cover blurred - under a black of this opacity (Phase 1's).
    public static let backdrop = 0.55
    /// ...darkened while lyrics show, so the dim lines read over the brightest cover: the backdrop at its brightest
    /// (a white sleeve) is then #4c4c4c, where a line at `dim` is 3.5:1 and the lit line 8.5:1.
    public static let backdropUnderLyrics = 0.7
    /// ...and with Increase Contrast: 5.5:1 at `dimIncreased`.
    public static let backdropUnderLyricsIncreased = 0.75
    /// Every line but the lit one: the primary colour at this opacity.
    public static let dim = 0.5
    public static let dimIncreased = 0.65

    /// The backdrop's black for lyrics showing or not, and Increase Contrast.
    public static func backdropDim(lyrics: Bool, increased: Bool) -> Double {
        guard lyrics else { return backdrop }
        return increased ? backdropUnderLyricsIncreased : backdropUnderLyrics
    }

    /// The dim lines' opacity, Increase Contrast or not.
    public static func lineDim(increased: Bool) -> Double {
        increased ? dimIncreased : dim
    }

    /// The soft edge at the lyrics' top and bottom, and the room above the first line, so it isn't under the fade.
    public static let edge = 24.0
    /// The space between two lines - drawn as each line's own padding, half either side, so the targets abut.
    public static let lineSpace = 14.0
    /// A break between verses: this tall, clear (the dots drawn inside it).
    public static let breakHeight = 14.0
    /// The dots' size.
    public static let dot = 8.0
}

/// Whether following is held, on the phone (2.5, 4.2, 4.4): the listener's finger scrolling the lyrics, VoiceOver's
/// focus on a line, and when the last of them let go (`heldAt`, ms) - the web's `heldAt` and `focused`, kept as one
/// value the view changes as they happen. `follows(now:playing:)` is Lyrics.follows over it.
public struct LyricsHold: Sendable, Equatable {
    /// When the listener last scrolled the lyrics or VoiceOver's focus left them (ms); nil while following.
    public private(set) var heldAt: Double?
    /// A finger is scrolling the lyrics (a scroll phase of the listener's, its fling included).
    public private(set) var scrolling = false
    /// VoiceOver's focus is on a line.
    public private(set) var focused = false

    public init() {}

    /// The scroll view's phases, as SwiftUI's ScrollPhase names them (iOS 18; on iOS 17 a drag stands in).
    public enum Phase: Sendable, Equatable {
        case idle, tracking, interacting, decelerating, animating
    }

    /// The scroll view's phase is now `phase`. A finger moving the lyrics (`interacting`) holds them, and its fling
    /// (`decelerating`) - or a finger put down on it (`tracking`) - still does; once the listener's scroll is over
    /// (`idle`, or following's own scroll, `animating`), the wait starts. A touch that never scrolled - a tap on a line,
    /// `tracking` then `idle` - holds nothing, and neither does following's own scroll.
    public mutating func phase(_ phase: Phase, at now: Double) {
        switch phase {
        case .interacting:
            scrolling = true
            heldAt = now
        case .decelerating, .tracking:
            if scrolling { heldAt = now }
        case .idle, .animating:
            if scrolling {
                scrolling = false
                heldAt = now
            }
        }
    }

    /// VoiceOver's focus moved: onto a line it holds for as long as it is there; off them, the wait starts.
    public mutating func focus(onLine: Bool, at now: Double) {
        if onLine {
            focused = true
        } else if focused {
            focused = false
            heldAt = now
        }
    }

    /// Following, now: a tap on a line, the song changing, the lyrics opened again, the wait run out while playing.
    public mutating func follow() {
        heldAt = nil
    }

    /// Whether the view follows the song now.
    public func follows(now: Double, playing: Bool) -> Bool {
        Lyrics.follows(now: now, heldAt: heldAt, playing: playing, focused: scrolling || focused)
    }

    /// How long until following may come back (ms), for the view's timer - nil while nothing waits: following
    /// already, or a finger or VoiceOver still on the lyrics.
    public func wait(now: Double) -> Double? {
        guard let heldAt, !scrolling, !focused else { return nil }
        return JSNumber.max(0, Lyrics.followAgainMs - (now - heldAt))
    }
}
