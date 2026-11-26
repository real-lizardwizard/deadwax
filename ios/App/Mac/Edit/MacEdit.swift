import DeadwaxCore
import SwiftUI

/// Edit an album on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"): Manage's Edit an album row's page. (R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder
/// list and Release") One page with the editor: the library's folders at its left, the album's editor and its tabs at
/// its right (MacEditWindow, Main.dc.html) - where every Edit album on the Mac opens (AppNavigation.editAlbum), never
/// the sheet.
@MainActor
enum MacEdit {
    enum Page: Hashable {
        case chooseFolder
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .chooseFolder: MacEditWindow()
        }
    }
}
