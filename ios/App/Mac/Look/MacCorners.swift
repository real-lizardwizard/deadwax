import SwiftUI

/// The Mac redesign's corners (slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared pieces").
/// James, 24 Nov: "Rounded on Mac only" - the design's corners on the Mac, through these alone; the iPhone stays square
/// (Corners, every one 0 since 15 Nov's "Actual corners"). Each is dw.css's (tests/test_ios_mac_look.py holds them):
///
/// - `button`: buttons, fields, wells, a segmented control, a sidebar row - .btn's 4.
/// - `box`: a group box, a folder tab's top, a toggle - .group's 5.
/// - `chip`: chips, a count, a small cover - .chip's 3.
///
/// Nothing else in ios/App/Mac writes a radius (the same test, and test_ios_palette.py's corners). Round stays round:
/// the player's keys are circles.
enum MacCorners {
    static let button: CGFloat = 4      // dw: .btn border-radius
    static let box: CGFloat = 5         // dw: .group border-radius
    static let chip: CGFloat = 3        // dw: .chip border-radius

    /// The shapes, as CSS rounds a corner (a circle's quarter, not the continuous curve).
    static var buttonShape: RoundedRectangle { RoundedRectangle(cornerRadius: button, style: .circular) }
    static var boxShape: RoundedRectangle { RoundedRectangle(cornerRadius: box, style: .circular) }
    static var chipShape: RoundedRectangle { RoundedRectangle(cornerRadius: chip, style: .circular) }

    /// A folder tab: a box's corners at its top, its foot square on the strip (.tab's border-radius: 5px 5px 0 0).
    static var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: box, topTrailingRadius: box, style: .circular)
    }
}
