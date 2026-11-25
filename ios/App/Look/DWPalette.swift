import DeadwaxCore
import SwiftUI

/// The new look's colours on both devices (the Mac and iPhone redesign, slice R1b - notes/ios.md "The redesign, slice
/// R1b: the shared look, and the phone's pieces"; R1's MacPalette, moved here for both). The window as James approved
/// it on the design canvas, "the web app's look, a touch more vintage", and the phone "married" to it - every colour
/// and gradient of ios/design/dw.css, the canvas's own stylesheet, that both devices draw, and the phone's own pieces'.
///
/// - **dw.css's tokens** first, under dw.css's own names (`--bg` is `bg`, `--t2` is `t2`) - one set for both devices:
///   the phone's rules (`.dw.ph`) redefine none of them.
/// - **The shared parts'** after them - a button's face, a well's shade, a chip's colours - each line naming the rule
///   and the property it comes from (`dw: .btn background`), which tests/test_ios_mac_look.py reads and holds the
///   colour to. Where the property holds more than one colour - a box-shadow's layers - the line names which, counting
///   from 1 (`dw: .btn box-shadow 2`), and is held to that one alone.
/// - **The phone's own** (`dw.ph: .card border-bottom`): where the phone's rules draw a part in another colour (the
///   primary button) and the phone's own pieces (App/Phone), each held by tests/test_ios_phone_look.py to the phone's
///   rule as the cascade resolves it - the later of two `.dw.ph` rules winning. The phone's purple - its primary button
///   and the switch - is the app's own, PrimaryButton's (Core, held to theme.css by tests/test_ios_palette.py), made
///   from it here: `.dw.ph .btn.pri` and `.sw` are that same colour. (R1c - notes/ios.md "The redesign, slice R1c: the
///   phone is flat (2026-11-25)") The phone is flat: its own lines are hairlines and grounds now, no card, group or
///   strip face - and the shared parts it draws no face for (a secondary button's, the tinted chips') it draws nowhere.
/// - **The web's** (`web: --dw-primary-pressed`): the phone's primary pressed, PrimaryButton's own darkened press
///   (PrimaryFace's, held to theme.css by tests/test_ios_palette.py) - dw.css draws no pressed state - and `off`, the
///   faded opacity.
/// - Ahead of their slices: the checkbox's fill (R11's DWCheckbox) and the meter's (R8's DWMeter), so App/Look gains only
///   new files after R1b (the build plan's 3.5).
/// - Nothing else: every line here is one of those, a colour made by `hex`, `rgba`, `vertical`, `horizontal` or `deck`
///   from dw.css's own numbers or PrimaryButton's - no colour of SwiftUI's or the system's, and none without its comment.
///
/// What the Mac alone draws (the title strip, the toolbar, the folder tabs, the status bar, the keys, the lcd) is
/// MacPalette's, in App/Mac. The iPhone's Palette is as it was: this is not a second name for it.
enum DWPalette {
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

    // MARK: the phone's primary: the app's own purple (PrimaryButton's)

    static let phonePrimaryEdge = deck(PrimaryButton.edge)            // dw.ph: .btn.pri border-color
    static let phonePrimaryFace = vertical(deck(PrimaryButton.top), deck(PrimaryButton.bottom))    // dw.ph: .btn.pri background
    static let phonePrimarySheen = deck(PrimaryButton.highlight)      // dw.ph: .btn.pri box-shadow 1
    static let phonePrimaryDrop = rgba(0, 0, 0, 0.5)                  // dw.ph: .btn.pri box-shadow 2
    static let phonePrimaryText = deck(PrimaryButton.label)           // dw.ph: .btn.pri color
    // pressed: PrimaryFace's - the fill and the edge darkened by brightness(0.92), the web's own press (dw.css draws none)
    static let phonePrimaryPressedFace = vertical(deck(PrimaryButton.pressedTop), deck(PrimaryButton.pressedBottom))    // web: --dw-primary-pressed
    static let phonePrimaryPressedEdge = deck(PrimaryButton.pressedEdge)    // web: --dw-primary-pressed

    // MARK: fields and wells

    static let wellShade = rgba(0, 0, 0, 0.7)                         // dw: .well box-shadow
    static let fieldText = hex(0xffffff)                              // dw: .in color

    // MARK: a checkbox, a meter

    static let checkFill = hex(0xa855f7)                              // dw: input[type=checkbox] accent-color
    static let meterShade = rgba(0, 0, 0, 0.7)                        // dw: .meter box-shadow
    static let meterFill = vertical(hex(0xc8c8d4), hex(0x9a9aa8))     // dw: .meter > i background
    static let meterMarked = vertical(hex(0xb56af5), hex(0x9333ea))   // dw: .meter.pur > i background
    static let meterGood = vertical(hex(0x5ee39a), hex(0x34c47f))     // dw: .meter.grn > i background

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

    // MARK: the phone's pieces: the strip, the cards and groups, a list's rows

    // (R1c - James, 25 Nov: "get rid of all the grey boxes") The phone is flat: no strip, card or group has a face, and
    // the hairlines under them are these. A switch's and a strip's chosen line is the accent's (--acc).
    static let stripRule = hex(0x1c1b22)                              // dw.ph: .chips box-shadow
    static let segRule = hex(0x1c1b22)                                // dw.ph: .seg box-shadow
    static let cardRule = hex(0x1c1b22)                               // dw.ph: .card border-bottom
    // (R1c's review) The Mac's own: R2's card face, as R1b's phone drew its card (`.dw.ph .card`'s #1c1b22 before the
    // flat block) - the one face still drawn in it, the Mac's (RefreshProblemNote on the Mac's Downloaded and Songs
    // pages). Read from the rules before the flat block, so no change to the flat phone moves it: the Mac doesn't change.
    static let macCardFace = hex(0x1c1b22)                            // dw.ph: .card background (R1b)
    static let groupRule = hex(0x23212b)                              // dw.ph: .field border-bottom
    static let rowText = hex(0xffffff)                                // dw.ph: .field > label color
    static let kvLabel = hex(0xffffff)                                // dw.ph: .kv > span:first-child color
    static let rowRule = hex(0x1c1b22)                                // dw.ph: .row border-bottom-color
    static let metaRule = hex(0x34323c)                               // dw.ph: .meta .scope > i background

    // MARK: the phone's pieces: the mini player, the tab bar's items, the foot

    // (R1c) The mini player, the tab bar and the foot are the page's black under (or over) a hairline - (R1c's review)
    // the very colour of every page they sit on: `page`, `.dw.ph`'s own ground, which the album's and the playlist's
    // pages draw on the phone now too (R5 drew them on --bg, #0b0a10, a seam against the bars' black).
    static let page = hex(0x000000)                                   // dw.ph: .dw background
    static let miniFace = hex(0x000000)                               // dw.ph: .mini background
    // (R1c's review) The scrub's time tag over the mini player keeps the face it had, R1b's mini player's ground: on
    // the flat black bar a tag of the bar's own black would be its edge alone.
    static let scrubTagFace = hex(0x1c1b22)                           // dw.ph: .mini background (R1b)
    static let miniEdge = hex(0x1c1b22)                               // dw.ph: .mini border-top
    static let seekTrack = hex(0x2c2a36)                              // dw.ph: .mini > .prog background
    static let seekFill = horizontal(hex(0x9333ea), hex(0xc084fc))    // dw.ph: .mini > .prog > i background
    static let tabBarFace = hex(0x000000)                             // dw.ph: .tabbar background
    static let tabBarEdge = hex(0x1c1b22)                             // dw.ph: .tabbar border-top
    static let tabItemText = hex(0x8a8a9c)                            // dw.ph: .tabbar > a color
    // (R1c) .foot2 has no fill (`background: none`): drawn in the page's own black, so what scrolls under it
    // doesn't show through - the same black as the page's
    static let footFace = hex(0x000000)                               // dw.ph: .dw background
    static let footEdge = hex(0x1c1b22)                               // dw.ph: .foot2 border-top

    // MARK: the phone's pieces: the switch - on in the app's own purple

    static let switchEdge = deck(PrimaryButton.edge)                  // dw.ph: .sw border
    static let switchFace = vertical(deck(PrimaryButton.top), deck(PrimaryButton.bottom))    // dw.ph: .sw background
    static let switchShade = rgba(0, 0, 0, 0.4)                       // dw.ph: .sw box-shadow
    static let switchKnob = vertical(hex(0xffffff), hex(0xd9d6e6))    // dw.ph: .sw::after background
    static let switchKnobDrop = rgba(0, 0, 0, 0.5)                    // dw.ph: .sw::after box-shadow
    static let switchOffEdge = hex(0x2c2a36)                          // dw.ph: .sw.off border-color
    static let switchOffFace = hex(0x0c0b11)                          // dw.ph: .sw.off background
    static let switchOffKnob = vertical(hex(0x9a97ab), hex(0x6b6a7c)) // dw.ph: .sw.off::after background

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

    /// One of Core's colours (PrimaryButton's), in sRGB.
    private static func deck(_ colour: DeckRGBA) -> Color {
        Color(.sRGB, red: Double(colour.red) / 255, green: Double(colour.green) / 255, blue: Double(colour.blue) / 255,
              opacity: colour.alpha)
    }

    /// linear-gradient(to bottom, top, bottom).
    private static func vertical(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// linear-gradient(to right, left, right).
    private static func horizontal(_ left: Color, _ right: Color) -> LinearGradient {
        LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
    }
}
