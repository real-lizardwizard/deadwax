import DeadwaxCore
import SwiftUI

/// Now Playing, over the tabs (ui/src/player/NowPlaying.tsx, a phone's): the cover over its own blur, smaller while
/// paused; a failure's words ABOVE the title (a line that comes and goes moves the cover, never what a finger is
/// reaching for); the title and "Artist — Album", which goes to the album; the scrubber; the transport - Shuffle,
/// Previous, Play/Pause, Next, Repeat (2.0.14) - and (the redesign, R3 - notes/ios.md "The redesign, slice R3: the
/// side panel's tabs; the Now Playing sheet"; iNowPlaying.dc.html) the bottom row in the footer's place: five labelled
/// icons, Queue, Lyrics, the output, Info, EQ (NowPlayingTabs.row). The ••• is up beside the look button. It closes
/// from Close (the chevron until R4b) or a drag down its top half past PlayerWords.dismissDistance, begun past
/// dragStartDistance - the
/// cover and the row above it are the grip, the bar and the buttons below keep their own gestures.
///
/// ONE SHEET (R3): Queue, Info and EQ open Now Playing's one sheet on their tab (NowPlayingSheet) - in place of its
/// three, Up Next, Info and the EQ - and the sheet up already moves to the tab asked for; Lyrics never opens it.
///
/// LYRICS (app 0.4, notes/app-lyrics.md 4.1-4.3): with Lyrics on, the song's lyrics take the cover's place - the cover
/// and the room around it - and the top row alone is the grip, so scrolling them never drags the sheet; the title,
/// the scrubber, the transport and the bottom row stay where they are. A song with none (or none kept on this phone,
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
/// off 1x, a chip - `1.25x`, a tap back to 1x - (R3's review) in a band of its own just above the bottom row, over the
/// gap between the output and Info (SpeedChipBand; AirPlay and Up Next before), drawn whether the chip shows or not, so
/// nothing moves as it comes and goes and its target overlaps no button's; at the accessibility sizes, where it wouldn't
/// fit, the ••• menu says it instead ("Speed 1.25x - back to normal speed"). The mini player doesn't show it.
///
/// Every action is PlayerModel's, called straight from the tap. Shuffle and Repeat are named in Up Next's words
/// (shuffleLabel, repeatLabel), pressed while on, tinted while on; a library's shuffle can't be turned off, so its
/// Shuffle stays on and does nothing. The Queue button names what is on for VoiceOver (upNextLabel) and is never tinted.
///
/// THE FACE (the redesign, slice R4b - notes/ios.md "The redesign, slice R4b: Now Playing's face"; iNowPlaying.dc.html;
/// the phone alone, the Mac's frame never opens Now Playing): the top is the compact top (PhoneTop, `.topbar`) - Close
/// at its left, the look button named at its right (NamedLookButton: Turntable, or Cover on the turntable) and the •••,
/// each the accent's words or glyph with no face, at the top's own 12 from the screen's edges; the cover 24 either side;
/// the title (22, bold, its letters drawn closer) over "Artist — Album" in the accent, a link to the album, the row the
/// title's alone (27 Nov); the scrubber sunken (ScrubberView), and between its two times the readout, "3 of 11 · FLAC
/// 16/44.1" in their Courier Prime - Core's BarDisplay's, as the Mac's bar says it (NowPlayingReadout) - or on a line of
/// its own under them where the three don't fit. The transport, the bottom row, Lyrics in the cover's place, the
/// turntable (its titles too) and every gesture are as they were. The phone stays flat (R1c): only the cover, the
/// scrubber's track, the speed chip and the notice keep a face here, each as it was.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    @Environment(LyricsModel.self) private var lyrics
    @Environment(DeckController.self) private var deck
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// (R3) Now Playing's one sheet is up (NowPlayingSheet) - on `sheetTab`, which moves it in place.
    @State private var sheetUp = false
    @State private var sheetTab: NowPlayingTabs.Tab = .upNext
    /// A shared file's EQ waits for the cover full screen to close (eq.md 3.9; NowPlayingTabs.shared).
    @State private var eqWaits = false
    /// How far the sheet has been dragged down (points).
    @State private var dragY: CGFloat = 0
    /// The look the button switched to while this stays open; nil: as You > Playback says (the web's, reset as it opens).
    @State private var switched: TurntableSettings.Look?
    /// Add to a playlist, from the •••: the picker over Now Playing, with the song playing (Phase 4, slice 2).
    @State private var playlistPick: PlaylistPickRequest?
    /// The cover full screen, from a tap on it (CoverViewer.swift): presented from the root, so it stays up as the
    /// cover's place gives way to Lyrics.
    @State private var viewing: ViewedCover?
    /// (R4b) How wide the top's two ends are as last laid out - Close, and the look button with the ••• - so the notice
    /// is laid in the room between them (topRow).
    @State private var topEnds = TopEnds()
    @Environment(Reachability.self) private var reachability

    /// The cover's scale while paused (--pl-paused-scale).
    private static let pausedScale: CGFloat = 0.82
    /// (R4b) The title's letters drawn closer.
    private static let titleTracking: CGFloat = -0.3     // drawn: iNowPlaying's title letter-spacing

    init() {}

    /// Lyrics take the cover's place: on, and the song has some (or they are on their way, or failed).
    private var lyricsShown: Bool { Lyrics.shows(lyrics.have, on: lyrics.showing) }

    /// The look showing, the button's or You's. (The Mac app, slice 2) The cover, always, on the Mac: James's direction
    /// for the Mac is no turntable - no look button there, nor Settings > Playback's two turntable rows.
    private var look: TurntableSettings.Look { Platform.mac ? .cover : switched ?? deck.opensAs }

    /// A sheet is over Now Playing, at its full height: its one sheet (R3: the Queue, Info or the EQ), Add to a playlist
    /// or the cover full screen - the scrubber under it unseen.
    private var sheetOver: Bool { sheetUp || playlistPick != nil || viewing != nil }

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
        // (R3) one sheet, the Queue, Info and the EQ its tabs - moved between them in place, never a second over it
        .appSheet(isPresented: $sheetUp) { NowPlayingSheet(tab: $sheetTab).macSheet() }
        .appSheet(item: $playlistPick) { (request: PlaylistPickRequest) in PlaylistPicker(request: request).macSheet() }
        .coverViewer($viewing, onDismiss: eqAfterSheet)
        .onAppear { lyrics.opened() }
        // the deck told what shows as it opens and as the look changes - and that it doesn't, as it closes (2.1)
        .onChange(of: turntable, initial: true) { (_: Bool, now: Bool) -> Void in deck.screen(turntable: now) }
        .onDisappear { deck.closed() }
        .onChange(of: navigation.eqImport?.id, initial: true) { (_: UUID?, _: UUID?) -> Void in shared() }
    }

    /// A file shared to deadwax while Now Playing is up (eq.md 3.9): the sheet on EQ, the preview over it - the sheet up
    /// on the Queue or Info moved to EQ in place, nothing lost under them; over the EQ already up, the preview shows in
    /// it as it stands. The cover full screen is closed first, and the sheet opens once it has gone (NowPlayingTabs.shared).
    private func shared() {
        guard navigation.eqImport != nil, navigation.eqImportPage == nil, !navigation.eqPreviewUp else { return }
        switch NowPlayingTabs.shared(sheet: sheetUp ? sheetTab : nil, coverUp: viewing != nil) {
        case .show(let tab):
            open(tab)
        case .waitThenShow:
            eqWaits = true
            CoverViewing.put(nil, into: $viewing)
        }
    }

    /// The cover full screen gone: the sheet on EQ a shared file waited for.
    private func eqAfterSheet() {
        guard eqWaits else { return }
        eqWaits = false
        if navigation.eqImport != nil && navigation.eqImportPage == nil { open(.eq) }
    }

    /// (R3) The sheet on `tab`: opened on it, or - up already - moved to it in place.
    private func open(_ tab: NowPlayingTabs.Tab) {
        sheetTab = tab
        sheetUp = true
    }

    private func content(_ track: QueueTrack) -> some View {
        VStack(spacing: 0) {
            // the top row is the grip either way; it stays put as lyrics come and go. (R4b) It is the compact top, at its
            // own 12 from the screen's edges (`.topbar`): out past the column's 24 either side, which everything under
            // it keeps (the padding at the foot of this column) - its grip the whole width
            topRow(track)
                .contentShape(Rectangle())
                .gesture(grip)
                .padding(.horizontal, -24)
                // (R4b's review) drawn over what follows it, so a notice laid just under the top shows over the cover
                .zIndex(1)
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
                        // (R4b) the column's width: 24 either side (iNowPlaying's cover) on every phone, where it was
                        // 32 and at most 360 - still asked at 360, which is the largest size asked (CoverSize.hero) on
                        // every phone's screen, as before, and the backdrop's
                        CoverImage(id: track.coverArt, size: 360)
                            .clipShape(Corners.artShape)
                            // a tap opens the cover full screen; a drag is still the grip's (CoverViewer.swift)
                            .opensCoverFullScreen(track, into: $viewing)
                            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                            .scaleEffect(player.isPlaying ? 1 : Self.pausedScale)
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // high priority over the cover's tap: a drag is the grip's from its first dragStartDistance, and
                    // the tap fires at lift only when no drag began
                    .highPriorityGesture(grip)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // the titles crossfade between the looks (leading on the cover, centred on the turntable) - a fade, not a
            // slide; in a ZStack, so the two share their place through it
            ZStack {
                // (R4b) the cover's titles and the readout (coverTitles); the turntable's exactly as they were (titles)
                if turntable {
                    titles(track, centred: true)
                        .transition(.opacity)
                } else {
                    coverTitles(track)
                        .transition(.opacity)
                }
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
            // so the swap moves no row (2.1) - and hidden there or under a sheet, no frames drawn for it (review, 15 Nov)
            ZStack {
                ScrubberView(visible: !turntable && !sheetOver) {
                    // (27 Nov) the readout between its times - on the cover alone, so the turntable's row is the
                    // hidden scrubber's, as it was
                    if !turntable { NowPlayingReadout() }
                }
                .opacity(turntable ? 0 : 1)
                .allowsHitTesting(!turntable)
                .accessibilityHidden(turntable)
                if turntable {
                    TurntableTimeLine()
                        .transition(.opacity)
                }
            }

            transport
                .padding(.top, 12)

            // (R3's review) the speed chip's own band, over the gap between the output and Info: its target clear of
            // the transport above and the row below, the band drawn whether the chip shows or not (5.1)
            SpeedChipBand(shown: chipShown)

            bottomRow
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

    /// The turntable's titles: the title and "Artist — Album", centred over the record, as the web's are. (R4b) Exactly
    /// as at 31cab12d - the turntable keeps no diff (mac-redesign-build.md 3.6), so its titles keep their own face, the
    /// quiet byline and no tracking, and nothing beside them; tests/test_ios_now_playing_look.py pins this function and
    /// `byline` to what they were. Called centred alone: the cover's are coverTitles.
    private func titles(_ track: QueueTrack, centred: Bool) -> some View {
        VStack(alignment: centred ? .center : .leading, spacing: 4) {
            if !centred, let error = player.errorLine, !error.isEmpty {
                Text(error)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(track.title)
                .font(Typeface.title2.bold())
                .lineLimit(1)
            byline(track, centred: centred)
        }
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }

    /// (R4b) The cover's titles: the failure's line above the title, in the flow; the title and "Artist — Album". (27 Nov)
    /// The title's row is the title's alone, at the column's whole width: the readout that stood beside it is between
    /// the scrubber's times now (NowPlayingReadout, in ScrubberView).
    private func coverTitles(_ track: QueueTrack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = player.errorLine, !error.isEmpty {
                Text(error)
                    .font(Typeface.footnote)
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            coverNames(track)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// (R4b) The cover's title - 22, bold, white, its letters drawn closer (iNowPlaying's) - over "Artist — Album" in the
    /// accent (coverByline).
    private func coverNames(_ track: QueueTrack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(track.title)
                .font(Typeface.title2.bold())
                .tracking(Self.titleTracking)
                .foregroundStyle(DWPalette.text)
                .lineLimit(1)
            coverByline(track)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// (R4b) The compact top (PhoneTop, iNowPlaying's `.topbar`): Close at its left; the look button named and the ••• at
    /// its right, 8 apart - each the accent's words or glyph with no face, in a finger's target, as every flat button on
    /// the phone is. Capped at xxxLarge as the top is, so each shows large under a long press at the sizes past it.
    ///
    /// The notice (D11), said over Now Playing - which covers the capsule over the mini player - is in the top's middle,
    /// between Close and the look button with the •••, as wide as they leave it, so it moves nothing and covers no button
    /// whatever its length (phase2-downloads.md 4.2; R3's review - centred over the whole row it covered the look button);
    /// as tall as its lines, taking no touch; in with opacity alone. PhoneTop's middle is its own Spacer, so the notice
    /// is laid over the top, in from each side by the top's room, that end's width and the gap (`topEnds`, measured).
    /// (R4b's review) The middle narrows as the top's words grow, so where it is narrower than the notice's longest word
    /// (NoticeWord, measured - from xxLarge on a 375 pt phone, "Downloading" 116 against 99) the notice is laid the whole
    /// width just under the top instead, over the cover, still taking no touch - never a word broken in half. Its words
    /// stop growing at xxxLarge, as the top's do.
    private func topRow(_ track: QueueTrack) -> some View {
        let side = CGFloat(PhoneLook.topSide)
        let gap = CGFloat(PhoneLook.topGap)
        let middle = Self.noticeInMiddle(topEnds, side: side, gap: gap)
        return PhoneTop {
            closeButton
                .onGeometryChange(for: CGFloat.self) { (end: GeometryProxy) -> CGFloat in
                    end.size.width
                } action: { (width: CGFloat) -> Void in
                    topEnds.leading = width
                }
        } trailing: {
            HStack(spacing: gap) {
                // named for the look a tap shows, not for what shows (NowPlaying.tsx:382): over the lyrics it still says
                // what a tap shows, as it will. None on the Mac, which has no turntable (`look`)
                if !Platform.mac {
                    NamedLookButton(showingTurntable: look == .turntable, action: lookTapped)
                }
                // (R3) up from the footer, beside the look button (iNowPlaying.dc.html's topbar); the EQ left it for the row
                menu(track)
            }
            .onGeometryChange(for: CGFloat.self) { (end: GeometryProxy) -> CGFloat in
                end.size.width
            } action: { (width: CGFloat) -> Void in
                topEnds.trailing = width
            }
        }
        .onGeometryChange(for: CGFloat.self) { (top: GeometryProxy) -> CGFloat in
            top.size.width
        } action: { (width: CGFloat) -> Void in
            topEnds.whole = width
        }
        .background {
            // the notice's longest word, measured as the notice draws it, unseen
            if let notice = player.notice {
                NoticeWord(text: notice)
                    .onGeometryChange(for: CGFloat.self) { (word: GeometryProxy) -> CGFloat in
                        word.size.width
                    } action: { (width: CGFloat) -> Void in
                        topEnds.word = width
                    }
            }
        }
        .overlay(alignment: middle ? Alignment.center : Alignment.bottom) {
            if let notice = player.notice {
                Notice(text: notice)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, middle ? side + topEnds.leading + gap : side)
                    .padding(.trailing, middle ? gap + topEnds.trailing + side : side)
                    .alignmentGuide(.bottom) { (d: ViewDimensions) -> CGFloat in middle ? d[.bottom] : d[.top] }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: player.notice)
    }

    /// (R4b's review) Notice's own room either side of its words (Notice.swift's `.padding(.horizontal, 16)`).
    private static let noticePad: CGFloat = 16

    /// (R4b's review) The notice in the top's middle: its longest word fits the room Close and the look button with the
    /// ••• leave it, inside its own padding - else it lies the whole width under the top.
    private static func noticeInMiddle(_ ends: TopEnds, side: CGFloat, gap: CGFloat) -> Bool {
        let room = ends.whole - 2 * side - ends.leading - ends.trailing - 2 * gap - 2 * noticePad
        return ends.word > 0 && ends.word <= room
    }

    /// (R4b) Close (iNowPlaying's, where the chevron was): a flat small button, the accent's word. The drag down from the
    /// top half still closes Now Playing too (`grip`).
    private var closeButton: some View {
        Button(NowPlayingWords.close, action: close)
            .buttonStyle(DWButtonStyle(size: .small))
            .accessibilityShowsLargeContentViewer { Text(NowPlayingWords.close) }
            // (the Mac app, slice 2) Escape closes Now Playing; nothing on the iPhone
            .escapeCloses()
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
                LyricsView(lyrics: shown, covered: sheetUp)
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
                        // (R4b) a flat button, the accent's words with no face, as every one on the flat phone (R1c)
                        Button(LibraryWords.tryAgain) { lyrics.retry() }
                            .buttonStyle(DWButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
            }
        case .cover:
            // none: the cover - lyricsShown is false then, so not drawn here
            EmptyView()
        }
    }

    /// Lyrics, the bottom row's second: on, it is lit and filled (Apple Music's glyph); dimmed - its tap nothing - only
    /// while off for a song known to have none, or none kept on this phone offline (2.7). Named for that state, selected
    /// while on. (R3) It turns the lyrics in the cover's place on and off - never the sheet (NowPlayingTabs.opens).
    private var lyricsItem: some View {
        let have = lyrics.have
        let on = lyrics.showing
        let dimmed = Lyrics.dimmed(have, on: on)
        return PhoneTabItem(words: NowPlayingTabs.Words.button(.lyrics) ?? LyricsWords.lyrics, shown: on,
                            spoken: LyricsWords.label(have, device: Platform.device),
                            action: { tapped(.lyrics) }) {
            Image(systemName: NowPlayingTabs.symbol(.lyrics, on: on) ?? "")
                .font(Typeface.symbol(.title3))
        }
        .disabled(dimmed)
        .opacity(dimmed ? Palette.off : 1)
    }

    /// Lyrics on or off in the cover's place: off over the turntable's look goes back to the record, a gesture its sound
    /// may start from.
    private func lyricsTapped() {
        let tapped = TurntableSettings.lyricsTapped(look, lyricsOn: lyrics.showing)
        if tapped.wake { deck.wake() }
        withAnimation(.easeInOut(duration: 0.25)) { lyrics.showing = tapped.lyricsOn }
    }

    /// The turntable's "Artist — Album", a link to the album. (R4b) Exactly as at 31cab12d, with `titles`: quiet, centred.
    @ViewBuilder private func byline(_ track: QueueTrack, centred: Bool) -> some View {
        let byline = PlayerWords.byline(artist: track.artist, album: track.album)
        if let route = PlayedAlbum.route(track, player: player) {
            Button {
                navigation.openAlbum(route)
            } label: {
                Text(byline)
                    .font(Typeface.body)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: centred ? .center : .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlayerWords.goToAlbum(byline))
        } else {
            Text(byline)
                .font(Typeface.body)
                .foregroundStyle(Palette.quiet)
                .lineLimit(1)
                .frame(minHeight: 28)
        }
    }

    /// (R4b) The cover's "Artist — Album": a link to the album in the accent (iNowPlaying's `.acc`), as every flat
    /// button's words are; for a song that names no album, plain words in the second colour - the accent would say a
    /// tap goes somewhere.
    @ViewBuilder private func coverByline(_ track: QueueTrack) -> some View {
        let byline = PlayerWords.byline(artist: track.artist, album: track.album)
        if let route = PlayedAlbum.route(track, player: player) {
            Button {
                navigation.openAlbum(route)
            } label: {
                Text(byline)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.acc)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlayerWords.goToAlbum(byline))
        } else {
            Text(byline)
                .font(Typeface.body)
                .foregroundStyle(DWPalette.t2)
                .lineLimit(1)
                .frame(minHeight: 28)
        }
    }

    private var transport: some View {
        //? Shuffle can't be used during a library's shuffle - (Last.fm, A3) nor turned on with a station, as the Queue's
        let paged = player.paged != nil || player.stationHoldsShuffle
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
                SharpSymbol(.previous).font(Typeface.symbol(.title))
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
                    PlayPauseGlyph(playing: player.isPlaying)
                        .font(Typeface.symbol(size: 44))
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
                SharpSymbol(.next).font(Typeface.symbol(.title))
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

    /// The ••• (NowPlayingMenu), up beside the look button since R3: Info opens the sheet on Info; the EQ left it for the
    /// bottom row (`onEQ` nil). (R4b) Its glyph in the accent with no face, as the top's flat buttons are (iNowPlaying's
    /// `.btn.sm`), in the menu's own 44 pt target; large under a long press past xxxLarge, where the top stops growing.
    private func menu(_ track: QueueTrack) -> some View {
        let route = PlayedAlbum.route(track, player: player)
        return NowPlayingMenu(hasAlbum: route != nil, saysSpeed: menuSaysSpeed,
                              onInfo: { open(.info) }, onEQ: nil,
                              onPlaylist: reachability.online ? { playlistPick = PlaylistPickRequest(PlaylistPick(playing: track)) } : nil) {
            if let route { navigation.openAlbum(route) }
        }
        .foregroundStyle(DWPalette.acc)
        .accessibilityShowsLargeContentViewer { Image(systemName: "ellipsis") }
    }

    /// (R3) The bottom row, in the footer's place (iNowPlaying.dc.html): five labelled icons, as the tab bar's items with
    /// no bar (PhoneTabItem) - Queue, Lyrics, the output, Info, EQ (NowPlayingTabs.row), each opening what it names
    /// (`tapped`), each the whole of its column. (R3's review) The EQ and the output are views of their own, the only
    /// ones here reading the EQ (EQRowItem, OutputItem): a slider moved redraws them, never Now Playing.
    private var bottomRow: some View {
        HStack(spacing: 0) {
            ForEach(NowPlayingTabs.row, id: \.self) { (button: NowPlayingTabs.Button) in
                switch button {
                case .lyrics:
                    lyricsItem
                case .output:
                    OutputItem()
                case .eq:
                    EQRowItem { tapped(.eq) }
                case .upNext, .info:
                    sheetItem(button)
                }
            }
        }
    }

    /// A button of the row that opens the sheet on its tab - Queue and Info (the EQ is EQRowItem) - named in the tab's
    /// words, never tinted; for VoiceOver the Queue's with what is on (upNextLabel: "Queue - Shuffle on").
    private func sheetItem(_ button: NowPlayingTabs.Button) -> some View {
        let words = NowPlayingTabs.Words.button(button) ?? ""
        let spoken: String? = switch button {
        case .upNext: upNextLabel(shuffle: player.shuffle, repeat: player.repeatMode)
        case .lyrics, .output, .info, .eq: nil
        }
        return PhoneTabItem(words: words, shown: false, spoken: spoken, action: { tapped(button) }) {
            Image(systemName: NowPlayingTabs.symbol(button) ?? "")
                .font(Typeface.symbol(.title3))
        }
    }

    /// A button of the row tapped: what it opens (NowPlayingTabs.opens) - the sheet on its tab, or moved to it; the lyrics
    /// on or off in the cover's place; the output's taps are AirPlay's own.
    private func tapped(_ button: NowPlayingTabs.Button) {
        switch NowPlayingTabs.opens(button) {
        case .tab(let tab):
            open(tab)
        case .lyrics:
            lyricsTapped()
        case .output:
            break
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

/// (R4b) How wide the top's two ends are - Close, and the look button with the ••• - the whole top, and (R4b's review)
/// the notice's longest word.
private struct TopEnds: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    var whole: CGFloat = 0
    var word: CGFloat = 0
}

/// (R4b's review) The notice's longest word as Notice draws it - its face, its cap at xxxLarge - each word whole on one
/// line, the widest setting the width; drawn unseen, heard by no one. Split where the notice's lines can break, at
/// spaces: a word with a hyphen is measured whole, wider than the most it could need.
private struct NoticeWord: View {
    let text: String

    var body: some View {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        ZStack {
            ForEach(words.indices, id: \.self) { (index: Int) in
                Text(words[index])
            }
        }
        .font(Typeface.subheadline)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .hidden()
        .accessibilityHidden(true)
    }
}

/// (R4b) The look button, named (iNowPlaying's "Turntable"): the look a tap shows, in words where its glyph was (the
/// record, the square - LookButton's, which Now Playing no longer draws) - **Turntable** while the cover shows,
/// **Cover** while the turntable does, You > Playback's own two words for them. A flat small button (DWButtonStyle,
/// `.dw.ph .btn.sm`): the accent's word with no face, in a finger's 44 pt target. VoiceOver hears what a tap does, as
/// before ("Show as a turntable", "Show the cover"); past xxxLarge, where the top stops growing, a long press shows its
/// word large, as LookButton's did.
private struct NamedLookButton: View {
    let showingTurntable: Bool
    let action: () -> Void

    var body: some View {
        let words = showingTurntable ? TurntableWords.lookCover : TurntableWords.lookTurntable
        Button(words, action: action)
            .buttonStyle(DWButtonStyle(size: .small))
            .accessibilityLabel(TurntableWords.lookButton(showingTurntable: showingTurntable))
            .accessibilityShowsLargeContentViewer { Text(words) }
    }
}

/// (R4b; under the scrubber since 27 Nov - notes/ios.md "Now Playing's readout under the scrubber (27 Nov)") The
/// readout between the scrubber's times (iNowPlaying's `.q3`): the song's place in what was queued and its format, joined
/// - "3 of 11 · FLAC 16/44.1" - Core's BarDisplay.readout, the Mac player bar's own words, never counted here: a song
/// added with Play Next has no place, a song naming no format no format, either alone without the dot, and with neither
/// there is no readout. ScrubberView draws it in the times' face, the third colour, centred, and decides its line. One
/// element for VoiceOver, as before: "3 of 11, FLAC, 16-bit, 44.1 kHz". A view of its own, so the queue is read here
/// alone, never in Now Playing's body - which reads `player.current` (the queue's index and entries) as it always has,
/// so it is drawn again as the song changes either way.
private struct NowPlayingReadout: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let queue = player.queue
        if let readout = BarDisplay.readout(queue) {
            Text(readout)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BarDisplay.readoutSpoken(queue) ?? "")
        }
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
                .font(Typeface.symbol(.title3).weight(.semibold))
                .foregroundStyle(on ? Palette.accent : Color.primary.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// (R3's review) The row's EQ (PhoneTabItem): opens the sheet on EQ, named for VoiceOver with the output now's setting,
/// as the ••• item was ("EQ, Bass Boost") - a view of its own, so only it redraws as the EQ changes.
private struct EQRowItem: View {
    let action: () -> Void
    @Environment(EQModel.self) private var eq

    var body: some View {
        PhoneTabItem(words: NowPlayingTabs.Words.button(.eq) ?? "", shown: false,
                     spoken: NowPlayingTabs.Words.eq(setting: eq.now.short), action: action) {
            Image(systemName: NowPlayingTabs.symbol(.eq) ?? "")
                .font(Typeface.symbol(.title3))
        }
    }
}

/// (R3's review) The output: AirPlay's own button - its picker is the system's - laid under the whole column, its glyph
/// hidden, so all of the column takes the tap as the other four's do; over it, taking no touch, AirPlay's glyph and the
/// output's name as the EQ names it, both in the accent (iNowPlaying.dc.html). VoiceOver hears the picker alone -
/// "AirPlay", its value where it plays (the name) - the drawing over it hidden. A view of its own, so only it redraws as
/// the EQ's outputs change.
private struct OutputItem: View {
    @Environment(EQModel.self) private var eq

    var body: some View {
        let name = eq.settings.setting(for: eq.route).shownName
        VStack(spacing: CGFloat(PhoneLook.tabGap)) {
            Image(systemName: NowPlayingTabs.symbol(.output) ?? "")
                .font(Typeface.symbol(.title3))
                .lookSquare(PhoneLook.tabIcon)
            Text(name)
                .font(Typeface.Phone.text(.tabItem).weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(DWPalette.acc)
        .frame(maxWidth: .infinity)
        .lookHeight(PhoneLook.tabItem)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background {
            AirPlayButton(glyph: false, playsTo: name)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// (R3's review) The speed chip's band, between the transport and the bottom row: as tall as the chip's target
/// (TurntableFace.hit), drawn whether the chip shows or not - so nothing moves as it comes and goes (5.1) - the chip
/// centred in it on the line between the output's column and Info's (NowPlayingTabs.chipAt). Nothing else is in it, so
/// the chip's target overlaps no button's at any size it is drawn, on any phone (tests/test_ios_nowplaying_row.py works
/// the frames out for 375 and 390 points). In the row it lapped Info's column and AirPlay's target, so a tap meant for
/// Info could reset the speed and open nothing.
private struct SpeedChipBand: View {
    let shown: Bool
    @Environment(PlayerModel.self) private var player

    var body: some View {
        GeometryReader { (band: GeometryProxy) in
            if shown {
                SpeedChip(speed: player.speed) { player.setSpeed(PlaySpeed.normal) }
                    .position(x: band.size.width * CGFloat(NowPlayingTabs.chipAt), y: band.size.height / 2)
                    .transition(.opacity)
            }
        }
        .frame(height: CGFloat(TurntableFace.hit))
    }
}

/// The chip (5.1, SpeedChip.tsx): `1.25x` in the toggled face, a tap back to 1x, named for both
/// ("1.25x, 1.25 times the song's speed: back to normal speed"). Its words stop growing at xxLarge: at 19 pt (xxxLarge)
/// the widest, `0.25x`, is about 73 pt; at 17 pt it is about 67 - in its band (SpeedChipBand) a fifth of the row's width
/// either side of it is free.
private struct SpeedChip: View {
    let speed: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(TurntableWords.speedLabel(speed))
                .font(Typeface.mono(.footnote).weight(.semibold))
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(SpeedChipFace())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel(TurntableWords.chip(speed))
    }
}

/// STYLE.md's toggled chip (app.css .app-speed-chip-face): 28 pt tall, 8 pt across, square (actual corners, 15 Nov:
/// Corners.control, where the web's radius is 4), the toggled edge and fill - `--dw-pressed` under a finger - in a 44 pt
/// target.
private struct SpeedChipFace: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let radius = Corners.control
        let shape = RoundedRectangle(cornerRadius: radius)
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
