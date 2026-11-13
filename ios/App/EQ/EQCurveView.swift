import Accessibility
import DeadwaxCore
import SwiftUI

/// The curve (eq.md 3.4): what you hear on the output - Core's EQDrawing, the preamp added, so the top sits at 0 dB or
/// below - as an audio graph: log frequency across, dB up. Drawn once, above the sliders.
///
/// - **The axes**: ±15 dB by default, growing to ±18 or ±24 when the curve goes further; hairlines at ±6 and ±12 dB and
///   at 100 Hz, 1 kHz and 10 kHz in `barEdge` (`textTertiary` under Increase Contrast), the 0 dB line in
///   `textTertiary`, 1 pt; "+12", "0", "-12" at the left inside the plot, "100", "1k", "10k" along its foot, in
///   `.caption2` `quiet`, stopped at `.xxxLarge`.
/// - **The line**: 2 pt `accent`, round joins, filled to 0 dB in `toggledFill` - boosts above, cuts below; per ear, the
///   right in `accentText`, each labelled at its right end, the fill under the left only; a correction under a tone
///   as a 1 pt dashed `quiet` line (1.5 pt under Increase Contrast), the tone alone dotted. Off: flat, grey, at
///   `Palette.off`.
/// - **Moves**: a preset, On/Off or another output morph the lines over 0.25 s; the axis grows the same way; a drag
///   moves them with the finger, never animated (`animated` false); all of it at once under Reduce Motion. A curve
///   drawn at other frequencies - a correction's f0s added or dropped - crossfades rather than morphs: the lines
///   have a different number of points.
/// - **VoiceOver**: one element, "The EQ's curve", its value the summary (3.14), and an audio graph
///   (`accessibilityChartDescriptor`) - the rotor's Play Audio Graph plays it as a rising and falling tone. Not
///   given `.allowsDirectInteraction`. Marked as a picture for Smart Invert.
struct EQCurveView: View {
    let drawing: EQDrawing
    /// the output's name, for the audio graph's title
    let name: String
    /// false while a finger drags a slider: the line follows the finger, unanimated
    var animated = true

    static let height: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    private var increased: Bool { contrast == .increased }
    /// One pixel.
    private var hairline: CGFloat { 1 / max(displayScale, 1) }

    var body: some View {
        VStack(spacing: 4) {
            // in a ZStack of its own, so the plot going and the plot coming lie over each other while they crossfade
            // - a VStack would stack the two for the 0.25 s, the row twice as tall
            ZStack {
                plot
                    // a new set of frequencies is a new plot: the lines can't morph between point counts (EQVector's
                    // difference across lengths is zero), so it crossfades instead - a correction chosen or taken away
                    // adds or drops its f0s (slice 3's review)
                    .id(drawing.frequencies)
            }
            .frame(height: Self.height)
            foot
        }
        .padding(.vertical, 10)
        .animation(animated && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: drawing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EQWords.Said.curve)
        .accessibilityValue(drawing.summary)
        .accessibilityChartDescriptor(EQAudioGraph(drawing: drawing, name: name))
        .accessibilityIgnoresInvertColors()
    }

    private var plot: some View {
        ZStack(alignment: .topLeading) {
            EQGridShape(range: drawing.range)
                .stroke(increased ? Palette.textTertiary : Palette.barEdge, lineWidth: hairline)
            EQZeroLine()
                .stroke(Palette.textTertiary, lineWidth: 1)
            if drawing.on, let heard = drawing.lines.first {
                EQCurveShape(values: EQVector(heard.db), frequencies: drawing.frequencies, range: drawing.range,
                             closed: true)
                    .fill(Palette.toggledFill)
            }
            ForEach(drawing.lines, id: \.kind) { line in
                EQCurveShape(values: EQVector(line.db), frequencies: drawing.frequencies, range: drawing.range)
                    .stroke(color(line), style: style(line))
                    .opacity(drawing.on ? 1 : Palette.off)
            }
            gainLabels
            earLabels
        }
        .clipped()
    }

    private func color(_ line: EQDrawing.Line) -> Color {
        guard drawing.on else { return Palette.quiet }
        switch line.kind {
        case .heard: return Palette.accent
        case .right: return Palette.accentText
        case .correction, .tone: return Palette.quiet
        }
    }

    private func style(_ line: EQDrawing.Line) -> StrokeStyle {
        switch line.kind {
        case .heard, .right:
            return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        case .correction:
            return StrokeStyle(lineWidth: increased ? 1.5 : 1, lineCap: .round, lineJoin: .round, dash: [5, 4])
        case .tone:
            return StrokeStyle(lineWidth: increased ? 1.5 : 1, lineCap: .round, lineJoin: .round, dash: [1, 4])
        }
    }

    /// "+12", "0", "-12" at the left, inside the plot, on their lines.
    private var gainLabels: some View {
        GeometryReader { geometry in
            let height = Double(geometry.size.height)
            ForEach(Array(zip([12.0, 0, -12], EQWords.Screen.gainLabels)), id: \.1) { gain, label in
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.quiet)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize()
                    // just above its line, so the line runs under it unbroken
                    .position(x: 18, y: EQDrawing.y(gain, range: drawing.range, height: height) - 7)
            }
        }
    }

    /// "Left" and "Right" at the right ends of the ears' lines (state 6).
    private var earLabels: some View {
        GeometryReader { geometry in
            let height = Double(geometry.size.height)
            ForEach(drawing.lines.filter { $0.label != nil }, id: \.kind) { line in
                Text(line.label ?? "")
                    .font(.caption2)
                    .foregroundStyle(line.kind == .right ? Palette.accentText : Palette.accent)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize()
                    .position(x: Double(geometry.size.width) - 24,
                              y: EQDrawing.y(line.db.last ?? 0, range: drawing.range, height: height)
                                + (line.kind == .right ? 9 : -9))
            }
        }
    }

    /// "100", "1k", "10k" under their lines.
    private var foot: some View {
        GeometryReader { geometry in
            ForEach(Array(zip([100.0, 1_000, 10_000], EQWords.Screen.frequencyLabels)), id: \.1) { frequency, label in
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.quiet)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize()
                    .position(x: EQDrawing.x(frequency, width: Double(geometry.size.width)),
                              y: Double(geometry.size.height) / 2)
            }
        }
        .frame(height: 16)
    }
}

/// A line's dB values, animatable: SwiftUI morphs one curve into another point for point. Lines of different lengths
/// (a correction's own f0s, slice 4) don't morph: the new one is drawn at once.
struct EQVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: EQVector { EQVector([]) }

    static func + (a: EQVector, b: EQVector) -> EQVector {
        if a.values.isEmpty { return b }
        if b.values.isEmpty || a.values.count != b.values.count { return a.values.count >= b.values.count ? a : b }
        return EQVector(zip(a.values, b.values).map { $0 + $1 })
    }

    static func - (a: EQVector, b: EQVector) -> EQVector {
        if b.values.isEmpty { return a }
        if a.values.isEmpty { return EQVector(b.values.map { -$0 }) }
        if a.values.count != b.values.count { return .zero }
        return EQVector(zip(a.values, b.values).map { $0 - $1 })
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// A curve across the plot: x by octaves (EQDrawing.x), y by dB (EQDrawing.y, `range` either way of 0). `closed`: down
/// to the 0 dB line and back, for the fill.
struct EQCurveShape: Shape {
    var values: EQVector
    let frequencies: [Double]
    var range: Double
    var closed = false

    var animatableData: AnimatablePair<EQVector, Double> {
        get { AnimatablePair(values, range) }
        set {
            values = newValue.first
            range = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = Double(rect.width), height = Double(rect.height)
        let count = min(values.values.count, frequencies.count)
        guard count > 1 else { return path }
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: EQDrawing.x(frequencies[i], width: width), y: EQDrawing.y(values.values[i], range: range, height: height))
        }
        if closed {
            path.move(to: CGPoint(x: EQDrawing.x(frequencies[0], width: width), y: height / 2))
            for i in 0..<count { path.addLine(to: point(i)) }
            path.addLine(to: CGPoint(x: EQDrawing.x(frequencies[count - 1], width: width), y: height / 2))
            path.closeSubpath()
        } else {
            path.move(to: point(0))
            for i in 1..<count { path.addLine(to: point(i)) }
        }
        return path
    }
}

/// The hairlines: ±6 and ±12 dB, and 100 Hz, 1 kHz and 10 kHz.
struct EQGridShape: Shape {
    var range: Double

    var animatableData: Double {
        get { range }
        set { range = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = Double(rect.width), height = Double(rect.height)
        for gain in [12.0, 6, -6, -12] {
            let y = EQDrawing.y(gain, range: range, height: height)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        for frequency in [100.0, 1_000, 10_000] {
            let x = EQDrawing.x(frequency, width: width)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        return path
    }
}

/// The 0 dB line, across the middle.
struct EQZeroLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The curve as VoiceOver's audio graph (3.14): "EQ curve for James's AirPods Pro"; Frequency, 20-20,000 Hz on a log
/// scale, gridlines at 100, 1,000 and 10,000, said "125 hertz"; Gain, the drawn range, said "plus 3 decibels"; one
/// continuous series "What you hear" of 61 points - or each ear's.
struct EQAudioGraph: AXChartDescriptorRepresentable {
    let drawing: EQDrawing
    let name: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXNumericDataAxisDescriptor(title: EQWords.Said.frequencyAxis, range: 20...20_000,
                                            gridlinePositions: [100, 1_000, 10_000]) { (value: Double) -> String in
            EQWords.hertzSaid(value)
        }
        x.scaleType = .log10
        let y = AXNumericDataAxisDescriptor(title: EQWords.Said.gainAxis, range: -drawing.range...drawing.range,
                                            gridlinePositions: [-12, -6, 0, 6, 12]) { (value: Double) -> String in
            EQWords.decibelsSaid((value * 2).rounded() / 2)
        }
        let series = drawing.graph.map { (s: EQDrawing.Series) -> AXDataSeriesDescriptor in
            AXDataSeriesDescriptor(name: s.name, isContinuous: true,
                                   dataPoints: s.points.map { AXDataPoint(x: $0.frequency, y: $0.db) })
        }
        return AXChartDescriptor(title: EQWords.Said.graphTitle(name), summary: drawing.summary, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: series)
    }
}
