import SwiftUI
import UIKit

/// The app's type, one place for every screen, on the iPhone and the Mac (notes/ios.md "The app's fonts: Libre Franklin
/// and Courier Prime (2026-11-25)"). James chose them on 25 Nov ("libre franklin", then "Adopt it"), in place of Noto
/// Sans (15 Nov) and Noto Sans Mono (24 Nov): **Libre Franklin** for the words and **Courier Prime** for the readouts.
/// ios/scripts/make-fonts.py makes them from ios/scripts/fonts (google/fonts at 6ebe737e) - Libre Franklin's variable
/// font pinned at 400, 500, 600 and 700, Courier Prime's Regular and Bold as they are - six faces in ios/App/Fonts,
/// registered by Info.plist's UIAppFonts. Nothing in ios/App names a system text font of its own
/// (tests/test_ios_palette.py holds that).
///
/// - Each of iOS's text styles is here at its size at the standard text size (Large: body 17, footnote 13...),
///   `relativeTo:` its style, so it grows and shrinks with the phone's text size exactly as iOS's own did.
///   `.weight()`, `.bold()` and `Text.fontWeight()` pick the family's face (measured on this Mac: each draws the
///   named face pixel for pixel) - Regular, Medium, SemiBold, Bold; a heavier weight takes Bold.
/// - **Libre Franklin's figures are proportional** (a 1 is 465 thousandths wide, a 0 688) and it has no tabular ones
///   (no `tnum`), so `.monospacedDigit()` changes nothing drawn in it (measured: "1111" 82.5 pt, "0000" 118.5, at 40),
///   and the app asks it of nothing. A number is in the readout face, Courier Prime, whose every character is 1228/2048
///   of an em, where the drawings set it in mono, or where it changes continuously while you watch it and stands on its
///   own - a clock, a speed, a value being dragged or held, a size growing as a download comes: `readout(_:)` at a text
///   style, or Mac.mono, Phone.mono and Look.mono where a slice redrew it. A step count inside a sentence
///   ("Downloading - 4 of 12 songs", "30 of 140", a place in the queue) stays in the words, as drawn: its small shift
///   as a digit changes is accepted. tests/test_ios_palette.py's `TICKING` lists the readouts that change as you watch.
/// - **A readout beside words sits on their first text baseline** (`HStack(alignment: .firstTextBaseline)`, the
///   `.readout` LabeledContent style): Courier Prime's line is shorter than Libre Franklin's (1.123 of an em to 1.212)
///   and its baseline nearer its centre (0.22 of an em under it, to 0.36), so a row centring the two would set the
///   readout 1 to 2 points high. A piece with no words of its own in such a row - a divider, a meter - is centred on
///   the words' line by `centredOnWords(_:)`. tests/test_ios_readout_rows.py holds every readout beside words to it.
/// - `mono`: data - ids, paths, versions, an error's detail - in the system's monospace, as before, wherever a slice
///   hasn't redrawn it (the readouts a slice redraws take Courier Prime: `Typeface.Mac.mono`, `Typeface.Phone.mono`).
/// - `symbol`: what sizes an SF Symbol drawn alone (an Image) - iOS's own text style, as before, so every symbol is
///   the size and weight it was. A symbol inside a Label takes the Label's font, as any text beside it.
/// - A character neither face has falls back to iOS's own font, character by character - CoreText's own cascade, as
///   the families are registered (seen on this Mac: Greek in Libre Franklin draws in the system's sans, and Greek,
///   Cyrillic and Vietnamese's ơ and ư in Courier Prime in the system's monospace; nothing draws as a missing glyph).
///   Libre Franklin has Latin, Latin Extended, Vietnamese and Cyrillic but no Greek; Courier Prime Latin alone.
///
/// What UIKit draws for SwiftUI - the navigation bars' titles and buttons, the search fields, the segmented
/// controls - takes the same faces from `configureUIKit()` at launch. Menus, alerts, confirmation dialogs, swipe
/// actions and the Paste button are iOS's own and can't be given a font: they stay in iOS's.
enum Typeface {
    /// The family the four words faces share (their name table's, and SwiftUI's lookup).
    static let family = "Libre Franklin"

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

    /// A text style's size in Libre Franklin, scaled as that style scales.
    private static func text(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(family, size: size, relativeTo: style)
    }

    /// A readout - a number that changes while it is on screen - at a text style: Courier Prime at the style's size,
    /// scaled as the style scales, so it grows with the text size as the words beside it do and its figures hold still
    /// as they count. `.weight(.semibold)` and `.bold()` draw its Bold; Courier Prime has no Medium, and asked for one
    /// it draws Bold too (measured), so nothing asks a readout for Medium.
    static func readout(_ style: Font.TextStyle) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 17
        case .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        default: size = 17
        }
        return .custom(Mac.monoFamily, size: size, relativeTo: style)
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
        case regular = "LibreFranklin-Regular"
        case medium = "LibreFranklin-Medium"
        case semibold = "LibreFranklin-SemiBold"
        case bold = "LibreFranklin-Bold"
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
    /// Mac's type as James approved it on the design canvas (ios/design/dw.css): the words in Libre Franklin and the data -
    /// numbers, lengths, paths, formats - in Courier Prime (25 Nov, "Adopt it": in place of R1's Noto Sans and its "Bundle
    /// Noto Sans Mono" of 24 Nov), at the drawings' fixed sizes, as a Mac's own windows draw theirs. Only the Mac's views
    /// (ios/App/Mac) use it; the iPhone's sizes above are as they were. `.weight()` picks the face, as for the iPhone's.
    enum Mac {
        /// The readouts' family, Courier Prime - the two faces' name table's, and SwiftUI's lookup - for the Mac's data,
        /// Look.mono, Phone.mono and Typeface.readout alike.
        static let monoFamily = "Courier Prime"

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

        /// Data at a size, in Courier Prime.
        static func mono(_ size: Size) -> Font {
            .custom(monoFamily, fixedSize: CGFloat(size.rawValue))
        }

        /// The mono faces by their PostScript names (each file's name table; test_ios_palette.py checks them). Courier
        /// Prime has no Medium or SemiBold: as the drawings' browser does, a rule asking 500 is drawn Regular and one
        /// asking 600 Bold - `.weight(.semibold)` and `.bold()` draw Bold (measured). Asked for `.medium`, Apple's
        /// CoreText draws Bold too, not Regular (measured on this Mac), so nothing in the app asks a readout for Medium
        /// (test_ios_palette.py holds that): a readout the drawings set at 500 is drawn at the default, Regular.
        enum MonoFace: String, CaseIterable {
            case regular = "CourierPrime-Regular"
            case bold = "CourierPrime-Bold"
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
            /// .chip, and .count's - drawn in the mono face; (R1c's review) and the phone's faced chip, R1b's .chip (the
            /// New mark's: DWChip's `keepsFace`).
            case chip, count, facedChip
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
                case .facedChip: return .label                  // dw: .chip font-size
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
                case .chip: return (13, .footnote)              // dw.ph: .chip font-size
                case .count: return (11, .caption2)             // dw.ph: .count font
                case .facedChip: return (12.5, .caption)        // dw.ph: .chip font-size (R1b)
                case .segment: return (13, .footnote)           // dw.ph: .seg button font-size
                case .largeSegment: return (15, .subheadline)   // dw.ph: .seg.lg button font-size
                }
            }
        }

        /// Words in a role, on this device.
        static func text(_ role: Role) -> Font {
            Platform.mac ? Mac.text(role.mac) : .custom(family, size: role.phone.points, relativeTo: role.phone.style)
        }

        /// Data in a role (a count), in Courier Prime, on this device.
        static func mono(_ role: Role) -> Font {
            Platform.mac ? Mac.mono(role.mac)
                : .custom(Mac.monoFamily, size: role.phone.points, relativeTo: role.phone.style)
        }
    }

    /// (R1b) The phone's own pieces' type (ios/App/Phone), the phone's alone: dw.css's `.dw.ph` sizes - each scaled
    /// `relativeTo:` the text style nearest it, the smaller on a tie (R2's titled top's 28, iLibrary's own, went with it
    /// in R2b). `mono` is Courier Prime, the readout face, scaled the same way: for the readouts a slice redraws in mono
    /// ("3 of 11", "FLAC 16/44.1", "8 songs · 33 min left"). Typeface.mono, the system's, stays wherever a slice hasn't
    /// redrawn the data.
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
                case .strip: return (15, .subheadline)          // dw.ph: .chips > button font-size
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

        /// A readout at a size, in Courier Prime, scaled.
        static func mono(_ size: Size) -> Font {
            .custom(Mac.monoFamily, size: size.scaled.points, relativeTo: size.scaled.style)
        }
    }
}

// MARK: a readout beside words (25 Nov)

extension Typeface {
    /// How far Libre Franklin's baseline sits under the centre of its line, in ems: its ascender 966 and descender 246
    /// of 1000, no line gap - (966 - 246) / 2. Courier Prime's sits 0.22 under (its ascender 1600 and descender 700 of
    /// 2048), so the two centred side by side would set the readout's baseline higher (test_ios_palette.py measures
    /// both from the files).
    static let wordsBaselineUnderCentre: CGFloat = 0.36
}

extension View {
    /// A piece with no words of its own - a divider, a meter - in a row set on the first text baseline, centred on the
    /// line of the words at `size` points, where it was while the row was centred. Without it the row would stand the
    /// piece on the baseline (a view without text has its bottom for one). (The Mac's views pass one of its sizes'
    /// points: Typeface.Mac is named only from the Mac's own files - test_ios_mac_reach.py.)
    func centredOnWords(_ size: CGFloat) -> some View {
        alignmentGuide(.firstTextBaseline) { (piece: ViewDimensions) -> CGFloat in
            piece[VerticalAlignment.center] + size * Typeface.wordsBaselineUnderCentre
        }
    }
}

/// (25 Nov) A fact's row with its value on its label's first text baseline - laid out as a list's own LabeledContent
/// is, the label leading and the value trailing in the secondary colour, but never centred on the label, which would
/// set a readout (Courier Prime) 1 to 2 points above the words beside it. Where the two don't fit side by side (the
/// accessibility sizes) the value goes under its label. One element for VoiceOver, its label then its value, as a
/// LabeledContent is. `.labeledContentStyle(.readout)`, on the row or on what holds it.
struct ReadoutLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                configuration.label
                Spacer(minLength: 8)
                configuration.content
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.content
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension LabeledContentStyle where Self == ReadoutLabeledContentStyle {
    /// A fact's row with its value on its label's baseline (ReadoutLabeledContentStyle).
    static var readout: ReadoutLabeledContentStyle { ReadoutLabeledContentStyle() }
}
