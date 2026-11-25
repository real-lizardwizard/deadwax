import DeadwaxCore
import SwiftUI

/// The desktop frame's side panel (the Mac app, slice 3 - the Mac app's plan 1.2; the web's app/SidePanel.tsx) - since
/// the Mac redesign's R3 (notes/ios.md "The redesign, slice R3: the side panel's tabs; the Now Playing sheet") a dock
/// of folder tabs (MacFolderTabs, dw.css's .tabs): Queue, Lyrics, Info and EQ, and Sources while a Get page is open,
/// one at a time (AppNavigation.macPanel, MacDock.toggled) - the bar's Lyrics and Queue, the •••'s Info and EQ, View's
/// four (⌥⌘U, ⌥⌘L, ⌘I, ⌥⌘E) and a tab clicked open and switch it. MacLook.panelWidth (400) wide: a column of its own
/// beside the page in a window 1280 wide or more, a drawer over the page's right edge below that (MacFrame.panelStyle).
/// Never modal: the page, the sidebar and the bar take their clicks while it shows.
///
/// Each tab is today's page until R3b redraws it: Queue and Info the very pages their sheet is on the iPhone, their Done
/// (and Escape) closing the panel (`inSidePanel`) rather than a sheet; Lyrics the lyrics Now Playing's face shows
/// (LyricsPanel); Info about the row selected on the page in front, else the song playing (DockInfo); the EQ the EQ page
/// of the output now on the dock's own stack (DockEQ), a shared file's preview over it. Sources is R7's: nothing draws
/// it until then. (R3's review) A tab with nothing to be about - the Queue with nothing queued, Info with nothing
/// selected and nothing playing - says "Nothing playing" in its page's place (MacDock.empty, DockEmpty).
struct MacPanel: View {
    let tab: MacDock.Tab

    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player
    @Environment(MacSelection.self) private var selection: MacSelection?

    var body: some View {
        VStack(spacing: 0) {
            MacFolderTabs(tabs: MacDock.tabs(getOpen: navigation.macGetOpen), words: MacDock.Words.tab,
                          chosen: Binding(get: { tab }, set: { (chosen: MacDock.Tab) -> Void in navigation.showPanel(chosen) }),
                          spoken: MacDock.Words.spoken)
            //? one tab's page at a time, and only the one showing: the tab chosen is the page drawn - or its words, with
            //? nothing for it to be about
            Group {
                if let words = MacDock.empty(tab, playing: player.current != nil, selected: selection?.subject != nil) {
                    DockEmpty(tab: tab, words: words)
                } else {
                    page
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.inSidePanel, true)
        .frame(width: CGFloat(MacLook.panelWidth))
        .frame(maxHeight: .infinity)
        .background(DWPalette.panel)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .upNext:
            UpNextScreen()
        case .lyrics:
            LyricsPanel()
        case .info:
            DockInfo()
        case .eq:
            DockEQ()
        case .sources:
            //? R7's MacSourcesTab: never shown until then (MacDock.tabs - no Get page says it is open)
            EmptyView()
        }
    }
}

/// (R3's review) A tab with nothing to be about (MacDock.empty): its name over its words, quiet and centred - Lyrics'
/// own "Nothing playing" (LyricsPanel's note) - and the dock's Done, so it is never a blank page with no heading.
private struct DockEmpty: View {
    let tab: MacDock.Tab
    let words: String

    var body: some View {
        NavigationStack {
            Text(words)
                .font(Typeface.body)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(MacDock.Words.tab(tab))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { DockDone() }
                }
        }
    }
}

extension EnvironmentValues {
    /// (The Mac app, slice 3) A page drawn in the desktop frame's side panel: its Done puts the panel away
    /// (AppNavigation.closePanel). False everywhere else, where Done dismisses its sheet as before.
    @Entry var inSidePanel = false
}

/// (R3) The dock's Done, on every tab's page but Queue's and Info's own (which draw theirs): the panel put away - and
/// Escape's after a field with the cursor, before the page's Edit (MacFrame.escape - one owner).
struct DockDone: View {
    var words: String = InfoWords.done

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button(words) { navigation.closePanel() }
            .escapeCloses(MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)
    }
}

/// (R3) The dock's Info (James, 24 Nov, section 7's answer 2: "Selection, else playing"): about the row selected on the
/// page in front - an album's Album info, an artist's name and Go to artist - else the song playing's Info (InfoView),
/// its heading saying which (MacDock.infoSubject, MacDock.Words.heading). The selection is MacSelection's, the page in
/// front's alone (R2's lists say theirs), so a row on a page gone from the screen is never what it shows.
private struct DockInfo: View {
    @Environment(PlayerModel.self) private var player
    @Environment(MacSelection.self) private var selection: MacSelection?

    var body: some View {
        let selected = selection?.subject
        let subject = MacDock.infoSubject(selected: selected.map(Self.kind), playing: player.current != nil)
        VStack(spacing: 0) {
            if let heading = MacDock.Words.heading(subject) {
                Text(heading)
                    .font(Typeface.Mac.text(.label).weight(.semibold))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            switch selected {
            case .album(let album)?:
                DockAlbumInfo(album: album)
                    .id(album.id)
            case .artist(let artist)?:
                DockArtistInfo(artist: artist)
                    .id(artist.id)
            case nil:
                InfoView()
            }
        }
    }

    private static func kind(_ subject: MacSelection.Subject) -> MacDock.Selected {
        switch subject {
        case .album: return .album
        case .artist: return .artist
        }
    }
}

/// The album selected: its Album info (AlbumInfoList), from what its row knew - a stub, so its own lines wait for the
/// album's answer, which it asks itself.
private struct DockAlbumInfo: View {
    let album: AlbumRoute

    var body: some View {
        NavigationStack {
            AlbumInfoList(album: Album(id: album.id, name: album.name, artist: album.artist, artistId: album.artistId,
                                       coverArt: album.coverArt, year: album.year, genre: album.genre,
                                       musicBrainzId: album.musicBrainzId, partial: true))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { DockDone(words: AlbumInfoWords.done) }
                }
        }
    }
}

/// The artist selected: their name, their albums' count where Navidrome counts them, and Go to artist.
private struct DockArtistInfo: View {
    let artist: ArtistRoute

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artist.preview?.name ?? "")
                            .font(Typeface.headline)
                        let count = ArtistWords.albumCountLine(artist.preview?.albumCount, place: "")
                        if !count.isEmpty {
                            Text(count)
                                .font(Typeface.footnote)
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Section {
                    Button(MacDock.Words.goToArtist) { navigation.open(.artist(artist)) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(InfoWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { DockDone() }
            }
        }
    }
}

/// (R3) The EQ in the dock (check 535): the EQ page of the output now, on the dock's own stack (EQSheetStack, as the
/// sheet's), its pages pushed on it, the Done at the top right of each putting the panel away (EQDoneButton). (R3's
/// review) The Mac's one EQ: a file shared to deadwax, dropped on the window or chosen in File > Import EQ File… shows
/// this tab (SharedEQFile) and its preview comes up over it as the EQ sheet's did - once the tab has been up a moment
/// (one presented as it is drawn isn't shown), over the page as it stands, Cancel's answer if it is put away; Import…
/// on the page keeps its own (EQImportRows).
private struct DockEQ: View {
    @Environment(AppNavigation.self) private var navigation
    @State private var stack = EQSheetStack()
    /// Up long enough for a sheet over it (EQSheet's wait).
    @State private var ready = false

    var body: some View {
        NavigationStack(path: $stack.path) {
            EQScreen(opened: .now)
                .navigationDestination(for: EQRoute.self) { (route: EQRoute) in
                    EQDestination(route: route)
                }
        }
        .environment(stack)
        .appSheet(isPresented: Binding<Bool>(get: {
            ready && navigation.eqImport != nil && navigation.eqImportPage == nil
        }, set: { (up: Bool) -> Void in
            // put away: Cancel's answer
            if !up { navigation.importAnswered() }
        })) {
            EQImportSheetContent()
                .macSheet()
        }
        .task { () async -> Void in
            try? await Task.sleep(for: .milliseconds(400))
            ready = true
        }
    }
}

/// Lyrics in the side panel (the web's LyricsPanel.tsx): the song playing's lines, lit and followed as on Now Playing's
/// face (LyricsView, its rules Core's); the spinner while they are asked with none in hand; a failure in a listener's
/// words with Try again; "No lyrics for this song."; "Nothing playing" with nothing queued - the panel stays when the
/// queue ends, as the web's does (MacFrame.afterQueueEnds). Lyrics are on (LyricsModel.showing) while it shows, so the
/// song's are asked as it opens and the next song's ahead, and off again as it goes.
struct LyricsPanel: View {
    @Environment(PlayerModel.self) private var player
    @Environment(LyricsModel.self) private var lyrics

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(LyricsWords.lyrics)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // (R3) the dock's Done: Escape's after a field with the cursor, before the page's Edit
                        DockDone()
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
                note(lyrics.have == .notKept ? LyricsWords.label(.notKept, device: Platform.device) : LyricsWords.noLyrics)
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
