import DeadwaxCore
import SwiftUI

/// Now Playing's bar and its two clocks (NowPlaying.tsx Scrubber), every rule Core's Scrub: the whole bar is the
/// target - a tap seeks to where it lands; a drag follows the finger and seeks where it is let go, never on the way;
/// a drag the system takes away (a call, Control Center) seeks nowhere; a drag in progress is dropped when the song
/// changes under it. While a finger is on it the bar shows the finger; once let go, PlayerModel's `shownPosition`
/// holds the seek's target until the engine reports it landed (Scrub.reportedPosition and Scrub.settled), so the
/// thumb never goes back to the old time meanwhile. A slider to VoiceOver: "Position in the song", "0:12 of 5:00",
/// swipe up and down moving 5 s (Scrub.adjusted).
struct ScrubberView: View {
    @Environment(PlayerModel.self) private var player
    /// The finger on the bar (one: a phone's bar takes one touch).
    @State private var drag: Scrub.Drag?
    /// True while the drag gesture is live - SwiftUI puts it back to false however the gesture ends, so a drag still
    /// held when it does was cancelled, not let go.
    @GestureState private var touching = false
    /// This touch has begun: its moves follow a drag, and never start another - one dropped (the song changed under
    /// it) stays dropped until the finger is lifted.
    @State private var pressed = false

    /// The bar's own height, and the tap target's around it.
    private static let barHeight: CGFloat = 4
    private static let heldHeight: CGFloat = 8
    private static let target: CGFloat = 44

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let shown = Scrub.shownTime(Scrub.dragFor(drag, track: track), position: player.shownPosition, length: length)
        let done = length > 0 ? min(max(shown / length, 0), 1) : 0
        VStack(spacing: 6) {
            GeometryReader { bar in
                let width = bar.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.2))
                    Capsule().fill(Color.primary.opacity(0.85))
                        .frame(width: done.isFinite ? width * done : 0)
                }
                .frame(height: drag == nil ? Self.barHeight : Self.heldHeight)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: drag == nil)
                .gesture(press(track: track, width: width, length: length))
            }
            .frame(height: Self.target)
            HStack {
                Text(PlayerWords.elapsed(shown: shown))
                Spacer()
                Text(PlayerWords.remaining(shown: shown, length: length))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Palette.quiet)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayerWords.scrubberName)
        .accessibilityValue(PlayerWords.scrubberValue(shown: shown, length: length))
        .accessibilityAdjustableAction { direction in
            let increment: Bool
            switch direction {
            case .increment: increment = true
            case .decrement: increment = false
            @unknown default: return
            }
            if let target = Scrub.adjusted(increment: increment, from: shown, length: length) { player.seek(to: target) }
        }
        .onChange(of: track) { _, now in drag = Scrub.dragFor(drag, track: now) }
        .onChange(of: touching) { _, live in
            //? the gesture went without an end of its own: the system took the touch - a cancel seeks nowhere
            guard !live, pressed else { return }
            pressed = false
            drag = Scrub.dragEnd(drag, pointer: 0, how: .cancel).drag
        }
    }

    private func press(track: String, width: CGFloat, length: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, live, _ in live = true }
            .onChanged { value in
                let time = Scrub.timeAt(x: value.location.x, left: 0, width: width, length: length)
                if !pressed {
                    pressed = true
                    //? no length yet: the bar is no target (the web's pointerdown returns)
                    if length > 0 { drag = Scrub.dragStart(pointer: 0, track: track, time: time) }
                } else {
                    drag = Scrub.dragMove(drag, pointer: 0, time: time)
                }
            }
            .onEnded { _ in
                pressed = false
                let (next, seek) = Scrub.dragEnd(drag, pointer: 0, how: .up)
                drag = next
                if let seek { player.seek(to: seek) }
            }
    }
}
