import Testing
@testable import DeadwaxCore

// The sharp glyphs (15 Nov, SharpGlyph): the transport's and the Library tab's, drawn with actual corners at the
// weight of the rounded SF Symbols they replace.
@Suite struct SharpGlyphTests {
    private func inked(_ glyph: SharpGlyph) -> Double {
        glyph.polygons.reduce(0) { (sum: Double, polygon: [SharpGlyph.Point]) -> Double in
            sum + SharpGlyph.area(polygon)
        }
    }

    @Test func eachInksWhatItsSymbolDid() {
        for glyph in SharpGlyph.allCases {
            let difference = abs(inked(glyph) - glyph.inkArea)
            #expect(difference < 1e-9, "\(glyph)")
        }
    }

    @Test func eachSitsWhereItsSymbolsInkDid() {
        for glyph in SharpGlyph.allCases {
            let box = glyph.box.centre
            let ink = glyph.ink.centre
            let off = max(abs(box.x - ink.x), abs(box.y - ink.y))
            #expect(off < 1e-9, "\(glyph)")
        }
    }

    @Test func roundingCutTheTrianglesSoTheyGrowAndTheRectanglesHardly() {
        // a triangle's rounded points cost it most: play's box grows about 8%, next's 9%; pause's and the stack's
        // straight sides cost little, so they shrink under 1.5%
        let play = SharpGlyph.play.box.width / SharpGlyph.play.ink.width
        let next = SharpGlyph.next.box.width / SharpGlyph.next.ink.width
        let pause = SharpGlyph.pause.box.width / SharpGlyph.pause.ink.width
        let stack = SharpGlyph.library.box.width / SharpGlyph.library.ink.width
        #expect(play > 1.07 && play < 1.10)
        #expect(next > 1.08 && next < 1.10)
        #expect(pause > 0.985 && pause < 1)
        #expect(stack > 0.985 && stack < 1)
    }

    @Test func noneReachesFarPastItsFrame() {
        for glyph in SharpGlyph.allCases {
            let points = glyph.polygons.flatMap { (polygon: [SharpGlyph.Point]) -> [SharpGlyph.Point] in polygon }
            let xs = points.map { (point: SharpGlyph.Point) -> Double in point.x }
            let ys = points.map { (point: SharpGlyph.Point) -> Double in point.y }
            let reach = max(-(xs.min() ?? 0), (xs.max() ?? 1) - 1, -(ys.min() ?? 0), (ys.max() ?? 1) - 1)
            #expect(reach < 0.03, "\(glyph)")
        }
    }

    @Test func pausesBarsArePauseFills() {
        let bars = SharpGlyph.pause.polygons
        #expect(bars.count == 2)
        let box = SharpGlyph.pause.box
        let first = bars[0].map { (point: SharpGlyph.Point) -> Double in point.x }
        let second = bars[1].map { (point: SharpGlyph.Point) -> Double in point.x }
        let width = ((first.max() ?? 0) - (first.min() ?? 0)) / box.width
        let gap = ((second.min() ?? 0) - (first.max() ?? 0)) / box.width
        #expect(abs(width - 0.4048) < 1e-9)
        #expect(abs(gap - 0.1904) < 1e-9)
    }

    @Test func previousIsNextTurnedRound() {
        // backward.fill is forward.fill mirrored, and inks a hair more: the two glyphs mirror within a thousandth
        let next = SharpGlyph.next.polygons.flatMap { (polygon: [SharpGlyph.Point]) -> [SharpGlyph.Point] in polygon }
        let previous = SharpGlyph.previous.polygons.flatMap { (polygon: [SharpGlyph.Point]) -> [SharpGlyph.Point] in
            polygon
        }
        var worst = 0.0
        for point in previous {
            let mirrored = SharpGlyph.Point(x: 1 - point.x, y: point.y)
            let nearest = next.map { (other: SharpGlyph.Point) -> Double in
                max(abs(other.x - mirrored.x), abs(other.y - mirrored.y))
            }.min() ?? 1
            worst = max(worst, nearest)
        }
        #expect(worst < 1e-3)
    }

    @Test func theLibrarysFrontCardIsASquare() {
        // square.stack.fill's frame at 44 points is 48.62 by 61.12: the front card's sides in points
        let front = SharpGlyph.library.polygons[2]
        let xs = front.map { (point: SharpGlyph.Point) -> Double in point.x }
        let ys = front.map { (point: SharpGlyph.Point) -> Double in point.y }
        let wide = ((xs.max() ?? 0) - (xs.min() ?? 0)) * 48.62
        let tall = ((ys.max() ?? 0) - (ys.min() ?? 0)) * 61.12
        #expect(abs(wide - tall) < 0.1)
        // and at its foot, the two cards behind it above, each narrower
        let near = SharpGlyph.library.polygons[1].map { (point: SharpGlyph.Point) -> Double in point.x }
        let far = SharpGlyph.library.polygons[0].map { (point: SharpGlyph.Point) -> Double in point.x }
        let nearWidth = (near.max() ?? 0) - (near.min() ?? 0)
        let farWidth = (far.max() ?? 0) - (far.min() ?? 0)
        #expect(farWidth < nearWidth)
        #expect(nearWidth < wide / 48.62)
    }

    @Test func playPointsRightFromTheMiddle() {
        let tip = SharpGlyph.play.polygons[0][1]
        let box = SharpGlyph.play.box
        let off = max(abs(tip.x - box.right), abs(tip.y - box.centre.y))
        #expect(off < 1e-12)
    }

    @Test func theTemplatesAreTheFilledSymbols() {
        let names = SharpGlyph.allCases.map { (glyph: SharpGlyph) -> String in glyph.template }
        #expect(names == ["play.fill", "pause.fill", "forward.fill", "backward.fill", "square.stack.fill"])
    }
}
