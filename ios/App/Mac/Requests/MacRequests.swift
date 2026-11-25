import DeadwaxCore
import SwiftUI

/// Requests on the Mac (the Mac redesign - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the Requests tab's root, which pushes nothing of its own. R8 redraws it; until then it is the phone's page.
@MainActor
enum MacRequests {
    static func root() -> some View {
        RequestsScreen()
    }
}
