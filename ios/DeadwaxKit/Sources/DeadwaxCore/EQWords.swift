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
