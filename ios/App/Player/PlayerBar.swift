import DeadwaxCore
import SwiftUI

/// The player bar (the Mac app, slice 3; redrawn in the Mac and iPhone redesign's slice R4 - notes/ios.md "The redesign,
/// slice R4: the player bar, the mini player and the tab bar"): along the desktop frame's foot, under the sidebar, the
/// page and the side panel alike, as dw.css's .player draws it - 66 tall (MacLook.barHeight) on its own face, its edge
/// along the top. Left to right, 14 apart and 14 in from either end:
///
/// - **The keys** (.keys, 11 apart): Shuffle and Repeat as toggles (DWToggleStyle, lit while on - Shuffle dimmed during a
///   library's shuffle, whose order is the shuffle), Previous and Next as round keys (MacKeyStyle), Play/Pause the big
///   purple one, busy while the song loads. Each is PlayerModel's own call, made in the click - Now Playing's buttons'.
/// - **The display** (.lcd, MacDisplay): the bar's whole height, the cover flush at its left (a click opens it full size,
///   the cover viewer, as Now Playing's cover does - Now Playing never opens on the Mac), then three lines - the title
///   and "Next" with the song that then plays (BarDisplay.next); "Artist — Album" (a button to the album's page when the
///   song names one, PlayedAlbum.route - a player failure in its place) and the readout, "3 of 11 · FLAC 16/44.1"
///   (BarDisplay.readout); the clocks either side of the scrubber (BarScrubber). Narrow, each line gives way on its own
///   (a ViewThatFits of its own): the first drops Next when it doesn't fit, the second the readout - which goes first
///   depends on the words - and every line truncates with its full words in its tooltip and VoiceOver.
/// - **The tools** (.tools, 6 apart): Queue, Lyrics and Info as one joined strip (MacStripButtonStyle), then a groove, the
///   EQ, where the music plays (MacOutput: AirPlay's own button and the output's name - the name left out in a window
///   under 1000 wide, so the display keeps room for its lines, its tooltip kept) and the •••. Each of the four
///   opens its tab of the side panel (MacDock) or closes it (AppNavigation.togglePanel), lit while its tab shows; the
///   •••'s Info and EQ show theirs (R3), Add to a playlist… opens the picker (AppNavigation.playlistPick, the frame's
///   sheet), Go to album the album's page.
///
/// Nothing queued: the keys there and dimmed, "Nothing playing" in the display - the bar never comes and goes - and the
/// tools still open their tabs. Space plays and pauses from the Controls menu (MacCommands: never while typing). No
/// volume (the system's is the Mac's), and nothing of the engine's: every action is a call the player's buttons already
/// make.
struct PlayerBar: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(LyricsModel.self) private var lyrics
    @Environment(Reachability.self) private var reachability

    /// The cover full size, from a click on the display's cover.
    @State private var viewing: ViewedCover?
    /// The bar's width, which is the window's: narrower than `namedFrom`, the output's name gives way to the display.
    @State private var width: CGFloat = 0

    // dw.css's .player and its parts, in points
    private static let gap: CGFloat = 14           // dw: .player gap
    private static let pad: CGFloat = 14           // dw: .player padding
    private static let keysGap: CGFloat = 11       // dw: .keys gap
    private static let toolsGap: CGFloat = 6       // dw: .tools gap
    private static let keyGlyph: CGFloat = 15      // dw: .key svg width
    private static let playGlyph: CGFloat = 22     // dw: .key.big svg width
    private static let playNudge: CGFloat = 2      // dw: .key.big svg margin-left
    private static let toggleGlyph: CGFloat = 16   // dw: .tog svg width
    private static let lineGap: CGFloat = 4        // dw: .lcd > .col gap
    private static let rowGap: CGFloat = 10        // the drawing's first two lines' gap
    private static let lcdGap: CGFloat = 14        // dw: .lcd gap
    private static let lcdEnd: CGFloat = 16        // dw: .lcd padding-right
    /// The display's cover: the bar's height under its 1 pt edge (.lcd > .cover's 65, flush).
    private static let cover = CGFloat(MacLook.barHeight) - 1
    /// The ••• menu's square, how wide the output (its button and name) may grow before the name truncates, and the
    /// bar's least width that draws the name at all (below it, from the smallest window's 880, the name's room is the
    /// display's - its tooltip kept).
    private static let more: CGFloat = 32
    private static let outputMost: CGFloat = 150
    private static let namedFrom: CGFloat = 1000
    /// How wide Next's song may grow beside the title, and how little of the byline keeps the readout beside it.
    private static let nextMost: CGFloat = 160
    private static let bylineLeast: CGFloat = 80

    var body: some View {
        HStack(spacing: Self.gap) {
            keys
            MacDisplay {
                if let entry = player.current {
                    display(entry.track)
                } else {
                    Text(LyricsWords.nothingPlaying)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            tools
                .fixedSize()
        }
        .padding(.horizontal, Self.pad)
        .frame(height: CGFloat(MacLook.barHeight) - 1)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { (bar: GeometryProxy) -> CGFloat in
            bar.size.width
        } action: { (now: CGFloat) -> Void in
            width = now
        }
        .background(alignment: .top) { DWRule(colour: MacPalette.playerSheen) }
        .padding(.top, 1)
        .background(MacPalette.playerFace)
        .overlay(alignment: .top) { DWRule(colour: MacPalette.playerEdge) }
        .coverViewer($viewing, onDismiss: {})
        .accessibilityElement(children: .contain)
    }

    // MARK: the keys

    private var keys: some View {
        let queued = player.hasQueue
        let paged = player.paged != nil
        let mode = player.repeatMode
        return HStack(spacing: Self.keysGap) {
            Button {
                if !paged { player.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .font(Typeface.symbol(size: Self.toggleGlyph, weight: .medium))
            }
            .buttonStyle(DWToggleStyle(on: player.shuffle))
            .disabled(paged)
            .opacity(paged ? DWPalette.off : 1)
            .accessibilityLabel(shuffleLabel(player.paged?.scope))
            .help(shuffleLabel(player.paged?.scope))
            Button {
                player.previous()
            } label: {
                SharpSymbol(.previous)
                    .font(Typeface.symbol(size: Self.keyGlyph))
            }
            .buttonStyle(MacKeyStyle())
            .accessibilityLabel(NowPlayingWords.previous)
            .help(NowPlayingWords.previous)
            Button {
                player.toggle()
            } label: {
                ZStack {
                    PlayPauseGlyph(playing: player.isPlaying)
                        .font(Typeface.symbol(size: Self.playGlyph))
                        .padding(.leading, Self.playNudge)
                        .opacity(player.isLoading ? DWPalette.off : 1)
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(MacPalette.bigKeyText)
                    }
                }
            }
            .buttonStyle(MacKeyStyle(big: true))
            .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
            .help(PlayerWords.playPause(playing: player.isPlaying))
            Button {
                player.next()
            } label: {
                SharpSymbol(.next)
                    .font(Typeface.symbol(size: Self.keyGlyph))
            }
            .buttonStyle(MacKeyStyle())
            .accessibilityLabel(PlayerWords.next)
            .help(PlayerWords.next)
            Button {
                player.setRepeat(nextRepeat(mode))
            } label: {
                Image(systemName: mode == .one ? "repeat.1" : "repeat")
                    .font(Typeface.symbol(size: Self.toggleGlyph, weight: .medium))
            }
            .buttonStyle(DWToggleStyle(on: mode != .off))
            .accessibilityLabel(repeatLabel(mode))
            .help(repeatLabel(mode))
        }
        .disabled(!queued)
        .opacity(queued ? 1 : DWPalette.off)
        .fixedSize()
    }

    // MARK: the display

    private func display(_ track: QueueTrack) -> some View {
        let next = BarDisplay.next(player.queue, repeat: player.repeatMode)
        let readout = BarDisplay.readout(player.queue)
        return HStack(spacing: Self.lcdGap) {
            CoverImage(id: track.coverArt, size: Self.cover)
                .frame(width: Self.cover, height: Self.cover)
                .clipped()
                .overlay(alignment: .trailing) { DWRule(colour: DWPalette.line, vertical: true) }
                .opensCoverFullScreen(track, into: $viewing)
            VStack(alignment: .leading, spacing: Self.lineGap) {
                ViewThatFits(in: .horizontal) {
                    titleLine(track, next: next)
                    titleLine(track, next: nil)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(track.title)
                .accessibilityValue(next.map { BarDisplay.Words.nextSpoken($0.title) } ?? "")
                ViewThatFits(in: .horizontal) {
                    // on the byline's baseline (25 Nov): centred, the readout's shorter line would sit it higher
                    HStack(alignment: .firstTextBaseline, spacing: Self.rowGap) {
                        byline(track)
                            .frame(minWidth: 0, idealWidth: Self.bylineLeast, maxWidth: .infinity, alignment: .leading)
                        if let readout {
                            Text(readout)
                                .font(Typeface.Mac.mono(.label))
                                .foregroundStyle(DWPalette.t3)
                                .lineLimit(1)
                                .fixedSize()
                                .accessibilityLabel(BarDisplay.readoutSpoken(player.queue) ?? readout)
                        }
                    }
                    byline(track)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                BarScrubber()
            }
            .padding(.trailing, Self.lcdEnd)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The first line: the title, and with room for it, "Next" and the song that then plays.
    private func titleLine(_ track: QueueTrack, next: QueueTrack?) -> some View {
        HStack(spacing: Self.rowGap) {
            Text(track.title)
                .font(Typeface.Mac.text(.lcd).weight(.semibold))
                .foregroundStyle(DWPalette.text)
                .lineLimit(1)
                .help(track.title)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let next {
                Text(BarDisplay.Words.next)
                    .font(Typeface.Mac.text(.label))
                    .foregroundStyle(DWPalette.t3)
                    .lineLimit(1)
                    .fixedSize()
                Text(next.title)
                    .font(Typeface.Mac.text(.label))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .frame(maxWidth: Self.nextMost, alignment: .leading)
                    .help(next.title)
            }
        }
    }

    /// "Artist — Album": the album's page from a click, when the song names one; a player failure in its place.
    @ViewBuilder private func byline(_ track: QueueTrack) -> some View {
        let words = PlayerWords.byline(artist: track.artist, album: track.album)
        if let error = player.errorLine, !error.isEmpty {
            bylineText(error)
        } else if let route = PlayedAlbum.route(track, player: player) {
            Button {
                navigation.openAlbum(route)
            } label: {
                bylineText(words)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlayerWords.goToAlbum(words))
        } else {
            bylineText(words)
        }
    }

    private func bylineText(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.small))
            .foregroundStyle(DWPalette.t2)
            .lineLimit(1)
            .help(words)
    }

    // MARK: the tools

    private var tools: some View {
        let shown = navigation.macPanel
        let lyricsOn = shown == .lyrics
        let dimmed = Lyrics.dimmed(lyrics.have, on: lyricsOn)
        return HStack(spacing: Self.toolsGap) {
            HStack(spacing: -1) {
                Button(MacDock.Words.tab(.upNext)) {
                    navigation.togglePanel(.upNext)
                }
                .buttonStyle(MacStripButtonStyle(place: .first, on: shown == .upNext))
                .zIndex(shown == .upNext ? 1 : 0)
                .accessibilityLabel(upNextLabel(shuffle: player.shuffle, repeat: player.repeatMode))
                .accessibilityAddTraits(shown == .upNext ? .isSelected : [])
                Button(MacDock.Words.tab(.lyrics)) {
                    navigation.togglePanel(.lyrics)
                }
                .buttonStyle(MacStripButtonStyle(place: .middle, on: lyricsOn))
                .zIndex(lyricsOn ? 1 : 0)
                .disabled(dimmed)
                .accessibilityLabel(LyricsWords.label(lyrics.have, device: Platform.device))
                .accessibilityAddTraits(lyricsOn ? .isSelected : [])
                .help(LyricsWords.label(lyrics.have, device: Platform.device))
                Button(MacDock.Words.tab(.info)) {
                    navigation.togglePanel(.info)
                }
                .buttonStyle(MacStripButtonStyle(place: .last, on: shown == .info))
                .zIndex(shown == .info ? 1 : 0)
                .accessibilityAddTraits(shown == .info ? .isSelected : [])
            }
            MacGroove()
            BarEQButton(on: shown == .eq) {
                navigation.togglePanel(.eq)
            }
            // not yet measured (0): named, as a window opens at 1280
            MacOutput(named: width == 0 || width >= Self.namedFrom)
                .frame(maxWidth: Self.outputMost)
            if let entry = player.current {
                more(entry.track)
            }
        }
    }

    /// The •••: Info, Add to a playlist…, the downloads, the EQ, Go to album.
    private func more(_ track: QueueTrack) -> some View {
        let route = PlayedAlbum.route(track, player: player)
        return NowPlayingMenu(hasAlbum: route != nil, saysSpeed: player.speed != PlaySpeed.normal,
                              onInfo: { if navigation.macPanel != .info { navigation.togglePanel(.info) } },
                              // (R3) the side panel's EQ tab, whatever was showing - a shared file's EQ stays the
                              // frame's one sheet (DesktopFrame), the tab's page covered under it (EQScreen.onTop)
                              onEQ: { navigation.showPanel(.eq) },
                              onPlaylist: reachability.online ? {
                                  navigation.playlistPick = PlaylistPickRequest(PlaylistPick(playing: track))
                              } : nil) {
            if let route { navigation.openAlbum(route) }
        }
        .foregroundStyle(DWPalette.t2)
        .frame(width: Self.more, height: Self.more)
    }
}

/// The bar's EQ: opens the side panel's EQ tab, or closes it, lit while it shows - named to VoiceOver with the setting
/// playing ("EQ, Bass Boost"). A view of its own, so only it redraws as the EQ moves.
private struct BarEQButton: View {
    let on: Bool
    let action: () -> Void
    @Environment(EQModel.self) private var eq

    var body: some View {
        Button(MacDock.Words.tab(.eq), action: action)
            .buttonStyle(DWButtonStyle(kind: on ? .on : .normal))
            .accessibilityLabel(NowPlayingTabs.Words.eq(setting: eq.now.short))
            .help(NowPlayingTabs.Words.eq(setting: eq.now.short))
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The bar's scrubber (the drawing's third line: the elapsed clock, .meter, the time left, 8 apart) - every rule Now
/// Playing's scrubber's (Scrub): a click seeks where it lands, a drag follows the pointer and seeks where it is let go,
/// the song changing under it drops it, and PlayerModel's `shownPosition` holds a seek's target until the engine says it
/// landed. A slider to VoiceOver, 5 s a step. Drawn from the ticker, twice a second at most - no frames of its own (the
/// bar is small, and the clocks move a second at a time). Its track is .meter's - the well, its line, the shade inside
/// its top, the grey fill inside the line - 6 tall, 8 while held; the room a pointer takes is the line's whole height.
private struct BarScrubber: View {
    @Environment(PlayerModel.self) private var player
    @State private var drag: Scrub.Drag?
    @State private var pressed = false
    @GestureState private var touching = false

    private static let gap: CGFloat = 8        // the drawing's third line's gap
    private static let held: CGFloat = 8       // the track while held: 2 taller than .meter's 6
    private static let room: CGFloat = 16      // the line's height, which the pointer takes

    var body: some View {
        let track = player.current?.track.id ?? ""
        let length = player.duration
        let held = Scrub.dragFor(drag, track: track)
        let shown = Scrub.shownTime(held, position: player.shownPosition, length: length)
        HStack(spacing: Self.gap) {
            Text(PlayerWords.elapsed(shown: shown))
            GeometryReader { (bar: GeometryProxy) in
                let width = bar.size.width
                DWCorners.meterShape
                    .fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1)))
                    .overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: 1) }
                    .overlay(alignment: .leading) {
                        DWCorners.meterFillShape
                            .fill(DWPalette.meterFill)
                            .frame(width: max(width - 2, 0) * Self.part(shown, length: length))
                            .padding(1)
                    }
                    .frame(height: held == nil ? CGFloat(DWLook.here.meterHeight) : Self.held)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(press(track: track, width: width, length: length))
            }
            .frame(height: Self.room)
            Text(PlayerWords.remaining(shown: shown, length: length))
        }
        .font(Typeface.Mac.mono(.label))
        .foregroundStyle(DWPalette.t2)
        .lineLimit(1)
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
