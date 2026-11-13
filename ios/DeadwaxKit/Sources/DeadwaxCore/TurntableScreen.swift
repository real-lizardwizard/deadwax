import Foundation

// The turntable on Now Playing, as rules the screen and the DeckController read (notes/ios-specs/turntable.md 2.1-2.12,
// 4.6, 6.1, 6.2): the face's numbers, the plinth's fit, the states of 2.8 as a function of what the deck engine and
// the song say, when the deck engine runs, the two settings, and Debug's Turntable section. Pure: held on Linux by
// TurntableScreenTests, the face's numbers to app.css by tests/test_ios_turntable_face.py.

/// The face and the plinth in points - app.css's and theme.css's own numbers (2.1, 2.2, 2.4, 2.5), where the stage's
/// units (TurntableGeometry) aren't: CSS draws the grooves, the rings and the plinth's room in px, a point on an
/// iPhone. tests/test_ios_turntable_face.py reads each from the stylesheets.
public enum TurntableFace {
    /// `.app-tt-label`: the label, round, 38.75% of the face's width, 30.625% in - centred
    public static let labelShare = 0.3875
    /// `--app-tt-label-ring`: its ring, inside that share - player.css makes every box border-box (`*, *::before,
    /// *::after`), so the border is drawn inside the 38.75% and the cover is that less twice the ring
    public static let labelRing = 2.0
    /// `.app-tt-spindle`: 6.25% of the face, 46.875% in - centred
    public static let spindleShare = 0.0625
    /// `--app-tt-spindle-ring`: inside that share, as the label's
    public static let spindleRing = 3.0
    /// `--dw-tt-grooves`: a repeating radial gradient, a ring every 4 pt - clear to 2, black at 0.2 at 3, clear at 4
    public static let groovePeriod = 4.0
    public static let grooveStops: [(at: Double, alpha: Double)] = [(0, 0), (2, 0), (3, 0.2), (4, 0)]
    /// `--dw-tt-sheen`: a conic gradient from 20 deg (clockwise of 12 o'clock), white at each stop's alpha
    public static let sheenFrom = 20.0
    public static let sheenStops: [(degrees: Double, alpha: Double)] = [(0, 0), (28, 0.07), (56, 0), (180, 0), (208, 0.05), (236, 0)]
    /// where the sheen is brightest, clockwise of the top: its from and its brightest stop (2.4's check)
    public static var sheenBrightest: Double { sheenFrom + 28 }
    /// `--app-tt-handle-edge`, and `--app-tt-handle-cap`: the handle's ring and the most of the plinth it may be
    public static let handleEdge = 1.0
    public static let handleCap = 0.30
    /// `--app-tt-handle-edge`'s dashes: the web's `dashed` 1 px border, which WebKit draws 3 on, 3 off
    public static let handleDash = 3.0
    /// `--pl-hit`
    public static let hit = 44.0
    /// `--app-tt-max`, `--app-tt-pad`, `--app-tt-clear`: the plinth at its widest; round it; above it
    public static let plinthMax = 440.0
    public static let pad = 12.0
    public static let clear = 24.0
    /// `--dw-radius-card`, the plinth's corners; `--dw-hairline`, its edge; `--dw-highlight`, its top line
    public static let plinthRadius = 6.0
    public static let hairline = 1.0
    public static let highlight = 1.0
    /// `--app-look-face`, `--app-look-icon`, `--dw-radius-control`: the look button
    public static let lookFace = 36.0
    public static let lookIcon = 20.0
    public static let lookRadius = 4.0
    /// RecordIcon and SquareIcon (player/icons.tsx:126, :133), on a 24 grid
    public static let recordIconRings = (outer: 8.5, inner: 2.5)
    public static let squareIcon = (side: 15.0, radius: 2.0)
    /// the icons' stroke at the glyph's 20 pt: icons.tsx `thin()`'s 1.8 on its 24 grid
    public static let iconStroke = 1.5
    /// `--app-tt-time-gap`: the album line to the time line
    public static let timeGap = 6.0
    /// `--app-speed-chip`, `--app-speed-chip-pad`: the speed's chip on the cover, drawn in a tap's target (5.1)
    public static let chipFace = 28.0
    public static let chipPad = 8.0
}

/// The plinth on Now Playing (2.2): as big as fits the cover's room both ways, at most 440 pt wide - the room less 12
/// pt round it and 24 pt clear above.
public enum TurntableFit {
    /// The plinth's width for a room of `width` by `height` points (the cover's room inside Now Playing's padding).
    public static func plinthWidth(roomWidth: Double, roomHeight: Double) -> Double {
        let stage = TurntableGeometry.stage
        let across = Swift.max(0, roomWidth - 2 * TurntableFace.pad)
        let down = Swift.max(0, roomHeight - TurntableFace.clear - TurntableFace.pad)
        let scale = Swift.min(across / stage.width, down / stage.height, TurntableFace.plinthMax / stage.width)
        return (scale * stage.width * 1_000).rounded(.down) / 1_000
    }

    /// The layout for that room.
    public static func layout(roomWidth: Double, roomHeight: Double) -> TurntableLayout {
        TurntableLayout(width: plinthWidth(roomWidth: roomWidth, roomHeight: roomHeight))
    }
}

/// The face's parts as the layers draw them: each a circle about the record's centre, radii in points. The web's
/// boxes are border-box (player.css's `*, *::before, *::after`, linked before app.css), so each ring is inside its
/// share of the face: the label's outer edge is 38.75% of the face across and the cover is that less twice its 2 pt
/// ring, the spindle's 6.25% less twice its 3 pt.
public struct TurntableFaceParts: Equatable, Sendable {
    /// the record's radius
    public var record: Double
    /// the cover inside the label's ring, and the ring's outer edge (the label's share)
    public var label: Double
    public var labelOuter: Double
    /// the spindle inside its ring, and the ring's outer edge (the spindle's share)
    public var spindle: Double
    public var spindleOuter: Double

    public init(_ layout: TurntableLayout) {
        let face = layout.record.width
        record = face / 2
        labelOuter = face * TurntableFace.labelShare / 2
        label = Swift.max(0, labelOuter - TurntableFace.labelRing)
        spindleOuter = face * TurntableFace.spindleShare / 2
        spindle = Swift.max(0, spindleOuter - TurntableFace.spindleRing)
    }
}

/// The song as the deck has it (3.4): its id, its length, whether it is a FLAC, its kind in capitals - the web's
/// `kindOf` (Turntable.tsx:46) and `isFlac` (streamWrap.ts:54).
extension DeckSong {
    public init(id: String, length: Double, suffix: String?, contentType: String?) {
        let kind: String
        if let suffix, !suffix.isEmpty {
            kind = suffix.uppercased()
        } else {
            let type = WebText.trim(String((contentType ?? "").split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")).lowercased()
            if type.hasPrefix("audio/") {
                var rest = String(type.dropFirst("audio/".count))
                if rest.hasPrefix("x-") { rest = String(rest.dropFirst(2)) }
                kind = rest.uppercased()
            } else {
                kind = ""
            }
        }
        self.init(id: id, length: length, flac: Loudness.isFlac(suffix: suffix, contentType: contentType), kind: kind)
    }
}

/// Where the deck engine stands, as the screen and the deck's rules need it (3.3, 4.6, 2.8).
public struct DeckEngineState: Equatable, Sendable {
    /// made and prepared (its voice state made and warmed), on this route
    public var prepared = false
    /// its start threw: the engine's own words
    public var failure: String?
    /// the route has an AirPlay output
    public var airPlay = false
    /// an audio interruption (a call, Siri) hasn't ended
    public var interrupted = false
    public init(prepared: Bool = false, failure: String? = nil, airPlay: Bool = false, interrupted: Bool = false) {
        self.prepared = prepared
        self.failure = failure
        self.airPlay = airPlay
        self.interrupted = interrupted
    }
}

/// The deck engine's failed start (4.6): its words, kept so the record isn't asked to sound on a phone that couldn't
/// start it - `engineWant` is `.off` and a press scrubs silently while they stand - but only until something that could
/// change the answer. A route change, the deck made again and an interruption's end forget it, and the next want
/// starts the engine again; a press (or another gesture the sound may start from) forgets it once the last failure is
/// `retryGap` old. Nothing else does: no post or frame starts a failed engine, so a phone that truly can't make the
/// sound is asked again once a press at most, never at every frame.
public struct DeckStartFailure: Equatable, Sendable {
    /// The least time from a failed start to the press that may try again.
    public static let retryGap = 2.0

    /// the engine's own words, while the failure stands
    public private(set) var words: String?
    /// when it failed, seconds
    public private(set) var at = -Double.infinity

    public init() {}

    /// The start threw, at `now`.
    public mutating func failed(_ words: String, at now: Double) {
        self.words = words
        at = now
    }

    /// The start succeeded.
    public mutating func started() {
        words = nil
    }

    /// A route change, the deck made, an interruption ended: the answer may be different now.
    public mutating func forget() {
        words = nil
    }

    /// A press at `now`: the failure forgotten when it is `retryGap` old - true when it was, and the start may be tried.
    public mutating func pressed(at now: Double) -> Bool {
        guard words != nil, now - at >= Self.retryGap else { return false }
        words = nil
        return true
    }
}

/// What the deck engine should be doing (4.6).
public enum DeckEngineWant: Equatable, Sendable {
    /// not made or let go: the turntable doesn't show, or it can't be had here (AirPlay)
    case off
    /// prepared, its output not running
    case resting
    /// its output running
    case running
}

public enum TurntableScreen {
    /// `soundReady()` (3.3): prepared and allowed - not failed, not on AirPlay, not interrupted. Not "running": the
    /// engine rests between sounds and starts on the press that needs it.
    public static func soundReady(_ engine: DeckEngineState) -> Bool {
        engine.prepared && engine.failure == nil && !engine.airPlay && !engine.interrupted
    }

    /// The rate a window is made at (4.4): the deck engine's once it has started at one (and the new route's after a
    /// route change made it again), else the session's - the rate it will start at. Before its first start the
    /// engine's own rate is a 48 kHz guess, and a first window made at it on a 44.1 kHz route would be dropped at that
    /// start and made again. 48 kHz when neither says.
    public static func windowRate(engineRate: Double, engineStarted: Bool, sessionRate: Double) -> Double {
        if engineStarted && engineRate > 0 { return engineRate }
        if sessionRate > 0 { return sessionRate }
        return engineRate > 0 ? engineRate : 48_000
    }

    /// The record can't make its sound on this phone at all (the press's `noAudio`): the engine couldn't start.
    public static func noAudio(_ engine: DeckEngineState) -> Bool {
        engine.failure != nil
    }

    /// The silent line over the plinth's foot (2.8, 2.9, NowPlaying.tsx:419): from the song's first silent turn until
    /// it changes, AirPlay first - and never while the player's failure shows, which says more.
    public static func silentLine(turnedSilent: Bool, flac: Bool, engine: DeckEngineState, error: String?) -> String? {
        guard turnedSilent, error?.isEmpty ?? true else { return nil }
        return TurntableWords.silentNote(flac: flac, noAudio: noAudio(engine), airPlay: engine.airPlay)
    }

    /// The display link runs (2.6) only while the deck has asked for a frame, the turntable shows on Now Playing and
    /// the scene is active - a still record costs nothing - and under Reduce Motion only while a hand holds the record:
    /// the web's loop asks a frame for a held record whatever the motion setting (`moving()`, deck.ts:2074), to show
    /// the time line and count the frames under the hand, and the platter never turns by itself then.
    public static func framesRun(asked: Bool, showing: Bool, active: Bool, reduced: Bool, held: Bool) -> Bool {
        asked && showing && active && (!reduced || held)
    }

    /// The deck engine's run rule (4.6, question 13 C). `showing`: the turntable shows; `songPlaying`: the player is
    /// playing (or loading a play); `sounding`: the record's sound is on (a hand, a coast, a wind-down, a handover),
    /// whatever the song is doing; `quietFor`: seconds since the record's sound last ended (nil: it hasn't sounded);
    /// `pausedFor`: seconds since the song stopped (nil while it plays); `active`: the scene is.
    ///
    /// Running while it shows and the song plays, and while it sounds; when neither, resting **at once** if the song
    /// stopped with the record quiet (a pause from the lock screen), and **0.5 s after** the record's sound ended
    /// otherwise. Never on AirPlay or after a failed start (`.off`: not prepared); resting while the scene isn't active
    /// or an interruption lasts.
    public static func engineWant(showing: Bool, songPlaying: Bool, sounding: Bool, quietFor: Double?, pausedFor: Double?,
                                  active: Bool, engine: DeckEngineState) -> DeckEngineWant {
        if engine.airPlay || engine.failure != nil { return .off }
        if !active || engine.interrupted { return .resting }
        if sounding { return .running }
        if showing && songPlaying { return .running }
        guard let quietFor, quietFor < quietHold else { return .resting }
        // the song stopped after the sound had ended: at once
        if let pausedFor, pausedFor <= quietFor { return .resting }
        return .running
    }

    /// How long the deck engine runs on after the record's sound ends, the song paused (4.6).
    public static let quietHold = 0.5
}

/// The two settings (6.1), kept on this phone under the web's keys.
public enum TurntableSettings {
    public static let opensAsKey = "deadwax-player-opens-as"
    public static let windDownKey = "deadwax-player-wind-down"

    public enum Look: String, Equatable, Sendable, CaseIterable {
        case cover, turntable
        /// the other one (turntable.ts otherLook)
        public var other: Look { self == .cover ? .turntable : .cover }
    }

    /// The turntable only when it says exactly that (persisted.ts:247).
    public static func opensAs(_ stored: String?) -> Look { stored == "turntable" ? .turntable : .cover }
    public static func stored(_ look: Look) -> String { look.rawValue }
    /// On unless it says exactly 'off' (persisted.ts:262).
    public static func windDown(_ stored: String?) -> Bool { stored != "off" }
    public static func stored(windDown: Bool) -> String { windDown ? "on" : "off" }

    /// What Now Playing shows (NowPlaying.tsx:269): the turntable only with the lyrics off.
    public static func showsTurntable(_ look: Look, lyricsOn: Bool) -> Bool { look == .turntable && !lyricsOn }

    /// The look button (NowPlaying.tsx:343): the lyrics off, the look switched; whether the deck may start its sound
    /// (the web's wakeDeckAudio) - switching to the turntable is a gesture that may.
    public static func lookTapped(_ look: Look, lyricsOn: Bool) -> (look: Look, lyricsOff: Bool, wake: Bool) {
        (look.other, lyricsOn, look == .cover)
    }

    /// The lyrics button over the turntable's look (NowPlaying.tsx:351): turning them off shows the turntable again,
    /// and wakes the deck.
    public static func lyricsTapped(_ look: Look, lyricsOn: Bool) -> (lyricsOn: Bool, wake: Bool) {
        (!lyricsOn, lyricsOn && look == .turntable)
    }
}

/// Debug's Turntable section on the phone (6.2): the web's rows where the phone has the same fact, and the phone's own.
public struct DeckPhoneFacts {
    public enum From: Equatable, Sendable {
        case download, cache, server, offline
    }

    /// A let-go's handover (3.5): how early the song was resumed (`E - D`), `E` predicted and as it came, the timer's
    /// lateness, the seam.
    public struct Handover: Equatable, Sendable {
        public var lead: Double
        public var predicted: Double
        public var took: Double?
        public var timerLate: Double?
        public var seam: Double?
        public init(lead: Double, predicted: Double, took: Double? = nil, timerLate: Double? = nil, seam: Double? = nil) {
            self.lead = lead
            self.predicted = predicted
            self.took = took
            self.timerLate = timerLate
            self.seam = seam
        }
    }

    /// nil: the turntable isn't showing
    public var report: DeckReport?
    public var from: From?
    public var clock: (lead: Double?, largest: Double?, underHand: Bool)?
    public var handover: Handover?
    /// the `deck.position` queue's longest wait on the engine, during the last handover
    public var positionRead: Double?
    public var windowMade: (took: Double, seconds: Double, rate: Double)?
    public var dropped = 0
    /// coalesced samples and their events, a second, under the last hand
    public var touches: (samples: Double, events: Double)?
    /// presses whose sound started after its delay, and the worst by how much
    public var slowStarts: (count: Int, worst: Double)?

    public init(report: DeckReport?) { self.report = report }
}

extension TurntableDebugRows {
    /// The phone's voice, in the web's row (debugRows.ts:372 says "an AudioWorklet").
    public static let phoneVoice = "On its own audio thread (an AVAudioSourceNode)"

    /// The Turntable sound row's words while an interruption lasts.
    public static let interruptedWords = "an interruption (a call, Siri, an alarm) hasn't ended - a press scrubs silently until it does"

    /// "Window from" (new).
    public static func windowFromRow(_ from: DeckPhoneFacts.From) -> InfoRow {
        let value: String
        switch from {
        case .download: value = "This phone's download"
        case .cache: value = "The copy kept on this phone"
        case .server: value = "deadwax - the song is still coming in"
        case .offline: value = "Off: no window - this phone is offline and the song isn't all on it yet"
        }
        return InfoRow(label: "Window from", value: value)
    }

    /// "Handover" (new, 3.5).
    public static func handoverRow(_ handover: DeckPhoneFacts.Handover) -> InfoRow {
        func s(_ seconds: Double) -> String { "\(jsFixed(seconds, 2)) s" }
        var value = handover.lead > 0 ? "Resumed \(s(handover.lead)) early for a start of \(s(handover.predicted))"
            : "Resumed at the let-go for a start of \(s(handover.predicted))"
        if let took = handover.took {
            let late = handover.timerLate.map { (late: Double) -> String in ", the timer \(JSNumber.string((late * 1000).rounded())) ms late" } ?? ""
            value += " (it took \(s(took))\(late))"
        }
        if let seam = handover.seam {
            let ms = JSNumber.string((Swift.abs(seam) * 1000).rounded())
            value += seam >= 0 ? "; the song came in \(ms) ms after the record's sound was there"
                : "; the song came in \(ms) ms before the record's sound was there"
        }
        return InfoRow(label: "Handover", value: value)
    }

    /// "Position read in" (new, 2.6).
    public static func positionReadRow(_ seconds: Double) -> InfoRow {
        InfoRow(label: "Position read in", value: "\(ms(seconds)) at worst during the last handover")
    }

    /// "Touches under a hand" (new, 3.1).
    public static func touchesRow(samples: Double, events: Double) -> InfoRow {
        InfoRow(label: "Touches under a hand",
                value: "\(JSNumber.string(samples.rounded())) a second, from \(JSNumber.string(events.rounded())) events a second")
    }

    /// "Slow starts" (new, 4.6): shown only when there were some.
    public static func slowStartsRow(count: Int, worst: Double) -> InfoRow? {
        guard count > 0 else { return nil }
        let presses = count == 1 ? "1 press whose sound started after its delay" : "\(count) presses whose sound started after its delay"
        let by = count == 1 ? ", by \(JSNumber.string((worst * 1000).rounded())) ms" : ", the worst by \(JSNumber.string((worst * 1000).rounded())) ms"
        return InfoRow(label: "Slow starts", value: presses + by)
    }

    /// The Turntable section, top to bottom, in 6.2's order: the web's rows (its Voice the phone's), then the phone's
    /// own beside the facts they belong with.
    public static func phoneRows(_ facts: DeckPhoneFacts) -> [InfoRow] {
        let report = facts.report
        var rows = [turntableRow(report)]
        guard report != nil else { return rows }
        if let from = facts.from { rows.append(windowFromRow(from)) }
        for row in turntableSoundFacts(report) {
            if row.label == "Voice" {
                rows.append(InfoRow(label: "Voice", value: phoneVoice))
            } else if row.label == "Clock step" {
                rows.append(row)
                if let clock = facts.clock { rows.append(clockRow(lead: clock.lead, largest: clock.largest, underHand: clock.underHand)) }
            } else {
                rows.append(row)
            }
        }
        if report?.clockStep == nil, let clock = facts.clock {
            rows.append(clockRow(lead: clock.lead, largest: clock.largest, underHand: clock.underHand))
        }
        rows.append(turntableTimingRow(report))
        if let handover = facts.handover { rows.append(handoverRow(handover)) }
        if let read = facts.positionRead { rows.append(positionReadRow(read)) }
        if let made = facts.windowMade { rows.append(windowMadeRow(took: made.took, seconds: made.seconds, rate: made.rate)) }
        if let dropped = messagesDroppedRow(facts.dropped) { rows.append(dropped) }
        for row in turntableTimingFacts(report) {
            rows.append(row)
            if row.label == "Frames under a hand", let touches = facts.touches {
                rows.append(touchesRow(samples: touches.samples, events: touches.events))
            }
        }
        if let slow = facts.slowStarts, let row = slowStartsRow(count: slow.count, worst: slow.worst) { rows.append(row) }
        return rows
    }

    /// The deck's report as the phone has it (6.2): `context` from the engine - 'failed' with its words when it
    /// couldn't start, is on AirPlay or an interruption hasn't ended (a call, Siri, an alarm: soundReady is false, so
    /// the row mustn't read Ready), 'starting' until it is prepared, else 'running' (the web's word for a context that
    /// can sound; the phone's rests between sounds by design) - and the rest from the deck's rules.
    public static func phoneReport(engine: DeckEngineState, window: DeckReport.Window?, loading: Bool, refused: String?,
                                   failed: String?, fetched: Double, lastFetchAt: Double, ioBuffer: Double?,
                                   outputLatency: Double?, health: DeckReport.DeckHealth?) -> DeckReport {
        let context: String
        var problem: String?
        if let failure = engine.failure {
            context = "failed"
            problem = failure
        } else if engine.airPlay {
            context = "failed"
            problem = "the record makes no sound over AirPlay"
        } else if engine.interrupted {
            context = "failed"
            problem = interruptedWords
        } else if !engine.prepared {
            context = "starting"
        } else {
            context = "running"
        }
        let voiced = context == "running" || context == "starting"
        let latency = DeckReport.Latency(base: ioBuffer, output: outputLatency, design: DeckVoice.handDelayS + DeckVoice.lookaheadS)
        return DeckReport(context: context, problem: problem, voice: voiced ? "worklet" : nil, window: window, loading: loading,
                          refused: refused, failed: failed, fetched: fetched, lastFetchAt: lastFetchAt, clockStep: ioBuffer,
                          health: health, latency: voiced ? latency : nil)
    }
}
