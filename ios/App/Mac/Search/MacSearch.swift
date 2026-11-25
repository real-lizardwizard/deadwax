import DeadwaxCore
import SwiftUI

/// Search on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Search tab's root, the album you don't have (Get) and a MusicBrainz artist's page. R7 redraws them; until then
/// each is the phone's page, exactly as appRoutes draws it.
@MainActor
enum MacSearch {
    enum Page: Hashable {
        case group(GroupRoute)
        case mbArtist(MBArtistRoute)
    }

    /// The Search tab's root: its field is the sidebar's on the Mac (Platform's searchField).
    static func root() -> some View {
        SearchScreen()
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .group(let group): GroupView(route: group).readableOnMac()
        case .mbArtist(let artist): MBArtistView(route: artist).readableOnMac()
        }
    }
}
