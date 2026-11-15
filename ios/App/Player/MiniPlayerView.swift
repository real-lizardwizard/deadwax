import DeadwaxCore
import SwiftUI

/// The play bar, on the tab bar whenever something is queued (15 Nov; notes/ios.md "The play bar on the tab bar").
/// James: "merge the play bar with the bottom bar so it doesn't look like it's floating", "opaque the whole way", "get
/// rid of the skip forward button". AppTabBar draws it at its top, full width and square, on the bar's own opaque
/// fill, with a hairline under it: one block with the tabs.
///
/// - The cover, flush left, the bar's full height.
/// - The title, and under it the player's failure words (a skipped song's notice included) or else the artist
///   (PlayerWords.secondLine).
/// - Play/Pause, busy while the song loads: a 48 pt target with room past it to the screen's edge, so a thumb finds it.
///   There is no Next button.
/// - Along the top edge, the seek line (SeekLine).
///
/// The title and the cover take the gestures (BarTitle): a tap or a drag up opens Now Playing, a swipe across goes to the
/// next song or the one before. VoiceOver reads the bar as before, "Now playing: Roads, Portishead - open", with "Next
/// song" and "Previous song" as its actions, the only way to skip from it without a swipe. It grows with the text size
/// up to the tab bar's own cap (AppTabBar).
struct MiniPlayerView: View {
    @Environment(PlayerModel.self) private var player

    /// The bar's height at the standard text size, and its cover's: the cover is the bar's full height.
    private static let height: CGFloat = 60
    /// Play/Pause's target, and the room past it to the screen's edge.
    private static let button: CGFloat = 48
    private static let edge: CGFloat = 14

    /// The bar's height at the text size in use: its two lines' room, growing with them (never under 60).
    @ScaledMetric(relativeTo: .subheadline) private var scaled: CGFloat = 60

    init() {}

    var body: some View {
        if let entry = player.current {
            let row = max(Self.height, scaled)
            HStack(spacing: 0) {
                BarTitle(entry: entry, line: PlayerWords.secondLine(error: player.errorLine, artist: entry.track.artist),
                         row: row)
                Button { player.toggle() } label: {
                    ZStack {
                        // the glyph keeps its room under the spinner, so the button doesn't change size as it loads
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(Typeface.symbol(.title2))
                            .opacity(player.isLoading ? 0 : 1)
                        if player.isLoading {
                            ProgressView()
                        }
                    }
                    .frame(minWidth: Self.button, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Self.edge)
                .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
                .accessibilityShowsLargeContentViewer {
                    Label(PlayerWords.playPause(playing: player.isPlaying),
                          systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .frame(height: row)
            .overlay(alignment: .top) { SeekLine() }
        }
    }
}

/// The cover and the words, and the bar's gestures. A drag's direction is read once, as soon as the finger has moved
/// (PlayBar.way), and kept until it is let go:
/// - across: the words follow the finger, and on letting go past PlayBar.skipPast (or a flick) left is the next song,
///   right the song before - "right" always the song before, however far into this one (PlayerModel.songBefore, never
///   Previous's restart). The words slide out and the new song's slide in from the other side. Under the threshold, or
///   at the queue's first or last song, they spring back; toward a song that isn't there they hold back as they follow.
/// - up: Now Playing opens on letting go past PlayBar.openPast (or a flick). It is a full-screen cover, which can't
///   follow a finger, so it opens as it does for a tap.
/// - down: nothing.
/// A tap opens Now Playing.
private struct BarTitle: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: QueueEntry
    let line: String?
    let row: CGFloat

    /// Between the cover and the words.
    private static let gap: CGFloat = 12
    /// A skip's slide.
    private static let slide = Animation.easeOut(duration: 0.22)

    /// The drag's direction, once it is read.
    @State private var way: PlayBar.Way?
    /// The words' offset under the finger.
    @State private var offset: CGFloat = 0
    /// Which way the words slide as the song changes: set while a drag goes across, so the words leaving already carry
    /// it; nil otherwise, so a song changing by itself (or from the lock screen) changes the words at once, as before.
    @State private var sliding: PlayBar.Skip?
    /// True while the drag is live - put back to false however it ends, so a drag still read when it does was taken by
    /// the system, not let go (as ScrubberView's).
    @GestureState private var touching = false

    var body: some View {
        let track = entry.track
        HStack(spacing: Self.gap) {
            CoverImage(id: track.coverArt, size: row)
                .frame(width: row, height: row)
                .clipShape(Corners.artShape)
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(Typeface.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let line, !line.isEmpty {
                        Text(line)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // the offset is each song's words' own: the words leaving keep where the finger left them, and the new
                // song's come in from beyond the column's edge, not from under the finger
                .offset(x: offset)
                .id(entry.key)
                .transition(transition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .animation(Self.slide, value: entry.key)
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .gesture(drag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayerWords.miniPlayerLabel(title: track.title, line: line))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            if player.hasSongAfter {
                Button(PlayerWords.nextSong) { player.next() }
            }
            if player.hasSongBefore {
                Button(PlayerWords.previousSong) { player.songBefore() }
            }
        }
        .onChange(of: entry.key) { (_: Int, _: Int) -> Void in
            // the slide was taken by the words as they changed: the next change is a plain one unless a drag says
            Task { @MainActor in sliding = nil }
        }
        .onChange(of: touching) { (_: Bool, live: Bool) -> Void in
            //? the gesture went without an end of its own: the system took the touch - nothing skips or opens
            guard !live, way != nil else { return }
            way = nil
            sliding = nil
            withAnimation(.spring(duration: 0.3)) { offset = 0 }
        }
    }

    /// How the words leave and come in: sliding the drag's way, or, under Reduce Motion, fading; at once otherwise.
    private var transition: AnyTransition {
        guard let sliding else { return .identity }
        if reduceMotion { return .opacity }
        switch sliding {
        case .next: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .before: return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: PlayBar.decideAfter, coordinateSpace: .local)
            .updating($touching) { (_: DragGesture.Value, live: inout Bool, _: inout Transaction) -> Void in live = true }
            .onChanged { (value: DragGesture.Value) -> Void in
                let dx = value.translation.width
                guard let decided = way ?? PlayBar.way(dx: dx, dy: value.translation.height) else { return }
                way = decided
                guard decided == .across else { return }
                sliding = dx < 0 ? .next : .before
                let there = PlayBar.songThere(dx: dx, before: player.hasSongBefore, after: player.hasSongAfter)
                offset = PlayBar.followed(dx: dx, songThere: there)
            }
            .onEnded { (value: DragGesture.Value) -> Void in
                let decided = way
                way = nil
                switch decided {
                case .across:
                    let dx = value.translation.width
                    if let skip = PlayBar.skip(dx: dx, predicted: value.predictedEndTranslation.width),
                       skip == .next ? player.hasSongAfter : player.hasSongBefore {
                        sliding = skip
                        let was = entry.key
                        if skip == .next { player.next() } else { player.songBefore() }
                        if player.current?.key != was {
                            // the new song's words start at their place; the column's animation slides them in
                            offset = 0
                        } else {
                            sliding = nil
                            withAnimation(.spring(duration: 0.3)) { offset = 0 }
                        }
                    } else {
                        sliding = nil
                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                    }
                case .up:
                    if PlayBar.opens(dy: value.translation.height, predicted: value.predictedEndTranslation.height) {
                        open()
                    }
                case .down, nil:
                    break
                }
            }
    }

    private func open() {
        navigation.nowPlayingShown = true
    }
}

/// The seek line along the play bar's top edge (James: "let's put the progress on top of the play bar"): at rest a 2 pt
/// line of --dw-border, the part played in the accent; a finger on it thickens it to 8 pt, with the time under the
/// finger over it ("1:23 / 4:56"). Every rule is Now Playing's scrubber's (Scrub): it follows the finger and seeks once,
/// where it is let go; a drag the system takes away seeks nowhere; the song changing under it drops it; PlayerModel's
/// `shownPosition` holds the seek's target until the engine says it landed. One rule is the bar's own: a touch that
/// never moved PlayBar.seekSlop across seeks nowhere, since its 16 pt touch area reaches over the title's top and the
/// page's foot, where a tap means something else. A slider to VoiceOver, "Position in the song", "0:12 of 5:00", 10 s a
/// swipe (PlayBar.adjusted). A view of its own, so only it is drawn again as the position moves.
private struct SeekLine: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.displayScale) private var displayScale

    /// The finger on the line.
    @State private var drag: Scrub.Drag?
    /// This touch has begun (ScrubberView's `pressed`).
    @State private var pressed = false
    /// The furthest this touch has gone across from where it went down.
    @State private var moved: CGFloat = 0
    /// True while the drag is live (ScrubberView's `touching`).
    @GestureState private var touching = false

    /// The line at rest, and under a finger.
    private static let rest: CGFloat = 2
    private static let held: CGFloat = 8
    /// The touch area's height, centred on the line.
    private static let reach: CGFloat = 16
    /// The time's gap above the held line, and its least room from the screen's sides.
    private static let lift: CGFloat = 6
    private static let side: CGFloat = 8

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        let done = PlayerWords.progress(position: shown, duration: length)
        let part = done.isFinite ? min(max(done, 0), 1) : 0
        GeometryReader { (band: GeometryProxy) in
            let width = band.size.width
            ZStack(alignment: .leading) {
                Color.clear
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.border)
                    Rectangle().fill(Palette.accent)
                        .frame(width: width * part)
                }
                .frame(height: held == nil ? Self.rest : Self.held)
                .animation(.easeOut(duration: 0.15), value: held == nil)
            }
            .contentShape(Rectangle())
            .gesture(press(track: track, width: width, length: length))
            .overlay(alignment: .topLeading) {
                if held != nil {
                    tag(PlayerWords.barTime(shown: shown, length: length), at: width * part, width: width)
                }
            }
        }
        .frame(height: Self.reach)
        // the touch area centred on the line, whose top is the bar's top edge: the half above it overlaps the page
        .offset(y: Self.rest / 2 - Self.reach / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayerWords.scrubberName)
        .accessibilityValue(PlayerWords.scrubberValue(shown: shown, length: length))
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) -> Void in
            let increment: Bool
            switch direction {
            case .increment: increment = true
            case .decrement: increment = false
            @unknown default: return
            }
            if let target = PlayBar.adjusted(increment: increment, from: shown, length: length) {
                player.seek(to: target)
            }
        }
        .onChange(of: track) { (_: String, now: String) -> Void in drag = Scrub.dragFor(drag, track: now) }
        .onChange(of: touching) { (_: Bool, live: Bool) -> Void in
            //? the gesture went without an end of its own: the system took the touch - a cancel seeks nowhere
            guard !live, pressed else { return }
            pressed = false
            drag = Scrub.dragEnd(drag, pointer: 0, how: .cancel).drag
        }
    }

    /// The time over the finger, above the held line, kept on the screen.
    private func tag(_ words: String, at x: CGFloat, width: CGFloat) -> some View {
        Text(words)
            .font(Typeface.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Palette.tabBar, in: Corners.controlShape)
            .overlay(Corners.controlShape.strokeBorder(Palette.border, lineWidth: 1 / max(displayScale, 1)))
            .fixedSize()
            .alignmentGuide(.leading) { (tag: ViewDimensions) -> CGFloat in
                -min(max(x - tag.width / 2, Self.side), max(width - tag.width - Self.side, Self.side))
            }
            .alignmentGuide(.top) { (tag: ViewDimensions) -> CGFloat in
                // its foot `lift` above the held line's top, which is (reach - held) / 2 into the touch area
                tag.height + Self.lift - (Self.reach - Self.held) / 2
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func press(track: String, width: CGFloat, length: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { (_: DragGesture.Value, live: inout Bool, _: inout Transaction) -> Void in live = true }
            .onChanged { (value: DragGesture.Value) -> Void in
                let time = Scrub.timeAt(x: value.location.x, left: 0, width: width, length: length)
                if !pressed {
                    pressed = true
                    moved = 0
                    //? no length yet: the line is no target (as the scrubber)
                    if length > 0 { drag = Scrub.dragStart(pointer: 0, track: track, time: time) }
                } else {
                    moved = max(moved, abs(value.translation.width))
                    drag = Scrub.dragMove(drag, pointer: 0, time: time)
                }
            }
            .onEnded { (value: DragGesture.Value) -> Void in
                pressed = false
                let how: Scrub.Release = PlayBar.seeks(moved: max(moved, abs(value.translation.width))) ? .up : .cancel
                let (next, seek) = Scrub.dragEnd(drag, pointer: 0, how: how)
                drag = next
                if let seek { player.seek(to: seek) }
            }
    }
}
