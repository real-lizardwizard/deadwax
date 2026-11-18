import DeadwaxCore
import SwiftUI
import UIKit

/// The Mac's menus and keys (the Mac app's plan 1.3; notes/ios.md "The Mac app, slice 2: menus, keys, right-click and
/// the window"): deadwax > Settings… (⌘,), Edit > Find (⌘F), View > Refresh (⌘R) and the Controls menu - Play/Pause
/// (Space), Next (⌘→), Previous (⌘←), Forward and Back 10 Seconds (⌥⌘→, ⌥⌘←), Shuffle, Repeat's three and Go to Current
/// Song (⌘L) - and (slice 3, the desktop frame) View's Show/Hide Sidebar (⌃⌘S), Up Next (⌥⌘U), Lyrics (⌥⌘L) and Info
/// (⌘I), the three side panels ticked while theirs shows. Drawn from Core's MacMenu and nothing else: each item's words, key, dimming and tick are MacMenu's, read
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
    /// (Slice 3) Whether the song has lyrics: View > Lyrics is dimmed for one known to have none, as the bar's button.
    let lyrics: LyricsModel

    /// The menus' state now: the player's, the window's (a text field with the cursor, the sign-in, Now Playing, a
    /// sheet, the page shown's Refresh).
    private var state: MacMenu.State {
        let track = player.current?.track
        return MacMenu.State(queued: player.hasQueue, playing: player.isPlaying, shuffle: player.shuffle,
                             paged: player.paged?.scope, repeatMode: player.repeatMode, length: player.duration,
                             hasAlbum: track.flatMap { PlayedAlbum.route($0, player: player) } != nil,
                             typing: TextEditing.shared.typing,
                             tabs: server.launch == .ready && server.signInOver == nil,
                             refresh: MacRefresh.shared.state, nowPlaying: navigation.nowPlayingShown,
                             sheet: MacRefresh.shared.sheetUp, sidebarShown: navigation.macSidebarShown,
                             panel: navigation.macPanel, lyrics: lyrics.have)
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
        // (slice 3) the frame's: the sidebar, then the three panels - in the View menu's sidebar place. Replacing it,
        // never beside it (slice 3's review, smoke-run): kept, the system's own Show Sidebar has ⌃⌘S too, and UIKit
        // throws at launch over the two. Enter Full Screen is a place of its own and stays (fn-F, and ⌃⌘F).
        CommandGroup(replacing: .sidebar) {
            let sections = MacMenu.view(state)
            ForEach(Array(sections.enumerated()), id: \.offset) { (index: Int, section: [MacMenu.Item]) in
                if index > 0 { Divider() }
                frameItems(section)
            }
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

    /// (Slice 3) One section of View's frame: Show/Hide Sidebar a button, each panel a tick.
    @ViewBuilder private func frameItems(_ section: [MacMenu.Item]) -> some View {
        ForEach(section, id: \.command) { (each: MacMenu.Item) in
            if each.command.panel != nil {
                tick(each)
            } else {
                button(each)
            }
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
        case .sidebar:
            navigation.macSidebarShown.toggle()
        case .upNext, .lyrics, .info:
            if let panel = command.panel { navigation.togglePanel(panel) }
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
/// views), and counted again each time the window comes to the front - a field that lost the cursor with no notice
/// (its window closed, the app in the background) never leaves the keys off; started at launch on the Mac only
/// (Platform.launching).
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
        _ = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil,
                                                   queue: .main) { (_: Notification) in
            MainActor.assumeIsolated { TextEditing.shared.changed(nil, began: false) }
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
/// and hasn't gone (a page pushed over another, a tab); one refresh at a time, Refresh dimmed while it is on its way.
///
/// A sheet leaves the page under it on screen - it never disappears - so each sheet's root says it is up (`macSheet`,
/// MacSheet): every page and sheet carries how many sheets deep it is drawn (the environment's `macSheetLevel`), and only
/// the deepest counts. A sheet with no Refresh of its own dims Refresh, and Settings…, Find and Go to Current Song with it
/// (`sheetUp`); a page inside the sheet that has one (Edit album's release page) is the page shown. Each page is its view's
/// own, held here weakly and let go with its view: one that never said it went (its window closed under it) can't
/// linger. Not let go as a scene comes or goes - on the Mac every sheet is a scene of its own (notes/ios.md "Every sheet
/// carries the app's models"), so a scene coming or going says nothing of the pages under it.
@MainActor
@Observable
final class MacRefresh {
    static let shared = MacRefresh()

    /// One page's Refresh, or a sheet's root: its action, as its view last drew it, and how many sheets deep it is.
    @MainActor
    final class Page {
        var action: (@MainActor () async -> Void)?
        /// Sheets deep: 0 on the tabs (and on Now Playing), 1 in a sheet over them, 2 in one over that.
        var level = 0
        /// A sheet's root (MacSheet), not a page with a Refresh.
        var sheet = false
        /// Among the pages showing: let go here if its view goes without saying so.
        var listed = false

        nonisolated init() {}

        deinit {
            if listed { Task { @MainActor in MacRefresh.shared.letGo() } }
        }
    }

    /// One of the pages showing, held weakly: its view holds it.
    private struct Shown {
        weak var page: Page?
    }

    /// The pages showing with a Refresh, and the sheets up - the latest last.
    private var shown: [Shown] = []
    private var running = false

    /// Those still there.
    private var pages: [Page] { shown.compactMap { (each: Shown) -> Page? in each.page } }

    var state: MacMenu.Refresh {
        if running { return .running }
        return front?.action == nil ? .none : .ready
    }

    /// A sheet is up: the page under it out of reach.
    var sheetUp: Bool { deepest > 0 }

    /// How many sheets deep the deepest thing showing is.
    private var deepest: Int { pages.map { (page: Page) -> Int in page.level }.max() ?? 0 }

    /// The page shown: the latest page as deep as the deepest - none while a sheet with no Refresh is over the pages.
    private var front: Page? {
        let deepest = self.deepest
        return pages.last { (page: Page) -> Bool in !page.sheet && page.level == deepest }
    }

    func appeared(_ page: Page) {
        shown.removeAll { (each: Shown) -> Bool in each.page == nil || each.page === page }
        page.listed = true
        shown.append(Shown(page: page))
    }

    func went(_ page: Page) {
        page.listed = false
        shown.removeAll { (each: Shown) -> Bool in each.page == nil || each.page === page }
    }

    /// A page gone with its view, unsaid (its window closed under it): off the list, the menus drawn again.
    func letGo() {
        guard shown.contains(where: { (each: Shown) -> Bool in each.page == nil }) else { return }
        shown.removeAll { (each: Shown) -> Bool in each.page == nil }
    }

    func run() {
        guard !running, let page = front, page.action != nil else { return }
        running = true
        Task { @MainActor in
            await page.action?()
            running = false
        }
    }
}

/// How many sheets deep a view is drawn (MacRefresh): 0 on the tabs, one more inside each sheet's root (MacSheet).
private struct MacSheetLevel: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var macSheetLevel: Int {
        get { self[MacSheetLevel.self] }
        set { self[MacSheetLevel.self] = newValue }
    }
}

/// A page's ⌘R while it shows (MacRefresh), as deep as it is drawn.
struct MacRefreshing: ViewModifier {
    let action: @MainActor () async -> Void
    @Environment(\.macSheetLevel) private var level
    @State private var page = MacRefresh.Page()

    func body(content: Content) -> some View {
        page.action = action
        page.level = level
        return content
            .onAppear { MacRefresh.shared.appeared(page) }
            .onDisappear { MacRefresh.shared.went(page) }
    }
}

/// A sheet's root (Platform's `macSheet`): up while it shows, one sheet deeper than what it was opened over - and so is
/// everything inside it.
struct MacSheet: ViewModifier {
    @Environment(\.macSheetLevel) private var level
    @State private var page = MacRefresh.Page()

    func body(content: Content) -> some View {
        page.sheet = true
        page.level = level + 1
        return content
            .environment(\.macSheetLevel, level + 1)
            .onAppear { MacRefresh.shared.appeared(page) }
            .onDisappear { MacRefresh.shared.went(page) }
    }
}

/// The window can't be closed while it holds work a close would lose (the Mac's, slice 2): Edit album's changes, a
/// playlist's Edit with something changed (Platform's `keepsWindowOpen`). Close Window (⌘W) and the window's close
/// button are off meanwhile - the scene's own `isClosable` - and on again once nothing holds it: its Done, Discard or
/// Cancel, or the view holding it gone (a hold is let go with its view, so nothing gone can keep the window).
@MainActor
final class WindowWork {
    static let shared = WindowWork()

    /// One view's hold - the view's own, let go with it.
    @MainActor
    final class Holder {
        var on = false

        nonisolated init() {}

        deinit {
            Task { @MainActor in WindowWork.shared.apply() }
        }
    }

    private let holders = NSHashTable<Holder>.weakObjects()
    /// The windows shut here - the only ones opened again: a scene macOS made unclosable itself (a sheet's own, on the
    /// Mac) is never made closable.
    private let shut = NSHashTable<UIWindowScene>.weakObjects()
    private var started = false

    /// At launch on the Mac (Platform.launching): a window told as it comes.
    func start() {
        guard !started else { return }
        started = true
        for name in [UIScene.willConnectNotification, UIScene.didActivateNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { (_: Notification) in
                MainActor.assumeIsolated { WindowWork.shared.apply() }
            }
        }
    }

    func hold(_ holder: Holder, _ on: Bool) {
        holder.on = on
        holders.add(holder)
        apply()
    }

    /// Every window shut while something holds work; those shut opened again once nothing does.
    func apply() {
        let holding = holders.allObjects.contains { (holder: Holder) -> Bool in holder.on }
        if holding {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                guard let behaviors = scene.windowingBehaviors, behaviors.isClosable else { continue }
                behaviors.isClosable = false
                shut.add(scene)
            }
        } else {
            for scene in shut.allObjects {
                scene.windowingBehaviors?.isClosable = true
            }
            shut.removeAllObjects()
        }
    }
}

/// A view holding work (Platform's `keepsWindowOpen`): its hold kept in step with `on`.
struct WindowKeptOpen: ViewModifier {
    let on: Bool
    @State private var holder = WindowWork.Holder()

    func body(content: Content) -> some View {
        content
            .onAppear { WindowWork.shared.hold(holder, on) }
            .onChange(of: on) { (_: Bool, now: Bool) -> Void in WindowWork.shared.hold(holder, now) }
    }
}

/// The search field takes the cursor at Edit > Find (AppNavigation.find): once it shows - (slice 3) the desktop frame's
/// sidebar's field, a plain text field, its sidebar brought back first if it was put away. It was Search's own
/// navigation-bar field until slice 3, focused through SwiftUI's searchFocused (macOS 15 and later); a text field's
/// focus works on every macOS the app runs on.
struct FindFocus: ViewModifier {
    /// The field's focus - its own, so it knows when it has the cursor (the sidebar's clear button's Escape).
    let focused: FocusState<Bool>.Binding

    @Environment(AppNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content
            .focused(focused)
            .task(id: navigation.findWanted) {
                guard navigation.findWanted else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                focused.wrappedValue = true
                navigation.findTaken()
            }
    }
}
