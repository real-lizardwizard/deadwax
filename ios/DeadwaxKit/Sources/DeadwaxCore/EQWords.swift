import Foundation

/// The EQ's words (eq.md 3.13, and 3.9's for an import) - every one tested. Title case for menu items and buttons that
/// name a command, as the app's are; sentence case in rows and lines.
public enum EQWords {
    /// A number in a sentence: the shortest form that reads back, without a trailing ".0" (`30000`, `-2`, `12.345`).
    public static func number(_ x: Double) -> String {
        let t = x.description
        return t.hasSuffix(".0") ? String(t.dropLast(2)) : t
    }

    /// One decimal, correctly rounded, never "-0.0" ("-6.4", "6.0").
    public static func oneDecimal(_ x: Double) -> String {
        let t = String(format: "%.1f", x)
        return t == "-0.0" ? "0.0" : t
    }

    /// Up to a tenth, the next tenth up - for "within" and "up to" (a value within 1e-9 of a tenth is on it).
    public static func tenthAbove(_ x: Double) -> Double {
        ((x - 1e-9) * 10).rounded(.up) / 10
    }

    // ------------------------------------------------------------ import (3.9)

    /// 3.9's words: each refusal and each note, and the preview's lines.
    public enum Import {
        public static let fromFiles = "Import from Files…"
        public static let title = "Import"
        public static let importButton = "Import"
        public static let cancel = "Cancel"
        public static let done = "Done"
        public static let fromClipboard = "From the clipboard"
        public static let forLabel = "For"
        public static let skipped = "Skipped"
        public static let refusedTitle = "Can't import this file"

        public static func from(file: String) -> String { "From \"\(file)\"" }

        /// "10 filters, preamp -6.4 dB"; "11 filters for both ears, 2 more for the left, preamp -6.0 dB" - the
        /// file's own preamp, its shared part.
        public static func summary(_ reading: APOReading) -> String {
            let both = reading.filters.filter { $0.channel == .all }.count
            let left = reading.filters.filter { $0.channel == .left }.count
            let right = reading.filters.filter { $0.channel == .right }.count
            var parts: [String] = []
            if left == 0 && right == 0 {
                parts.append(count(both, "filter"))
            } else {
                parts.append("\(count(both, "filter")) for both ears")
                if left > 0 { parts.append("\(left) more for the left") }
                if right > 0 { parts.append("\(right) more for the right") }
            }
            parts.append("preamp \(oneDecimal(reading.preamp.all)) dB")
            return parts.joined(separator: ", ")
        }

        /// The preamp as it will play: deadwax's, with this output's tone, or the file's when it is set by hand.
        public static func preampAutomatic(_ dB: Double) -> String {
            "Preamp: set by deadwax, \(oneDecimal(dB)) dB with this output's tone."
        }

        public static func preampFiles(_ dB: Double) -> String { "Preamp: the file's, \(oneDecimal(dB)) dB." }

        /// "It replaces the correction for James's AirPods Pro (Apple AirPods Pro, from AutoEq)."
        public static func replaces(output: String, what: String) -> String {
            "It replaces the correction for \(output) (\(what))."
        }

        /// 3.10's line: "Converted from a GraphicEQ curve: 54 filters, within 0.1 dB of it on average and 0.5 dB at
        /// most up to 16 kHz; above that, up to 3.8 dB." - each rounded up to a tenth; "above that" left off when it
        /// is within 1 dB.
        public static func converted(_ fit: GraphicEQFit.Result) -> String {
            let s = fit.stats48000
            var text = "Converted from a GraphicEQ curve: \(count(fit.kept, "filter")), within \(oneDecimal(tenthAbove(s.mean))) dB of it on average and \(oneDecimal(tenthAbove(s.largest))) dB at most up to 16 kHz"
            if tenthAbove(s.above) > 1 { text += "; above that, up to \(oneDecimal(tenthAbove(s.above))) dB" }
            return text + "."
        }

        static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

        // ---------------------------------------------------- refused: the whole file

        static func refusal(_ kind: APORefusal.Kind, _ line: Int?, _ text: String) -> APORefusal {
            APORefusal(kind: kind, line: line, text: text)
        }

        public static func nothing(pasted: Bool) -> APORefusal {
            refusal(.nothing, nil, "There's no EQ in \(pasted ? "what you pasted" : "this file"): no Preamp, Filter or GraphicEQ lines.")
        }

        public static func tooBig(bytes: Int) -> APORefusal {
            refusal(.tooBig, nil, "This file is too big to be an EQ file (\(Bytes.words(Int64(bytes)))).")
        }

        public static let unreadable = APORefusal(kind: .unreadable, line: nil, text: "deadwax couldn't read this file.")

        public static let crOnly = APORefusal(kind: .crOnly, line: nil, text: "This file's lines end the old Mac way, which Equalizer APO reads as one long line. Save it again from a text editor and import that.")

        public static func include(line n: Int, what: String) -> APORefusal {
            refusal(.include, n, "Line \(n) includes another file (\(what)). Import that file itself.")
        }

        public static func unsupported(line n: Int, command: String) -> APORefusal {
            refusal(.unsupported, n, "Line \(n) uses \(command), which deadwax can't play.")
        }

        public static func devices(line n: Int) -> APORefusal {
            refusal(.devices, n, "This file has settings for more than one device (line \(n)). deadwax keeps a setting for each output itself - import the part for these headphones as a file of its own.")
        }

        public static func iir(line n: Int) -> APORefusal {
            refusal(.iir, n, "Line \(n) gives a filter as raw coefficients, made for one sample rate - deadwax plays at several, so it can't play it.")
        }

        public static func frequencyLow(line n: Int) -> APORefusal {
            refusal(.frequencyLow, n, "Line \(n): a filter's frequency must be at least 1 Hz.")
        }

        public static func frequencyHigh(line n: Int, hz: Double) -> APORefusal {
            refusal(.frequencyHigh, n, "Line \(n): \(number(hz)) Hz is higher than this phone plays - the highest a filter can be is 22000 Hz.")
        }

        public static func gain(line n: Int, dB: Double) -> APORefusal {
            refusal(.gain, n, "Line \(n): a gain of \(number(dB)) dB is more than deadwax plays - at most 30 dB either way.")
        }

        public static func q(line n: Int, q: Double) -> APORefusal {
            refusal(.q, n, "Line \(n): Q \(number(q)) won't make a filter - it must be between 0.01 and 100, or left out.")
        }

        public static func width(line n: Int, octaves: Double) -> APORefusal {
            refusal(.width, n, "Line \(n): a width of \(number(octaves)) octaves won't make a filter - it must be between 0.01 and 10, or left out.")
        }

        public static func slope(line n: Int, dB: Double) -> APORefusal {
            refusal(.slope, n, "Line \(n): a slope of \(number(dB)) dB won't make a filter - it must be above 0.")
        }

        public static func tooSteep(line n: Int, kind: EQKind, slope: Double, gain: Double) -> APORefusal {
            refusal(.tooSteep, n, "Line \(n): \(typePhrase[kind]!) this steep (\(number(slope)) dB an octave) can't have \(number(gain)) dB of gain - Equalizer APO can't play it either.")
        }

        public static func preamp(line n: Int, dB: Double) -> APORefusal {
            refusal(.preamp, n, "Line \(n): a preamp of \(number(dB)) dB is more than deadwax plays - at most 30 dB either way.")
        }

        public static func tooMany(count: Int) -> APORefusal {
            refusal(.tooMany, nil, "This file has \(count) filters for one ear - deadwax plays up to 64.")
        }

        public static func graphicEmpty(line n: Int) -> APORefusal {
            refusal(.graphicEmpty, n, "Line \(n): a GraphicEQ line needs at least one frequency and its gain.")
        }

        public static func graphicZero(line n: Int, frequency: Double) -> APORefusal {
            refusal(.graphicZero, n, "Line \(n): a GraphicEQ's frequencies must be above 0 Hz (\(number(frequency)) is there).")
        }

        // ---------------------------------------------------- skipped, with a note

        static let typePhrase: [EQKind: String] = [
            .peak: "a peak filter", .lowShelf: "a low-shelf filter", .highShelf: "a high-shelf filter",
            .lowPass: "a low-pass filter", .highPass: "a high-pass filter", .bandPass: "a band-pass filter",
            .notch: "a notch filter", .allPass: "an all-pass filter",
        ]

        public static func device(line n: Int, text: String) -> APONote {
            APONote(kind: .device, first: n, last: n,
                    text: "Line \(n) (\(text)) chooses a device in Equalizer APO - deadwax keeps a setting for each output itself.")
        }

        /// "Lines 12-20 are for the centre channel (C), which a phone doesn't have."
        public static func channels(first: Int, last: Int, words: [[Unicode.Scalar]]) -> APONote {
            let one = first == last
            let whom = one ? "Line \(first) is" : "Lines \(first)-\(last) are"
            let text: String
            if words.isEmpty {
                text = "\(whom) for no channel: the Channel line before \(one ? "it" : "them") names none."
            } else {
                text = "\(whom) for \(positions(words.map { APOReader.text($0) })), which a phone doesn't have."
            }
            return APONote(kind: .channels, first: first, last: last, text: text)
        }

        /// The positions a phone doesn't have, in words: "the centre channel (C)", "the rear channels (RL, RR)",
        /// "channel 3", each kind once, in the order the line names them.
        static func positions(_ words: [String]) -> String {
            var groups: [(key: String, words: [String])] = []
            for word in words {
                let key: String
                switch word {
                case "C": key = "centre"
                case "LFE", "SUB": key = "sub"
                case "RL", "RR": key = "rear"
                case "RC": key = "rearCentre"
                case "SL", "SR": key = "side"
                default: key = "other"
                }
                if let i = groups.firstIndex(where: { $0.key == key }) {
                    if !groups[i].words.contains(word) { groups[i].words.append(word) }
                } else {
                    groups.append((key, [word]))
                }
            }
            let phrases = groups.map { group -> String in
                let listed = group.words.joined(separator: ", ")
                let plural = group.words.count > 1 ? "s" : ""
                switch group.key {
                case "centre": return "the centre channel (\(listed))"
                case "sub": return "the subwoofer channel (\(listed))"
                case "rear": return "the rear channel\(plural) (\(listed))"
                case "rearCentre": return "the rear centre channel (\(listed))"
                case "side": return "the side channel\(plural) (\(listed))"
                default: return (group.words.count == 1 ? "channel " : "channels ") + andList(group.words)
                }
            }
            return andList(phrases)
        }

        static func andList(_ items: [String]) -> String {
            items.count == 1 ? items[0] : items.dropLast().joined(separator: ", ") + " and " + items.last!
        }

        /// "Line 9 isn't something Equalizer APO plays either (Volume: 5)." - and when the case is all that differs
        /// from a command APO knows, which one it reads.
        public static func unknown(line n: Int, text: String, hint: String?) -> APONote {
            var t = "Line \(n) isn't something Equalizer APO plays either (\(text))"
            if let hint { t += " - it reads \"\(hint)\" only as written, capital and all" }
            return APONote(kind: .unknown, first: n, last: n, text: t + ".")
        }

        /// What a filter APO leaves out lacks.
        public enum Missing: Equatable, Sendable {
            case frequency, gain, width, onOff
            /// an unknown type, as written
            case type(String)
        }

        /// "Line 5 (a peak filter) is left out, as Equalizer APO leaves it out: it has no gain." - with the near miss
        /// that explains it, when there is one.
        public static func leftOut(line n: Int, kind: EQKind?, reason: Missing, near: String?) -> APONote {
            let who = kind.map { "Line \(n) (\(typePhrase[$0]!))" } ?? "Line \(n)"
            let why: String
            switch reason {
            case .frequency: why = "it has no frequency"
            case .gain: why = "it has no gain"
            case .width: why = "it has no width (a Q or a BW Oct; 0 counts as none, as in APO)"
            case .onOff: why = "it has no ON or OFF"
            case .type(let written): why = "it has an unknown type (\"\(written)\")"
            }
            var text = "\(who) is left out, as Equalizer APO leaves it out: \(why)"
            if let near { text += " - " + near }
            return APONote(kind: .leftOut, first: n, last: n, text: text + ".")
        }

        /// `it says "gain 6", and Equalizer APO reads only "Gain 6 dB"`
        public static func says(_ said: String, reads: String) -> String {
            "it says \"\(said)\", and Equalizer APO reads only \"\(reads)\""
        }

        public static let noHz = "its frequency has no \"Hz\" after it, which Equalizer APO needs"

        public static func knowsType(_ known: String) -> String { "Equalizer APO knows the type as \"\(known)\"" }

        public static let utf16 = APONote(kind: .utf16, first: nil, last: nil,
                                          text: "This file is saved as UTF-16, which Equalizer APO doesn't read - deadwax read it anyway.")
    }
}

// ------------------------------------------------------------ every other word (3.13)

extension EQWords {
    static func count(_ n: Int, _ noun: String, _ nouns: String? = nil) -> String {
        "\(n) \(n == 1 ? noun : (nouns ?? noun + "s"))"
    }

    /// A gain or a preamp as the screen shows it: one decimal, signed - "+2.6 dB", "-6.4 dB", "0.0 dB".
    public static func signedDB(_ x: Double) -> String {
        let t = oneDecimal(x)
        return (x > 0 && t != "0.0" ? "+" : "") + t + " dB"
    }

    /// A slider held: "+3.5 dB", "0 dB", "-6 dB".
    public static func held(_ gain: Double) -> String {
        gain == 0 ? "0 dB" : (gain > 0 ? "+" : "") + number(gain) + " dB"
    }

    /// Decibels for VoiceOver: "plus 3.5 decibels", "0 decibels", "minus 6 decibels".
    public static func decibelsSaid(_ x: Double) -> String {
        let unit = abs(x) == 1 ? "decibel" : "decibels"
        if x > 0 { return "plus \(number(x)) \(unit)" }
        if x < 0 { return "minus \(number(-x)) \(unit)" }
        return "0 decibels"
    }

    /// Hertz for VoiceOver: "125 hertz", "2.5 kilohertz", "1 kilohertz".
    public static func hertzSaid(_ f: Double) -> String {
        f < 1000 ? "\(Int(f.rounded())) hertz" : "\(tenths(f / 1000)) kilohertz"
    }

    /// A frequency or a rate, short: "62 Hz", "8.9 kHz", "48 kHz", "44.1 kHz".
    public static func hertz(_ f: Double) -> String {
        f < 1000 ? "\(Int(f.rounded())) Hz" : "\(tenths(f / 1000)) kHz"
    }

    /// One decimal at most, none when whole: "2.5", "16", "44.1".
    static func tenths(_ x: Double) -> String { number((x * 10).rounded() / 10) }

    // ------------------------------------------------------------ You, Now Playing, Info

    public enum You {
        public static let row = "EQ"
        public static let footer = "Each output keeps its own EQ - your headphones, the speaker, the car - and the EQ switches by itself when the output changes. This is kept on this phone."
    }

    /// The short setting (You's row, Now Playing's subtitle, Other outputs): "Off", "Flat", "Bass Boost", "Custom",
    /// "AutoEq", "From a file", "Your filters", or "<correction> + <tone>".
    public static func shortSetting(_ output: EQOutputSetting, in settings: EQSettings) -> String {
        guard output.on else { return "Off" }
        let tone = toneName(output.tone, in: settings)
        guard let c = output.correction else { return tone ?? "Flat" }
        let correction = switch c.kind {
        case .autoeq: "AutoEq"
        case .file: "From a file"
        case .built: "Your filters"
        }
        return tone.map { "\(correction) + \($0)" } ?? correction
    }

    /// A tone's name: a preset's, yours, or "Custom" - nil for Flat.
    public static func toneName(_ tone: EQTone, in settings: EQSettings) -> String? {
        switch tone {
        case .preset(let id): return EQGraphic.preset(id).flatMap { $0.id == "flat" ? nil : $0.name }
        case .yours(let id): return settings.presets.first { $0.id == id }?.name ?? "Custom"
        case .custom: return "Custom"
        }
    }

    public static let nowPlaying = "EQ"

    /// The ••• button's name with the EQ's part: "More: info, go to album, download, EQ".
    public static func moreName(_ base: String) -> String { base + ", EQ" }

    public enum Info {
        public static let label = "EQ"

        /// Sound's row: "Bass Boost on James's AirPods Pro, preamp -6.4 dB" - no preamp part at 0, and no row while
        /// Off (8, question 8).
        public static func sound(short: String, output: String, preamp: Double, on: Bool) -> String? {
            guard on else { return nil }
            return preamp == 0 ? "\(short) on \(output)" : "\(short) on \(output), preamp \(signedDB(preamp))"
        }

        /// Debug's row: "Filtering: 20 filters at 48 kHz, preamp -6.4 dB".
        public static func filtering(filters: Int, rate: Double, preamp: Double) -> String {
            "Filtering: \(count(filters, "filter")) at \(hertz(rate)), preamp \(signedDB(preamp))"
        }

        public static let passing = "Off: every sample passed through untouched"
        public static let changing = "Changing: crossfading to the new curve"
    }

    // ------------------------------------------------------------ the EQ screen (3.2-3.4)

    public enum Screen {
        public static let title = "EQ"
        public static let rename = "Rename…"
        /// The toolbar's •••, as the album page's is "More for this album" (slice 3).
        public static let more = "More for this output"
        public static let done = "Done"
        public static let connected = "Connected now"
        public static let notConnected = "Not connected"

        /// The output's row as one element: "James's AirPods Pro, connected now".
        public static func outputSaid(_ name: String, connected: Bool) -> String {
            "\(name), \(connected ? "connected now" : "not connected")"
        }

        public static let toggle = "EQ"
        public static func toggleSaid(_ name: String) -> String { "EQ for \(name)" }
        public static let airPlayFooter = "Over AirPlay, a change is heard about 2 seconds later."

        // the line under the curve
        public static let off = "Off: nothing changes the sound."
        public static let flat = "Flat: nothing changes the sound yet."
        public static func automatic(_ preamp: Double) -> String {
            "Preamp \(signedDB(preamp)), so loud songs don't clip."
        }
        /// Yours: enough, or how much the curve boosts past it (rounded up to a tenth, so never understated).
        public static func hand(_ preamp: Double, top: Double) -> String {
            let over = top + preamp
            if over > 1e-9 {
                return "Loud songs may clip: the curve boosts \(oneDecimal(tenthAbove(over))) dB more than this preamp takes away."
            }
            return "Preamp \(signedDB(preamp)), set by you."
        }
        public static let notConnectedLine = "Not connected: this is what it plays when it is."
        public static let unitNotMade = "The EQ can't play on this phone just now, so the sound is as it is. Closing deadwax and opening it again may help."
        public static let fallback = "The EQ comes in after a moment's pause."

        // the curve's labels
        public static let gainLabels = ["+12", "0", "-12"]
        public static let frequencyLabels = ["100", "1k", "10k"]
        public static let left = "Left"
        public static let right = "Right"

        /// At the top of a pushed page whose output has gone.
        public static func outputGone(_ name: String) -> String {
            "\(name) isn't connected: changes are kept for when it is."
        }
    }

    // ------------------------------------------------------------ Correction (3.7)

    public enum Correction {
        public static let header = "Correction"
        public static let none = "None"
        public static let backToAutoEq = "Back to AutoEq's"

        /// Where it's from: "AutoEq, measured by crinacle" (" - changed"), "From HD650 ParametricEQ.txt"
        /// (", converted"), "Your own filters".
        public static func source(_ c: EQCorrection) -> String {
            switch c.kind {
            case .autoeq: "AutoEq, measured by \(c.source ?? "")" + (c.changed ? " - changed" : "")
            case .file: "From \(c.name)" + (c.converted ? ", converted" : "")
            case .built: "Your own filters"
            }
        }

        /// The row's value: "None" or the correction's name.
        public static func value(_ c: EQCorrection?) -> String {
            guard let c else { return none }
            return c.kind == .built ? "Your own filters" : c.name
        }

        public static let headphonesFooter = "Evens out what these headphones do to the sound, so they sound neutral. Your tone goes on top."
        public static let otherFooter = "Evens out what this output does to the sound. Your tone goes on top."
        public static func footer(_ output: EQOutput) -> String { output.isHeadphones ? headphonesFooter : otherFooter }

        // the suggestion
        public static func suggestion(_ name: String) -> String { "AutoEq has a correction for \(name)" }
        public static func measuredBy(_ source: String) -> String { "Measured by \(source)" }
        public static func suggestions(_ query: String) -> String { "AutoEq has corrections for \(query)" }
        public static func models(_ n: Int) -> String { "\(n) models - pick yours" }
        public static let notNow = "Not now"
    }

    public enum Picker {
        public static let title = "Correction"
        public static let prompt = "Find your headphones"
        public static let none = "None"
        public static func suggested(_ name: String) -> String { "Suggested for \(name)" }
        public static let header = "AutoEq"

        /// A result's line: "crinacle · in-ear · 3 more measurements".
        public static func row(source: String, form: String?, more: Int) -> String {
            var parts = [source]
            if let form { parts.append(form) }
            if more > 0 { parts.append(count(more, "more measurement", "more measurements")) }
            return parts.joined(separator: " · ")
        }

        public static let searching = "Searching…"
        public static let empty = "Search by name or model - \"hd650\" finds the Sennheiser HD 650. Corrections come from AutoEq, which works out one for each headphone it has a measurement of."
        public static func noMatch(_ query: String) -> String { "AutoEq has no headphones called \"\(query)\"." }
        public static let tryTheModel = "Try the model alone, like \"hd650\"."
    }

    public enum Profile {
        /// "Measured by crinacle, on a 711 rig (in-ear)." - without a rig, "Measured by crinacle."
        public static func measured(source: String, rig: String?, form: String?) -> String {
            guard let rig else { return "Measured by \(source)." }
            return "Measured by \(source), on a \(rig) rig" + (form.map { " (\($0))" } ?? "") + "."
        }

        public static func summary(filters: Int, preamp: Double) -> String {
            "\(count(filters, "filter")), preamp \(signedDB(preamp))"
        }

        public static func use(_ name: String) -> String { "Use for \(name)" }
        public static func used(_ name: String) -> String { "Used for \(name)" }
        public static let others = "Other measurements"
        public static func other(source: String, form: String?) -> String {
            ([source] + (form.map { [$0] } ?? [])).joined(separator: " · ")
        }
        public static let gitHub = "AutoEq on GitHub"
        public static let footer = "From AutoEq, which works out a correction from each measurement to make headphones sound neutral. It's a starting point: how in-ears sit in your ears changes what you hear."
        public static let notRead = "deadwax couldn't read this correction."
        public static let gone = "AutoEq doesn't have that measurement any more."
    }

    // ------------------------------------------------------------ Tone and presets (3.5, 3.6)

    public enum Tone {
        public static let header = "Tone"
        public static let preset = "Preset"
        public static let custom = "Custom"
        public static let saveAsPreset = "Save as Preset…"
        public static let footer = "Shapes the sound to your taste, on top of any correction. A preset moves the sliders; move them yourself to make your own."

        /// The Preset row's value: the preset's name, or "Custom".
        public static func value(_ tone: EQTone, in settings: EQSettings) -> String {
            toneName(tone, in: settings) ?? "Flat"
        }

        public static let bands = EQGraphic.names
        /// "31 hertz", "1 kilohertz", "16 kilohertz".
        public static func bandSaid(_ band: Int) -> String {
            let name = EQGraphic.names[band]
            return name.hasSuffix("k") ? "\(name.dropLast()) kilohertz" : "\(name) hertz"
        }
        public static let resetToZero = "Reset to 0"
    }

    public enum Presets {
        public static let title = "Preset"
        public static let custom = "Custom"
        public static let customNote = "Where you left the sliders."
        public static let yours = "Your presets"
        public static let rename = "Rename"
        public static let delete = "Delete"
        public static let saveTitle = "Save as Preset"
        public static let renameTitle = "Rename Preset"
        public static let name = "Name"
        public static let save = "Save"
        public static let cancel = "Cancel"

        public static func problem(_ p: EQNameProblem) -> String {
            switch p {
            case .empty: "Give it a name."
            case .taken(let name): "There's already a preset called \"\(name)\"."
            }
        }
    }

    // ------------------------------------------------------------ Advanced (3.8)

    public enum Advanced {
        public static let title = "Advanced"
        public static let footer = "Build a correction from filters of your own, set the preamp yourself, and import or export Equalizer APO files."

        public static func type(_ kind: EQKind) -> String {
            switch kind {
            case .peak: "Peak"
            case .lowShelf: "Low shelf"
            case .highShelf: "High shelf"
            case .lowPass: "Low pass"
            case .highPass: "High pass"
            case .bandPass: "Band pass"
            case .notch: "Notch"
            case .allPass: "All pass"
            }
        }

        /// Its width as the row shows it: "Q 0.70", "BW 1.0 oct", "12 dB/oct", or a shelf with none "S 0.9" (its
        /// type's default otherwise) - nil for a peak or an all pass with none, which plays nothing.
        public static func width(_ f: EQFilter) -> String? {
            if f.kind.isShelf, case .slope(let s)? = f.width, s != 0 { return "\(number(s)) dB/oct" }
            guard let w = f.playedWidth else { return nil }
            if !w.isBandwidthOrS { return "Q " + String(format: "%.2f", w.value) }
            return f.kind.isShelf ? "S " + String(format: "%.1f", w.value) : "BW " + String(format: "%.1f", w.value) + " oct"
        }

        /// The row's line: "105 Hz · +2.6 dB · Q 0.70" - no gain for a pass, notch or all pass; "Left" or "Right"
        /// after it for one ear's.
        public static func detail(_ f: EQFilter) -> String {
            var parts = ["\(number(f.fc)) Hz"]
            if f.kind.hasGain { parts.append(signedDB(f.gain)) }
            if let w = width(f) { parts.append(w) }
            if f.channel == .left { parts.append("Left") }
            if f.channel == .right { parts.append("Right") }
            return parts.joined(separator: " · ")
        }

        /// The handles' capsule: "Peak · 8903 Hz · +6.0 dB · Q 1.66".
        public static func capsule(_ f: EQFilter) -> String {
            var parts = [type(f.kind), "\(number(f.fc)) Hz"]
            if f.kind.hasGain { parts.append(signedDB(f.gain)) }
            if let w = width(f) { parts.append(w) }
            return parts.joined(separator: " · ")
        }

        /// A row for VoiceOver: "Filter 3: peak at 8903 hertz, plus 6 decibels, Q 1.66" (", left ear only").
        public static func said(_ f: EQFilter, number n: Int) -> String {
            var text = "Filter \(n): \(type(f.kind).lowercased()) at \(number(f.fc)) hertz"
            if f.kind.hasGain { text += ", " + decibelsSaid(f.gain) }
            if let w = width(f) { text += ", " + w }
            if f.channel == .left { text += ", left ear only" }
            if f.channel == .right { text += ", right ear only" }
            return text
        }

        public static func switchSaid(_ n: Int) -> String { "Filter \(n) on" }
        public static let on = "On"
        public static let off = "Off"
        public static let turnOn = "Turn On"
        public static let turnOff = "Turn Off"
        public static let above = "Above what this output plays, so it's left out."
        public static let addFilter = "Add Filter"
        public static let mostFilters = "64 filters is the most deadwax plays"
        public static let delete = "Delete"
    }

    public enum Editor {
        public static func title(_ n: Int) -> String { "Filter \(n)" }
        public static let type = "Type"
        public static let frequency = "Frequency"
        public static let hz = "Hz"
        public static let gain = "Gain"
        public static let dB = "dB"
        public static let q = "Q"
        public static let width = "Width"
        public static let octaves = "octaves"
        public static let slope = "Slope"
        public static let dBAnOctave = "dB an octave"
        public static let useQ = "Use Q instead"
        public static let ear = "Ear"
        public static let both = "Both"
        public static let left = "Left"
        public static let right = "Right"
        public static let on = "On"
        public static let deleteFilter = "Delete Filter"
        public static let frequencyRange = "Between 1 and 22000 Hz."
        public static let gainRange = "Between -30 and 30 dB."
        public static let qRange = "Between 0.01 and 100."
        public static let widthRange = "Between 0.01 and 10."

        /// A shelf read by its corner: "Its corner frequency, as Equalizer APO reads this shelf - it is centred at
        /// 131 Hz."
        public static func corner(centredAt f0: Double) -> String {
            "Its corner frequency, as Equalizer APO reads this shelf - it is centred at \(Int(f0.rounded())) Hz."
        }

        /// A slope too steep for the gain (1.3): the steepest it can be, rounded down so it is.
        public static func tooSteep(gain: Double) -> String? {
            guard let most = EQCookbook.steepestSlope(gain: gain) else { return nil }
            return "Too steep for this gain - at most \(String(format: "%.1f", (most * 10).rounded(.down) / 10)) dB an octave."
        }

        /// A field with no width shows its type's default: "0.71", "30", or "S 0.9" for a shelf.
        public static func placeholder(_ kind: EQKind) -> String? {
            switch kind {
            case .lowPass, .highPass, .bandPass: "0.71"
            case .notch: "30"
            case .lowShelf, .highShelf: "S 0.9"
            case .peak, .allPass: nil
            }
        }
    }

    public enum Preamp {
        public static let header = "Preamp"
        public static let automatic = "Automatic"
        public static let row = "Preamp"
        public static let automaticFooter = "Takes away the curve's highest boost, so loud songs don't clip."
        public static let handFooter = "Yours, for every song on this output."
        public static func value(_ dB: Double) -> String { signedDB(dB) }
    }

    // ------------------------------------------------------------ Export (3.11)

    public enum Export {
        public static let menu = "Export…"
        public static let whole = "The Whole Curve"
        public static let alone = "The Correction Alone"

        /// `<output name> EQ.txt`, the name with `/` and `:` taken out.
        public static func fileName(_ output: String) -> String {
            output.filter { $0 != "/" && $0 != ":" } + " EQ.txt"
        }

        /// The file's comment lines: who it's for and when, the correction, the tone (the whole curve's), and a
        /// converted GraphicEQ's line.
        public static func comments(output: String, day: String, correction: EQCorrection?, tone: String?) -> [String] {
            var lines = ["deadwax EQ for \(output), \(day)"]
            if let c = correction {
                lines.append(c.kind == .autoeq ? "Correction: \(c.name) (\(Correction.source(c)))" : "Correction: \(Correction.source(c))")
            }
            if let tone { lines.append("Tone: \(tone)") }
            if correction?.converted == true { lines.append("Converted from a GraphicEQ curve") }
            return lines
        }
    }

    // ------------------------------------------------------------ outputs (3.12)

    public enum Outputs {
        public static let speaker = "iPhone speaker"
        public static let headphones = "Headphones"
        public static let others = "Other outputs"
        public static let renameTitle = "Rename Output"
        public static let rename = "Rename"
        public static let forget = "Forget"
        public static let forgetThis = "Forget This Output"
        public static func forgetQuestion(_ name: String) -> String {
            "Forget \(name)? Its EQ is deleted. It starts Off next time it connects."
        }
        public static let cancel = "Cancel"
        public static let save = "Save"
    }

    // ------------------------------------------------------------ VoiceOver (3.14)

    public enum Said {
        public static let curve = "The EQ's curve"
        public static func graphTitle(_ name: String) -> String { "EQ curve for \(name)" }
        public static let frequencyAxis = "Frequency"
        public static let gainAxis = "Gain"
        public static let whatYouHear = "What you hear"
        public static let correction = "Correction"
        public static let tone = "Tone"
        public static func route(_ name: String) -> String { "EQ for \(name)" }
        public static let on = "EQ on"
        public static let off = "EQ off"
    }

    /// The curve's value for VoiceOver (3.14): its largest boost and cut of at least 1 dB, each with its region and
    /// rounded to 0.5 dB, then the preamp - "Up to 5.5 decibels louder in the bass; up to 2 decibels quieter in the
    /// upper mids. Preamp minus 6.5 decibels." - "Flat." when neither, "Off." when off. `shape` is each ear's curve
    /// without the preamp.
    public static func curveSummary(on: Bool, shape: [[EQChart.Point]], preamp: Double) -> String {
        guard on else { return "Off." }
        func halves(_ x: Double) -> String {
            let r = (x * 2).rounded() / 2
            return "\(number(r)) \(r == 1 ? "decibel" : "decibels")"
        }
        func region(_ f: Double) -> String {
            f < 250 ? "the bass" : f < 1000 ? "the lower mids" : f <= 4000 ? "the upper mids" : "the treble"
        }
        let (boost, cut) = EQChart.extremes(shape)
        var parts: [String] = []
        if let b = boost, b.db >= 1 { parts.append("up to \(halves(b.db)) louder in \(region(b.frequency))") }
        if let c = cut, c.db <= -1 { parts.append("up to \(halves(-c.db)) quieter in \(region(c.frequency))") }
        var text = parts.isEmpty ? "Flat." : "U" + parts.joined(separator: "; ").dropFirst() + "."
        if preamp != 0 { text += " Preamp \(decibelsSaid(preamp))." }
        return text
    }

    // ------------------------------------------------------------ Debug's EQ Section (3.13)

    public enum Debug {
        public static func port(_ p: EQRoutePort) -> String {
            switch p.port {
            case .builtInSpeaker: "Speaker"
            case .headphones: "Headphones"
            case .bluetoothA2DP: "Bluetooth (A2DP)"
            case .bluetoothLE: "Bluetooth (LE)"
            case .usbAudio: "USB"
            case .carAudio: "Car"
            case .airPlay: "AirPlay"
            case .hdmi: "HDMI"
            case .lineOut: "Line out"
            case .other: p.portType
            }
        }

        /// "Bluetooth (A2DP) · James's AirPods Pro · 60:F8:1D:…-tacl" - one line a port.
        public static func output(_ ports: [EQRoutePort]) -> String {
            ports.map { "\(port($0)) · \($0.name) · \($0.uid)" }.joined(separator: "\n")
        }

        public static let passing = "In the graph: passing every sample through"
        public static let filtering = "In the graph: filtering"
        public static let crossfading = "In the graph: crossfading"
        public static func notMade(_ words: String) -> String { "Not made: \(words)" }
        public static let outOfTheGraph = "Out of the graph while Off"
        /// Slice 2's: the output stopped, so the unit holds no render memory until it starts again (1.2).
        public static let stopped = "In the graph: the output is stopped"
        /// Slice 2's: no audio engine yet - it is made when something first plays.
        public static let noEngine = "No audio engine yet: it's made when something first plays"
        /// Slice 2's review: the unit's memory is made for a start and nothing has come through it yet (a moment, normally;
        /// stuck there, the output isn't asking the EQ for sound).
        public static let waiting = "In the graph: waiting for its first block of sound"

        /// Slice 2's review, the "Render block" row: whether iOS asked the unit for its render block - through the getter
        /// added with the Objective-C runtime (eq.md 1.2, 7). macOS asks twice as the unit is made and once a start.
        public static func renderBlockAsked(_ times: Int) -> String {
            switch times {
            case ..<1: "iOS hasn't asked for it, so no sound can go through the EQ"
            case 1: "iOS asked for it once"
            default: "iOS asked for it \(times) times"
            }
        }

        /// "10 filters for both ears + 10 tone bands; its top +6.3 dB at 8.9 kHz; preamp -6.4 dB (automatic)".
        public static func curve(both: Int, left: Int, right: Int, bands: Int, top: Double, at: Double, preamp: Double,
                                 automatic: Bool) -> String {
            var parts: [String] = []
            if left > 0 || right > 0 {
                var p = "\(count(both, "filter")) for both ears"
                if left > 0 { p += ", \(left) more for the left" }
                if right > 0 { p += ", \(right) more for the right" }
                parts.append(p)
            } else if both > 0 {
                parts.append("\(count(both, "filter")) for both ears")
            }
            if bands > 0 { parts.append(count(bands, "tone band")) }
            let what = parts.isEmpty ? "No filters" : parts.joined(separator: " + ")
            return "\(what); its top \(signedDB(top)) at \(hertz(at)); preamp \(signedDB(preamp)) (\(automatic ? "automatic" : "yours"))"
        }

        /// "48 kHz: 20 sections a channel" - "; 1 left out (above 23.5 kHz)".
        public static func atRate(_ rate: Double, sections: Int, leftOut: Int) -> String {
            var text = "\(hertz(rate)): \(count(sections, "section")) a channel"
            if leftOut > 0 { text += "; \(leftOut) left out (above \(hertz(EQLimits.topFraction * rate)))" }
            return text
        }

        /// "112 crossfades; 3 waited for the one before; 0 made for another rate".
        public static func changes(_ c: EQRenderCounters) -> String {
            "\(count(c.crossfades, "crossfade")); \(c.waited) waited for the one before; \(c.otherRate) made for another rate"
        }

        /// "AirPods Pro's curve, put in 0.1 ms before the output started".
        public static func startedWith(_ name: String, msBefore: Double) -> String {
            "\(name)'s curve, put in \(String(format: "%.1f", msBefore)) ms before the output started"
        }

        /// Slice 2's, while the only curve is Debug's test: "The test curve, put in 0.1 ms before the output started".
        public static func startedWithTest(msBefore: Double) -> String {
            "The test curve, put in \(String(format: "%.1f", msBefore)) ms before the output started"
        }

        /// "Off, put in 0.1 ms before the output started".
        public static func startedOff(msBefore: Double) -> String {
            "Off, put in \(String(format: "%.1f", msBefore)) ms before the output started"
        }

        public static let startedWithNothing = "Nothing put in: the output started passing every sample through"
        public static let notStarted = "The output hasn't started yet"

        /// "None since the output started" - "14 samples since the output started, the loudest +0.8 dBFS".
        public static func overFullScale(_ c: EQRenderCounters) -> String {
            guard c.overs > 0 else { return "None since the output started" }
            let loudest = 20 * log10(c.largest)
            let t = oneDecimal(loudest)
            return "\(count(c.overs, "sample")) since the output started, the loudest \(loudest > 0 && t != "0.0" ? "+" : "")\(t) dBFS"
        }

        /// "0.04 ms a block on average, 0.19 ms at worst - of 21.3 ms; refused blocks: 0".
        public static func render(meanMs: Double, worstMs: Double, blockMs: Double, refused: Int) -> String {
            "\(String(format: "%.2f", meanMs)) ms a block on average, \(String(format: "%.2f", worstMs)) ms at worst - of \(String(format: "%.1f", blockMs)) ms; refused blocks: \(refused)"
        }

        /// "eq.json: 3 outputs, 2 presets of yours, 4.1 KB".
        public static func kept(outputs: Int, presets: Int, bytes: Int) -> String {
            "eq.json: \(count(outputs, "output")), \(count(presets, "preset of yours", "presets of yours")), \(String(format: "%.1f", Double(bytes) / 1000)) KB"
        }

        public static func setAside(_ name: String) -> String {
            "eq.json couldn't be read, so it was set aside as \(name)"
        }

        /// The Curve row while the output's EQ is Off (slice 3).
        public static let curveOff = "Off"

        /// Slice 3's "Start took" row (slice 2's review, item 1): what the last start of the output spent putting its
        /// curve in - "0.031 ms, its curve made ahead" - or, at a rate the output hadn't started at before, "1.90 ms, its
        /// curve made then, for 44.1 kHz" (three decimals under 0.1 ms, two above).
        public static func startTook(ms: Double, ready: Bool, rate: Double) -> String {
            let time = ms < 0.1 ? String(format: "%.3f", ms) : String(format: "%.2f", ms)
            return ready ? "\(time) ms, its curve made ahead" : "\(time) ms, its curve made then, for \(hertz(rate))"
        }
        public static let startTookLabel = "Start took"

        public static let muffle = "Muffle what plays"
        /// Under the toggle (slice 2, check 0).
        public static let muffleFooter = "A test of the EQ's audio unit: a -24 dB high shelf at 2 kHz, put in through the unit itself, so what plays sounds muffled at once and plain again when it's off - with no click either way. Off, the unit passes every sample through untouched. It turns itself off when you leave Debug, and it's never kept."
        public static let header = "EQ"
    }
}
