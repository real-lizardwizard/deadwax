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
///   Noto Sans Mono is bundled since the Mac redesign's R1, for the Mac's views: `Typeface.Mac.mono`, below - and,
///   from R1b, the readouts a slice redraws on the phone: `Typeface.Phone.mono`).
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
    /// isn't registered, never nothing. Capped (after review, 15 Nov) at the style's size at xxxLarge, the app's tab
    /// bar's cap (AppTabBar's `dynamicTypeSize(...xxxLarge)`): what these fonts go into - the inline title, the bars'
    /// buttons and the back button, a search field, a segmented control - is a bar or a control of a fixed height, and
    /// uncapped they reached about 53 pt in a 44 pt bar at the largest size. `capped: false` for the large title alone,
    /// which grows as iOS's own does.
    static func uiFont(_ face: Face, size: CGFloat, style: UIFont.TextStyle, capped: Bool = true) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: style)
        let font = UIFont(name: face.rawValue, size: size) ?? .systemFont(ofSize: size)
        guard capped else { return metrics.scaledFont(for: font) }
        return metrics.scaledFont(for: font, maximumPointSize: cap(size, style))
    }

    /// The cap: a style's size at xxxLarge, the largest of the standard text sizes - 23 for the 17 of the body and the
    /// headline, 19 for the footnote's 13.
    static func cap(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
        let largest = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        return UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: largest)
    }

    /// The faces for what UIKit draws, set on its appearance proxies once at launch (AppDelegate): a large title Bold
    /// at 34 (iOS's), an inline title SemiBold at 17, the bars' buttons and the back button Regular at 17, a search
    /// field's words Regular at 17, a segmented control's Regular at 13 and its chosen segment's SemiBold. Only the
    /// font is set - every colour, background and shape is still iOS's. They take the text size the app opened at:
    /// one changed while it's open reaches the bars when it next opens. All but the large title stop growing at
    /// xxxLarge (`uiFont`'s cap), as the app's tab bar does.
    @MainActor
    static func configureUIKit() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: uiFont(.bold, size: 34, style: .largeTitle, capped: false)]
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

// MARK: the Mac's

extension Typeface {
    /// (The Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces") The
    /// Mac's type as James approved it on the design canvas (ios/design/dw.css): Noto Sans for words and Noto Sans Mono for
    /// data - numbers, lengths, paths, formats ("Bundle Noto Sans Mono", 24 Nov: the web's own, made for the app by
    /// ios/scripts/make-fonts.py - Regular, Medium and SemiBold) - at the drawings' fixed sizes, as a Mac's own windows
    /// draw theirs. Only the Mac's views (ios/App/Mac) use it; the iPhone's sizes above are as they were.
    /// `.weight()` picks the face, as for the iPhone's.
    enum Mac {
        /// The family the three mono faces share (their name table's, and SwiftUI's lookup).
        static let monoFamily = "Noto Sans Mono"

        /// The drawings' sizes, in points (dw.css's px; tests/test_ios_mac_look.py holds each to it).
        enum Size: Double, CaseIterable {
            /// .h1: a page's own heading.
            case h1 = 28
            /// A page's second heading: Edit an album's album over its tabs, Needs a look's and People's.
            case h2 = 20
            /// .brand: the wordmark at the sidebar's top.
            case brand = 19
            /// A third: Info's album, beside its cover.
            case h3 = 18
            /// .lcd .b: the song's title in the player's display.
            case lcd = 14
            /// The window's words (.dw's font). Named apart from iOS's text styles (`.body`, `.title`), which the Mac's
            /// type never takes.
            case base = 13
            /// .btn, .find, .tab, a field's label, a large segment.
            case control = 12.5
            /// .s, .btn.sm, the title strip.
            case small = 12
            /// .xs, a group's heading, a column's header, the status bar, a segment, a chip, a box's legend.
            case label = 11.5
            /// .count: a sidebar row's count, in the mono face.
            case count = 11
        }

        /// Words at a size.
        static func text(_ size: Size) -> Font {
            .custom(family, fixedSize: CGFloat(size.rawValue))
        }

        /// Data at a size, in Noto Sans Mono.
        static func mono(_ size: Size) -> Font {
            .custom(monoFamily, fixedSize: CGFloat(size.rawValue))
        }

        /// The mono faces by their PostScript names (each file's name table; test_ios_palette.py checks them).
        enum MonoFace: String, CaseIterable {
            case regular = "NotoSansMono-Regular"
            case medium = "NotoSansMono-Medium"
            case semibold = "NotoSansMono-SemiBold"
        }
    }
}

// MARK: both devices' (R1b)

extension Typeface {
    /// (The Mac and iPhone redesign, slice R1b - notes/ios.md "The redesign, slice R1b: the shared look, and the phone's
    /// pieces") The type of the parts both devices draw (ios/App/Look), by what each is for: on the Mac R1's, Typeface.Mac's
    /// fixed sizes, exactly as before; on the phone dw.css's `.dw.ph` size, scaled `relativeTo:` the text style nearest
    /// it (the smaller on a tie) - so it grows with the text size as every other word on the phone does.
    /// tests/test_ios_phone_look.py holds both halves to dw.css, rule by rule. `.weight()` picks the face.
    enum Look {
        enum Role: CaseIterable {
            /// .btn, .btn.sm and .btn.lg (the Mac has no large button: its is a button's).
            case button, smallButton, largeButton
            /// .in, and a field's label (.field > label).
            case field, fieldLabel
            /// .chip, and .count's - drawn in the mono face.
            case chip, count
            /// .seg button and .seg.lg button.
            case segment, largeSegment

            /// The Mac's size: Typeface.Mac's.
            var mac: Mac.Size {
                switch self {
                case .button: return .control                   // dw: .btn font-size
                case .smallButton: return .small                // dw: .btn.sm font-size
                case .largeButton: return .control              // dw: .btn font-size
                case .field: return .base                       // dw: .in font-size
                case .fieldLabel: return .control               // dw: .field > label font-size
                case .chip: return .label                       // dw: .chip font-size
                case .count: return .count                      // dw: .count font
                case .segment: return .label                    // dw: .seg button font-size
                case .largeSegment: return .control             // dw: .seg.lg button font-size
                }
            }

            /// The phone's size, and the text style it scales with.
            var phone: (points: CGFloat, style: Font.TextStyle) {
                switch self {
                case .button: return (14, .footnote)            // dw.ph: .btn font-size
                case .smallButton: return (13.5, .footnote)     // dw.ph: .btn.sm font-size
                case .largeButton: return (17, .headline)       // dw.ph: .btn.lg font-size
                case .field: return (16, .callout)              // dw.ph: .in font-size
                case .fieldLabel: return (16, .callout)         // dw.ph: .field > label font-size
                case .chip: return (12.5, .caption)             // dw.ph: .chip font-size
                case .count: return (11, .caption2)             // dw.ph: .count font
                case .segment: return (13, .footnote)           // dw.ph: .seg button font-size
                case .largeSegment: return (14, .footnote)      // dw.ph: .seg.lg button font-size
                }
            }
        }

        /// Words in a role, on this device.
        static func text(_ role: Role) -> Font {
            Platform.mac ? Mac.text(role.mac) : .custom(family, size: role.phone.points, relativeTo: role.phone.style)
        }

        /// Data in a role (a count), in Noto Sans Mono, on this device.
        static func mono(_ role: Role) -> Font {
            Platform.mac ? Mac.mono(role.mac)
                : .custom(Mac.monoFamily, size: role.phone.points, relativeTo: role.phone.style)
        }
    }

    /// (R1b) The phone's own pieces' type (ios/App/Phone), the phone's alone: dw.css's `.dw.ph` sizes - each scaled
    /// `relativeTo:` the text style nearest it, the smaller on a tie (R2's titled top's 28, iLibrary's own, went with it
    /// in R2b). `mono` is
    /// Noto Sans Mono, the bundled face, scaled the same way: for the readouts a slice redraws in mono ("3 of 11",
    /// "FLAC 16/44.1", "8 songs · 33 min left"). Typeface.mono, the system's, stays wherever a slice hasn't redrawn the
    /// data.
    enum Phone {
        enum Size: CaseIterable {
            /// A one-tap strip's button (.chips > button).
            case strip
            /// The compact top's purple back link (.back).
            case back
            /// The large title under the top (.big).
            case big
            /// A page's name centred in the compact top (.topbar > .ttl).
            case topName
            /// The meta line, and its purple link (.meta, .meta .link).
            case meta
            /// A tab bar's item's words, and Now Playing's bottom row's (.tabbar > a).
            case tabItem
            /// A group's legend (.group > .legend).
            case legend
            /// A card's row: a fact's, a row that goes somewhere, a field's label (.kv, .go).
            case row
            /// The drawings' small and extra-small words and readouts (.s, .xs).
            case small, extraSmall

            /// Its size, and the text style it scales with.
            var scaled: (points: CGFloat, style: Font.TextStyle) {
                switch self {
                case .strip: return (14, .footnote)             // dw.ph: .chips > button font-size
                case .back: return (17, .headline)              // dw.ph: .back font-size
                case .big: return (34, .largeTitle)             // dw.ph: .big font-size
                case .topName: return (17, .headline)           // dw.ph: .dw font-size
                case .meta: return (13, .footnote)              // dw.ph: .meta font-size
                case .tabItem: return (11, .caption2)           // dw.ph: .tabbar > a font-size
                case .legend: return (13, .footnote)            // dw.ph: .group > .legend font-size
                case .row: return (16, .callout)                // dw.ph: .go font-size
                case .small: return (13, .footnote)             // dw.ph: .s font-size
                case .extraSmall: return (12, .caption)         // dw.ph: .xs font-size
                }
            }
        }

        /// Words at a size, scaled.
        static func text(_ size: Size) -> Font {
            .custom(family, size: size.scaled.points, relativeTo: size.scaled.style)
        }

        /// A readout at a size, in Noto Sans Mono, scaled.
        static func mono(_ size: Size) -> Font {
            .custom(Mac.monoFamily, size: size.scaled.points, relativeTo: size.scaled.style)
        }
    }
}
