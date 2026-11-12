import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.11: an export, read back, gives the same filters bit for bit - every reader fixture and AutoEq profile,
/// alone and with each built-in preset on top - in AutoEq's own shape, per ear when it must be, and with an `Fc` APO
/// would read as thousands written so it reads back as itself.
@Suite struct APOWriterTests {
    /// Every correction the fixtures read to: the reader's (apo.json's readings that aren't refused) and AutoEq's.
    static func corrections() throws -> [(String, APOReading)] {
        var out: [(String, APOReading)] = []
        for c in try EQFixtures.apo().readings where c.reading.refused == nil {
            if case .success(let reading) = APOReader.read(try EQFixtures.bytes(of: c), pasted: c.pasted) {
                out.append((c.name, reading))
            }
        }
        for profile in try EQFixtures.profiles().profiles {
            if case .success(let reading) = APOReader.read(try Fixtures.data("eq/\(profile.path)")) {
                out.append((profile.name, reading))
            }
        }
        return out
    }

    /// The filters in the order a file writes them (shared, the left's, the right's), numbered from 1 as read back.
    static func asWritten(_ filters: [EQFilter]) -> [EQFilter] {
        let perEar = filters.contains { $0.channel != .all }
        let ordered = perEar ? [EQChannel.all, .left, .right].flatMap { ear in filters.filter { $0.channel == ear } } : filters
        return ordered.enumerated().map { (i: Int, f: EQFilter) -> EQFilter in
            var f = f
            f.id = i + 1
            return f
        }
    }

    /// An export of more than 64 filters for an ear - a converted GraphicEQ's 60 and a tone's 10 - is refused when
    /// it is read back, as any file is (3.9): the render plays 80, but an import is held to 64. Checked as such.
    @Test func everyFixtureAndPresetReadsBackTheSame() throws {
        let corrections = try Self.corrections()
        #expect(corrections.count == 31 + 14)
        var files = 0, tooMany = 0
        for (name, reading) in corrections {
            for preset in [nil] + EQGraphic.presets {
                let filters = APOWriter.curve(correction: reading.filters, bands: preset?.gains)
                let text = APOWriter.write(filters: filters, preamp: reading.preamp, comments: ["deadwax EQ for \(name)"])
                let most = [EQChannel.left, .right].map { ear in filters.filter { $0.channel == .all || $0.channel == ear }.count }.max()!
                if most > EQLimits.filtersPerEar {
                    guard case .failure(let refusal) = APOReader.read(Data(text.utf8)) else {
                        Issue.record("\(name) + \(preset?.id ?? "nothing"): \(most) filters for an ear read back")
                        continue
                    }
                    #expect(refusal.kind == .tooMany, "\(name)")
                    tooMany += 1
                    continue
                }
                guard case .success(let back) = APOReader.read(Data(text.utf8)) else {
                    Issue.record("\(name) + \(preset?.id ?? "nothing"): refused\n\(text)")
                    continue
                }
                let expected = Self.asWritten(filters)
                #expect(back.filters.count == expected.count, "\(name) + \(preset?.id ?? "nothing")")
                for (mine, theirs) in zip(back.filters, expected) {
                    #expect(EQFixtures.sameBits(mine, theirs), "\(name): \(mine) written as \(theirs)\n\(text)")
                }
                #expect(back.preamp == reading.preamp, "\(name)")
                #expect(back.notes.isEmpty && back.graphic.isEmpty, "\(name)")
                files += 1
            }
        }
        #expect(files + tooMany == (31 + 14) * 10)
        print("APOWriterTests: \(files) exports read back the same, bit for bit; \(tooMany) over 64 filters for an ear refused")
    }

    /// AutoEq's files are its own shape exactly: the reader's filters written back are the file, byte for byte.
    @Test func autoEqsFilesAreWrittenBackByteForByte() throws {
        for profile in try EQFixtures.profiles().profiles {
            let data = try Fixtures.data("eq/\(profile.path)")
            guard case .success(let reading) = APOReader.read(data) else {
                Issue.record("\(profile.name): refused")
                continue
            }
            #expect(APOWriter.write(filters: reading.filters, preamp: reading.preamp) == String(decoding: data, as: UTF8.self),
                    "\(profile.name)")
        }
    }

    @Test func autoEqsShape() {
        let filters = [
            EQFilter(id: 1, kind: .lowShelf, written: "LSC", fc: 105, gain: 2.6, width: .q(0.7)),
            EQFilter(id: 2, kind: .peak, fc: 31.25, gain: 5, width: .q(1.41)),
            EQFilter(id: 3, kind: .highShelf, written: "HS", fc: 9000, gain: -2, width: .slope(12), corner: true, on: false),
            EQFilter(id: 4, kind: .notch, fc: 60, width: .bandwidth(0)),
            EQFilter(id: 5, kind: .bandPass, fc: 1500, gain: 6),
            EQFilter(id: 6, kind: .lowPass, fc: 18000),
        ]
        let text = APOWriter.write(filters: filters, preamp: EQPreampParts(all: -7.1, left: 0, right: 0),
                                   comments: ["deadwax EQ for James's AirPods Pro, 2026-11-12", "Tone:\nBass Boost"])
        #expect(text == """
        # deadwax EQ for James's AirPods Pro, 2026-11-12
        # Tone: Bass Boost
        Preamp: -7.1 dB
        Filter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70
        Filter 2: ON PK Fc 31.25 Hz Gain 5.0 dB Q 1.41
        Filter 3: OFF HS 12 dB Fc 9000 Hz Gain -2.0 dB
        Filter 4: ON NO Fc 60 Hz BW Oct 0.00
        Filter 5: ON BP Fc 1500 Hz Gain 6.0 dB
        Filter 6: ON LP Fc 18000 Hz

        """)
    }

    @Test func perEar() {
        let filters = [
            EQFilter(id: 1, kind: .peak, fc: 100, gain: 1, width: .q(1), channel: .right),
            EQFilter(id: 2, kind: .peak, fc: 200, gain: 2, width: .q(1)),
            EQFilter(id: 3, kind: .peak, fc: 300, gain: 3, width: .q(1), channel: .left),
        ]
        let text = APOWriter.write(filters: filters, preamp: EQPreampParts(all: -6, left: -1.5, right: 0))
        #expect(text == """
        Preamp: -6.0 dB
        Channel: all
        Filter 1: ON PK Fc 200 Hz Gain 2.0 dB Q 1.00
        Channel: L
        Preamp: -1.5 dB
        Filter 2: ON PK Fc 300 Hz Gain 3.0 dB Q 1.00
        Channel: R
        Filter 3: ON PK Fc 100 Hz Gain 1.0 dB Q 1.00

        """)
        //? a per-ear preamp alone makes it per ear; a flat curve's -0 is written 0.0
        #expect(APOWriter.write(filters: [], preamp: EQPreampParts(all: -0.0, left: 0, right: -2)) == """
        Preamp: 0.0 dB
        Channel: all
        Channel: L
        Channel: R
        Preamp: -2.0 dB

        """)
    }

    /// 3.11: `12.345 Hz` would come back as 12345 Hz; a trailing zero keeps it.
    @Test func anFcAPOWouldReadAsThousandsGainsAZero() {
        #expect(APOWriter.frequency(12.345) == "12.3450")
        #expect(APOWriter.frequency(1.5) == "1.5" && APOWriter.frequency(1000) == "1000")
        #expect(APOWriter.frequency(123.456) == "123.4560" && APOWriter.frequency(1234.567) == "1234.5670")
        #expect(APOWriter.frequency(20.125) == "20.1250" && APOWriter.frequency(1.001) == "1.0010")
        #expect(APOWriter.frequency(1234.56) == "1234.56" && APOWriter.frequency(12.3456) == "12.3456")
        //? every three-decimal Fc from 1 to 22000 Hz in steps of a prime number of thousandths, read back as itself
        var checked = 0
        var x = 1000
        while x <= 22_000_000 {
            let fc = Double(x) / 1000
            let f = EQFilter(kind: .peak, fc: fc, gain: 1, width: .q(1))
            guard case .success(let back) = EQFixtures.read(APOWriter.write(filters: [f], preamp: .zero)) else {
                Issue.record("\(fc): refused")
                return
            }
            if back.filters.first?.fc.bitPattern != fc.bitPattern { Issue.record("\(fc) read back as \(back.filters.first?.fc ?? -1)") }
            checked += 1
            x += 997
        }
        #expect(checked > 20_000)
    }

    @Test func numbersAreShortestAndPlain() {
        #expect(APOWriter.number(105, decimals: 0) == "105")
        #expect(APOWriter.number(2.6, decimals: 1) == "2.6" && APOWriter.number(5, decimals: 1) == "5.0")
        #expect(APOWriter.number(0.7, decimals: 2) == "0.70" && APOWriter.number(1.41, decimals: 2) == "1.41")
        #expect(APOWriter.number(0.7071067811865476, decimals: 2) == "0.7071067811865476")
        #expect(APOWriter.number(1e-5, decimals: 2) == "0.00001" && APOWriter.number(-2.5e-7, decimals: 1) == "-0.00000025")
        #expect(APOWriter.number(1.25e20, decimals: 0) == "125000000000000000000")
        #expect(APOWriter.number(-0.0, decimals: 1) == "-0.0")
        for x in [1e-5, -2.5e-7, 1.25e20, 0.1 + 0.2, 1.0 / 3, 22000, 4.32] {
            #expect(Double(APOWriter.number(x, decimals: 2)) == x)
        }
    }
}
