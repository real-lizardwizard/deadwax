import Foundation

// The Mac's menus and keys (the Mac app's plan 1.3; notes/ios.md "The Mac app, slice 2: menus, keys, right-click and the
// window"): what deadwax adds to the menu bar - Settings… in the app's menu, Find in Edit, Refresh in View, and the
// Controls menu - each item's words, its shortcut and whether it can be used now, from the player's state and the
// window's. The App draws these and nothing else (ios/App/Shared/MacCommands.swift); every rule is here, tested on
// Linux. The words are the app's own where it has them, never retyped: Play/Pause, Next and Previous the player's;
// Shuffle the name of Now Playing's Shuffle button (shuffleLabel - "Shuffle - shuffling your whole library", or "...all
// music", during a library's shuffle); the Repeat submenu the Repeat button's name with Repeat off (repeatLabel), and its
// three items what Up Next says to VoiceOver as Repeat changes (UpNextWords.repeatSaid: "Repeat off", "Repeat all",
// "Repeat one"); Refresh the Library's •••'s; Settings the tab's. Forward 10 Seconds, Back 10 Seconds and Go to Current
// Song are the Mac's own, as Music names them.
//
// (Slice 3, notes/ios.md "The Mac app, slice 3: the desktop frame") And the View menu's frame: Show Sidebar or Hide
// Sidebar (⌃⌘S, the Mac's own words for it), and the three side panels - Up Next (⌥⌘U), Lyrics (⌥⌘L) and Info (⌘I),
// each ticked while it shows, one at a time (MacFrame.toggled) - named as the panels are.
//
// (Slice 6, notes/ios.md "The Mac app, slice 6: EQ files") And File's Import EQ File… (⌘O): the Mac's Open panel, a
// plain-text file whose EQ shows in its preview - the way a file opened with deadwax comes. From the pages alone, as
// Settings… and Find: not over the sign-in, and not over a sheet (the panel is the window's own, and a sheet is already
// up in front of it).

public enum MacMenu {
    /// What the menus are drawn from - read by the App each time it draws them.
    public struct State: Sendable, Equatable {
        /// Something is queued (the mini player shows): every Controls item is dimmed without it.
        public var queued: Bool
        /// The player means to play (playing, or loading to play): Play/Pause says Pause.
        public var playing: Bool
        /// Shuffle is on for this queue.
        public var shuffle: Bool
        /// A whole library's shuffle, whose order IS the shuffle: Shuffle stays on and can't be turned off.
        public var paged: PagedScope?
        /// The device's Repeat.
        public var repeatMode: Repeat
        /// The song's length in seconds; 0 while it isn't known - nothing to skip within.
        public var length: Double
        /// The song playing names its album: Go to Current Song can open it.
        public var hasAlbum: Bool
        /// A text field has the cursor: the keys that type or move it there are the field's (Space, ⌘→, ⌘←).
        public var typing: Bool
        /// The app's tabs are drawn - signed in, the sign-in not over them: Settings…, Find and Refresh go there.
        public var tabs: Bool
        /// The page shown can be asked again (a pull to refresh on the phone, or its •••'s Refresh), and whether one is
        /// on its way.
        public var refresh: Refresh
        /// Now Playing is over the pages: what shows is the player, which has nothing to refresh - the page under it isn't
        /// asked again unseen.
        public var nowPlaying: Bool
        /// A sheet is up (Edit album, Up Next, Add to a playlist…, any of them): the page under it is out of reach - it
        /// isn't refreshed unseen, and Settings…, Find and Go to Current Song don't change the tab under the sheet.
        public var sheet: Bool
        /// (Slice 3) The sidebar is shown: the View menu's item says Hide Sidebar.
        public var sidebarShown: Bool
        /// (Slice 3) The side panel showing.
        public var panel: MacFrame.Panel
        /// (Slice 3) What is known of the song playing's lyrics: Lyrics is dimmed while it is known there are none to
        /// open, as the bar's button is (Lyrics.dimmed).
        public var lyrics: LyricsHave

        public init(queued: Bool = false, playing: Bool = false, shuffle: Bool = false, paged: PagedScope? = nil,
                    repeatMode: Repeat = .off, length: Double = 0, hasAlbum: Bool = false, typing: Bool = false,
                    tabs: Bool = true, refresh: Refresh = .none, nowPlaying: Bool = false, sheet: Bool = false,
                    sidebarShown: Bool = true, panel: MacFrame.Panel = .none, lyrics: LyricsHave = .unknown) {
            self.queued = queued
            self.playing = playing
            self.shuffle = shuffle
            self.paged = paged
            self.repeatMode = repeatMode
            self.length = length
            self.hasAlbum = hasAlbum
            self.typing = typing
            self.tabs = tabs
            self.refresh = refresh
            self.nowPlaying = nowPlaying
            self.sheet = sheet
            self.sidebarShown = sidebarShown
            self.panel = panel
            self.lyrics = lyrics
        }
    }

    /// The page shown's Refresh: none on this page, ready, or one on its way (a second waits for it).
    public enum Refresh: Sendable, Equatable {
        case none, ready, running
    }

    /// What each item does - one each, so no two share a key.
    public enum Command: String, Sendable, CaseIterable {
        case settings, find, refresh
        case playPause, next, previous, forward, back
        case shuffle, repeatOff, repeatAll, repeatOne
        case goToCurrentSong
        case sidebar, upNext, lyrics, info
        // (slice 6) File's
        case importEQFile

        /// (Slice 3) The View menu's three panels, in the bar's order (Lyrics, Up Next, then Info from its •••).
        public static let panels: [Command] = [.upNext, .lyrics, .info]

        /// The panel this item shows - nil for every other.
        public var panel: MacFrame.Panel? {
            switch self {
            case .upNext: return .upNext
            case .lyrics: return .lyrics
            case .info: return .info
            default: return nil
            }
        }

        /// Repeat's three, in Up Next's order (off, all, one).
        public static let repeats: [Command] = [.repeatOff, .repeatAll, .repeatOne]

        /// The Repeat this item sets - nil for every other.
        public var repeatMode: Repeat? {
            switch self {
            case .repeatOff: return .off
            case .repeatAll: return .all
            case .repeatOne: return .one
            default: return nil
            }
        }
    }

    /// A key a shortcut presses.
    public enum Key: Sendable, Equatable {
        case character(Character)
        case space
        case rightArrow
        case leftArrow

        /// How the menu writes it.
        public var said: String {
            switch self {
            case .character(let character): return String(character).uppercased()
            case .space: return "Space"
            case .rightArrow: return "\u{2192}"
            case .leftArrow: return "\u{2190}"
            }
        }
    }

    /// The keys held with it.
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)

        /// As the Mac writes them, in its order: ⌃⌥⇧⌘.
        public var said: String {
            var out = ""
            if contains(.control) { out += "\u{2303}" }
            if contains(.option) { out += "\u{2325}" }
            if contains(.shift) { out += "\u{21E7}" }
            if contains(.command) { out += "\u{2318}" }
            return out
        }
    }

    public struct Shortcut: Sendable, Equatable {
        public let key: Key
        public let modifiers: Modifiers

        public init(_ key: Key, _ modifiers: Modifiers = []) {
            self.key = key
            self.modifiers = modifiers
        }

        /// "⌥⌘→", "⌘,", "Space".
        public var said: String { modifiers.said + key.said }
    }

    /// One menu item as it is drawn now.
    public struct Item: Sendable, Equatable {
        public let command: Command
        public let words: String
        /// nil: no key - none of its own, or a field has the cursor and the key is the field's.
        public let shortcut: Shortcut?
        public let enabled: Bool
        /// Shuffle while it's on, the Repeat that's set: ticked.
        public let ticked: Bool
    }

    /// The Mac's own words - the ones the app hadn't got.
    public enum Words {
        /// The menu Play/Pause, Next, Previous, the skips, Shuffle, Repeat and Go to Current Song are in.
        public static let controls = "Controls"
        public static let forward = "Forward \(Int(MacMenu.skipSeconds)) Seconds"
        public static let back = "Back \(Int(MacMenu.skipSeconds)) Seconds"
        public static let goToCurrentSong = "Go to Current Song"
        /// Edit > Find: the cursor in Search's field.
        public static let find = "Find"
        /// The app menu's: the Settings tab - the tab's own name, an ellipsis as the Mac writes an item that opens a place.
        public static let settings = "\(YouWords.title)\u{2026}"
        /// The submenu Repeat's three are in: Repeat's own word when it's off.
        public static let repeatMenu = repeatLabel(.off)
        /// (Slice 3) The View menu's sidebar item, as every Mac app words it.
        public static let showSidebar = "Show Sidebar"
        public static let hideSidebar = "Hide Sidebar"
        /// (Slice 6) File's: the Open panel, for an EQ file - an ellipsis, as the Mac writes an item that opens a panel.
        public static let importEQFile = "Import EQ File\u{2026}"
    }

    /// How far Forward and Back move, in seconds.
    public static let skipSeconds = 10.0

    /// Each command's key - before a field takes it.
    public static func key(_ command: Command) -> Shortcut? {
        switch command {
        case .settings: return Shortcut(.character(","), .command)
        case .find: return Shortcut(.character("f"), .command)
        case .refresh: return Shortcut(.character("r"), .command)
        case .playPause: return Shortcut(.space)
        case .next: return Shortcut(.rightArrow, .command)
        case .previous: return Shortcut(.leftArrow, .command)
        case .forward: return Shortcut(.rightArrow, [.option, .command])
        case .back: return Shortcut(.leftArrow, [.option, .command])
        case .goToCurrentSong: return Shortcut(.character("l"), .command)
        case .sidebar: return Shortcut(.character("s"), [.control, .command])
        case .upNext: return Shortcut(.character("u"), [.option, .command])
        case .lyrics: return Shortcut(.character("l"), [.option, .command])
        case .info: return Shortcut(.character("i"), .command)
        case .importEQFile: return Shortcut(.character("o"), .command)
        case .shuffle, .repeatOff, .repeatAll, .repeatOne: return nil
        }
    }

    /// The keys a text field has its own use for while it has the cursor: Space types a space, ⌘→ and ⌘← go to the
    /// line's end and start. Taken off their items meanwhile, so a field never plays, pauses or skips.
    public static func yieldsToTyping(_ command: Command) -> Bool {
        command == .playPause || command == .next || command == .previous
    }

    /// One item, as it is now.
    public static func item(_ command: Command, _ state: State) -> Item {
        let shortcut = state.typing && yieldsToTyping(command) ? nil : key(command)
        return Item(command: command, words: words(command, state), shortcut: shortcut,
                    enabled: enabled(command, state), ticked: ticked(command, state))
    }

    /// The Controls menu, its sections in order: Play/Pause, Next, Previous; the skips; Shuffle and Repeat's three
    /// (drawn in Repeat's submenu); Go to Current Song.
    public static func controls(_ state: State) -> [[Item]] {
        [[.playPause, .next, .previous], [.forward, .back], [.shuffle] + Command.repeats, [.goToCurrentSong]]
            .map { $0.map { item($0, state) } }
    }

    /// (Slice 3) The View menu's frame, its sections in order: the sidebar; the three panels.
    public static func view(_ state: State) -> [[Item]] {
        [[.sidebar], Command.panels].map { $0.map { item($0, state) } }
    }

    /// Where Forward or Back goes from `from` in a song `length` long: kept within the song - nil for any other
    /// command, and with no length known.
    public static func skip(_ command: Command, from: Double, length: Double) -> Double? {
        guard length > 0 else { return nil }
        switch command {
        case .forward: return Scrub.clamp(Scrub.clamp(from, length) + skipSeconds, length)
        case .back: return Scrub.clamp(Scrub.clamp(from, length) - skipSeconds, length)
        default: return nil
        }
    }

    static func words(_ command: Command, _ state: State) -> String {
        switch command {
        case .settings: return Words.settings
        case .find: return Words.find
        case .refresh: return LibrarySwitchWords.refresh
        case .playPause: return PlayerWords.playPause(playing: state.queued && state.playing)
        case .next: return PlayerWords.next
        case .previous: return NowPlayingWords.previous
        case .forward: return Words.forward
        case .back: return Words.back
        case .shuffle: return shuffleLabel(state.paged)
        case .repeatOff, .repeatAll, .repeatOne: return UpNextWords.repeatSaid(command.repeatMode ?? .off)
        case .goToCurrentSong: return Words.goToCurrentSong
        case .sidebar: return state.sidebarShown ? Words.hideSidebar : Words.showSidebar
        case .upNext: return UpNextWords.title
        case .lyrics: return LyricsWords.lyrics
        case .info: return InfoWords.title
        case .importEQFile: return Words.importEQFile
        }
    }

    static func enabled(_ command: Command, _ state: State) -> Bool {
        switch command {
        case .settings, .find: return state.tabs && !state.sheet
        case .refresh: return state.tabs && !state.nowPlaying && !state.sheet && state.refresh == .ready
        case .playPause, .next, .previous: return state.queued
        case .forward, .back: return state.queued && state.length > 0
        //? as Now Playing's Shuffle: a library's shuffle can't be turned off
        case .shuffle: return state.queued && state.paged == nil
        case .repeatOff, .repeatAll, .repeatOne: return state.queued
        case .goToCurrentSong: return state.tabs && !state.sheet && state.queued && state.hasAlbum
        //? (slice 3) the frame's: with the tabs drawn and no sheet over them - a panel open can always be put away, and
        //? one closed opens with something queued (Lyrics not while it is known the song has none)
        case .sidebar: return state.tabs && !state.sheet
        case .upNext, .info: return state.tabs && !state.sheet && (state.queued || state.panel == command.panel)
        case .lyrics:
            return state.tabs && !state.sheet
                && (state.panel == .lyrics || (state.queued && !Lyrics.dimmed(state.lyrics, on: false)))
        //? (slice 6) as Settings… and Find: the pages in front - never over the sign-in, and never over a sheet, which is
        //? already presented in front of the window the Open panel is shown from
        case .importEQFile: return state.tabs && !state.sheet
        }
    }

    static func ticked(_ command: Command, _ state: State) -> Bool {
        switch command {
        case .shuffle: return state.queued && state.shuffle
        case .repeatOff, .repeatAll, .repeatOne: return state.queued && command.repeatMode == state.repeatMode
        case .upNext, .lyrics, .info: return state.panel == command.panel
        default: return false
        }
    }
}
