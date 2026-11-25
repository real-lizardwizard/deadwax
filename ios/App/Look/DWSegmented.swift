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
///
/// (R1c - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") **On the phone it is words, with no
/// well**: a hairline under the whole control, the chosen segment's words white over the accent's 2 pt line as wide as
/// its segment, the others' in the second colour (`.dw.ph .seg`); and, at the accessibility sizes, each segment's words
/// in iOS's Large Content Viewer under a held finger (R2b's review: James's 14 Nov switch had one). The Mac's is R1's.
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
            phoneSegments
                .fixedSize(horizontal: !large, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(spoken)
        }
    }

    /// (R1c) The phone's: the segments side by side, 1 pt in from either end (where the well's edge was, so
    /// DWSegmentedNeed measures what is drawn), over the hairline under the whole control - each chosen line over it.
    private var phoneSegments: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { (option: Value) in
                phoneSegment(option)
            }
        }
        .padding(.horizontal, 1)
        .background(alignment: .bottom) {
            // .dw.ph .seg: box-shadow inset 0 -1px 0 #1c1b22 - under the whole control, the chosen line over it
            DWRule(colour: DWPalette.segRule)
        }
    }

    /// (R1c) A phone segment: its words semibold (`.seg button`), white over the accent's line when chosen, else in the
    /// second colour - the line as wide as the segment, at its foot (`.seg button.on`'s inset 0 -2px 0 var(--acc)).
    private func phoneSegment(_ option: Value) -> some View {
        let on = option == chosen
        let look = DWLook.here
        return Button {
            chosen = option
        } label: {
            Text(words(option))
                .font(Typeface.Look.text(large ? .largeSegment : .segment).weight(.semibold))
                .foregroundStyle(on ? DWPalette.text : DWPalette.t2)
                .lineLimit(1)
                // .seg button: padding 0 12px; .seg.lg 0, each an equal part of the control
                .padding(.horizontal, CGFloat(large ? look.largeSegmentPadding : look.segmentPadding))
                .frame(maxWidth: large ? .infinity : nil)
                .lookHeight(large ? look.largeSegmentHeight : look.segmentHeight)
                .overlay(alignment: .bottom) {
                    if on {
                        Rectangle()
                            .fill(DWPalette.acc)
                            .frame(height: CGFloat(DWFlat.chosenLine))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(DWTarget(face: Rectangle()))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(words(option))
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

/// (the redesign, slice R2b - notes/ios.md "The redesign, slice R2b: the Library's top, one row again") What a large
/// control of `words` needs across with its segments equal, as the phone draws it: the widest words in every segment,
/// in a segment's face, weight and room either side (DWSegmented's), and the 1 pt either end - drawn hidden, for a
/// layout to measure (the Library's row, whose switch folds under its circles where the row can't hold it). Nothing in
/// it is seen, touched or heard. (R1c) With no well between them a segment's words keep DWFlat's room either side
/// (6) before the row holds them: so two neighbours' words never come closer than 12 beside the circles - folded, the
/// control takes the page's width, and the words what room it has (R2b's review: "Playlists" had 0.7 pt to spare).
struct DWSegmentedNeed: View {
    let words: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(words.indices, id: \.self) { (_: Int) in
                ZStack {
                    ForEach(words.indices, id: \.self) { (at: Int) in
                        Text(words[at])
                            .font(Typeface.Look.text(.largeSegment).weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, CGFloat(DWLook.here.largeSegmentPadding))
                    }
                }
                .padding(.horizontal, CGFloat(DWFlat.segmentRoom))
            }
        }
        // the 1 pt either end, the segments' own (R2b's well edge)
        .padding(1)
        .fixedSize()
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
