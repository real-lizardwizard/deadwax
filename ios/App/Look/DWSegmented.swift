import DeadwaxCore
import SwiftUI

/// A segmented control (dw.css's .seg - the redesign, slices R1 and R1b, notes/ios.md "The redesign, slice R1b: the
/// shared look, and the phone's pieces"; R1's MacSegmented, moved here for both): drawn, since SwiftUI's segmented Picker
/// is the system's and takes no style. Its segments in a well with the line's edge, the one chosen in the selection's
/// colours; `large` is .seg.lg (the Mac's toolbar Grid | List; on the phone a control across the page's width, each
/// segment an equal part of it - `.dw.ph .seg.lg`).
///
/// Each segment is a button VoiceOver reads as selected when chosen (`.isSelected`). On the Mac, with the control
/// focused, ← and → choose the one beside it - at either end the key does nothing. The phone's takes no focus: a
/// finger's segment is its target, 44 tall at least round a smaller face.
struct DWSegmented<Value: Hashable>: View {
    let options: [Value]
    let words: (Value) -> String
    @Binding var chosen: Value
    /// What VoiceOver calls the control.
    let spoken: String
    var large = false

    @FocusState private var focused: Bool

    var body: some View {
        if Platform.mac {
            segments
                .fixedSize()
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .arrowKeys { (by: Int) -> KeyPress.Result in move(by) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(spoken)
        } else {
            segments
                .fixedSize(horizontal: !large, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(spoken)
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { (option: Value) in
                segment(option)
            }
        }
        // .seg: border 1px solid var(--line) round the segments
        .padding(1)
        .background(DWPalette.well, in: DWCorners.buttonShape)
        .clipShape(DWCorners.buttonShape)
        .overlay(DWCorners.buttonShape.strokeBorder(focused ? DWPalette.acc : DWPalette.line, lineWidth: 1))
    }

    private func segment(_ option: Value) -> some View {
        let on = option == chosen
        let look = DWLook.here
        return Button {
            chosen = option
        } label: {
            Text(words(option))
                .font(Typeface.Look.text(large ? .largeSegment : .segment).weight(.semibold))
                .foregroundStyle(on ? DWPalette.selt : DWPalette.t2)
                .lineLimit(1)
                // .seg button: padding 0 8px (.seg.lg 0 10px) on the Mac; 0 12px (.seg.lg 0, each an equal part) on
                // the phone
                .padding(.horizontal, CGFloat(large ? look.largeSegmentPadding : look.segmentPadding))
                .frame(maxWidth: large && !Platform.mac ? .infinity : nil)
                .lookHeight(large ? look.largeSegmentHeight : look.segmentHeight)
                .background {
                    if on {
                        Rectangle()
                            .fill(DWPalette.selbg)
                            .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
                    }
                }
                .contentShape(DWTarget(face: Rectangle()))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// ← or →: the segment beside the chosen one, none past either end.
    private func move(_ by: Int) -> KeyPress.Result {
        guard let at = options.firstIndex(of: chosen) else { return .ignored }
        let next = at + by
        guard options.indices.contains(next) else { return .handled }
        chosen = options[next]
        return .handled
    }
}
