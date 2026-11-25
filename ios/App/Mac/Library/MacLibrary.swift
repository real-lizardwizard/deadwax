import DeadwaxCore
import SwiftUI

/// The Library's pages on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"): the Library tab's root, All music's Albums and Artists, and All songs. R2 draws Albums and Artists as column
/// lists; until then each is the phone's page, exactly as appRoutes draws it.
@MainActor
enum MacLibrary {
    /// The Library's pages pushed on a stack (MacRoutes).
    enum Page: Hashable {
        case albums(AlbumScope)
        case artists(AlbumScope)
        case allSongs
    }

    /// The Library tab's root, its own top drawn (the switch and its •••).
    static func root() -> some View {
        LibraryView()
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .albums(let scope): AlbumsScreen(scope: scope)
        case .artists(let scope): ArtistsScreen(scope: scope)
        case .allSongs: SongsScreen()
        }
    }
}
