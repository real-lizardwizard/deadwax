import DeadwaxCore
import SwiftUI

/// An album's page and a playlist's on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame
/// and the shared pieces"). R5 redraws them; until then each is the phone's page, exactly as appRoutes draws it.
@MainActor
enum MacAlbum {
    enum Page: Hashable {
        case album(AlbumRoute)
        case playlist(PlaylistRoute)
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        // by its id: a page moved to an album's new id is that album's page afresh (appRoutes' own)
        case .album(let album): AlbumView(route: album).id(album.id).readableOnMac()
        case .playlist(let playlist): PlaylistView(route: playlist)
        }
    }
}
