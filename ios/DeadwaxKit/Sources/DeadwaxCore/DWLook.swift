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
    /// The room either side of a button's words (.btn's padding), a small one's and a large one's - on the phone a flat
    /// button's (R1c; the faced ones' are DWFlat's).
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

    /// .chip and .count. (R1c) The phone's chip is words with no face (`height: auto`): 0, its words' own height.
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

    // MARK: a meter (.meter)

    /// .meter: a download's bar, its track and its fill (R8's DWMeter) - on the phone grown with the text.
    public let meterHeight: Double

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

    /// (R8) How much of a meter's track its fill takes, for `fraction` (0 to 1) of the way: never past its track, never
    /// less than none: a download's 104% full, -3% empty, and a value that is no number (NaN, an infinity) empty.
    /// App/Look's DWMeter draws it.
    public static func meterShare(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
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
        meterHeight: 6,                                 // dw: .meter height
        target: 0,
        grows: false)

    /// The phone's: dw.css's `.dw.ph` rules, the later winning. (R1c) The phone is flat: a button's room either side
    /// is a flat one's, words with no face (`.dw.ph .btn`); the faced two, the purple and the red, keep DWFlat's.
    static let onPhone = DWLook(
        buttonHeight: 36,                               // dw.ph: .btn height
        smallButtonHeight: 32,                          // dw.ph: .btn.sm height
        largeButtonHeight: 48,                          // dw.ph: .btn.lg height
        buttonPadding: 6,                               // dw.ph: .btn padding-left
        smallButtonPadding: 6,                          // dw.ph: .btn.sm padding-left
        largeButtonPadding: 6,                          // dw.ph: .btn.lg padding-left
        fieldHeight: 36,                                // dw.ph: .in height
        fieldRowHeight: 44,                             // dw.ph: .field min-height
        labelWidth: 88,                                 // dw.ph: .field > label width
        chipHeight: 0,                                  // dw.ph: .chip height
        countHeight: 17,                                // dw.ph: .count height
        segmentHeight: 28,                              // dw.ph: .seg button height
        segmentPadding: 12,                             // dw.ph: .seg button padding-left
        largeSegmentHeight: 40,                         // dw.ph: .seg.lg button height
        largeSegmentPadding: 0,                         // dw.ph: .seg.lg button padding-left
        toggleSize: 28,                                 // dw.ph: .tog.sm width
        rowHeight: 48,                                  // dw.ph: .row height
        tallRowHeight: 60,                              // dw.ph: .row.tall height
        groupRowHeight: 38,                             // dw.ph: .row.grp height
        meterHeight: 8,                                 // dw.ph: .meter height
        target: 44,
        grows: true)
}

/// (The redesign, slice R1c - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)"; James, 25 Nov: "on
/// ios, I want to try to get rid of all the grey boxes") The flat phone's sizes that App/Look's shared pieces draw on the
/// phone alone, each a `.dw.ph` rule's - kept apart from DWLook, whose parts both devices hold. The Mac draws none of
/// them.
public enum DWFlat {
    /// The faced buttons' room either side of their words, every size (`.btn.pri`, and `.btn.red` as much): a flat
    /// button's is DWLook's.
    public static let facedPadding: Double = 16         // dw.ph: .btn.pri padding-left
    public static let smallFacedPadding: Double = 16    // dw.ph: .btn.sm.pri padding-left
    public static let largeFacedPadding: Double = 16    // dw.ph: .btn.lg.pri padding-left
    /// The accent's line under the chosen one - a switch's segment, a strip's words.
    public static let chosenLine: Double = 2            // dw.ph: .seg button.on box-shadow
    /// The least room a large switch keeps either side of its words before it folds (DWSegmentedNeed), so two
    /// neighbouring words never come closer than twice it. (R1c's review) **R1c's own room, no rule of dw.css's**: the
    /// drawing's `.seg.lg button` has none (padding 0), so the slice chose 6, as much as a flat button's (`.dw.ph .btn`'s,
    /// DWLook's buttonPadding). It is what
    /// makes the four pages' switch (logins off, the break-glass sign-in) fold under the glyphs at the standard size
    /// (notes/ios.md R1c's departures).
    public static let segmentRoom: Double = 6           // own: the switch's room, R1c's
    /// A status chip: the dot before its words, between the two, and the room either side of it.
    public static let dot: Double = 6                   // dw.ph: .chip.green::before width
    public static let dotGap: Double = 6                // dw.ph: .chip gap
    public static let chipSide: Double = 5              // dw.ph: .chip margin-left
    /// (R1c's review) A chip that keeps R1b's face on the phone (the New mark - DWChip's `keepsFace`): 22 tall at least,
    /// R1b's `.dw.ph .chip`, as it was before the flat block made a chip as tall as its words.
    public static let facedChipHeight: Double = 22      // dw.ph: .chip height (R1b)
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

    /// A strip's words (R1c: no face), and the room either side of them - none: the gap between them is the room.
    public static let strip: Double = 40                // dw.ph: .chips > button height
    public static let stripPadding: Double = 0          // dw.ph: .chips > button padding-left
    /// Between the words, the strip's sides, and under its hairline.
    public static let stripGap: Double = 22             // dw.ph: .chips gap
    public static let stripSide: Double = 16            // dw.ph: .chips padding-left
    public static let stripFoot: Double = 10            // dw.ph: .chips margin-bottom

    // MARK: the compact top (.topbar, .big)

    /// The top (R2's titled top, the Library's, went in R2b: its one row is .ltop's, below).
    public static let top: Double = 44                  // dw.ph: .topbar height
    /// Its sides, and between what it holds.
    public static let topSide: Double = 12              // dw.ph: .topbar padding-left
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

    /// (R1c) Above and below a card's words, which sit on the page over its hairline - none at its sides.
    public static let cardPadding: Double = 14          // dw.ph: .card padding-top
    /// A group: the room above it (its heading's), either side (R1c: none - no edge) and at its ends.
    public static let groupAbove: Double = 28           // dw.ph: .group margin-top
    public static let groupSide: Double = 0             // dw.ph: .group padding-left
    public static let groupEnds: Double = 2             // dw.ph: .group padding-top
    /// The heading (R1c: the legend, with no panel under it): how far above the group it stands, in from its side,
    /// and its line.
    public static let legendLift: Double = 23           // dw.ph: .group > .legend top
    public static let legendSide: Double = 0            // dw.ph: .group > .legend left
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

    /// The line, between what it holds, its sides, and between a link's words and its caret. (R2b) The Library's
    /// pages - the only ones drawing it - have it 32 tall and 16 in at the right too (iLibrary's, iArtists' and
    /// iPlaylists' inline style: `height: 32px; padding-right: 16px`).
    public static let meta: Double = 32                 // drawn: iLibrary .meta height
    public static let metaGap: Double = 6               // dw.ph: .meta gap
    public static let metaLead: Double = 16             // dw.ph: .meta padding-left
    public static let metaTrail: Double = 16            // drawn: iLibrary .meta padding-right
    public static let linkGap: Double = 5               // dw.ph: .meta .link gap
    /// (R2b) Grid and List at the line's end, bare glyphs: each one's square, between the two, and the room after them
    /// before Yours | All.
    public static let metaGlyph: Double = 28            // dw.ph: .meta .v width
    public static let metaGlyphGap: Double = 2          // dw.ph: .meta .views gap
    public static let metaGlyphsAfter: Double = 10      // dw.ph: .meta .views margin-right
    /// (R2b) Yours | All: between each word and the hairline, and the hairline's height.
    public static let sidesGap: Double = 10             // dw.ph: .meta .scope gap
    public static let sidesRule: Double = 12            // dw.ph: .meta .scope > i height

    // MARK: the Library's one row (.ltop, .circ)

    /// (R2b - James, 25 Nov: "The top of the library on iOS is actually kinda a mess, can we streamline it a bit?")
    /// The row: its height, how far in from each edge, and between Find's circle, the switch and the •••.
    public static let row: Double = 52                  // dw.ph: .ltop height
    public static let rowSide: Double = 16              // dw.ph: .ltop padding-left
    public static let rowGap: Double = 12               // dw.ph: .ltop gap
    /// Find's and the •••'s (R1c: bare glyphs, no face - the circle in name only): the box each glyph is centred in,
    /// inside a finger's target.
    public static let circle: Double = 36               // dw.ph: .circ width
    public static let circleHeight: Double = 34         // dw.ph: .circ height
}

/// (R2b) A size in points, as SwiftUI measured a view, for the layout rules Core holds so they are tested here
/// (MetaLine, LibraryTopFit) - the app's own Layouts measure, ask Core where each view goes, and place it there.
public struct LookSize: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// (R2b) Where a view goes in a layout Core lays out: its top leading corner in the layout's own space, and the size it
/// is given there.
public struct LookBox: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// `size` centred on (`midX`, `midY`).
    public init(centredOn midX: Double, _ midY: Double, _ size: LookSize) {
        self.init(x: midX - size.width / 2, y: midY - size.height / 2, width: size.width, height: size.height)
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
}

/// (R2b) The Library's quiet line (PhoneMeta): its words - the count, then the order or New playlist… - and its end
/// (Grid and List, Yours | All). Where all of it doesn't fit on one line, it gives way inside itself first: the count's
/// noun dropped ("2318 · Year, newest first", "12 of 140 · Recently added" - VoiceOver still hears "2318 albums"). Only
/// where even that doesn't fit does its end fold onto a line of its own under the words, at the trailing edge - the
/// count saying its noun again, unless even then the words need more than the line, when they wrap. The order's words
/// and New playlist… are never shortened, and no word is ever cut. Each way is measured as it is drawn (PhoneMeta's
/// ViewThatFits, tried in `Fit`'s order), so a face or a text size of its own moves where the line gives way, never
/// whether it cuts a word. (The review of R2b, 25 Nov: folding at the standard size on every phone James has - "140
/// albums · Recently added" 351 pt of a 375 pt phone's 343 - a list dropping 32 pt at Find's first keystroke.)
public enum MetaLine {
    /// The ways the line is drawn, in the order they are tried: the first whose width fits is drawn, the last where none
    /// does.
    public enum Fit: CaseIterable, Sendable, Equatable {
        /// one line, the count in full
        case full
        /// one line, the count's noun dropped
        case short
        /// the end on a line of its own, the count in full
        case folded
        /// the end on a line of its own, the count's noun dropped, the words wrapping in the line should they need to
        case foldedShort

        /// The count drawn without its noun.
        public var short: Bool { self == .short || self == .foldedShort }
        /// The end on a line of its own.
        public var folded: Bool { self == .folded || self == .foldedShort }
    }

    /// The count without its noun - "2318 albums" "2318", "12 of 140 albums" "12 of 140", "1 song" "1": the count as
    /// Find's countText and filteredCountText say it, numbers first and the noun last. Words with no noun stay as they
    /// are, "" too.
    public static func short(_ count: String) -> String {
        guard let space = count.lastIndex(of: " ") else { return count }
        return String(count[..<space])
    }

    /// The count's words as `fit` draws them.
    public static func count(_ count: String, _ fit: Fit) -> String {
        fit.short ? short(count) : count
    }

    /// How wide the line is at its two ends' own widths: on one line, the words, then - with anything at its end - the
    /// room between and the end; folded, the wider of its two lines.
    public static func width(words: Double, end: Double, folded: Bool) -> Double {
        if folded { return max(words, end) }
        return end > 0 ? words + 2 * PhoneLook.metaGap + end : words
    }

    /// The way the line is drawn in `room`: its words `full` wide with the count in full and `short` wide without its
    /// noun, its end `end` wide - the first of `Fit`'s ways whose width fits the room, the last where none does. What
    /// PhoneMeta's ViewThatFits does with the widths it measures.
    public static func fit(full: Double, short: Double, end: Double, room: Double) -> Fit {
        Fit.allCases.first { (each: Fit) -> Bool in
            width(words: each.short ? short : full, end: end, folded: each.folded) <= room
        } ?? .foldedShort
    }

    /// What the words are given across in `room`: the whole line, folded or with nothing at its end; on one line, what
    /// the end and the room before it leave.
    public static func wordsRoom(_ room: Double, end: Double, folded: Bool) -> Double {
        folded || end <= 0 ? room : max(0, room - end - 2 * PhoneLook.metaGap)
    }

    /// Where the line's words and its end go in `room`, at their sizes (the words' in the room they are given), and the
    /// line's size.
    public struct Placed: Sendable, Equatable {
        public let words: LookBox
        public let end: LookBox
        public let width: Double
        public let height: Double
    }

    /// On one line, the words at the leading edge and the end at the trailing one, each centred in the line. Folded, the
    /// words centred in the first line and the end under them at the trailing edge, each line as tall as the line is
    /// drawn at least (PhoneLook.meta) - and with nothing at the end, no second line.
    public static func place(words: LookSize, end: LookSize, room: Double, folded: Bool) -> Placed {
        if folded {
            let first = max(words.height, PhoneLook.meta)
            let second = end.width > 0 ? max(end.height, PhoneLook.meta) : 0
            return Placed(words: LookBox(x: 0, y: (first - words.height) / 2, width: words.width, height: words.height),
                          end: LookBox(x: room - end.width, y: first + (second - end.height) / 2, width: end.width,
                                       height: end.height),
                          width: room, height: first + second)
        }
        let height = max(words.height, end.height)
        return Placed(words: LookBox(x: 0, y: (height - words.height) / 2, width: words.width, height: words.height),
                      end: LookBox(x: room - end.width, y: (height - end.height) / 2, width: end.width, height: end.height),
                      width: room, height: height)
    }
}
