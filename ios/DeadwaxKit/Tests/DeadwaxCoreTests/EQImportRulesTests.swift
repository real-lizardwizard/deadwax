import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.9 and 3.11 (slice 5): an import's preview - its lines for the output it is for, For's outputs, the text kept
/// and a refusal's line for whoever runs deadwax - and check 26 held here: the whole curve exported (the tone Flat) or
/// the correction alone, imported again, plays the same.
@Suite struct EQImportRulesTests {
    static let airpods = EQAdvancedTests.airpods
    static let car = EQOutputs.output(EQRoutePort(port: .carAudio, portType: "CarAudio", name: "Golf", uid: "car-1"))

    static func read(_ text: String, pasted: Bool = false) throws -> APOReading {
        switch APOReader.read(Data(text.utf8), pasted: pasted) {
        case .success(let reading): return reading
        case .failure(let refusal): throw refusal
        }
    }

    static func setting(_ settings: inout EQSettings, _ o: EQOutput, seen: String, correction: EQCorrection? = nil,
                        tone: EQTone = .preset("flat"), preamp: EQPreampSetting = .automatic) {
        settings.met(o, at: seen)
        settings.change(o) { (s: inout EQOutputSetting) -> Void in
            s.correction = correction
            s.tone = tone
            s.preamp = preamp
        }
    }

    /// The preview's lines: from where, what was read, the preamp as it will play here, what it replaces, the skipped.
    @Test func thePreviewsLines() throws {
        let text = "Preamp: -6.4 dB\nVolume: 5\nFilter 1: ON PK Fc 1000 Hz Gain 6 dB Q 1\nFilter 2: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.7\n"
        let reading = try Self.read(text)
        var settings = EQSettings()
        Self.setting(&settings, Self.airpods, seen: "2", correction: try EQAdvancedTests.autoEq(), tone: .preset("bassBoost"))
        let setting = settings.output(Self.airpods.key)!
        let preview = EQImportRules.preview(name: "HD650 ParametricEQ.txt", reading: reading, for: setting,
                                            in: settings, rate: 48_000)
        #expect(preview.from == "From \"HD650 ParametricEQ.txt\"")
        #expect(preview.summary == ["2 filters, preamp -6.4 dB"])
        #expect(preview.replaces == "It replaces the correction for James's AirPods Pro (Apple AirPods Pro, from AutoEq).")
        #expect(preview.skipped == ["Line 2 isn't something Equalizer APO plays either (Volume: 5)."])
        // the preamp deadwax sets with this output's tone (Bass Boost) on top
        var after = setting
        after.correction = EQImportRules.correction(name: "x", text: "", reading: reading)
        let played = settings.bank(after, rate: 48_000, version: 0).preamp
        #expect(played < -6.4)
        #expect(preview.preamp == "Preamp: set by deadwax, \(EQWords.oneDecimal(played)) dB with this output's tone.")
        // set by hand: the file's, held to the hand-set range
        var hand = setting
        hand.preamp = .hand(-2)
        #expect(EQImportRules.preview(name: nil, reading: reading, for: hand, in: settings, rate: 48_000).preamp
                    == "Preamp: the file's, -6.4 dB.")
        let loud = try Self.read("Preamp: 20 dB\nFilter: ON PK Fc 100 Hz Gain -3 dB Q 1\n")
        #expect(EQImportRules.preview(name: nil, reading: loud, for: hand, in: settings, rate: 48_000).preamp
                    == "Preamp: the file's, 12.0 dB.")
        // pasted, onto an output with no correction
        let none = EQSettings.newOutput(Self.car, seen: "")
        let pasted = EQImportRules.preview(name: nil, reading: reading, for: none, in: settings, rate: 48_000)
        #expect(pasted.from == "From the clipboard" && pasted.replaces == nil)
    }

    /// Per ear, the summary says so; a GraphicEQ, 3.10's line instead.
    @Test func perEarAndGraphic() throws {
        let ears = try Self.read("Preamp: -6 dB\nFilter: ON PK Fc 100 Hz Gain 2 dB Q 1\nChannel: L\nFilter: ON PK Fc 200 Hz Gain 2 dB Q 1\nFilter: ON PK Fc 300 Hz Gain 2 dB Q 1\n")
        let setting = EQSettings.newOutput(Self.airpods, seen: "")
        #expect(EQImportRules.preview(name: "a.txt", reading: ears, for: setting, in: EQSettings(), rate: 48_000).summary
                    == ["1 filter for both ears, 2 more for the left, preamp -6.0 dB"])
        let graphic = try Self.read("GraphicEQ: 20 -3; 1000 0; 10000 4; 20000 -2\n")
        let lines = EQImportRules.preview(name: "Wavelet.txt", reading: graphic, for: setting, in: EQSettings(),
                                          rate: 48_000).summary
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("Converted from a GraphicEQ curve: "))
        #expect(lines[0] == EQWords.Import.converted(graphic.fits[0].fit))
        let c = EQImportRules.correction(name: "Wavelet.txt", text: "", reading: graphic)
        #expect(EQWords.Correction.source(c) == "From Wavelet.txt, converted")
    }

    /// For's outputs: the one connected now first, then every other met, the most recent first, the speaker always.
    @Test func forsOutputs() {
        var settings = EQSettings()
        settings.met(Self.car, at: "2026-11-10T08:00:00Z")
        settings.met(Self.airpods, at: "2026-11-12T10:00:00Z")
        let keys = EQImportRules.outputs(settings, route: Self.car).map(\.key)
        #expect(keys == [Self.car.key, Self.airpods.key, EQOutputs.speaker.key])
        #expect(EQImportRules.outputs(EQSettings(), route: EQOutputs.speaker).map(\.key) == [EQOutputs.speaker.key])
    }

    /// The text kept: UTF-8 (its mark dropped), UTF-16 with its mark, else Windows-1252 - and a line for whoever runs
    /// deadwax, counted as the reader counts.
    @Test func theTextKept() {
        let plain = "Preamp: -6 dB\r\nFilter: ON PK Fc 100 Hz Gain 2 dB Q 1\n"
        #expect(EQImportRules.text(Data(plain.utf8)) == plain)
        #expect(EQImportRules.text(Data([0xEF, 0xBB, 0xBF] + Array("Preamp: 1 dB".utf8))) == "Preamp: 1 dB")
        var utf16 = Data([0xFF, 0xFE])
        for unit in "Preamp: -2 dB".utf16 { utf16.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
        #expect(EQImportRules.text(utf16) == "Preamp: -2 dB")
        // 0x93 0x94 are Windows-1252's curly quotes; 0xE9 its e-acute
        let cp = EQImportRules.text(Data(Array("# ".utf8) + [0x93, 0x45, 0x94, 0x20, 0x63, 0x61, 0x66, 0xE9]))
        #expect(cp.unicodeScalars.map(\.value) == [0x23, 0x20, 0x201C, 0x45, 0x201D, 0x20, 0x63, 0x61, 0x66, 0xE9])
        #expect(EQImportRules.line(1, of: plain) == "Preamp: -6 dB")
        #expect(EQImportRules.line(2, of: plain) == "Filter: ON PK Fc 100 Hz Gain 2 dB Q 1")
        #expect(EQImportRules.line(3, of: plain) == "")
        #expect(EQImportRules.line(4, of: plain) == nil)
        #expect(EQImportRules.line(0, of: plain) == nil)
    }

    /// A refusal names its line: the line itself is for whoever runs deadwax (3.17).
    @Test func aRefusalsLine() throws {
        let text = "Preamp: -3 dB\nFilter: ON PK Fc 100 Hz Gain 2 dB Q 1\nInclude: bass.txt\n"
        guard case .failure(let refusal) = APOReader.read(Data(text.utf8), pasted: true) else {
            Issue.record("Include is refused")
            return
        }
        #expect(refusal.text == "Line 3 includes another file (bass.txt). Import that file itself.")
        #expect(EQImportRules.line(try #require(refusal.line), of: text) == "Include: bass.txt")
    }

    /// Check 26 held here: the whole curve exported with the tone Flat, or the correction alone, imported again plays
    /// the same - its response to 1e-9 dB at every grid point, the same preamp - for every AutoEq profile and both ways
    /// of setting the preamp.
    @Test func anExportImportedAgainPlaysTheSame() throws {
        for profile in try EQFixtures.profiles().profiles {
            let data = try Fixtures.data("eq/\(profile.path)")
            guard case .success(let reading) = APOReader.read(data) else { continue }
            let c = EQCorrection.autoeq(id: profile.path, name: "x", source: profile.measurer, rig: nil, form: nil,
                                        text: String(decoding: data, as: UTF8.self), reading: reading)
            for preamp in [EQPreampSetting.automatic, .hand(-7.5)] {
                for (whole, tone) in [(true, EQTone.preset("flat")), (false, EQTone.preset("bassBoost"))] {
                    var settings = EQSettings()
                    Self.setting(&settings, Self.airpods, seen: "1", correction: c, tone: tone, preamp: preamp)
                    let before = settings.output(Self.airpods.key)!
                    let file = APOWriter.export(before, in: settings, whole: whole, day: "2026-11-12")
                    let back = try Self.read(file)
                    var after = settings
                    after.importCorrection(EQImportRules.correction(name: "x EQ.txt", text: file, reading: back),
                                           for: Self.airpods)
                    let a = settings.bank(before, rate: 48_000, version: 0)
                    let b = after.bank(after.output(Self.airpods.key)!, rate: 48_000, version: 0)
                    #expect(a.preamp == b.preamp, "\(profile.path)")
                    let grid = EQChart.grid.filter { $0 < 24_000 }
                    let ra = EQResponse.curve(a.left.map(\.coefficients), at: grid, rate: 48_000, offset: a.preamp)
                    let rb = EQResponse.curve(b.left.map(\.coefficients), at: grid, rate: 48_000, offset: b.preamp)
                    let most = zip(ra, rb).map { abs($0 - $1) }.max() ?? 0
                    #expect(most < 1e-9, "\(profile.path), whole \(whole), \(preamp): \(most) dB")
                }
            }
        }
    }
}
