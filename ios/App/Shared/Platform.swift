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

    /// The window (slice 3, the desktop frame - the Mac app's plan 1.2): as wide and as tall as you like above the
    /// least that holds the sidebar, a page and the player bar (MacFrame's smallest, 880 x 600), opening at 1280 x 820,
    /// where the side panels are a third column. It was phone-shaped until slice 3 (390 x 640 to 600 wide). Its size
    /// and place after that are macOS's to remember.
    enum Window {
        static let smallest = CGSize(width: MacFrame.smallestWidth, height: MacFrame.smallestHeight)
        static let widest = CGFloat.greatestFiniteMagnitude
        static let opening = CGSize(width: MacFrame.openingWidth, height: MacFrame.openingHeight)
    }

    /// (Slice 3) The app's own window scenes - the one RootView is drawn in (MainWindowMarker). Only these are shaped,
    /// never whatever else comes to the front: a sheet held to the main window's least size would be 880 wide. On the
    /// Mac a sheet is drawn in a window of its own (macOS logs a scene for it) - though slice 3's smoke runs saw no
    /// second UIWindowScene join the app's while one was up, and a cover drawn in the main window - so nothing here
    /// counts on either. RootView is drawn in the WindowGroup's scene alone - never inside a presentation, whose page is
    /// the sheet's own view - so a scene RootView's view has moved into is the main one.
    @MainActor private static let mainScenes = NSHashTable<UIWindowScene>.weakObjects()

    /// At launch (the app delegate): the app's window shaped as RootView is drawn in it (`mainScene`), and again each
    /// time it comes to the front (the same values - in case the first was too soon for macOS to take them). A scene
    /// that isn't the app's window - a sheet's, a cover's - is never shaped.
    static func launching() {
        _ = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil,
                                                   queue: .main) { (note: Notification) in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated {
                if mainScenes.contains(scene) { shape(scene) }
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

    /// (Slice 3) RootView's view is in this scene's window: the app's own, shaped now and each time it comes to the front.
    @MainActor static func mainScene(_ scene: UIWindowScene) {
        guard !mainScenes.contains(scene) else { return }
        mainScenes.add(scene)
        shape(scene)
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
    /// The Mac's window: opening at the desktop frame's size (slice 3), and the menus without File > New Window (one
    /// window: never a second copy of the app's pages) or Help (there is no Mac help book) - and (slice 2) deadwax's
    /// own: Settings…, Find, Refresh and Controls (MacCommands).
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

    /// (Slice 2) Search's field takes the cursor at Edit > Find (⌘F, AppNavigation.find) - (slice 3) the sidebar's, its
    /// focus the field's own (`focused`), so the field knows when it has the cursor.
    func findField(_ focused: FocusState<Bool>.Binding) -> some View {
        modifier(FindFocus(focused: focused))
    }

    /// (Slice 3) Search's field: the sidebar's on the Mac (MacSidebarView), so Search's page draws none of its own.
    func searchField(text: Binding<String>, prompt: String) -> some View {
        self
    }

    /// (Slice 3) An album's page, an artist's and the album you don't have: centred at a readable width in the
    /// desktop frame (MacFrame.readableWidth, the web's --app-desk-content-max), the page's room either side of it -
    /// (slice 3's review) as its scroll views' margins, so the page still scrolls under the pointer anywhere across
    /// it and its scroll bar is at the page's edge, rather than the scroll view narrowed to the readable width.
    func readableOnMac() -> some View {
        modifier(ReadableOnMac())
    }

    /// (Slice 3) RootView: the window it is drawn in is the app's own, the one scene shaped (MainWindowMarker).
    func shapesWindow() -> some View {
        background(MainWindowMarker().accessibilityHidden(true))
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

/// readableOnMac's: the page's width read, and the room beyond the readable width given to its scroll views as their
/// content's horizontal margins (MacFrame.readableMargin) - none, the scroll view's own, on a page narrower than that.
private struct ReadableOnMac: ViewModifier {
    @State private var margin: Double = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin > 0 ? CGFloat(margin) : nil, for: .scrollContent)
            .onGeometryChange(for: Double.self) { (page: GeometryProxy) -> Double in
                MacFrame.readableMargin(width: Double(page.size.width))
            } action: { (now: Double) -> Void in
                margin = now
            }
    }
}

/// (Slice 3) A view of no size behind RootView: as it is put in a window, that window's scene is the app's own
/// (Platform.mainScene) - the one shaped. UIKit says when a view moves into a window; SwiftUI has no such moment.
private struct MainWindowMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker {
        Marker()
    }

    func updateUIView(_ marker: Marker, context: Context) {}

    final class Marker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let scene = window?.windowScene { Platform.mainScene(scene) }
        }
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
    func findField(_ focused: FocusState<Bool>.Binding) -> some View {
        self
    }

    /// Search's field in the navigation bar, always drawn - exactly as before.
    func searchField(text: Binding<String>, prompt: String) -> some View {
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
    }

    /// The Mac's alone: the iPhone's page is the screen's width.
    func readableOnMac() -> some View {
        self
    }

    /// The Mac's alone: the iPhone's window is the screen.
    func shapesWindow() -> some View {
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
