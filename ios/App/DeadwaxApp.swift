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
/// runtime, and actool needs one). The web app's brand purple, and the few colours of its theme
/// (interface/styles/theme.css) the screens share, each named by its token.
enum Palette {
    static let accent = Color(red: 0xC0 / 255, green: 0x84 / 255, blue: 0xFC / 255)
    static let quiet = Color.secondary
    /// A cover's square while it loads, and where there is none.
    static let coverEmpty = Color(white: 0.16)
    /// --dw-avatar #3b3547: the avatar's round tile (the sign-in's "d", You's initial).
    static let avatar = Color(red: 0x3B / 255, green: 0x35 / 255, blue: 0x47 / 255)
    /// --dw-amber-text #fcd34d: why the sign-in is showing, You's UNVERIFIED line.
    static let amber = Color(red: 0xFC / 255, green: 0xD3 / 255, blue: 0x4D / 255)
    /// --dw-badge-amber-bg rgba(251, 191, 36, 0.14).
    static let amberFill = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255).opacity(0.14)
    /// --dw-badge-amber-border rgba(252, 211, 77, 0.3).
    static let amberEdge = Color(red: 252 / 255, green: 211 / 255, blue: 77 / 255).opacity(0.3)
    /// --dw-danger-text #fca5a5: what went wrong on the sign-in, Sign out, an Add or Remove refused.
    static let danger = Color(red: 0xFC / 255, green: 0xA5 / 255, blue: 0xA5 / 255)
    /// --dw-badge-green-text #6ee7b7: the album page's "In your library".
    static let held = Color(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255)
    /// --dw-badge-green-bg rgba(52, 211, 153, 0.14).
    static let heldFill = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255).opacity(0.14)
    /// --dw-badge-green-border rgba(110, 231, 183, 0.28).
    static let heldEdge = Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255).opacity(0.28)
}
