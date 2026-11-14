import DeadwaxCore
import SwiftUI

/// deadwax for iPhone (app 0.2, Phase 1's shell; Phase 2's downloads): the server and its gates, two tabs, and the
/// models every screen reads from the environment - see docs/ios.md and notes/ios.md.
///
/// The EQ (app 0.5, notes/ios-specs/eq.md): EQModel is made before the player, kept on this phone and never reset when
/// the person changes - an output's EQ is the phone's, not the account's - and handed to the player, which gives it
/// each engine it makes.
///
/// Downloads go through one background URLSession (DownloadSession), made at every launch - a background relaunch for
/// its events included, which `.backgroundTask(.urlSession(...))` holds open until the store has them, and (Phase 3,
/// slice 3) until the plan has handed over the next batch.
///
/// Your library in the background (app 0.9, phase3-autodownload.md 2.9): the app delegate registers BackgroundWork's
/// two tasks as the launch ends - SwiftUI's own background task for them is iOS 27's.
@main
struct DeadwaxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var server: ServerModel
    @State private var player: PlayerModel
    @State private var navigation: AppNavigation
    @State private var library: LibraryModel
    @State private var debug: DebugModel
    @State private var reachability: Reachability
    @State private var downloads: DownloadModel
    @State private var lyrics: LyricsModel
    @State private var eq: EQModel
    @State private var deck: DeckController
    @State private var history: HistoryModel
    @State private var playlists: PlaylistsModel

    /// The one background session, made before anything else can ask it.
    private static let downloadSession = DownloadSession()

    init() {
        let transport = URLSessionTransport()
        let server = ServerModel(transport: transport)
        let reachability = Reachability(server: server)
        transport.listen { [weak reachability] answered in reachability?.heard(answered: answered) }
        reachability.whenChanged { [weak reachability] in CoverCache.shared.reach(online: reachability?.online ?? true) }
        let files = SongFiles()
        let eq = EQModel()
        let player = PlayerModel(server: server, files: files)
        player.eq = eq
        let navigation = AppNavigation()
        let library = LibraryModel(server: server)
        // Phase 4: the person's playlists, as they are on Navidrome
        let playlists = PlaylistsModel(server: server)
        let downloads = DownloadModel(server: server, reachability: reachability, files: files, session: Self.downloadSession)
        player.connect(downloads: downloads, reachability: reachability)
        // play history (app 0.8): each song begun recorded by the player, kept and sent through the person's store
        let history = HistoryModel(server: server, reachability: reachability)
        history.downloads = downloads
        player.history = history
        // the background tasks run DownloadModel's own (slice 3): set before the delegate registers them
        BackgroundWork.shared.downloads = downloads
        let debug = DebugModel(server: server, player: player, downloads: downloads)
        let lyrics = LyricsModel(server: server, player: player, downloads: downloads, reachability: reachability)
        // the turntable's deck (turntable.md 2.1): beside the player for the app's run, as Now Playing's cover comes and goes
        let deck = DeckController(player: player, server: server, files: files, reachability: reachability, eq: eq)
        reachability.start()
        // a new person (signed out, someone else signed in, another server): nothing of the last one's kept
        server.whenPersonChanges {
            player.reset()
            navigation.reset()
            library.reset()
            debug.reset()
            lyrics.reset()
            history.reset()
            playlists.reset()
        }
        _server = State(initialValue: server)
        _player = State(initialValue: player)
        _navigation = State(initialValue: navigation)
        _library = State(initialValue: library)
        _debug = State(initialValue: debug)
        _reachability = State(initialValue: reachability)
        _downloads = State(initialValue: downloads)
        _lyrics = State(initialValue: lyrics)
        _eq = State(initialValue: eq)
        _deck = State(initialValue: deck)
        _history = State(initialValue: history)
        _playlists = State(initialValue: playlists)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(server)
                .environment(player)
                .environment(navigation)
                .environment(library)
                .environment(debug)
                .environment(reachability)
                .environment(downloads)
                .environment(lyrics)
                .environment(eq)
                .environment(deck)
                .environment(history)
                .environment(playlists)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .backgroundTask(.urlSession(DownloadSession.identifier)) {
            let began = ContinuousClock().now
            await Self.downloadSession.eventsDelivered()
            // the events and the plan after them within one budget (slice 3's review)
            await BackgroundWork.shared.eventsHandled(began: began)
        }
    }
}

/// The app delegate, for BGTaskScheduler's one rule SwiftUI can't keep before iOS 27: every task registered before the
/// launch ends (2.9).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundWork.shared.register()
        return true
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
    /// --dw-amber-icon #fbbf24: a download that didn't arrive, its mark (an amber the listener can act on).
    static let amberIcon = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)
    /// --app-pin-off 0.45, an opacity: "a pin, or an Edit button, that can't be used just now" - a song or an album not
    /// on this phone while deadwax can't be reached.
    static let off: Double = 0.45
    /// --dw-track #121117, --dw-border #2c2a36 and --dw-bar-purple (#b56af5 to #9333ea, top to bottom): the Requests
    /// board's bar (app.css .app-bar), You > Downloads' bars - a download on the phone looks like one on the web.
    /// Named `bar…`: in a music app a track is a song.
    static let barTrack = Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x17 / 255)
    static let barEdge = Color(red: 0x2C / 255, green: 0x2A / 255, blue: 0x36 / 255)
    static let barFill = LinearGradient(colors: [Color(red: 0xB5 / 255, green: 0x6A / 255, blue: 0xF5 / 255),
                                                 Color(red: 0x93 / 255, green: 0x33 / 255, blue: 0xEA / 255)],
                                        startPoint: .top, endPoint: .bottom)
    /// --dw-text-3 #8e8ea3: the EQ's 0 dB lines, and its gridlines under Increase Contrast (eq.md 3.18).
    static let textTertiary = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0xA3 / 255)
    /// --dw-accent-text #d8b4fe: the EQ curve's right ear.
    static let accentText = Color(red: 0xD8 / 255, green: 0xB4 / 255, blue: 0xFE / 255)
    /// --dw-toggled-bg rgba(168, 85, 247, 0.18): the fill under the EQ's curve, and the speed chip's face.
    static let toggledFill = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255).opacity(0.18)
    /// --dw-toggled-border: the speed chip's edge (turntable.md 5.1).
    static let toggledEdge = colour(TurntablePalette.toggledEdge)
    /// --dw-pressed rgba(255, 255, 255, 0.06): the speed chip's face under a finger (app.css .app-speed-chip:active).
    static let pressed = Color.white.opacity(0.06)

    // The turntable's look button (turntable.md 2.1, 2.14), from Core's TurntablePalette - the web's tokens' values,
    // held to theme.css there. The plinth's own colours are drawn by DeadwaxTurntable from the same table.

    /// --dw-secondary-bg, top to bottom; --dw-secondary-bg-active, the same reversed.
    static let secondaryFill = LinearGradient(colors: [colour(TurntablePalette.secondaryFillTop),
                                                       colour(TurntablePalette.secondaryFillBottom)],
                                              startPoint: .top, endPoint: .bottom)
    static let secondaryFillPressed = LinearGradient(colors: [colour(TurntablePalette.secondaryFillBottom),
                                                              colour(TurntablePalette.secondaryFillTop)],
                                                     startPoint: .top, endPoint: .bottom)
    /// --dw-secondary-border.
    static let secondaryEdge = colour(TurntablePalette.secondaryEdge)
    /// --dw-text-on-secondary: the look button's glyph.
    static let onSecondary = colour(TurntablePalette.onSecondary)
    /// --dw-highlight: a 1 pt line inside the top edge.
    static let highlight = colour(TurntablePalette.highlight)

    static func colour(_ rgba: DeckRGBA) -> Color {
        Color(.sRGB, red: Double(rgba.red) / 255, green: Double(rgba.green) / 255, blue: Double(rgba.blue) / 255,
              opacity: rgba.alpha)
    }
}
