import Foundation

// The EQ's page on the phone, redrawn (the redesign, slice R3b - notes/ios.md "The redesign, slice R3b: the Queue, Info
// and the EQ inside"; iEQ.dc.html): its new words, and a filter's editor left with a field still typed in.
//
// The editor (R3's review): Back, the sheet's strip or `‹ Now Playing`, the sheet put down - the field is never left the
// way a tap elsewhere leaves it, so what was typed was lost unsaid; now it is applied, as leaving the field applies it
// (eq.md 3.8).

extension EQWords.Screen {
    /// The switch at the top of the sheet's EQ, and on the phone's output card (iEQ's "EQ on").
    public static let on = "EQ on"
    /// The output's button's own word before the output's name (iEQ's "Output  AirPods Pro").
    public static let output = "Output"

    /// (R3b's review) The output's button's hint to VoiceOver - its name and value are the page's output's: "Opens
    /// AirPlay. Playing on James's iPhone now." - nothing of where it plays when that isn't known.
    public static func outputHint(playsTo: String) -> String {
        let name = playsTo.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Opens AirPlay." : "Opens AirPlay. Playing on \(name) now."
    }
}

extension EQEditorRules {
    /// The filter as leaving its editor leaves it: every field typed in and not yet applied, applied where it is in
    /// range - in the order the editor draws them (Frequency, Gain, then the width), each checked against the filter as
    /// the ones before it left it - and one out of range, or nothing typed, left as it is, as leaving the field leaves
    /// it (3.8: "nothing changes until it is in range"). Nil where nothing typed changes the filter.
    public static func leaving(_ typed: [EQField: String], filter f: EQFilter) -> EQFilter? {
        var g = f
        for field in EQField.allCases {
            guard let text = typed[field], case .value(let value) = check(text, field, for: g) else { continue }
            g = applying(value, field, to: g)
        }
        return g == f ? nil : g
    }
}
