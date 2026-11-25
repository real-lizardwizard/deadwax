import SwiftUI

/// The Mac redesign's colours (slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces"):
/// the window as James approved it on the design canvas, "the web app's look, a touch more vintage" - every colour and
/// gradient of ios/design/dw.css, the canvas's own stylesheet, and nothing else.
///
/// - **dw.css's tokens** first, under dw.css's own names (`--bg` is `bg`, `--t2` is `t2`), each held to its custom
///   property by tests/test_ios_mac_look.py.
/// - **Each part's own** after them - a button's face, the title strip's gradient, a key's ring - each line naming the
///   rule and the property it comes from (`dw: .btn background`), which the test reads and holds the colour to: a
///   colour that isn't that rule's fails it. Where the property holds more than one colour - a box-shadow's layers -
///   the line names which, counting from 1 (`dw: .btn box-shadow 2`, the drop under the button), and is held to that
///   one alone.
/// - Nothing else: every line here is one of those, a colour made by `hex`, `rgba` or `vertical` from dw.css's own
///   numbers - no colour of SwiftUI's or the system's, and none without its comment.
///
/// Only the Mac's views (ios/App/Mac) and its frame draw these; nothing in App/Mac writes a colour of its own (the same
/// test). The iPhone's Palette is as it was: this is not a second name for it - where they differ (the card, the
/// selection's first stop), dw.css's is the Mac's.
enum MacPalette {
    // MARK: dw.css's tokens (.dw)

    static let bg = hex(0x0b0a10)                // --bg
    static let side = hex(0x111018)              // --side
    static let panel = hex(0x131219)             // --panel
    static let card = hex(0x1e1c26)              // --card
    static let frame = hex(0x22202b)             // --frame
    static let line = hex(0x2c2a36)              // --line
    static let rowline = hex(0x17161e)           // --rowline
    static let text = hex(0xffffff)              // --text
    static let head = hex(0xe4e4ec)              // --head
    static let t2 = hex(0xa3a3b8)                // --t2
    static let t3 = hex(0x8e8ea3)                // --t3
    static let label = hex(0x9d9db2)             // --label
    static let acc = hex(0xc084fc)               // --acc
    static let acct = hex(0xd8b4fe)              // --acct
    static let selt = hex(0xe9d5ff)              // --selt
    static let selbg = vertical(rgba(168, 85, 247, 0.22), rgba(168, 85, 247, 0.1))    // --selbg
    static let selbd = rgba(192, 132, 252, 0.5)  // --selbd
    static let well = hex(0x09080d)              // --well

    // MARK: the title strip, a toolbar, the groove

    static let titleFace = vertical(hex(0x221f2b), hex(0x17161d))     // dw: .titlebar background
    static let titleEdge = hex(0x07060a)                              // dw: .titlebar border-bottom
    static let titleSheen = rgba(255, 255, 255, 0.07)                 // dw: .titlebar box-shadow
    static let toolbarFace = vertical(hex(0x1d1b25), hex(0x15141b))   // dw: .bar background
    static let toolbarSheen = rgba(255, 255, 255, 0.05)               // dw: .bar box-shadow
    static let groove = hex(0x0a090e)                                 // dw: .groove background
    static let grooveSheen = rgba(255, 255, 255, 0.06)                // dw: .groove box-shadow

    // MARK: buttons

    static let buttonEdge = hex(0x3d3a49)                             // dw: .btn border
    static let buttonFace = vertical(hex(0x2e2c38), hex(0x201e28))    // dw: .btn background
    static let buttonSheen = rgba(255, 255, 255, 0.08)                // dw: .btn box-shadow 1
    static let buttonDrop = rgba(0, 0, 0, 0.45)                       // dw: .btn box-shadow 2
    static let buttonText = hex(0xe8e8f0)                             // dw: .btn color
    static let primaryEdge = hex(0x6b21a8)                            // dw: .btn.pri border-color
    static let primaryFace = vertical(hex(0xb56af5), hex(0x9333ea))   // dw: .btn.pri background
    static let primarySheen = rgba(255, 255, 255, 0.3)                // dw: .btn.pri box-shadow 1
    static let primaryDrop = rgba(0, 0, 0, 0.5)                       // dw: .btn.pri box-shadow 2
    static let primaryText = hex(0xffffff)                            // dw: .btn.pri color
    static let redEdge = hex(0x991b1b)                                // dw: .btn.red border-color
    static let redFace = vertical(hex(0xdc4a4a), hex(0xb91c1c))       // dw: .btn.red background
    static let redText = hex(0xffffff)                                // dw: .btn.red color

    // MARK: fields and wells

    static let wellShade = rgba(0, 0, 0, 0.7)                         // dw: .well box-shadow
    static let fieldText = hex(0xffffff)                              // dw: .in color
    static let checkFill = hex(0xa855f7)                              // dw: input[type=checkbox] accent-color

    // MARK: chips and counts

    static let countEdge = rgba(192, 132, 252, 0.4)                   // dw: .count border
    static let countFill = rgba(168, 85, 247, 0.16)                   // dw: .count background
    static let amberEdge = rgba(252, 211, 77, 0.3)                    // dw: .chip.amber border-color
    static let amberFill = rgba(251, 191, 36, 0.14)                   // dw: .chip.amber background
    static let amberText = hex(0xfcd34d)                              // dw: .chip.amber color
    static let greenEdge = rgba(110, 231, 183, 0.28)                  // dw: .chip.green border-color
    static let greenFill = rgba(52, 211, 153, 0.14)                   // dw: .chip.green background
    static let greenText = hex(0x6ee7b7)                              // dw: .chip.green color
    static let redChipEdge = rgba(252, 165, 165, 0.3)                 // dw: .chip.red border-color
    static let redChipFill = rgba(248, 113, 113, 0.14)                // dw: .chip.red background
    static let redChipText = hex(0xfca5a5)                            // dw: .chip.red color

    // MARK: folder tabs, the status bar, a group box's rules

    static let tabStripFace = vertical(hex(0x17161d), hex(0x131219))  // dw: .tabs background
    static let tabFace = vertical(hex(0x1c1a24), hex(0x16151c))       // dw: .tab background
    static let chosenTabEdge = hex(0x3d3a49)                          // dw: .tab.on border-color
    static let chosenTabText = hex(0xffffff)                          // dw: .tab.on color
    static let statusFace = vertical(hex(0x17161d), hex(0x111017))    // dw: .status background
    static let statusSheen = rgba(255, 255, 255, 0.04)                // dw: .status box-shadow
    static let divider = hex(0x262430)                                // dw: .status > div border-right

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

    // MARK: opacities

    /// A control that can't be used just now, faded (dw.css draws none: the web app's own, app.css's --app-pin-off).
    static let off: Double = 0.45                                     // web: --app-pin-off

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
