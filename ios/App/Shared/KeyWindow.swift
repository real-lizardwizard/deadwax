import UIKit

/// The app's key window - the screen's own safe area, where a view's can be other than the screen's: a view's bottom
/// inset counts the keyboard (MainTabs's home indicator's room), and the Library's top stood in the Dynamic Island's
/// strip under the safe area its views were given (LibraryTop, TopClearance).
enum KeyWindow {
    /// The key window's safe area, none before there is a window.
    @MainActor static var safeArea: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { (scene: UIScene) -> UIWindowScene? in
            scene as? UIWindowScene
        }
        let windows = scenes.flatMap { (scene: UIWindowScene) -> [UIWindow] in scene.windows }
        let window = windows.first { (window: UIWindow) -> Bool in window.isKeyWindow } ?? windows.first
        return window?.safeAreaInsets ?? .zero
    }
}
