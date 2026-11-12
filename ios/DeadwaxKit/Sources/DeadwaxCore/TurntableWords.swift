/// Every word the turntable and the fader say (notes/ios-specs/turntable.md 2.9), and Debug's turntable rows - the
/// web's, moved into Core and held to what the web's own functions make (Fixtures/deck/words.json, TurntableWordsTests).
/// Where the web names the browser the phone says "phone"; where the phone has something the web hasn't, the words are
/// new and written in the web's manner. Each says where in the web it comes from.
public enum TurntableWords {
    // ----- Now Playing

    /// The look button: the look it switches to (turntable.ts:47).
    public static func lookButton(showingTurntable: Bool) -> String {
        showingTurntable ? "Show the cover" : "Show as a turntable"
    }

    /// The record, named for what a tap does (Turntable.tsx:443).
    public static func record(playing: Bool) -> String {
        playing ? "The record: a tap pauses the song" : "The record: a tap plays the song"
    }

    /// The arm, a slider (Turntable.tsx:502), and its value (:506).
    public static let arm = "Tonearm: position in the song"
    public static func armValue(_ shown: Double, _ length: Double) -> String {
        "\(Format.clock(shown)) of \(Format.clock(length))"
    }

    /// The time line under the plinth (turntable.ts:372): the time, of the length when there is one, led by what is
    /// moving it.
    public static func timeLine(_ time: Double, _ length: Double, _ how: TurntableDrag.Kind?) -> String {
        let at = length > 0 ? "\(Format.clock(time)) of \(Format.clock(length))" : Format.clock(time)
        switch how {
        case .arm: return "Needle up \u{00B7} \(at)"
        case .record: return "Scrubbing \u{00B7} \(at)"
        case nil: return at
        }
    }

    // ----- the silent line (turntable.ts:379-400, the spec's 2.9)

    /// Not a FLAC: the web's words (turntable.ts:386).
    public static let notFlac = "The record makes sound for FLAC songs only - this one moves silently."
    /// No sound possible here (turntable.ts:388) - the phone's words: "phone" for the web's "browser".
    public static let noAudio = "This phone can't make the record's sound - turning it still moves through the song."
    /// The web's own, which the phone's is held to with that one word changed.
    public static let noAudioWeb = "This browser can't make the record's sound - turning it still moves through the song."
    /// Over AirPlay (new): the record is silent there, as the spec's question 5 has it.
    public static let airPlay = "The record makes no sound over AirPlay - turning it still moves through the song."

    /// Why the record is silent for good on this song, nil when it isn't (turntable.ts:393), AirPlay first on the
    /// phone - it holds for every song while it lasts.
    public static func silentNote(flac: Bool, noAudio: Bool, airPlay: Bool = false) -> String? {
        if airPlay { return Self.airPlay }
        if noAudio { return Self.noAudio }
        return flac ? nil : notFlac
    }

    // ----- Debug's new words, for the phone's own (the spec's 2.9 and 3.3)

    /// A window the phone couldn't make (new: the web's decode failure, deck.ts:2382, said for the phone's making).
    public static func windowNotMade(_ words: String) -> String {
        "this phone couldn't make its window - \(words.isEmpty ? "it gave no reason" : words)"
    }

    /// A file of more than two channels (new).
    public static func tooManyChannels(_ channels: Int) -> String {
        "it has \(channels) channels - the record plays two at most"
    }

    /// Offline, with no whole copy on the phone (new).
    public static let offline = "no window - this phone is offline and the song isn't all on it yet"

    /// A song slow to start after a let-go (new, the spec's 3.5).
    public static func slowStart(_ seconds: Double) -> String {
        "The song took \(jsFixed(seconds, 1)) s to start"
    }

    // ----- the fader (playSpeed.ts, SpeedFader.tsx, SpeedChip.tsx)

    /// The readout's face and the chip's, two places always (playSpeed.ts:68).
    public static func speedLabel(_ speed: Double) -> String {
        "\(jsFixed(PlaySpeed.roundSpeed(speed), 2))x"
    }

    /// What VoiceOver says of a speed (playSpeed.ts:73).
    public static func speedWords(_ speed: Double) -> String {
        let rounded = PlaySpeed.roundSpeed(speed)
        return rounded == PlaySpeed.normal ? "normal speed" : "\(JSNumber.string(rounded)) times"
    }

    /// The fader's name (SpeedFader.tsx:113).
    public static let fader = "Speed"

    /// The readout, a button back to 1x (SpeedFader.tsx:139).
    public static func readout(_ speed: Double) -> String {
        speed == PlaySpeed.normal ? "Speed: normal" : "Speed \(speedLabel(speed)): back to normal speed"
    }

    /// The chip on the cover, off 1x (SpeedChip.tsx:35).
    public static func chip(_ speed: Double) -> String {
        "\(speedLabel(speed)), \(speedWords(speed)) the song's speed: back to normal speed"
    }

    /// The ••• menu's item where the chip isn't drawn (new, the spec's 5.1).
    public static func menuBackToNormal(_ speed: Double) -> String {
        "Speed \(speedLabel(speed)) - back to normal speed"
    }

    // ----- You > Playback (LookChoice.tsx, WindDownChoice.tsx, You.tsx)

    public static let opensAs = "Now Playing opens as"
    public static let lookCover = "Cover"
    public static let lookTurntable = "Turntable"
    public static let windDown = "Pause winds the record down"

    /// The notes under them: the web's, less the last sentence about its desktop frame, which the app has no case for
    /// (the spec's 2.9). `lookNoteWebEnd` and `windDownNoteWebEnd` are those sentences.
    public static let lookNote = "What you see first when you open Now Playing. The button at its top right switches between the two while it's open."
    public static let lookNoteWebEnd = "For phones: a big screen has no Now Playing view."
    public static let windDownNote = "On the turntable, pausing slows the music to a stop over about a second, as a real record deck does. Turn it off to stop at once. Pausing from the cover always stops at once."
    public static let windDownNoteWebEnd = "For phones: a big screen has no turntable."
}

// MARK: - Debug's turntable rows, as the web's debugRows.ts has them

/// What the deck reports to Info > Debug (deckVoice.ts DeckReport, :859).
public struct DeckReport: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var kind: String
        public var decodedAt: Double
        public var bytes: Double
        public init(start: Double, end: Double, kind: String, decodedAt: Double, bytes: Double) {
            self.start = start
            self.end = end
            self.kind = kind
            self.decodedAt = decodedAt
            self.bytes = bytes
        }
    }

    /// deckVoice.ts DeckHealth (:927).
    public struct Health: Equatable, Sendable {
        public var blocks = 0.0, lateBlocks = 0.0, worstBlockMs = 0.0
        public var frames = 0.0, slowFrames = 0.0, worstFrameMs = 0.0
        public var backMs: Double?
        public var motorMs: Double?
        public var notBack = 0.0
        public var interruptions = 0.0
        public var peaksHeld: Double? = 0
        public var samplesHeld = 0.0
        public var deepestHoldDb = 0.0
        public init() {}
    }

    /// deckVoice.ts DeckLatency (:906).
    public struct Latency: Equatable, Sendable {
        public var base: Double?
        public var output: Double?
        public var speaker: Double?
        public var block: Double?
        public var design: Double?
        public init(base: Double? = nil, output: Double? = nil, speaker: Double? = nil, block: Double? = nil, design: Double? = nil) {
            self.base = base
            self.output = output
            self.speaker = speaker
            self.block = block
            self.design = design
        }
    }

    /// 'none' | 'starting' | 'running' | 'unsupported' | 'no-voice' | 'failed'.
    public var context: String
    public var problem: String?
    /// 'worklet' | 'script', or nil.
    public var voice: String?
    public var voiceWhy: String?
    public var window: Window?
    public var loading: Bool
    public var refused: String?
    public var failed: String?
    public var fetched: Double
    public var lastFetchAt: Double
    public var clockStep: Double?
    public var health: Health?
    public var latency: Latency?

    public init(context: String, problem: String? = nil, voice: String? = nil, voiceWhy: String? = nil, window: Window? = nil, loading: Bool = false,
                refused: String? = nil, failed: String? = nil, fetched: Double = 0, lastFetchAt: Double = 0, clockStep: Double? = nil,
                health: Health? = nil, latency: Latency? = nil) {
        self.context = context
        self.problem = problem
        self.voice = voice
        self.voiceWhy = voiceWhy
        self.window = window
        self.loading = loading
        self.refused = refused
        self.failed = failed
        self.fetched = fetched
        self.lastFetchAt = lastFetchAt
        self.clockStep = clockStep
        self.health = health
        self.latency = latency
    }
}

/// What the player does with the speed (playSpeed.ts SpeedReading, :215).
public struct SpeedReading: Equatable, Sendable {
    public var speed: Double
    public var rate: Double
    /// 'moves' | 'held' | 'no switch'.
    public var pitch: String
    public var refused: String?
    public var measured: Double?
    public init(speed: Double, rate: Double, pitch: String, refused: String? = nil, measured: Double? = nil) {
        self.speed = speed
        self.rate = rate
        self.pitch = pitch
        self.refused = refused
        self.measured = measured
    }
}

/// The web's turntable rows and its speed row (debugRows.ts:285-470), word for word - the phone's Debug section
/// (the spec's 6.2) is built from these and its own.
public enum TurntableDebugRows {
    static let notKnown = "Not known"
    static let latencyLead = "The record's sound: "

    static func khz(_ rate: Double) -> String { "\(JSNumber.string(rate / 1000)) kHz" }
    static func megabytes(_ bytes: Double) -> String { "\(jsFixed(bytes / 1_000_000, 1)) MB" }
    static func upperFirst(_ words: String) -> String {
        guard let first = words.first else { return words }
        return first.uppercased() + words.dropFirst()
    }
    static func n(_ value: Double) -> String { JSNumber.string(value) }

    /// "Turntable sound" (debugRows.ts:341).
    public static func turntableRow(_ report: DeckReport?) -> InfoRow {
        let label = "Turntable sound"
        guard let report else { return InfoRow(label: label, value: "Off: the turntable isn't showing") }
        let window = report.window
        let stretch = window.map { "\(Format.clock($0.start))-\(Format.clock($0.end)), \($0.kind), decoded at \(khz($0.decodedAt))" } ?? ""
        let ready: String? = window == nil ? nil : "Its window is ready: \(stretch)"
        if report.context == "unsupported" { return InfoRow(label: label, value: "Off: this browser has no Web Audio") }
        if report.context == "no-voice" { return InfoRow(label: label, value: "Off: this browser has neither an AudioWorklet nor a ScriptProcessorNode to play it") }
        if report.context == "failed" { return InfoRow(label: label, value: upperFirst("off: \(report.problem ?? "the sound couldn't start")")) }
        if let refused = report.refused, !refused.isEmpty { return InfoRow(label: label, value: "Off: \(refused)") }
        if report.context == "none" { return InfoRow(label: label, value: "Off: waiting for a tap to start the sound", note: ready) }
        if report.context == "starting" { return InfoRow(label: label, value: "Off: still starting - a press scrubs silently until it has", note: ready) }
        if window != nil { return InfoRow(label: label, value: "Ready: \(stretch)") }
        if let failed = report.failed, !failed.isEmpty { return InfoRow(label: label, value: "Off: \(failed)") }
        if report.loading { return InfoRow(label: label, value: "Off: its window is loading - a press scrubs silently until it is in") }
        return InfoRow(label: label, value: "Off: no window yet - a press scrubs silently; one is fetched while the song plays, or as the record is pressed")
    }

    /// The sound's facts, a row each (:368).
    public static func turntableSoundFacts(_ report: DeckReport?) -> [InfoRow] {
        guard let report else { return [] }
        var rows: [InfoRow] = []
        if report.voice == "script" { rows.append(InfoRow(label: "Voice", value: "On the main thread - \(report.voiceWhy ?? "this browser has no AudioWorklet")")) }
        else if report.voice == "worklet" { rows.append(InfoRow(label: "Voice", value: "On its own audio thread (an AudioWorklet)")) }
        if let step = report.clockStep, JSMath.truthy(step), step > 0 { rows.append(InfoRow(label: "Clock step", value: "\(jsFixed(step * 1000, 1)) ms at a time")) }
        if report.fetched > 0 {
            let each = report.window.map { "\(megabytes($0.bytes)) a window; " } ?? ""
            rows.append(InfoRow(label: "Data used",
                                value: "\(each)\(megabytes(report.fetched)) fetched since the turntable showed, the last window \(Format.clock(report.lastFetchAt / 1000)) in"))
        }
        return rows
    }

    /// "Turntable timing" (:389).
    public static func turntableTimingRow(_ report: DeckReport?) -> InfoRow {
        let label = "Turntable timing"
        guard let health = report?.health else { return InfoRow(label: label, value: "Not known") }
        func seconds(_ ms: Double) -> String { "\(jsFixed(ms / 1000, ms < 10_000 ? 2 : 1)) s" }
        let value: String
        if let back = health.backMs {
            let motor = health.motorMs.flatMap { JSMath.truthy($0) ? " - \(seconds($0)) of it the record's run back to speed" : nil } ?? ""
            value = "The song was back \(seconds(back)) after the last let-go\(motor)"
        } else {
            value = "No let-go of a playing record timed yet"
        }
        return InfoRow(label: label, value: value)
    }

    /// What the deck measures of keeping up, a row each (:409).
    public static func turntableTimingFacts(_ report: DeckReport?) -> [InfoRow] {
        guard let report, let health = report.health else { return [] }
        var rows: [InfoRow] = []
        if report.voice == "script" {
            let late = JSMath.truthy(health.lateBlocks) ? ", the worst by \(n(JSMath.round(health.worstBlockMs))) ms" : ""
            rows.append(InfoRow(label: "Main-thread sound",
                                value: JSMath.truthy(health.blocks) ? "\(n(health.lateBlocks)) of \(n(health.blocks)) blocks late\(late)" : "No block played yet"))
        }
        if report.voice != nil, let peaks = health.peaksHeld {
            let deepest = health.deepestHoldDb < 0.05 ? "under 0.1" : jsFixed(health.deepestHoldDb, 1)
            rows.append(InfoRow(label: "Limiter", value: JSMath.truthy(peaks)
                ? "\(n(peaks)) \(peaks == 1 ? "peak" : "peaks") held under full scale since it showed (\(n(health.samplesHeld)) \(health.samplesHeld == 1 ? "sample" : "samples")), the deepest \(deepest) dB"
                : "No peaks held under full scale since it showed"))
        }
        let slow = JSMath.truthy(health.slowFrames) ? ", the longest gap \(n(JSMath.round(health.worstFrameMs))) ms" : ""
        rows.append(InfoRow(label: "Frames under a hand",
                            value: JSMath.truthy(health.frames) ? "\(n(health.frames)) frames, \(n(health.slowFrames)) late\(slow)" : "No frames yet"))
        if JSMath.truthy(health.notBack) {
            rows.append(InfoRow(label: "Not restarted", value: "\(n(health.notBack)) \(health.notBack == 1 ? "let-go" : "let-goes") after which the song didn't start"))
        }
        if JSMath.truthy(health.interruptions) {
            rows.append(InfoRow(label: "Interruptions", value: "The sound was interrupted \(health.interruptions == 1 ? "once" : "\(n(health.interruptions)) times")"))
        }
        if let latency = latencyNote(report) {
            rows.append(InfoRow(label: "Delay behind the hand", value: latency.replacingFirst(latencyLead, with: "")))
        }
        return rows
    }

    /// The turntable's rows, top to bottom (:442).
    public static func turntableRows(_ report: DeckReport?) -> [InfoRow] {
        [turntableRow(report)] + turntableSoundFacts(report) + [turntableTimingRow(report)] + turntableTimingFacts(report)
    }

    /// The record's sound behind the hand (:457).
    public static func latencyNote(_ report: DeckReport?) -> String? {
        guard let report, let latency = report.latency, let design = latency.design, let voice = report.voice else { return nil }
        func ms(_ seconds: Double) -> String { "\(jsFixed(seconds * 1000, 1)) ms" }
        let how: String
        if voice == "script" {
            how = latency.block.map { JSMath.truthy($0) ? " (blocks of \(n($0)) on the main thread)" : " (on the main thread)" } ?? " (on the main thread)"
        } else {
            how = " (on its own thread)"
        }
        var adds: [String] = []
        if let base = latency.base { adds.append("base \(ms(base))") }
        if let output = latency.output { adds.append("output \(ms(output))") }
        if let speaker = latency.speaker { adds.append("\(ms(speaker)) from render to speaker") }
        let says = adds.isEmpty ? "it doesn't say" : "it says \(adds.joined(separator: ", "))"
        return "\(latencyLead)\(ms(design)) behind the hand by design\(how), then what this device's audio adds - \(says)"
    }

    /// "Speed" (:285).
    public static func speedRow(_ reading: SpeedReading?) -> InfoRow {
        let label = "Speed"
        guard let reading else { return InfoRow(label: label, value: notKnown) }
        let pace = reading.measured.map { "The song moved at \(TurntableWords.speedLabel($0)) over the last few seconds of playing" }
        func withPace(_ value: String) -> InfoRow { InfoRow(label: label, value: value, note: pace) }
        let speed = reading.speed
        if let refused = reading.refused, !refused.isEmpty {
            return withPace("Asked for \(TurntableWords.speedLabel(speed)); the browser refused it - \(refused)")
        }
        if Swift.abs(reading.rate - speed) > 1e-6 {
            return withPace("Asked for \(TurntableWords.speedLabel(speed)); the browser plays it at \(TurntableWords.speedLabel(reading.rate))")
        }
        if speed == PlaySpeed.normal { return withPace("Normal (1.00x) - the song as it is, nothing changed") }
        if reading.pitch == "moves" { return withPace("\(TurntableWords.speedLabel(speed)), the pitch moving with it") }
        if reading.pitch == "held" { return withPace("\(TurntableWords.speedLabel(speed)), but the browser is holding the pitch") }
        return withPace("\(TurntableWords.speedLabel(speed)) - this browser has no pitch switch, so it may be holding the pitch")
    }
}

extension String {
    /// `String.prototype.replace(text, with)`: the first occurrence only.
    func replacingFirst(_ text: String, with replacement: String) -> String {
        guard let found = range(of: text) else { return self }
        return replacingCharacters(in: found, with: replacement)
    }
}
