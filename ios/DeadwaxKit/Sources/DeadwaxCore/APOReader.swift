import Foundation

// Equalizer APO's files read as APO's source reads them (eq.md 0.3, 3.9, at 53d885f7f1: FilterEngine.cpp,
// BiQuadFilterFactory.cpp, PreampFilterFactory.cpp, ChannelFilterFactory.cpp, GraphicEQFilterFactory.cpp), so a file
// plays here as it plays there - and where APO would leave something out, deadwax leaves it out too and says so.
// ios/scripts/make-eq-fixtures.py reads the same rules written out again in Python (Fixtures/eq/apo.json).

/// Something read and left out, said in a listener's words (3.9's "Skipped").
public struct APONote: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// a leading `Device:` line
        case device
        /// lines for positions a phone doesn't have
        case channels
        /// a command APO doesn't know
        case unknown
        /// a filter APO leaves out
        case leftOut
        /// read from UTF-16, which APO doesn't read
        case utf16
    }

    public var kind: Kind
    /// the lines it is about; none for the file as a whole
    public var first: Int?
    public var last: Int?
    public var text: String
}

/// Why a whole file isn't imported (3.9's "Refused"): what would play differently here than in Equalizer APO.
public struct APORefusal: Error, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case nothing, tooBig, unreadable, crOnly, include, unsupported, devices, iir, frequencyHigh, frequencyLow, gain,
             q, width, slope, tooSteep, preamp, tooMany, graphicEmpty, graphicZero
    }

    public var kind: Kind
    public var line: Int?
    public var text: String
}

/// A `GraphicEQ:` line: its channel, its line and its points, sorted by frequency as APO sorts them.
public struct APOGraphicLine: Equatable, Sendable {
    public var channel: EQChannel
    public var line: Int
    public var points: [GraphicEQPoint]
}

/// A GraphicEQ converted for an ear (`all` when no line is one ear's): 3.10's fit.
public struct APOFit: Equatable, Sendable {
    public var ear: EQChannel
    public var fit: GraphicEQFit.Result
}

/// What a file plays: its filters (each with its id, from 1, in the file's order; a converted GraphicEQ's after),
/// its preamp as a shared part and each ear's offset, its GraphicEQ lines and their conversion, and what was skipped.
public struct APOReading: Equatable, Sendable {
    public var filters: [EQFilter]
    public var preamp: EQPreampParts
    public var graphic: [APOGraphicLine]
    public var fits: [APOFit]
    public var notes: [APONote]

    /// The correction's next filter id (4's `nextFilterID`).
    public var nextFilterID: Int { (filters.map(\.id).max() ?? 0) + 1 }
}

public enum APOReader {
    /// 256 KB: an EQ file is a few KB.
    public static let maxBytes = 256 * 1024

    public static func read(_ data: Data, pasted: Bool = false) -> Result<APOReading, APORefusal> {
        do {
            return .success(try reading([UInt8](data), pasted: pasted))
        } catch {
            return .failure(error)
        }
    }

    // ------------------------------------------------------------ the text

    typealias Line = [Unicode.Scalar]

    static let lf = Unicode.Scalar(UInt8(0x0A))
    static let cr = Unicode.Scalar(UInt8(0x0D))
    static let nbsp = Unicode.Scalar(0xA0)!
    static let replacement = Unicode.Scalar(0xFFFD)!

    /// Windows-1252's 0x80-0x9F; every other byte is its own code point (APO falls back to the PC's ANSI page).
    static let cp1252: [UInt8: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
        0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
        0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    /// The lines (split at LF, one CR before it dropped), and whether they were UTF-16.
    static func lines(_ data: [UInt8]) throws(APORefusal) -> ([Line], Bool) {
        if data.count >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF)) {
            let little = data[0] == 0xFF
            let body = data.dropFirst(2)
            guard body.count % 2 == 0 else { throw EQWords.Import.unreadable }
            var units: [UInt16] = []
            units.reserveCapacity(body.count / 2)
            var i = body.startIndex
            while i < body.endIndex {
                let a = UInt16(body[i])
                let b = UInt16(body[i + 1])
                units.append(little ? a | b << 8 : a << 8 | b)
                i += 2
            }
            var text: [Unicode.Scalar] = []
            var failed = false
            var parser = Unicode.UTF16.ForwardParser()
            var iterator = units.makeIterator()
            loop: while true {
                switch parser.parseScalar(from: &iterator) {
                case .valid(let encoded): text.append(Unicode.UTF16.decode(encoded))
                case .emptyInput: break loop
                case .error: failed = true; break loop
                }
            }
            if failed { throw EQWords.Import.unreadable }
            if !text.contains(lf) && text.dropLast().contains(cr) { throw EQWords.Import.crOnly }
            return (text.split(separator: lf, omittingEmptySubsequences: false).map { Line($0.last == cr ? $0.dropLast() : $0) }, true)
        }
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if !bytes.contains(0x0A) && bytes.dropLast().contains(0x0D) { throw EQWords.Import.crOnly }
        return (bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map { (raw: ArraySlice<UInt8>) -> Line in
            let line = raw.last == 0x0D ? raw.dropLast() : raw
            let decoded = Array(String(decoding: line, as: UTF8.self).unicodeScalars)
            if !decoded.contains(replacement) { return decoded }
            return line.map { Unicode.Scalar(cp1252[$0] ?? UInt32($0))! }
        }, false)
    }

    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == lf || c == cr || c.value == 0x0B || c.value == 0x0C
    }

    static func isRun(_ c: Unicode.Scalar) -> Bool {
        c == "-" || c == "+" || c == "." || c == "e" || c == "E" || (c >= "0" && c <= "9")
    }

    static func isDigit(_ c: Unicode.Scalar) -> Bool { c >= "0" && c <= "9" }

    static func isLetter(_ c: Unicode.Scalar) -> Bool { (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") }

    static func lower(_ c: Unicode.Scalar) -> Unicode.Scalar {
        c >= "A" && c <= "Z" ? Unicode.Scalar(c.value + 32)! : c
    }

    static func upper(_ c: Unicode.Scalar) -> Unicode.Scalar {
        c >= "a" && c <= "z" ? Unicode.Scalar(c.value - 32)! : c
    }

    static func trimmed(_ s: some Collection<Unicode.Scalar>) -> Line {
        let a = Array(s)
        guard let first = a.firstIndex(where: { !isSpace($0) }) else { return [] }
        let last = a.lastIndex(where: { !isSpace($0) })!
        return Array(a[first...last])
    }

    static func text(_ s: some Sequence<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s)
        return String(view)
    }

    static func scalars(_ s: String) -> Line { Array(s.unicodeScalars) }

    static func replacingCommas(_ s: Line) -> Line { s.map { $0 == "," ? "." : $0 } }

    // ------------------------------------------------------------ APO's patterns, matched as its regexes match

    /// A pattern's parts. Each run is greedy and nothing after it can begin inside it, so matching never needs to back
    /// up - the leftmost match is Python's `re`'s and APO's `std::wregex`'s.
    enum Part {
        /// whitespace, at least `least` of it
        case space(least: Int)
        /// these characters, with their case or (ASCII) without
        case word(String, anyCase: Bool)
        /// a captured run of `-+0-9.eE` (with a non-breaking space too, for a frequency)
        case number(frequency: Bool)
        /// a captured run of ASCII letters (a filter's type)
        case letters
        /// one of these words, captured, case aside (`on|off`)
        case either([String])
        /// these parts if they match, else nothing
        case optional([Part])
        /// any one ASCII letter
        case letter
    }

    struct Match {
        var start: Int
        var end: Int
        var capture: Range<Int>?
    }

    static func match(_ parts: [Part], _ s: Line, at start: Int) -> Match? {
        var i = start
        var capture: Range<Int>?
        for part in parts {
            switch part {
            case .space(let least):
                var j = i
                while j < s.count && isSpace(s[j]) { j += 1 }
                if j - i < least { return nil }
                i = j
            case .word(let w, let anyCase):
                for c in w.unicodeScalars {
                    guard i < s.count, anyCase ? lower(s[i]) == lower(c) : s[i] == c else { return nil }
                    i += 1
                }
            case .number(let frequency):
                var j = i
                while j < s.count && (isRun(s[j]) || (frequency && s[j] == nbsp)) { j += 1 }
                if j == i { return nil }
                capture = i..<j
                i = j
            case .letters:
                var j = i
                while j < s.count && isLetter(s[j]) { j += 1 }
                if j == i { return nil }
                capture = i..<j
                i = j
            case .either(let words):
                var found = false
                for w in words {
                    let ws = scalars(w)
                    if i + ws.count <= s.count && zip(s[i..<(i + ws.count)], ws).allSatisfy({ lower($0) == lower($1) }) {
                        capture = i..<(i + ws.count)
                        i += ws.count
                        found = true
                        break
                    }
                }
                if !found { return nil }
            case .optional(let inner):
                if let m = match(inner, s, at: i) {
                    i = m.end
                    if let c = m.capture { capture = c }
                }
            case .letter:
                guard i < s.count && isLetter(s[i]) else { return nil }
                i += 1
            }
        }
        return Match(start: start, end: i, capture: capture)
    }

    /// The leftmost match anywhere.
    static func search(_ parts: [Part], _ s: Line) -> Match? {
        for start in 0...s.count {
            if let m = match(parts, s, at: start) { return m }
        }
        return nil
    }

    static let on: [Part] = [.space(least: 0), .word("ON", anyCase: false), .space(least: 1), .letters]
    static let off: [Part] = [.space(least: 0), .word("OFF", anyCase: false), .space(least: 1), .letters]
    static let fc: [Part] = [.space(least: 1), .word("Fc", anyCase: false), .space(least: 0), .number(frequency: true),
                             .space(least: 0), .word("H", anyCase: false), .space(least: 0), .word("z", anyCase: false)]
    static let gain: [Part] = [.space(least: 1), .word("Gain", anyCase: false), .space(least: 0), .number(frequency: false),
                               .space(least: 0), .word("dB", anyCase: false)]
    static let q: [Part] = [.space(least: 1), .word("Q", anyCase: false), .space(least: 0), .number(frequency: false)]
    static let bw: [Part] = [.space(least: 1), .word("BW", anyCase: false), .space(least: 1), .word("Oct", anyCase: false),
                             .space(least: 0), .number(frequency: false)]
    static let slope: [Part] = [.space(least: 0), .number(frequency: false), .space(least: 0), .word("dB", anyCase: false)]

    // the near misses, for the notes: the same, case aside, or a unit missing
    static let fcAnyCase: [Part] = [.space(least: 1), .word("fc", anyCase: true), .space(least: 0), .number(frequency: true),
                                    .space(least: 0), .word("h", anyCase: true), .space(least: 0), .word("z", anyCase: true)]
    static let fcNoHz: [Part] = [.space(least: 1), .word("Fc", anyCase: false), .space(least: 0), .number(frequency: true)]
    static let fcNoHzAnyCase: [Part] = [.space(least: 1), .word("fc", anyCase: true), .space(least: 0), .number(frequency: true)]
    static let gainAnyCase: [Part] = [.space(least: 1), .word("gain", anyCase: true), .space(least: 0), .number(frequency: false),
                                      .optional([.space(least: 0), .word("db", anyCase: true)])]
    static let qAnyCase: [Part] = [.space(least: 1), .word("q", anyCase: true), .space(least: 0), .number(frequency: false)]
    static let bwAnyCase: [Part] = [.space(least: 1), .word("bw", anyCase: true), .space(least: 1), .word("oct", anyCase: true),
                                    .space(least: 0), .number(frequency: false)]
    static let onOffAnyCase: [Part] = [.space(least: 0), .either(["on", "off"]), .space(least: 1), .letter]

    // ------------------------------------------------------------ numbers

    /// Where a decimal number starting at `i` ends, as C's `wcstod` reads one (sign, digits with a point, an exponent
    /// only when digits follow it) - nil when none starts there.
    static func decimalEnd(_ s: Line, from i: Int) -> Int? {
        var j = i
        if j < s.count && (s[j] == "+" || s[j] == "-") { j += 1 }
        var k = j
        while k < s.count && isDigit(s[k]) { k += 1 }
        if k > j {
            if k < s.count && s[k] == "." {
                k += 1
                while k < s.count && isDigit(s[k]) { k += 1 }
            }
        } else if j + 1 < s.count && s[j] == "." && isDigit(s[j + 1]) {
            k = j + 1
            while k < s.count && isDigit(s[k]) { k += 1 }
        } else {
            return nil
        }
        if k < s.count && (s[k] == "e" || s[k] == "E") {
            var e = k + 1
            if e < s.count && (s[e] == "+" || s[e] == "-") { e += 1 }
            if e < s.count && isDigit(s[e]) {
                while e < s.count && isDigit(s[e]) { e += 1 }
                k = e
            }
        }
        return k
    }

    static func value(_ s: some Collection<Unicode.Scalar>) -> Double {
        Double(text(s)) ?? 0
    }

    /// `wcstod` of a run: its longest start that reads as a number, else 0 (`6.5.1` is 6.5, `-` is 0).
    static func wcstod(_ run: Line) -> Double {
        guard let end = decimalEnd(run, from: 0) else { return 0 }
        return value(run[0..<end])
    }

    /// BiQuadFilterFactory::getFreq: non-breaking spaces dropped; no number is -1; a number of five or more
    /// characters, no exponent, with a point fourth from its end is thousands (REW's `1.000`).
    static func frequency(_ run: Line) -> Double {
        let s = run.filter { $0 != nbsp }
        guard let end = decimalEnd(s, from: 0) else { return -1 }
        var result = value(s[0..<end])
        if s.count >= 5 && !s.contains("e") && !s.contains("E") && s[s.count - 4] == "." { result *= 1000 }
        return result
    }

    // ------------------------------------------------------------ the file

    static let refusedCommands = ["Include", "Convolution", "Delay", "Copy", "Eval", "If", "ElseIf", "Else", "EndIf",
                                  "Stage", "VSTPlugin", "LoudnessCorrection"]
    static let knownCommands = ["Preamp", "Channel", "GraphicEQ", "Device"] + refusedCommands
    /// APO's types in its factory's order, for the note on a type written in another case.
    static let typeOrder = ["PK", "PEQ", "Modal", "LP", "LPQ", "HP", "HPQ", "BP", "LS", "HS", "LSC", "HSC", "NO", "AP"]

    static func reading(_ data: [UInt8], pasted: Bool) throws(APORefusal) -> APOReading {
        if data.count > maxBytes { throw EQWords.Import.tooBig(bytes: data.count) }
        let (lines, utf16) = try lines(data)
        var notes: [APONote] = []
        var filters: [EQFilter] = []
        var graphic: [APOGraphicLine] = []
        var all = 0.0, left = 0.0, right = 0.0
        var readPreamp = false
        var chosenLeft = true, chosenRight = true
        var group: (words: [Line], first: Int?, last: Int?)?
        var playingSeen = false
        var devices = 0

        func closeGroup() {
            if let g = group, let first = g.first {
                notes.append(EQWords.Import.channels(first: first, last: g.last ?? first, words: g.words))
            }
        }

        for (index, line) in lines.enumerated() {
            let n = index + 1
            guard let colon = line.firstIndex(of: ":") else {
                let t = trimmed(line)
                if !t.isEmpty && t[0] != "#" { notes.append(EQWords.Import.unknown(line: n, text: cut(line), hint: nil)) }
                continue
            }
            //? compared scalar for scalar, as APO compares them - never as Swift compares Strings (canonically)
            let key = trimmed(line[..<colon])
            let value = Array(line[(colon + 1)...])
            if key.first == "#" { continue }
            if key == scalars("Device") {
                if devices > 0 || playingSeen { throw EQWords.Import.devices(line: n) }
                devices += 1
                notes.append(EQWords.Import.device(line: n, text: cut(line)))
                continue
            }
            if key == scalars("Include") { throw EQWords.Import.include(line: n, what: text(trimmed(value))) }
            if refusedCommands.contains(where: { scalars($0) == key }) {
                throw EQWords.Import.unsupported(line: n, command: text(key))
            }
            guard key == scalars("Preamp") || key == scalars("Channel") || key == scalars("GraphicEQ")
                || key.starts(with: scalars("Filter")) else {
                notes.append(EQWords.Import.unknown(line: n, text: cut(line), hint: caseHint(key)))
                continue
            }
            playingSeen = true
            if key == scalars("Channel") {
                closeGroup()
                let words = channelWords(value)
                (chosenLeft, chosenRight) = selection(words)
                group = chosenLeft || chosenRight ? nil : (words, nil, nil)
                continue
            }
            if !chosenLeft && !chosenRight {
                group!.first = group!.first ?? n
                group!.last = n
                continue
            }
            let channel: EQChannel = chosenLeft && chosenRight ? .all : (chosenLeft ? .left : .right)
            if key == scalars("Preamp") {
                let v = replacingCommas(value)
                var i = 0
                while i < v.count && isSpace(v[i]) { i += 1 }
                guard let end = decimalEnd(v, from: i) else {
                    notes.append(EQWords.Import.unknown(line: n, text: cut(line), hint: nil))
                    continue
                }
                let amount = self.value(v[i..<end])
                if !(-EQLimits.filePreamp <= amount && amount <= EQLimits.filePreamp) {
                    throw EQWords.Import.preamp(line: n, dB: amount)
                }
                switch channel {
                case .all: all += amount
                case .left: left += amount
                case .right: right += amount
                }
                readPreamp = true
            } else if key == scalars("GraphicEQ") {
                let v = value.contains(".") ? value : replacingCommas(value)
                var numbers: [Double] = []
                var i = 0
                while i < v.count {
                    if isRun(v[i]) {
                        var j = i
                        while j < v.count && isRun(v[j]) { j += 1 }
                        numbers.append(wcstod(Array(v[i..<j])))
                        i = j
                    } else {
                        i += 1
                    }
                }
                let pairs = stride(from: 0, to: numbers.count - 1, by: 2).map { GraphicEQPoint(numbers[$0], numbers[$0 + 1]) }
                if pairs.isEmpty { throw EQWords.Import.graphicEmpty(line: n) }
                if let zero = pairs.first(where: { !($0.frequency > 0) }) {
                    throw EQWords.Import.graphicZero(line: n, frequency: zero.frequency)
                }
                //? a filter's limit (added in slice 1, where 3.9 was silent): beyond it the fit's sums overflow to NaN
                if let loud = pairs.first(where: { !(-EQLimits.gain <= $0.gain && $0.gain <= EQLimits.gain) }) {
                    throw EQWords.Import.gain(line: n, dB: loud.gain)
                }
                let sorted = pairs.enumerated().sorted {
                    $0.element.frequency < $1.element.frequency
                        || ($0.element.frequency == $1.element.frequency && $0.offset < $1.offset)
                }.map(\.element)
                graphic.append(APOGraphicLine(channel: channel, line: n, points: sorted))
            } else {
                let (made, note) = try filter(line: n, value: value, channel: channel)
                if let note { notes.append(note) }
                if var made {
                    made.id = filters.count + 1
                    filters.append(made)
                }
            }
        }
        closeGroup()

        var fits: [APOFit] = []
        if !graphic.isEmpty {
            let ears: [EQChannel] = graphic.contains { $0.channel != .all } ? [.left, .right] : [.all]
            for ear in ears {
                let lines = graphic.filter { $0.channel == .all || $0.channel == ear }.map(\.points)
                let fit = GraphicEQFit.fit(lines)
                filters += fit.filters(channel: ear, firstID: filters.count + 1)
                switch ear {
                case .all: all += fit.median
                case .left: left += fit.median
                case .right: right += fit.median
                }
                fits.append(APOFit(ear: ear, fit: fit))
            }
        }

        for ear in [EQChannel.left, .right] {
            let count = filters.filter { $0.channel == .all || $0.channel == ear }.count
            if count > EQLimits.filtersPerEar { throw EQWords.Import.tooMany(count: count) }
        }
        if !readPreamp && filters.isEmpty && graphic.isEmpty { throw EQWords.Import.nothing(pasted: pasted) }

        //? Python's max(left, right): the first unless the second is larger
        let extra = right > left ? right : left
        let parts = EQPreampParts(all: all + extra, left: left - extra, right: right - extra)
        var ordered = notes.enumerated().sorted {
            ($0.element.first ?? 0, $0.offset) < ($1.element.first ?? 0, $1.offset)
        }.map(\.element)
        if utf16 { ordered.insert(EQWords.Import.utf16, at: 0) }
        return APOReading(filters: filters, preamp: parts, graphic: graphic, fits: fits, notes: ordered)
    }

    /// A command APO knows in another case: the one it reads.
    static func caseHint(_ key: Line) -> String? {
        let lowered = key.map(lower)
        for known in knownCommands where lowered == scalars(known).map(lower) { return known }
        if lowered.starts(with: scalars("filter")) { return "Filter" }
        return nil
    }

    /// A line for a note: trimmed, and cut at 40 characters with an ellipsis.
    static func cut(_ line: Line) -> String {
        var t = trimmed(line)
        if t.count > 40 { t = trimmed(t.prefix(40)) + [Unicode.Scalar(0x2026)!] }
        return text(t)
    }

    /// ChannelFilterFactory: split at spaces only, upper-cased.
    static func channelWords(_ value: Line) -> [Line] {
        value.map(upper).split(separator: " ").map { Line($0) }
    }

    /// Which of a phone's two channels a `Channel:` line selects, as APO selects them on a stereo device.
    static func selection(_ words: [Line]) -> (Bool, Bool) {
        var l = false, r = false
        for s in words {
            if s == scalars("ALL") {
                l = true
                r = true
            } else if let c = s.first, isDigit(c) {
                let digits = s.prefix { isDigit($0) }
                switch Int(text(digits)) {
                case 1: l = true
                case 2: r = true
                default: break
                }
            } else if s == ["L"] {
                l = true
            } else if s == ["R"] {
                r = true
            }
        }
        return (l, r)
    }

    static func says(_ m: Match, in s: Line, reads: String) -> String {
        EQWords.Import.says(text(trimmedFront(s[m.start..<m.end])), reads: reads)
    }

    static func trimmedFront(_ s: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        s.drop { isSpace($0) }
    }

    /// One `Filter` line: the filter, or a note on why APO leaves it out (or neither, for `None`).
    static func filter(line n: Int, value: Line, channel: EQChannel) throws(APORefusal) -> (EQFilter?, APONote?) {
        let v = replacingCommas(value)
        var isOn = true
        var m = match(on, v, at: 0)
        if m == nil {
            isOn = false
            m = match(off, v, at: 0)
        }
        guard let m, let typeRange = m.capture else {
            var near: String?
            if let miss = match(onOffAnyCase, v, at: 0), let said = miss.capture {
                let written = text(v[said])
                near = EQWords.Import.says(written, reads: text(scalars(written).map(upper)))
            }
            return (nil, EQWords.Import.leftOut(line: n, kind: nil, reason: .onOff, near: near))
        }
        let written = text(v[typeRange])
        let rest = Array(v[m.end...])
        let type = Array(v[typeRange])
        if type == scalars("None") { return (nil, nil) }
        if type == scalars("IIR") { throw EQWords.Import.iir(line: n) }
        guard let kind = EQKind.written.first(where: { scalars($0.key) == type })?.value else {
            var near: String?
            for known in typeOrder where scalars(known).map(lower) == v[typeRange].map(lower) {
                near = EQWords.Import.knowsType(known)
            }
            return (nil, EQWords.Import.leftOut(line: n, kind: nil, reason: .type(written), near: near))
        }

        var errors: [(EQWords.Import.Missing, String?)] = []
        var fcValue = 0.0
        if let found = search(fc, rest), let r = found.capture {
            fcValue = frequency(Array(rest[r]))
        } else {
            var near: String?
            if let miss = search(fcAnyCase, rest) {
                near = says(miss, in: rest, reads: "Fc \(text(rest[miss.capture!])) Hz")
            } else if search(fcNoHz, rest) != nil {
                near = EQWords.Import.noHz
            } else if let miss = search(fcNoHzAnyCase, rest) {
                near = says(miss, in: rest, reads: "Fc \(text(rest[miss.capture!])) Hz")
            }
            errors.append((.frequency, near))
        }
        var gainValue = 0.0
        if let found = search(gain, rest), let r = found.capture {
            if kind != .lowPass && kind != .highPass && kind != .notch && kind != .allPass {
                gainValue = wcstod(Array(rest[r]))
            }
        } else if kind.hasGain {
            var near: String?
            if let miss = search(gainAnyCase, rest) {
                near = says(miss, in: rest, reads: "Gain \(text(rest[miss.capture!])) dB")
            }
            errors.append((.gain, near))
        }
        var width: EQWidth?
        let foundQ = search(q, rest)
        if let r = foundQ?.capture { width = .q(wcstod(Array(rest[r]))) }
        let foundBW = search(bw, rest)
        if let r = foundBW?.capture, !kind.isShelf { width = .bandwidth(wcstod(Array(rest[r]))) }
        if kind.isShelf, let found = match(slope, rest, at: 0), let r = found.capture { width = .slope(wcstod(Array(rest[r]))) }
        if (kind == .peak || kind == .allPass) && (width == nil || width!.value == 0) {
            var near: String?
            if foundQ == nil, let miss = search(qAnyCase, rest) {
                near = says(miss, in: rest, reads: "Q \(text(rest[miss.capture!]))")
            } else if foundBW == nil, let miss = search(bwAnyCase, rest) {
                near = says(miss, in: rest, reads: "BW Oct \(text(rest[miss.capture!]))")
            }
            errors.append((.width, near))
        }
        if let (reason, near) = errors.first {
            return (nil, EQWords.Import.leftOut(line: n, kind: kind, reason: reason, near: near))
        }

        if fcValue < EQLimits.frequency.lowerBound { throw EQWords.Import.frequencyLow(line: n) }
        if fcValue > EQLimits.frequency.upperBound { throw EQWords.Import.frequencyHigh(line: n, hz: fcValue) }
        if kind.hasGain && !(-EQLimits.gain <= gainValue && gainValue <= EQLimits.gain) {
            throw EQWords.Import.gain(line: n, dB: gainValue)
        }
        switch width {
        case .q(let v)? where v != 0 && !EQLimits.q.contains(v):
            throw EQWords.Import.q(line: n, q: v)
        case .bandwidth(let v)? where v != 0 && !EQLimits.bandwidth.contains(v):
            throw EQWords.Import.width(line: n, octaves: v)
        case .slope(let v)? where v < 0:
            throw EQWords.Import.slope(line: n, dB: v)
        case .slope(let v)? where v > 0 && EQCookbook.shelfRadicand(gain: gainValue, s: v / 12) <= 0:
            throw EQWords.Import.tooSteep(line: n, kind: kind, slope: v, gain: gainValue)
        default:
            break
        }
        var corner = false
        if kind.isShelf && type.last != "C", let width, width.value != 0 {
            if case .bandwidth = width {} else { corner = true }
        }
        return (EQFilter(kind: kind, written: written, fc: fcValue, gain: gainValue, width: width, corner: corner,
                         channel: channel, on: isOn), nil)
    }
}
