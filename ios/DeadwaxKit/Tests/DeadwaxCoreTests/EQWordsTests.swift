import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.13, every word - and 3.9's, whose refusals and notes APOReaderTests hold word for word against the
/// script's reader; here the preview's own words and the numbers in them.
@Suite struct EQWordsTests {
    typealias W = EQWords

    static let settings = EQSettings(presets: [EQYourPreset(id: "p1", name: "Late night", gains: EQGraphic.flat)])
    static let autoeq = EQCorrection(kind: .autoeq, id: "x", name: "Apple AirPods Pro", source: "crinacle", rig: "711",
                                     form: "in-ear", nextFilterID: 1, filters: [])

    static func output(on: Bool, correction: EQCorrection?, tone: EQTone) -> EQOutputSetting {
        EQOutputSetting(key: "k", type: .bluetoothA2DP, uid: "u", name: "James's AirPods Pro", renamed: nil, seen: "",
                        suggestion: nil, on: on, correction: correction, tone: tone, preamp: .automatic)
    }

    @Test func numbers() {
        #expect(W.signedDB(2.6) == "+2.6 dB" && W.signedDB(-6.4) == "-6.4 dB" && W.signedDB(0) == "0.0 dB")
        #expect(W.signedDB(6) == "+6.0 dB" && W.signedDB(0.04) == "0.0 dB" && W.signedDB(-0.04) == "0.0 dB")
        #expect(W.held(3.5) == "+3.5 dB" && W.held(0) == "0 dB" && W.held(-6) == "-6 dB" && W.held(-0.0) == "0 dB")
        #expect(W.decibelsSaid(3.5) == "plus 3.5 decibels" && W.decibelsSaid(0) == "0 decibels")
        #expect(W.decibelsSaid(-6) == "minus 6 decibels" && W.decibelsSaid(1) == "plus 1 decibel")
        #expect(W.hertzSaid(125) == "125 hertz" && W.hertzSaid(2500) == "2.5 kilohertz" && W.hertzSaid(1000) == "1 kilohertz")
        #expect(W.hertz(62.5) == "63 Hz" && W.hertz(8903) == "8.9 kHz" && W.hertz(48000) == "48 kHz" && W.hertz(44100) == "44.1 kHz")
        #expect(W.hertz(352800) == "352.8 kHz" && W.hertz(23520) == "23.5 kHz")
    }

    @Test func youNowPlayingAndInfo() {
        #expect(W.You.row == "EQ")
        #expect(W.You.footer == "Each output keeps its own EQ - your headphones, the speaker, the car - and the EQ switches by itself when the output changes. This is kept on this phone.")
        let s = Self.settings
        func short(_ on: Bool, _ c: EQCorrection?, _ t: EQTone) -> String { W.shortSetting(Self.output(on: on, correction: c, tone: t), in: s) }
        var file = Self.autoeq
        file.kind = .file
        var built = Self.autoeq
        built.kind = .built
        #expect(short(false, Self.autoeq, .preset("bassBoost")) == "Off")
        #expect(short(true, nil, .preset("flat")) == "Flat")
        #expect(short(true, nil, .preset("bassBoost")) == "Bass Boost")
        #expect(short(true, nil, .custom(EQGraphic.flat)) == "Custom")
        #expect(short(true, nil, .yours("p1")) == "Late night")
        #expect(short(true, Self.autoeq, .preset("flat")) == "AutoEq")
        #expect(short(true, file, .preset("flat")) == "From a file")
        #expect(short(true, built, .preset("flat")) == "Your filters")
        #expect(short(true, Self.autoeq, .preset("bassBoost")) == "AutoEq + Bass Boost")
        #expect(short(true, file, .custom([1, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == "From a file + Custom")
        #expect(short(true, built, .preset("vocal")) == "Your filters + Vocal")
        #expect(W.nowPlaying == "EQ")
        #expect(W.moreName("More: info, go to album, download") == "More: info, go to album, download, EQ")
        #expect(W.Info.label == "EQ")
        #expect(W.Info.sound(short: "Bass Boost", output: "James's AirPods Pro", preamp: -6.4, on: true) == "Bass Boost on James's AirPods Pro, preamp -6.4 dB")
        #expect(W.Info.sound(short: "AutoEq", output: "Headphones", preamp: 0, on: true) == "AutoEq on Headphones")
        #expect(W.Info.sound(short: "Off", output: "Headphones", preamp: 0, on: false) == nil)
        #expect(W.Info.filtering(filters: 20, rate: 48000, preamp: -6.4) == "Filtering: 20 filters at 48 kHz, preamp -6.4 dB")
        #expect(W.Info.filtering(filters: 1, rate: 44100, preamp: 0) == "Filtering: 1 filter at 44.1 kHz, preamp 0.0 dB")
        #expect(W.Info.passing == "Off: every sample passed through untouched")
        #expect(W.Info.changing == "Changing: crossfading to the new curve")
    }

    @Test func theScreen() {
        #expect(W.Screen.title == "EQ" && W.Screen.rename == "Rename…" && W.Screen.done == "Done")
        #expect(W.Screen.connected == "Connected now" && W.Screen.notConnected == "Not connected")
        #expect(W.Screen.outputSaid("James's AirPods Pro", connected: true) == "James's AirPods Pro, connected now")
        #expect(W.Screen.outputSaid("Headphones", connected: false) == "Headphones, not connected")
        #expect(W.Screen.toggle == "EQ" && W.Screen.toggleSaid("James's AirPods Pro") == "EQ for James's AirPods Pro")
        #expect(W.Screen.airPlayFooter == "Over AirPlay, a change is heard about 2 seconds later.")
        #expect(W.Screen.off == "Off: nothing changes the sound.")
        #expect(W.Screen.flat == "Flat: nothing changes the sound yet.")
        #expect(W.Screen.automatic(-6.4) == "Preamp -6.4 dB, so loud songs don't clip.")
        #expect(W.Screen.hand(-6, top: 5.9) == "Preamp -6.0 dB, set by you.")
        #expect(W.Screen.hand(-6, top: 6) == "Preamp -6.0 dB, set by you.")
        #expect(W.Screen.hand(-6, top: 8.4) == "Loud songs may clip: the curve boosts 2.4 dB more than this preamp takes away.")
        #expect(W.Screen.hand(-6, top: 6.01) == "Loud songs may clip: the curve boosts 0.1 dB more than this preamp takes away.")
        #expect(W.Screen.notConnectedLine == "Not connected: this is what it plays when it is.")
        #expect(W.Screen.unitNotMade == "The EQ can't play on this phone just now, so the sound is as it is. Closing deadwax and opening it again may help.")
        #expect(W.Screen.fallback == "The EQ comes in after a moment's pause.")
        #expect(W.Screen.gainLabels == ["+12", "0", "-12"] && W.Screen.frequencyLabels == ["100", "1k", "10k"])
        #expect(W.Screen.left == "Left" && W.Screen.right == "Right")
        #expect(W.Screen.outputGone("James's AirPods Pro") == "James's AirPods Pro isn't connected: changes are kept for when it is.")
    }

    @Test func theCorrection() {
        let c = W.Correction.self
        #expect(c.header == "Correction" && c.none == "None" && c.backToAutoEq == "Back to AutoEq's")
        var changed = Self.autoeq
        changed.changed = true
        let file = EQCorrection(kind: .file, name: "HD650 ParametricEQ.txt", nextFilterID: 1, filters: [])
        let converted = EQCorrection(kind: .file, name: "Wavelet.txt", converted: true, nextFilterID: 1, filters: [])
        let built = EQCorrection(kind: .built, name: "", nextFilterID: 1, filters: [])
        #expect(c.source(Self.autoeq) == "AutoEq, measured by crinacle")
        #expect(c.source(changed) == "AutoEq, measured by crinacle - changed")
        #expect(c.source(file) == "From HD650 ParametricEQ.txt")
        #expect(c.source(converted) == "From Wavelet.txt, converted")
        #expect(c.source(built) == "Your own filters")
        #expect(c.value(nil) == "None" && c.value(Self.autoeq) == "Apple AirPods Pro" && c.value(built) == "Your own filters")
        #expect(c.headphonesFooter == "Evens out what these headphones do to the sound, so they sound neutral. Your tone goes on top.")
        #expect(c.otherFooter == "Evens out what this output does to the sound. Your tone goes on top.")
        #expect(c.footer(EQOutputs.speaker) == c.otherFooter)
        #expect(c.footer(EQOutputs.output(EQRoutePort(port: .headphones, portType: "", name: "", uid: ""))) == c.headphonesFooter)
        #expect(c.suggestion("Apple AirPods Pro") == "AutoEq has a correction for Apple AirPods Pro")
        #expect(c.measuredBy("crinacle") == "Measured by crinacle")
        #expect(c.suggestions("AirPods Pro") == "AutoEq has corrections for AirPods Pro")
        #expect(c.models(5) == "5 models - pick yours" && c.notNow == "Not now")
    }

    @Test func thePickerAndAProfile() {
        let p = W.Picker.self
        #expect(p.title == "Correction" && p.prompt == "Find your headphones" && p.none == "None" && p.header == "AutoEq")
        #expect(p.suggested("James's AirPods Pro") == "Suggested for James's AirPods Pro")
        #expect(p.row(source: "crinacle", form: "in-ear", more: 0) == "crinacle · in-ear")
        #expect(p.row(source: "crinacle", form: "in-ear", more: 3) == "crinacle · in-ear · 3 more measurements")
        #expect(p.row(source: "oratory1990", form: nil, more: 1) == "oratory1990 · 1 more measurement")
        #expect(p.searching == "Searching…")
        #expect(p.empty == "Search by name or model - \"hd650\" finds the Sennheiser HD 650. Corrections come from AutoEq, which works out one for each headphone it has a measurement of.")
        #expect(p.noMatch("xyz") == "AutoEq has no headphones called \"xyz\".")
        #expect(p.tryTheModel == "Try the model alone, like \"hd650\".")
        #expect(p.tryAgain == "Try again")
        #expect(p.tooOld == "This deadwax is too old for AutoEq's corrections: they need deadwax 2.1.7 or later.")
        #expect(W.Profile.gitHubAddress == "https://github.com/jaakkopasanen/AutoEq")
        let f = W.Profile.self
        #expect(f.measured(source: "crinacle", rig: "711", form: "in-ear") == "Measured by crinacle, on a 711 rig (in-ear).")
        #expect(f.measured(source: "crinacle", rig: nil, form: "in-ear") == "Measured by crinacle.")
        #expect(f.summary(filters: 10, preamp: -6) == "10 filters, preamp -6.0 dB")
        #expect(f.use("James's AirPods Pro") == "Use for James's AirPods Pro")
        #expect(f.used("James's AirPods Pro") == "Used for James's AirPods Pro")
        #expect(f.others == "Other measurements" && f.other(source: "Super Review", form: "in-ear") == "Super Review · in-ear")
        #expect(f.gitHub == "AutoEq on GitHub")
        #expect(f.footer == "From AutoEq, which works out a correction from each measurement to make headphones sound neutral. It's a starting point: how in-ears sit in your ears changes what you hear.")
        #expect(f.notRead == "deadwax couldn't read this correction.")
        #expect(f.gone == "AutoEq doesn't have that measurement any more.")
    }

    @Test func toneAndPresets() {
        let t = W.Tone.self
        #expect(t.header == "Tone" && t.preset == "Preset" && t.custom == "Custom" && t.saveAsPreset == "Save as Preset…")
        #expect(t.footer == "Shapes the sound to your taste, on top of any correction. A preset moves the sliders; move them yourself to make your own.")
        #expect(t.value(.preset("flat"), in: Self.settings) == "Flat" && t.value(.custom([]), in: Self.settings) == "Custom")
        #expect(t.value(.preset("loudness"), in: Self.settings) == "Loudness")
        #expect(t.bands == ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
        #expect((0..<10).map(t.bandSaid) == ["31 hertz", "63 hertz", "125 hertz", "250 hertz", "500 hertz", "1 kilohertz",
                                             "2 kilohertz", "4 kilohertz", "8 kilohertz", "16 kilohertz"])
        #expect(t.resetToZero == "Reset to 0")
        let p = W.Presets.self
        #expect(p.title == "Preset" && p.custom == "Custom" && p.customNote == "Where you left the sliders.")
        #expect(p.yours == "Your presets" && p.rename == "Rename" && p.delete == "Delete")
        #expect(p.saveTitle == "Save as Preset" && p.renameTitle == "Rename Preset" && p.name == "Name")
        #expect(p.save == "Save" && p.cancel == "Cancel")
        #expect(p.problem(.empty) == "Give it a name.")
        #expect(p.problem(.taken("Bass Boost")) == "There's already a preset called \"Bass Boost\".")
        #expect(EQGraphic.presets.map(\.name) == ["Flat", "Bass Boost", "Bass Reduce", "Treble Boost", "Treble Reduce", "Vocal",
                                                  "Loudness", "Small Speakers", "Spoken Word"])
    }

    @Test func advancedTheFiltersAndTheEditor() {
        let a = W.Advanced.self
        #expect(a.title == "Advanced")
        #expect(a.footer == "Build a correction from filters of your own, set the preamp yourself, and import or export Equalizer APO files.")
        #expect(EQKind.allCases.map(a.type) == ["Peak", "Low shelf", "High shelf", "Low pass", "High pass", "Band pass", "Notch", "All pass"])
        let shelf = EQFilter(kind: .lowShelf, written: "LSC", fc: 105, gain: 2.6, width: .q(0.7))
        #expect(a.detail(shelf) == "105 Hz · +2.6 dB · Q 0.70")
        #expect(a.detail(EQFilter(kind: .peak, fc: 1000, gain: -3, width: .bandwidth(1), channel: .left)) == "1000 Hz · -3.0 dB · BW 1.0 oct · Left")
        #expect(a.detail(EQFilter(kind: .lowShelf, written: "LS", fc: 80, gain: 4, width: .slope(12), corner: true, channel: .right)) == "80 Hz · +4.0 dB · 12 dB/oct · Right")
        #expect(a.detail(EQFilter(kind: .highShelf, fc: 9000, gain: -2)) == "9000 Hz · -2.0 dB · S 0.9")
        #expect(a.detail(EQFilter(kind: .lowPass, fc: 18000)) == "18000 Hz · Q 0.71")
        #expect(a.detail(EQFilter(kind: .notch, fc: 60, width: .bandwidth(0))) == "60 Hz · BW 30.0 oct")
        #expect(a.detail(EQFilter(kind: .bandPass, fc: 1500, gain: 6, width: .q(2))) == "1500 Hz · Q 2.00")
        #expect(a.detail(EQFilter(kind: .peak, fc: 31.25, gain: 5)) == "31.25 Hz · +5.0 dB")
        let peak = EQFilter(kind: .peak, fc: 8903, gain: 6, width: .q(1.66))
        #expect(a.capsule(peak) == "Peak · 8903 Hz · +6.0 dB · Q 1.66")
        #expect(a.said(peak, number: 3) == "Filter 3: peak at 8903 hertz, plus 6 decibels, Q 1.66")
        var left = peak
        left.channel = .left
        #expect(a.said(left, number: 3) == "Filter 3: peak at 8903 hertz, plus 6 decibels, Q 1.66, left ear only")
        #expect(a.switchSaid(3) == "Filter 3 on" && a.on == "On" && a.off == "Off" && a.turnOn == "Turn On" && a.turnOff == "Turn Off")
        #expect(a.above == "Above what this output plays, so it's left out.")
        #expect(a.addFilter == "Add Filter" && a.mostFilters == "64 filters is the most deadwax plays" && a.delete == "Delete")
        let e = W.Editor.self
        #expect(e.title(3) == "Filter 3" && e.type == "Type" && e.frequency == "Frequency" && e.hz == "Hz")
        #expect(e.gain == "Gain" && e.dB == "dB" && e.q == "Q" && e.width == "Width" && e.octaves == "octaves")
        #expect(e.slope == "Slope" && e.dBAnOctave == "dB an octave" && e.useQ == "Use Q instead")
        #expect(e.corner(centredAt: 130.6) == "Its corner frequency, as Equalizer APO reads this shelf - it is centred at 131 Hz.")
        #expect(e.ear == "Ear" && e.both == "Both" && e.left == "Left" && e.right == "Right" && e.on == "On")
        #expect(e.deleteFilter == "Delete Filter")
        #expect(e.frequencyRange == "Between 1 and 22000 Hz." && e.gainRange == "Between -30 and 30 dB.")
        #expect(e.qRange == "Between 0.01 and 100." && e.widthRange == "Between 0.01 and 10.")
        //? said rounded down, so the slope it names is one that plays: 23 dB takes at most 23.855 dB an octave (1.3's
        //? line refuses 24 at 23 dB), and 27.8 dB at most 19.604 - the spec's example
        #expect(e.tooSteep(gain: 23) == "Too steep for this gain - at most 23.8 dB an octave.")
        #expect(e.tooSteep(gain: -27.8) == "Too steep for this gain - at most 19.6 dB an octave.")
        #expect(e.tooSteep(gain: 27.8) == "Too steep for this gain - at most 19.6 dB an octave.")
        #expect(e.tooSteep(gain: 0) == nil)
        #expect(e.placeholder(.lowPass) == "0.71" && e.placeholder(.notch) == "30" && e.placeholder(.highShelf) == "S 0.9")
        #expect(e.placeholder(.peak) == nil)
        let p = W.Preamp.self
        #expect(p.header == "Preamp" && p.automatic == "Automatic" && p.row == "Preamp" && p.value(-6.4) == "-6.4 dB")
        #expect(p.automaticFooter == "Takes away the curve's highest boost, so loud songs don't clip.")
        #expect(p.handFooter == "Yours, for every song on this output.")
    }

    @Test func importsWords() throws {
        let i = W.Import.self
        #expect(i.fromFiles == "Import from Files…" && i.importButton == "Import" && i.cancel == "Cancel")
        #expect(i.from(file: "HD650 ParametricEQ.txt") == "From \"HD650 ParametricEQ.txt\"")
        #expect(i.fromClipboard == "From the clipboard" && i.forLabel == "For" && i.skipped == "Skipped")
        #expect(i.refusedTitle == "Can't import this file" && i.done == "Done")
        guard case .success(let ten) = EQFixtures.read((1...10).map { "Filter: ON PK Fc \($0 * 100) Hz Gain 1 dB Q 1" }.joined(separator: "\n") + "\nPreamp: -6.4 dB"),
              case .success(let ears) = EQFixtures.read("Preamp: -6 dB\n" + (1...11).map { "Filter: ON PK Fc \($0 * 100) Hz Gain 1 dB Q 1" }.joined(separator: "\n")
                                                         + "\nChannel: L\nFilter: ON PK Fc 50 Hz Gain 1 dB Q 1\nFilter: ON PK Fc 60 Hz Gain 1 dB Q 1") else {
            Issue.record("refused")
            return
        }
        #expect(i.summary(ten) == "10 filters, preamp -6.4 dB")
        #expect(i.summary(ears) == "11 filters for both ears, 2 more for the left, preamp -6.0 dB")
        #expect(i.preampAutomatic(-6.1) == "Preamp: set by deadwax, -6.1 dB with this output's tone.")
        #expect(i.preampFiles(-6.4) == "Preamp: the file's, -6.4 dB.")
        #expect(i.replaces(output: "James's AirPods Pro", what: "Apple AirPods Pro, from AutoEq") == "It replaces the correction for James's AirPods Pro (Apple AirPods Pro, from AutoEq).")
        let graphic = try EQFixtures.graphic().fits[0]
        let fit = GraphicEQFit.fit([try GraphicEQFitTests.points(graphic.path)])
        #expect(i.converted(fit) == "Converted from a GraphicEQ curve: 54 filters, within 0.1 dB of it on average and 0.5 dB at most up to 16 kHz; above that, up to 5.0 dB.")
    }

    @Test func exportsWords() throws {
        let x = W.Export.self
        #expect(x.menu == "Export…" && x.whole == "The Whole Curve" && x.alone == "The Correction Alone")
        #expect(x.fileName("James's AirPods Pro") == "James's AirPods Pro EQ.txt")
        #expect(x.fileName("Car: A/B") == "Car AB EQ.txt")
        #expect(x.comments(output: "James's AirPods Pro", day: "2026-11-12", correction: Self.autoeq, tone: "Bass Boost") == [
            "deadwax EQ for James's AirPods Pro, 2026-11-12", "Correction: Apple AirPods Pro (AutoEq, measured by crinacle)",
            "Tone: Bass Boost"])
        let converted = EQCorrection(kind: .file, name: "Wavelet.txt", converted: true, nextFilterID: 1, filters: [])
        #expect(x.comments(output: "Headphones", day: "2026-11-12", correction: converted, tone: nil) == [
            "deadwax EQ for Headphones, 2026-11-12", "Correction: From Wavelet.txt, converted", "Converted from a GraphicEQ curve"])

        //? the whole curve: the correction by frequency, the tone's bands, the preamp as it plays - read back the same
        guard case .success(let reading) = APOReader.read(try Fixtures.data("eq/autoeq/results/crinacle/711 in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt")) else {
            Issue.record("refused")
            return
        }
        let correction = EQCorrection.autoeq(id: "x", name: "Apple AirPods Pro", source: "crinacle", rig: "711", form: "in-ear",
                                             text: "", reading: reading)
        let output = Self.output(on: true, correction: correction, tone: .preset("bassBoost"))
        let whole = APOWriter.export(output, in: Self.settings, whole: true, day: "2026-11-12")
        let bank = Self.settings.bank(output, rate: 48000, version: 1)
        #expect(bank.preamp == -8.5)
        #expect(whole == """
            # deadwax EQ for James's AirPods Pro, 2026-11-12
            # Correction: Apple AirPods Pro (AutoEq, measured by crinacle)
            # Tone: Bass Boost
            Preamp: -8.5 dB
            Filter 1: ON PK Fc 44 Hz Gain -0.5 dB Q 2.16
            Filter 2: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70
            Filter 3: ON PK Fc 183 Hz Gain 2.0 dB Q 0.77
            Filter 4: ON PK Fc 514 Hz Gain -4.4 dB Q 0.68
            Filter 5: ON PK Fc 618 Hz Gain -0.5 dB Q 2.86
            Filter 6: ON PK Fc 929 Hz Gain 1.2 dB Q 2.75
            Filter 7: ON PK Fc 1517 Hz Gain -1.0 dB Q 2.33
            Filter 8: ON PK Fc 4613 Hz Gain 3.4 dB Q 2.46
            Filter 9: ON PK Fc 8903 Hz Gain 6.0 dB Q 1.66
            Filter 10: ON HSC Fc 10000 Hz Gain -0.5 dB Q 0.70
            Filter 11: ON PK Fc 31.25 Hz Gain 5.0 dB Q 1.41
            Filter 12: ON PK Fc 62.5 Hz Gain 4.5 dB Q 1.41
            Filter 13: ON PK Fc 125 Hz Gain 3.0 dB Q 1.41
            Filter 14: ON PK Fc 250 Hz Gain 1.0 dB Q 1.41

            """)
        guard case .success(let back) = APOReader.read(Data(whole.utf8)) else {
            Issue.record("refused")
            return
        }
        #expect(back.filters.count == reading.filters.count + 4)
        #expect(zip(back.filters.prefix(reading.filters.count).map(\.fc), back.filters.prefix(reading.filters.count).map(\.fc).dropFirst()).allSatisfy { $0 <= $1 })
        #expect(back.preamp.all == bank.preamp)
        //? and it plays the same sections, bit for bit - in frequency order rather than the correction's
        func key(_ s: EQSection) -> [UInt64] {
            [s.coefficients.b0, s.coefficients.b1, s.coefficients.b2, s.coefficients.a1, s.coefficients.a2].map(\.bitPattern)
        }
        let played = EQBank.sections(back.filters, rate: 48000).map(key)
        #expect(played.sorted { $0.lexicographicallyPrecedes($1) } == bank.left.map(key).sorted { $0.lexicographicallyPrecedes($1) })
        let alone = APOWriter.export(output, in: Self.settings, whole: false, day: "2026-11-12")
        #expect(!alone.contains("Tone:") && alone.contains("Preamp: -6.0 dB\n"))
    }

    @Test func outputsAndVoiceOver() {
        let o = W.Outputs.self
        #expect(o.speaker == "iPhone speaker" && o.headphones == "Headphones" && o.others == "Other outputs")
        #expect(o.renameTitle == "Rename Output" && o.rename == "Rename" && o.forget == "Forget" && o.forgetThis == "Forget This Output")
        #expect(o.forgetQuestion("James's AirPods Pro") == "Forget James's AirPods Pro? Its EQ is deleted. It starts Off next time it connects.")
        #expect(o.cancel == "Cancel" && o.save == "Save")
        let s = W.Said.self
        #expect(s.curve == "The EQ's curve" && s.graphTitle("James's AirPods Pro") == "EQ curve for James's AirPods Pro")
        #expect(s.frequencyAxis == "Frequency" && s.gainAxis == "Gain" && s.whatYouHear == "What you hear")
        #expect(s.correction == "Correction" && s.tone == "Tone" && s.route("James's AirPods Pro") == "EQ for James's AirPods Pro")
        #expect(s.on == "EQ on" && s.off == "EQ off")
    }

    @Test func debugsRows() {
        let d = W.Debug.self
        let pods = EQRoutePort(port: .bluetoothA2DP, portType: "BluetoothA2DPOutput", name: "James's AirPods Pro", uid: "60:F8:1D:01-tacl")
        #expect(d.output([pods]) == "Bluetooth (A2DP) · James's AirPods Pro · 60:F8:1D:01-tacl")
        #expect(d.output([EQRoutePort(port: .other, portType: "Receiver", name: "Receiver", uid: "r")]) == "Receiver · Receiver · r")
        #expect(d.passing == "In the graph: passing every sample through" && d.filtering == "In the graph: filtering")
        #expect(d.crossfading == "In the graph: crossfading" && d.notMade("No such unit") == "Not made: No such unit")
        #expect(d.outOfTheGraph == "Out of the graph while Off")
        #expect(d.curve(both: 10, left: 0, right: 0, bands: 10, top: 6.3, at: 8903, preamp: -6.4, automatic: true)
                == "10 filters for both ears + 10 tone bands; its top +6.3 dB at 8.9 kHz; preamp -6.4 dB (automatic)")
        #expect(d.curve(both: 11, left: 2, right: 0, bands: 0, top: 4, at: 62.5, preamp: -6, automatic: false)
                == "11 filters for both ears, 2 more for the left; its top +4.0 dB at 63 Hz; preamp -6.0 dB (yours)")
        #expect(d.curve(both: 0, left: 0, right: 0, bands: 1, top: 3, at: 1000, preamp: -3, automatic: true)
                == "1 tone band; its top +3.0 dB at 1 kHz; preamp -3.0 dB (automatic)")
        #expect(d.atRate(48000, sections: 20, leftOut: 0) == "48 kHz: 20 sections a channel")
        #expect(d.atRate(48000, sections: 19, leftOut: 1) == "48 kHz: 19 sections a channel; 1 left out (above 23.5 kHz)")
        var c = EQRenderCounters()
        c.crossfades = 112
        c.waited = 3
        #expect(d.changes(c) == "112 crossfades; 3 waited for the one before; 0 made for another rate")
        #expect(d.overFullScale(c) == "None since the output started")
        c.overs = 14
        c.largest = pow(10, 0.8 / 20)
        #expect(d.overFullScale(c) == "14 samples since the output started, the loudest +0.8 dBFS")
        #expect(d.startedWith("AirPods Pro", msBefore: 0.1) == "AirPods Pro's curve, put in 0.1 ms before the output started")
        #expect(d.render(meanMs: 0.04, worstMs: 0.19, blockMs: 21.333, refused: 0) == "0.04 ms a block on average, 0.19 ms at worst - of 21.3 ms; refused blocks: 0")
        #expect(d.kept(outputs: 3, presets: 2, bytes: 4100) == "eq.json: 3 outputs, 2 presets of yours, 4.1 KB")
        #expect(d.kept(outputs: 1, presets: 1, bytes: 900) == "eq.json: 1 output, 1 preset of yours, 0.9 KB")
        #expect(d.setAside(EQSettings.unreadableName(day: "2026-11-12")) == "eq.json couldn't be read, so it was set aside as eq-unreadable-2026-11-12.json")
        #expect(d.muffle == "Muffle what plays")
    }

    @Test func slice2sDebugWords() {
        let d = W.Debug.self
        #expect(d.header == "EQ")
        #expect(d.stopped == "In the graph: the output is stopped")
        #expect(d.noEngine == "No audio engine yet: it's made when something first plays")
        #expect(d.startedWithTest(msBefore: 0.14) == "The test curve, put in 0.1 ms before the output started")
        #expect(d.startedOff(msBefore: 2.06) == "Off, put in 2.1 ms before the output started")
        #expect(d.startedWithNothing == "Nothing put in: the output started passing every sample through")
        #expect(d.notStarted == "The output hasn't started yet")
        #expect(d.muffleFooter.hasPrefix("A test of the EQ's audio unit: a -24 dB high shelf at 2 kHz"))
        #expect(d.muffleFooter.hasSuffix("It turns itself off when you leave Debug, and it's never kept."))
        //? slice 3: off, the output's own EQ plays - not "every sample passed through", which was slice 2's alone
        #expect(d.muffleFooter.contains("Off, the output's own EQ plays again."))
        #expect(d.waiting == "In the graph: waiting for its first block of sound")
        #expect(d.renderBlockAsked(0) == "iOS hasn't asked for it, so no sound can go through the EQ")
        #expect(d.renderBlockAsked(1) == "iOS asked for it once")
        #expect(d.renderBlockAsked(3) == "iOS asked for it 3 times")
        #expect(d.atRate(44_100, sections: 1, leftOut: 0) == "44.1 kHz: 1 section a channel")
        var c = EQRenderCounters()
        c.crossfades = 1
        #expect(d.changes(c) == "1 crossfade; 0 waited for the one before; 0 made for another rate")
    }
}
