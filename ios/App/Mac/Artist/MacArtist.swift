import DeadwaxCore
import SwiftUI

/// An artist's page and their Top Songs on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"). R6 draws the artist's window; until then each is the phone's page, exactly as
/// appRoutes draws it.
@MainActor
enum MacArtist {
    enum Page: Hashable {
        case artist(ArtistRoute)
        case topSongs(ArtistRoute)
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .artist(let artist): ArtistView(route: artist).readableOnMac()
        case .topSongs(let artist): TopSongsScreen(route: artist).readableOnMac()
        }
    }
}
