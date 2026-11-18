import Foundation

// The Mac's menus and keys (the Mac app's plan 1.3; notes/ios.md "The Mac app, slice 2: menus, keys, right-click and the
// window"): what deadwax adds to the menu bar - Settings… in the app's menu, Find in Edit, Refresh in View, and the
// Controls menu - each item's words, its shortcut and whether it can be used now, from the player's state and the
// window's. The App draws these and nothing else (ios/App/Shared/MacCommands.swift); every rule is here, tested on
// Linux. The words are the app's own where it has them - Play/Pause, Next and Previous the player's, Shuffle and Repeat
// Up Next's (shuffleLabel, repeatLabel, UpNextWords.repeatSaid), Refresh the Library's •••'s, Settings the tab's - never
// retyped; Forward 10 Seconds, Back 10 Seconds and Go to Current Song are the Mac's own, as Music names them.

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

        public init(queued: Bool = false, playing: Bool = false, shuffle: Bool = false, paged: PagedScope? = nil,
                    repeatMode: Repeat = .off, length: Double = 0, hasAlbum: Bool = false, typing: Bool = false,
                    tabs: Bool = true, refresh: Refresh = .none, nowPlaying: Bool = false) {
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
        /// A dialog's Cancel the iPhone leaves the system to draw, drawn on the Mac so Return presses it (the Remove
        /// dialogs of Downloads): the system's own word.
        public static let cancel = "Cancel"

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
        }
    }

    static func enabled(_ command: Command, _ state: State) -> Bool {
        switch command {
        case .settings, .find: return state.tabs
        case .refresh: return state.tabs && !state.nowPlaying && state.refresh == .ready
        case .playPause, .next, .previous: return state.queued
        case .forward, .back: return state.queued && state.length > 0
        //? as Now Playing's Shuffle: a library's shuffle can't be turned off
        case .shuffle: return state.queued && state.paged == nil
        case .repeatOff, .repeatAll, .repeatOne: return state.queued
        case .goToCurrentSong: return state.tabs && state.queued && state.hasAlbum
        }
    }

    static func ticked(_ command: Command, _ state: State) -> Bool {
        switch command {
        case .shuffle: return state.queued && state.shuffle
        case .repeatOff, .repeatAll, .repeatOne: return state.queued && command.repeatMode == state.repeatMode
        default: return false
        }
    }
}
