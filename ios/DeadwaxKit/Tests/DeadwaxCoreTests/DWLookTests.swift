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
        // the build plan's sizes: button 36, small 32, large 48, field 36, segment 28, rows 48/60, heading 38 - and
        // (R1c) the chip's 0: coloured words with no face, as tall as its words
        #expect([phone.buttonHeight, phone.smallButtonHeight, phone.largeButtonHeight] == [36, 32, 48])
        #expect([phone.fieldHeight, phone.chipHeight, phone.segmentHeight] == [36, 0, 28])
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
        // the large title's room is the strip's sides'
        #expect(PhoneLook.bigSide == PhoneLook.stripSide)
        // (R2b) the Library's row: its glyphs' boxes and the large switch (R1c: its words over its hairline, 1 pt in
        // at either end) inside it, the glyphs' targets too; as far in from each edge as the pages are, and the line
        // under it as far in
        #expect(PhoneLook.circle < PhoneLook.row && PhoneLook.circleHeight < PhoneLook.circle)
        #expect(phone.largeSegmentHeight + 2 < PhoneLook.row)
        #expect(phone.target < PhoneLook.row && PhoneLook.circle < phone.target)
        #expect(PhoneLook.rowSide == PhoneLook.stripSide && PhoneLook.rowSide == PhoneLook.metaLead)
        #expect(PhoneLook.metaTrail == PhoneLook.metaLead, "iLibrary's line is 16 in at either side")
        // a glyph's target reaches 4 past its box sideways, into the 12 between it and the switch - never to it
        #expect((phone.target - PhoneLook.circle) / 2 < PhoneLook.rowGap)
        // (27 Nov) the line's choices fit the line, their targets reaching above and below it as every target does; a
        // glyph's box and a chosen one's line inside a choice's height
        #expect(PhoneLook.opt < PhoneLook.meta && PhoneLook.optGlyph < PhoneLook.opt)
        #expect(DWFlat.chosenLine < PhoneLook.opt && phone.target > PhoneLook.opt)
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

    /// (R1c) The flat phone's own sizes: the faced buttons' room either side more than a flat one's, every size; the
    /// chosen line under its words inside a strip's and a switch's height, and the strip taller than its words' line;
    /// a chip's dot no taller than its words' gap from it.
    @Test func theFlatPhonesSizesFitTogether() {
        let phone = DWLook.of(.iPhone)
        #expect([DWFlat.facedPadding, DWFlat.smallFacedPadding, DWFlat.largeFacedPadding] == [16, 16, 16])
        #expect([phone.buttonPadding, phone.smallButtonPadding, phone.largeButtonPadding] == [6, 6, 6])
        #expect(DWFlat.facedPadding > phone.buttonPadding && DWFlat.segmentRoom == phone.buttonPadding)
        #expect(DWFlat.chosenLine < PhoneLook.strip && DWFlat.chosenLine < phone.segmentHeight)
        #expect(PhoneLook.stripPadding == 0 && PhoneLook.stripGap > 2 * DWFlat.segmentRoom)
        #expect(DWFlat.dot == DWFlat.dotGap && DWFlat.chipSide < DWFlat.dot)
        // the Mac's are untouched: R1's
        let mac = DWLook.of(.mac)
        #expect([mac.buttonPadding, mac.smallButtonPadding, mac.largeButtonPadding] == [11, 8, 11])
        #expect(mac.chipHeight == MacLook.chipHeight)
    }

    /// (R2b, its review) The count gives way first: its noun dropped, the numbers kept - as Find's own words say them.
    @Test func theCountsShortFormDropsItsNounAlone() {
        #expect(MetaLine.short(Find.countText(2318, one: "album", many: "albums")) == "2318")
        #expect(MetaLine.short(Find.filteredCountText(shown: 12, total: 140, one: "album", many: "albums")) == "12 of 140")
        #expect(MetaLine.short(Find.countText(1, one: "song", many: "songs")) == "1")
        #expect(MetaLine.short(LibrarySwitchWords.playlistsCount(total: 9, shown: 3, finding: true)) == "3 of 9")
        #expect(MetaLine.short("") == "" && MetaLine.short("2318") == "2318", "no noun: as it is")
        // drawn as each way says: the folded line says its noun again
        let count = "140 albums"
        #expect(MetaLine.Fit.allCases.map { (fit: MetaLine.Fit) -> String in MetaLine.count(count, fit) }
                == ["140 albums", "140", "140 albums", "140"])
    }

    /// (R2b, its review) A quiet line tries its ways in order - one line, then one line with the count's noun dropped,
    /// then its end folded under its words, then folded with the noun dropped - and draws the first that fits: it folds
    /// only where even the short count doesn't fit, and never with nothing at its end.
    @Test func aQuietLineGivesWayInsideItselfBeforeItFolds() {
        #expect(MetaLine.Fit.allCases == [.full, .short, .folded, .foldedShort])
        #expect(MetaLine.Fit.allCases.map(\.short) == [false, true, false, true])
        #expect(MetaLine.Fit.allCases.map(\.folded) == [false, false, true, true])
        // one line: the words, the 6 either side of the room between them, the end; folded, the wider line
        #expect(MetaLine.width(words: 200, end: 131, folded: false) == 343)
        #expect(MetaLine.width(words: 200, end: 0, folded: false) == 200, "nothing at its end: no room before it")
        #expect(MetaLine.width(words: 200, end: 131, folded: true) == 200)
        #expect(MetaLine.width(words: 100, end: 131, folded: true) == 131)
        // 343 pt of line on a 375 pt phone (16 in at either side)
        #expect(MetaLine.fit(full: 200, short: 150, end: 131, room: 343) == .full, "200 + 12 + 131 = 343: held")
        #expect(MetaLine.fit(full: 200.5, short: 150, end: 131, room: 343) == .short)
        #expect(MetaLine.fit(full: 300, short: 200, end: 131, room: 343) == .short)
        #expect(MetaLine.fit(full: 300, short: 200.5, end: 131, room: 343) == .folded, "folded, the count in full")
        #expect(MetaLine.fit(full: 350, short: 250, end: 131, room: 343) == .foldedShort)
        #expect(MetaLine.fit(full: 400, short: 350, end: 131, room: 343) == .foldedShort, "none fits: the last")
        #expect(MetaLine.fit(full: 300, short: 200, end: 0, room: 343) == .full)
        #expect(MetaLine.fit(full: 400, short: 300, end: 0, room: 343) == .short)
        // the words' room: on one line what the end leaves them, folded or with no end the whole line
        #expect(MetaLine.wordsRoom(343, end: 131, folded: false) == 200)
        #expect(MetaLine.wordsRoom(343, end: 131, folded: true) == 343)
        #expect(MetaLine.wordsRoom(343, end: 0, folded: false) == 343)
        #expect(MetaLine.wordsRoom(100, end: 131, folded: false) == 0)
    }

    /// (27 Nov - the Library's line underlines what is chosen) The line's end as LibraryLineEnd draws it now: each
    /// choice its words or glyph and 3 either side (`.opt`), the two of a pair 6 apart with no hairline between, and the
    /// pairs the line's 6 and the pair's 14 apart - iLibrary's numbers.
    @Test func aQuietLinesEndIsItsChoicesAtTheirSpacing() {
        #expect([PhoneLook.opt, PhoneLook.optPadding, PhoneLook.optGlyph] == [28, 3, 17])
        #expect([PhoneLook.pairGap, PhoneLook.pairAfter, PhoneLook.metaGap] == [6, 14, 6])
        // Grid and List as drawn, each 17 in its 23: 23 + 6 + 23
        #expect(MetaLine.end([[17, 17]]) == 52)
        // Yours | All alone (Artists', Playlists', Songs'): "Yours" 30 and "All" 15 - 36 + 6 + 21, where R2b's hairline
        // and its 10 either side made it 66
        #expect(MetaLine.end([[30, 15]]) == 63)
        // both, on Albums: 52, then 6 + 14, then 63
        #expect(MetaLine.end([[17, 17], [30, 15]]) == 135)
        // nothing at the end: no pair drawn, no room between them
        #expect(MetaLine.end([]) == 0 && MetaLine.end([[], []]) == 0)
        #expect(MetaLine.end([[], [30, 15]]) == 63, "Grid and List on Albums alone: Yours | All with no room before it")
        #expect(MetaLine.end([[17, 17], []]) == 52, "Grid and List with no Yours | All after them: no 14")
        // a pair's choices each hold their room - a wider word widens the end by itself alone
        #expect(MetaLine.end([[17, 17], [31.5, 15]]) - MetaLine.end([[17, 17], [30, 15]]) == 1.5)
    }

    /// (27 Nov) And the line gives way at its new end exactly as before (R2b's review): the first of its ways whose
    /// width fits - one line, the count's noun dropped, then its end folded - the end now its choices at their spacing.
    @Test func aQuietLineFoldsAtItsNewEnd() {
        let albums = MetaLine.end([[17, 17], [30, 15]])
        let sides = MetaLine.end([[30, 15]])
        // on a 375 pt phone's 343: words 196 wide and Albums' end of 135 are 196 + 12 + 135 = 343, one line
        #expect(MetaLine.width(words: 196, end: albums, folded: false) == 343)
        #expect(MetaLine.fit(full: 196, short: 150, end: albums, room: 343) == .full)
        #expect(MetaLine.fit(full: 196.5, short: 150, end: albums, room: 343) == .short, "the noun dropped first")
        #expect(MetaLine.fit(full: 300, short: 196.5, end: albums, room: 343) == .folded, "then folded, in full")
        #expect(MetaLine.fit(full: 350, short: 343, end: albums, room: 343) == .foldedShort)
        // R2b's end for the same words (Grid and List 28 square, 2 apart, 10 and 6 before Yours, a hairline 10 either
        // side) was 58 + 16 + 66 = 140: a line 196 wide went short there, and is whole now
        #expect(MetaLine.fit(full: 196, short: 150, end: 140, room: 343) == .short)
        // Yours | All alone leaves the words 343 - 12 - 63 = 268
        #expect(MetaLine.wordsRoom(343, end: sides, folded: false) == 268)
        #expect(MetaLine.fit(full: 268, short: 200, end: sides, room: 343) == .full)
        #expect(MetaLine.fit(full: 268.5, short: 200, end: sides, room: 343) == .short)
        // folded, the end alone on its line: as wide as it, at the trailing edge, 32 under the words' line
        let folded = MetaLine.place(words: LookSize(width: 300, height: 18), end: LookSize(width: albums, height: 28),
                                    room: 343, folded: true)
        #expect(folded.end == LookBox(x: 343 - albums, y: 32 + 2, width: albums, height: 28))
        #expect(MetaLine.width(words: 300, end: albums, folded: true) == 300)
    }

    /// (R2b, its review) The line's two ends where they are drawn: on one line, the words leading and the end trailing,
    /// each centred in the line; folded, the end under the words at the trailing edge, each line 32 tall at least.
    @Test func aQuietLinesEndsAreWhereTheyAreDrawn() {
        let words = LookSize(width: 180, height: 18)
        let end = LookSize(width: 131, height: 28)
        let line = MetaLine.place(words: words, end: end, room: 343, folded: false)
        #expect(line.words == LookBox(x: 0, y: 5, width: 180, height: 18))
        #expect(line.end == LookBox(x: 212, y: 0, width: 131, height: 28))
        #expect(line.end.maxX == 343 && line.width == 343 && line.height == 28)
        let folded = MetaLine.place(words: words, end: end, room: 343, folded: true)
        #expect(folded.words == LookBox(x: 0, y: 7, width: 180, height: 18))
        #expect(folded.end == LookBox(x: 212, y: 32 + 2, width: 131, height: 28))
        #expect(folded.height == 64 && folded.end.midY == 32 + 16, "the end centred in a second 32")
        // words wrapped onto two lines make the first line as tall as they are
        let wrapped = MetaLine.place(words: LookSize(width: 343, height: 40), end: end, room: 343, folded: true)
        #expect(wrapped.end.y == 40 + 2 && wrapped.height == 72)
        // nothing at its end: no second line
        let alone = MetaLine.place(words: words, end: LookSize(width: 0, height: 0), room: 343, folded: true)
        #expect(alone.height == 32)
    }

    @Test func theBackLinkIsReadAsIOSsOwn() {
        #expect(PhonePieceWords.back(to: "Library") == "Library, Back")
    }

    @Test func theTwoDevicesAreTheirOwn() {
        #expect(DWLook.of(.mac) != DWLook.of(.iPhone))
        #expect(DWLook.of(.mac) == DWLook.onMac && DWLook.of(.iPhone) == DWLook.onPhone)
    }
}
