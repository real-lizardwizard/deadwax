import DeadwaxCore
import SwiftUI

/// An album's page and a playlist's on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame
/// and the shared pieces"). Since R5 (notes/ios.md "The redesign, slice R5: an album, Playlists, a playlist") each is
/// the phone's page - its model, its asks, its writes and its leaving - drawing the Mac's own (MacAlbumPage,
/// MacPlaylistPage) in its List's place; a playlist's Edit is the phone page's form.
@MainActor
enum MacAlbum {
    enum Page: Hashable {
        case album(AlbumRoute)
        case playlist(PlaylistRoute)
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        // by its id: a page moved to an album's new id is that album's page afresh (appRoutes' own)
        case .album(let album): AlbumView(route: album, desk: MacAlbumPage.init(desk:)).id(album.id)
        case .playlist(let playlist): PlaylistView(route: playlist, desk: MacPlaylistPage.init(desk:))
        }
    }
}
