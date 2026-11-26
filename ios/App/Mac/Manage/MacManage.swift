import DeadwaxCore
import SwiftUI

/// Manage's pages on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"): Needs a look (R12), Library care and In nobody's library, the event log (R13), People, a person, Server
/// settings and a group of them (R14). Until each slice redraws its page, each is the phone's, at the readable width
/// exactly as appRoutes draws it. (R13) Library care and the event log are the Mac's own pages; In nobody's library is
/// drawn in Library care's boxes, so its route opens Library care.
@MainActor
enum MacManage {
    enum Page: Hashable {
        case needsALook
        case libraryCare
        case heldByNobody
        case eventLog
        case people
        case person(String)
        case serverSettings
        case serverSettingsGroup(String)
    }

    @ViewBuilder static func page(for page: Page) -> some View {
        switch page {
        case .needsALook: NeedsLookScreen().readableOnMac()
        case .libraryCare: MacLibraryCarePage()
        case .heldByNobody: MacLibraryCarePage()
        case .eventLog: MacEventLogPage()
        case .people: PeopleScreen().readableOnMac()
        case .person(let id): PersonScreen(id: id).readableOnMac()
        case .serverSettings: ServerSettingsScreen().readableOnMac()
        case .serverSettingsGroup(let id): ServerSettingsGroupScreen(id: id).readableOnMac()
        }
    }
}
