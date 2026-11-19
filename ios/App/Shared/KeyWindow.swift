import UIKit

/// The app's own window - the screen's own safe area, where a view's can be other than the screen's: a view's bottom
/// inset counts the keyboard (MainTabs's home indicator's room). The Library's top no longer asks here: it reads the
/// window its own row is in (LibraryTop's probe, 18 Nov).
///
/// Which window (18 Nov, notes/ios.md "The Library's top after Now Playing"): a scene's windows aren't only the app's -
/// iOS's own sit over them (the keyboard's, the text effects'), at a level above a normal window's, and can hold other
/// insets. So the window is the scene's key window when it is one of the app's, the scene in front first; else the
/// first of the app's own windows that shows - never `windows.first`, whatever that is, as it was until then.
enum KeyWindow {
    /// The app's window, nil before there is one.
    @MainActor static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { (scene: UIScene) -> UIWindowScene? in scene as? UIWindowScene }
            .sorted { (one: UIWindowScene, other: UIWindowScene) -> Bool in
                order(one.activationState) < order(other.activationState)
            }
        for scene in scenes {
            if let key = scene.keyWindow, isApps(key) { return key }
        }
        for scene in scenes {
            if let own = scene.windows.first(where: { (window: UIWindow) -> Bool in isApps(window) }) { return own }
        }
        return nil
    }

    /// The app's window's safe area, none before there is a window.
    @MainActor static var safeArea: UIEdgeInsets {
        window?.safeAreaInsets ?? .zero
    }

    /// One of the app's own windows: a normal window's level, showing, a page in it - never iOS's own laid over the
    /// app's (the keyboard's and the text effects' sit above normal).
    @MainActor private static func isApps(_ window: UIWindow) -> Bool {
        window.windowLevel == .normal && !window.isHidden && window.rootViewController != nil
    }

    /// The scene in front first: active, then inactive, then in the background, then not yet attached.
    private static func order(_ state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive: return 0
        case .foregroundInactive: return 1
        case .background: return 2
        case .unattached: return 3
        @unknown default: return 4
        }
    }
}
