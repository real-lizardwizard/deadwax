import DeadwaxCore
import SwiftUI
import UIKit

/// The Mac's menus and keys (the Mac app's plan 1.3; notes/ios.md "The Mac app, slice 2: menus, keys, right-click and
/// the window"): deadwax > Settings… (⌘,), Edit > Find (⌘F), View > Refresh (⌘R) and the Controls menu - Play/Pause
/// (Space), Next (⌘→), Previous (⌘←), Forward and Back 10 Seconds (⌥⌘→, ⌥⌘←), Shuffle, Repeat's three and Go to Current
/// Song (⌘L). Drawn from Core's MacMenu and nothing else: each item's words, key, dimming and tick are MacMenu's, read
/// from the player and the window each time the menus are drawn; this only carries the click out, through the very
/// calls the player's own buttons make. The system's menus stay - About, Hide, Quit (⌘Q), Undo to Select All, Close
/// Window (⌘W), Enter Full Screen, the Window menu; File > New Window and Help go (Platform's `macWindow`), and Format
/// with them (there is nothing of deadwax's to format).
///
/// Handed to the scene on the iPhone too (DeadwaxApp), where Platform's `macWindow` takes no menus: nothing of it runs
/// there - the iPhone's menus are its •••s.
struct MacCommands: Commands {
    let player: PlayerModel
    let navigation: AppNavigation
    let server: ServerModel

    /// The menus' state now: the player's, the window's (a text field with the cursor, the sign-in, Now Playing, the
    /// page shown's Refresh).
    private var state: MacMenu.State {
        let track = player.current?.track
        return MacMenu.State(queued: player.hasQueue, playing: player.isPlaying, shuffle: player.shuffle,
                             paged: player.paged?.scope, repeatMode: player.repeatMode, length: player.duration,
                             hasAlbum: track.flatMap { PlayedAlbum.route($0, player: player) } != nil,
                             typing: TextEditing.shared.typing,
                             tabs: server.launch == .ready && server.signInOver == nil,
                             refresh: MacRefresh.shared.state, nowPlaying: navigation.nowPlayingShown)
    }

    var body: some Commands {
        let state = self.state
        CommandGroup(replacing: .appSettings) {
            item(.settings, state)
        }
        // Edit's Find, in place of the system's Find, Spelling and Substitutions - there is no document to find in
        CommandGroup(replacing: .textEditing) {
            item(.find, state)
        }
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(after: .toolbar) {
            item(.refresh, state)
        }
        CommandMenu(MacMenu.Words.controls) {
            let sections = MacMenu.controls(state)
            ForEach(Array(sections.enumerated()), id: \.offset) { (index: Int, section: [MacMenu.Item]) in
                if index > 0 { Divider() }
                controls(section)
            }
        }
    }

    /// One section of Controls: buttons, Shuffle a tick, Repeat's three ticks in Repeat's submenu.
    @ViewBuilder private func controls(_ section: [MacMenu.Item]) -> some View {
        ForEach(section.filter { $0.command.repeatMode == nil }, id: \.command) { (each: MacMenu.Item) in
            if each.command == .shuffle {
                tick(each)
            } else {
                button(each)
            }
        }
        let repeats = section.filter { $0.command.repeatMode != nil }
        if !repeats.isEmpty {
            Menu(MacMenu.Words.repeatMenu) {
                ForEach(repeats, id: \.command) { (each: MacMenu.Item) in tick(each) }
            }
            .disabled(repeats.allSatisfy { !$0.enabled })
        }
    }

    private func item(_ command: MacMenu.Command, _ state: MacMenu.State) -> some View {
        button(MacMenu.item(command, state))
    }

    private func button(_ item: MacMenu.Item) -> some View {
        Button(item.words) { perform(item.command) }
            .keyboardShortcut(Self.shortcut(item.shortcut))
            .disabled(!item.enabled)
    }

    private func tick(_ item: MacMenu.Item) -> some View {
        Toggle(item.words, isOn: Binding(get: { item.ticked }, set: { (_: Bool) -> Void in perform(item.command) }))
            .keyboardShortcut(Self.shortcut(item.shortcut))
            .disabled(!item.enabled)
    }

    /// The click, as the player's own button does it - read again now, not as the menu was drawn.
    private func perform(_ command: MacMenu.Command) {
        let now = MacMenu.item(command, state)
        guard now.enabled else { return }
        switch command {
        case .settings:
            navigation.showSettings()
        case .find:
            navigation.find()
        case .refresh:
            MacRefresh.shared.run()
        case .playPause:
            player.toggle()
        case .next:
            player.next()
        case .previous:
            player.previous()
        case .forward, .back:
            if let to = MacMenu.skip(command, from: player.shownPosition, length: player.duration) { player.seek(to: to) }
        case .shuffle:
            player.toggleShuffle()
        case .repeatOff, .repeatAll, .repeatOne:
            if let mode = command.repeatMode { player.setRepeat(mode) }
        case .goToCurrentSong:
            if let track = player.current?.track, let route = PlayedAlbum.route(track, player: player) {
                navigation.openAlbum(route)
            }
        }
    }

    /// MacMenu's key as SwiftUI's.
    static func shortcut(_ shortcut: MacMenu.Shortcut?) -> KeyboardShortcut? {
        guard let shortcut else { return nil }
        let key: KeyEquivalent
        switch shortcut.key {
        case .character(let character): key = KeyEquivalent(character)
        case .space: key = .space
        case .rightArrow: key = .rightArrow
        case .leftArrow: key = .leftArrow
        }
        var modifiers: EventModifiers = []
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}

/// Whether a text field has the cursor (the Mac's, slice 2): Space, ⌘→ and ⌘← are the field's meanwhile, off their
/// Controls items (MacMenu.yieldsToTyping) - so typing a space in Search never pauses the music. Read from UIKit's own
/// notices, every field and text view the app draws (SwiftUI's TextField, a search bar's field, the editors' text
/// views); started at launch on the Mac only (Platform.launching).
@MainActor
@Observable
final class TextEditing {
    static let shared = TextEditing()

    /// A field has the cursor now.
    private(set) var typing = false

    @ObservationIgnored private let editing = NSHashTable<AnyObject>.weakObjects()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        let notices: [(Notification.Name, Bool)] = [
            (UITextField.textDidBeginEditingNotification, true), (UITextField.textDidEndEditingNotification, false),
            (UITextView.textDidBeginEditingNotification, true), (UITextView.textDidEndEditingNotification, false),
        ]
        for (name, began) in notices {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { (note: Notification) in
                let field = note.object as? NSObject
                MainActor.assumeIsolated { TextEditing.shared.changed(field, began: began) }
            }
        }
    }

    private func changed(_ field: NSObject?, began: Bool) {
        if let field {
            if began { editing.add(field) } else { editing.remove(field) }
        }
        // a field gone without ending (its page closed) is let go by the table itself
        let now = editing.allObjects.contains { (each: AnyObject) -> Bool in (each as? UIResponder)?.isFirstResponder == true }
        if typing != now { typing = now }
    }
}

/// View > Refresh (⌘R, the Mac's, slice 2): the page shown asked again - each page's own phone pull (`pullToRefresh`) or,
/// where the phone's pull shuffles, its •••'s Refresh (`refreshCommand`). The page shown is the one that last appeared
/// and hasn't gone (a page pushed over another, a tab, a sheet's page); one refresh at a time, Refresh dimmed while it
/// is on its way.
@MainActor
@Observable
final class MacRefresh {
    static let shared = MacRefresh()

    /// One page's Refresh: its action, as its view last drew it.
    @MainActor
    final class Page {
        var action: (@MainActor () async -> Void)?

        nonisolated init() {}
    }

    /// The pages showing with a Refresh, the latest last.
    private var shown: [Page] = []
    private var running = false

    var state: MacMenu.Refresh {
        if running { return .running }
        return shown.last?.action == nil ? .none : .ready
    }

    func appeared(_ page: Page) {
        shown.removeAll { $0 === page }
        shown.append(page)
    }

    func went(_ page: Page) {
        shown.removeAll { $0 === page }
    }

    func run() {
        guard !running, let page = shown.last, page.action != nil else { return }
        running = true
        Task { @MainActor in
            await page.action?()
            running = false
        }
    }
}

/// A page's ⌘R while it shows (MacRefresh).
struct MacRefreshing: ViewModifier {
    let action: @MainActor () async -> Void
    @State private var page = MacRefresh.Page()

    func body(content: Content) -> some View {
        page.action = action
        return content
            .onAppear { MacRefresh.shared.appeared(page) }
            .onDisappear { MacRefresh.shared.went(page) }
    }
}

/// Search's field takes the cursor at Edit > Find (AppNavigation.find): once Search shows, after the tab's switch is
/// drawn. macOS 15 and later (SwiftUI's searchFocused); on 14, Find opens Search and the field waits for a click.
struct FindFocus: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        focusing(content)
            .task(id: navigation.findWanted) {
                guard navigation.findWanted else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                focused = true
                navigation.findTaken()
            }
    }

    @ViewBuilder private func focusing(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused($focused)
        } else {
            content
        }
    }
}
