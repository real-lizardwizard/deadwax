import Foundation

// Advanced (notes/ios-specs/eq.md 3.8, slice 5): the correction's filters as a list and as handles on the curve, the
// filter's editor and the preamp set by hand - each rule pure, so it is tested on Linux and the views only draw.

// MARK: - the filter list (3.8)

/// A correction filter's row: the filter, its number - its place in the list, by frequency - and whether the output
/// leaves it out at its rate ("Above what this output plays, so it's left out.").
public struct EQFilterRow: Equatable, Sendable {
    public var filter: EQFilter
    public var number: Int
    public var leftOut: Bool
}

public enum EQAdvancedRules {
    /// Add Filter's (3.8): a Peak at 1000 Hz, 0 dB, Q 1.00.
    public static func newFilter(id: Int) -> EQFilter {
        EQFilter(id: id, kind: .peak, fc: 1000, gain: 0, width: .q(1))
    }

    /// The filters low to high, as the handles run left to right - two at one frequency in the correction's own order
    /// (APOWriter's order, so a correction for both ears is exported in it, numbered the same).
    public static func sorted(_ correction: EQCorrection?) -> [EQFilter] {
        APOWriter.curve(correction: correction?.filters ?? [], bands: nil)
    }

    /// The rows (3.8): by frequency, numbered from 1, each saying whether this output leaves it out at `rate` - only a
    /// filter that is on and whose f0 is above what the rate plays (an Off filter's switch says so already).
    public static func rows(_ correction: EQCorrection?, rate: Double) -> [EQFilterRow] {
        sorted(correction).enumerated().map { (i: Int, f: EQFilter) -> EQFilterRow in
            EQFilterRow(filter: f, number: i + 1, leftOut: f.design(rate: rate).outcome == .above)
        }
    }

    /// A filter's number - its place in the list - by its id: the editor's title ("Filter 3").
    public static func number(of id: Int, in correction: EQCorrection?) -> Int? {
        sorted(correction).firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Each ear's filters: the shared ones and its own.
    public static func perEar(_ filters: [EQFilter]) -> (left: Int, right: Int) {
        let all = filters.filter { $0.channel == .all }.count
        return (all + filters.filter { $0.channel == .left }.count, all + filters.filter { $0.channel == .right }.count)
    }

    /// What no edit takes a correction past (3.8): 64 an ear, or as many as that ear already had - a file may bring up
    /// to 74 (`EQLimits.importPerEar`), and its filters can still be switched, edited and moved between the ears, but
    /// no ear grows past 64 by it. So a correction you made stays within 64, and its whole curve exported - the tone's
    /// ten added - within the 74 an import reads back.
    public static func fits(_ filters: [EQFilter], before: [EQFilter]) -> Bool {
        let n = perEar(filters), was = perEar(before)
        return n.left <= max(EQLimits.filtersPerEar, was.left) && n.right <= max(EQLimits.filtersPerEar, was.right)
    }

    /// Add Filter is offered: one more, for both ears, still fits within 64 - else it is disabled and says "64
    /// filters is the most you can add".
    public static func canAdd(_ correction: EQCorrection?) -> Bool {
        let n = perEar(correction?.filters ?? [])
        return max(n.left, n.right) < EQLimits.filtersPerEar
    }

    /// The editor's Ear (3.8): only when the correction has a filter for one ear, or one ear's own preamp.
    public static func showsEar(_ correction: EQCorrection?) -> Bool {
        guard let c = correction else { return false }
        return c.preamp.perEar || c.filters.contains { $0.channel != .all }
    }

    /// "Back to AutoEq's" is offered (3.8): an AutoEq correction edited since, its text kept (4).
    public static func goesBack(_ correction: EQCorrection?) -> Bool {
        guard let c = correction else { return false }
        return c.kind == .autoeq && c.changed && c.text != nil
    }

    /// A filter an edit may leave (3.8): one the reader would take (1.3, 3.9) - its Fc 1 to 22000 Hz, a peak's or a
    /// shelf's gain within 30 dB (another's, which plays none, kept as written but finite), a Q 0.01 to 100 and a width
    /// 0.01 to 10 octaves (or 0, none), a shelf's slope 0 or above it and neither too steep for its gain nor so gentle
    /// its S overflows - so no NaN or infinity reaches the bank, the file or eq.json, however a handle, a field or a
    /// step got there, and every filter a file or AutoEq gave can still be switched and edited.
    public static func takes(_ f: EQFilter) -> Bool {
        guard EQLimits.frequency.contains(f.fc), f.gain.isFinite, !f.kind.hasGain || abs(f.gain) <= EQLimits.gain
        else { return false }
        switch f.width {
        case nil: return true
        case .q(let v)?: return v == 0 || EQLimits.q.contains(v)
        case .bandwidth(let v)?: return v == 0 || EQLimits.bandwidth.contains(v)
        case .slope(let v)? where f.kind.isShelf:
            guard v != 0 else { return true }
            let r = EQCookbook.shelfRadicand(gain: f.gain, s: v / 12)
            return v > 0 && r > 0 && r.isFinite
        case .slope(let v)?: return v.isFinite
        }
    }

    /// The preamp set by hand: to 0.1 dB, inside -30 to +12 (8, question 18) - never "-0".
    public static func handPreamp(_ dB: Double) -> Double {
        let r = EQLimits.handPreamp
        return min(max((dB * 10).rounded() / 10, r.lowerBound), r.upperBound) + 0.0
    }
}

// MARK: - changes (3.8)

extension EQSettings {
    /// Add Filter (3.8): Add Filter's peak, with the correction's next id - and, with no correction, one of your own
    /// begun ("Your own filters"). AutoEq's correction or a file's is marked changed. The new filter's id and whether it
    /// turned the EQ on - nil when an ear already has 64.
    @discardableResult
    public mutating func addFilter(for o: EQOutput) -> (id: Int, turnedOn: Bool)? {
        guard EQAdvancedRules.canAdd(setting(for: o).correction) else { return nil }
        var id = 0
        let turnedOn = change(o, always: true) { (s: inout EQOutputSetting) -> Void in
            var c = s.correction ?? EQCorrection(kind: .built, name: "", nextFilterID: 1, filters: [])
            //? never an id the correction already has, whatever a file kept as its counter
            id = max(c.nextFilterID, (c.filters.map(\.id).max() ?? 0) + 1)
            c.nextFilterID = id + 1
            c.filters.append(EQAdvancedRules.newFilter(id: id))
            if c.kind != .built { c.changed = true }
            s.correction = c
        }
        return (id, turnedOn)
    }

    /// One filter edited - by its handle, its row's switch or its editor - its id kept. Nothing when it is unchanged,
    /// would take an ear past 64 (or past what it had, `fits`), or isn't a filter the reader would take (`takes`);
    /// AutoEq's correction or a file's edited is marked changed ("- changed", back-home 15l for a file's). A shelf
    /// written by its corner's name (`LS`, `HS`) that plays by its centre and is given a width is written as one by its
    /// centre (`LSC`, `HSC`): an `LS` given a Q is read by its corner (0.3), so an export would otherwise move it. True
    /// when it turned the EQ on.
    @discardableResult
    public mutating func editFilter(_ id: Int, for o: EQOutput, _ body: (inout EQFilter) -> Void) -> Bool {
        guard var c = setting(for: o).correction, let i = c.filters.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var f = c.filters[i]
        body(&f)
        f.id = id
        if f.kind.isShelf && !f.corner && !f.written.hasSuffix("C") && f.playedWidth?.given == true {
            f.written = f.kind.defaultWritten
        }
        guard f != c.filters[i], EQAdvancedRules.takes(f) else { return false }
        let before = c.filters
        c.filters[i] = f
        guard EQAdvancedRules.fits(c.filters, before: before) else { return false }
        if c.kind != .built { c.changed = true }
        return change(o) { (s: inout EQOutputSetting) -> Void in s.correction = c }
    }

    /// A row's switch (APO's ON and OFF).
    @discardableResult
    public mutating func setFilter(_ id: Int, on: Bool, for o: EQOutput) -> Bool {
        editFilter(id, for: o) { (f: inout EQFilter) -> Void in f.on = on }
    }

    /// A filter deleted (a row's swipe, the editor's Delete Filter). Your own filters, the last one gone, are no
    /// correction at all - None, the switch left as it is, as choosing None leaves it (3.7). True when it turned the
    /// EQ on.
    @discardableResult
    public mutating func deleteFilter(_ id: Int, for o: EQOutput) -> Bool {
        guard var c = setting(for: o).correction, c.filters.contains(where: { $0.id == id }) else { return false }
        c.filters.removeAll { $0.id == id }
        if c.kind == .built && c.filters.isEmpty { return use(nil, for: o) }
        if c.kind != .built { c.changed = true }
        return change(o) { (s: inout EQOutputSetting) -> Void in s.correction = c }
    }

    /// "Back to AutoEq's" (3.8): an AutoEq correction edited, read again from the text it kept (4) - its filters, ids
    /// and preamp as they came, "changed" gone. Nothing for any other. True when it turned the EQ on.
    @discardableResult
    public mutating func backToAutoEq(for o: EQOutput) -> Bool {
        guard let c = setting(for: o).correction, EQAdvancedRules.goesBack(c), let text = c.text,
              case .success(let reading) = APOReader.read(Data(text.utf8)) else { return false }
        let back = EQCorrection.autoeq(id: c.id ?? "", name: c.name, source: c.source ?? "", rig: c.rig, form: c.form,
                                       text: text, reading: reading)
        return change(o) { (s: inout EQOutputSetting) -> Void in s.correction = back }
    }

    /// The Preamp section's Automatic (3.8): on, deadwax's own; off, yours - beginning at the preamp that plays now
    /// (`played`), so turning it off changes nothing you hear. True when it turned the EQ on.
    @discardableResult
    public mutating func setAutomaticPreamp(_ automatic: Bool, played: Double, for o: EQOutput) -> Bool {
        change(o) { (s: inout EQOutputSetting) -> Void in
            if automatic {
                s.preamp = .automatic
            } else if s.preamp == .automatic {
                s.preamp = .hand(EQAdvancedRules.handPreamp(played))
            }
        }
    }

    /// The preamp's stepper: yours, to 0.1 dB, -30 to +12. True when it turned the EQ on.
    @discardableResult
    public mutating func setHandPreamp(_ dB: Double, for o: EQOutput) -> Bool {
        change(o) { (s: inout EQOutputSetting) -> Void in s.preamp = .hand(EQAdvancedRules.handPreamp(dB)) }
    }

    /// An import (3.9): the output's correction from now on, the EQ on - and, with the preamp set by hand, the file's
    /// own (its shared part, held to the hand-set range: 1.4). True when it turned the EQ on.
    @discardableResult
    public mutating func importCorrection(_ correction: EQCorrection, for o: EQOutput) -> Bool {
        change(o, always: true) { (s: inout EQOutputSetting) -> Void in
            s.correction = correction
            if case .hand = s.preamp { s.preamp = .hand(EQAdvancedRules.handPreamp(correction.preamp.all)) }
        }
    }
}

// MARK: - the handles (3.8)

/// A correction filter's handle on the curve: where it is drawn - its f0 across (a corner shelf's centre, where its
/// gain is half; its Fc when it has no width) and its own gain up, 0 dB for a filter with none - and whose it is.
public struct EQHandle: Equatable, Sendable {
    public var id: Int
    public var frequency: Double
    public var gain: Double
}

/// The handles and what a finger does with one (3.8): a touch takes the nearest within 22 pt (none near, it scrolls);
/// a drag sideways is the frequency (1 Hz under 1 kHz, 10 Hz above), up and down the gain (0.1 dB); a pinch the
/// width. GarageBand's and Logic Pro for iPad's EQ are dragged the same way.
public enum EQHandleRules {
    /// how far from a handle a touch still takes it (pt)
    public static let reach: Double = 22
    /// how far a finger goes before a handle follows it (pt): a tap selects, and moves nothing
    public static let engage: Double = 4
    /// a drag's frequencies - the editor slider's - stretched to take in where the filter began
    public static let frequencies = 20.0...20_000.0
    /// a pinched Q - wider in the editor (3.8)
    public static let q = 0.1...20.0

    /// One for each correction filter that is on.
    public static func handles(_ correction: EQCorrection?) -> [EQHandle] {
        (correction?.filters ?? []).filter(\.on).map(handle)
    }

    public static func handle(_ f: EQFilter) -> EQHandle {
        EQHandle(id: f.id, frequency: f.f0 ?? f.fc, gain: f.kind.hasGain ? f.gain : 0)
    }

    /// A handle's centre in a plot `width` by `height`, `range` dB either way of its middle - held inside the plot, so
    /// one past an edge is drawn at it.
    public static func point(_ h: EQHandle, width: Double, height: Double, range: Double) -> (x: Double, y: Double) {
        let x = EQDrawing.x(h.frequency, width: width)
        let y = EQDrawing.y(h.gain, range: range, height: height)
        return (min(max(x, 0), width), min(max(y, 0), height))
    }

    /// The handle a touch at (x, y) takes: the nearest within `reach` - nil when none is, and the touch is the list's.
    public static func nearest(_ handles: [EQHandle], x: Double, y: Double, width: Double, height: Double,
                               range: Double, reach: Double = reach) -> Int? {
        var best: (id: Int, distance: Double)?
        for h in handles {
            let p = point(h, width: width, height: height, range: range)
            let distance = ((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)).squareRoot()
            if distance <= reach && distance < (best?.distance ?? .infinity) { best = (h.id, distance) }
        }
        return best?.id
    }

    /// A place across the plot as a frequency: EQDrawing.x's inverse.
    public static func frequency(x: Double, width: Double) -> Double {
        let lo = log2(EQChart.grid[0]), hi = log2(EQChart.grid[EQChart.grid.count - 1])
        return pow(2.0, lo + x / width * (hi - lo))
    }

    /// A dragged frequency: to 1 Hz under 1 kHz, 10 Hz above.
    public static func snappedFrequency(_ f: Double) -> Double {
        let step = f < 1000 ? 1.0 : 10.0
        return (f / step).rounded() * step
    }

    /// A dragged gain: to 0.1 dB, never "-0".
    public static func snappedGain(_ g: Double) -> Double { (g * 10).rounded() / 10 + 0.0 }

    /// A drag of `dx` across and `dy` down (pt) from where the filter began, in a plot `width` by `height` showing
    /// `range` dB either way: the frequency moved by the octaves the finger went (the Fc as written moved with its f0,
    /// so a corner shelf keeps its corner), the gain by the dB - each axis only when the finger moved along it, so an
    /// imported 31.25 Hz isn't rounded by a drag up. A pass, a notch or an all pass has no gain to drag; a shelf with a
    /// slope stops where the slope would be too steep for it.
    public static func dragged(_ start: EQFilter, dx: Double, dy: Double, width: Double, height: Double,
                               range: Double) -> EQFilter {
        var f = start
        if dx != 0 && width > 0 {
            // a corner shelf's centre, unless it is none a drag can move from (0 Hz, or past any number)
            let f0 = start.f0 ?? start.fc
            let from = f0 > 0 && f0.isFinite ? f0 : start.fc
            let ratio = frequency(x: EQDrawing.x(from, width: width) + dx, width: width) / from
            let lo = min(start.fc, frequencies.lowerBound), hi = max(start.fc, frequencies.upperBound)
            f.fc = min(max(snappedFrequency(start.fc * ratio), lo), hi)
        }
        if dy != 0 && height > 0 && start.kind.hasGain {
            let gain = snappedGain(start.gain - dy / height * 2 * range)
            f.gain = playable(f, gain: min(max(gain, -EQLimits.gain), EQLimits.gain))
        }
        return f
    }

    /// A gain a shelf written with a slope can play: moved toward 0 a tenth at a time until the slope isn't too steep
    /// for it (1.3). Any other filter's as it is.
    static func playable(_ f: EQFilter, gain: Double) -> Double {
        guard f.kind.isShelf, case .slope(let s)? = f.width, s > 0 else { return gain }
        var g = gain
        while g != 0 && EQCookbook.shelfRadicand(gain: g, s: s / 12) <= 0 {
            g = snappedGain(g > 0 ? g - 0.1 : g + 0.1)
        }
        return g
    }

    /// A pinch (3.8): `scale` above 1 spreads the fingers and widens the filter. Its width kept in its own form - a Q
    /// (to 0.01, 0.1 to 20), a width in octaves (to 0.01, up to 10), a shelf's slope (to 0.1 dB an octave, never too
    /// steep) - and a filter given none starts from the Q it plays as (1 for a peak or an all pass, which plays
    /// nothing without one). Each range is stretched to take in where it began, so a touch never makes it jump.
    public static func pinched(_ start: EQFilter, scale: Double) -> EQFilter {
        guard scale > 0, abs(scale - 1) >= 0.005 else { return start }
        var f = start
        switch start.width {
        case .bandwidth(let b)? where !start.kind.isShelf && b != 0:
            let v = (b * scale * 100).rounded() / 100
            f.width = .bandwidth(min(max(v, min(b, EQLimits.bandwidth.lowerBound)), max(b, EQLimits.bandwidth.upperBound)))
        case .slope(let s)? where start.kind.isShelf && s != 0:
            var v = max((s / scale * 10).rounded() / 10, min(s, 0.1))
            while v > 0.1 && EQCookbook.shelfRadicand(gain: start.gain, s: v / 12) <= 0 { v = ((v - 0.1) * 10).rounded() / 10 }
            f.width = .slope(v)
        default:
            let q0 = EQEditorRules.q(of: start) ?? 1
            let v = (q0 / scale * 100).rounded() / 100
            f.width = .q(min(max(v, min(q0, q.lowerBound)), max(q0, q.upperBound)))
        }
        return f
    }
}

/// One finger's drag on a handle (3.8): the filter as it was when the finger came down, the plot's range then (so the
/// axis growing under it doesn't change what a point is worth), and where each axis engaged - an axis moves nothing
/// until the finger has gone `engage` along it, and from there follows it without a jump. So a drag up that wobbles a
/// point or two sideways leaves the frequency as it was (an imported 31.25 Hz isn't rounded to 31), and a tap moves
/// nothing.
public struct EQHandleDrag: Sendable {
    public let start: EQFilter
    public let range: Double
    /// where the finger was (pt from where it came down) when each axis engaged - nil until it has
    public private(set) var engagedAt: (dx: Double?, dy: Double?) = (nil, nil)

    public init(start: EQFilter, range: Double) {
        self.start = start
        self.range = range
    }

    /// The filter for the finger's movement so far (pt, down positive) - nil until an axis has engaged.
    public mutating func filter(dx: Double, dy: Double, width: Double, height: Double) -> EQFilter? {
        if engagedAt.dx == nil && abs(dx) >= EQHandleRules.engage { engagedAt.dx = dx }
        if engagedAt.dy == nil && abs(dy) >= EQHandleRules.engage { engagedAt.dy = dy }
        guard engagedAt.dx != nil || engagedAt.dy != nil else { return nil }
        let across = engagedAt.dx.map { (at: Double) -> Double in dx - at } ?? 0
        let down = engagedAt.dy.map { (at: Double) -> Double in dy - at } ?? 0
        return EQHandleRules.dragged(start, dx: across, dy: down, width: width, height: height, range: range)
    }
}

// MARK: - the filter's editor (3.8)

/// The editor's number fields.
public enum EQField: String, Hashable, Sendable, CaseIterable {
    case frequency, gain, q, width, slope
}

public enum EQEditorRules {
    /// The width row the editor shows (3.8): "Slope" for a shelf written with one, "Width" in octaves for any other
    /// filter written with `BW Oct`, else "Q" - a filter given no width included, its type's default the placeholder.
    public static func widthField(_ f: EQFilter) -> EQField {
        switch f.width {
        case .slope? where f.kind.isShelf: return .slope
        case .bandwidth? where !f.kind.isShelf: return .width
        default: return .q
        }
    }

    /// A field's value - nil when the filter gives none (a width of 0 is none, as APO reads it).
    public static func value(_ f: EQFilter, _ field: EQField) -> Double? {
        switch (field, f.width) {
        case (.frequency, _): return f.fc
        case (.gain, _): return f.gain
        case (.q, .q(let v)?) where v != 0: return v
        case (.width, .bandwidth(let v)?) where v != 0: return v
        case (.slope, .slope(let v)?) where v != 0: return v
        default: return nil
        }
    }

    /// A field's text: the value in as many decimals as it needs and at least AutoEq's (Fc none, Gain one, a Q or a
    /// width two, a slope none), in the phone's decimal mark - empty when there is none, so the placeholder shows.
    public static func text(_ f: EQFilter, _ field: EQField, decimal: String = ".") -> String {
        guard let v = value(f, field) else { return "" }
        let decimals: Int
        switch field {
        case .frequency, .slope: decimals = 0
        case .gain: decimals = 1
        case .q, .width: decimals = 2
        }
        let t = APOWriter.number(v, decimals: decimals)
        return decimal == "." ? t : t.replacingOccurrences(of: ".", with: decimal)
    }

    /// A field's text as a number: a decimal comma or point (the phone's, or one pasted in), a sign, spaces around it -
    /// nil for anything else, or nothing.
    public static func parse(_ text: String) -> Double? {
        let minus = Character(Unicode.Scalar(0x2212)!)
        let t = String(text.trimmingCharacters(in: .whitespaces).map { (c: Character) -> Character in
            c == "," ? "." : (c == minus ? "-" : c)
        })
        guard !t.isEmpty, t.allSatisfy({ "0123456789.+-".contains($0) }), let v = Double(t), v.isFinite else {
            return nil
        }
        return v
    }

    /// What a field's text sets: a value, none (an empty Q, Width or Slope - the type's default, where it has one),
    /// or the line under the field in danger's colour - and then nothing changes (3.8).
    public enum Check: Equatable, Sendable {
        case value(Double?)
        case problem(String)
    }

    public static func check(_ text: String, _ field: EQField, for f: EQFilter) -> Check {
        let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
        let v = parse(text)
        switch field {
        case .frequency:
            guard let v, EQLimits.frequency.contains(v) else { return .problem(EQWords.Editor.frequencyRange) }
            return .value(v)
        case .gain:
            guard let v, abs(v) <= EQLimits.gain else { return .problem(EQWords.Editor.gainRange) }
            if f.kind.isShelf, case .slope(let s)? = f.width, s > 0, EQCookbook.shelfRadicand(gain: v, s: s / 12) <= 0,
               let words = EQWords.Editor.tooSteep(gain: v) {
                return .problem(words)
            }
            return .value(v)
        case .q, .width:
            if empty && EQWords.Editor.placeholder(f.kind) != nil { return .value(nil) }
            let range = field == .q ? EQLimits.q : EQLimits.bandwidth
            guard let v, range.contains(v) else {
                return .problem(field == .q ? EQWords.Editor.qRange : EQWords.Editor.widthRange)
            }
            return .value(v)
        case .slope:
            if empty { return .value(nil) }
            guard let v, v > 0 else { return .problem(EQWords.Editor.slopeRange) }
            guard EQCookbook.shelfRadicand(gain: f.gain, s: v / 12).isFinite else { return .problem(EQWords.Editor.tooGentle) }
            if EQCookbook.shelfRadicand(gain: f.gain, s: v / 12) <= 0, let words = EQWords.Editor.tooSteep(gain: f.gain) {
                return .problem(words)
            }
            return .value(v)
        }
    }

    /// The filter with a field's checked value in it.
    public static func applying(_ value: Double?, _ field: EQField, to f: EQFilter) -> EQFilter {
        var g = f
        switch field {
        case .frequency: if let value { g.fc = value }
        case .gain: if let value { g.gain = value }
        case .q: g.width = value.map { EQWidth.q($0) }
        case .width: g.width = value.map { EQWidth.bandwidth($0) }
        case .slope: g.width = value.map { EQWidth.slope($0) }
        }
        return g
    }

    /// A stepper's step (3.8): a gain 0.1 dB; a Q x1.1 (to 0.01, at least 0.01 a step); a width in octaves the same;
    /// a slope 1 dB an octave - each from the value the filter plays, and held to its range. Nil where it can go no
    /// further: the range's end, or a shelf's slope too steep for its gain.
    public static func stepped(_ f: EQFilter, _ field: EQField, up: Bool) -> EQFilter? {
        var g = f
        switch field {
        case .frequency:
            return nil
        case .gain:
            let v = min(max(EQHandleRules.snappedGain(f.gain + (up ? 0.1 : -0.1)), -EQLimits.gain), EQLimits.gain)
            if f.kind.isShelf, case .slope(let s)? = f.width, s > 0, EQCookbook.shelfRadicand(gain: v, s: s / 12) <= 0 {
                return nil
            }
            g.gain = v
        case .q, .width:
            let range = field == .q ? EQLimits.q : EQLimits.bandwidth
            let start = value(f, field) ?? (field == .q ? q(of: f) : f.playedWidth?.value) ?? 1
            let x = (start * 100).rounded() / 100
            let v = min(max(up ? max((start * 1.1 * 100).rounded() / 100, x + 0.01)
                               : min((start / 1.1 * 100).rounded() / 100, x - 0.01),
                            range.lowerBound), range.upperBound)
            g.width = field == .q ? .q(v) : .bandwidth(v)
        case .slope:
            let start = value(f, .slope) ?? (f.playedWidth?.value ?? 0.9) * 12
            let v = up ? start.rounded(.down) + 1 : start.rounded(.up) - 1
            guard v > 0, EQCookbook.shelfRadicand(gain: f.gain, s: v / 12) > 0 else { return nil }
            g.width = .slope(v)
        }
        return g == f ? nil : g
    }

    /// The Q a filter plays as at `rate`: its own; a width in octaves', by the cookbook's alpha at its frequency (the
    /// analog relation where the rate leaves it out); a shelf's from its S - its slope, or S 0.9 - which no rate
    /// changes. Nil for a peak or an all pass given no width, or a shelf too steep for its gain.
    public static func q(of f: EQFilter, rate: Double = 48_000) -> Double? {
        guard let w = f.playedWidth else { return nil }
        if !w.isBandwidthOrS { return w.value }
        if f.kind.isShelf {
            let r = EQCookbook.shelfRadicand(gain: f.gain, s: w.value)
            return r > 0 ? 1 / r.squareRoot() : nil
        }
        let omega = 2 * Double.pi * f.fc / rate
        let stretch = f.fc < EQLimits.topFraction * rate ? omega / sin(omega) : 1
        return 1 / (2 * sinh(log(2.0) / 2 * w.value * stretch))
    }

    /// "Use Q instead" (3.8): a width in octaves or a shelf's slope as the Q that plays the same at 48 kHz - a shelf's
    /// at every rate - to three significant figures, inside 0.01-100. Nil for a filter already given a Q, or none to
    /// convert (a slope too steep for its gain has no Q).
    public static func usingQ(_ f: EQFilter) -> EQFilter? {
        switch f.width {
        case .bandwidth? where !f.kind.isShelf: break
        case .slope? where f.kind.isShelf: break
        default: return nil
        }
        guard let q = q(of: f), q > 0 else { return nil }
        var g = f
        g.width = .q(min(max(significant(q), EQLimits.q.lowerBound), EQLimits.q.upperBound))
        return g
    }

    /// Three significant figures: 0.7071 is 0.707, 4.318 is 4.32.
    static func significant(_ x: Double) -> Double {
        let scale = pow(10.0, 2 - floor(log10(x)))
        return (x * scale).rounded() / scale
    }

    /// The Type picker (3.8): the frequency kept, the gain where both types have one, the width where the new type
    /// reads it (a width in octaves is ignored on a shelf, a slope on anything else - each then none); written as the
    /// new type is by default (`LSC`, `HSC`: a shelf by its centre). A peak or an all pass left with no width is given
    /// Add Filter's Q 1, as it would otherwise play nothing.
    public static func changingKind(_ f: EQFilter, to kind: EQKind) -> EQFilter {
        guard kind != f.kind else { return f }
        var g = f
        g.kind = kind
        g.written = kind.defaultWritten
        g.corner = false
        g.gain = f.kind.hasGain && kind.hasGain ? f.gain : 0
        switch f.width {
        case .bandwidth? where kind.isShelf: g.width = nil
        case .slope? where !kind.isShelf: g.width = nil
        default: break
        }
        if g.playedWidth == nil { g.width = .q(1) }
        return g
    }

    /// The line under Frequency for a shelf read by its corner (1.3: `LS`/`HS` given a Q or a slope): where it is
    /// centred - the f0 it plays at, where its handle is drawn.
    public static func cornerNote(_ f: EQFilter) -> String? {
        guard f.corner, f.kind.isShelf, f.playedWidth?.given == true, let f0 = f.f0 else { return nil }
        return EQWords.Editor.corner(centredAt: f0)
    }

    /// The frequency slider's range: 20 Hz to 20 kHz, on a log scale.
    public static let slider = 20.0...20_000.0

    /// A frequency's place along the slider, 0 to 1 - held at its ends.
    public static func place(_ f: Double) -> Double {
        min(max(log(f / slider.lowerBound) / log(slider.upperBound / slider.lowerBound), 0), 1)
    }

    /// A place along the slider as a frequency, snapped as a handle's is.
    public static func frequency(place: Double) -> Double {
        let p = min(max(place, 0), 1)
        return EQHandleRules.snappedFrequency(slider.lowerBound * pow(slider.upperBound / slider.lowerBound, p))
    }
}

// MARK: - the curves Advanced draws

extension EQDrawing {
    /// The editor's curve (3.8): the filter alone, for both ears, at no preamp - flat while it is off.
    public static func filter(_ f: EQFilter, rate: Double) -> EQDrawing {
        var setting = EQSettings.newOutput(EQOutputs.speaker, seen: "")
        setting.on = true
        setting.preamp = .hand(0)
        var alone = f
        alone.channel = .all
        setting.correction = EQCorrection(kind: .built, name: "", nextFilterID: f.id + 1, filters: [alone])
        return make(setting, in: EQSettings(), rate: rate)
    }
}
