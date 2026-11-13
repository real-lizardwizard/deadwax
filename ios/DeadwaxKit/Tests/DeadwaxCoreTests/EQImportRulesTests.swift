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
        var bigEnd = Data([0xFE, 0xFF])
        for unit in "Preamp: -2 dB".utf16 { bigEnd.append(contentsOf: [UInt8(unit >> 8), UInt8(unit & 0xFF)]) }
        #expect(EQImportRules.text(bigEnd) == "Preamp: -2 dB")
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

    /// The largest difference between two banks' curves, each ear's at its level, over the chart's grid at 48 kHz.
    static func difference(_ a: EQBank, _ b: EQBank) -> Double {
        let grid = EQChart.grid.filter { $0 < 24_000 }
        var most = 0.0
        for (x, y) in [(a.left, b.left), (a.right, b.right)] {
            let ra = EQResponse.curve(x.map(\.coefficients), at: grid, rate: 48_000, offset: a.preamp)
            let rb = EQResponse.curve(y.map(\.coefficients), at: grid, rate: 48_000, offset: b.preamp)
            most = max(most, zip(ra, rb).map { (p: (Double, Double)) -> Double in abs(p.0 - p.1) }.max() ?? 0)
        }
        return most
    }

    /// back-home 15: the most The Whole Curve writes for an ear reads back. It writes the correction's filters and
    /// the tone's moved bands, so its most is the most a correction is made with - 64 an ear, Add Filter's - under all
    /// ten bands moved: 74, what an import takes (`EQLimits.importPerEar`). Three ways there: 64 for both ears, by
    /// Add Filter itself; 60 for both and four for each ear's own (78 lines, 74 an ear); and a converted GraphicEQ
    /// keeping all 61 of its peaks - 71 under the tone, the case back-home named - with three filters added. Each
    /// reads back filter for filter, bit for bit; imported over a Flat tone it plays as it did to 1e-9 dB, and under
    /// the tone the render plays all 84 of its sections, none dropped. The step after is the bound no limit passes:
    /// that import, exported again under the tone, writes 84 an ear and is refused - over Flat, as docs/ios.md says to
    /// set it, it reads back.
    @Test func theMostAnExportWritesReadsBack() throws {
        let custom: [Double] = [3, -2.5, 1.5, -1, 0.5, -0.5, 1, -1.5, 2, -3]
        #expect(custom.allSatisfy { $0 != 0 } && custom.count == EQGraphic.names.count)
        #expect(EQLimits.importPerEar == EQLimits.filtersPerEar + custom.count)
        #expect(EQLimits.sectionsPerChannel == EQLimits.importPerEar + custom.count)

        /// The whole curve's file read back, checked bit for bit against what was written, with each ear's count.
        func wholeCurve(_ settings: EQSettings, _ what: String) throws -> (file: String, reading: APOReading, most: Int) {
            let setting = try #require(settings.output(Self.airpods.key))
            let file = APOWriter.export(setting, in: settings, whole: true, day: "2026-11-13")
            let written = APOWriterTests.asWritten(APOWriter.curve(correction: setting.correction?.filters ?? [],
                                                                   bands: settings.gains(setting.tone)))
            let back = try Self.read(file)
            #expect(back.filters.count == written.count, "\(what)")
            for (mine, theirs) in zip(back.filters, written) {
                #expect(EQFixtures.sameBits(mine, theirs), "\(what): \(mine) written as \(theirs)")
            }
            let n = EQAdvancedRules.perEar(back.filters)
            return (file, back, max(n.left, n.right))
        }

        /// Read back, imported on the output and heard over Flat: as the curve played before. Then under the tone
        /// again: every section played - and that, exported, is past what an import takes.
        func readsBack(_ settings: EQSettings, _ what: String) throws {
            let (file, reading, most) = try wholeCurve(settings, what)
            #expect(most == EQLimits.importPerEar, "\(what): \(most) an ear")
            var after = settings
            after.importCorrection(EQImportRules.correction(name: "AirPods EQ.txt", text: file, reading: reading),
                                   for: Self.airpods)
            after.choose(.preset("flat"), for: Self.airpods)
            let before = settings.bank(settings.output(Self.airpods.key)!, rate: 48_000, version: 0)
            let heard = after.bank(after.output(Self.airpods.key)!, rate: 48_000, version: 0)
            #expect(before.preamp == heard.preamp, "\(what): \(before.preamp) dB, then \(heard.preamp) dB")
            #expect(Self.difference(before, heard) < 1e-9, "\(what)")
            //? over Flat, its own export is the correction it is - which reads back
            #expect(try wholeCurve(after, what + ", read back").most == EQLimits.importPerEar)
            //? under the tone, the render plays every section: 74 and the tone's 10, none cut off
            after.change(Self.airpods) { (s: inout EQOutputSetting) -> Void in s.tone = .custom(custom) }
            let twice = after.bank(after.output(Self.airpods.key)!, rate: 48_000, version: 0)
            let left = EQBank.sections(reading.filters.filter { $0.channel != .right }, rate: 48_000).count + custom.count
            let right = EQBank.sections(reading.filters.filter { $0.channel != .left }, rate: 48_000).count + custom.count
            #expect(left == 84 && right == 84 && twice.left.count == left && twice.right.count == right,
                    "\(what): \(twice.left.count) of \(left), \(twice.right.count) of \(right)")
            //? and exported so, 84 an ear: refused, as any file over 74 is
            let again = APOWriter.export(after.output(Self.airpods.key)!, in: after, whole: true, day: "2026-11-13")
            guard case .failure(let refusal) = APOReader.read(Data(again.utf8)) else {
                Issue.record("\(what): 84 an ear read back")
                return
            }
            #expect(refusal.kind == .tooMany && refusal.text == "This file has 84 filters for one ear - deadwax plays up to 74.",
                    "\(what): \(refusal.text)")
        }

        // 64 for both ears, by Add Filter, each moved somewhere of its own
        var made = EQSettings()
        Self.setting(&made, Self.airpods, seen: "1", tone: .custom(custom))
        for i in 0..<EQLimits.filtersPerEar {
            let added = made.addFilter(for: Self.airpods)
            let id = try #require(added?.id)
            made.editFilter(id, for: Self.airpods) { (f: inout EQFilter) -> Void in
                f.fc = (25 * pow(800, Double(i) / 63)).rounded()
                f.gain = i % 2 == 0 ? 2.5 : -2
                f.width = .q(2)
            }
        }
        let built = try #require(made.output(Self.airpods.key)?.correction)
        #expect(built.kind == .built && built.filters.count == 64 && Set(built.filters.map(\.fc)).count == 64)
        #expect(built.filters.allSatisfy { $0.gain != 0 && $0.width == .q(2) })
        #expect(made.addFilter(for: Self.airpods) == nil)
        try readsBack(made, "64 for both ears")

        // 60 for both and four for each ear's own
        let shared = (0..<60).map { (i: Int) -> EQFilter in
            EQAdvancedTests.peak(i + 1, (30 * pow(600, Double(i) / 59)).rounded(), i % 2 == 0 ? 2 : -1.5)
        }
        let own = (0..<8).map { (i: Int) -> EQFilter in
            EQAdvancedTests.peak(61 + i, 150 + 1000 * Double(i), 1.5, channel: i < 4 ? .left : .right)
        }
        var ears = EQSettings()
        Self.setting(&ears, Self.airpods, seen: "1", correction: EQAdvancedTests.built(shared + own), tone: .custom(custom))
        #expect(!EQAdvancedRules.canAdd(ears.output(Self.airpods.key)?.correction))
        let lines = try wholeCurve(ears, "four for each ear").file.split(separator: "\n").filter { $0.hasPrefix("Filter ") }
        #expect(lines.count == 60 + 8 + custom.count)
        try readsBack(ears, "four for each ear")

        // a converted GraphicEQ keeping all 61 of its peaks: 71 under the tone; three more added, 74
        let points = GraphicEQFit.centres.enumerated().map { (k: Int, c: Double) -> String in
            "\(Int(c)) \(k % 2 == 0 ? 1 : -1)"
        }
        let graphic = "GraphicEQ: " + points.joined(separator: "; ") + "\n"
        let fitted = try Self.read(graphic)
        #expect(fitted.fits.first?.fit.kept == GraphicEQFit.centres.count && fitted.filters.count == 61)
        var converted = EQSettings()
        Self.setting(&converted, Self.airpods, seen: "1", tone: .custom(custom))
        converted.importCorrection(EQImportRules.correction(name: "Wavelet.txt", text: graphic, reading: fitted),
                                   for: Self.airpods)
        #expect(try wholeCurve(converted, "a converted GraphicEQ").most == 61 + custom.count)
        for k in 0..<3 {
            //? each given a gain: Add Filter's own 0 dB peak is written and read, but plays no section
            let added = converted.addFilter(for: Self.airpods)
            let id = try #require(added?.id)
            converted.editFilter(id, for: Self.airpods) { (f: inout EQFilter) -> Void in
                f.fc = 300 + 2000 * Double(k)
                f.gain = 2
            }
        }
        #expect(converted.addFilter(for: Self.airpods) == nil)
        try readsBack(converted, "a converted GraphicEQ and three more")
    }

    /// An import takes 74 an ear (back-home 15) - the shared filters counted for both, an ear's own for it alone -
    /// and refuses 75.
    @Test func anImportTakesSeventyFourAnEar() throws {
        func file(shared: Int, left: Int, right: Int) -> String {
            var lines = ["Preamp: -3 dB"]
            var n = 0
            func add(_ count: Int) {
                for _ in 0..<count {
                    n += 1
                    lines.append("Filter \(n): ON PK Fc \(20 + 100 * n) Hz Gain \(n % 2 == 0 ? 1 : -1) dB Q 2")
                }
            }
            add(shared)
            lines.append("Channel: L")
            add(left)
            lines.append("Channel: R")
            add(right)
            return lines.joined(separator: "\n") + "\n"
        }
        for (shared, left, right) in [(74, 0, 0), (70, 4, 4), (0, 74, 74), (60, 14, 0)] {
            let reading = try Self.read(file(shared: shared, left: left, right: right))
            #expect(reading.filters.count == shared + left + right)
        }
        for (shared, left, right, most) in [(75, 0, 0, 75), (70, 4, 5, 75), (0, 74, 75, 75), (74, 1, 0, 75), (90, 0, 0, 90)] {
            guard case .failure(let refusal) = APOReader.read(Data(file(shared: shared, left: left, right: right).utf8)) else {
                Issue.record("\(shared) + \(left) + \(right) read")
                continue
            }
            #expect(refusal.kind == .tooMany && refusal.line == nil)
            #expect(refusal.text == "This file has \(most) filters for one ear - deadwax plays up to 74.")
        }
    }
}
