import DeadwaxCore
import SwiftUI

/// The player bar (the Mac app, slice 3 - the Mac app's plan 1.2; the web's .app-playbar, app-desktop.css): along the
/// desktop frame's foot, under the sidebar, the page and a panel's column alike, MacFrame.barHeight (72) tall. Three
/// columns, as the web's grid: the song (MacFrame.barSide wide - 240, 320 from a 1280 window), the transport over the
/// scrubber in the middle, and the tools (the same width).
///
/// - The song: its cover, the title, and "Artist — Album" (PlayerWords.byline) - a button to the album's page when the
///   song names one (PlayedAlbum.route), the words in the quiet colour. A click on the cover opens it full size (the
///   cover viewer, as Now Playing's cover does - Now Playing never opens on the Mac, MacFrame.opensNowPlaying). A
///   player failure (a skipped song's words included) takes the byline's place.
/// - The transport: Shuffle, Previous, Play/Pause (busy while the song loads), Next, Repeat - each PlayerModel's own
///   call from the click, as Now Playing's buttons make them; Shuffle dimmed during a library's shuffle (its order is
///   the shuffle). Under it the scrubber, a clock at each end (BarScrubber).
/// - The tools: Lyrics, Up Next, AirPlay and the •••. Lyrics and Up Next open their side panel, or close it (one panel at
///   a time, AppNavigation.togglePanel), lit while theirs shows; the •••'s Info opens Info's. Its EQ opens the EQ as a
///   sheet - the frame's own, a shared file's too (AppNavigation.eqImportSheet); Add to a playlist… the picker
///   (AppNavigation.playlistPick, the frame's sheet); Go to album the album's page.
///
/// Nothing queued: "Nothing playing" across the bar, in the place the song would be - the bar never comes and goes.
/// No volume (the system's is the Mac's), and nothing of the engine's: every action is a call the player's buttons
/// already make.
struct PlayerBar: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(LyricsModel.self) private var lyrics
    @Environment(Reachability.self) private var reachability
    @Environment(\.displayScale) private var displayScale

    /// The bar's width, for its sides' (MacFrame.barSide - the window's, as the bar is the window's width).
    @State private var width: Double = MacFrame.openingWidth
    /// The cover full size, from a click on the bar's cover.
    @State private var viewing: ViewedCover?

    var body: some View {
        let side = CGFloat(MacFrame.barSide(width: width))
        Group {
            if let entry = player.current {
                HStack(spacing: CGFloat(MacFrame.barGap)) {
                    song(entry.track)
                        .frame(width: side, alignment: .leading)
                    middle
                        .frame(maxWidth: .infinity)
                    tools(entry.track)
                        .frame(width: side, alignment: .trailing)
                }
            } else {
                Text(LyricsWords.nothingPlaying)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, CGFloat(MacFrame.barPad))
        .frame(height: CGFloat(MacFrame.barHeight))
        .frame(maxWidth: .infinity)
        .background(Palette.playerBar)
        .overlay(alignment: .top) {
            Palette.frameBorder
                .frame(height: 1 / max(displayScale, 1))
                .accessibilityHidden(true)
        }
        .onGeometryChange(for: Double.self) { (bar: GeometryProxy) -> Double in
            Double(bar.size.width)
        } action: { (now: Double) -> Void in
            width = now
        }
        .coverViewer($viewing, onDismiss: {})
        .accessibilityElement(children: .contain)
    }

    // MARK: the song

    private func song(_ track: QueueTrack) -> some View {
        let cover = CGFloat(MacFrame.barCover)
        return HStack(spacing: 12) {
            CoverImage(id: track.coverArt, size: cover)
                .frame(width: cover, height: cover)
                .clipShape(Corners.artShape)
                .opensCoverFullScreen(track, into: $viewing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(Typeface.body.weight(.medium))
                    .lineLimit(1)
                byline(track)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Artist — Album": the album's page from a click, when the song names one; a player failure in its place.
    @ViewBuilder private func byline(_ track: QueueTrack) -> some View {
        let words = PlayerWords.byline(artist: track.artist, album: track.album)
        if let error = player.errorLine, !error.isEmpty {
            Text(error)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
        } else if let route = PlayedAlbum.route(track, player: player) {
            Button {
                navigation.openAlbum(route)
            } label: {
                Text(words)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlayerWords.goToAlbum(words))
        } else {
            Text(words)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
        }
    }

    // MARK: the transport and the scrubber

    private var middle: some View {
        VStack(spacing: 6) {
            transport
            BarScrubber()
                .frame(maxWidth: 520)
        }
    }

    private var transport: some View {
        let paged = player.paged != nil
        let mode = player.repeatMode
        return HStack(spacing: 22) {
            BarModeButton(glyph: "shuffle", on: player.shuffle, label: shuffleLabel(player.paged?.scope),
                          enabled: !paged) {
                if !paged { player.toggleShuffle() }
            }
            Button {
                player.previous()
            } label: {
                SharpSymbol(.previous).font(Typeface.symbol(.title3))
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NowPlayingWords.previous)
            Button {
                player.toggle()
            } label: {
                ZStack {
                    PlayPauseGlyph(playing: player.isPlaying)
                        .font(Typeface.symbol(.title2))
                        .opacity(player.isLoading ? 0.35 : 1)
                    if player.isLoading { ProgressView().controlSize(.small) }
                }
                .frame(minWidth: 34, minHeight: 34)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
            Button {
                player.next()
            } label: {
                SharpSymbol(.next).font(Typeface.symbol(.title3))
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(PlayerWords.next)
            BarModeButton(glyph: mode == .one ? "repeat.1" : "repeat", on: mode != .off, label: repeatLabel(mode)) {
                player.setRepeat(nextRepeat(mode))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: the tools

    private func tools(_ track: QueueTrack) -> some View {
        let route = PlayedAlbum.route(track, player: player)
        let panel = navigation.macPanel
        let lyricsOn = panel == .lyrics
        let dimmed = Lyrics.dimmed(lyrics.have, on: lyricsOn)
        return HStack(spacing: 6) {
            Button {
                navigation.togglePanel(.lyrics)
            } label: {
                Image(systemName: lyricsOn ? "quote.bubble.fill" : "quote.bubble")
                    .font(Typeface.symbol(.body))
                    .foregroundStyle(lyricsOn ? Palette.accent : Palette.quiet)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(dimmed)
            .opacity(dimmed ? Palette.off : 1)
            .accessibilityLabel(LyricsWords.label(lyrics.have))
            .accessibilityAddTraits(lyricsOn ? .isSelected : [])
            Button {
                navigation.togglePanel(.upNext)
            } label: {
                Image(systemName: "list.bullet")
                    .font(Typeface.symbol(.body))
                    .foregroundStyle(panel == .upNext ? Palette.accent : Palette.quiet)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(upNextLabel(shuffle: player.shuffle, repeat: player.repeatMode))
            .accessibilityAddTraits(panel == .upNext ? .isSelected : [])
            AirPlayButton()
                .frame(width: 32, height: 32)
            NowPlayingMenu(hasAlbum: route != nil, saysSpeed: player.speed != PlaySpeed.normal,
                           onInfo: { if navigation.macPanel != .info { navigation.togglePanel(.info) } },
                           // (slice 3's review) the frame's one EQ sheet, a shared file's too (DesktopFrame) - never a
                           // second over it, and an EQ page on Settings' stack knows it's covered (EQScreen.onTop)
                           onEQ: { navigation.eqImportSheet = true },
                           onPlaylist: reachability.online ? {
                               navigation.playlistPick = PlaylistPickRequest(PlaylistPick(playing: track))
                           } : nil) {
                if let route { navigation.openAlbum(route) }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}

/// Shuffle and Repeat in the bar: tinted the accent while on (VoiceOver's "selected"), and Shuffle, during a library's
/// shuffle, on and dimmed - as Now Playing's.
private struct BarModeButton: View {
    let glyph: String
    let on: Bool
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(Typeface.symbol(.body).weight(.semibold))
                .foregroundStyle(on ? Palette.accent : Palette.quiet)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The bar's scrubber (the web's .app-playbar .pl-scrubber): one row, the elapsed clock, a thin bar, the time left -
/// every rule Now Playing's scrubber's (Scrub): a click seeks where it lands, a drag follows the pointer and seeks
/// where it is let go, the song changing under it drops it, and PlayerModel's `shownPosition` holds a seek's target
/// until the engine says it landed. A slider to VoiceOver, 5 s a step. Drawn from the ticker, twice a second at most -
/// no frames of its own (the bar is small, and the clocks move a second at a time).
private struct BarScrubber: View {
    @Environment(PlayerModel.self) private var player
    @State private var drag: Scrub.Drag?
    @State private var pressed = false
    @GestureState private var touching = false

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        HStack(spacing: 10) {
            Text(PlayerWords.elapsed(shown: shown))
            GeometryReader { (bar: GeometryProxy) in
                let width = bar.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.border)
                    Rectangle().fill(Color.primary.opacity(0.85))
                        .frame(width: width * Self.part(shown, length: length))
                }
                .frame(height: held == nil ? 6 : 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(press(track: track, width: width, length: length))
            }
            .frame(height: 16)
            Text(PlayerWords.remaining(shown: shown, length: length))
        }
        .font(Typeface.caption.monospacedDigit())
        .foregroundStyle(Palette.quiet)
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
            if let target = Scrub.adjusted(increment: increment, from: shown, length: length) { player.seek(to: target) }
        }
        .onChange(of: track) { (_: String, now: String) -> Void in drag = Scrub.dragFor(drag, track: now) }
        .onChange(of: touching) { (_: Bool, live: Bool) -> Void in
            //? the gesture went without an end of its own: a cancel seeks nowhere
            guard !live, pressed else { return }
            pressed = false
            drag = Scrub.dragEnd(drag, pointer: 0, how: .cancel).drag
        }
    }

    /// The played part of the bar, 0...1 (none for no length).
    private static func part(_ shown: Double, length: Double) -> CGFloat {
        guard length > 0 else { return 0 }
        let done = min(max(shown / length, 0), 1)
        return done.isFinite ? CGFloat(done) : 0
    }

    private func press(track: String, width: CGFloat, length: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { (_: DragGesture.Value, live: inout Bool, _: inout Transaction) -> Void in live = true }
            .onChanged { (value: DragGesture.Value) -> Void in
                let time = Scrub.timeAt(x: value.location.x, left: 0, width: width, length: length)
                if !pressed {
                    pressed = true
                    //? no length yet: the bar is no target
                    if length > 0 { drag = Scrub.dragStart(pointer: 0, track: track, time: time) }
                } else {
                    drag = Scrub.dragMove(drag, pointer: 0, time: time)
                }
            }
            .onEnded { (_: DragGesture.Value) -> Void in
                pressed = false
                let (next, seek) = Scrub.dragEnd(drag, pointer: 0, how: .up)
                drag = next
                if let seek { player.seek(to: seek) }
            }
    }
}
