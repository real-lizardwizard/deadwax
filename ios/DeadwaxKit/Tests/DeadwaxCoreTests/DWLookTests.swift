import Foundation
import Testing
@testable import DeadwaxCore

/// The new look's sizes on both devices (notes/ios.md "The redesign, slice R1b: the shared look, and the phone's
/// pieces"). tests/test_ios_phone_look.py holds every number to dw.css's rule, the Mac's to MacLook's; here, what they
/// must be together: the Mac's are R1's exactly, the phone's grow with the text, a finger's target is 44, and each
/// piece fits what holds it.
@Suite struct DWLookTests {
    @Test func theMacsAreR1sExactly() {
        let mac = DWLook.of(.mac)
        #expect(mac.buttonHeight == MacLook.buttonHeight && mac.smallButtonHeight == MacLook.smallButtonHeight)
        // the Mac draws no large button or tall row: each is the plain one's
        #expect(mac.largeButtonHeight == MacLook.buttonHeight && mac.tallRowHeight == MacLook.rowHeight)
        #expect(mac.fieldHeight == MacLook.fieldHeight && mac.fieldRowHeight == MacLook.findHeight)
        #expect(mac.labelWidth == MacLook.labelWidth && mac.chipHeight == MacLook.chipHeight)
        #expect(mac.countHeight == MacLook.countHeight && mac.toggleSize == MacLook.toggleSize)
        #expect(mac.segmentHeight == MacLook.segmentHeight && mac.largeSegmentHeight == MacLook.largeSegmentHeight)
        #expect(mac.rowHeight == MacLook.rowHeight && mac.groupRowHeight == MacLook.groupRowHeight)
        // R1's paddings: .btn 0 11px, .btn.sm 0 8px, .seg button 0 8px, .seg.lg button 0 10px
        #expect([mac.buttonPadding, mac.smallButtonPadding, mac.largeButtonPadding] == [11, 8, 11])
        #expect([mac.segmentPadding, mac.largeSegmentPadding] == [8, 10])
        // exact, and a pointer's: no target past a face
        #expect(!mac.grows && mac.target == 0)
        let macFaces = [mac.buttonHeight, mac.smallButtonHeight, mac.toggleSize, mac.segmentHeight, 0]
        #expect(macFaces.map { (face: Double) -> Double in mac.reach(face) } == [0, 0, 0, 0, 0])
    }

    @Test func thePhonesGrowAndTakeAFinger() {
        let phone = DWLook.of(.iPhone)
        #expect(phone.grows && phone.target == 44)
        // the build plan's sizes: button 36, small 32, large 48, field 36, chip 22, segment 28, rows 48/60, heading 38
        #expect([phone.buttonHeight, phone.smallButtonHeight, phone.largeButtonHeight] == [36, 32, 48])
        #expect([phone.fieldHeight, phone.chipHeight, phone.segmentHeight] == [36, 22, 28])
        #expect([phone.rowHeight, phone.tallRowHeight, phone.groupRowHeight] == [48, 60, 38])
        // each piece a finger takes, its target as DWTarget draws it - the face, reaching `reach` above and below:
        // 44 tall exactly where the face is smaller, the face itself where it isn't (the large button's 48)
        let faces = [phone.buttonHeight, phone.smallButtonHeight, phone.largeButtonHeight, phone.segmentHeight,
                     phone.largeSegmentHeight, phone.toggleSize, phone.fieldHeight, PhoneLook.strip]
        #expect(faces.map { (face: Double) -> Double in face + 2 * phone.reach(face) } == [44, 44, 48, 44, 44, 44, 44, 44])
        #expect([phone.reach(32), phone.reach(28), phone.reach(44), phone.reach(60)] == [6, 8, 0, 0])
        // and the rows and bars a finger takes whole are 44 at least as drawn
        for row in [phone.fieldRowHeight, PhoneLook.goRow, PhoneLook.top, PhoneLook.tabItem, PhoneLook.miniPlay,
                    PhoneLook.foot, phone.rowHeight] {
            #expect(row >= phone.target)
        }
    }

    @Test func thePhonesPiecesFitTogether() {
        let phone = DWLook.of(.iPhone)
        // a small button and a strip's button sit in the compact top; a large one in the foot
        #expect(phone.smallButtonHeight < PhoneLook.top && PhoneLook.strip < PhoneLook.top)
        #expect(phone.largeButtonHeight < PhoneLook.foot)
        // a titled top is the taller; the large title's room is the strip's sides'
        #expect(PhoneLook.titledTop > PhoneLook.top && PhoneLook.bigSide == PhoneLook.stripSide)
        // the mini player's cover is its height less its top edge; Play's target fits it
        #expect(PhoneLook.miniCover == PhoneLook.mini - 1 && PhoneLook.miniPlay < PhoneLook.mini)
        // a tab item sits in the bar under its room, and the lit line stands on the bar's top edge, over its hairline
        #expect(PhoneLook.tabBarTop + PhoneLook.tabItem < PhoneLook.tabBar)
        #expect(PhoneLook.litLineLift == PhoneLook.tabBarTop + 1)
        // the switch's knob sits inside its edge, the same room above and below
        #expect(PhoneLook.knob + 2 * PhoneLook.knobInset + 2 == PhoneLook.switchHeight)
        // a field's well fits its row; the legend stands in the room above its group, over the group's edge
        #expect(phone.fieldHeight < phone.fieldRowHeight)
        #expect(PhoneLook.legendLift < PhoneLook.groupAbove && PhoneLook.legendLine < PhoneLook.legendLift)
    }

    @Test func theBackLinkIsReadAsIOSsOwn() {
        #expect(PhonePieceWords.back(to: "Library") == "Library, Back")
    }

    @Test func theTwoDevicesAreTheirOwn() {
        #expect(DWLook.of(.mac) != DWLook.of(.iPhone))
        #expect(DWLook.of(.mac) == DWLook.onMac && DWLook.of(.iPhone) == DWLook.onPhone)
    }
}
