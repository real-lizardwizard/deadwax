import SwiftUI

/// The Mac's own colours (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces"; since R1b, "The redesign, slice R1b: the shared look, and the phone's pieces", only what the Mac alone
/// draws): the window's title strip, a toolbar and its groove, the folder tabs, the status bar, the player's keys and
/// display - every colour of ios/design/dw.css, the canvas's own stylesheet, for those parts, and nothing else. dw.css's
/// tokens and the parts both devices draw (buttons, fields, chips, counts, segments, the toggle, the checkbox, a meter)
/// are DWPalette's, in App/Look.
///
/// - **Each part's own**: each line naming the rule and the property it comes from (`dw: .titlebar background`), which
///   tests/test_ios_mac_look.py reads and holds the colour to: a colour that isn't that rule's fails it. Where the
///   property holds more than one colour - a box-shadow's layers - the line names which, counting from 1 (`dw: .key
///   box-shadow 3`, the drop under the key), and is held to that one alone.
/// - Nothing else: every line here is one of those, a colour made by `hex`, `rgba` or `vertical` from dw.css's own
///   numbers - no colour of SwiftUI's or the system's, no token, and none without its comment.
///
/// Only the Mac's views (ios/App/Mac) and its frame draw these (tests/test_ios_mac_reach.py). The iPhone's Palette is as
/// it was: this is not a second name for it.
enum MacPalette {
    // MARK: the title strip, a toolbar, the groove

    static let titleFace = vertical(hex(0x221f2b), hex(0x17161d))     // dw: .titlebar background
    static let titleEdge = hex(0x07060a)                              // dw: .titlebar border-bottom
    static let titleSheen = rgba(255, 255, 255, 0.07)                 // dw: .titlebar box-shadow
    static let toolbarFace = vertical(hex(0x1d1b25), hex(0x15141b))   // dw: .bar background
    static let toolbarSheen = rgba(255, 255, 255, 0.05)               // dw: .bar box-shadow
    static let groove = hex(0x0a090e)                                 // dw: .groove background
    static let grooveSheen = rgba(255, 255, 255, 0.06)                // dw: .groove box-shadow

    // MARK: folder tabs, the status bar, a group box's rules

    static let tabStripFace = vertical(hex(0x17161d), hex(0x131219))  // dw: .tabs background
    static let tabFace = vertical(hex(0x1c1a24), hex(0x16151c))       // dw: .tab background
    static let chosenTabEdge = hex(0x3d3a49)                          // dw: .tab.on border-color
    static let chosenTabText = hex(0xffffff)                          // dw: .tab.on color
    static let statusFace = vertical(hex(0x17161d), hex(0x111017))    // dw: .status background
    static let statusSheen = rgba(255, 255, 255, 0.04)                // dw: .status box-shadow
    static let divider = hex(0x262430)                                // dw: .status > div border-right

    // MARK: a column list (Requests' table, slice R8)

    static let columnsFace = vertical(hex(0x1a1822), hex(0x131219))   // dw: .cols background
    static let columnsRule = hex(0x262430)                            // dw: .cols > div border-right
    static let rowStripe = rgba(255, 255, 255, 0.018)                 // dw: .row.alt background
    static let groupRowFace = hex(0x100f15)                           // dw: .row.grp background
    /// (R8's review) A row's cover's edge.
    static let coverEdge = hex(0x34323c)                              // dw: .cover border

    // MARK: the player's keys and display

    static let keyEdge = hex(0x4d4959)                                // dw: .key border
    static let keyFace = vertical(hex(0x423e4f), hex(0x1f1d27))       // dw: .key background
    static let keySheen = rgba(255, 255, 255, 0.16)                   // dw: .key box-shadow 1
    static let keyRing = hex(0x0b0a0f)                                // dw: .key box-shadow 2
    static let keyDrop = rgba(0, 0, 0, 0.6)                           // dw: .key box-shadow 3
    static let keyText = hex(0xf0eef8)                                // dw: .key color
    static let bigKeyEdge = hex(0x581c87)                             // dw: .key.big border-color
    static let bigKeyFace = vertical((hex(0xc58bfb), 0), (hex(0x9333ea), 0.58), (hex(0x7e22ce), 1))    // dw: .key.big background
    static let bigKeySheen = rgba(255, 255, 255, 0.42)                // dw: .key.big box-shadow 1
    static let bigKeyRing = hex(0x0b0a0f)                             // dw: .key.big box-shadow 2
    static let bigKeyOuterRing = hex(0x2c2a36)                        // dw: .key.big box-shadow 3
    static let bigKeyText = hex(0xffffff)                             // dw: .key.big color
    static let lcd = hex(0x08070c)                                    // dw: .lcd background
    static let lcdShade = rgba(0, 0, 0, 0.75)                         // dw: .lcd box-shadow

    // MARK: the makings

    /// #rrggbb, opaque, in sRGB (CSS's).
    private static func hex(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
              blue: Double(value & 0xff) / 255, opacity: 1)
    }

    /// rgba(r, g, b, a), in sRGB.
    private static func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: Double) -> Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: alpha)
    }

    /// linear-gradient(to bottom, top, bottom).
    private static func vertical(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// linear-gradient(to bottom, ...) with its stops where the rule puts them (.key.big's #9333ea at 58%).
    private static func vertical(_ stops: (Color, Double)...) -> LinearGradient {
        LinearGradient(stops: stops.map { (stop: (Color, Double)) -> Gradient.Stop in
            Gradient.Stop(color: stop.0, location: CGFloat(stop.1))
        }, startPoint: .top, endPoint: .bottom)
    }
}
