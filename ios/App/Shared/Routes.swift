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
    /// You's This phone > Server: the Server address screen, pushed.
    case serverAddress
    /// You's Debug (admins only).
    case debug
}

/// The album page's address: the album's id, and what the row that opened it already knew - drawn at once, while
/// the album loads (screens.md's album page). Only `id` decides which album; the rest is a head start.
struct AlbumRoute: Hashable {
    let id: String
    var name: String?
    var artist: String?
    var coverArt: String?
    var year: Int?

    init(id: String, name: String? = nil, artist: String? = nil, coverArt: String? = nil, year: Int? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.coverArt = coverArt
        self.year = year
    }

    /// A Library row's album.
    init(_ album: IndexAlbum) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year)
    }

    /// An album already loaded.
    init(_ album: Album) {
        self.init(id: album.id, name: album.name, artist: album.artist, coverArt: album.coverArt, year: album.year)
    }

    /// A queue entry's album (Now Playing's Go to the album, Info's album line); nil when the track names none.
    init?(track: QueueTrack) {
        guard let id = track.albumId, !id.isEmpty else { return nil }
        self.init(id: id, name: track.album, artist: track.artist, coverArt: track.coverArt)
    }
}

/// Where the app is: the tab shown, each tab's pages, and Now Playing open or not. RootView and MainTabs draw it;
/// any screen opens a page with `open(_:)` or `openAlbum(_:)`.
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

    /// A tab tapped. The tab already shown: back to its root - and, at its root already, to the top of its list.
    func select(_ tapped: AppTab) {
        guard tapped == tab else {
            tab = tapped
            return
        }
        switch tapped {
        case .library:
            if library.isEmpty { libraryScrollToTop += 1 } else { library.removeAll() }
        case .you:
            if you.isEmpty { youScrollToTop += 1 } else { you.removeAll() }
        }
    }

    /// `route` pushed on the tab shown.
    func open(_ route: AppRoute) {
        switch tab {
        case .library: library.append(route)
        case .you: you.append(route)
        }
    }

    /// An album's page pushed on the tab shown, closing Now Playing first (Go to the album).
    func openAlbum(_ album: AlbumRoute) {
        nowPlayingShown = false
        open(.album(album))
    }

    /// The tab shown back at its root.
    func popToRoot() {
        switch tab {
        case .library: library.removeAll()
        case .you: you.removeAll()
        }
    }

    /// The person changed: every page popped, Now Playing closed, Library shown.
    func reset() {
        library.removeAll()
        you.removeAll()
        nowPlayingShown = false
        tab = .library
    }
}

extension View {
    /// Every AppRoute's page, for a tab's NavigationStack.
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .album(let album): AlbumView(route: album)
            case .serverAddress: ServerAddressView()
            case .debug: DebugView()
            }
        }
    }
}
