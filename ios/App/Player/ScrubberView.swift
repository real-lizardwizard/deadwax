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
/// plays the bar's fill and its clocks are drawn every frame, up to 30 a second, from PlayerModel's `barPosition(at:)` -
/// the tick's reading carried on (PlayClock), the engine not asked - each in a timeline of its own, the bar's track and
/// its touch outside them, as the seek line's. Hidden or covered (`visible` false), paused, or under a finger, the
/// timelines stop and they show what PlayerModel says, as before. The clocks read the same value as the fill, a view
/// of their own drawn again only when their words change; VoiceOver's value stays on `shownPosition`, twice a second
/// at most.
///
/// Sunken (the redesign, slice R4b - notes/ios.md "The redesign, slice R4b: Now Playing's face"; iNowPlaying's `.meter`):
/// a sunken track keeps its face on the flat phone (R1c), so the bar is drawn as DWMeter draws a download's - the well,
/// its 1 pt line, the shade along its top, square - and the part played is the meter's grey fill inside the line. Its
/// 12 and 16 points are James's (the drawing's 8 is the download meter's), its target, its drag, its timelines and its
/// VoiceOver as they were; the clocks under it in Courier Prime, in the second colour (`.mono.xs.q`).
struct ScrubberView: View {
    @Environment(PlayerModel.self) private var player
    /// The scrubber can be seen: on the cover, with no sheet over Now Playing. The turntable keeps its row (hidden, the
    /// time line in its place) and Up Next's, Info's, the EQ's and the playlist picker's sheets cover it - and no
    /// frame is drawn for a bar no one sees (review, 15 Nov).
    let visible: Bool
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
    /// (R4b) The track's line, which the fill sits inside (`.meter`'s border, `.meter > i` inside it).
    private static let edge: CGFloat = 1

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        // VoiceOver's value and its swipes: the ticker's, never the frames'
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        // no frames hidden or covered (the turntable's look, a sheet over Now Playing), paused, loading or under the
        // finger - and none once Now Playing has closed, the view gone with it
        let runs = visible && player.barsRun && held == nil
        VStack(spacing: 6) {
            GeometryReader { (bar: GeometryProxy) in
                let width = bar.size.width
                ZStack(alignment: .leading) {
                    // (R4b) the sunken track, DWMeter's: the well with the shade along its top, inside its line
                    DWCorners.meterShape
                        .fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1)))
                        .overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: Self.edge) }
                    TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs)) {
                        (_: TimelineViewDefaultContext) in
                        // the part played, the meter's grey, inside the track's line as `.meter > i` is
                        DWCorners.meterFillShape.fill(DWPalette.meterFill)
                            .frame(width: max(0, width - 2 * Self.edge) * Self.part(drawn(held, length: length), length: length))
                    }
                    .padding(Self.edge)
                }
                .frame(height: drag == nil ? Self.barHeight : Self.heldHeight)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: drag == nil)
                .gesture(press(track: track, width: width, length: length))
            }
            .frame(height: Self.target)
            TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs)) {
                (_: TimelineViewDefaultContext) in
                let time = drawn(held, length: length)
                ScrubberClocks(elapsed: PlayerWords.elapsed(shown: time),
                               remaining: PlayerWords.remaining(shown: time, length: length))
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

    /// The time the fill and the clocks draw now: the finger's, else PlayerModel's for the bars (the carried reading
    /// while they run) - read inside their timelines alone.
    private func drawn(_ held: Scrub.Drag?, length: Double) -> Double {
        Scrub.shownTime(held, position: player.barPosition(at: Monotonic.seconds()), length: length)
    }

    /// The played part of the bar, 0...1 (none for no length).
    private static func part(_ drawn: Double, length: Double) -> CGFloat {
        guard length > 0 else { return 0 }
        let done = min(max(drawn / length, 0), 1)
        return done.isFinite ? CGFloat(done) : 0
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
/// when their words change - a second's step, not every frame the bar is. In the readout face (25 Nov), as iNowPlaying
/// draws them (`mono xs`): Libre Franklin has no tabular figures, so they'd shift as they count. (R4b) In the second
/// colour, the drawing's `.q`.
private struct ScrubberClocks: View, Equatable {
    let elapsed: String
    let remaining: String

    var body: some View {
        HStack {
            Text(elapsed)
            Spacer()
            Text(remaining)
        }
        .font(Typeface.readout(.caption))
        .foregroundStyle(DWPalette.t2)
        .accessibilityHidden(true)
    }
}
