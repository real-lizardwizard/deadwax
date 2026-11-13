import DeadwaxCore
import SwiftUI
import UIKit

/// The tone's ten sliders (eq.md 3.5): one row, the bands an octave apart left to right, each its own band's gain -
/// the curve above is their sum.
///
/// - **The look**: ten columns sharing the width; in each a 4 pt track the full 200 pt in `barTrack` with a `barEdge`
///   hairline, a fill from the 0 dB mark to the knob in `accent`, and the knob - a 24 pt white circle with the iOS
///   slider's own shadow. A 1 pt line at 0 dB in `textTertiary` across all ten, "+12", "0", "-12" inside the first
///   column, each band's name under it; while a knob is held, its value on a capsule above it (below it near the top,
///   where above is off the row). Labels stop growing at `.xxxLarge`.
/// - **A drag** takes hold wherever the knob is - a touch anywhere in a column grabs its knob without moving it - and
///   moves nothing until the finger has gone 6 pt up or down; then the knob follows the finger's movement, 24 dB over
///   the track's 200 pt, rounded to 0.5 dB, and every new value is heard (a bank, crossfaded). A light tick as it
///   crosses into 0 dB. A double-tap puts a band back to 0. The finger's down and up are told (`onHold`), so the
///   page never switches output under it and the file is written once, at its end.
/// - **Moves**: a preset chosen moves the knobs over 0.25 s, at once under Reduce Motion; a drag never animates.
/// - **VoiceOver**: each column one adjustable element - "125 hertz", "plus 3.5 decibels" - a swipe up or down 1 dB,
///   and the action "Reset to 0"; the ten in frequency order. The tick isn't given to VoiceOver's steps.
struct EQSliders: View {
    let gains: [Double]
    /// a band's new value
    let onChange: (Int, Double) -> Void
    /// a finger down (true) or up (false)
    let onHold: (Bool) -> Void

    static let track: CGFloat = 200
    static let knob: CGFloat = 24
    /// room above and below the track for the knob's half, and the held value's capsule
    static let margin: CGFloat = 14

    @State private var grab: Grab?
    @State private var lastTap: (band: Int, at: Date)?
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    @GestureState private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The knob a finger holds: its band, its drag (Core's EQSliderDrag: where it took hold, where it engaged) and the
    /// value last given.
    private struct Grab {
        var band: Int
        var drag: EQSliderDrag
        var last: Double
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let column = geometry.size.width / CGFloat(max(gains.count, 1))
                ZStack(alignment: .topLeading) {
                    // the 0 dB line across all ten, under the tracks
                    Rectangle()
                        .fill(Palette.textTertiary)
                        .frame(width: geometry.size.width, height: 1)
                        .offset(y: Self.margin + Self.track / 2 - 0.5)
                    scale
                    HStack(spacing: 0) {
                        ForEach(gains.indices, id: \.self) { band in
                            EQBandColumn(band: band, gain: gains[band], held: grab?.band == band,
                                         onAdjust: { up in
                                             onChange(band, EQSliderRules.adjusted(gains[band], up: up))
                                         },
                                         onReset: { onChange(band, 0) })
                                .frame(width: column)
                        }
                    }
                }
                // a preset chosen, a double-tap's reset, a VoiceOver step: the knobs move over 0.25 s - never under
                // a finger, which they follow; at once under Reduce Motion
                .animation(grab == nil && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: gains)
                .contentShape(Rectangle())
                .gesture(drag(column: column))
            }
            .frame(height: Self.track + 2 * Self.margin)
            names
        }
        .padding(.vertical, 8)
        .onChange(of: pressing) { _, now in
            // the touch ended or was taken away (a call, a system gesture): let go either way
            if !now { letGo() }
        }
        // gone with a finger still down (a second finger on Back, the text size crossing into the stepper rows): let
        // go, so the page and EQModel aren't left holding - a hold never let go would keep eq.json unwritten until the
        // app went to the back
        .onDisappear { letGo() }
    }

    /// "+12", "0", "-12" inside the first column, beside the track's top, middle and foot.
    private var scale: some View {
        ForEach(Array(zip([12.0, 0, -12], EQWords.Screen.gainLabels)), id: \.1) { gain, label in
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Palette.quiet)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .fixedSize()
                .position(x: 10, y: Self.margin + Self.track * EQSliderRules.place(gain) - 8)
                .accessibilityHidden(true)
        }
    }

    /// Each band's name, under its column.
    private var names: some View {
        HStack(spacing: 0) {
            ForEach(gains.indices, id: \.self) { band in
                Text(EQWords.Tone.bands[band])
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.quiet)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func drag(column: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { value in
                if grab == nil {
                    let band = min(max(Int(value.startLocation.x / max(column, 1)), 0), gains.count - 1)
                    grab = Grab(band: band, drag: EQSliderDrag(start: gains[band]), last: gains[band])
                    haptic.prepare()
                    onHold(true)
                }
                guard var held = grab else { return }
                // from where it engaged, so neither taking hold nor passing back over it makes the knob jump
                let dy = Double(value.translation.height)
                guard let gain = held.drag.value(dy: dy, track: Double(Self.track)) else { return }
                if gain != held.last {
                    if EQSliderRules.ticks(from: held.last, to: gain) { haptic.impactOccurred() }
                    held.last = gain
                    onChange(held.band, gain)
                }
                grab = held
            }
            .onEnded { _ in
                guard let held = grab else { return }
                if !held.drag.engaged {
                    // a tap: two on the same band, quickly, put it back to 0
                    if let tap = lastTap, tap.band == held.band, Date().timeIntervalSince(tap.at) < 0.35 {
                        if gains[held.band] != 0 {
                            haptic.impactOccurred()
                            onChange(held.band, 0)
                        }
                        lastTap = nil
                    } else {
                        lastTap = (held.band, Date())
                    }
                }
                letGo()
            }
    }

    private func letGo() {
        guard grab != nil else { return }
        grab = nil
        onHold(false)
    }
}

/// One band's column: its track, fill, knob and - held - its value. One adjustable element for VoiceOver.
private struct EQBandColumn: View {
    let band: Int
    let gain: Double
    let held: Bool
    let onAdjust: (Bool) -> Void
    let onReset: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let top = EQSliders.margin
        let track = EQSliders.track
        let knobY = top + track * EQSliderRules.place(gain)
        let zeroY = top + track / 2
        ZStack(alignment: .top) {
            Capsule()
                .fill(Palette.barTrack)
                .overlay(Capsule().strokeBorder(Palette.barEdge, lineWidth: 1 / max(displayScale, 1)))
                .frame(width: 4, height: track)
                .offset(y: top)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 4, height: abs(knobY - zeroY))
                .offset(y: min(knobY, zeroY))
            Circle()
                .fill(Color.white)
                .frame(width: EQSliders.knob, height: EQSliders.knob)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(y: knobY - EQSliders.knob / 2)
            if held {
                Text(EQWords.held(gain))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.barTrack, in: Capsule())
                    // above the knob; below it near the top, where above is off the row
                    .offset(y: gain > 6 ? knobY + EQSliders.knob / 2 + 4 : knobY - EQSliders.knob / 2 - 24)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EQWords.Tone.bandSaid(band))
        .accessibilityValue(EQWords.decibelsSaid(gain))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(true)
            case .decrement: onAdjust(false)
            @unknown default: break
            }
        }
        .accessibilityAction(named: EQWords.Tone.resetToZero, onReset)
    }
}

/// At the accessibility sizes (3.15): a band as a row of its own - "31 Hz", "+3.5 dB", and a Stepper of 0.5 dB from -12
/// to +12 - its words above the stepper when they don't fit beside it. One adjustable element, the band's label and
/// value as the slider's.
struct EQStepperRow: View {
    let band: Int
    let gain: Double
    let onChange: (Int, Double) -> Void
    let onHold: (Bool) -> Void

    var body: some View {
        let value = Binding<Double>(get: { gain }, set: { (new: Double) -> Void in
            onChange(band, EQGraphic.snapped(new))
        })
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                words
                Spacer(minLength: 8)
                stepper(value)
            }
            VStack(alignment: .leading, spacing: 8) {
                words
                stepper(value)
            }
        }
    }

    /// The words, for the eye: the Stepper says them to VoiceOver.
    private var words: some View {
        HStack(spacing: 12) {
            Text(EQWords.Tone.bandLabel(band))
            Text(EQWords.held(gain))
                .monospacedDigit()
                .foregroundStyle(Palette.quiet)
        }
        .accessibilityHidden(true)
    }

    private func stepper(_ value: Binding<Double>) -> some View {
        Stepper(value: value, in: EQGraphic.range, step: EQGraphic.step, onEditingChanged: onHold) {
            Text(EQWords.Tone.bandLabel(band))
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(EQWords.Tone.bandSaid(band))
        .accessibilityValue(EQWords.decibelsSaid(gain))
    }
}
