import DeadwaxCore
import SwiftUI

/// Search on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Search tab's root, the album you don't have (Get) and a MusicBrainz artist's page. (R7 - notes/ios.md "The
/// redesign, slice R7: Search, Get and Sources (2026-11-25)") The root is MacSearchPage (Search.dc.html's one grouped
/// table) and Get is MacGetPage (Get.dc.html), each SearchScreen's or GroupView's own model and actions drawn as the
/// Mac's (their `desk`); a MusicBrainz artist's page is still the phone's, exactly as appRoutes draws it.
@MainActor
enum MacSearch {
    enum Page: Hashable {
        case group(GroupRoute)
        case mbArtist(MBArtistRoute)
    }

    /// The Search tab's root: its field is the sidebar's on the Mac (Platform's searchField), its page the table.
    static func root() -> some View {
        SearchScreen { MacSearchPage() }
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .group(let group): GroupView(route: group) { (desk: GroupDesk) in MacGetPage(desk: desk) }
        case .mbArtist(let artist): MBArtistView(route: artist).readableOnMac()
        }
    }
}
