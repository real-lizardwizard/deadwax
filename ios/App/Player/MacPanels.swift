import DeadwaxCore
import SwiftUI

/// The desktop frame's side panel (the Mac app, slice 3 - the Mac app's plan 1.2; the web's app/SidePanel.tsx): Up Next,
/// Lyrics or Info, one at a time (AppNavigation.macPanel, MacFrame.toggled) - the bar's Lyrics and Up Next, the •••'s
/// Info, and View's three (⌥⌘U, ⌥⌘L, ⌘I) open and close it. MacFrame.panelWidth (470) wide: a column of its own beside
/// the page in a window 1280 wide or more, a drawer over the page's right edge below that (MacFrame.panelStyle). Never
/// modal: the page, the sidebar and the bar take their clicks while it shows. Up Next and Info are the very pages their
/// sheets over Now Playing are on the iPhone, their Done (and Escape) closing the panel (`inSidePanel`) rather than a
/// sheet; Lyrics is the lyrics Now Playing's face shows (LyricsPanel).
struct MacPanel: View {
    let panel: MacFrame.Panel

    var body: some View {
        Group {
            switch panel {
            case .upNext:
                UpNextScreen()
            case .lyrics:
                LyricsPanel()
            case .info:
                InfoView()
            case .none:
                EmptyView()
            }
        }
        .environment(\.inSidePanel, true)
        .frame(width: CGFloat(MacFrame.panelWidth))
        .frame(maxHeight: .infinity)
        .background(Palette.sidePanel)
    }
}

extension EnvironmentValues {
    /// (The Mac app, slice 3) A page drawn in the desktop frame's side panel: its Done puts the panel away
    /// (AppNavigation.closePanel). False everywhere else, where Done dismisses its sheet as before.
    @Entry var inSidePanel = false
}

/// Lyrics in the side panel (the web's LyricsPanel.tsx): the song playing's lines, lit and followed as on Now Playing's
/// face (LyricsView, its rules Core's); the spinner while they are asked with none in hand; a failure in a listener's
/// words with Try again; "No lyrics for this song."; "Nothing playing" with nothing queued - the panel stays when the
/// queue ends, as the web's does (MacFrame.afterQueueEnds). Lyrics are on (LyricsModel.showing) while it shows, so the
/// song's are asked as it opens and the next song's ahead, and off again as it goes.
struct LyricsPanel: View {
    @Environment(PlayerModel.self) private var player
    @Environment(LyricsModel.self) private var lyrics
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(LyricsWords.lyrics)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(InfoWords.done) { navigation.closePanel() }
                            .escapeCloses(!TextEditing.shared.typing)
                    }
                }
        }
        .onAppear {
            lyrics.showing = true
            lyrics.opened()
        }
        .onDisappear { lyrics.showing = false }
    }

    @ViewBuilder private var content: some View {
        if let track = player.current?.track {
            switch lyrics.face {
            case .synced, .plain:
                if let shown = lyrics.shown {
                    // made afresh for each song: a new song's lines start at their top
                    LyricsView(lyrics: shown, covered: false)
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
                                .buttonBorderShape(Corners.controlBorder)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            case .cover:
                note(lyrics.have == .notKept ? LyricsWords.label(.notKept) : LyricsWords.noLyrics)
            }
        } else {
            note(LyricsWords.nothingPlaying)
        }
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .font(Typeface.body)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }
}
