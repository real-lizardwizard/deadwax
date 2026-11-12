import DeadwaxCore
import SwiftUI

/// A song's lyrics in Now Playing's cover place (app 0.4, notes/app-lyrics.md 4.2-4.5) - the web's player/Lyrics.tsx
/// on the phone; its rules Core's (Lyrics, LyricsHold), its answer LyricsModel's. Made afresh for each song (Now
/// Playing puts `.id(song)` on it), so a new song starts at its top, unscrolled.
///
/// - THE LIT LINE is judged from PlayerModel.clock() - the engine's position as heard, a seek on its way its target - in
///   a TimelineView ten times a second while the clock runs (`Lyrics.clockRuns`: synced, playing, nothing over Now
///   Playing, the app active), and redrawn only when it or a break's dots change - the player read in LitClock's body
///   alone. Stopped, it is still redrawn on a seek: clock() reads the player's observed position and seek.
/// - FOLLOWING: the lit line scrolled to `Lyrics.anchor` of the view's height - a spring, or a jump for Reduce Motion.
///   The listener's own scroll holds it (a scroll phase of theirs, iOS 18; a drag on iOS 17), and so does VoiceOver's
///   focus on a line; `Lyrics.followAgainMs` after the last of them let go it comes back, while the song plays - paused,
///   it stays put until the song plays again. A change of size re-follows at once. Plain lyrics never follow: nothing
///   is lit, nothing moves on its own.
/// - A TAP ON A LINE plays from it - its seek, and Play when paused, straight from the tap - and follows it at once.
/// - VOICEOVER: each line one element - its words, its time ("1:23", the lit one "1:23, now"), "Plays from here.",
///   and on every line but the lit one the action "Go to the line being sung". The lyrics a container named "Lyrics".
///   Breaks and dots hidden. Nothing announced as lines change.
struct LyricsView: View {
    /// The song's answer - synced or plain, with lines.
    let lyrics: SongLyrics
    /// Up Next or Info is over Now Playing: the clock stands.
    let covered: Bool

    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    /// The lines as drawn: synced lyrics with their intro's break (Lyrics.withIntro), plain ones as they came.
    private let lines: [LyricLine]

    /// What is lit now: the lines and the lit break's dots.
    @State private var lit = Lit.unlit
    /// The listener's scroll and VoiceOver's focus, holding following.
    @State private var hold = LyricsHold()
    /// The view's height, for the room after the last line.
    @State private var height: CGFloat = 0
    /// The first follow (opening) is done: until then a new lit line is gone to at once, never scrolled to.
    @State private var placed = false
    /// The line VoiceOver is on.
    @AccessibilityFocusState private var focus: Int?

    /// The top of the lyrics, above the first line: where following goes before anything is lit.
    private static let top = -1

    init(lyrics: SongLyrics, covered: Bool) {
        self.lyrics = lyrics
        self.covered = covered
        lines = lyrics.synced ? Lyrics.withIntro(lyrics.lines) : lyrics.lines
    }

    private var synced: Bool { lyrics.synced && !lines.isEmpty }

    private var runs: Bool {
        synced && Lyrics.clockRuns(shows: true, playing: player.isPlaying, covered: covered, visible: scenePhase == .active)
    }

    private var dim: Color { Color.primary.opacity(Lyrics.lineDim(increased: contrast == .increased)) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // the room above the first line - the fade's, so it is never under the fade at the top
                    Color.clear
                        .frame(height: Lyrics.edge)
                        .id(Self.top)
                        .accessibilityHidden(true)
                    if !synced {
                        Text(LyricsWords.notSynced)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Lyrics.lineSpace / 2)
                    }
                    ForEach(lines.indices, id: \.self) { index in
                        row(index, proxy: proxy)
                            .id(index)
                    }
                    // the room after the last line, so it can reach the anchor too
                    Color.clear
                        .frame(height: Lyrics.endRoom(Double(height)))
                        .accessibilityHidden(true)
                }
                .animation(.easeOut(duration: 0.14), value: lit)
            }
            .modifier(ScrollHold { phase in
                hold.phase(phase, at: Self.nowMs())
            })
            .mask { fade }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                height = new
                // a change of size - Dynamic Type, the room the body leaves - re-follows at once
                if hold.follows(now: Self.nowMs(), playing: player.isPlaying) { follow(proxy, smooth: false) }
            }
            .background {
                TimelineView(.animation(minimumInterval: 0.1, paused: !runs)) { context in
                    LitClock(lines: lines, synced: synced, moment: context.date) { lit = $0 }
                }
                .accessibilityHidden(true)
            }
            .onAppear {
                // opened: the line being sung, and following at once - after the first layout, so it is there to go to
                hold = LyricsHold()
                lit = synced ? Lyrics.litAt(lines, at: player.clock()) : .unlit
                DispatchQueue.main.async {
                    follow(proxy, smooth: false)
                    placed = true
                }
            }
            .onChange(of: lit.range?.first) {
                // a new lit line, followed - unless the listener holds the lyrics
                guard hold.follows(now: Self.nowMs(), playing: player.isPlaying) else { return }
                hold.follow()
                follow(proxy, smooth: placed)
            }
            .onChange(of: lyrics) {
                // its answer come again, changed: following at once
                if hold.follows(now: Self.nowMs(), playing: player.isPlaying) { follow(proxy, smooth: false) }
            }
            .onChange(of: player.isPlaying) { _, playing in
                // a play after a hold that has run its time: following comes back at once (paused, it waited)
                guard playing, hold.heldAt != nil, hold.follows(now: Self.nowMs(), playing: true) else { return }
                hold.follow()
                follow(proxy, smooth: true)
            }
            .onChange(of: focus) { _, line in
                hold.focus(onLine: line != nil, at: Self.nowMs())
            }
            .task(id: hold) {
                // the wait after the last scroll or VoiceOver's leaving: following back once it has run, while playing
                guard let wait = hold.wait(now: Self.nowMs()) else { return }
                try? await Task.sleep(for: .milliseconds(Int(wait.rounded(.up))))
                guard !Task.isCancelled, hold.follows(now: Self.nowMs(), playing: player.isPlaying) else { return }
                hold.follow()
                follow(proxy, smooth: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LyricsWords.lyrics)
    }

    // MARK: the lines

    @ViewBuilder private func row(_ index: Int, proxy: ScrollViewProxy) -> some View {
        let line = lines[index]
        if !Lyrics.sung(line) {
            // a break between verses: clear, its three dots inside it while it is the lit line of a long gap - so their
            // coming moves nothing
            breakRow(index)
        } else if synced, let time = line.time {
            let isLit = lit.range?.contains(index) ?? false
            Button {
                playFrom(index, proxy: proxy)
            } label: {
                lineText(line.text, color: isLit ? Color.primary : dim)
            }
            .buttonStyle(.plain)
            .accessibilityValue(LyricsWords.lineValue(time, lit: isLit))
            .accessibilityHint(LyricsWords.lineHint)
            .accessibilityActions {
                if !isLit, lit.range != nil {
                    Button(LyricsWords.goToLit) { focus = lit.range?.first }
                }
            }
            .accessibilityFocused($focus, equals: index)
        } else {
            // plain: every line bright, nothing to tap
            lineText(line.text, color: Color.primary)
        }
    }

    private func lineText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.title, weight: .bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // the space between lines is each line's own, half either side: targets that abut, a gap never dead
            .padding(.vertical, Lyrics.lineSpace / 2)
            .contentShape(Rectangle())
    }

    private func breakRow(_ index: Int) -> some View {
        let dots = lit.range?.first == index ? lit.dots : 0
        return HStack(spacing: Lyrics.dot / 2) {
            if dots > 0 {
                ForEach(1...3, id: \.self) { dot in
                    Circle()
                        .fill(dots >= dot ? Color.primary : dim)
                        .frame(width: Lyrics.dot, height: Lyrics.dot)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Lyrics.breakHeight, maxHeight: Lyrics.breakHeight, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// The soft top and bottom edges - none with Reduce Transparency, as the system's own lists lose theirs.
    @ViewBuilder private var fade: some View {
        if reduceTransparency {
            Color.black
        } else {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Lyrics.edge)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Lyrics.edge)
            }
        }
    }

    // MARK: following and a tap

    /// The lit line to the anchor - the top, before anything is lit. Synced lyrics only.
    private func follow(_ proxy: ScrollViewProxy, smooth: Bool) {
        guard synced else { return }
        let target = lit.range?.first ?? Self.top
        let anchor = lit.range == nil ? UnitPoint.top : UnitPoint(x: 0, y: Lyrics.anchor)
        if smooth, !reduceMotion {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { proxy.scrollTo(target, anchor: anchor) }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { proxy.scrollTo(target, anchor: anchor) }
        }
    }

    /// A tap on a line: from there, playing - straight from the tap - and followed at once.
    private func playFrom(_ index: Int, proxy: ScrollViewProxy) {
        guard lines.indices.contains(index), let time = lines[index].time else { return }
        player.seek(to: time)
        if !player.isPlaying { player.toggle() }
        hold.follow()
        let was = lit.range?.first
        lit = Lyrics.litAt(lines, at: time)
        // a line newly lit is followed by the lit line's own change; the line already lit, here
        if lit.range?.first == was { follow(proxy, smooth: true) }
    }

    /// Milliseconds on a clock that only goes forward - the hold's.
    private static func nowMs() -> Double { Monotonic.seconds() * 1000 }
}

/// The clock: the lines lit as the player says now, handed up when they change - and the next song's ask as the
/// position moves (LyricsModel.ahead, 2.6). The player is read in THIS body, never the lyrics': it is read again at each
/// of the timeline's moments while the clock runs (`moment`, new each time), and - the clock stopped - whenever what it
/// reads of the player changes (its position, a seek on its way), so a seek while paused still lights its line. The
/// lyrics' own body is drawn again only when what is lit changes - not at every half-second tick of the position, as
/// an `onChange(of: player.position)` there would have it.
private struct LitClock: View {
    let lines: [LyricLine]
    let synced: Bool
    /// The timeline's moment: a new one each time it draws, so this body is read again.
    let moment: Date
    let changed: (Lit) -> Void

    @Environment(PlayerModel.self) private var player
    @Environment(LyricsModel.self) private var model

    var body: some View {
        let now = synced ? Lyrics.litAt(lines, at: player.clock()) : Lit.unlit
        Color.clear
            .onAppear { changed(now) }
            .onChange(of: now) { _, new in changed(new) }
            .onChange(of: player.position) { model.ahead() }
    }
}

/// The listener's own scroll, as a phase: SwiftUI's scroll phases on iOS 18; on iOS 17 a drag stands in - moving holds,
/// lifted (or taken over by the scroll view: a GestureState resets on both, where onEnded misses a cancel) starts the
/// wait. (Not the drag on iOS 18 too: there a simultaneous drag can keep the scroll view from scrolling.)
private struct ScrollHold: ViewModifier {
    let changed: (LyricsHold.Phase) -> Void
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in changed(LyricsHold.Phase(phase)) }
        } else {
            content
                .simultaneousGesture(DragGesture(minimumDistance: 10).updating($dragging) { _, state, _ in state = true })
                .onChange(of: dragging) { _, now in changed(now ? .interacting : .idle) }
        }
    }
}

@available(iOS 18.0, *)
private extension LyricsHold.Phase {
    init(_ phase: ScrollPhase) {
        switch phase {
        case .idle: self = .idle
        case .tracking: self = .tracking
        case .interacting: self = .interacting
        case .decelerating: self = .decelerating
        case .animating: self = .animating
        @unknown default: self = .idle
        }
    }
}
