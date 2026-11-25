import DeadwaxCore
import SwiftUI

/// The play bar, on the tab bar whenever something is queued (15 Nov; notes/ios.md "The play bar on the tab bar").
/// James: "merge the play bar with the bottom bar so it doesn't look like it's floating", "opaque the whole way", "get
/// rid of the skip forward button". AppTabBar draws it at its top, full width and square, over the tabs' own edge: one
/// block with the tabs. Drawn since the redesign's slice R4 as dw.css's .mini (notes/ios.md "The redesign, slice R4: the
/// player bar, the mini player and the tab bar"): 60 tall at least (PhoneLook.mini) on its own ground (PhoneMiniGround,
/// #1c1b22 under its top edge).
///
/// - The cover, flush left, the bar's full height under its top edge, the line's rule at its right.
/// - The title, and under it the player's failure words (a skipped song's notice included) or else the artist
///   (PlayerWords.secondLine), 10 short of Play/Pause (.mini's gap, the title's to tap).
/// - Play/Pause, bare (a sharp glyph, never a round key - James, 25 Nov: "Sharp glyphs"), busy while the song loads: a
///   48 pt target (PhoneLook.miniPlay) with 12 past it to the screen's edge (PhoneLook.miniTrail), so a thumb finds it.
///   There is no Next button.
/// - Along the top edge, the seek line (SeekLine), 2 pt in the purple gradient, drawn only: the bar's drag seeks with it.
///
/// One drag takes the whole bar (after its review, 15 Nov), read once as soon as the finger has moved (PlayBar.way and
/// PlayBar.role, from where it began): across from the bar's top PlayBar.seekReach a seek, across from the title or the
/// cover a skip, up from anywhere Now Playing, down nothing. It is a high-priority DragGesture with a minimum distance,
/// so a tap is never one: a tap anywhere on the cover or the words opens Now Playing (BarTitle), and anywhere on
/// Play/Pause toggles - its top edge, under the line, included. Nothing above the bar is the bar's: the page there keeps
/// its taps and scrolls. A seek or a skip begun on one song and let go on another does nothing (PlayBar.atLetGo).
///
/// VoiceOver reads the title (with "Next song" and "Previous song" as its actions, the only way to skip from the bar
/// without a swipe), then Play/Pause, then the line. It grows with the text size up to the tab bar's own cap (AppTabBar).
struct MiniPlayerView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation

    /// The bar's height at the standard text size (.mini's 60): the cover is its full height under the top edge.
    private static let height = CGFloat(PhoneLook.mini)
    /// Play/Pause's target, and the room past it to the screen's edge (.mini .key.big's 48, .mini's padding-right 12).
    private static let button = CGFloat(PhoneLook.miniPlay)
    private static let edge = CGFloat(PhoneLook.miniTrail)

    /// The bar's height at the text size in use: its two lines' room, growing with them (never under 60).
    @ScaledMetric(relativeTo: .subheadline) private var scaled = CGFloat(PhoneLook.mini)

    /// The bar's width: where a finger is along the seek line, and whether a drag began over Play/Pause.
    @State private var width: CGFloat = 0
    /// The drag on the bar, once read.
    @State private var hold: Hold?
    /// A seek's finger along the line (Scrub's drag, as Now Playing's scrubber keeps it).
    @State private var seek: Scrub.Drag?
    /// A skip's words under the finger, and which way they slide as the song changes - set while the skip's drag goes
    /// across, so the words leaving already carry it; nil otherwise, so a song changing by itself (or from the lock
    /// screen) changes the words at once.
    @State private var offset: CGFloat = 0
    @State private var sliding: PlayBar.Skip?
    /// True while the drag is live - put back to false however it ends, so a drag still held when it does was taken by
    /// the system, not let go (as ScrubberView's).
    @GestureState private var touching = false

    /// A drag read: what it does, and the entry it began on.
    private struct Hold: Equatable {
        let role: PlayBar.Role
        let key: Int
    }

    init() {}

    var body: some View {
        if let entry = player.current {
            let row = max(Self.height, scaled)
            HStack(spacing: 0) {
                BarTitle(entry: entry, line: PlayerWords.secondLine(error: player.errorLine, artist: entry.track.artist),
                         row: row, offset: offset, sliding: sliding)
                    .accessibilitySortPriority(3)
                Button { player.toggle() } label: {
                    ZStack {
                        // the glyph keeps its room under the spinner, so the button doesn't change size as it loads
                        PlayPauseGlyph(playing: player.isPlaying)
                            .font(Typeface.symbol(.title2))
                            .opacity(player.isLoading ? 0 : 1)
                        if player.isLoading {
                            ProgressView()
                                .tint(DWPalette.text)
                        }
                    }
                    // .mini .key: bare - no face, no edge, no shadow - in its white
                    .foregroundStyle(DWPalette.text)
                    .frame(minWidth: Self.button, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Self.edge)
                .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
                .accessibilityShowsLargeContentViewer {
                    Label {
                        Text(PlayerWords.playPause(playing: player.isPlaying))
                    } icon: {
                        Image(uiImage: (player.isPlaying ? SharpGlyph.pause : SharpGlyph.play).image)
                    }
                }
                .accessibilitySortPriority(2)
            }
            .frame(height: row)
            .background { PhoneMiniGround() }
            .overlay(alignment: .top) {
                SeekLine(drag: seek)
                    .accessibilitySortPriority(1)
            }
            .onGeometryChange(for: CGFloat.self) { (bar: GeometryProxy) -> CGFloat in
                bar.size.width
            } action: { (now: CGFloat) -> Void in
                width = now
            }
            .contentShape(Rectangle())
            .highPriorityGesture(drag)
            // the title, Play/Pause, then the line - in that order, whatever their frames (the line's starts above the bar)
            .accessibilityElement(children: .contain)
            .onChange(of: entry.key) { (_: Int, _: Int) -> Void in
                // the slide was taken by the words as they changed: the next change is a plain one unless a skip says
                Task { @MainActor in sliding = nil }
            }
            .onChange(of: touching) { (_: Bool, live: Bool) -> Void in
                //? the gesture went without an end of its own: the system took the touch - nothing seeks, skips or opens
                guard !live, hold != nil else { return }
                hold = nil
                seek = nil
                springBack()
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: PlayBar.decideAfter, coordinateSpace: .local)
            .updating($touching) { (_: DragGesture.Value, live: inout Bool, _: inout Transaction) -> Void in live = true }
            .onChanged { (value: DragGesture.Value) -> Void in
                guard let now = player.current else { return }
                let dx = value.translation.width
                let held: Hold
                if let hold {
                    held = hold
                } else {
                    guard let way = PlayBar.way(dx: dx, dy: value.translation.height) else { return }
                    let onTitle = value.startLocation.x < width - (Self.button + Self.edge)
                    held = Hold(role: PlayBar.role(way, startY: value.startLocation.y, onTitle: onTitle), key: now.key)
                    hold = held
                }
                //? the song changed under the finger: the drag is dropped, and stays dropped until it is let go
                guard held.key == now.key else {
                    seek = nil
                    if offset != 0 { springBack() }
                    return
                }
                switch held.role {
                case .seek:
                    let length = player.duration
                    //? no length yet: the line is no target (as the scrubber)
                    guard length > 0 else { return }
                    let time = Scrub.timeAt(x: value.location.x, left: 0, width: width, length: length)
                    if let seek {
                        self.seek = Scrub.dragMove(seek, pointer: 0, time: time)
                    } else {
                        seek = Scrub.dragStart(pointer: 0, track: now.track.id, time: time)
                    }
                case .skip:
                    sliding = dx < 0 ? .next : .before
                    let there = PlayBar.songThere(dx: dx, before: player.hasSongBefore, after: player.hasSongAfter)
                    offset = PlayBar.followed(dx: dx, songThere: there)
                case .open, .nothing:
                    break
                }
            }
            .onEnded { (value: DragGesture.Value) -> Void in
                guard let held = hold else { return }
                hold = nil
                let seeking = Scrub.dragFor(seek, track: player.current?.track.id ?? "")
                seek = nil
                switch PlayBar.atLetGo(held.role, began: held.key, now: player.current?.key) {
                case .seek:
                    if let target = Scrub.dragEnd(seeking, pointer: 0, how: .up).seek { player.seek(to: target) }
                case .skip:
                    skip(dx: value.translation.width, predicted: value.predictedEndTranslation.width)
                case .open:
                    if PlayBar.opens(dy: value.translation.height, predicted: value.predictedEndTranslation.height) {
                        navigation.nowPlayingShown = true
                    }
                case .nothing:
                    springBack()
                }
            }
    }

    /// A skip's drag let go: the next song or the one before past the threshold (or a flick) with a song there, the
    /// words sliding; else back where they were.
    private func skip(dx: CGFloat, predicted: CGFloat) {
        guard let skip = PlayBar.skip(dx: dx, predicted: predicted),
              skip == .next ? player.hasSongAfter : player.hasSongBefore else {
            springBack()
            return
        }
        sliding = skip
        let was = player.current?.key
        if skip == .next { player.next() } else { player.songBefore() }
        if player.current?.key != was {
            // the new song's words start at their place; the column's animation slides them in
            offset = 0
        } else {
            springBack()
        }
    }

    private func springBack() {
        sliding = nil
        withAnimation(.spring(duration: 0.3)) { offset = 0 }
    }
}

/// The cover and the words (the bar's drag is MiniPlayerView's). A tap anywhere on them opens Now Playing. Under a
/// skip's finger the words follow it (`offset`); as the song changes on a skip they slide out and the new song's slide
/// in from the other side (`sliding`), fading instead under Reduce Motion. VoiceOver reads them as one button, "Now
/// playing: Roads, Portishead - open" (PlayerWords.miniPlayerLabel), whose actions are "Next song" and "Previous song",
/// each only while there is a song that way - "previous" always the song before, however far into this one
/// (PlayerModel.songBefore, never Previous's restart).
private struct BarTitle: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: QueueEntry
    let line: String?
    let row: CGFloat
    let offset: CGFloat
    let sliding: PlayBar.Skip?

    /// Between the cover and the words (the drawing's 12), between the title and its line (its 1), and past the words to
    /// Play/Pause (.mini's gap of 10) - the title's to tap.
    private static let gap: CGFloat = 12
    private static let lines: CGFloat = 1
    private static let end = CGFloat(PhoneLook.miniGap)
    /// A skip's slide.
    private static let slide = Animation.easeOut(duration: 0.22)

    var body: some View {
        let track = entry.track
        // the bar's height under its 1 pt top edge (.mini .cover's 59 of 60), flush left, the line's rule at its right
        let cover = row - 1
        HStack(spacing: Self.gap) {
            CoverImage(id: track.coverArt, size: cover)
                .frame(width: cover, height: cover)
                .clipped()
                .overlay(alignment: .trailing) { DWRule(colour: DWPalette.line, vertical: true) }
                .frame(maxHeight: .infinity, alignment: .bottom)
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: Self.lines) {
                    Text(track.title)
                        .font(Typeface.subheadline.weight(.semibold))
                        .foregroundStyle(DWPalette.text)
                        .lineLimit(1)
                    if let line, !line.isEmpty {
                        Text(line)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
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
        .padding(.trailing, Self.end)
        .contentShape(Rectangle())
        .onTapGesture { navigation.nowPlayingShown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayerWords.miniPlayerLabel(title: track.title, line: line))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { navigation.nowPlayingShown = true }
        .accessibilityActions {
            if player.hasSongAfter {
                Button(PlayerWords.nextSong) { player.next() }
            }
            if player.hasSongBefore {
                Button(PlayerWords.previousSong) { player.songBefore() }
            }
        }
    }

    /// How the words leave and come in: sliding the skip's way, or, under Reduce Motion, fading; at once otherwise.
    private var transition: AnyTransition {
        guard let sliding else { return .identity }
        if reduceMotion { return .opacity }
        switch sliding {
        case .next: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .before: return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }
}

/// The seek line along the play bar's top edge (James: "let's put the progress on top of the play bar"): at rest a 2 pt
/// line over the bar's top edge (since R4 .mini > .prog's: #2c2a36, the part played in the purple gradient across it);
/// under a seek's finger (MiniPlayerView's drag, `drag`) 8 pt thick, with the time under the finger over it ("1:23 /
/// 4:56"). (R1b's PhoneSeekLine draws the resting line alone; this one grows under the finger and draws its part played
/// every frame, so it keeps its own, in the same colours.) It is drawn only, taking no touch, so a tap at the
/// bar's top edge is the cover's, the title's or Play/Pause's, and the page above keeps its own. Every rule of the seek
/// is Now Playing's scrubber's (Scrub): it follows the finger and seeks once, where it is let go; a drag the system
/// takes away seeks nowhere; the song changing under it drops it; PlayerModel's `shownPosition` holds the seek's target
/// until the engine says it landed. A slider to VoiceOver, "Position in the song", "0:12 of 5:00", 10 s a swipe
/// (PlayBar.adjusted). A view of its own, so only it is drawn again as the position moves.
///
/// Smooth (James, 15 Nov: "Can we make the progress bar smooth instead of updating every half second?"): while the song
/// plays, the part played alone is drawn every frame, up to 30 a second (PlayClock.frame), from PlayerModel's
/// `barPosition(at:)` - the tick's reading carried on, the engine not asked. Paused, loading, under the finger, or
/// covered by Now Playing, its timeline stops and it shows `shownPosition`, as before; VoiceOver's value stays on
/// `shownPosition`.
private struct SeekLine: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.displayScale) private var displayScale

    /// The seek's finger, while there is one.
    let drag: Scrub.Drag?

    /// The line at rest, and under a finger.
    private static let rest: CGFloat = 2
    private static let held: CGFloat = 8
    /// The room the line is drawn in, centred on it (it takes no touch).
    private static let room: CGFloat = 16
    /// The time's gap above the held line, and its least room from the screen's sides.
    private static let lift: CGFloat = 6
    private static let side: CGFloat = 8

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        // VoiceOver's value, its swipes and the finger's time: the ticker's, never the frames'
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        let part = Self.part(shown, length: length)
        // no frames paused, loading, under the finger, or with Now Playing over the bar
        let runs = player.barsRun && held == nil && !navigation.nowPlayingShown
        GeometryReader { (band: GeometryProxy) in
            let width = band.size.width
            ZStack(alignment: .leading) {
                Color.clear
                ZStack(alignment: .leading) {
                    Rectangle().fill(DWPalette.seekTrack)
                    TimelineView(.animation(minimumInterval: PlayClock.frame, paused: !runs)) {
                        (_: TimelineViewDefaultContext) in
                        let position = player.barPosition(at: Monotonic.seconds())
                        let drawn = Scrub.shownTime(held, position: position, length: length)
                        Rectangle().fill(DWPalette.seekFill)
                            .frame(width: width * Self.part(drawn, length: length))
                    }
                }
                .frame(height: held == nil ? Self.rest : Self.held)
                .animation(.easeOut(duration: 0.15), value: held == nil)
            }
            .overlay(alignment: .topLeading) {
                if held != nil {
                    tag(PlayerWords.barTime(shown: shown, length: length), at: width * part, width: width)
                }
            }
        }
        .frame(height: Self.room)
        // centred on the line, whose top is the bar's top edge (.prog's top: -1px, over the bar's 1 pt edge)
        .offset(y: Self.rest / 2 - Self.room / 2)
        .allowsHitTesting(false)
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
    }

    /// The part of the line played: `seconds` of `length`, 0 to 1.
    private static func part(_ seconds: Double, length: Double) -> CGFloat {
        let done = PlayerWords.progress(position: seconds, duration: length)
        return CGFloat(done.isFinite ? min(max(done, 0), 1) : 0)
    }

    /// The time over the finger, above the held line, kept on the screen.
    private func tag(_ words: String, at x: CGFloat, width: CGFloat) -> some View {
        Text(words)
            .font(Typeface.Phone.mono(.extraSmall))
            .foregroundStyle(DWPalette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DWPalette.miniFace, in: DWCorners.chipShape)
            .overlay(DWCorners.chipShape.strokeBorder(DWPalette.line, lineWidth: 1 / max(displayScale, 1)))
            .fixedSize()
            .alignmentGuide(.leading) { (tag: ViewDimensions) -> CGFloat in
                -min(max(x - tag.width / 2, Self.side), max(width - tag.width - Self.side, Self.side))
            }
            .alignmentGuide(.top) { (tag: ViewDimensions) -> CGFloat in
                // its foot `lift` above the held line's top, which is (room - held) / 2 into the room drawn in
                tag.height + Self.lift - (Self.room - Self.held) / 2
            }
            .accessibilityHidden(true)
    }
}
