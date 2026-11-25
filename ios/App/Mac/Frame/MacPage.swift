import DeadwaxCore
import SwiftUI

/// A redesigned page's frame (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the
/// shared pieces"): its toolbar across the top (MacToolbar - its buttons the page's •••'s own items), the page under it
/// on the window's ground. Each slice from R2 draws its pages in one; the status bar under them is the frame's
/// (`.macStatus(_:)`).
struct MacPage<Tools: View, Content: View>: View {
    @ViewBuilder let tools: Tools
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            MacToolbar { tools }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MacPalette.bg)
    }
}

/// The title strip's words and the window's name (MacTitleStrip, Platform.nameWindow): the page in front, as the design
/// canvas titles each window - "Albums", "Back in Black", "AC/DC", "Requests", "Settings".
///
/// - A page pushed on top by its name, while the page knows it: an album's, an artist's, a playlist's, the album you
///   don't have, a MusicBrainz artist. A playlist's is the playlists list's as it is now (PlaylistsModel's, asked again
///   after every write), the route's preview only until the list has it - so a rename in Edit renames the window.
/// - Otherwise the sidebar's row for where the app is (MacSidebar.current - the Library's page its switch shows, a Manage
///   page, Requests, Settings; a playlist's row its name in the list).
/// - Otherwise - Search, which has no row - the tab's own name.
@MainActor
enum MacTitle {
    static func title(_ navigation: AppNavigation, personal: Bool, savedOrder: String, playlists: [Playlist]?) -> String {
        let order = LibraryPages.shown(LibraryPages.read(savedOrder), personal: personal)
        let at = navigation.macWhere(page: navigation.macLibraryPage ?? LibraryPages.first(order))
        let listed = MacSidebar.playlists(playlists)
        let row = MacSidebar.current(at, listed: listed.map(\.id))
        return title(navigation.shownStack.last, row: row, playlists: playlists ?? [], tab: navigation.tab)
    }

    /// `playlists`: the whole list as it is now, for a playlist's name.
    static func title(_ top: AppRoute?, row: MacSidebar.Row?, playlists: [Playlist], tab: AppTab) -> String {
        if let top, let name = named(top, playlists: playlists) { return name }
        switch row {
        case .playlist(let id)?:
            return playlists.first { (playlist: Playlist) -> Bool in playlist.id == id }?.name ?? MacSidebar.label(.playlists)
        case let row?:
            return MacSidebar.label(row)
        case nil:
            return tab.title
        }
    }

    /// A pushed page's own name, while it is known - none for a page named by where it is. A playlist's from
    /// `playlists`, the list as it is now, before the route's preview (the list as it was when the row was tapped).
    static func named(_ route: AppRoute, playlists: [Playlist]) -> String? {
        let name: String?
        switch route {
        case .album(let album): name = album.name
        case .artist(let artist): name = artist.preview?.name
        case .playlist(let playlist):
            name = playlists.first { (listed: Playlist) -> Bool in listed.id == playlist.id }?.name ?? playlist.preview?.name
        case .group(let group): name = group.title ?? group.preview?.title
        case .mbArtist(let artist): name = artist.name
        default: name = nil
        }
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return name
    }
}
