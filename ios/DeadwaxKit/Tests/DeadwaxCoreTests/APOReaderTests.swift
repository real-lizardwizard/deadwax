import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.9 and 0.3: Equalizer APO's files read as APO reads them. Every fixture of Fixtures/eq/apo/ - one or more
/// for each accepted, skipped and refused case - read to what the script's own Python reader reads (apo.json): the
/// same filters bit for bit, the same preamp parts, GraphicEQ points and fit, and the same notes and refusals, word
/// for word and line for line. Then the rules 5.1 names, each on a line of its own, so a failure says which.
@Suite struct APOReaderTests {
    static let d = EQFixtures.d

    @Test func everyFixtureIsReadAsThePythonReaderReadsIt() throws {
        let file = try EQFixtures.apo()
        #expect(file.readings.count == 57)
        for c in file.readings {
            let result = APOReader.read(try EQFixtures.bytes(of: c), pasted: c.pasted)
            let expected = c.reading
            if let refused = expected.refused {
                guard case .failure(let r) = result else {
                    Issue.record("\(c.name): read, where the Python refuses it (\(refused.kind))")
                    continue
                }
                #expect(r.kind.rawValue == refused.kind, "\(c.name)")
                #expect(r.line == refused.line, "\(c.name)")
                #expect(r.text == refused.text, "\(c.name)")
                continue
            }
            guard case .success(let reading) = result else {
                Issue.record("\(c.name): refused (\(result)), where the Python reads it")
                continue
            }
            let filters = expected.filters!.map(\.filter)
            #expect(reading.filters.count == filters.count, "\(c.name): filters")
            for (mine, theirs) in zip(reading.filters, filters) {
                #expect(EQFixtures.sameBits(mine, theirs), "\(c.name): \(mine) where the Python reads \(theirs)")
            }
            #expect(reading.nextFilterID == filters.count + 1, "\(c.name)")

            //? exact, but for a converted GraphicEQ's median (within 1e-12 of NumPy's, as GraphicEQFitTests hold it)
            let fits = expected.fits ?? []
            let allowed = fits.isEmpty ? 0 : 1e-12
            let p = expected.preamp!
            #expect(abs(reading.preamp.all - Self.d(p["all"]!)) <= allowed, "\(c.name): preamp")
            #expect(abs(reading.preamp.left - Self.d(p["left"]!)) <= allowed, "\(c.name): preamp")
            #expect(abs(reading.preamp.right - Self.d(p["right"]!)) <= allowed, "\(c.name): preamp")

            let graphic = expected.graphic ?? []
            #expect(reading.graphic.count == graphic.count, "\(c.name): GraphicEQ lines")
            for (mine, theirs) in zip(reading.graphic, graphic) {
                #expect(mine.channel.rawValue == theirs.channel && mine.line == theirs.line, "\(c.name)")
                #expect(mine.points == theirs.points.map { GraphicEQPoint(Self.d($0[0]), Self.d($0[1])) }, "\(c.name)")
            }
            #expect(reading.fits.count == fits.count, "\(c.name): fits")
            for (mine, theirs) in zip(reading.fits, fits) {
                #expect(mine.ear.rawValue == theirs.ear, "\(c.name)")
                #expect(mine.fit.kept == theirs.filters && mine.fit.rounds == theirs.rounds, "\(c.name)")
                #expect(abs(mine.fit.median - Self.d(theirs.median)) <= 1e-12, "\(c.name): median")
                let s = mine.fit.stats48000
                #expect(abs(s.mean - Self.d(theirs.mean)) <= 1e-6 && abs(s.largest - Self.d(theirs.largest)) <= 1e-6
                        && abs(s.above - Self.d(theirs.above)) <= 1e-6 && s.aboveAt == Self.d(theirs.aboveAt), "\(c.name)")
            }

            let notes = expected.notes ?? []
            #expect(reading.notes.count == notes.count, "\(c.name): notes \(reading.notes.map(\.text))")
            for (mine, theirs) in zip(reading.notes, notes) {
                #expect(mine.kind.rawValue == theirs.kind, "\(c.name)")
                #expect(mine.first == theirs.first && mine.last == theirs.last, "\(c.name): \(mine.text)")
                #expect(mine.text == theirs.text, "\(c.name)")
            }
        }
    }

    /// Every refusal and every note of 3.9 is among the fixtures, so the test above has said each one.
    @Test func everyRefusalAndNoteIsAmongTheFixtures() throws {
        let readings = try EQFixtures.apo().readings.map(\.reading)
        let refused = Set(readings.compactMap { $0.refused?.kind })
        let noted = Set(readings.flatMap { $0.notes ?? [] }.map(\.kind))
        #expect(refused == Set(APORefusal.Kind.allCases.map(\.rawValue)))
        #expect(noted == Set(APONote.Kind.allCases.map(\.rawValue)))
    }

    /// AutoEq's ParametricEQ.txt files: read to their filters with nothing skipped, the file's preamp shared.
    @Test func everyAutoEqProfileIsReadToItsFilters() throws {
        for profile in try EQFixtures.profiles().profiles {
            guard case .success(let reading) = APOReader.read(try Fixtures.data("eq/\(profile.path)")) else {
                Issue.record("\(profile.name): refused")
                continue
            }
            #expect(reading.notes.isEmpty, "\(profile.name)")
            let filters = profile.filters.map(\.filter)
            #expect(reading.filters.count == filters.count && zip(reading.filters, filters).allSatisfy {
                EQFixtures.sameBits($0, $1)
            }, "\(profile.name)")
            #expect(reading.preamp == EQPreampParts(all: Self.d(profile.filePreamp), left: 0, right: 0), "\(profile.name)")
        }
    }

    /// The two GraphicEQ.txt files: their one line read to the points a plain parse gives, and converted by 3.10's fit.
    @Test func theGraphicEQFilesAreReadToTheirPoints() throws {
        for fit in try EQFixtures.graphic().fits {
            guard case .success(let reading) = APOReader.read(try Fixtures.data("eq/\(fit.path)")) else {
                Issue.record("\(fit.path): refused")
                continue
            }
            let points = try GraphicEQFitTests.points(fit.path)
            #expect(reading.graphic.map(\.points) == [points])
            #expect(reading.graphic.first?.channel == .all)
            let expected = GraphicEQFit.fit([points])
            #expect(reading.fits == [APOFit(ear: .all, fit: expected)])
            #expect(reading.filters == expected.filters(channel: .all, firstID: 1))
            #expect(reading.preamp == EQPreampParts(all: expected.median, left: 0, right: 0))
            #expect(reading.notes.isEmpty)
        }
    }

    // ------------------------------------------------------------ 5.1's rules, one at a time

    static func filters(_ text: String) -> [EQFilter] {
        guard case .success(let reading) = EQFixtures.read(text) else { return [] }
        return reading.filters
    }

    static func refusal(_ text: String) -> APORefusal? {
        guard case .failure(let refusal) = EQFixtures.read(text) else { return nil }
        return refusal
    }

    @Test func aCommaIsAPoint() {
        let f = Self.filters("Filter: ON PK Fc 100,5 Hz Gain -3,5 dB Q 1,41\n")
        #expect(f.map(\.fc) == [100.5] && f.map(\.gain) == [-3.5] && f.map(\.width) == [.q(1.41)])
    }

    @Test func aPointFourthFromTheEndIsThousands() {
        #expect(Self.filters("Filter: ON PK Fc 1.000 Hz Gain 1 dB Q 1").map(\.fc) == [1000])
        #expect(Self.filters("Filter: ON PK Fc 12.345 Hz Gain 1 dB Q 1").map(\.fc) == [12345])
        #expect(Self.filters("Filter: ON PK Fc 12.3450 Hz Gain 1 dB Q 1").map(\.fc) == [12.345])
        #expect(Self.filters("Filter: ON PK Fc 1.5e3 Hz Gain 1 dB Q 1").map(\.fc) == [1500])
    }

    @Test func keywordsAndCommandsKeepTheirCase() throws {
        #expect(Self.filters("Filter: ON PK fc 100 Hz Gain 1 dB Q 1\nPreamp: -1 dB").isEmpty)
        #expect(Self.filters("Filter: ON PK Fc 100 Hz gain 1 dB Q 1\nPreamp: -1 dB").isEmpty)
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain 1 dB q 1\nPreamp: -1 dB").isEmpty)
        #expect(Self.filters("Filter: on PK Fc 100 Hz Gain 1 dB Q 1\nPreamp: -1 dB").isEmpty)
        #expect(Self.filters("Filter: ON pk Fc 100 Hz Gain 1 dB Q 1\nPreamp: -1 dB").isEmpty)
        guard case .success(let reading) = EQFixtures.read("preamp: -6 dB\nFilter: ON PK Fc 100 Hz Gain 1 dB Q 1") else {
            Issue.record("refused")
            return
        }
        #expect(reading.preamp == .zero && reading.notes.map(\.kind) == [.unknown])
        //? a Channel line's words are upper-cased, as ChannelFilterFactory does
        #expect(Self.filters("Channel: l r\nFilter: ON PK Fc 100 Hz Gain 1 dB Q 1").map(\.channel) == [.all])
    }

    @Test func hzAndDBAreNeeded() {
        #expect(Self.filters("Filter: ON PK Fc 100 Gain 1 dB Q 1\nPreamp: 0 dB").isEmpty)
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain 1 Q 1\nPreamp: 0 dB").isEmpty)
        #expect(Self.filters("Filter: ON PK Fc 100 H z Gain 1 dB Q 1").map(\.fc) == [100])
    }

    @Test func numbersAreReadAsWcstodReadsThem() {
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain 6.5.1 dB Q 1").map(\.gain) == [6.5])
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain 1e dB Q 1").map(\.gain) == [1])
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain - dB Q 1").map(\.gain) == [0])
        #expect(Self.filters("Filter: ON PK Fc 100 Hz Gain -.5 dB Q .7").map(\.width) == [.q(0.7)])
    }

    /// wcstod's overflow is HUGE_VAL, its underflow 0 - and Swift's `Double(_:)` reads them the same way, never nil.
    @Test func anOverflowIsInfinityAndRefusedByItsRange() {
        #expect(Double("1e999") == .infinity && Double("-1e999") == -.infinity && Double("1e-999") == 0)
        #expect(Self.refusal("Filter: ON PK Fc 1e999 Hz Gain 1 dB Q 1")?.text
                == "Line 1: inf Hz is higher than this phone plays - the highest a filter can be is 22000 Hz.")
        #expect(Self.refusal("Filter: ON PK Fc -1e999 Hz Gain 1 dB Q 1")?.kind == .frequencyLow)
        #expect(Self.refusal("Filter: ON PK Fc 100 Hz Gain 1e999 dB Q 1")?.text
                == "Line 1: a gain of inf dB is more than deadwax plays - at most 30 dB either way.")
        #expect(Self.refusal("Filter: ON PK Fc 100 Hz Gain 1 dB Q 1e999")?.text
                == "Line 1: Q inf won't make a filter - it must be between 0.01 and 100, or left out.")
        #expect(Self.refusal("Filter: ON PK Fc 100 Hz Gain 1 dB BW Oct 1e999")?.text
                == "Line 1: a width of inf octaves won't make a filter - it must be between 0.01 and 10, or left out.")
        #expect(Self.refusal("Preamp: -1e999 dB")?.text
                == "Line 1: a preamp of -inf dB is more than deadwax plays - at most 30 dB either way.")
        #expect(Self.refusal("Filter: ON LS 1e999 dB Fc 100 Hz Gain 1 dB")?.text
                == "Line 1: a low-shelf filter this steep (inf dB an octave) can't have 1 dB of gain - Equalizer APO can't play it either.")
        #expect(Self.refusal("GraphicEQ: 20 0; 1000 1e999")?.kind == .gain)
        //? Q 1e-999 is 0: no width, so the peak is left out, and nothing is left
        #expect(Self.refusal("Filter: ON PK Fc 100 Hz Gain 1 dB Q 1e-999")?.kind == .nothing)
    }

    @Test func offIsKeptOff() {
        let f = Self.filters("Filter: OFF PK Fc 100 Hz Gain 1 dB Q 1")
        #expect(f.count == 1 && f[0].on == false)
    }

    @Test func keywordsInAnyOrder() {
        let f = Self.filters("Filter: ON PK Q 2 Gain -4 dB Fc 300 Hz")
        #expect(f.map(\.fc) == [300] && f.map(\.gain) == [-4] && f.map(\.width) == [.q(2)])
    }

    @Test func channelLinesChooseTheEar() {
        let text = """
        Filter: ON PK Fc 100 Hz Gain 1 dB Q 1
        Channel: R
        Filter: ON PK Fc 200 Hz Gain 1 dB Q 1
        Channel: L
        Filter: ON PK Fc 300 Hz Gain 1 dB Q 1
        Channel: 2
        Filter: ON PK Fc 400 Hz Gain 1 dB Q 1
        Channel: 1
        Filter: ON PK Fc 500 Hz Gain 1 dB Q 1
        """
        #expect(Self.filters(text).map(\.channel) == [.all, .right, .left, .right, .left])
    }

    @Test func preampsAddUpPerChannel() throws {
        guard case .success(let reading) = EQFixtures.read("Preamp: -3 dB\nPreamp: -2.5 dB\nChannel: L\nPreamp: -1 dB\nChannel: R\nPreamp: 1 dB") else {
            Issue.record("refused")
            return
        }
        //? left -1 and right +1: the larger, +1, is moved into the shared part
        #expect(reading.preamp == EQPreampParts(all: -4.5, left: -2, right: 0))
    }

    @Test func aGraphicEQsPointsAreSorted() throws {
        guard case .success(let reading) = EQFixtures.read("GraphicEQ: 1000 1; 20 2; 200 3; 200 4") else {
            Issue.record("refused")
            return
        }
        #expect(reading.graphic[0].points == [GraphicEQPoint(20, 2), GraphicEQPoint(200, 3), GraphicEQPoint(200, 4),
                                             GraphicEQPoint(1000, 1)])
        //? a comma is a point only on a line with no point anywhere
        guard case .success(let commas) = EQFixtures.read("GraphicEQ: 20 1,5; 1000 2") else { return }
        #expect(commas.graphic[0].points == [GraphicEQPoint(20, 1.5), GraphicEQPoint(1000, 2)])
        //? with a point on the line, a comma only separates: 20, 1, 5, 1000, 2.5 - the odd one out dropped
        guard case .success(let both) = EQFixtures.read("GraphicEQ: 20 1,5; 1000 2.5") else { return }
        #expect(both.graphic[0].points == [GraphicEQPoint(5, 1000), GraphicEQPoint(20, 1)])
    }

    @Test func aDeviceLineIsSkippedOnceAndRefusedTwice() throws {
        guard case .success(let one) = EQFixtures.read("Device: Speakers\nPreamp: -1 dB") else {
            Issue.record("refused")
            return
        }
        #expect(one.notes.map(\.kind) == [.device])
        #expect(Self.refusal("Device: Speakers\nDevice: Headphones\nPreamp: -1 dB")?.kind == .devices)
        #expect(Self.refusal("Device: Speakers\nDevice: Headphones\nPreamp: -1 dB")?.line == 2)
        #expect(Self.refusal("Preamp: -1 dB\nDevice: Speakers")?.kind == .devices)
    }

    @Test func aCROnlyFileIsRefusedAndAStrayCRIsNot() {
        #expect(Self.refusal("Preamp: -1 dB\rFilter: ON PK Fc 100 Hz Gain 1 dB Q 1\r")?.kind == .crOnly)
        #expect(Self.filters("Preamp: -1 dB\r\nFilter: ON PK Fc 100 Hz Gain 1 dB Q 1\r\n").count == 1)
    }

    @Test func aFileOfMaxBytesIsReadAndOneMoreIsNot() {
        let line = "Preamp: -1 dB\n"
        let exactly = line + String(repeating: " ", count: APOReader.maxBytes - line.utf8.count)
        #expect(Self.refusal(exactly) == nil)
        #expect(Self.refusal(exactly + " ")?.kind == .tooBig)
    }

    /// A long run of spaces is read once, not again from each space in it: the search for "Gain" or "Q" after a run
    /// of n spaces took n squared steps, and a 256 KB line of them hung the import for hours (eq.md 5.5's review).
    @Test func aLongRunOfSpacesIsReadInOnePass() {
        let text = "Filter: ON PK" + String(repeating: " ", count: 20_000) + "Fc 100 Hz Gain 1 dB Q 1\n"
        var filters: [EQFilter] = []
        let took = ContinuousClock().measure { filters = Self.filters(text) }
        #expect(filters.map(\.fc) == [100] && filters.map(\.gain) == [1] && filters.map(\.width) == [.q(1)])
        #expect(took < .seconds(2), "\(took)")
    }

    /// A band pass plays no gain but keeps the one written, for an export: an overflowing one - `wcstod`'s infinity - is
    /// refused by the gain's words, as any filter's, since eq.json can't hold an infinity and every save after it was
    /// lost. A finite one, however large, is kept.
    @Test func anInfiniteGainIsRefusedOnABandPassToo() throws {
        #expect(Self.refusal("Filter: ON BP Fc 100 Hz Gain 1e999 dB Q 1")?.text
                == "Line 1: a gain of inf dB is more than deadwax plays - at most 30 dB either way.")
        #expect(Self.filters("Filter: ON BP Fc 100 Hz Gain 1e300 dB Q 1").map(\.gain) == [1e300])
        // every reading of the fixtures is one eq.json can hold
        for c in try EQFixtures.apo().readings {
            let bytes = try EQFixtures.bytes(of: c)
            guard case .success(let reading) = APOReader.read(bytes, pasted: c.pasted) else { continue }
            var settings = EQSettings()
            var o = EQSettings.newOutput(EQOutputs.speaker, seen: "")
            o.correction = EQCorrection.file(name: "x.txt", text: EQImportRules.text(bytes), reading: reading)
            settings.outputs = [o]
            #expect(throws: Never.self, "\(c.name)") { _ = try settings.written() }
        }
    }

    /// A slope so gentle its shelf's S overflows - 1/S past the largest Double - makes no filter: its coefficients
    /// would be NaN, and a NaN in the bank is silence or noise. Refused, as a slope; the gentlest that plays still reads.
    @Test func aSlopeTooGentleToMakeAFilterIsRefused() {
        let r = Self.refusal("Filter: ON LSC 1e-310 dB Fc 100 Hz Gain 6 dB")
        #expect(r?.kind == .slope && r?.line == 1)
        #expect(r?.text == "Line 1: a slope of 1e-310 dB is too gentle to make a filter.")
        #expect(Self.refusal("Filter: ON HS 1e-308 dB Fc 1000 Hz Gain 0 dB")?.kind == .slope)
        let gentle = Self.filters("Filter: ON LSC 1e-300 dB Fc 100 Hz Gain 6 dB")
        #expect(gentle.count == 1)
        for f in gentle {
            for rate in [44_100.0, 48_000, 192_000] {
                let c = f.design(rate: rate).coefficients
                #expect(c != nil && [c!.b0, c!.b1, c!.b2, c!.a1, c!.a2].allSatisfy(\.isFinite), "\(rate)")
            }
        }
    }
}
