import DeadwaxCore
import SwiftUI
import UIKit

/// Which build this is - the iPhone's, or the Mac's (Mac Catalyst, the Mac idiom): one app built twice from the same
/// files (notes/ios.md "The Mac app, slice 1: it runs and plays"). This file is the only one in the App that asks:
/// everything else reads `Platform.mac`, hands Core `Platform.device` (Core never asks - its words and rules that differ
/// take the device as a value, tested on Linux), or calls one of the few things below that are the Mac's alone.
///
/// The one switch is `targetEnvironment(macCatalyst)`, said once, below. Never `os(macOS)` (false on Catalyst),
/// `canImport(AppKit)` (true there, with AppKit's classes refused) or the Mac idiom (the same thing today, and another
/// if the idiom ever changed) - tests/test_ios_mac.py holds it.
///
/// (Slice 2, notes/ios.md "The Mac app, slice 2: menus, keys, right-click and the window") Every helper below is the
/// iPhone's exactly as before on the iPhone - `self`, or SwiftUI's own - and the Mac's on the Mac: its menus and keys
/// (MacCommands.swift), ⌘R hung on the same pulls, the ••• menus' items on a right-click, Escape on a sheet's Close,
/// Return on a dialog's Cancel, Find's cursor, a sheet's root known to the menus, the window kept open over work, and
/// one window.
enum Platform {
    /// The device this build is, for Core.
    static var device: Device { mac ? .mac : .iPhone }
}

#if targetEnvironment(macCatalyst)

extension Platform {
    /// The Mac's build.
    static let mac = true

    /// The window, phone-shaped until the desktop frame (the Mac app's plan 1.1): the phone's layout in a window,
    /// honest about what it is - no narrower or shorter than a phone, no wider than a phone's layout reads, opening at
    /// a big phone's size. Its size and place after that are macOS's to remember.
    enum Window {
        static let smallest = CGSize(width: 390, height: 640)
        static let widest: CGFloat = 600
        static let opening = CGSize(width: 430, height: 860)
    }

    /// At launch (the app delegate): each window scene shaped as it connects, and again each time it comes to the front
    /// (the same values - in case the first was too soon for macOS to take them).
    static func launching() {
        for name in [UIScene.willConnectNotification, UIScene.didActivateNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { (note: Notification) in
                guard let scene = note.object as? UIWindowScene else { return }
                MainActor.assumeIsolated { shape(scene) }
            }
        }
        // (slice 2) whether a text field has the cursor: Space, ⌘→ and ⌘← are its own meanwhile (MacMenu); the window's
        // close kept in step with the work it holds (WindowWork)
        MainActor.assumeIsolated {
            TextEditing.shared.start()
            WindowWork.shared.start()
        }
    }

    /// (Slice 2) A dialog's Cancel where the iPhone leaves it to the system to draw: drawn on the Mac, so Return presses
    /// it - never the dialog's Remove. The app's own Cancel (the web's word, QueuePickWords').
    @MainActor static func dialogCancel() -> some View {
        Button(QueuePickWords.cancel, role: .cancel) {}
            .returnCancels()
    }

    /// The window's limits, and its title bar: one with the toolbar, no title shown (each page has its own).
    @MainActor private static func shape(_ scene: UIWindowScene) {
        scene.sizeRestrictions?.minimumSize = Window.smallest
        scene.sizeRestrictions?.maximumSize = CGSize(width: Window.widest, height: CGFloat.greatestFiniteMagnitude)
        scene.titlebar?.titleVisibility = .hidden
        scene.titlebar?.toolbarStyle = .unified
    }
}

extension Scene {
    /// The Mac's window: opening phone-sized, and the menus without File > New Window (one window: never a second copy
    /// of the app's pages) or Help (there is no Mac help book) - and (slice 2) deadwax's own: Settings…, Find,
    /// Refresh and Controls (MacCommands).
    func macWindow(_ menus: MacCommands) -> some Scene {
        defaultSize(width: Platform.Window.opening.width, height: Platform.Window.opening.height)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .help) {}
                menus
            }
    }
}

extension View {
    /// Pull to refresh - the iPhone's alone. In the Mac idiom UIKit refuses the refresh control with an exception
    /// ("not supported when running Catalyst apps in the Mac idiom"), so on the Mac there is none: (slice 2) the same
    /// action is the page's View > Refresh (⌘R) while it is the page shown (MacRefresh).
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshCommand(action)
    }

    /// (Slice 2) ⌘R on a page whose phone pull is the shuffle's (the Library, an album, a playlist): its •••'s own
    /// Refresh, while it is the page shown. Nothing on the iPhone, where the ••• has it.
    func refreshCommand(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(MacRefreshing(action: action))
    }

    /// (Slice 2) A right-click's menu: `items`, the ••• menu's own (QueueMenuItems). On the iPhone, nothing - no row
    /// there had a long press, and none is added.
    func macContextMenu<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        contextMenu(menuItems: items)
    }

    /// (Slice 2) An album's tile or row: its •••'s items on a right-click (MacRightClick.swift).
    func albumRightClick(_ route: AlbumRoute) -> some View {
        modifier(AlbumRightClick(route: route))
    }

    /// (Slice 2) A playlist's row: its page's •••'s items on a right-click (MacRightClick.swift).
    func playlistRightClick(_ route: PlaylistRoute) -> some View {
        modifier(PlaylistRightClick(route: route))
    }

    /// (Slice 2) A sheet's Close, Cancel or Done - or Now Playing's and a cover's: Escape presses it, so Escape does
    /// what it does, asking first where it asks. `on` false: not now - something is typed that this Close would throw
    /// away without asking (Escape then does nothing, and Close is a click away), or a form inside a sheet whose own
    /// Cancel has it. Read only here (an autoclosure): the iPhone never reads it.
    func escapeCloses(_ on: @autoclosure () -> Bool = true) -> some View {
        keyboardShortcut(on() ? .cancelAction : nil)
    }

    /// (Slice 2) A sheet's root: while it is up the page under it is out of the menus' reach - ⌘R, Settings…, Find and
    /// Go to Current Song dimmed, unless a page inside the sheet has a Refresh of its own (MacRefresh, MacSheet).
    func macSheet() -> some View {
        modifier(MacSheet())
    }

    /// (Slice 2) While `on` - work a close would lose (Edit album's changes, a playlist's Edit) - the window can't be
    /// closed: ⌘W and its close button are off until the work is done or discarded (WindowWork).
    func keepsWindowOpen(_ on: @autoclosure () -> Bool) -> some View {
        modifier(WindowKeptOpen(on: on()))
    }

    /// (Slice 2) A dialog's Cancel (Keep editing, Don't delete…): Return presses it, so Return never confirms a delete
    /// or a write.
    func returnCancels() -> some View {
        keyboardShortcut(.defaultAction)
    }

    /// (Slice 2) Search's field takes the cursor at Edit > Find (⌘F, AppNavigation.find).
    func findField() -> some View {
        modifier(FindFocus())
    }

    /// (Slice 2) The one window: a file opened, or a link, comes to the window that's open rather than a second one.
    func oneWindow() -> some View {
        handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    /// A presented page on the Mac: given its presenter's models (Presenting.swift - a presentation's own scene starts
    /// it with an empty environment here, and its first `@Environment(PlayerModel.self)` would be a crash).
    func carryingApp(_ carried: AppCarried) -> some View {
        modifier(CarriesApp(carried: carried))
    }
}

#else

extension Platform {
    /// The iPhone's build.
    static let mac = false

    /// Nothing to do on the iPhone.
    static func launching() {}

    /// The iPhone's dialogs as before: the system draws their Cancel.
    @MainActor static func dialogCancel() -> some View {
        EmptyView()
    }
}

extension Scene {
    /// The iPhone's window is the screen, and its menus are the •••s.
    func macWindow(_ menus: MacCommands) -> some Scene {
        self
    }
}

extension View {
    /// Pull to refresh: SwiftUI's own, exactly as before.
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshable(action: action)
    }

    /// The Mac's alone: the ••• has Refresh.
    func refreshCommand(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        self
    }

    /// The Mac's alone: no long press is added to a row.
    func macContextMenu<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        self
    }

    /// The Mac's alone.
    func albumRightClick(_ route: AlbumRoute) -> some View {
        self
    }

    /// The Mac's alone.
    func playlistRightClick(_ route: PlaylistRoute) -> some View {
        self
    }

    /// The Mac's alone: no key is added to a button, and `on` is never read.
    func escapeCloses(_ on: @autoclosure () -> Bool = true) -> some View {
        self
    }

    /// The Mac's alone: a sheet as before.
    func macSheet() -> some View {
        self
    }

    /// The Mac's alone: the iPhone has no window to close, and `on` is never read.
    func keepsWindowOpen(_ on: @autoclosure () -> Bool) -> some View {
        self
    }

    /// The Mac's alone: a dialog's buttons as before.
    func returnCancels() -> some View {
        self
    }

    /// The Mac's alone: Search's field as before.
    func findField() -> some View {
        self
    }

    /// The iPhone has one scene.
    func oneWindow() -> some View {
        self
    }

    /// A presented page on the iPhone inherits its presenter's environment, as it always has: nothing to hand on.
    func carryingApp(_ carried: AppCarried) -> some View {
        self
    }
}

#endif
