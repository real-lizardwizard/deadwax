// The turntable's screen rules (notes/ios-specs/turntable.md 2.1-2.12, 4.6, 6.1, 6.2), on Linux: the plinth's fit, the
// face's parts, the song as the deck has it, the states of 2.8, the deck engine's run rule, the two settings, the look
// button and the lyrics, and Debug's Turntable section - and the disc's route.
@testable import DeadwaxCore
import Foundation
import Testing

struct TurntableScreenTests {
    // MARK: the plinth and the face (2.2, 2.4, 2.5)

    @Test func thePlinthFitsTheRoomBothWaysAtMost440() {
        // a 393 pt phone: the room 345 wide (Now Playing's 24 a side), tall enough: 345 - 24 = 321 (2.2)
        #expect(TurntableFit.plinthWidth(roomWidth: 345, roomHeight: 500) == 321)
        // held by the height: 368 units tall for 372 wide, after 24 above and 12 below
        let held = TurntableFit.plinthWidth(roomWidth: 345, roomHeight: 323)
        #expect(abs(held - (323 - 36) * 372 / 368) < 0.001)
        // a big room: 440 at most
        #expect(TurntableFit.plinthWidth(roomWidth: 900, roomHeight: 900) == 440)
        // no room: nothing, never negative
        #expect(TurntableFit.plinthWidth(roomWidth: 10, roomHeight: 10) == 0)
        #expect(TurntableFit.layout(roomWidth: 345, roomHeight: 500).width == 321)
    }

    @Test func theFacesPartsAreTheStylesheets() {
        let layout = TurntableLayout(width: 372)
        let parts = TurntableFaceParts(layout)
        // the record 320 across at full size: the cover 124 across (38.75%), its ring 2 pt outside it - 62 to 64,
        // the grooves' inner edge - and the spindle 20 across (6.25%), its ring 3 pt outside
        #expect(abs(parts.record - 160) < 1e-9)
        #expect(abs(parts.label - 62) < 1e-9 && abs(parts.labelOuter - 64) < 1e-9)
        #expect(abs(parts.spindle - 10) < 1e-9 && abs(parts.spindleOuter - 13) < 1e-9)
        // the label's and the spindle's frames centred on the record's
        let record = layout.record, label = layout.label, spindle = layout.spindle
        #expect(abs((label.left + label.width / 2) - (record.left + record.width / 2)) < 1e-9)
        #expect(abs((spindle.top + spindle.height / 2) - (record.top + record.height / 2)) < 1e-9)
        #expect(abs(label.width - 124) < 1e-9 && abs(spindle.width - 20) < 1e-9)
        // the rings are points, not units: on a 284 pt plinth still 2 and 3
        let small = TurntableFaceParts(TurntableLayout(width: 284))
        #expect(abs(small.labelOuter - small.label - 2) < 1e-9 && abs(small.spindleOuter - small.spindle - 3) < 1e-9)
    }

    @Test func theHandleIsATapAtLeastButNeverMoreThan30PercentOfThePlinth() {
        // 56 units on a 321 pt plinth is 48.3 pt: more than 44
        #expect(abs(TurntableLayout(width: 321).handleSize - 56 * 321 / 372) < 1e-9)
        // on a 200 pt plinth 56 units is 30 pt: the tap's 44
        #expect(TurntableLayout(width: 200).handleSize == 44)
        // on a 100 pt plinth 44 is more than its 30%: 30
        #expect(abs(TurntableLayout(width: 100).handleSize - 30) < 1e-9)
    }

    @Test func theSheenIsBrightestAt48Degrees() {
        #expect(TurntableFace.sheenBrightest == 48)
        let brightest = TurntableFace.sheenStops.max { $0.alpha < $1.alpha }
        #expect(brightest?.degrees == 28 && brightest?.alpha == 0.07)
    }

    // MARK: the song (3.4)

    @Test func theSongsKindIsTheWebs() {
        #expect(DeckSong(id: "a", length: 240, suffix: "flac", contentType: "audio/flac") == DeckSong(id: "a", length: 240, flac: true, kind: "FLAC"))
        #expect(DeckSong(id: "a", length: 1, suffix: "mp3", contentType: nil).kind == "MP3")
        #expect(!DeckSong(id: "a", length: 1, suffix: "mp3", contentType: nil).flac)
        // no suffix: the type, its x- dropped
        let typed = DeckSong(id: "a", length: 1, suffix: nil, contentType: "audio/x-flac; charset=x")
        #expect(typed.kind == "FLAC" && typed.flac)
        #expect(DeckSong(id: "a", length: 1, suffix: "", contentType: "video/mp4").kind == "")
    }

    // MARK: the states of 2.8

    @Test func soundIsReadyOnlyPreparedAndAllowed() {
        #expect(TurntableScreen.soundReady(DeckEngineState(prepared: true)))
        #expect(!TurntableScreen.soundReady(DeckEngineState(prepared: false)))
        #expect(!TurntableScreen.soundReady(DeckEngineState(prepared: true, failure: "no output")))
        #expect(!TurntableScreen.soundReady(DeckEngineState(prepared: true, airPlay: true)))
        #expect(!TurntableScreen.soundReady(DeckEngineState(prepared: true, interrupted: true)))
    }

    @Test func theSilentLineIsAirPlaysFirstThenNoSoundThenNotAFLAC() {
        let ready = DeckEngineState(prepared: true)
        // not turned silently: nothing
        #expect(TurntableScreen.silentLine(turnedSilent: false, flac: false, engine: ready, error: nil) == nil)
        // a FLAC on a phone that can sound: nothing to say (a window not in yet is a silence that passes)
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: true, engine: ready, error: nil) == nil)
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: false, engine: ready, error: nil) == TurntableWords.notFlac)
        let failed = DeckEngineState(prepared: false, failure: "the output refused")
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: true, engine: failed, error: nil) == TurntableWords.noAudio)
        let airPlay = DeckEngineState(prepared: false, airPlay: true)
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: false, engine: airPlay, error: nil) == TurntableWords.airPlay)
        // a failure's line says more: the silent line waits
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: false, engine: ready, error: "Couldn't play this song") == nil)
        #expect(TurntableScreen.silentLine(turnedSilent: true, flac: false, engine: ready, error: "") == TurntableWords.notFlac)
    }

    @Test func framesRunOnlyWhenAskedShowingActiveAndMotionAllowed() {
        #expect(TurntableScreen.framesRun(asked: true, showing: true, active: true, reduced: false, held: false))
        #expect(!TurntableScreen.framesRun(asked: false, showing: true, active: true, reduced: false, held: true))
        #expect(!TurntableScreen.framesRun(asked: true, showing: false, active: true, reduced: false, held: true))
        #expect(!TurntableScreen.framesRun(asked: true, showing: true, active: false, reduced: false, held: true))
        #expect(!TurntableScreen.framesRun(asked: true, showing: true, active: true, reduced: true, held: false))
        // a held record under Reduce Motion: the web's loop still asks, for the time line and the hand's frames
        #expect(TurntableScreen.framesRun(asked: true, showing: true, active: true, reduced: true, held: true))
    }

    /// 4.6, question 13 C.
    @Test func theDeckEngineRunsAsQuestion13Says() {
        let ready = DeckEngineState(prepared: true)
        func want(showing: Bool = true, playing: Bool = false, sounding: Bool = false, quietFor: Double? = nil, pausedFor: Double? = nil,
                  active: Bool = true, engine: DeckEngineState = ready) -> DeckEngineWant {
            TurntableScreen.engineWant(showing: showing, songPlaying: playing, sounding: sounding, quietFor: quietFor, pausedFor: pausedFor,
                                       active: active, engine: engine)
        }
        // showing and playing: running, so the press that matters most finds it so
        #expect(want(playing: true) == .running)
        // sounding: running whatever the song does, showing or not (a coast that outlives Now Playing)
        #expect(want(sounding: true) == .running)
        #expect(want(showing: false, sounding: true) == .running)
        // showing, paused, quiet for long: resting
        #expect(want(quietFor: 10, pausedFor: 20) == .resting)
        // the record's sound ended 0.2 s ago, after the song stopped (a wind-down): held to 0.5 s
        #expect(want(quietFor: 0.2, pausedFor: 1.2) == .running)
        #expect(want(quietFor: 0.6, pausedFor: 1.6) == .resting)
        // the song stopped with the record quiet (the lock screen's pause): at once
        #expect(want(quietFor: 0.3, pausedFor: 0.1) == .resting)
        #expect(want(quietFor: 0.3, pausedFor: 0.3) == .resting)
        // playing but not showing, the sound just ended: held 0.5 s, then resting
        #expect(want(showing: false, playing: true, quietFor: 0.1) == .running)
        #expect(want(showing: false, playing: true, quietFor: 0.5) == .resting)
        // the scene not active, or an interruption: resting, even mid-sound
        #expect(want(playing: true, sounding: true, active: false) == .resting)
        #expect(want(playing: true, engine: DeckEngineState(prepared: true, interrupted: true)) == .resting)
        // AirPlay, or a start that failed: not prepared at all
        #expect(want(playing: true, engine: DeckEngineState(prepared: false, airPlay: true)) == .off)
        #expect(want(sounding: true, engine: DeckEngineState(prepared: false, failure: "no")) == .off)
    }

    // MARK: the settings and the look (6.1, 2.1)

    @Test func theSettingsAreTheWebsKeysAndDefaults() {
        #expect(TurntableSettings.opensAsKey == "deadwax-player-opens-as" && TurntableSettings.windDownKey == "deadwax-player-wind-down")
        #expect(TurntableSettings.opensAs("turntable") == .turntable)
        for other in [nil, "", "cover", "Turntable", "record"] as [String?] { #expect(TurntableSettings.opensAs(other) == .cover) }
        #expect(TurntableSettings.windDown(nil) && TurntableSettings.windDown("on") && TurntableSettings.windDown("OFF"))
        #expect(!TurntableSettings.windDown("off"))
        #expect(TurntableSettings.stored(.turntable) == "turntable" && TurntableSettings.stored(windDown: false) == "off")
        #expect(TurntableSettings.windDown(TurntableSettings.stored(windDown: true)))
    }

    @Test func theLookButtonAndTheLyricsAreNowPlayingsRules() {
        // the turntable shows only with the lyrics off
        #expect(TurntableSettings.showsTurntable(.turntable, lyricsOn: false))
        #expect(!TurntableSettings.showsTurntable(.turntable, lyricsOn: true))
        #expect(!TurntableSettings.showsTurntable(.cover, lyricsOn: false))
        // the button: the other look, the lyrics off, the deck woken only going to the turntable
        let toTurntable = TurntableSettings.lookTapped(.cover, lyricsOn: true)
        #expect(toTurntable.look == .turntable && toTurntable.lyricsOff && toTurntable.wake)
        let toCover = TurntableSettings.lookTapped(.turntable, lyricsOn: false)
        #expect(toCover.look == .cover && !toCover.lyricsOff && !toCover.wake)
        // the lyrics off over the turntable's look: back to the turntable, woken
        let back = TurntableSettings.lyricsTapped(.turntable, lyricsOn: true)
        #expect(!back.lyricsOn && back.wake)
        #expect(!TurntableSettings.lyricsTapped(.cover, lyricsOn: true).wake && TurntableSettings.lyricsTapped(.turntable, lyricsOn: false).lyricsOn)
    }

    // MARK: Debug (6.2)

    static func report(_ engine: DeckEngineState, window: DeckReport.Window? = nil, refused: String? = nil) -> DeckReport {
        TurntableDebugRows.phoneReport(engine: engine, window: window, loading: false, refused: refused, failed: nil, fetched: 0,
                                       lastFetchAt: 0, ioBuffer: 1_024.0 / 48_000, outputLatency: 0.0081, health: DeckReport.DeckHealth())
    }

    @Test func theTurntableSoundRowSaysThePhonesStates() {
        func row(_ report: DeckReport?) -> String { TurntableDebugRows.turntableRow(report).value }
        #expect(row(nil) == "Off: the turntable isn't showing")
        #expect(row(Self.report(DeckEngineState(prepared: false))) == "Off: still starting - a press scrubs silently until it has")
        #expect(row(Self.report(DeckEngineState(prepared: false, failure: "the output refused (-10851)")))
                == "Off: the output refused (-10851)")
        #expect(row(Self.report(DeckEngineState(prepared: false, airPlay: true))) == "Off: the record makes no sound over AirPlay")
        #expect(row(Self.report(DeckEngineState(prepared: true), refused: "it isn't a FLAC file (it is MP3)"))
                == "Off: it isn't a FLAC file (it is MP3)")
        let window = DeckReport.Window(start: 42, end: 82, kind: "FLAC", decodedAt: 48_000, bytes: 1_400_000)
        #expect(row(Self.report(DeckEngineState(prepared: true), window: window)) == "Ready: 0:42-1:22, FLAC, decoded at 48 kHz")
        #expect(row(Self.report(DeckEngineState(prepared: true))).hasPrefix("Off: no window yet"))
    }

    @Test func theSectionIsInSixPointTwosOrderWithThePhonesVoice() {
        var facts = DeckPhoneFacts(report: Self.report(DeckEngineState(prepared: true),
                                                       window: DeckReport.Window(start: 0, end: 40, kind: "FLAC", decodedAt: 44_100, bytes: 1)))
        facts.from = .download
        facts.clock = (0.0239, 0.0246, true)
        facts.handover = DeckPhoneFacts.Handover(lead: 0.17, predicted: 0.29, took: 0.31, timerLate: 0.002, seam: 0.018)
        facts.positionRead = 0.0012
        facts.windowMade = (0.21, 40, 44_100)
        facts.dropped = 3
        facts.touches = (238, 120)
        facts.slowStarts = (2, 0.018)
        let rows = TurntableDebugRows.phoneRows(facts)
        #expect(rows.map(\.label) == ["Turntable sound", "Window from", "Voice", "Clock step", "Clock", "Turntable timing", "Handover",
                                      "Position read in", "Window made in", "Messages dropped", "Limiter", "Frames under a hand",
                                      "Touches under a hand", "Delay behind the hand", "Slow starts"])
        let value = { (label: String) -> String in rows.first { $0.label == label }?.value ?? "" }
        #expect(value("Voice") == "On its own audio thread (an AVAudioSourceNode)")
        #expect(value("Window from") == "This phone's download")
        #expect(value("Clock step") == "21.3 ms at a time")
        #expect(value("Clock") == "The record's clock runs 23.9 ms behind the render's time stamps; the largest lead under the last hand 24.6 ms")
        #expect(value("Handover") == "Resumed 0.17 s early for a start of 0.29 s (it took 0.31 s, the timer 2 ms late); "
                + "the song came in 18 ms after the record's sound was there")
        #expect(value("Position read in") == "1.2 ms at worst during the last handover")
        #expect(value("Messages dropped") == "3 of the record's messages were dropped")
        #expect(value("Touches under a hand") == "238 a second, from 120 events a second")
        #expect(value("Slow starts") == "2 presses whose sound started after its delay, the worst by 18 ms")
        #expect(value("Delay behind the hand") == "121.5 ms behind the hand by design (on its own thread), then what this device's audio adds "
                + "- it says base 21.3 ms, output 8.1 ms")
        // not showing: the one row
        #expect(TurntableDebugRows.phoneRows(DeckPhoneFacts(report: nil)).map(\.label) == ["Turntable sound"])
        // the phone's new rows only when they have something
        #expect(TurntableDebugRows.slowStartsRow(count: 0, worst: 0) == nil)
        #expect(TurntableDebugRows.slowStartsRow(count: 1, worst: 0.0204)?.value == "1 press whose sound started after its delay, by 20 ms")
        #expect(TurntableDebugRows.windowFromRow(.offline).value == "Off: " + TurntableWords.offline)
        #expect(TurntableDebugRows.handoverRow(DeckPhoneFacts.Handover(lead: 0, predicted: 0.3)).value
                == "Resumed at the let-go for a start of 0.30 s")
    }

    // MARK: the disc (2.3)

    @Test func theDiscsArtIsAskedOfDeadwaxAndA404IsNone() async throws {
        let (deadwax, transport) = client(session: "abc")
        let request = deadwax.discArtRequest(albumID: "al 1", disc: 2)
        #expect(request.url.path == "/deadwax/library/disc_art/navidrome")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "album", value: "al 1")) && query.contains(URLQueryItem(name: "disc", value: "2")))
        #expect(request.headers["Accept"] == "image/*")
        #expect(deadwax.discArtRequest(albumID: "a", disc: 0).url.query?.contains("disc=1") == true)
        transport.answer("/deadwax/library/disc_art/navidrome", 404, #"{"detail":"No CD art"}"#)
        #expect(try await deadwax.discArt(albumID: "a", disc: 1) == nil)
        transport.answer("/deadwax/library/disc_art/navidrome", 200, "PNG")
        #expect(try await deadwax.discArt(albumID: "a", disc: 1) == Data("PNG".utf8))
        #expect(TurntableGeometry.playingDisc([("s1", 1), ("s2", 2)], "s2") == 2)
    }
}
