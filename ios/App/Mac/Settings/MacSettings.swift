import DeadwaxCore
import SwiftUI

/// Settings on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Settings tab's root and the pages it pushes - Downloaded, the downloads, the server's address, Debug, the EQ's
/// pages, its sections, Change password. R9 redraws Downloaded and Settings (R3 the EQ, in the side panel); until then
/// each is the phone's page, exactly as appRoutes draws it.
@MainActor
enum MacSettings {
    enum Page: Hashable {
        case downloaded
        case downloads
        case downloadedPlaylists
        case serverAddress
        case debug
        case eq(EQRoute)
        case gettingAlbums
        case playback
        case account
        case thisPhone
        case about
        case changePassword
    }

    /// The Settings tab's root.
    static func root() -> some View {
        YouView()
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .downloaded: AlbumsScreen(list: .downloaded)
        case .downloads: DownloadsScreen()
        case .downloadedPlaylists: DownloadedPlaylistsScreen()
        case .serverAddress: ServerAddressView()
        case .debug: DebugView()
        case .eq(let page): EQDestination(route: page)
        case .gettingAlbums: GettingAlbumsPage()
        case .playback: PlaybackPage()
        case .account: AccountPage()
        case .thisPhone: ThisPhonePage()
        case .about: AboutPage()
        case .changePassword: ChangePasswordScreen()
        }
    }
}
