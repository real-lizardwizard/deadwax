import DeadwaxCore
import SwiftUI

/// Now Playing, over the tabs (ui/src/player/NowPlaying.tsx, a phone's): the cover over its own blur, smaller while
/// paused; a failure's words ABOVE the title (a line that comes and goes moves the cover, never what a finger is
/// reaching for); the title and "Artist — Album", which goes to the album; the scrubber; the transport - Shuffle,
/// Previous, Play/Pause, Next, Repeat (2.0.14) - and a footer of Lyrics, AirPlay, Up Next and ••• (Apple Music's
/// order, app 0.4). It closes from the chevron or a drag down its top half past PlayerWords.dismissDistance, begun past
/// dragStartDistance - the cover and the row above it are the grip, the bar and the buttons below keep their own
/// gestures.
///
/// LYRICS (app 0.4, notes/app-lyrics.md 4.1-4.3): with Lyrics on, the song's lyrics take the cover's place - the cover
/// and the room around it - and the chevron's row alone is the grip, so scrolling them never drags the sheet; the title,
/// the scrubber, the transport and the footer stay where they are. A song with none (or none kept on this phone,
/// offline) shows the cover, the button still lit. The backdrop darkens under them so the dim lines read over the
/// brightest cover.
///
/// THE TURNTABLE (app 0.6, notes/ios-specs/turntable.md 2.1): the look button at the top row's right switches between
/// the cover and the turntable for as long as Now Playing stays open - it opens as You > Playback says, every time, and
/// the button never changes that. On the turntable the plinth takes the cover's room (TurntableView), the title and
/// the album line are centred, the time line takes the scrubber's place in the scrubber's own row (so nothing below
/// moves), a failure's line or the silent record's is laid over the plinth's foot, and the grip is the top row alone -
/// the record and the arm are outside it. The swap is a 0.2 s crossfade, none under Reduce Motion. The deck itself is
/// DeckController's, which outlives this view (a coast still hands the song back after a close); the transport's
/// Play/Pause on the turntable is the deck's (a pause winds the record down), and its three buttons are gestures the
/// record's sound may start from. Lyrics on show over neither look, as the web's: the look button gives way to them.
///
/// THE SPEED (app 0.7, notes/ios-specs/turntable.md 5.1): on the turntable the fader and its readout say it - the
/// readout laid over this column at the plinth's corner, above the foot line (TurntableReadoutLayer). On the cover,
/// off 1x, a chip - `1.25x`, a tap back to 1x - laid over the gap between AirPlay and Up Next, so nothing in the footer
/// moves as it comes and goes; at the accessibility sizes, where it wouldn't fit, the ••• menu says it instead
/// ("Speed 1.25x - back to normal speed"). The mini player doesn't show it.
///
/// Every action is PlayerModel's, called straight from the tap. Shuffle and Repeat are named in Up Next's words
/// (shuffleLabel, repeatLabel), pressed while on, tinted while on; a library's shuffle can't be turned off, so its
/// Shuffle stays on and does nothing. The Up Next button names what is on (upNextLabel) and is never tinted.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(LyricsModel.self) private var lyrics
    @Environment(DeckController.self) private var deck
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsUpNext = false
    @State private var showsInfo = false
    /// The EQ over Now Playing (eq.md 3.1), from the •••: its own stack, "Done" at its top right.
    @State private var showsEQ = false
    /// A shared file's EQ sheet waits for Up Next or Info to close (eq.md 3.9).
    @State private var eqWaits = false
    /// How far the sheet has been dragged down (points).
    @State private var dragY: CGFloat = 0
    /// The look the button switched to while this stays open; nil: as You > Playback says (the web's, reset as it opens).
    @State private var switched: TurntableSettings.Look?
    /// Add to a playlist, from the •••: the picker over Now Playing, with the song playing (Phase 4, slice 2).
    @State private var playlistPick: PlaylistPickRequest?
    @Environment(Reachability.self) private var reachability

    /// The cover's scale while paused (--pl-paused-scale).
    private static let pausedScale: CGFloat = 0.82

    init() {}

    /// Lyrics take the cover's place: on, and the song has some (or they are on their way, or failed).
    private var lyricsShown: Bool { Lyrics.shows(lyrics.have, on: lyrics.showing) }

    /// The look showing, the button's or You's.
    private var look: TurntableSettings.Look { switched ?? deck.opensAs }

    /// The turntable shows: its look, with the lyrics off (NowPlaying.tsx:269).
    private var turntable: Bool { TurntableSettings.showsTurntable(look, lyricsOn: lyrics.showing) }

    /// The look's swap: a crossfade, none under Reduce Motion (2.1, 2.12).
    private var swap: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }

    /// The speed isn't the song's own: the chip on the cover, or the menu's line where it isn't drawn (5.1).
    private var offSpeed: Bool { player.speed != PlaySpeed.normal }

    /// The chip shows: on the cover (the readout says it on the turntable), off 1x, short of the accessibility sizes.
    private var chipShown: Bool { !turntable && offSpeed && !dynamicTypeSize.isAccessibilitySize }

    /// The ••• menu says the speed: where the chip would, at the accessibility sizes.
    private var menuSaysSpeed: Bool { !turntable && offSpeed && dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let entry = player.current {
                Backdrop(cover: entry.track.coverArt,
                         dim: Lyrics.backdropDim(lyrics: lyricsShown, increased: contrast == .increased))
                content(entry.track)
            }
        }
        .offset(y: dragY)
        .sheet(isPresented: $showsUpNext, onDismiss: eqAfterSheet) { UpNextScreen() }
        .sheet(isPresented: $showsInfo, onDismiss: eqAfterSheet) { InfoView() }
        .sheet(isPresented: $showsEQ) { EQSheet() }
        .sheet(item: $playlistPick) { (request: PlaylistPickRequest) in PlaylistPicker(request: request) }
        .onAppear { lyrics.opened() }
        // the deck told what shows as it opens and as the look changes - and that it doesn't, as it closes (2.1)
        .onChange(of: turntable, initial: true) { (_: Bool, now: Bool) -> Void in deck.screen(turntable: now) }
        .onDisappear { deck.closed() }
        .onChange(of: navigation.eqImport?.id, initial: true) { (_: UUID?, _: UUID?) -> Void in shared() }
    }

    /// A file shared to deadwax while Now Playing is up (eq.md 3.9): the EQ sheet opens, the preview over it - over the
    /// EQ sheet already up, the preview shows in it as it stands; Up Next or Info is closed first.
    private func shared() {
        guard navigation.eqImport != nil, navigation.eqImportPage == nil, !navigation.eqPreviewUp, !showsEQ else { return }
        if showsUpNext || showsInfo {
            eqWaits = true
            showsUpNext = false
            showsInfo = false
        } else {
            showsEQ = true
        }
    }

    /// Up Next or Info gone: the EQ sheet a shared file waited for.
    private func eqAfterSheet() {
        guard eqWaits else { return }
        eqWaits = false
        if navigation.eqImport != nil && navigation.eqImportPage == nil { showsEQ = true }
    }

    private func content(_ track: QueueTrack) -> some View {
        VStack(spacing: 0) {
            // the chevron's row is the grip either way; it stays put as lyrics come and go
            topRow
                .contentShape(Rectangle())
                .gesture(grip)
            // the cover or the lyrics, crossfading in ONE place: a ZStack, so the one going and the one coming share
            // the room through the fade rather than each taking half of it in the column (the cover shrinking and the
            // lyrics laid out at half height, then grown)
            ZStack {
                if lyricsShown {
                    // outside the grip: a scroll of the lyrics never drags the sheet
                    lyricsFace(track)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if turntable {
                    // outside the grip too: the record and the arm are controls (2.7)
                    TurntableView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        CoverImage(id: track.coverArt, size: 360)
                            .frame(maxWidth: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                            .scaleEffect(player.isPlaying ? 1 : Self.pausedScale)
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
                            .padding(.horizontal, 8)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(grip)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // the titles crossfade between the looks (leading on the cover, centred on the turntable) - a fade, not a
            // slide; in a ZStack, so the two share their place through it
            ZStack {
                titles(track, centred: turntable)
                    .id(turntable)
                    .transition(.opacity)
            }
            // on the turntable a failure's line, or the silent record's, is laid over the plinth's foot: its bottom
            // --pl-error-gap above the title, taking no touch, so the plinth never moves for it (2.1, 2.8)
            .overlay(alignment: .top) {
                if turntable, let line = footLine {
                    TurntableFootLine(text: line)
                        .alignmentGuide(.top) { (d: ViewDimensions) -> CGFloat in d[.bottom] + Self.errorGap }
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 12)

            // the scrubber's row either way: the scrubber on the cover, the time line centred in it on the turntable,
            // so the swap moves no row (2.1)
            ZStack {
                ScrubberView()
                    .opacity(turntable ? 0 : 1)
                    .allowsHitTesting(!turntable)
                    .accessibilityHidden(turntable)
                if turntable {
                    TurntableTimeLine()
                        .transition(.opacity)
                }
            }

            transport
                .padding(.vertical, 12)

            footer(track)
        }
        // the readout over everything in the column, the foot line included (5.1)
        .overlayPreferenceValue(PlinthPlaceKey.self) { (place: PlinthPlace?) in
            TurntableReadoutLayer(place: place, shown: turntable, swap: swap)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    /// --pl-error-gap: a failure's line to the title under it.
    static let errorGap: CGFloat = 6

    /// The line over the plinth's foot: the player's failure, else the silent record's (which never shows over one).
    private var footLine: String? {
        if let error = player.errorLine, !error.isEmpty { return error }
        return deck.silentLine
    }

    /// The failure's line (on the cover: above the title, in the flow), the title and "Artist — Album" - centred on the
    /// turntable, as the web's are.
    private func titles(_ track: QueueTrack, centred: Bool) -> some View {
        VStack(alignment: centred ? .center : .leading, spacing: 4) {
            if !centred, let error = player.errorLine, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(track.title)
                .font(.title2.bold())
                .lineLimit(1)
            byline(track, centred: centred)
        }
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }

    /// The chevron, the notice over the row, and the look button opposite the chevron.
    private var topRow: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NowPlayingWords.close)
            Spacer()
            // named for the look, not for what shows (NowPlaying.tsx:382): over the lyrics, the look's square still says
            // a tap shows the cover, as it will
            LookButton(showingTurntable: look == .turntable, action: lookTapped)
        }
        // the notice (D11), said over Now Playing - which covers the capsule over the mini player: in the top
        // row, centred, where nothing else is, so it moves nothing and covers no button (phase2-downloads.md
        // 4.2); in with opacity alone
        .overlay {
            if let notice = player.notice {
                Notice(text: notice)
                    .padding(.horizontal, 48)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: player.notice)
    }

    /// The look button (NowPlaying.tsx:343): the other look for as long as this stays open, the lyrics giving way to it;
    /// switching to the turntable is a gesture the record's sound may start from.
    private func lookTapped() {
        let tapped = TurntableSettings.lookTapped(look, lyricsOn: lyrics.showing)
        if tapped.wake { deck.wake() }
        withAnimation(swap) {
            if tapped.lyricsOff { lyrics.showing = false }
            switched = tapped.look
        }
    }

    /// The lyrics' place (4.2): the lines; the spinner while they're asked with none in hand; a failure in a listener's
    /// words and - unless the song is gone - Try again.
    @ViewBuilder private func lyricsFace(_ track: QueueTrack) -> some View {
        switch lyrics.face {
        case .synced, .plain:
            if let shown = lyrics.shown {
                // made afresh for each song: a new song's lines start at their top
                LyricsView(lyrics: shown, covered: showsUpNext || showsInfo || showsEQ)
                    .id(track.id)
            }
        case .loading:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(LyricsWords.loading)
        case .failed(let tryAgain):
            if let failure = lyrics.failure {
                VStack(spacing: 12) {
                    ErrorNote(failure, gone: LyricsWords.songGone, failed: LyricsWords.failed, retry: true)
                    if tryAgain {
                        Button(LibraryWords.tryAgain) { lyrics.retry() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 8)
            }
        case .cover:
            // none: the cover - lyricsShown is false then, so not drawn here
            EmptyView()
        }
    }

    /// Lyrics: on, it is lit and filled (Apple Music's glyph); dimmed - its tap nothing - only while off for a song
    /// known to have none, or none kept on this phone offline (2.7). Named for that state, selected while on.
    private var lyricsButton: some View {
        let have = lyrics.have
        let on = lyrics.showing
        let dimmed = Lyrics.dimmed(have, on: on)
        return Button {
            // off over the turntable's look goes back to the record, a gesture its sound may start from
            let tapped = TurntableSettings.lyricsTapped(look, lyricsOn: on)
            if tapped.wake { deck.wake() }
            withAnimation(.easeInOut(duration: 0.25)) { lyrics.showing = tapped.lyricsOn }
        } label: {
            Image(systemName: on ? "quote.bubble.fill" : "quote.bubble")
                .font(.title3)
                .foregroundStyle(on ? Palette.accent : Color.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .opacity(dimmed ? Palette.off : 1)
        .accessibilityLabel(LyricsWords.label(have))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func byline(_ track: QueueTrack, centred: Bool) -> some View {
        let byline = PlayerWords.byline(artist: track.artist, album: track.album)
        if let route = PlayedAlbum.route(track, player: player) {
            Button {
                navigation.openAlbum(route)
            } label: {
                Text(byline)
                    .font(.body)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: centred ? .center : .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlayerWords.goToAlbum(byline))
        } else {
            Text(byline)
                .font(.body)
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
                .frame(minHeight: 28)
        }
    }

    private var transport: some View {
        let paged = player.paged != nil
        let mode = player.repeatMode
        return HStack {
            ModeButton(glyph: "shuffle", on: player.shuffle, label: shuffleLabel(player.paged?.scope), enabled: !paged) {
                if !paged { player.toggleShuffle() }
            }
            Spacer(minLength: 0)
            Button {
                if turntable { deck.wake() }
                player.previous()
            } label: {
                Image(systemName: "backward.fill").font(.title)
                    .frame(minWidth: 56, minHeight: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NowPlayingWords.previous)
            Spacer(minLength: 0)
            Button {
                // on the turntable the deck's: a pause winds the record down, a play during a coast starts from it
                if turntable { deck.toggle() } else { player.toggle() }
            } label: {
                ZStack {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .opacity(player.isLoading ? 0.35 : 1)
                    if player.isLoading { ProgressView().controlSize(.large) }
                }
                .frame(minWidth: 72, minHeight: 72)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(PlayerWords.playPause(playing: player.isPlaying))
            Spacer(minLength: 0)
            Button {
                if turntable { deck.wake() }
                player.next()
            } label: {
                Image(systemName: "forward.fill").font(.title)
                    .frame(minWidth: 56, minHeight: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(PlayerWords.next)
            Spacer(minLength: 0)
            ModeButton(glyph: mode == .one ? "repeat.1" : "repeat", on: mode != .off, label: repeatLabel(mode)) {
                player.setRepeat(nextRepeat(mode))
            }
        }
        .buttonStyle(.plain)
    }

    private func footer(_ track: QueueTrack) -> some View {
        let route = PlayedAlbum.route(track, player: player)
        return HStack {
            lyricsButton
            Spacer()
            AirPlayButton()
                .frame(width: 44, height: 44)
                .anchorPreference(key: FooterGapKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> FooterGap in
                    FooterGap(airPlay: bounds)
                }
            Spacer()
            Button { showsUpNext = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(upNextLabel(shuffle: player.shuffle, repeat: player.repeatMode))
            .anchorPreference(key: FooterGapKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> FooterGap in
                FooterGap(upNext: bounds)
            }
            Spacer()
            NowPlayingMenu(hasAlbum: route != nil, saysSpeed: menuSaysSpeed,
                           onInfo: { showsInfo = true }, onEQ: { showsEQ = true },
                           onPlaylist: reachability.online ? { playlistPick = PlaylistPickRequest(PlaylistPick(playing: track)) } : nil) {
                if let route { navigation.openAlbum(route) }
            }
        }
        .foregroundStyle(.primary)
        // the chip over the gap between AirPlay and Up Next, the buttons untouched (5.1)
        .overlayPreferenceValue(FooterGapKey.self) { (gap: FooterGap) in
            SpeedChipPlace(gap: gap, shown: chipShown)
        }
    }

    /// The sheet's drag to close, from the top half alone: it follows a finger down once it has gone
    /// dragStartDistance, and closes the sheet let go past dismissDistance - else springs back.
    private var grip: some Gesture {
        DragGesture(minimumDistance: PlayerWords.dragStartDistance, coordinateSpace: .global)
            .onChanged { value in dragY = max(0, value.translation.height) }
            .onEnded { value in
                if max(0, value.translation.height) > PlayerWords.dismissDistance {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
                }
            }
    }

    private func close() {
        navigation.nowPlayingShown = false
    }
}

/// Shuffle and Repeat on the transport: pressed while on (VoiceOver's "selected"), tinted the accent while on - and
/// Shuffle, during a library's shuffle, on and dimmed, its tap doing nothing (that order is the shuffle).
private struct ModeButton: View {
    let glyph: String
    let on: Bool
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.title3.weight(.semibold))
                .foregroundStyle(on ? Palette.accent : Color.primary.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// AirPlay's and Up Next's targets in the footer: the chip goes in the gap between them (5.1).
private struct FooterGap {
    var airPlay: Anchor<CGRect>?
    var upNext: Anchor<CGRect>?
}

private struct FooterGapKey: PreferenceKey {
    static var defaultValue: FooterGap { FooterGap() }

    static func reduce(value: inout FooterGap, nextValue: () -> FooterGap) {
        let next = nextValue()
        value.airPlay = value.airPlay ?? next.airPlay
        value.upNext = value.upNext ?? next.upNext
    }
}

/// The chip, centred in the gap between AirPlay's target and Up Next's, level with them.
private struct SpeedChipPlace: View {
    let gap: FooterGap
    let shown: Bool
    @Environment(PlayerModel.self) private var player

    var body: some View {
        GeometryReader { (space: GeometryProxy) in
            if shown, let airPlay = gap.airPlay, let upNext = gap.upNext {
                let left = space[airPlay]
                let right = space[upNext]
                SpeedChip(speed: player.speed) { player.setSpeed(PlaySpeed.normal) }
                    .position(x: (left.maxX + right.minX) / 2, y: left.midY)
                    .transition(.opacity)
            }
        }
    }
}

/// The chip (5.1, SpeedChip.tsx): `1.25x` in the toggled face, a tap back to 1x, named for both
/// ("1.25x, 1.25 times the song's speed: back to normal speed"). Its words stop growing at xxLarge: at 19 pt (xxxLarge)
/// the widest, `0.25x`, is about 73 pt, past the glyphs either side of a 375 pt phone's gap (about 70 pt apart); at
/// 17 pt it is about 67.
private struct SpeedChip: View {
    let speed: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(TurntableWords.speedLabel(speed))
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(SpeedChipFace())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel(TurntableWords.chip(speed))
    }
}

/// STYLE.md's toggled chip (app.css .app-speed-chip-face): 28 pt tall, 8 pt across, radius 4, the toggled edge and
/// fill - `--dw-pressed` under a finger - in a 44 pt target.
private struct SpeedChipFace: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(TurntableFace.lookRadius))
        return configuration.label
            .padding(.horizontal, CGFloat(TurntableFace.chipPad))
            .frame(height: CGFloat(TurntableFace.chipFace))
            .background(shape.fill(configuration.isPressed ? Palette.pressed : Palette.toggledFill))
            .overlay(shape.strokeBorder(Palette.toggledEdge, lineWidth: CGFloat(TurntableFace.hairline)))
            .frame(height: CGFloat(TurntableFace.hit))
            .contentShape(Rectangle())
    }
}

/// Behind it all, the cover again - blurred to a wash and dimmed, asked at the size the big cover is, so it is the
/// same picture from the cache. Dimmed further while lyrics show (Lyrics.backdropDim), the change eased in.
private struct Backdrop: View {
    let cover: String?
    let dim: Double

    var body: some View {
        GeometryReader { space in
            CoverImage(id: cover, size: 360)
                .scaledToFill()
                .frame(width: space.size.width, height: space.size.height)
                .clipped()
                .blur(radius: 60)
                .overlay(Color.black.opacity(dim))
                .animation(.easeInOut(duration: 0.25), value: dim)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
