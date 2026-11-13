import Foundation

// An import's preview (notes/ios-specs/eq.md 3.9, slice 5): what APOReader read, said as the preview says it, for the
// output it is for - and the correction it makes. The reading itself is APOReader's (slice 1).

/// The preview's lines (3.9): where it's from, what was read, the preamp as it will play, what it replaces, and what was
/// skipped.
public struct EQImportPreview: Equatable, Sendable {
    /// "From "HD650 ParametricEQ.txt"", or "From the clipboard"
    public var from: String
    /// "10 filters, preamp -6.4 dB" - or, for a GraphicEQ, 3.10's line for each curve converted
    public var summary: [String]
    /// "Preamp: set by deadwax, -6.1 dB with this output's tone." or "Preamp: the file's, -6.4 dB."
    public var preamp: String
    /// "It replaces the correction for James's AirPods Pro (Apple AirPods Pro, from AutoEq)." - when there is one
    public var replaces: String?
    /// "Skipped": one line each
    public var skipped: [String]
}

public enum EQImportRules {
    /// The correction an import makes (4): a file's, its name and text kept. A paste has no name: it is kept with
    /// none, and called "Pasted", from the clipboard.
    public static func correction(name: String?, text: String, reading: APOReading) -> EQCorrection {
        EQCorrection.file(name: name ?? "", text: text, reading: reading)
    }

    /// For's outputs (3.9): the one connected now first, then every other the phone has met, as Other outputs lists
    /// them (the speaker always among them) - so a file for headphones not connected can be put on them.
    public static func outputs(_ settings: EQSettings, route: EQOutput) -> [EQOutputSetting] {
        [settings.setting(for: route)] + EQScreenRules.others(settings, shown: route.key)
    }

    /// The preview for an output (3.9) at the rate it plays at (48 kHz while it isn't connected): the summary - a
    /// GraphicEQ's conversion said instead - the preamp it will play at with this output's tone (deadwax's, or with
    /// the preamp set by hand the file's own, held to the hand-set range), what it replaces, and the notes.
    public static func preview(name: String?, reading: APOReading, for setting: EQOutputSetting, in settings: EQSettings,
                               rate: Double) -> EQImportPreview {
        var after = setting
        after.on = true
        after.correction = correction(name: name, text: "", reading: reading)
        if case .hand = after.preamp { after.preamp = .hand(EQAdvancedRules.handPreamp(reading.preamp.all)) }
        let preamp: String
        switch after.preamp {
        case .automatic: preamp = EQWords.Import.preampAutomatic(settings.bank(after, rate: rate, version: 0).preamp)
        case .hand(let dB): preamp = EQWords.Import.preampFiles(dB)
        }
        let replaces = setting.correction.map { (c: EQCorrection) -> String in
            EQWords.Import.replaces(output: setting.shownName, what: EQWords.Import.what(c))
        }
        return EQImportPreview(from: name.map { EQWords.Import.from(file: $0) } ?? EQWords.Import.fromClipboard,
                               summary: reading.fits.isEmpty ? [EQWords.Import.summary(reading)]
                                   : reading.fits.map { EQWords.Import.converted($0.fit) },
                               preamp: preamp, replaces: replaces, skipped: reading.notes.map(\.text))
    }

    /// The text kept with a file's correction (4): read as the reader reads it - UTF-16 with its byte-order mark,
    /// UTF-8 (a mark at its start dropped), else Windows-1252.
    public static func text(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            //? by hand, after the mark: Foundation's .utf16 reads a mark its own way on each platform
            let little = bytes[0] == 0xFF
            let units = stride(from: 2, to: bytes.count - 1, by: 2).map { (i: Int) -> UInt16 in
                little ? UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 : UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            }
            return String(decoding: units, as: UTF16.self)
        }
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
        if let text = String(bytes: body, encoding: .utf8) { return text }
        return String(String.UnicodeScalarView(body.map { (b: UInt8) -> Unicode.Scalar in
            Unicode.Scalar(APOReader.cp1252[b] ?? UInt32(b)) ?? Unicode.Scalar(b)
        }))
    }

    /// Line `n` of a text (from 1), as the reader counts lines - at LF, a CR before it dropped: a refusal's line for
    /// whoever runs deadwax (3.17). Nil past its end.
    public static func line(_ n: Int, of text: String) -> String? {
        let lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        guard n >= 1, n <= lines.count else { return nil }
        var line = lines[n - 1]
        if line.last == "\r" { line = line.dropLast() }
        return String(String.UnicodeScalarView(line))
    }
}
