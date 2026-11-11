import Foundation

// JSON as JavaScript reads and writes it - for resume's snapshot (Resume.swift), which the web app writes with
// JSON.stringify and reads with JSON.parse, and which the phone must write as the very same text and read as the
// web reads it: a snapshot saved by one is put back by the other (notes/ios.md, the plan's risk R12).
//
// Not JSONEncoder and JSONDecoder: the encoder leaves out every nil (the snapshot keeps `albumId: null` and
// leaves `paged` out - both on purpose), writes `\/`, `200.0`-style numbers and its own key order; the decoder
// blurs 1 and true through NSNumber on a Mac and differs between platforms. Both halves here are written out by
// hand, so the phone's text is the web's to the byte on a Mac and on Linux alike:
//
//  - reading: ECMA-404's grammar exactly as JSON.parse takes it (whitespace only space, tab, LF and CR; no BOM, no
//    trailing comma, no leading zero), a repeated key's last value kept, numbers as Doubles (an exponent past a
//    Double is an infinity, as JavaScript's), strings unescaped to UTF-16 units. Two differences, neither met by
//    anything a writer makes: a lone surrogate (which JavaScript keeps) becomes U+FFFD, since a Swift string can't
//    hold one - the same length in UTF-16 units; and nesting past `depthLimit` is refused (JavaScript goes on until
//    its stack runs out) - the server's own json.loads refuses far less deep.
//  - writing: JSON.stringify's escapes (`"`, `\`, \b \f \n \r \t, any other control as a six-character escape in
//    lowercase hex, everything else as it is - no `\/`) and its numbers (JavaScript's Number to String: integers in
//    full below 1e21, else the shortest digits that read back, `1e-7`, `1.5e+300`).
//
// Named WebJSON, not JSText: the Library port has a JSText of its own (JavaScript's string methods).

public enum WebJSON {
    /// A JSON value as JSON.parse makes one. An object is a dictionary: the reader's checks look keys up, never
    /// walk them in order (`Writer` keeps the order for what is written).
    public enum Value: Sendable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([Value])
        case object([String: Value])

        public subscript(key: String) -> Value? {
            if case .object(let fields) = self { return fields[key] }
            return nil
        }
    }

    /// The deepest arrays and objects go inside one another before a text is refused.
    public static let depthLimit = 1000

    /// JSON.parse(text), or nil where it would throw.
    public static func parse(_ text: String) -> Value? {
        var reader = Reader(units: Array(text.utf16))
        reader.skipSpace()
        guard let value = reader.value() else { return nil }
        reader.skipSpace()
        return reader.at == reader.units.count ? value : nil
    }

    /// JSON.stringify(text): the string quoted and escaped.
    public static func quoted(_ text: String) -> String {
        var writer = Writer()
        writer.string(text)
        return writer.text
    }

    /// JSON.stringify(number): JavaScript's own text for it - `null` for NaN and the infinities, `0` for -0.
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == 0 { return "0" }
        //? an integer below 2^53 is its own shortest digits; above it JavaScript writes the shortest digits padded
        //? with zeros (2^60 is "1152921504606847000"), which shortest() lays out the same way
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 { return String(Int64(value)) }
        return shortest(value)
    }

    /// The names an object has before anything is put in it (Object.prototype's own properties, as
    /// `Object.getOwnPropertyNames` lists them): JavaScript's `name in object` says true for each of them. The
    /// snapshot's writer meets this - see toSave in Resume.swift.
    public static let prototypeNames: Set<String> = [
        "constructor", "__defineGetter__", "__defineSetter__", "hasOwnProperty", "__lookupGetter__",
        "__lookupSetter__", "isPrototypeOf", "propertyIsEnumerable", "toString", "valueOf", "__proto__",
        "toLocaleString",
    ]

    /// Whether `key` is an array index (a canonical decimal integer 0...4294967294), the keys a JavaScript object
    /// lists first, in ascending order, ahead of the rest in the order they were put in.
    public static func isArrayIndex(_ key: String) -> Bool {
        let digits = Array(key.utf8)
        guard !digits.isEmpty, digits.count <= 10, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return false }
        if digits.count > 1 && digits[0] == 0x30 { return false }
        return (UInt64(key) ?? .max) <= 4_294_967_294
    }

    /// The keys of an object in the order JavaScript lists them: array indexes ascending, then the rest as `keys`
    /// has them (the order they were put in).
    public static func ordered(_ keys: [String]) -> [String] {
        let indexes = keys.filter(isArrayIndex).sorted { (UInt64($0) ?? 0) < (UInt64($1) ?? 0) }
        return indexes + keys.filter { !isArrayIndex($0) }
    }

    /// Number::toString for a finite non-zero Double that isn't an integer below 2^53: the shortest digits that
    /// read back (Swift's `description` makes the same choice JavaScript's does - the shortest, nearest the value),
    /// laid out as JavaScript lays them out.
    static func shortest(_ value: Double) -> String {
        let negative = value < 0
        let text = abs(value).description
        let parts = text.split(separator: "e", maxSplits: 1)
        let mantissa = parts[0]
        var exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let halves = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(halves[0])
        let fraction = halves.count > 1 ? String(halves[1]) : ""
        var digits = Array(whole + fraction)
        exponent -= fraction.count
        while digits.count > 1 && digits.first == "0" { digits.removeFirst() }
        while digits.count > 1 && digits.last == "0" {
            digits.removeLast()
            exponent += 1
        }
        //? the value is digits x 10^exponent; JavaScript's n is where the point goes: digits x 10^(n - k)
        let k = digits.count
        let n = exponent + k
        let s = String(digits)
        var out: String
        if k <= n && n <= 21 {
            out = s + String(repeating: "0", count: n - k)
        } else if 0 < n && n <= 21 {
            out = String(digits[0..<n]) + "." + String(digits[n...])
        } else if -6 < n && n <= 0 {
            out = "0." + String(repeating: "0", count: -n) + s
        } else {
            let e = n - 1
            let sign = e < 0 ? "-" : "+"
            out = k == 1 ? s : String(digits[0]) + "." + String(digits[1...])
            out += "e" + sign + String(abs(e))
        }
        return negative ? "-" + out : out
    }

    /// JSON.stringify's text, built a piece at a time in the order it is written - the order JavaScript would
    /// list the same object's keys in. UTF-8 bytes until the end: escaping looks only at ASCII, so the rest is
    /// copied.
    struct Writer {
        private var bytes: [UInt8] = []

        var text: String { String(decoding: bytes, as: UTF8.self) }

        mutating func raw(_ text: String) {
            bytes.append(contentsOf: text.utf8)
        }

        mutating func string(_ text: String) {
            bytes.append(0x22)
            for byte in text.utf8 {
                switch byte {
                case 0x22: bytes.append(contentsOf: [0x5C, 0x22])
                case 0x5C: bytes.append(contentsOf: [0x5C, 0x5C])
                case 0x08: bytes.append(contentsOf: [0x5C, 0x62])
                case 0x0C: bytes.append(contentsOf: [0x5C, 0x66])
                case 0x0A: bytes.append(contentsOf: [0x5C, 0x6E])
                case 0x0D: bytes.append(contentsOf: [0x5C, 0x72])
                case 0x09: bytes.append(contentsOf: [0x5C, 0x74])
                case 0x00..<0x20:
                    let hex = Array("0123456789abcdef".utf8)
                    bytes.append(contentsOf: [0x5C, 0x75, 0x30, 0x30, hex[Int(byte >> 4)], hex[Int(byte & 15)]])
                default: bytes.append(byte)
                }
            }
            bytes.append(0x22)
        }

        mutating func nullableString(_ text: String?) {
            if let text { string(text) } else { raw("null") }
        }

        mutating func int(_ value: Int) {
            raw(String(value))
        }

        mutating func number(_ value: Double) {
            raw(WebJSON.number(value))
        }

        mutating func bool(_ value: Bool) {
            raw(value ? "true" : "false")
        }

        /// `"key":` - the key escaped as any string.
        mutating func key(_ name: String) {
            string(name)
            bytes.append(0x3A)
        }

        mutating func comma() {
            bytes.append(0x2C)
        }

        /// `[` items `]`, each written by `item`, commas between.
        mutating func array<T>(_ items: [T], _ item: (inout Writer, T) -> Void) {
            bytes.append(0x5B)
            for (place, value) in items.enumerated() {
                if place > 0 { comma() }
                item(&self, value)
            }
            bytes.append(0x5D)
        }

        mutating func open() { bytes.append(0x7B) }
        mutating func close() { bytes.append(0x7D) }
    }

    /// JSON.parse's reader, over the text's UTF-16 units as JavaScript sees them.
    private struct Reader {
        let units: [UInt16]
        var at = 0

        init(units: [UInt16]) {
            self.units = units
        }

        mutating func skipSpace() {
            while at < units.count {
                switch units[at] {
                case 0x20, 0x09, 0x0A, 0x0D: at += 1
                default: return
                }
            }
        }

        /// An array or object being read: what it holds so far, and (an object) the key its next value goes under.
        private struct Open {
            let isObject: Bool
            var items: [Value] = []
            var fields: [String: Value] = [:]
            var key = ""
        }

        /// One value, read without recursion - a stack of what is open, so nesting is bounded by `depthLimit` and
        /// never by the thread's stack (a test's or a background thread's is 512 KB; a recursive reader in a debug
        /// build ran out of it below 900 deep).
        mutating func value() -> Value? {
            var open: [Open] = []
            while true {
                skipSpace()
                guard at < units.count else { return nil }
                var done: Value
                switch units[at] {
                case 0x7B, 0x5B:
                    let isObject = units[at] == 0x7B
                    //? the outermost is depth 1: `depthLimit` inside one another, and no more
                    guard open.count < WebJSON.depthLimit else { return nil }
                    at += 1
                    skipSpace()
                    if at < units.count && units[at] == (isObject ? 0x7D : 0x5D) {
                        at += 1
                        done = isObject ? .object([:]) : .array([])
                    } else {
                        var frame = Open(isObject: isObject)
                        if isObject {
                            guard let key = key() else { return nil }
                            frame.key = key
                        }
                        open.append(frame)
                        continue
                    }
                case 0x22:
                    guard let text = string() else { return nil }
                    done = .string(text)
                case 0x74:
                    guard let word = literal("true", .bool(true)) else { return nil }
                    done = word
                case 0x66:
                    guard let word = literal("false", .bool(false)) else { return nil }
                    done = word
                case 0x6E:
                    guard let word = literal("null", .null) else { return nil }
                    done = word
                case 0x2D, 0x30...0x39:
                    guard let number = number() else { return nil }
                    done = number
                default:
                    return nil
                }
                //? a value read: into what is open, closing each that ends here
                closing: while true {
                    guard !open.isEmpty else { return done }
                    let last = open.count - 1
                    if open[last].isObject {
                        //? a key twice: the last value, as JSON.parse keeps it
                        open[last].fields[open[last].key] = done
                    } else {
                        open[last].items.append(done)
                    }
                    skipSpace()
                    guard at < units.count else { return nil }
                    if units[at] == 0x2C {
                        at += 1
                        if open[last].isObject {
                            guard let key = key() else { return nil }
                            open[last].key = key
                        }
                        break closing
                    }
                    guard units[at] == (open[last].isObject ? 0x7D : 0x5D) else { return nil }
                    at += 1
                    let frame = open.removeLast()
                    done = frame.isObject ? .object(frame.fields) : .array(frame.items)
                }
            }
        }

        mutating func literal(_ word: String, _ value: Value) -> Value? {
            for unit in word.utf16 {
                guard at < units.count, units[at] == unit else { return nil }
                at += 1
            }
            return value
        }

        /// An object's key and its colon, the space around them skipped.
        mutating func key() -> String? {
            skipSpace()
            guard at < units.count, units[at] == 0x22, let key = string() else { return nil }
            skipSpace()
            guard at < units.count, units[at] == 0x3A else { return nil }
            at += 1
            return key
        }

        /// A string from its opening quote, unescaped into UTF-16 units; nil for a raw control character, an
        /// escape JSON hasn't got, or no closing quote.
        mutating func string() -> String? {
            at += 1
            var out: [UInt16] = []
            while at < units.count {
                let unit = units[at]
                if unit == 0x22 {
                    at += 1
                    //? a lone surrogate - which JavaScript keeps - can't be in a Swift string: U+FFFD, one unit too
                    return String(decoding: out, as: UTF16.self)
                }
                if unit < 0x20 { return nil }
                if unit != 0x5C {
                    out.append(unit)
                    at += 1
                    continue
                }
                at += 1
                guard at < units.count else { return nil }
                switch units[at] {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    guard at + 4 < units.count else { return nil }
                    var code: UInt16 = 0
                    for place in 1...4 {
                        guard let digit = Self.hex(units[at + place]) else { return nil }
                        code = code << 4 | digit
                    }
                    out.append(code)
                    at += 4
                default: return nil
                }
                at += 1
            }
            return nil
        }

        static func hex(_ unit: UInt16) -> UInt16? {
            switch unit {
            case 0x30...0x39: return unit - 0x30
            case 0x41...0x46: return unit - 0x41 + 10
            case 0x61...0x66: return unit - 0x61 + 10
            default: return nil
            }
        }

        /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, read as the nearest Double (an exponent past a
        /// Double reads as an infinity, one below it as 0 - as JavaScript reads them).
        mutating func number() -> Value? {
            let start = at
            func digit() -> Bool { at < units.count && units[at] >= 0x30 && units[at] <= 0x39 }
            func digits() -> Bool {
                guard digit() else { return false }
                while digit() { at += 1 }
                return true
            }
            if units[at] == 0x2D { at += 1 }
            guard at < units.count else { return nil }
            if units[at] == 0x30 {
                at += 1
            } else if !digits() {
                return nil
            }
            if at < units.count && units[at] == 0x2E {
                at += 1
                guard digits() else { return nil }
            }
            if at < units.count && (units[at] == 0x65 || units[at] == 0x45) {
                at += 1
                if at < units.count && (units[at] == 0x2B || units[at] == 0x2D) { at += 1 }
                guard digits() else { return nil }
            }
            let text = String(decoding: units[start..<at], as: UTF16.self)
            return Double(text).map(Value.number)
        }
    }
}
