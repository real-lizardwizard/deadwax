import DeadwaxCore
import Observation
import SwiftUI

/// The app's two tabs (D1): Library and You.
enum AppTab: Hashable {
    case library
    case you
}

/// A page pushed on a tab's NavigationStack. Every page the parts add is a case here, drawn in `appRoutes()`.
enum AppRoute: Hashable {
    /// An album's page, by Navidrome's album id (with what the list knew, to draw before it loads).
    case album(AlbumRoute)
    /// An Albums screen of a scope, pushed: All music's All albums (the store's), over Your albums - and, while the root
    /// is Downloaded, the root's own row back to your albums.
    case albums(AlbumScope)
    /// The Library's Downloaded (Phase 2): every album on this phone, as an Albums screen.
    case downloaded
    /// You > Downloads (Phase 2): what's on this phone, the two settings, what's on its way and what didn't arrive.
    case downloads
    /// You's This phone > Server: the Server address screen, pushed.
    case serverAddress
    /// You's Debug (admins only).
    case debug
    /// You > Playback > EQ, and the EQ's own pages (eq.md 3.1-3.2): the EQ page, an output's, the presets.
    case eq(EQRoute)
    /// The Library's Playlists (Phase 4, phase4-library.md 3.2): yours, shared with you, from files.
    case playlists
    /// One playlist's page (3.3), by Navidrome's playlist id.
    case playlist(PlaylistRoute)
    /// (Phase 4, slice 3) The playlists downloaded to this phone - reached from Downloaded.
    case downloadedPlaylists
}

/// A playlist page's address: its id, and the row that opened it - the hero drawn at once while the playlist loads.
/// Only `id` decides which playlist.
struct PlaylistRoute: Hashable {
    let id: String
    var preview: Playlist?

    init(id: String, preview: Playlist? = nil) {
        self.id = id
        self.preview = preview
    }

    /// A row of the Playlists screen.
    init(_ playlist: Playlist) {
        self.init(id: playlist.id, preview: playlist)
    }
}

/// The album page's address: the album's id, and what the row that opened it already knew - drawn at once, while
/// the album loads (screens.md's album page). Only `id` decides which album; the rest is a head start.
struct AlbumRoute: Hashable {
    let id: String
    var name: String?
    var artist: String?
    var coverArt: String?
    var year: Int?
    /// The album's genre, as the opener knew it: the meta line's first part before the album answers (AlbumPage.tsx's
    /// `[shown?.genre, shown?.year, format]`, shown = album ?? preview), so the line only gains the format when it does.
    var genre: String?
    /// The album's MusicBrainz release id, as the opener knew it: what the page tells your library it opened with
    /// (MyLibraryState.opened - the web's preview's musicBrainzId).
    var musicBrainzId: String?

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil, year: Int? = nil,
         genre: String? = nil, musicBrainzId: String? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.coverArt = coverArt
        self.year = year
        self.genre = genre
        self.musicBrainzId = musicBrainzId
    }

    /// A Library row's album.
    init(_ album: IndexAlbum) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year,
                  genre: album.genre, musicBrainzId: album.musicBrainzId)
    }

    /// An album already loaded.
    init(_ album: Album) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year,
                  genre: album.genre, musicBrainzId: album.musicBrainzId)
    }

    /// A queue entry's album (Now Playing's Go to the album, Info's album line); nil when the track names none.
    init?(track: QueueTrack) {
        guard let id = track.albumId, !id.isEmpty else { return nil }
        self.init(id: id, name: track.album, artist: track.artist, coverArt: track.coverArt)
    }
}

/// Where the app is: the tab shown, each tab's pages, and Now Playing open or not. RootView and MainTabs draw it;
/// a screen opens a page on its own tab with `open(_:)`, and the player goes to an album with `openAlbum(_:)` - on the
/// tab shown, as a screen's page would be.
@MainActor
@Observable
final class AppNavigation {
    /// The tab shown.
    private(set) var tab: AppTab = .library
    /// The Library tab's pages, root first left out.
    var library: [AppRoute] = []
    /// The You tab's pages.
    var you: [AppRoute] = []
    /// Now Playing is open (a full-screen cover over the tabs).
    var nowPlayingShown = false
    /// One more each time a tab already at its root is tapped again: its root list scrolls to the top.
    private(set) var libraryScrollToTop = 0
    private(set) var youScrollToTop = 0

    /// An EQ import's preview (eq.md 3.9), one at a time: a file shared to deadwax, or one an EQ page read from Files or
    /// the clipboard. A second arriving while a preview is up takes its place there.
    private(set) var eqImport: EQImportItem?
    /// The EQ page whose own preview shows it (its import from Files or Paste) - nil: the EQ sheet's, for a shared
    /// file.
    private(set) var eqImportPage: UUID?
    /// The EQ sheet over the tabs, opened for a shared file - over Now Playing, Now Playing opens its own.
    var eqImportSheet = false
    /// A preview is drawn (EQImportSheetContent says so).
    var eqPreviewUp = false
    /// Add to a playlist (Phase 4, slice 2), opened from a page's ••• (QueueMenu): the picker over the tabs, with the
    /// songs in hand. Now Playing opens its own, over itself.
    var playlistPick: PlaylistPickRequest?
    /// The playlist whose Edit is open on a tab's page: the tab tapped again goes back no further than that page, so
    /// Edit's changes are never thrown away without Cancel's question (PlaylistEdit.pagesKept).
    private(set) var editingPlaylist: String?

    /// A file shared to deadwax (`.onOpenURL`): shown by the preview that is up, in place - else by the EQ sheet,
    /// opened over Now Playing (by Now Playing) or over the tabs (here).
    func share(_ item: EQImportItem) {
        eqImport = item
        guard !eqPreviewUp else { return }
        eqImportPage = nil
        if !nowPlayingShown { eqImportSheet = true }
    }

    /// An EQ page's own import (Files, Paste): its preview, over that page.
    func importOnPage(_ page: UUID, _ item: EQImportItem) {
        eqImportPage = page
        eqImport = item
    }

    /// The preview answered - Import, Cancel, Done - or gone with what it showed.
    func importAnswered(_ id: UUID? = nil) {
        guard id == nil || eqImport?.id == id else { return }
        eqImport = nil
        eqImportPage = nil
    }

    /// A tab tapped. The tab already shown: back to its root - and, at its root already, to the top of its list.
    func select(_ tapped: AppTab) {
        guard tapped == tab else {
            tab = tapped
            return
        }
        switch tapped {
        case .library:
            if library.isEmpty { libraryScrollToTop += 1 } else { backToRoot(&library) }
        case .you:
            if you.isEmpty { youScrollToTop += 1 } else { backToRoot(&you) }
        }
    }

    /// Every page popped - but none of a playlist being edited, nor the pages under it.
    private func backToRoot(_ stack: inout [AppRoute]) {
        let ids = stack.map { (route: AppRoute) -> String? in
            if case .playlist(let shown) = route { return shown.id }
            return nil
        }
        let kept = PlaylistEdit.pagesKept(ids, editing: editingPlaylist)
        stack.removeLast(stack.count - kept)
    }

    /// A playlist's page opened or closed its Edit.
    func editing(_ id: String, _ open: Bool) {
        if open {
            editingPlaylist = id
        } else if editingPlaylist == id {
            editingPlaylist = nil
        }
    }

    /// A playlist's page went away: popped (no page of it left on either tab), its Edit with it.
    func pageGone(_ id: String) {
        guard editingPlaylist == id else { return }
        let held = (library + you).contains { (route: AppRoute) -> Bool in
            if case .playlist(let shown) = route { return shown.id == id }
            return false
        }
        if !held { editingPlaylist = nil }
    }

    /// `route` pushed on the tab shown.
    func open(_ route: AppRoute) {
        switch tab {
        case .library: library.append(route)
        case .you: you.append(route)
        }
    }

    /// Go to album, from the player (Now Playing's byline and •••, Info's album card): Now Playing closes - Info and
    /// Up Next with it - and the album's page is pushed on the tab shown, its pages kept (screens.md 7, the web's
    /// goToAlbum: "opens the album page on the current tab"). An album already on top of it isn't pushed twice.
    func openAlbum(_ album: AlbumRoute) {
        nowPlayingShown = false
        let top = tab == .library ? library.last : you.last
        if case .album(let shown)? = top, shown.id == album.id { return }
        open(.album(album))
    }

    /// A playlist's page gone from the top of the tab shown (deleted on it, Phase 4 slice 2) - only while it is still
    /// what shows: a delete answering after another page was opened over it pops nothing (App.tsx playlistDeleted).
    func leavePlaylist(_ id: String) {
        switch tab {
        case .library:
            if case .playlist(let shown)? = library.last, shown.id == id { library.removeLast() }
        case .you:
            if case .playlist(let shown)? = you.last, shown.id == id { you.removeLast() }
        }
    }

    /// Back to the EQ page a page was pushed from ("Use for …", eq.md 3.7): every page over the topmost EQ page on the
    /// tab shown popped at once. Nothing when the tab holds no EQ page.
    func backToEQPage() {
        func popped(_ stack: inout [AppRoute]) {
            guard let page = stack.lastIndex(where: { (route: AppRoute) -> Bool in
                if case .eq(let eq) = route { return eq.isPage }
                return false
            }) else { return }
            stack.removeSubrange((page + 1)...)
        }
        switch tab {
        case .library: popped(&library)
        case .you: popped(&you)
        }
    }

    /// The person changed: every page popped, Now Playing closed, Library shown.
    func reset() {
        library.removeAll()
        you.removeAll()
        nowPlayingShown = false
        eqImportSheet = false
        playlistPick = nil
        editingPlaylist = nil
        importAnswered()
        tab = .library
    }
}

extension View {
    /// Every AppRoute's page, for a tab's NavigationStack - each given room at its foot for the player over it
    /// (`clearsPlayer()`, MainTabs.swift), and the offline banner at its top (`showsOfflineBanner()`).
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            Group {
                switch route {
                case .album(let album): AlbumView(route: album)
                case .albums(let scope): AlbumsScreen(scope: scope, root: false)
                case .downloaded: AlbumsScreen(list: .downloaded, root: false)
                case .downloads: DownloadsScreen()
                case .serverAddress: ServerAddressView()
                case .debug: DebugView()
                case .eq(let page): EQDestination(route: page)
                case .playlists: PlaylistsScreen()
                case .playlist(let playlist): PlaylistView(route: playlist)
                case .downloadedPlaylists: DownloadedPlaylistsScreen()
                }
            }
            .clearsPlayer()
            .showsOfflineBanner()
        }
    }
}
