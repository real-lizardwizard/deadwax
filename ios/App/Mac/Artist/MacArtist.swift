import DeadwaxCore
import SwiftUI

/// An artist's page and their Top Songs on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the
/// frame and the shared pieces"). Since R6 (notes/ios.md "The redesign, slice R6: an artist") the artist's is the
/// phone's page - its model, its asks and its leaving - drawing the Mac's own (MacArtistPage) in its ScrollView's place;
/// Top Songs is still the phone's page, exactly as appRoutes draws it (the Mac's artist page shows all ten itself) - and
/// (Last.fm, slice A2) Similar Artists' See All, the phone's grid, so a mouse reaches every tile.
@MainActor
enum MacArtist {
    enum Page: Hashable {
        case artist(ArtistRoute)
        case topSongs(ArtistRoute)
        case similarArtists(ArtistRoute)
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .artist(let artist): ArtistView(route: artist, desk: MacArtistPage.init(desk:))
        case .topSongs(let artist): TopSongsScreen(route: artist).readableOnMac()
        case .similarArtists(let artist): SimilarArtistsScreen(route: artist).readableOnMac()
        }
    }
}
