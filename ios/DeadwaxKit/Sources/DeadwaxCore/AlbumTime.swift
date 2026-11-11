import Foundation

/// The Library's dates as the web app reads them (ui/src/lib/shelves.ts `time`, `monthLabel`): only a string is a
/// date, read as JavaScript's `Date.parse` reads the forms Navidrome sends, kept as whole milliseconds since 1970
/// (JS's numbers here) - and a month header in English from a fixed table, from the UTC month, never the device's
/// zone or language.
public enum AlbumTime {
    /// What a month header says for an album with no readable date.
    public static let dateUnknown = "Date unknown"

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]

    /// The furthest a JavaScript Date reaches either side of 1970 (TimeClip): beyond it, NaN.
    static let maxMs: Int64 = 8_640_000_000_000_000

    /// `Date.parse(text)` for the ISO forms: `YYYY` (or an expanded year, `+YYYYYY`/`-YYYYYY`, never `-000000`),
    /// `YYYY-MM`, `YYYY-MM-DD` (UTC midnight), then `T` or `t` and `HH:MM`, optional `:SS`, optional `.` and one or
    /// more digits (read as V8 reads them - `fraction`), then `Z`/`z`, `+HH:MM`, `-HH:MM` (hours 0-23, minutes
    /// 0-59) - or nothing, which is LOCAL time in `zone`, as a browser reads it in its own. Month 1-12, day 1-31
    /// rolling on past a month's end ("2026-02-30" is 2 March, as V8), hour 0-24 (24 only as 24:00:00, with no
    /// fraction digit but 0), minute and second 0-59, within a Date's reach; anything else nil.
    ///
    /// A SPACE in the T's place is read too, after a whole date: V8 hands that to its legacy parser, which reads
    /// these forms as above except for a year 0-99 (a year 1-31 as a month and day, the rest as 19xx and 20xx) - so
    /// that is nil with a space - and where it is looser (an offset of 24 hours or more, a fraction after 24:00 that
    /// rounds to 0 ms), which is nil here too. What V8 reads only with its legacy parser ("2026-1-05", "+0100", a
    /// space around the date or before the zone, "2026-10 14:22", "Mon, 05 Oct 2026 ...") is nil: Navidrome sends
    /// RFC 3339 with a T and nothing else. dates.json's `legacy` lists each kind, with what V8 makes of it.
    public static func ms(_ text: String?, zone: TimeZone = .current) -> Int64? {
        guard let text else { return nil }
        let bytes = Array(text.utf8)
        var at = 0
        func digits(_ count: Int) -> Int? {
            guard at + count <= bytes.count else { return nil }
            var value = 0
            for k in 0..<count {
                let byte = bytes[at + k]
                guard byte >= 0x30 && byte <= 0x39 else { return nil }
                value = value * 10 + Int(byte - 0x30)
            }
            at += count
            return value
        }
        func take(_ byte: UInt8) -> Bool {
            if at < bytes.count && bytes[at] == byte { at += 1; return true }
            return false
        }
        let year: Int
        if let sign = bytes.first, sign == 0x2B || sign == 0x2D {          // + -
            at = 1
            guard let expanded = digits(6), sign == 0x2B || expanded != 0 else { return nil }
            year = sign == 0x2D ? -expanded : expanded
        } else {
            guard let plain = digits(4) else { return nil }
            year = plain
        }
        var month = 1, day = 1, hour = 0, minute = 0, second = 0, millis = 0
        var fractionIsZero = true
        var offset: Int? = 0                                           //? the date-only forms are UTC
        var wholeDate = false
        if take(0x2D) {                                                // -
            guard let m = digits(2) else { return nil }
            month = m
            if take(0x2D) {
                guard let d = digits(2) else { return nil }
                day = d
                wholeDate = true
            }
        }
        if at < bytes.count && (bytes[at] == 0x54 || bytes[at] == 0x74 || bytes[at] == 0x20) {   // T t space
            //? a space is V8's legacy parser: read only where it reads as the ISO one does (see above)
            if bytes[at] == 0x20 && (!wholeDate || (0...99).contains(year)) { return nil }
            at += 1
            offset = nil                                               //? a time with no zone is local
            guard let h = digits(2), take(0x3A), let mi = digits(2) else { return nil }
            hour = h
            minute = mi
            if take(0x3A) {
                guard let s = digits(2) else { return nil }
                second = s
                if take(0x2E) {                                        // .
                    let start = at
                    while at < bytes.count, bytes[at] >= 0x30, bytes[at] <= 0x39 { at += 1 }
                    guard at > start else { return nil }
                    let read = fraction(bytes[start..<at])
                    millis = read.ms
                    fractionIsZero = read.zero
                }
            }
            if at < bytes.count {
                if bytes[at] == 0x5A || bytes[at] == 0x7A {            // Z z
                    at += 1
                    offset = 0
                } else if bytes[at] == 0x2B || bytes[at] == 0x2D {     // + -
                    let sign = bytes[at] == 0x2D ? -1 : 1
                    at += 1
                    guard let oh = digits(2), take(0x3A), let om = digits(2), oh <= 23, om <= 59 else { return nil }
                    offset = sign * (oh * 3600 + om * 60)
                }
            }
        }
        guard at == bytes.count, (1...12).contains(month), (1...31).contains(day), hour <= 24, minute <= 59,
              second <= 59, hour < 24 || (minute == 0 && second == 0 && fractionIsZero) else { return nil }
        let days = Int64(daysFromCivil(year, month, 1)) + Int64(day - 1)
        let wall = days * 86_400_000 + Int64(hour * 3_600_000 + minute * 60_000 + second * 1000 + millis)
        let instant = offset.map { wall - Int64($0) * 1000 } ?? utc(fromLocal: wall, zone: zone)
        return abs(instant) <= maxMs ? instant : nil
    }

    /// The digits after a second's `.` as V8's date parser reads them (dateparser ReadUnsignedNumeral and
    /// ReadMilliseconds): leading zeros skipped, the next nine digits at most taken as a number, which is then scaled
    /// to milliseconds by how many digits there were - counting no more than nine. Up to nine digits that is the
    /// fraction cut to milliseconds (".9999" is 999); past nine, with leading zeros, V8 makes more of it than is
    /// there (".0123456789" is 123 ms, ".00012345678" 12), and so does this. `zero`: no digit but 0 - the only
    /// fraction 24:00:00 may have.
    static func fraction(_ digits: ArraySlice<UInt8>) -> (ms: Int, zero: Bool) {
        var number = 0, taken = 0
        var zero = true
        for byte in digits {
            if zero && byte == 0x30 { continue }
            zero = false
            if taken < 9 { number = number * 10 + Int(byte - 0x30) }
            taken += 1
        }
        switch digits.count {
        case 1: return (number * 100, zero)
        case 2: return (number * 10, zero)
        case 3: return (number, zero)
        default:
            var scale = min(digits.count, 9)
            while scale > 3 { number /= 10; scale -= 1 }
            return (number, zero)
        }
    }

    /// A local wall time (as milliseconds, read as if it were UTC) as the instant it names in `zone`, as V8 decides
    /// it with ICU's "former" rule: a time that happens twice (the clocks going back) is the earlier, and one that
    /// never happens (the clocks going forward) is read with the offset before the change.
    static func utc(fromLocal wall: Int64, zone: TimeZone) -> Int64 {
        func offset(_ instant: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(instant) / 1000))) * 1000
        }
        let before = offset(wall - 86_400_000)
        let after = offset(wall + 86_400_000)
        let early = wall - before
        if offset(early) == before { return early }
        let late = wall - after
        if offset(late) == after { return late }
        return early
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's days_from_civil) - not Foundation's
    /// Calendar, whose Gregorian is Julian before 1582 (Go's zero time, 0001-01-01, must read January 1).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The UTC year and month of an instant (civil_from_days).
    static func civil(_ ms: Int64) -> (year: Int, month: Int) {
        var days = ms / 86_400_000
        if ms % 86_400_000 < 0 { days -= 1 }
        let z = Int(days) + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month)
    }

    /// `monthOf`: "October 2026" - the UTC month of an instant, in English; "Date unknown" for none.
    public static func month(_ ms: Int64?) -> String {
        guard let ms else { return dateUnknown }
        let date = civil(ms)
        return "\(months[date.month - 1]) \(date.year)"
    }

    /// `monthLabel`: the month a date string falls in, or "Date unknown".
    public static func monthLabel(_ text: String?, zone: TimeZone = .current) -> String {
        month(ms(text, zone: zone))
    }
}
