import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.8 (slice 5, Advanced): the filter list's order and numbers, the 64-an-ear limit, Add Filter, an edit
/// marking AutoEq's correction changed and "Back to AutoEq's", the preamp set by hand, an import's preamp; the handles
/// - where each is drawn, which a touch takes, a drag and a pinch; and the editor's fields, steps, type change and
/// "Use Q instead".
@Suite struct EQAdvancedTests {
    static let airpods = EQOutputs.output(EQRoutePort(port: .bluetoothA2DP, portType: "BluetoothA2DPOutput",
                                                      name: "James's AirPods Pro", uid: "60:F8:1D:01-tacl"))
    static let speaker = EQOutputs.speaker

    static func peak(_ id: Int, _ fc: Double, _ gain: Double = 3, q: Double = 1, channel: EQChannel = .all,
                     on: Bool = true) -> EQFilter {
        EQFilter(id: id, kind: .peak, fc: fc, gain: gain, width: .q(q), channel: channel, on: on)
    }

    static func built(_ filters: [EQFilter]) -> EQCorrection {
        EQCorrection(kind: .built, name: "", nextFilterID: (filters.map(\.id).max() ?? 0) + 1, filters: filters)
    }

    /// AutoEq's AirPods Pro, as "Use for" keeps it.
    static func autoEq() throws -> EQCorrection {
        let path = "eq/autoeq/results/crinacle/711 in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt"
        let data = try Fixtures.data(path)
        guard case .success(let reading) = APOReader.read(data) else { throw Failure.unread }
        return EQCorrection.autoeq(id: "crinacle/711 in-ear/Apple AirPods Pro", name: "Apple AirPods Pro",
                                   source: "crinacle", rig: "711", form: "in-ear",
                                   text: String(decoding: data, as: UTF8.self), reading: reading)
    }

    enum Failure: Error { case unread }

    static func settings(_ correction: EQCorrection?, on: Bool = true, preamp: EQPreampSetting = .automatic)
        -> EQSettings {
        var settings = EQSettings()
        var s = EQSettings.newOutput(airpods, seen: "2026-11-12T10:00:00Z")
        s.on = on
        s.correction = correction
        s.preamp = preamp
        settings.outputs = [s]
        return settings
    }

    // MARK: the list (3.8)

    /// By frequency, low to high as the handles run; two at one frequency in the correction's own order; numbered
    /// from 1 - the number an export gives each.
    @Test func rowsRunByFrequency() {
        let c = Self.built([Self.peak(1, 8903), Self.peak(2, 105), Self.peak(3, 514), Self.peak(4, 105, 1)])
        let rows = EQAdvancedRules.rows(c, rate: 48_000)
        #expect(rows.map(\.filter.id) == [2, 4, 3, 1])
        #expect(rows.map(\.number) == [1, 2, 3, 4])
        #expect(EQAdvancedRules.number(of: 1, in: c) == 4)
        #expect(EQAdvancedRules.number(of: 4, in: c) == 2)
        #expect(EQAdvancedRules.number(of: 9, in: c) == nil)
        #expect(EQAdvancedRules.rows(nil, rate: 48_000).isEmpty)
        // the same order and numbers as an export (3.11)
        let written = APOWriter.write(filters: APOWriter.curve(correction: c.filters, bands: nil), preamp: .zero)
        #expect(written.contains("Filter 2: ON PK Fc 105 Hz Gain 1.0 dB Q 1.00"))
        #expect(written.contains("Filter 4: ON PK Fc 8903 Hz Gain 3.0 dB Q 1.00"))
    }

    /// "Above what this output plays": a filter that is on whose f0 is at or above 0.49 of the rate - at 44.1 kHz,
    /// not at 48. An Off one says nothing (its switch does).
    @Test func aFilterAboveTheRateSaysSo() {
        let c = Self.built([Self.peak(1, 21_800), Self.peak(2, 21_800, on: false), Self.peak(3, 1000)])
        let at44 = EQAdvancedRules.rows(c, rate: 44_100)
        #expect(at44.map(\.leftOut) == [false, true, false])
        #expect(at44.map(\.filter.id) == [3, 1, 2])
        #expect(EQAdvancedRules.rows(c, rate: 48_000).allSatisfy { !$0.leftOut })
    }

    /// 64 an ear (3.8): the shared filters count for both, an ear's own for it alone.
    @Test func sixtyFourAnEar() {
        let shared = (1...63).map { Self.peak($0, Double(100 + $0)) }
        #expect(EQAdvancedRules.canAdd(Self.built(shared)))
        #expect(EQAdvancedRules.canAdd(nil))
        let full = shared + [Self.peak(64, 5000)]
        #expect(!EQAdvancedRules.canAdd(Self.built(full)))
        #expect(EQAdvancedRules.fits(full))
        #expect(!EQAdvancedRules.fits(full + [Self.peak(65, 6000, channel: .left)]))
        // 60 shared and 4 for the left: the left is full, the right has room - Add Filter adds for both
        let leftFull = Array(shared.prefix(60)) + (61...64).map { Self.peak($0, 7000, channel: .left) }
        #expect(EQAdvancedRules.perEar(leftFull) == (left: 64, right: 60))
        #expect(!EQAdvancedRules.canAdd(Self.built(leftFull)))
        #expect(EQWords.Advanced.mostFilters == "64 filters is the most deadwax plays")
    }

    /// The editor's Ear: only when the correction has one ear's filter or preamp.
    @Test func earOnlyWhenPerEar() {
        #expect(!EQAdvancedRules.showsEar(nil))
        #expect(!EQAdvancedRules.showsEar(Self.built([Self.peak(1, 100)])))
        #expect(EQAdvancedRules.showsEar(Self.built([Self.peak(1, 100), Self.peak(2, 200, channel: .right)])))
        var c = Self.built([Self.peak(1, 100)])
        c.preamp = EQPreampParts(all: -3, left: -1, right: 0)
        #expect(EQAdvancedRules.showsEar(c))
    }

    // MARK: changes (3.8)

    /// Add Filter with no correction begins your own ("Your own filters"): a Peak at 1000 Hz, 0 dB, Q 1.00, id 1 -
    /// and, while Off, turns the EQ on (8, question 9).
    @Test func addFilterBeginsYourOwn() {
        var settings = Self.settings(nil, on: false)
        let added = settings.addFilter(for: Self.airpods)
        #expect(added?.id == 1 && added?.turnedOn == true)
        let s = settings.output(Self.airpods.key)!
        #expect(s.on)
        #expect(s.correction?.kind == .built && s.correction?.nextFilterID == 2)
        #expect(s.correction?.filters == [EQFilter(id: 1, kind: .peak, written: "PK", fc: 1000, gain: 0, width: .q(1))])
        #expect(EQWords.Correction.value(s.correction) == "Your own filters")
        // the next one, id 2; a counter behind its ids (a file kept so) never gives one twice
        #expect(settings.addFilter(for: Self.airpods)?.id == 2)
        var behind = Self.built([Self.peak(7, 100)])
        behind.nextFilterID = 3
        var other = Self.settings(behind)
        #expect(other.addFilter(for: Self.airpods)?.id == 8)
        #expect(other.output(Self.airpods.key)?.correction?.nextFilterID == 9)
    }

    /// At 64 an ear, nothing is added.
    @Test func addFilterAtSixtyFour() {
        var settings = Self.settings(Self.built((1...64).map { Self.peak($0, Double(100 + $0)) }))
        let before = settings
        #expect(settings.addFilter(for: Self.airpods) == nil)
        #expect(settings == before)
    }

    /// Editing AutoEq's correction makes it yours: "- changed", and "Back to AutoEq's" puts it back as it came.
    @Test func anEditMarksAutoEqChangedAndBackPutsItBack() throws {
        let original = try Self.autoEq()
        var settings = Self.settings(original)
        #expect(!EQAdvancedRules.goesBack(original))
        #expect(EQWords.Correction.source(original) == "AutoEq, measured by crinacle")
        let id = original.filters[2].id
        settings.editFilter(id, for: Self.airpods) { (f: inout EQFilter) -> Void in f.gain = 4 }
        var edited = settings.output(Self.airpods.key)!.correction!
        #expect(edited.changed && edited.filters[2].gain == 4)
        #expect(EQWords.Correction.source(edited) == "AutoEq, measured by crinacle - changed")
        #expect(EQAdvancedRules.goesBack(edited))
        settings.deleteFilter(original.filters[0].id, for: Self.airpods)
        settings.addFilter(for: Self.airpods)
        edited = settings.output(Self.airpods.key)!.correction!
        #expect(edited.filters.count == 10 && edited.changed)
        #expect(settings.backToAutoEq(for: Self.airpods) == false)
        #expect(settings.output(Self.airpods.key)?.correction == original)
        // nothing to go back to now, nor for a file
        #expect(!EQAdvancedRules.goesBack(original))
        var file = EQCorrection.file(name: "HD650.txt", text: "", reading: APOReading(
            filters: [Self.peak(1, 100)], preamp: .zero, graphic: [], fits: [], notes: []))
        file.changed = true
        #expect(!EQAdvancedRules.goesBack(file))
    }

    /// An edit that changes nothing changes nothing; one that would take an ear past 64 is refused; the id stays.
    @Test func editsThatChangeNothing() {
        let shared = (1...63).map { Self.peak($0, Double(100 + $0)) }
        let c = Self.built(shared + [Self.peak(64, 5000, channel: .left)])
        var settings = Self.settings(c, on: false)
        let before = settings
        #expect(settings.editFilter(1, for: Self.airpods) { (f: inout EQFilter) -> Void in f.gain = 3 } == false)
        #expect(settings == before)
        // the left's own to both ears: the right then has 64 too - it fits; and Add Filter has no room left
        #expect(settings.editFilter(64, for: Self.airpods) { (f: inout EQFilter) -> Void in f.channel = .all } == true)
        #expect(settings.output(Self.airpods.key)?.on == true)
        settings.addFilter(for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.correction?.filters.count == 64)
        // an id is never changed by an edit
        settings.editFilter(2, for: Self.airpods) { (f: inout EQFilter) -> Void in
            f.id = 99
            f.gain = 5
        }
        #expect(settings.output(Self.airpods.key)?.correction?.filters[1].id == 2)
        #expect(settings.output(Self.airpods.key)?.correction?.filters[1].gain == 5)
        // a row's switch
        settings.setFilter(2, on: false, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.correction?.filters[1].on == false)
    }

    /// The last of your own filters deleted is no correction at all - None - with the switch left as it is.
    @Test func deletingTheLastOfYourOwn() {
        var settings = Self.settings(Self.built([Self.peak(1, 100), Self.peak(2, 200)]), on: false)
        #expect(settings.deleteFilter(1, for: Self.airpods) == true)
        #expect(settings.output(Self.airpods.key)?.correction?.filters.map(\.id) == [2])
        settings.setOn(false, for: Self.airpods)
        #expect(settings.deleteFilter(2, for: Self.airpods) == false)
        #expect(settings.output(Self.airpods.key)?.correction == nil)
        #expect(settings.output(Self.airpods.key)?.on == false)
        #expect(settings.deleteFilter(2, for: Self.airpods) == false)
    }

    /// Automatic off begins at the preamp playing - nothing heard changes - and the stepper's value is held to 0.1 dB,
    /// -30 to +12, never "-0".
    @Test func thePreampByHand() {
        var settings = Self.settings(Self.built([Self.peak(1, 100, 6)]))
        settings.setAutomaticPreamp(false, played: -6.0, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(-6))
        // already by hand: Automatic off again keeps yours
        settings.setHandPreamp(-2.04, for: Self.airpods)
        settings.setAutomaticPreamp(false, played: -6.0, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(-2))
        settings.setHandPreamp(14, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(12))
        settings.setHandPreamp(-31, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(-30))
        #expect(EQAdvancedRules.handPreamp(-0.04).sign == .plus)
        settings.setAutomaticPreamp(true, played: 0, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .automatic)
    }

    /// An import is the output's correction, the EQ on; with the preamp set by hand, the file's own, held to the range
    /// (1.4).
    @Test func anImportsPreamp() {
        var c = Self.built([Self.peak(1, 100)])
        c.preamp = EQPreampParts(all: 15, left: 0, right: 0)
        var settings = Self.settings(nil, on: false, preamp: .hand(-3))
        #expect(settings.importCorrection(c, for: Self.airpods) == true)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(12))
        #expect(settings.output(Self.airpods.key)?.correction == c)
        c.preamp.all = -6.4
        settings.importCorrection(c, for: Self.airpods)
        #expect(settings.output(Self.airpods.key)?.preamp == .hand(-6.4))
        var automatic = Self.settings(nil, preamp: .automatic)
        automatic.importCorrection(c, for: Self.airpods)
        #expect(automatic.output(Self.airpods.key)?.preamp == .automatic)
    }

    // MARK: the handles (3.8)

    /// One for each filter that is on, at its f0 - a corner shelf's centre - and its own gain; 0 dB for a pass.
    @Test func whereHandlesAre() {
        let corner = EQFilter(id: 3, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .q(0.7), corner: true)
        let c = Self.built([Self.peak(1, 1000, 6), Self.peak(2, 500, on: false), corner,
                            EQFilter(id: 4, kind: .highPass, fc: 30, width: .q(0.5)),
                            EQFilter(id: 5, kind: .peak, fc: 800, gain: 3)])
        let handles = EQHandleRules.handles(c)
        #expect(handles.map(\.id) == [1, 3, 4, 5])
        #expect(handles[0] == EQHandle(id: 1, frequency: 1000, gain: 6))
        #expect(handles[1].frequency == corner.f0 && handles[1].frequency > 100 && handles[1].gain == 5)
        #expect(handles[2] == EQHandle(id: 4, frequency: 30, gain: 0))
        // a peak with no width plays nothing, but its handle is there, at its Fc
        #expect(handles[3] == EQHandle(id: 5, frequency: 800, gain: 3))
    }

    /// A touch takes the nearest handle within 22 pt; none near, it is the list's. A handle past an edge is drawn at it.
    @Test func aTouchTakesTheNearest() {
        let w = 350.0, h = 220.0, r = 15.0
        let handles = [EQHandle(id: 1, frequency: 1000, gain: 0), EQHandle(id: 2, frequency: 1100, gain: 0)]
        let p1 = EQHandleRules.point(handles[0], width: w, height: h, range: r)
        let p2 = EQHandleRules.point(handles[1], width: w, height: h, range: r)
        #expect(p1.y == 110)
        #expect(EQHandleRules.nearest(handles, x: p1.x + 1, y: 110, width: w, height: h, range: r) == 1)
        #expect(EQHandleRules.nearest(handles, x: p2.x - 1, y: 110, width: w, height: h, range: r) == 2)
        #expect(EQHandleRules.nearest(handles, x: p1.x, y: 110 + 21.9, width: w, height: h, range: r) == 1)
        #expect(EQHandleRules.nearest(handles, x: p1.x, y: 110 - 22.1, width: w, height: h, range: r) == nil)
        #expect(EQHandleRules.nearest([], x: 0, y: 0, width: w, height: h, range: r) == nil)
        let off = EQHandleRules.point(EQHandle(id: 3, frequency: 10, gain: 30), width: w, height: h, range: r)
        #expect(off.x == 0 && off.y == 0)
        // across the plot and back
        for f in [22.1, 100.0, 1000, 8903, 20_000] {
            let x = EQDrawing.x(f, width: w)
            #expect(abs(EQHandleRules.frequency(x: x, width: w) / f - 1) < 1e-12)
        }
    }

    /// A drag: sideways the frequency (1 Hz under 1 kHz, 10 Hz above), up and down the gain (0.1 dB) - each only when
    /// the finger moved along it, so a value as imported is kept exactly until it is dragged.
    @Test func aDrag() {
        let w = 350.0, h = 220.0, r = 15.0
        let start = EQFilter(id: 1, kind: .peak, fc: 31.25, gain: 2.55, width: .q(1.41))
        let up = EQHandleRules.dragged(start, dx: 0, dy: -h * 6.02 / 30, width: w, height: h, range: r)
        #expect(up.fc == 31.25 && up.gain == 8.6)
        let across = EQHandleRules.dragged(start, dx: w / 10 + 0.1, dy: 0, width: w, height: h, range: r)
        #expect(across.gain == 2.55 && across.fc == 63)
        // an octave up, to the hertz
        #expect(EQHandleRules.dragged(Self.peak(1, 40), dx: w / 10, dy: 0, width: w, height: h, range: r).fc == 80)
        // an octave up from 1 kHz: to 10 Hz above 1 kHz
        let high = EQHandleRules.dragged(Self.peak(1, 1003), dx: w / 10, dy: 0, width: w, height: h, range: r)
        #expect(high.fc == 2010)
        // held to ±30 dB and, by a finger, 20 Hz to 20 kHz
        #expect(EQHandleRules.dragged(start, dx: 0, dy: -10 * h, width: w, height: h, range: r).gain == 30)
        #expect(EQHandleRules.dragged(start, dx: 0, dy: 10 * h, width: w, height: h, range: r).gain == -30)
        #expect(EQHandleRules.dragged(start, dx: -w, dy: 0, width: w, height: h, range: r).fc == 20)
        #expect(EQHandleRules.dragged(Self.peak(1, 1000), dx: 2 * w, dy: 0, width: w, height: h, range: r).fc == 20_000)
        // ... stretched to take in where it began
        let low = EQFilter(id: 1, kind: .peak, fc: 12, gain: 1, width: .q(1))
        #expect(EQHandleRules.dragged(low, dx: -w, dy: 0, width: w, height: h, range: r).fc == 12)
        // a pass has no gain to drag
        let pass = EQFilter(id: 1, kind: .highPass, fc: 30, width: .q(0.5))
        #expect(EQHandleRules.dragged(pass, dx: 0, dy: -h, width: w, height: h, range: r) == pass)
        // never "-0"
        let zero = EQHandleRules.dragged(EQFilter(id: 1, kind: .peak, fc: 1000, gain: -0.04, width: .q(1)), dx: 0,
                                         dy: -0.2, width: w, height: h, range: r)
        #expect(zero.gain == 0 && zero.gain.sign == .plus)
    }

    /// A corner shelf (LS with a Q) is drawn at its centre and keeps its corner: dragged an octave, its Fc moves an
    /// octave. A shelf with a slope stops where the slope would be too steep for it (1.3).
    @Test func aShelfsDrag() {
        let w = 350.0, h = 220.0, r = 15.0
        let corner = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .q(0.7), corner: true)
        let moved = EQHandleRules.dragged(corner, dx: w / 10, dy: 0, width: w, height: h, range: r)
        #expect(moved.fc == 200 && moved.corner && moved.written == "LS")
        let steep = EQFilter(id: 2, kind: .lowShelf, written: "LSC", fc: 100, gain: 2, width: .slope(24))
        let most = EQCookbook.steepestSlope(gain: 2)!
        #expect(most > 24)
        let pushed = EQHandleRules.dragged(steep, dx: 0, dy: -h, width: w, height: h, range: r)
        #expect(EQCookbook.shelfRadicand(gain: pushed.gain, s: 2) > 0)
        #expect(EQCookbook.shelfRadicand(gain: pushed.gain + 0.1, s: 2) <= 0)
        #expect(pushed.design(rate: 48_000).outcome == .plays)
    }

    /// A finger moves nothing until it has gone 4 pt (a tap selects); then the handle follows it from there, without a
    /// jump - and the range it began with holds, however the axis grows under it.
    @Test func aDragEngages() {
        let start = Self.peak(1, 1000, 0)
        var drag = EQHandleDrag(start: start, range: 15)
        #expect(drag.filter(dx: 1, dy: -2, width: 350, height: 220) == nil)
        #expect(drag.filter(dx: 0, dy: -4, width: 350, height: 220) == start)
        #expect(drag.filter(dx: 0, dy: -4 - 22, width: 350, height: 220)?.gain == 3)
        #expect(drag.filter(dx: 0, dy: -4 - 22, width: 350, height: 110)?.gain == 6)
    }

    /// A pinch: spread, wider - a Q down, a width in octaves up, a slope gentler - each in its own form, to its step,
    /// inside its range stretched to take in where it began; a filter given no width starts from its Q.
    @Test func aPinch() {
        #expect(EQHandleRules.pinched(Self.peak(1, 1000, q: 2), scale: 2).width == .q(1))
        #expect(EQHandleRules.pinched(Self.peak(1, 1000, q: 2), scale: 0.01).width == .q(20))
        #expect(EQHandleRules.pinched(Self.peak(1, 1000, q: 2), scale: 1000).width == .q(0.1))
        #expect(EQHandleRules.pinched(Self.peak(1, 1000, q: 40), scale: 0.5).width == .q(40))
        #expect(EQHandleRules.pinched(Self.peak(1, 1000, q: 2), scale: 1.001).width == .q(2))
        let bw = EQFilter(id: 1, kind: .peak, fc: 1000, gain: 3, width: .bandwidth(1))
        #expect(EQHandleRules.pinched(bw, scale: 1.5).width == .bandwidth(1.5))
        let slope = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(12))
        #expect(EQHandleRules.pinched(slope, scale: 2).width == .slope(6))
        let steepest = EQHandleRules.pinched(slope, scale: 0.01)
        if case .slope(let s)? = steepest.width {
            #expect(EQCookbook.shelfRadicand(gain: 6, s: s / 12) > 0)
            #expect(EQCookbook.shelfRadicand(gain: 6, s: (s + 0.1) / 12) <= 0)
        } else {
            Issue.record("a slope pinched is a slope")
        }
        let pass = EQFilter(id: 1, kind: .lowPass, fc: 10_000)
        #expect(EQHandleRules.pinched(pass, scale: 0.5).width == .q(1.41))
        let none = EQFilter(id: 1, kind: .peak, fc: 1000, gain: 3)
        #expect(EQHandleRules.pinched(none, scale: 2).width == .q(0.5))
    }

    // MARK: the editor (3.8)

    /// The width row: Slope for a shelf written with one, Width for a filter written with BW Oct, else Q.
    @Test func whichWidthRow() {
        #expect(EQEditorRules.widthField(Self.peak(1, 100)) == .q)
        #expect(EQEditorRules.widthField(EQFilter(id: 1, kind: .peak, fc: 100, gain: 1, width: .bandwidth(1))) == .width)
        #expect(EQEditorRules.widthField(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 1, width: .slope(12))) == .slope)
        // a shelf reads no BW, anything else no slope: each shows its Q, with its type's default
        #expect(EQEditorRules.widthField(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 1, width: .bandwidth(1))) == .q)
        #expect(EQEditorRules.widthField(EQFilter(id: 1, kind: .notch, fc: 100, width: .slope(12))) == .q)
        #expect(EQEditorRules.widthField(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 1)) == .q)
        #expect(EQEditorRules.value(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 1), .q) == nil)
        #expect(EQEditorRules.value(EQFilter(id: 1, kind: .lowPass, fc: 100, width: .q(0)), .q) == nil)
        #expect(EQWords.Editor.placeholder(.lowShelf) == "S 0.9")
    }

    /// The fields' text: AutoEq's decimals at least, and more where the value needs them; the phone's decimal mark.
    @Test func fieldText() {
        let f = EQFilter(id: 1, kind: .peak, fc: 31.25, gain: -6, width: .q(0.7))
        #expect(EQEditorRules.text(f, .frequency) == "31.25")
        #expect(EQEditorRules.text(f, .gain) == "-6.0")
        #expect(EQEditorRules.text(f, .q) == "0.70")
        #expect(EQEditorRules.text(f, .q, decimal: ",") == "0,70")
        #expect(EQEditorRules.text(Self.peak(1, 8903), .frequency) == "8903")
        #expect(EQEditorRules.text(EQFilter(id: 1, kind: .lowPass, fc: 100), .q) == "")
        #expect(EQEditorRules.text(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 1, width: .slope(12)), .slope) == "12")
    }

    /// A field's text read: a comma or a point, a sign (the typographic minus too), spaces - nothing else.
    @Test func parsing() {
        #expect(EQEditorRules.parse("6,5") == 6.5)
        #expect(EQEditorRules.parse(" -3.25 ") == -3.25)
        #expect(EQEditorRules.parse("+2") == 2)
        #expect(EQEditorRules.parse(String(Character(Unicode.Scalar(0x2212)!)) + "4") == -4)
        #expect(EQEditorRules.parse(".5") == 0.5)
        for bad in ["", " ", "abc", "1e3", "1.2.3", "6 dB", "inf", "nan", "--1"] {
            #expect(EQEditorRules.parse(bad) == nil, "\(bad)")
        }
    }

    /// Out of range, the line under the field - "Between 1 and 22000 Hz." and the rest - and nothing changes; in
    /// range, the value; an empty Q or Width where the type has a default, none.
    @Test func checking() {
        let peak = Self.peak(1, 1000)
        #expect(EQEditorRules.check("22000", .frequency, for: peak) == .value(22_000))
        #expect(EQEditorRules.check("22001", .frequency, for: peak) == .problem("Between 1 and 22000 Hz."))
        #expect(EQEditorRules.check("0,5", .frequency, for: peak) == .problem("Between 1 and 22000 Hz."))
        #expect(EQEditorRules.check("", .frequency, for: peak) == .problem("Between 1 and 22000 Hz."))
        #expect(EQEditorRules.check("-30", .gain, for: peak) == .value(-30))
        #expect(EQEditorRules.check("30,1", .gain, for: peak) == .problem("Between -30 and 30 dB."))
        #expect(EQEditorRules.check("100", .q, for: peak) == .value(100))
        #expect(EQEditorRules.check("0", .q, for: peak) == .problem("Between 0.01 and 100."))
        // a peak has no default width: an empty Q is out of range; a low pass's is its default
        #expect(EQEditorRules.check("", .q, for: peak) == .problem("Between 0.01 and 100."))
        let pass = EQFilter(id: 1, kind: .lowPass, fc: 100, width: .bandwidth(1))
        #expect(EQEditorRules.check(" ", .q, for: pass) == .value(nil))
        #expect(EQEditorRules.check("", .width, for: pass) == .value(nil))
        #expect(EQEditorRules.check("10,5", .width, for: pass) == .problem("Between 0.01 and 10."))
        // a slope: above 0, and not too steep for the gain (3.8's words, rounded down)
        let shelf = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(12))
        #expect(EQEditorRules.check("0", .slope, for: shelf) == .problem("Above 0 dB an octave."))
        #expect(EQEditorRules.check("", .slope, for: shelf) == .value(nil))
        let most = EQCookbook.steepestSlope(gain: 6)!
        #expect(EQEditorRules.check(EQWords.number(most - 0.01), .slope, for: shelf) == .value(most - 0.01))
        #expect(EQEditorRules.check(EQWords.number(most + 0.01), .slope, for: shelf)
                    == .problem(EQWords.Editor.tooSteep(gain: 6)!))
        // ... and a gain that would make the slope it has too steep
        let at24 = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 2, width: .slope(24))
        #expect(EQEditorRules.check("2", .gain, for: at24) == .value(2))
        #expect(EQEditorRules.check("20", .gain, for: at24) == .value(20))
        #expect(EQEditorRules.check("25", .gain, for: at24) == .problem(EQWords.Editor.tooSteep(gain: 25)!))
        #expect(EQWords.Editor.tooSteep(gain: 25)?.hasPrefix("Too steep for this gain - at most ") == true)
        // a value put in
        #expect(EQEditorRules.applying(2.5, .q, to: peak).width == .q(2.5))
        #expect(EQEditorRules.applying(nil, .width, to: pass).width == nil)
        #expect(EQEditorRules.applying(18, .slope, to: shelf).width == .slope(18))
        #expect(EQEditorRules.applying(440, .frequency, to: peak).fc == 440)
        #expect(EQEditorRules.applying(nil, .frequency, to: peak) == peak)
    }

    /// The steppers: a gain 0.1 dB; a Q x1.1 a step (at least 0.01); a slope 1 dB an octave - each held to its range,
    /// and nil where it can go no further.
    @Test func stepping() {
        let peak = Self.peak(1, 1000, 2, q: 1)
        #expect(EQEditorRules.stepped(peak, .gain, up: true)?.gain == 2.1)
        #expect(EQEditorRules.stepped(peak, .gain, up: false)?.gain == 1.9)
        #expect(EQEditorRules.stepped(Self.peak(1, 1000, 30), .gain, up: true) == nil)
        #expect(EQEditorRules.stepped(peak, .q, up: true)?.width == .q(1.1))
        #expect(EQEditorRules.stepped(peak, .q, up: false)?.width == .q(0.91))
        #expect(EQEditorRules.stepped(Self.peak(1, 1000, q: 0.01), .q, up: true)?.width == .q(0.02))
        #expect(EQEditorRules.stepped(Self.peak(1, 1000, q: 0.01), .q, up: false) == nil)
        #expect(EQEditorRules.stepped(Self.peak(1, 1000, q: 95), .q, up: true)?.width == .q(100))
        #expect(EQEditorRules.stepped(Self.peak(1, 1000, q: 100), .q, up: true) == nil)
        // a low pass given none steps from its default Q, 0.71
        #expect(EQEditorRules.stepped(EQFilter(id: 1, kind: .lowPass, fc: 100), .q, up: true)?.width == .q(0.78))
        let bw = EQFilter(id: 1, kind: .bandPass, fc: 100, width: .bandwidth(1))
        #expect(EQEditorRules.stepped(bw, .width, up: true)?.width == .bandwidth(1.1))
        let shelf = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(12))
        #expect(EQEditorRules.stepped(shelf, .slope, up: true)?.width == .slope(13))
        #expect(EQEditorRules.stepped(shelf, .slope, up: false)?.width == .slope(11))
        #expect(EQEditorRules.stepped(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(1)), .slope,
                                      up: false) == nil)
        let most = EQCookbook.steepestSlope(gain: 6)!
        let edge = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(most.rounded(.down)))
        #expect(EQEditorRules.stepped(edge, .slope, up: true) == nil)
        // a gain step that would make a slope too steep is none
        let at24 = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 2, width: .slope(24))
        let up = EQEditorRules.stepped(at24, .gain, up: true)
        #expect(up == nil || EQCookbook.shelfRadicand(gain: up!.gain, s: 2) > 0)
        #expect(EQEditorRules.stepped(peak, .frequency, up: true) == nil)
    }

    /// "Use Q instead": a width in octaves as the Q that plays the same at 48 kHz - the same coefficients, to three
    /// significant figures' worth - and a shelf's slope as the Q that plays the same at every rate.
    @Test func useQInstead() throws {
        let bw = EQFilter(id: 1, kind: .peak, fc: 8000, gain: 4, width: .bandwidth(1))
        let q = try #require(EQEditorRules.q(of: bw))
        let exact = EQFilter(id: 1, kind: .peak, fc: 8000, gain: 4, width: .q(q))
        let a = try #require(bw.design(rate: 48_000).coefficients)
        let b = try #require(exact.design(rate: 48_000).coefficients)
        for (x, y) in [(a.b0, b.b0), (a.b1, b.b1), (a.b2, b.b2), (a.a1, b.a1), (a.a2, b.a2)] {
            #expect(abs(x - y) < 1e-12)
        }
        let converted = try #require(EQEditorRules.usingQ(bw))
        #expect(converted.width == .q(EQEditorRules.significant(q)))
        #expect(abs(q - 1.4142) > 0.01, "the cookbook's digital width, not the analog 1.41")
        // a shelf's slope: the same S, so the same filter at any rate
        let shelf = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .slope(6), corner: true)
        let sq = try #require(EQEditorRules.q(of: shelf))
        let asQ = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .q(sq), corner: true)
        for rate in [44_100.0, 96_000] {
            let s1 = try #require(shelf.design(rate: rate).coefficients)
            let s2 = try #require(asQ.design(rate: rate).coefficients)
            #expect(abs(s1.b0 - s2.b0) < 1e-12 && abs(s1.a1 - s2.a1) < 1e-12 && abs(s1.a2 - s2.a2) < 1e-12)
        }
        #expect(EQEditorRules.usingQ(shelf)?.corner == true)
        // nothing to convert: a Q already, a slope on a peak (ignored), a slope too steep
        #expect(EQEditorRules.usingQ(Self.peak(1, 100)) == nil)
        #expect(EQEditorRules.usingQ(EQFilter(id: 1, kind: .peak, fc: 100, gain: 1, width: .slope(6))) == nil)
        #expect(EQEditorRules.usingQ(EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 20, width: .slope(48))) == nil)
        #expect(EQEditorRules.significant(0.70710678) == 0.707)
        #expect(EQEditorRules.significant(4.3184) == 4.32)
        #expect(EQEditorRules.significant(30.4) == 30.4)
    }

    /// The Type picker keeps the frequency, and the gain and width where the new type has them.
    @Test func changingType() {
        let corner = EQFilter(id: 4, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .slope(6), corner: true,
                              channel: .left, on: false)
        let high = EQEditorRules.changingKind(corner, to: .highShelf)
        #expect(high == EQFilter(id: 4, kind: .highShelf, written: "HSC", fc: 100, gain: 5, width: .slope(6),
                                 channel: .left, on: false))
        // a slope means nothing to a peak, which would then play nothing: Add Filter's Q 1
        #expect(EQEditorRules.changingKind(corner, to: .peak).width == .q(1))
        #expect(EQEditorRules.changingKind(corner, to: .peak).gain == 5)
        // a low pass has no gain; nor does it keep one to give back
        let pass = EQEditorRules.changingKind(Self.peak(1, 1000, 6, q: 2), to: .lowPass)
        #expect(pass.gain == 0 && pass.width == .q(2) && pass.written == "LP")
        #expect(EQEditorRules.changingKind(pass, to: .peak).gain == 0)
        // a width in octaves is nothing to a shelf: its default
        let bw = EQFilter(id: 1, kind: .peak, fc: 1000, gain: 3, width: .bandwidth(1))
        #expect(EQEditorRules.changingKind(bw, to: .lowShelf).width == nil)
        #expect(EQEditorRules.changingKind(bw, to: .notch).width == .bandwidth(1))
        #expect(EQEditorRules.changingKind(bw, to: .peak) == bw)
    }

    /// A shelf read by its corner says where it is centred; one by its centre, or given no width, says nothing.
    @Test func theCornersLine() {
        let corner = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .q(0.7), corner: true)
        let f0 = corner.f0!
        #expect(EQEditorRules.cornerNote(corner) == EQWords.Editor.corner(centredAt: f0))
        #expect(EQEditorRules.cornerNote(corner)?.hasPrefix("Its corner frequency, as Equalizer APO reads this shelf - it is centred at ") == true)
        #expect(EQEditorRules.cornerNote(EQFilter(id: 1, kind: .lowShelf, written: "LSC", fc: 100, gain: 5, width: .q(0.7))) == nil)
        #expect(EQEditorRules.cornerNote(EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 5, corner: true)) == nil)
    }

    /// The frequency slider: 20 Hz to 20 kHz on a log scale, snapped as a handle is.
    @Test func theSlider() {
        #expect(EQEditorRules.place(20) == 0 && EQEditorRules.place(20_000) == 1)
        #expect(abs(EQEditorRules.place(632.455532) - 0.5) < 1e-9)
        #expect(EQEditorRules.place(10) == 0 && EQEditorRules.place(22_000) == 1)
        #expect(EQEditorRules.frequency(place: 0) == 20 && EQEditorRules.frequency(place: 1) == 20_000)
        #expect(EQEditorRules.frequency(place: 0.5) == 632)
        #expect(EQEditorRules.frequency(place: 0.7) == 2520)
    }

    /// The editor's curve: the filter alone, both ears, no preamp - flat while it is off.
    @Test func theEditorsCurve() {
        let drawing = EQDrawing.filter(Self.peak(1, 1000, 6, channel: .left), rate: 48_000)
        #expect(drawing.on && drawing.lines.count == 1 && drawing.preamp == 0)
        let at = drawing.frequencies.firstIndex(of: 1000)!
        #expect(abs(drawing.lines[0].db[at] - 6) < 1e-9)
        let off = EQDrawing.filter(Self.peak(1, 1000, 6, on: false), rate: 48_000)
        #expect(off.lines[0].db.allSatisfy { $0 == 0 })
    }

    /// The words slice 5 adds: a paste's correction, what an import replaces, a slope of 0.
    @Test func words() {
        let pasted = EQImportRules.correction(name: nil, text: "", reading: APOReading(
            filters: [Self.peak(1, 100)], preamp: .zero, graphic: [], fits: [], notes: []))
        #expect(EQWords.Correction.value(pasted) == "Pasted")
        #expect(EQWords.Correction.source(pasted) == "From the clipboard")
        #expect(EQWords.Import.what(pasted) == "from the clipboard")
        var converted = pasted
        converted.converted = true
        #expect(EQWords.Correction.source(converted) == "From the clipboard, converted")
        let file = EQImportRules.correction(name: "HD650 ParametricEQ.txt", text: "", reading: APOReading(
            filters: [], preamp: .zero, graphic: [], fits: [], notes: []))
        #expect(EQWords.Correction.value(file) == "HD650 ParametricEQ.txt")
        #expect(EQWords.Import.what(file) == "from HD650 ParametricEQ.txt")
        #expect(EQWords.Import.what(Self.built([])) == "your own filters")
        #expect(EQWords.Editor.slopeRange == "Above 0 dB an octave.")
    }

    // MARK: the review (slice 5)

    /// An edit that would take an ear past 64 is refused: 63 for both and one for each ear - the left one's moved to
    /// both makes the right 65, the right one's moved to the left makes the left 65.
    @Test func anEditPastSixtyFourIsRefused() {
        let shared = (1...63).map { Self.peak($0, Double(100 + $0)) }
        let c = Self.built(shared + [Self.peak(64, 5000, channel: .left), Self.peak(65, 6000, channel: .right)])
        var settings = Self.settings(c)
        let before = settings
        #expect(settings.editFilter(64, for: Self.airpods) { (f: inout EQFilter) -> Void in f.channel = .all } == false)
        #expect(settings.editFilter(65, for: Self.airpods) { (f: inout EQFilter) -> Void in f.channel = .left } == false)
        #expect(settings == before)
    }

    /// Add Filter alone, or a delete alone, makes AutoEq's correction yours - "- changed", and Back offered.
    @Test func addingOrDeletingMarksAutoEqChanged() throws {
        let original = try Self.autoEq()
        var added = Self.settings(original)
        added.addFilter(for: Self.airpods)
        #expect(added.output(Self.airpods.key)?.correction?.changed == true)
        var deleted = Self.settings(original)
        deleted.deleteFilter(original.filters[0].id, for: Self.airpods)
        #expect(deleted.output(Self.airpods.key)?.correction?.changed == true)
        #expect(EQAdvancedRules.goesBack(deleted.output(Self.airpods.key)?.correction))
    }

    /// A filter at 0 dB plays nothing, but isn't "left out" - that is only for one above the rate.
    @Test func aFlatFilterIsNotLeftOut() {
        let c = Self.built([Self.peak(1, 1000, 0), EQFilter(id: 2, kind: .lowShelf, fc: 100, gain: 0, width: .slope(12))])
        #expect(EQAdvancedRules.rows(c, rate: 44_100).map(\.leftOut) == [false, false])
    }

    /// An `LS` or `HS` read with no width plays by its centre; given one - its field, a step, a pinch - it is written
    /// `LSC`/`HSC`, since an `LS` given a Q is read by its corner (0.3) and an export read again would move it. One read
    /// by its corner keeps its corner. Exported and read again, each plays as it did.
    @Test func aShelfGivenAWidthPlaysTheSameExported() throws {
        let text = "Filter: ON LS Fc 100 Hz Gain 6 dB\nFilter: ON HS Fc 8000 Hz Gain -4 dB\nFilter: ON LS Fc 200 Hz Gain 3 dB Q 0.7\n"
        guard case .success(let reading) = APOReader.read(Data(text.utf8)) else { throw Failure.unread }
        var settings = Self.settings(EQImportRules.correction(name: "a.txt", text: text, reading: reading))
        let ids = reading.filters.map(\.id)
        let stepped = try #require(EQEditorRules.stepped(reading.filters[0], .q, up: true))
        settings.editFilter(ids[0], for: Self.airpods) { (f: inout EQFilter) -> Void in f = stepped }
        settings.editFilter(ids[1], for: Self.airpods) { (f: inout EQFilter) -> Void in f = EQHandleRules.pinched(f, scale: 2) }
        settings.editFilter(ids[2], for: Self.airpods) { (f: inout EQFilter) -> Void in f.width = .q(0.8) }
        let filters = try #require(settings.output(Self.airpods.key)?.correction?.filters)
        #expect(filters.map(\.written) == ["LSC", "HSC", "LS"] && filters.map(\.corner) == [false, false, true])
        #expect(filters[0].f0 == 100 && filters[1].f0 == 8000)
        let file = APOWriter.write(filters: filters, preamp: .zero)
        guard case .success(let back) = APOReader.read(Data(file.utf8)) else { throw Failure.unread }
        #expect(back.filters.count == 3)
        for (mine, read) in zip(filters, back.filters) {
            #expect(mine.f0 == read.f0, "\(file)")
            #expect(mine.design(rate: 48_000).coefficients == read.design(rate: 48_000).coefficients, "\(file)")
        }
    }

    /// No edit leaves a filter the reader would refuse - a NaN or an infinity from anywhere, a frequency, gain or width
    /// out of range, a slope too steep or so gentle it overflows: nothing changes. In range, it does.
    @Test func anEditNeverLeavesAFilterTheReaderWouldRefuse() {
        // 6 dB takes up to 211 dB an octave; 24 dB an octave, under 23 dB of gain
        let shelf = EQFilter(id: 2, kind: .lowShelf, fc: 100, gain: 6, width: .slope(24))
        let before = Self.settings(Self.built([Self.peak(1, 1000), shelf]), on: false)
        let peakEdits: [(inout EQFilter) -> Void] = [
            { (f: inout EQFilter) -> Void in f.fc = .nan },
            { (f: inout EQFilter) -> Void in f.fc = .infinity },
            { (f: inout EQFilter) -> Void in f.fc = 0.5 },
            { (f: inout EQFilter) -> Void in f.fc = 22_001 },
            { (f: inout EQFilter) -> Void in f.gain = .nan },
            { (f: inout EQFilter) -> Void in f.gain = -.infinity },
            { (f: inout EQFilter) -> Void in f.gain = 30.1 },
            { (f: inout EQFilter) -> Void in f.width = .q(.nan) },
            { (f: inout EQFilter) -> Void in f.width = .q(0.001) },
            { (f: inout EQFilter) -> Void in f.width = .q(101) },
            { (f: inout EQFilter) -> Void in f.width = .bandwidth(10.5) },
        ]
        for (i, edit) in peakEdits.enumerated() {
            var settings = before
            #expect(settings.editFilter(1, for: Self.airpods, edit) == false && settings == before, "peak \(i)")
        }
        let shelfEdits: [(inout EQFilter) -> Void] = [
            { (f: inout EQFilter) -> Void in f.width = .slope(-1) },
            { (f: inout EQFilter) -> Void in f.width = .slope(1e-310) },
            { (f: inout EQFilter) -> Void in f.width = .slope(.nan) },
            { (f: inout EQFilter) -> Void in f.width = .slope(.infinity) },
            { (f: inout EQFilter) -> Void in f.width = .slope(300) },
            { (f: inout EQFilter) -> Void in f.gain = 30 },
        ]
        for (i, edit) in shelfEdits.enumerated() {
            var settings = before
            #expect(settings.editFilter(2, for: Self.airpods, edit) == false && settings == before, "shelf \(i)")
        }
        var settings = before
        #expect(settings.editFilter(1, for: Self.airpods) { (f: inout EQFilter) -> Void in f.fc = 22_000 })
        #expect(settings.editFilter(2, for: Self.airpods) { (f: inout EQFilter) -> Void in f.width = nil } == false)
        #expect(settings.output(Self.airpods.key)?.correction?.filters.map(\.fc) == [22_000, 100])
        #expect(settings.output(Self.airpods.key)?.correction?.filters[1].width == nil)
        #expect(EQAdvancedRules.takes(EQFilter(id: 3, kind: .lowPass, fc: 100, width: .q(0))))
        // a band pass's gain plays nothing, and a file's of 45 dB is kept: it can still be switched off
        let file = "Filter: ON BP Fc 1000 Hz Gain 45 dB Q 2"
        guard case .success(let reading) = APOReader.read(Data(file.utf8)) else {
            Issue.record("a band pass's gain is kept as written")
            return
        }
        var pass = Self.settings(EQImportRules.correction(name: "b.txt", text: file, reading: reading))
        pass.setFilter(reading.filters[0].id, on: false, for: Self.airpods)
        #expect(pass.output(Self.airpods.key)?.correction?.filters.map(\.on) == [false])
    }

    /// Every filter a file or AutoEq gives is one an edit may leave, so each can be switched and edited: the guard
    /// above refuses only what no reading makes.
    @Test func everyFilterAFileGivesCanBeEdited() throws {
        var filters: [EQFilter] = []
        for c in try EQFixtures.apo().readings {
            if case .success(let reading) = APOReader.read(try EQFixtures.bytes(of: c), pasted: c.pasted) {
                filters += reading.filters
            }
        }
        for profile in try EQFixtures.profiles().profiles {
            if case .success(let reading) = APOReader.read(try Fixtures.data("eq/\(profile.path)")) {
                filters += reading.filters
            }
        }
        #expect(filters.count > 500)
        for f in filters { #expect(EQAdvancedRules.takes(f), "\(f)") }
    }

    /// A corner shelf whose centre is no frequency - 0 Hz, or past any number (a gain of 30 dB and Q 0.01 moves it
    /// that far) - is dragged from its Fc: it moves, and never to NaN.
    @Test func aCornerWithNoCentreIsDraggedFromItsFc() {
        let w = 350.0, h = 220.0, r = 15.0
        let down = EQFilter(id: 1, kind: .highShelf, written: "HS", fc: 1000, gain: 30, width: .q(0.01), corner: true)
        let up = EQFilter(id: 2, kind: .lowShelf, written: "LS", fc: 100, gain: 30, width: .q(0.01), corner: true)
        #expect(down.f0 == 0 && up.f0 == .infinity)
        #expect(EQHandleRules.dragged(down, dx: w / 10, dy: 0, width: w, height: h, range: r).fc == 2000)
        #expect(EQHandleRules.dragged(up, dx: w / 10, dy: 0, width: w, height: h, range: r).fc == 200)
    }

    /// A finger never moves straight: an axis follows it only once it has gone 4 pt along that axis, from there - so a
    /// drag up that wobbles sideways keeps an imported 31.25 Hz, and 3 pt each way is still a tap.
    @Test func aDragUpThatWobblesKeepsItsFrequency() {
        let start = EQFilter(id: 1, kind: .peak, fc: 31.25, gain: 2.5, width: .q(1.41))
        var drag = EQHandleDrag(start: start, range: 15)
        #expect(drag.filter(dx: 3, dy: -3, width: 350, height: 220) == nil)
        #expect(drag.filter(dx: 1, dy: -4, width: 350, height: 220) == start)
        let up = drag.filter(dx: -3.5, dy: -4 - 22, width: 350, height: 220)
        #expect(up?.fc == 31.25 && up?.gain == 5.5)
        // sideways past 4 pt: the frequency follows from there, without a jump
        #expect(drag.filter(dx: 6, dy: -4 - 22, width: 350, height: 220)?.fc == 31.25)
        let across = drag.filter(dx: 6 + 35, dy: -4 - 22, width: 350, height: 220)
        #expect(abs((across?.fc ?? 0) - 62.5) <= 0.5 && across?.gain == 5.5)
    }

    /// A slope so near 0 its S overflows is refused by its field ("Too gentle to make a filter."), as the reader refuses
    /// it.
    @Test func aSlopeTooGentleIsRefusedByItsField() {
        let shelf = EQFilter(id: 1, kind: .lowShelf, fc: 100, gain: 6, width: .slope(12))
        let tiny = "0." + String(repeating: "0", count: 309) + "1"
        #expect(EQEditorRules.parse(tiny) == 1e-310)
        #expect(EQEditorRules.check(tiny, .slope, for: shelf) == .problem("Too gentle to make a filter."))
        #expect(EQEditorRules.check("0.0001", .slope, for: shelf) == .value(0.0001))
    }

    /// A corner shelf moved past any frequency (an `LS` of 0.1 dB an octave and 30 dB: f0 1e47 Hz, or infinity) says
    /// so in numbers - the line under Frequency once trapped turning it into an Int.
    @Test func aCornerFarAwaySaysWhereWithoutTrapping() {
        let far = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 30, width: .slope(0.1), corner: true)
        #expect(far.f0! > 1e40)
        #expect(EQEditorRules.cornerNote(far)?.hasSuffix(" Hz.") == true)
        let gone = EQFilter(id: 1, kind: .lowShelf, written: "LS", fc: 100, gain: 30, width: .q(0.01), corner: true)
        #expect(EQEditorRules.cornerNote(gone) == "Its corner frequency, as Equalizer APO reads this shelf - it is centred at inf Hz.")
        #expect(EQWords.Editor.corner(centredAt: 130.6) == "Its corner frequency, as Equalizer APO reads this shelf - it is centred at 131 Hz.")
    }

    /// The Advanced state written to eq.json and read again (4): the switch, every width's form, a corner, an ear's own,
    /// one off, the counter, AutoEq's "changed" and its text, and the preamp by hand.
    @Test func theAdvancedStateIsKeptAcrossALaunch() throws {
        var c = try Self.autoEq()
        c.filters += [
            EQFilter(id: 20, kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .slope(6), corner: true),
            EQFilter(id: 21, kind: .highShelf, written: "HSC", fc: 9000, gain: -3, width: .q(0.7)),
            EQFilter(id: 22, kind: .lowPass, written: "LPQ", fc: 18_000, width: .bandwidth(1.5), channel: .left),
            EQFilter(id: 23, kind: .notch, written: "NO", fc: 60, width: nil, channel: .right, on: false),
        ]
        c.nextFilterID = 24
        c.changed = true
        var settings = Self.settings(c, preamp: .hand(-7.5))
        settings.advanced = true
        let again = try #require(EQSettings.read(try settings.written()))
        #expect(again == settings)
        #expect(again.advanced && again.output(Self.airpods.key)?.correction?.changed == true)
        #expect(EQAdvancedRules.goesBack(again.output(Self.airpods.key)?.correction))
    }
}
