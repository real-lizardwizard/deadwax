import SwiftUI
import UIKit

/// The app's type, one place for every screen (Noto Sans, 15 Nov - notes/ios.md "Noto Sans"). James chose "Noto Sans
/// (the web's)": the web app's own face, made for the phone from the web's own files (ios/scripts/make-fonts.py) -
/// four faces in ios/App/Fonts, Regular, Medium, SemiBold and Bold, each the web's seven scripts merged into one font
/// (Latin, Latin Extended, Vietnamese, Greek and Cyrillic, with their extensions), registered by Info.plist's
/// UIAppFonts. Nothing in ios/App names a system text font of its own (tests/test_ios_palette.py holds that).
///
/// - Each of iOS's text styles is here at its size at the standard text size (Large: body 17, footnote 13...),
///   `relativeTo:` its style, so it grows and shrinks with the phone's text size exactly as iOS's own did.
///   `.weight()`, `.bold()` and `Text.fontWeight()` pick the family's face (measured on this Mac: each draws the
///   named face pixel for pixel) - Regular, Medium, SemiBold, Bold; a heavier weight takes Bold.
/// - Noto Sans's figures are tabular as they are (every digit 572 thousandths wide), so a time or a track number
///   holds still with or without `.monospacedDigit()`, kept where it was.
/// - `mono`: data - ids, paths, versions, an error's detail - in the system's monospace, as before (the web's
///   Noto Sans Mono isn't bundled).
/// - `symbol`: what sizes an SF Symbol drawn alone (an Image) - iOS's own text style, as before, so every symbol is
///   the size and weight it was. A symbol inside a Label takes the Label's font, as any text beside it.
///
/// What UIKit draws for SwiftUI - the navigation bars' titles and buttons, the search fields, the segmented
/// controls - takes the same faces from `configureUIKit()` at launch. Menus, alerts, confirmation dialogs, swipe
/// actions and the Paste button are iOS's own and can't be given a font: they stay in iOS's.
enum Typeface {
    /// The family the four faces share (their name table's, and SwiftUI's lookup).
    static let family = "Noto Sans"

    static let largeTitle = text(34, .largeTitle)
    static let title = text(28, .title)
    static let title2 = text(22, .title2)
    static let title3 = text(20, .title3)
    /// iOS's headline: the body's size, semibold.
    static let headline = text(17, .headline).weight(.semibold)
    static let body = text(17, .body)
    static let callout = text(16, .callout)
    static let subheadline = text(15, .subheadline)
    static let footnote = text(13, .footnote)
    static let caption = text(12, .caption)
    static let caption2 = text(11, .caption2)

    /// A text style's size in Noto Sans, scaled as that style scales.
    private static func text(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(family, size: size, relativeTo: style)
    }

    /// Data: the system's monospace at a text style (ids, paths, versions, an error's detail, the turntable's line).
    static func mono(_ style: Font.TextStyle) -> Font {
        .system(style, design: .monospaced)
    }

    /// An SF Symbol drawn alone, at a text style: iOS's own font, which is how a symbol is sized.
    static func symbol(_ style: Font.TextStyle) -> Font {
        .system(style)
    }

    /// An SF Symbol drawn alone at a fixed size (a placeholder's glyph, Now Playing's play button).
    static func symbol(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: UIKit

    /// The faces by their PostScript names (each file's name table; test_ios_palette.py checks them).
    enum Face: String, CaseIterable {
        case regular = "NotoSans-Regular"
        case medium = "NotoSans-Medium"
        case semibold = "NotoSans-SemiBold"
        case bold = "NotoSans-Bold"
    }

    /// A face for UIKit at a text style's size, scaled for the text size in use - iOS's own font if the face somehow
    /// isn't registered, never nothing.
    static func uiFont(_ face: Face, size: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: style)
        guard let font = UIFont(name: face.rawValue, size: size) else {
            return metrics.scaledFont(for: .systemFont(ofSize: size))
        }
        return metrics.scaledFont(for: font)
    }

    /// The faces for what UIKit draws, set on its appearance proxies once at launch (AppDelegate): a large title Bold
    /// at 34 (iOS's), an inline title SemiBold at 17, the bars' buttons and the back button Regular at 17, a search
    /// field's words Regular at 17, a segmented control's Regular at 13 and its chosen segment's SemiBold. Only the
    /// font is set - every colour, background and shape is still iOS's. They take the text size the app opened at:
    /// one changed while it's open reaches the bars when it next opens.
    @MainActor
    static func configureUIKit() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: uiFont(.bold, size: 34, style: .largeTitle)]
        bar.titleTextAttributes = [.font: uiFont(.semibold, size: 17, style: .headline)]
        let button = [NSAttributedString.Key.font: uiFont(.regular, size: 17, style: .body)]
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes(button, for: state)
        }
        UISearchTextField.appearance().font = uiFont(.regular, size: 17, style: .body)
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: uiFont(.regular, size: 13, style: .footnote)], for: .normal)
        segmented.setTitleTextAttributes([.font: uiFont(.semibold, size: 13, style: .footnote)], for: .selected)
    }
}
