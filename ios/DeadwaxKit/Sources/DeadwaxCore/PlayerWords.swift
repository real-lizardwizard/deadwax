import Foundation

/// What the mini player and Now Playing say, and what the player does with a song that won't play - the web app's
/// ui/src/player/MiniPlayer.tsx (miniPlayerLabel, its second line), player/NowPlaying.tsx (the byline, Go to the
/// album, the scrubber's name and value, the clocks, the sheet's drag), lib/playQueue.ts afterFailure and
/// player/usePlayer.ts's words for a failure, ported line for line. Held to what the TypeScript answers:
/// Tests/DeadwaxCoreTests/Fixtures/screens/player.json, written by ios/scripts/export-screen-vectors.cjs.
///
/// A failure's words come from what KIND of failure it was (`Failure`, the audio engine's AudioFailure.Kind by its
/// raw value), as the web's come from the media element's error code - never from the engine's own description,
/// which is Debug's "Last failure" and nobody else's.
public enum PlayerWords {
    // MARK: the mini player

    /// The mini player's name for VoiceOver: "Now playing: Roads, Portishead - open" - no line, no ", ".
    public static func miniPlayerLabel(title: String, line: String?) -> String {
        if let line, !line.isEmpty { return "Now playing: \(title), \(line) - open" }
        return "Now playing: \(title) - open"
    }

    /// The mini player's second line, and Now Playing's line over the title: the player's failure words (a skipped
    /// song's notice included) when there are any - "" included, as the web's `??` keeps it - else the song's artist.
    public static func secondLine(error: String?, artist: String?) -> String? {
        error ?? artist
    }

    /// Play and Pause's name: what pressing it does.
    public static func playPause(playing: Bool) -> String { playing ? "Pause" : "Play" }
    /// Next's name.
    public static let next = "Next"

    // MARK: Now Playing

    /// Under the title: "Portishead — Dummy" (an em dash), the two there are.
    public static func byline(artist: String?, album: String?) -> String {
        [artist, album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// The byline's button, which opens the album: "Go to the album: Portishead — Dummy".
    public static func goToAlbum(_ byline: String) -> String { "Go to the album: \(byline)" }

    /// The scrubber's name.
    public static let scrubberName = "Position in the song"

    /// The scrubber's value: "0:12 of 5:00".
    public static func scrubberValue(shown: Double, length: Double) -> String {
        "\(Format.clock(shown)) of \(Format.clock(length))"
    }

    /// The clock under the bar's left end: how far in.
    public static func elapsed(shown: Double) -> String { Format.clock(shown) }

    /// The clock under its right end: how much is left, "-4:47".
    public static func remaining(shown: Double, length: Double) -> String { "-" + Format.clock(length - shown) }

    /// A drag down this far (points) closes Now Playing.
    public static let dismissDistance = 110.0
    /// A drag down is the sheet's only once it has gone this far - a tap or a small wobble isn't one.
    public static let dragStartDistance = 6.0

    // MARK: a song that won't play

    /// What kind of failure it was - the audio engine's AudioFailure.Kind, by its raw value.
    public enum Failure: String, Sendable, CaseIterable {
        /// The connection dropped, or the song stopped arriving.
        case network
        /// The bytes came, and iOS couldn't decode them.
        case decode
        /// What came isn't audio iOS can play (no audio found in it, a kind of file it can't decode, or an answer that
        /// wasn't the song).
        case unsupported
        /// deadwax said this phone isn't signed in (401).
        case signedOut
        /// Anything else.
        case other
    }

    /// The media element's error code the web would have for it (playQueue.ts MEDIA_ERR_*): network 2, decode 3, and
    /// 4 for what didn't come as audio - which is also what a refused request looks like from the element, a 401
    /// included (the sign-in comes up over the app from the 401 itself, `SignInRules`) - and 0 for anything else.
    public static func code(_ failure: Failure) -> Int {
        switch failure {
        case .network: return mediaErrNetwork
        case .decode: return mediaErrDecode
        case .unsupported, .signedOut: return mediaErrSrcNotSupported
        case .other: return 0
        }
    }

    public static let mediaErrAborted = 1
    public static let mediaErrNetwork = 2
    public static let mediaErrDecode = 3
    public static let mediaErrSrcNotSupported = 4

    /// A song that wouldn't play, in a listener's words (usePlayer.ts describeMediaError) - shown as they are, with no
    /// full stop, in the song's second line.
    public static func words(_ failure: Failure) -> String { ErrorWords.media(code(failure)) }

    /// Why the song before this one was passed over, named - shown in the NEXT song's second line for `skipNotice`
    /// seconds (usePlayer.ts skipNotice); "a song" when the failed one had no title.
    public static func skipped(title: String?, failure: Failure) -> String {
        ErrorWords.skipped(title: title ?? untitled, code: code(failure))
    }

    /// A skipped song with no title, as the notice names it.
    public static let untitled = "a song"
    /// How long a skip's notice stands where the artist's name goes (SKIP_NOTICE_MS).
    public static let skipNoticeSeconds = 5.0
    /// How long to wait before asking again for a song that failed to load (LOAD_RETRY_DELAY_MS): long enough for a
    /// connection that dropped at a change of song to come back, short enough to read as a hiccup.
    public static let retryDelaySeconds = 1.5

    /// What the player does about a song that won't play (playQueue.ts FailureAction).
    public enum AfterFailure: Sendable, Equatable {
        /// ask again, once, after `retryDelaySeconds`, from where it stopped - the same listen
        case retry
        /// on to this song of the queue
        case skip(Int)
        /// nothing more: the words stay
        case stop
    }

    /// afterFailure: stopped when the listener didn't mean it to play (paused) or the failure was an abort; a load
    /// failure (network, or not audio) asked for again once; otherwise on to `next` - the queue's next song, past any
    /// Repeat One copies of the failed one (`nil`: none) - or stopped at the queue's end.
    public static func afterFailure(code: Int, intendsToPlay: Bool, retried: Bool, next: Int?) -> AfterFailure {
        if !intendsToPlay || code == mediaErrAborted { return .stop }
        let loadFailure = code == mediaErrNetwork || code == mediaErrSrcNotSupported
        if loadFailure && !retried { return .retry }
        return next.map(AfterFailure.skip) ?? .stop
    }

    /// The same, by the failure's kind.
    public static func afterFailure(_ failure: Failure, intendsToPlay: Bool, retried: Bool, next: Int?) -> AfterFailure {
        afterFailure(code: code(failure), intendsToPlay: intendsToPlay, retried: retried, next: next)
    }

    /// playQueue.ts nextIndex: the song after `index`, or nil past the last.
    public static func nextIndex(index: Int, count: Int) -> Int? {
        index + 1 < count ? index + 1 : nil
    }
}
