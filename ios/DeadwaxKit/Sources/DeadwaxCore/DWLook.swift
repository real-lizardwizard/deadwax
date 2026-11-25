import Foundation

// The new look's sizes on both devices (the Mac and iPhone redesign, slice R1b - notes/ios.md "The redesign, slice R1b:
// the shared look, and the phone's pieces"; the build plan's section 2). James, 25 Nov: "Both together" - each shared
// piece is built for the Mac and the iPhone at once, each in its own device's sizes:
//
// - DWLook: the parts both devices draw (App/Look - buttons, fields, chips, counts, segments, the toggle, rows), as
//   `DWLook.of(device)`. The Mac's are MacLook's (dw.css's rules, held there by tests/test_ios_mac_look.py); the phone's
//   are dw.css's `.dw.ph` rules, the later of two winning where the canvas restyled the phone twice
//   (tests/test_ios_phone_look.py resolves the cascade and holds each, line by line, to the rule its comment names).
// - PhoneLook: the phone's own pieces' sizes (App/Phone - the strip, the compact top, the lit line, the mini player,
//   the tab bar's items, the cards and groups, the switch, the foot, the meta line), the phone's alone.
//
// In points, dw.css's CSS px. **On the phone each height is a minimum**, grown with the text size (`grows`); on the
// Mac each is exact, as a Mac's own controls are. The iPhone draws none of these until a slice redraws a screen with
// them: R1b changes no screen the phone draws today.

/// The shared parts' sizes on one device.
public struct DWLook: Equatable, Sendable {
    // MARK: buttons (.btn)

    /// .btn, .btn.sm and .btn.lg: a button, a small one and a large one (the phone's 48, an album's Play and Shuffle,
    /// Edit album's foot - the Mac draws no large button: its is a button's).
    public let buttonHeight: Double
    public let smallButtonHeight: Double
    public let largeButtonHeight: Double
    /// The room either side of a button's words (.btn's padding), a small one's and a large one's.
    public let buttonPadding: Double
    public let smallButtonPadding: Double
    public let largeButtonPadding: Double

    // MARK: fields (.in, .field)

    /// .in: a text field in its well.
    public let fieldHeight: Double
    /// .field: a field's row - on the phone a card's row, with its hairline.
    public let fieldRowHeight: Double
    /// .field > label: the label's width.
    public let labelWidth: Double

    // MARK: chips, counts, segments, the toggle

    /// .chip and .count.
    public let chipHeight: Double
    public let countHeight: Double
    /// .seg button and .seg.lg button: a segment and a large one, and the room either side of their words.
    public let segmentHeight: Double
    public let segmentPadding: Double
    public let largeSegmentHeight: Double
    public let largeSegmentPadding: Double
    /// .tog: Shuffle's and Repeat's toggles on the Mac; .tog.sm, the Library's Grid and List, on the phone.
    public let toggleSize: Double

    // MARK: rows (.row)

    /// .row, .row.tall and .row.grp: a list's row, a tall one (a song with its cover) and a heading's (the Mac has no
    /// tall row: its is a row's).
    public let rowHeight: Double
    public let tallRowHeight: Double
    public let groupRowHeight: Double

    // MARK: the device

    /// The least side of what a finger takes (the build plan's "a finger's targets at least 44", iOS's own): every
    /// control's target on the phone, larger than its face where the face is smaller. 0 on the Mac, whose pointer is
    /// exact - a control's target there is its face.
    public let target: Double
    /// Whether a height above is a minimum, grown with the text size (the phone), or exact (the Mac).
    public let grows: Bool

    /// The sizes `device` draws.
    public static func of(_ device: Device) -> DWLook {
        switch device {
        case .mac: return onMac
        case .iPhone: return onPhone
        }
    }

    /// How far a finger's target reaches past a face `height` tall, above it and below: half what the face lacks of
    /// `target`, none where the face is that tall already - and none on the Mac, whose target is 0. Never sideways: a
    /// target grown sideways would reach into the control beside it (the Library's Grid and List, 28 wide and 6 apart),
    /// so it reaches up and down alone, as LibrarySwitchControl's SegmentReach does ("never into the next segment").
    /// App/Look's DWTarget draws it.
    public func reach(_ height: Double) -> Double {
        max(0, (target - height) / 2)
    }

    /// The Mac's: MacLook's, dw.css's rules for the window - R1's, unchanged.
    static let onMac = DWLook(
        buttonHeight: MacLook.buttonHeight,             // dw: .btn height
        smallButtonHeight: MacLook.smallButtonHeight,   // dw: .btn.sm height
        largeButtonHeight: MacLook.buttonHeight,        // dw: .btn height
        buttonPadding: 11,                              // dw: .btn padding-left
        smallButtonPadding: 8,                          // dw: .btn.sm padding-left
        largeButtonPadding: 11,                         // dw: .btn padding-left
        fieldHeight: MacLook.fieldHeight,               // dw: .in height
        fieldRowHeight: MacLook.findHeight,             // dw: .field min-height
        labelWidth: MacLook.labelWidth,                 // dw: .field > label width
        chipHeight: MacLook.chipHeight,                 // dw: .chip height
        countHeight: MacLook.countHeight,               // dw: .count height
        segmentHeight: MacLook.segmentHeight,           // dw: .seg button height
        segmentPadding: 8,                              // dw: .seg button padding-left
        largeSegmentHeight: MacLook.largeSegmentHeight, // dw: .seg.lg button height
        largeSegmentPadding: 10,                        // dw: .seg.lg button padding-left
        toggleSize: MacLook.toggleSize,                 // dw: .tog width
        rowHeight: MacLook.rowHeight,                   // dw: .row height
        tallRowHeight: MacLook.rowHeight,               // dw: .row height
        groupRowHeight: MacLook.groupRowHeight,         // dw: .row.grp height
        target: 0,
        grows: false)

    /// The phone's: dw.css's `.dw.ph` rules, the later winning.
    static let onPhone = DWLook(
        buttonHeight: 36,                               // dw.ph: .btn height
        smallButtonHeight: 32,                          // dw.ph: .btn.sm height
        largeButtonHeight: 48,                          // dw.ph: .btn.lg height
        buttonPadding: 13,                              // dw.ph: .btn padding-left
        smallButtonPadding: 11,                         // dw.ph: .btn.sm padding-left
        largeButtonPadding: 13,                         // dw.ph: .btn.lg padding-left
        fieldHeight: 36,                                // dw.ph: .in height
        fieldRowHeight: 44,                             // dw.ph: .field min-height
        labelWidth: 88,                                 // dw.ph: .field > label width
        chipHeight: 22,                                 // dw.ph: .chip height
        countHeight: 17,                                // dw.ph: .count height
        segmentHeight: 28,                              // dw.ph: .seg button height
        segmentPadding: 12,                             // dw.ph: .seg button padding-left
        largeSegmentHeight: 38,                         // dw.ph: .seg.lg button height
        largeSegmentPadding: 0,                         // dw.ph: .seg.lg button padding-left
        toggleSize: 28,                                 // dw.ph: .tog.sm width
        rowHeight: 48,                                  // dw.ph: .row height
        tallRowHeight: 60,                              // dw.ph: .row.tall height
        groupRowHeight: 38,                             // dw.ph: .row.grp height
        target: 44,
        grows: true)
}

/// The phone's own pieces' words (App/Phone), the phone's alone.
public enum PhonePieceWords {
    /// What VoiceOver calls the compact top's back link: the page it goes back to, then "Back", as iOS's own back
    /// button is read ("Library, Back").
    public static func back(to page: String) -> String {
        "\(page), Back"
    }
}

/// The phone's own pieces' sizes (App/Phone), each a `.dw.ph` rule's - or, said so, the drawings' own inline style.
public enum PhoneLook {
    // MARK: the one-tap strip (.chips)

    /// A strip's button, and the room either side of its words.
    public static let strip: Double = 32                // dw.ph: .chips > button height
    public static let stripPadding: Double = 12         // dw.ph: .chips > button padding-left
    /// Between the buttons, the strip's sides and its foot.
    public static let stripGap: Double = 6              // dw.ph: .chips gap
    public static let stripSide: Double = 16            // dw.ph: .chips padding-left
    public static let stripFoot: Double = 10            // dw.ph: .chips padding-bottom

    // MARK: the compact top (.topbar, .big)

    /// The top, and the top with the page's own title in it (the Library's: iLibrary's inline 50).
    public static let top: Double = 44                  // dw.ph: .topbar height
    public static let titledTop: Double = 50            // drawn: iLibrary .topbar height
    /// Its sides (a titled top's leading side iLibrary's inline 16), and between what it holds.
    public static let topSide: Double = 12              // dw.ph: .topbar padding-left
    public static let titledTopSide: Double = 16        // drawn: iLibrary .topbar padding-left
    /// A titled top's title drawn closer (iLibrary's inline -0.5px).
    public static let titledTopTracking: Double = -0.5  // drawn: iLibrary .topbar title letter-spacing
    public static let topGap: Double = 8                // dw.ph: .topbar gap
    /// The large title under it: its room above, either side and below, and its letters drawn closer.
    public static let bigAbove: Double = 2              // dw.ph: .big padding-top
    public static let bigSide: Double = 16              // dw.ph: .big padding-left
    public static let bigBelow: Double = 10             // dw.ph: .big padding-bottom
    public static let bigTracking: Double = -0.6        // dw.ph: .big letter-spacing

    // MARK: the tab bar's items and the lit line (.tabbar)

    /// The bar (R4's), its room above the items, an item, its icon and the gap under the icon.
    public static let tabBar: Double = 83               // dw.ph: .tabbar height
    public static let tabBarTop: Double = 6             // dw.ph: .tabbar padding-top
    public static let tabItem: Double = 49              // dw.ph: .tabbar > a height
    public static let tabIcon: Double = 24              // dw.ph: .tabbar svg width
    public static let tabGap: Double = 3                // dw.ph: .tabbar > a gap
    /// The lit line over the shown tab: 24 x 2, square, on the bar's top edge - 7 above the item.
    public static let litLineWidth: Double = 24         // dw.ph: .tabbar > a.on::before width
    public static let litLineHeight: Double = 2         // dw.ph: .tabbar > a.on::before height
    public static let litLineLift: Double = 7           // dw.ph: .tabbar > a.on::before top

    // MARK: the mini player (.mini)

    /// The bar, its cover (flush left, the bar's height less its top edge), the seek line along its top, Play's target,
    /// between the cover and the words, and the room past Play.
    public static let mini: Double = 60                 // dw.ph: .mini height
    public static let miniCover: Double = 59            // dw.ph: .mini .cover width
    public static let seekLine: Double = 2              // dw.ph: .mini > .prog height
    public static let miniPlay: Double = 48             // dw.ph: .mini .key.big width
    public static let miniGap: Double = 10              // dw.ph: .mini gap
    public static let miniTrail: Double = 12            // dw.ph: .mini padding-right

    // MARK: cards and groups (.card, .group, .kv, .go)

    /// Inside a card.
    public static let cardPadding: Double = 12          // dw.ph: .card padding-top
    /// A group: the room above it (its legend's), inside its edge either side and at its ends.
    public static let groupAbove: Double = 28           // dw.ph: .group margin-top
    public static let groupSide: Double = 12            // dw.ph: .group padding-left
    public static let groupEnds: Double = 2             // dw.ph: .group padding-top
    /// The legend: how far above the group it stands, in from its side, and its line.
    public static let legendLift: Double = 23           // dw.ph: .group > .legend top
    public static let legendSide: Double = 2            // dw.ph: .group > .legend left
    public static let legendLine: Double = 16           // dw.ph: .group > .legend line-height
    /// A fact's row: its height, its label's width and between the two.
    public static let kvRow: Double = 42                // dw.ph: .kv min-height
    public static let kvLabelWidth: Double = 116        // dw.ph: .kv > span:first-child width
    public static let kvGap: Double = 8                 // dw.ph: .kv gap
    /// A row that goes somewhere, and between what it holds.
    public static let goRow: Double = 46                // dw.ph: .go min-height
    public static let goGap: Double = 8                 // dw.ph: .go gap

    // MARK: the switch (.sw)

    /// The switch, its knob and the knob's room inside its edge.
    public static let switchWidth: Double = 46          // dw.ph: .sw width
    public static let switchHeight: Double = 28         // dw.ph: .sw height
    public static let knob: Double = 22                 // dw.ph: .sw::after width
    public static let knobInset: Double = 2             // dw.ph: .sw::after top

    // MARK: the fixed bottom action (.foot2)

    /// The foot, between its buttons, and its sides.
    public static let foot: Double = 68                 // dw.ph: .foot2 height
    public static let footGap: Double = 10              // dw.ph: .foot2 gap
    public static let footSide: Double = 16             // dw.ph: .foot2 padding-left

    // MARK: the meta line (.meta)

    /// The line, between what it holds, its sides, and between a link's words and its caret.
    public static let meta: Double = 30                 // dw.ph: .meta height
    public static let metaGap: Double = 6               // dw.ph: .meta gap
    public static let metaLead: Double = 16             // dw.ph: .meta padding-left
    public static let metaTrail: Double = 10            // dw.ph: .meta padding-right
    public static let linkGap: Double = 5               // dw.ph: .meta .link gap
}
