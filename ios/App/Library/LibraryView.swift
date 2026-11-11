import DeadwaxCore
import SwiftUI

/// The Library tab's root (D2): the Albums screen of the person's scope - "Your albums" with a library of your own
/// (and, above them, All music's one row, All albums), "Albums" with logins off and for the break-glass admin.
///
/// As the tab comes into view - picked, the app back in front on it, a new person - its lists are asked again if
/// over a minute old and your library is asked for its New marks (App.tsx's libraryShown), whichever page of the
/// tab is on top: the root stays in the tab's stack under its pages, so it hears the tab and the scene change.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var shownOnce = false

    init() {}

    var body: some View {
        AlbumsScreen(scope: library.scope, root: true)
            // another scope is another screen: its own Find and its own place in the list
            .id(library.scope)
            .onAppear {
                guard !shownOnce else { return }
                shownOnce = true
                library.libraryShown()
            }
            .onChange(of: navigation.tab) { _, tab in
                if tab == .library { library.libraryShown() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, navigation.tab == .library { library.libraryShown() }
            }
            .onChange(of: server.person) { _, _ in
                library.libraryShown()
            }
            .onChange(of: server.signInOver == nil) { _, gone in
                // signed in again over the app, as the same person: what failed while signed out is asked again
                if gone { library.signedInAgain() }
            }
    }
}
