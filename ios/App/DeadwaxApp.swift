import SwiftUI

/// deadwax for iPhone (app 0.2, Phase 1's shell): the server and its gates, two tabs, and the models every screen
/// reads from the environment - see docs/ios.md and notes/ios.md.
@main
struct DeadwaxApp: App {
    @State private var server: ServerModel
    @State private var player: PlayerModel
    @State private var navigation: AppNavigation
    @State private var library: LibraryModel
    @State private var debug: DebugModel

    init() {
        let server = ServerModel()
        let files = SongFiles()
        let player = PlayerModel(server: server, files: files)
        let navigation = AppNavigation()
        let library = LibraryModel(server: server)
        let debug = DebugModel(server: server, player: player, files: files)
        // a new person (signed out, someone else signed in, another server): nothing of the last one's kept
        server.whenPersonChanges {
            player.reset()
            navigation.reset()
            library.reset()
            debug.reset()
        }
        _server = State(initialValue: server)
        _player = State(initialValue: player)
        _navigation = State(initialValue: navigation)
        _library = State(initialValue: library)
        _debug = State(initialValue: debug)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(server)
                .environment(player)
                .environment(navigation)
                .environment(library)
                .environment(debug)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
    }
}

/// The app's few colours, in code: there is no asset catalog (James's Mac has no Simulator
/// runtime, and actool needs one). The web app's brand purple and its page black.
enum Palette {
    static let accent = Color(red: 0xC0 / 255, green: 0x84 / 255, blue: 0xFC / 255)
    static let quiet = Color.secondary
    /// A cover's square while it loads, and where there is none.
    static let coverEmpty = Color(white: 0.16)
}
