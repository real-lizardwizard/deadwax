import DeadwaxCore
import SwiftUI

/// Requests on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Requests tab's root, which pushes nothing of its own. Since R8 (notes/ios.md "The redesign, slice R8: Requests")
/// the Mac's own page, the table Requests.dc.html draws - the phone's is RequestsScreen.
@MainActor
enum MacRequests {
    static func root() -> some View {
        MacRequestsPage()
    }
}
