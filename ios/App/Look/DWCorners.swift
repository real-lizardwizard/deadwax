import SwiftUI

/// The new look's corners on both devices (the Mac and iPhone redesign, slice R1b - notes/ios.md "The redesign, slice
/// R1b: the shared look, and the phone's pieces"; R1's MacCorners, moved here for both). James, 24 Nov: "Rounded on Mac
/// only"; 25 Nov: "keep the phone square as well". So each corner is its device's:
///
/// - `button`: buttons, fields, wells, a segmented control, a strip's button, a sidebar row - .btn's 4 on the Mac.
/// - `box`: a group box, a card, a folder tab's top, a toggle - .group's 5 on the Mac.
/// - `chip`: chips, a count, a small cover, the checkbox - .chip's 3 on the Mac.
///
/// On the phone each is Corners' (every one 0 since 15 Nov's "Actual corners"), as dw.css's last block draws the phone
/// (`.dw.ph .btn, .dw.ph .seg, ... { border-radius: 0; }`). tests/test_ios_mac_look.py holds the Mac's to dw.css;
/// tests/test_ios_phone_look.py and test_ios_palette.py the phone's to Corners'. Nothing else in App/Look, App/Mac or
/// App/Phone writes a radius. Round stays round: `roundShape` is the switch's (.sw's 14 on its 28 - no corner at all).
enum DWCorners {
    /// The Mac's: dw.css's radii.
    enum Mac {
        static let button: CGFloat = 4              // dw: .btn border-radius
        static let box: CGFloat = 5                 // dw: .group border-radius
        static let chip: CGFloat = 3                // dw: .chip border-radius
    }

    /// The phone's: Corners', square.
    enum Phone {
        static let button: CGFloat = Corners.control    // dw.ph: .btn border-radius
        static let box: CGFloat = Corners.card          // dw.ph: .group border-radius
        static let chip: CGFloat = Corners.control      // dw.ph: .chip border-radius
    }

    /// This device's.
    static var button: CGFloat { Platform.mac ? Mac.button : Phone.button }
    static var box: CGFloat { Platform.mac ? Mac.box : Phone.box }
    static var chip: CGFloat { Platform.mac ? Mac.chip : Phone.chip }

    /// The shapes, as CSS rounds a corner (a circle's quarter, not the continuous curve).
    static var buttonShape: RoundedRectangle { RoundedRectangle(cornerRadius: button, style: .circular) }
    static var boxShape: RoundedRectangle { RoundedRectangle(cornerRadius: box, style: .circular) }
    static var chipShape: RoundedRectangle { RoundedRectangle(cornerRadius: chip, style: .circular) }

    /// A folder tab (the Mac's): a box's corners at its top, its foot square on the strip (.tab's 5px 5px 0 0).
    static var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: box, topTrailingRadius: box, style: .circular)
    }

    /// Round, on either device: the switch (.sw), whose ends are half its height.
    static var roundShape: Capsule { Capsule(style: .circular) }
}
