import DeadwaxCore
import SwiftUI

/// A segmented control (dw.css's .seg - the Mac redesign, slice R1, notes/ios.md "The Mac redesign, slice R1: the frame
/// and the shared pieces"): drawn, since SwiftUI's segmented Picker is the system's and takes no style. Its segments in a
/// well with the line's edge, the one chosen in the selection's colours; `large` is .seg.lg (a toolbar's Grid | List).
///
/// Each segment is a button VoiceOver reads as selected when chosen (`.isSelected`); with the control focused, ← and →
/// choose the one beside it - at either end the key does nothing.
struct MacSegmented<Value: Hashable>: View {
    let options: [Value]
    let words: (Value) -> String
    @Binding var chosen: Value
    /// What VoiceOver calls the control.
    let spoken: String
    var large = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { (option: Value) in
                segment(option)
            }
        }
        // .seg: border 1px solid var(--line) round the segments
        .padding(1)
        .background(MacPalette.well, in: MacCorners.buttonShape)
        .clipShape(MacCorners.buttonShape)
        .overlay(MacCorners.buttonShape.strokeBorder(focused ? MacPalette.acc : MacPalette.line, lineWidth: 1))
        .fixedSize()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .arrowKeys { (by: Int) -> KeyPress.Result in move(by) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
    }

    private func segment(_ option: Value) -> some View {
        let on = option == chosen
        return Button {
            chosen = option
        } label: {
            Text(words(option))
                .font(Typeface.Mac.text(large ? .control : .label).weight(.semibold))
                .foregroundStyle(on ? MacPalette.selt : MacPalette.t2)
                .lineLimit(1)
                // .seg button: padding 0 8px (.seg.lg 0 10px)
                .padding(.horizontal, large ? 10 : 8)
                .frame(height: CGFloat(large ? MacLook.largeSegmentHeight : MacLook.segmentHeight))
                .background {
                    if on {
                        Rectangle()
                            .fill(MacPalette.selbg)
                            .overlay(Rectangle().strokeBorder(MacPalette.selbd, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
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
