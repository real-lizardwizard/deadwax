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
    /// of the app's pages) or Help (there is no Mac help book).
    func macWindow() -> some Scene {
        defaultSize(width: Platform.Window.opening.width, height: Platform.Window.opening.height)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .help) {}
            }
    }
}

extension View {
    /// Pull to refresh - the iPhone's alone. In the Mac idiom UIKit refuses the refresh control with an exception
    /// ("not supported when running Catalyst apps in the Mac idiom"), so on the Mac there is none: the Library's •••
    /// has Refresh, and View > Refresh (⌘R) comes with the Mac's menus (slice 2), hung on this same modifier.
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        self
    }
}

#else

extension Platform {
    /// The iPhone's build.
    static let mac = false

    /// Nothing to do on the iPhone.
    static func launching() {}
}

extension Scene {
    /// The iPhone's window is the screen.
    func macWindow() -> some Scene {
        self
    }
}

extension View {
    /// Pull to refresh: SwiftUI's own, exactly as before.
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshable(action: action)
    }
}

#endif
