import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/player.json: player/MiniPlayer.tsx's label, its drawn line and its hairline, lib/playQueue.ts's
/// afterFailure, Now Playing's byline, Go to the album and clocks (NowPlaying.tsx, evaluated as written), and the
/// constants.
@Suite struct ScreenPlayerTests {
    let fixture = try! Web.load("player")

    @Test func theFixtureIsThere() {
        #expect(fixture["failures"].list.count == 120 && fixture["progress"].list.count == 70)
        expectMadeFrom(fixture, ["ui/src/player/MiniPlayer.tsx", "ui/src/lib/playQueue.ts afterFailure", "ui/src/player/NowPlaying.tsx the byline"])
    }

    @Test func theConstantsAreTheWebs() {
        let constants = fixture["constants"]
        #expect(PlayerWords.retryDelaySeconds * 1000 == constants["LOAD_RETRY_DELAY_MS"].num)
        #expect(PlayerWords.skipNoticeSeconds * 1000 == constants["SKIP_NOTICE_MS"].num)
        #expect(PlayerWords.dismissDistance == constants["DISMISS_PX"].num)
        #expect(PlayerWords.dragStartDistance == constants["DRAG_START_PX"].num)
        #expect(PlayerWords.mediaErrAborted == constants["MEDIA_ERR_ABORTED"].int)
        #expect(PlayerWords.mediaErrNetwork == constants["MEDIA_ERR_NETWORK"].int)
        #expect(PlayerWords.mediaErrDecode == constants["MEDIA_ERR_DECODE"].int)
        #expect(PlayerWords.mediaErrSrcNotSupported == constants["MEDIA_ERR_SRC_NOT_SUPPORTED"].int)
        #expect(PlayerWords.untitled == constants["untitled"].string)
        #expect(PlayerWords.scrubberName == constants["scrubName"].string)
    }

    /// info.sim.cjs's miniPlayerLabel, over titles and lines - "undefined" a line not sent.
    @Test func theMiniPlayersLabelIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["labels"].list {
            let line = row["line"].string == "undefined" ? nil : row["line"].string
            diffs.text("miniPlayerLabel(\(row["title"]), \(row["line"]))", PlayerWords.miniPlayerLabel(title: row["title"].string!, line: line), row["label"])
        }
        diffs.done()
    }

    /// The mini player drawn: its second line - the player's error, else the artist - and its name, and its buttons.
    @Test func theMiniPlayerDrawnIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["drawn"].list {
            let line = PlayerWords.secondLine(error: row["error"].string, artist: row["artist"].string)
            diffs.text("line(\(row["error"]), \(row["artist"]))", line ?? "", row["line"])
            diffs.text("label(\(row["error"]), \(row["artist"]))", PlayerWords.miniPlayerLabel(title: "Roads", line: line), row["label"])
            diffs.text("buttons", PlayerWords.playPause(playing: true), row["buttons"][0])
            diffs.text("buttons", PlayerWords.next, row["buttons"][1])
        }
        diffs.text("paused", PlayerWords.playPause(playing: false), fixture["pausedButtons"][0])
        diffs.done()
    }

    /// afterFailure, as [code, intendsToPlay, retried, next, action]. The web's answer carries where a skip goes, and
    /// stops at the queue's end; the phone's `.skip` leaves both to `skipFailed`. So `.skip` is replayed as the web's
    /// skip to the queue's next song (`next`, the fixture's nextIndex) - or, with none, its stop at the end.
    @Test func afterAFailureIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["failures"].list {
            let action = PlayerWords.afterFailure(code: row[0].int!, intendsToPlay: row[1].bool!, retried: row[2].bool!)
            let swift: String = switch action {
            case .retry: "retry"
            case .stop: "stop"
            case .skip: row[3].int.map { "skip \($0)" } ?? "stop"
            }
            let web = row[4]["kind"].string == "skip" ? "skip \(row[4]["index"].int!)" : row[4]["kind"].string ?? "?"
            diffs.check("afterFailure(\(row[0]), \(row[1]), \(row[2]), \(row[3]))", swift, web)
        }
        diffs.done()
    }

    /// MiniPlayer.tsx's Progress driven: the hairline's transform, from the position and the song's length.
    @Test func theMiniPlayersHairlineIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["progress"].list {
            let done = PlayerWords.progress(position: row["position"].num!, duration: row["duration"].num!)
            diffs.text("progress(\(row["position"]), \(row["duration"]))", "scaleX(\(JSNumber.string(done)))", row["transform"])
        }
        diffs.done()
        #expect(PlayerWords.progress(position: 150, duration: 300) == 0.5 && PlayerWords.progress(position: 450, duration: 300) == 1)
        #expect(PlayerWords.progress(position: 12, duration: 0) == 0 && PlayerWords.progress(position: 12, duration: .nan) == 0)
    }

    /// A failure's words by its kind: the engine's network, decode and not-audio failures as the web's media codes
    /// 2, 3 and 4 say them; a 401 as the element would see it (4); anything else as the element's no code.
    @Test func aFailuresWordsComeFromItsKind() {
        #expect(PlayerWords.words(.network) == "The connection dropped while this song was loading")
        #expect(PlayerWords.words(.decode) == "This device couldn't play this song's audio")
        #expect(PlayerWords.words(.unsupported) == "Couldn't play this song - it didn't come as audio this device can play")
        #expect(PlayerWords.words(.signedOut) == PlayerWords.words(.unsupported))
        #expect(PlayerWords.words(.other) == "Couldn't play this song")
        #expect(PlayerWords.skipped(title: "Glory Box", failure: .decode) == "Skipped \"Glory Box\" - this device couldn't play its audio")
        #expect(PlayerWords.skipped(title: nil, failure: .network) == "Skipped \"a song\" - it wouldn't play")
        //? the engine's kinds, by their raw values (DeadwaxAudio's AudioFailure.Kind)
        #expect(PlayerWords.Failure.allCases.map(\.rawValue) == ["network", "decode", "unsupported", "signedOut", "other"])
        //? a load failure is asked for again once; a decode failure, or one asked again already, goes on
        #expect(PlayerWords.afterFailure(.network, intendsToPlay: true, retried: false) == .retry)
        #expect(PlayerWords.afterFailure(.unsupported, intendsToPlay: true, retried: true) == .skip)
        #expect(PlayerWords.afterFailure(.decode, intendsToPlay: true, retried: false) == .skip)
        #expect(PlayerWords.afterFailure(.signedOut, intendsToPlay: true, retried: false) == .retry)
        #expect(PlayerWords.afterFailure(.other, intendsToPlay: false, retried: false) == .stop)
    }

    @Test func nowPlayingsBylineIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["bylines"].list {
            let byline = PlayerWords.byline(artist: row["artist"].string, album: row["album"].string)
            diffs.text("byline(\(row["artist"]), \(row["album"]))", byline, row["byline"])
            diffs.text("goTo(\(row["artist"]), \(row["album"]))", PlayerWords.goToAlbum(byline), row["goTo"])
        }
        diffs.done()
    }

    @Test func nowPlayingsClocksAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["scrub"].list {
            let shown = row["shown"].num!, length = row["length"].num!
            diffs.text("value(\(row["shown"]), \(row["length"]))", PlayerWords.scrubberValue(shown: shown, length: length), row["value"])
            diffs.text("elapsed(\(row["shown"]))", PlayerWords.elapsed(shown: shown), row["elapsed"])
            diffs.text("remaining(\(row["shown"]), \(row["length"]))", PlayerWords.remaining(shown: shown, length: length), row["remaining"])
        }
        diffs.done()
    }
}
