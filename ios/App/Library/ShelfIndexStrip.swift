import DeadwaxCore
import SwiftUI

/// The index down an Albums screen's trailing edge (app/ShelfIndex.tsx; Core's ShelfIndex decides it all): the
/// letters for Artist and Title, the decades for the year sorts, as many as there is room for (`fit`, a dot for
/// those left out), as tall as the visible list. A finger on it jumps to the entry under it (`entryAt`) - at touch
/// down and at each change of entry - reading the strip as it was drawn when the touch began, never the strip's own
/// box as it changes under the finger (the .59 reviews). It never scrolls the page itself: `jump` does, to the
/// entry's group, at once.
///
/// For VoiceOver each drawn entry is a button, "Jump to A" ... "Jump to numbers and symbols", "Jump to the 1990s",
/// inside "Jump to" (ShelfIndex.tsx:167).
struct ShelfIndexStrip: View {
    let entries: [ShelfIndex.Entry]
    /// decades ("1990"), wider than a letter
    let years: Bool
    /// scroll to the group at this place among the groups
    let jump: (Int) -> Void

    /// An entry's height (`--app-index-entry: 15px`), grown with the text size (the screen holds the strip's text size
    /// to accessibility1 at most, so the letters stay letters); the slots are counted in it.
    @ScaledMetric(relativeTo: .caption2) private var entryHeight = CGFloat(ShelfIndex.entryHeight)
    /// The strip as it was drawn when the finger landed, read until it lifts.
    @State private var press: Press?
    /// The entry under the finger (its place among all the entries).
    @State private var under: Int?
    /// One more at each jump - the tick a finger feels.
    @State private var jumps = 0

    /// The strip's width: a letter's, or a year's (`--app-index-width`, `--app-index-width-years`).
    static func width(years: Bool) -> CGFloat { years ? 36 : 22 }

    /// The ShelfIndex.tsx strip's own label for VoiceOver.
    static let spoken = "Jump to"

    private struct Press {
        let drawn: [ShelfIndex.Slot]
        let top: Double
        let height: Double
    }

    var body: some View {
        GeometryReader { space in
            let height = Double(space.size.height)
            // the slots ShelfIndex counts at its 15 pt entry, for an entry grown with the text size
            let slots = ShelfIndex.slots(height: height * ShelfIndex.entryHeight / Double(max(entryHeight, 1)))
            let drawn = ShelfIndex.fit(entries, slots: slots)
            let slot = min(Double(entryHeight), height / Double(max(drawn.count, 1)))
            let extent = slot * Double(drawn.count)
            let top = max(0, (height - extent) / 2)

            VStack(spacing: 0) {
                ForEach(Array(drawn.enumerated()), id: \.offset) { _, place in
                    slotView(place)
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(slot))
                }
            }
            .frame(width: space.size.width, height: space.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { touch in
                        let held = press ?? Press(drawn: drawn, top: top, height: extent)
                        if press == nil { press = held }
                        guard let at = ShelfIndex.entryAt(held.drawn, y: Double(touch.location.y), top: held.top,
                                                          height: held.height),
                              at != under, entries.indices.contains(at) else { return }
                        under = at
                        jumps += 1
                        jump(entries[at].group)
                    }
                    .onEnded { _ in
                        press = nil
                        under = nil
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.spoken)
        }
        .frame(width: Self.width(years: years))
        .sensoryFeedback(.selection, trigger: jumps)
    }

    @ViewBuilder
    private func slotView(_ place: ShelfIndex.Slot) -> some View {
        switch place {
        case .entry(let entry, _):
            Text(entry.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(entry.accessibility)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { jump(entry.group) }
        case .dot:
            Circle()
                .fill(Palette.accent.opacity(0.6))
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)
        }
    }
}
