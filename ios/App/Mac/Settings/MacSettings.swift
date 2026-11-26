import DeadwaxCore
import SwiftUI

/// Settings on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Settings tab's root and the pages it pushes - Downloaded, the downloads, the server's address, Debug, the EQ's
/// pages, its sections, Change password. (R9) The root is the Mac's own Settings (MacSettingsRoot, Settings.dc.html):
/// the phone's pages as boxes, row for row; Downloaded is the Mac's column list (MacDownloadedPage, Downloaded.dc.html),
/// its Playlists the same page on its Playlists tab. The pages the root opens are the phone's, exactly as appRoutes
/// draws them - Settings > Downloads' lists among them.
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
        MacSettingsRoot()
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .downloaded: MacDownloadedPage()
        case .downloads: DownloadsScreen()
        case .downloadedPlaylists: MacDownloadedPage(tab: .playlists)
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
