import DeadwaxCore
import SwiftUI

/// Edit an album on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"): Manage's Edit an album row's folder list. R10 makes it one page with the editor - the folder list beside
/// the editor's tabs; until then it is the phone's, exactly as appRoutes draws it, and the editor is still the sheet
/// DesktopFrame presents (EditAlbumSheet, the phone's).
@MainActor
enum MacEdit {
    enum Page: Hashable {
        case chooseFolder
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .chooseFolder: ChooseFolderScreen().readableOnMac()
        }
    }
}
