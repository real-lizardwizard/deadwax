import Foundation

/// The transport's glyphs and the Library tab's, with actual corners (15 Nov, James: "let's square off everything
/// already square a bit more. Actual corners. The pause, skip buttons, etc. I like the square look. Even the library
/// icon should be a bit more square."; notes/ios.md "Actual corners").
///
/// SF Symbols' play, pause, forward, backward and square.stack are rounded at every corner, and SF Symbols has none
/// with sharp corners to ask for. So each is drawn as straight lines meeting at points, laid by the app into the very
/// frame its SF Symbol takes at the font in use (the symbol is still there, hidden, as the template).
///
/// Measured, not guessed: SwiftUI's own rendering of each symbol at 44 points (ImageRenderer at 8x on the Mac, 15 Nov -
/// the symbols are iOS's artwork) gave the frame SwiftUI lays it into, where its ink sits in that frame (`ink`, as
/// fractions of it, top-down) and how much of the frame it inks (`inkArea`). Each sharp glyph is its shape in the
/// symbol's ink box, grown or shrunk about the box's centre until it inks just as much as the rounded symbol did: the
/// same weight. Rounding a triangle cuts most at its points, so play and the skip pair grow 8-9% and their points reach
/// a little past where the rounded ones stopped (the skip pair's past their frames' edges, by under 3% of the frame,
/// the overlay unclipped); pause's bars and the stack, rectangles, shrink under 1.5%. Measured at the regular weight;
/// at semibold the template's larger frame carries the weight's size, its ink some 5% heavier than the sharp glyph's.
///
/// Pure, so it is tested on Linux; the app's Shared/SharpGlyphs.swift draws `polygons` as a SwiftUI path.
public enum SharpGlyph: CaseIterable, Sendable {
    case play, pause, next, previous, library

    /// A point in fractions of the template's frame, top-down.
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// A rectangle in fractions of the template's frame, top-down.
    public struct Box: Equatable, Sendable {
        public let left: Double
        public let top: Double
        public let right: Double
        public let bottom: Double

        public init(left: Double, top: Double, right: Double, bottom: Double) {
            self.left = left
            self.top = top
            self.right = right
            self.bottom = bottom
        }

        public var width: Double { right - left }
        public var height: Double { bottom - top }
        public var centre: Point { Point(x: (left + right) / 2, y: (top + bottom) / 2) }
    }

    /// The SF Symbol it replaces, whose frame it takes - the filled one, as each place drew it.
    public var template: String {
        switch self {
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .library: return "square.stack.fill"
        }
    }

    /// Where the template's ink sits in its frame (measured, as above).
    public var ink: Box {
        switch self {
        case .play: return Box(left: 0.1429, top: 0.0883, right: 0.9773, bottom: 0.9117)
        case .pause: return Box(left: 0.1477, top: 0.0893, right: 0.8523, bottom: 0.9078)
        case .next: return Box(left: 0.0849, top: 0.0954, right: 0.9865, bottom: 0.9015)
        case .previous: return Box(left: 0.0135, top: 0.0954, right: 0.9151, bottom: 0.9015)
        case .library: return Box(left: 0.1131, top: 0.0634, right: 0.8869, bottom: 0.8793)
        }
    }

    /// How much of the template's frame its ink covers (measured, as above).
    public var inkArea: Double {
        switch self {
        case .play: return 0.4039
        case .pause: return 0.4589
        case .next: return 0.4330
        case .previous: return 0.4333
        case .library: return 0.5116
        }
    }

    /// Pause's bars, each this share of the box's width (pause.fill's: 0.405, 0.19 between them).
    public static let bar = 0.4048

    /// Its shape in a unit box (0...1 both ways, top-down): polygons that don't overlap.
    var unit: [[Point]] {
        switch self {
        case .play:
            return [[Point(x: 0, y: 0), Point(x: 1, y: 0.5), Point(x: 0, y: 1)]]
        case .pause:
            return [Self.rect(0, 0, Self.bar, 1), Self.rect(1 - Self.bar, 0, 1, 1)]
        case .next:
            // two triangles, point to base: the first's point on the second's base, at the middle
            return [[Point(x: 0, y: 0), Point(x: 0.5, y: 0.5), Point(x: 0, y: 1)],
                    [Point(x: 0.5, y: 0), Point(x: 1, y: 0.5), Point(x: 0.5, y: 1)]]
        case .previous:
            return [[Point(x: 1, y: 0), Point(x: 0.5, y: 0.5), Point(x: 1, y: 1)],
                    [Point(x: 0.5, y: 0), Point(x: 0, y: 0.5), Point(x: 0.5, y: 1)]]
        case .library:
            // square.stack.fill's own parts, measured the same way, squared: the front card a true square at the foot
            // (37.6 points a side at 44), the two cards behind it strips above, each narrower, with its gaps
            return [Self.rect(0.2375, 0, 0.7625, 0.0552), Self.rect(0.1197, 0.1128, 0.8803, 0.1754),
                    Self.rect(0, 0.2456, 1, 1)]
        }
    }

    /// The box it is drawn in: the ink's, grown or shrunk about its centre so the sharp shape inks `inkArea`.
    public var box: Box {
        let ink = self.ink
        let drawn = unit.reduce(0) { (sum: Double, polygon: [Point]) -> Double in sum + Self.area(polygon) }
        let scale = (inkArea / (drawn * ink.width * ink.height)).squareRoot()
        let centre = ink.centre
        let halfWidth = ink.width * scale / 2
        let halfHeight = ink.height * scale / 2
        return Box(left: centre.x - halfWidth, top: centre.y - halfHeight, right: centre.x + halfWidth,
                   bottom: centre.y + halfHeight)
    }

    /// Its polygons in the template's frame (fractions, top-down) - what the app draws.
    public var polygons: [[Point]] {
        let box = self.box
        return unit.map { (polygon: [Point]) -> [Point] in
            polygon.map { (point: Point) -> Point in
                Point(x: box.left + point.x * box.width, y: box.top + point.y * box.height)
            }
        }
    }

    /// A polygon's area (the shoelace formula), whichever way round it goes.
    public static func area(_ polygon: [Point]) -> Double {
        guard polygon.count > 2 else { return 0 }
        var twice = 0.0
        for index in polygon.indices {
            let here = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            twice += here.x * next.y - next.x * here.y
        }
        return abs(twice) / 2
    }

    private static func rect(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [Point] {
        [Point(x: left, y: top), Point(x: right, y: top), Point(x: right, y: bottom), Point(x: left, y: bottom)]
    }
}
