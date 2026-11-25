import DeadwaxCore
import SwiftUI

/// The Library's pages on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"): the Library tab's root, All music's Albums and Artists, and All songs. Since R2 (notes/ios.md "The
/// redesign, slice R2: Albums and Artists, and the Library's top") Albums and Artists are the Mac's own column lists,
/// pushed and at the root alike; All songs, Playlists and Downloaded are still the phone's pages, borrowed.
@MainActor
enum MacLibrary {
    /// The Library's pages pushed on a stack (MacRoutes).
    enum Page: Hashable {
        case albums(AlbumScope)
        case artists(AlbumScope)
        case allSongs
    }

    /// The Library tab's root, its own top drawn: the phone's pager, with Albums and Artists the Mac's own pages.
    static func root() -> some View {
        LibraryView(desk: { (page: LibraryPage, scope: AlbumScope) -> MacLibraryDesk in
            MacLibraryDesk(page: page, scope: scope)
        })
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .albums(let scope): MacAlbumsPage(scope: scope)
        case .artists(let scope): MacArtistsPage(scope: scope)
        case .allSongs: SongsScreen()
        }
    }
}
