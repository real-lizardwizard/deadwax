import DeadwaxCore
import SwiftUI

/// The Mac's own routes (the Mac redesign, slice R1 - the build plan's section 1, notes/ios.md "The Mac redesign, slice
/// R1: the frame and the shared pieces"): every AppRoute's page in the desktop frame, said once - each case handed to
/// the area that owns it (`Mac<Area>.page(for:)`), so each slice redraws its own pages here and nowhere else. Until its
/// slice does, each is the phone's page exactly as appRoutes() draws it, so the iPhone's routes (MainTabs, TabStack and
/// appRoutes) are never touched for the Mac. The switch is exhaustive: a route added to AppRoute is a build error here
/// until the Mac says where it goes (tests/test_ios_mac_reach.py holds every case to it as well).
@MainActor
enum MacRoutes {
    @ViewBuilder static func page(for route: AppRoute) -> some View {
        switch route {
        // the Library's
        case .albums(let scope): MacLibrary.page(for: .albums(scope))
        case .artists(let scope): MacLibrary.page(for: .artists(scope))
        case .allSongs: MacLibrary.page(for: .allSongs)
        // an album's and a playlist's
        case .album(let album): MacAlbum.page(for: .album(album))
        case .playlist(let playlist): MacAlbum.page(for: .playlist(playlist))
        // an artist's
        case .artist(let artist): MacArtist.page(for: .artist(artist))
        case .topSongs(let artist): MacArtist.page(for: .topSongs(artist))
        // Search's: the album you don't have, a MusicBrainz artist
        case .group(let group): MacSearch.page(for: .group(group))
        case .mbArtist(let artist): MacSearch.page(for: .mbArtist(artist))
        // Settings' own
        case .downloaded: MacSettings.page(for: .downloaded)
        case .downloads: MacSettings.page(for: .downloads)
        case .downloadedPlaylists: MacSettings.page(for: .downloadedPlaylists)
        case .serverAddress: MacSettings.page(for: .serverAddress)
        case .debug: MacSettings.page(for: .debug)
        case .eq(let page): MacSettings.page(for: .eq(page))
        case .gettingAlbums: MacSettings.page(for: .gettingAlbums)
        case .playback: MacSettings.page(for: .playback)
        case .account: MacSettings.page(for: .account)
        case .thisPhone: MacSettings.page(for: .thisPhone)
        case .about: MacSettings.page(for: .about)
        case .changePassword: MacSettings.page(for: .changePassword)
        // Edit an album's folder list
        case .chooseFolder: MacEdit.page(for: .chooseFolder)
        // Manage's
        case .needsALook: MacManage.page(for: .needsALook)
        case .libraryCare: MacManage.page(for: .libraryCare)
        case .heldByNobody: MacManage.page(for: .heldByNobody)
        case .eventLog: MacManage.page(for: .eventLog)
        case .people: MacManage.page(for: .people)
        case .person(let id): MacManage.page(for: .person(id))
        case .serverSettings: MacManage.page(for: .serverSettings)
        case .serverSettingsGroup(let id): MacManage.page(for: .serverSettingsGroup(id))
        }
    }
}

extension View {
    /// Every AppRoute's page for one of the desktop frame's stacks (MacTabStack): the Mac's own (MacRoutes), each given
    /// what appRoutes() gives the phone's - room at its foot for the notice, the offline banner at its top, and iOS's tab
    /// bar kept hidden on every page.
    func macRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { (route: AppRoute) in
            MacRoutes.page(for: route)
                .clearsPlayer()
                .showsOfflineBanner()
                .toolbar(.hidden, for: .tabBar)
        }
    }
}
