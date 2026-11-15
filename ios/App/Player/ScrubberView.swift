import DeadwaxCore
import SwiftUI

/// Now Playing's bar and its two clocks (NowPlaying.tsx Scrubber), every rule Core's Scrub: the whole bar is the
/// target - a tap seeks to where it lands; a drag follows the finger and seeks where it is let go, never on the way;
/// a drag the system takes away (a call, Control Center) seeks nowhere; a drag in progress is dropped when the song
/// changes under it. While a finger is on it the bar shows the finger; once let go, PlayerModel's `shownPosition`
/// holds the seek's target until the engine reports it landed (Scrub.reportedPosition and Scrub.settled), so the
/// thumb never goes back to the old time meanwhile. A slider to VoiceOver: "Position in the song", "0:12 of 5:00",
/// swipe up and down moving 5 s (Scrub.adjusted). A squared-off bar, 12 pt, 16 while held (James, 2026-11-14: "a
/// squared off thicker bar for the play progress"; the web's phone bar since 2.1.20, the same sizes); it was a 4 pt
/// capsule.
///
/// Smooth (James, 15 Nov: "Can we make the progress bar smooth instead of updating every half second?"): while the song
/// plays the bar and its clocks are drawn every frame, up to 30 a second, from PlayerModel's `barPosition(at:)` - the
/// tick's reading carried on (PlayClock), the engine not asked. Paused, loading, or under a finger, the timeline stops
/// and they show `shownPosition`, as before. The clocks read the same value as the bar, a view of their own that is
/// drawn again only when their words change; VoiceOver's value stays on `shownPosition`, twice a second at most.
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
    private static let barHeight: CGFloat = 12
    private static let heldHeight: CGFloat = 16
    private static let target: CGFloat = 44

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        // VoiceOver's value and its swipes: the ticker's, never the frames'
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        // no frames paused, loading or under the finger (and none once Now Playing has closed: the view is gone)
        let runs = player.barsRun && held == nil
        TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs)) { (_: TimelineViewDefaultContext) in
            let position = player.barPosition(at: Monotonic.seconds())
            let drawn = Scrub.shownTime(held, position: position, length: length)
            let done = length > 0 ? min(max(drawn / length, 0), 1) : 0
            VStack(spacing: 6) {
                GeometryReader { (bar: GeometryProxy) in
                    let width = bar.size.width
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(0.2))
                        Rectangle().fill(Color.primary.opacity(0.85))
                            .frame(width: done.isFinite ? width * done : 0)
                    }
                    .frame(height: drag == nil ? Self.barHeight : Self.heldHeight)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.15), value: drag == nil)
                    .gesture(press(track: track, width: width, length: length))
                }
                .frame(height: Self.target)
                ScrubberClocks(elapsed: PlayerWords.elapsed(shown: drawn),
                               remaining: PlayerWords.remaining(shown: drawn, length: length))
                    .equatable()
            }
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

/// The scrubber's two clocks, "1:23" and "-3:33": the bar's own value in whole seconds, so this view is drawn again only
/// when their words change - a second's step, not every frame the bar is.
private struct ScrubberClocks: View, Equatable {
    let elapsed: String
    let remaining: String

    var body: some View {
        HStack {
            Text(elapsed)
            Spacer()
            Text(remaining)
        }
        .font(Typeface.caption.monospacedDigit())
        .foregroundStyle(Palette.quiet)
        .accessibilityHidden(true)
    }
}
