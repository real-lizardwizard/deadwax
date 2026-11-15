import DeadwaxCore
import SwiftUI
import UIKit

// The transport's glyphs and the Library tab's, with actual corners (15 Nov; Core's SharpGlyph holds the shapes, what
// they were measured from and why; notes/ios.md "Actual corners").

extension SharpGlyph {
    /// Its outline in `frame`: the template's frame, as SwiftUI lays the symbol out.
    func path(in frame: CGRect) -> Path {
        var path = Path()
        for polygon in polygons {
            path.addLines(polygon.map { (point: SharpGlyph.Point) -> CGPoint in
                CGPoint(x: frame.minX + CGFloat(point.x) * frame.width, y: frame.minY + CGFloat(point.y) * frame.height)
            })
            path.closeSubpath()
        }
        return path
    }

    /// The glyph as an image, for the Large Content Viewer, which shows images, not shapes: drawn in its template's
    /// frame at 44 points (the room grown to hold a point past the frame), as a template image that takes the viewer's
    /// colour. Made once each.
    var image: UIImage { Self.images[self] ?? UIImage() }

    private static let images: [SharpGlyph: UIImage] = {
        var made: [SharpGlyph: UIImage] = [:]
        for glyph in SharpGlyph.allCases {
            let symbol = UIImage(systemName: glyph.template, withConfiguration: UIImage.SymbolConfiguration(pointSize: 44))
            let size = symbol?.size ?? CGSize(width: 44, height: 44)
            let box = glyph.box
            let left = CGFloat(min(box.left, 0)), top = CGFloat(min(box.top, 0))
            let right = CGFloat(max(box.right, 1)), bottom = CGFloat(max(box.bottom, 1))
            let room = CGSize(width: size.width * (right - left), height: size.height * (bottom - top))
            let frame = CGRect(x: -left * size.width, y: -top * size.height, width: size.width, height: size.height)
            let drawn = UIGraphicsImageRenderer(size: room).image { (_: UIGraphicsImageRendererContext) -> Void in
                UIColor.black.setFill()
                UIBezierPath(cgPath: glyph.path(in: frame).cgPath).fill()
            }
            made[glyph] = drawn.withRenderingMode(.alwaysTemplate)
        }
        return made
    }()
}

/// A sharp glyph where its SF Symbol was: the symbol, hidden, takes its frame at the font from outside (`.font`, a
/// Label's, `.symbolVariant`) - so the glyph is the size the symbol was at every text size and grows with Dynamic Type
/// as it did - and the shape fills that frame with the foreground style, as a symbol does. Hidden from VoiceOver: its
/// button says what it does.
struct SharpSymbol: View {
    let glyph: SharpGlyph

    init(_ glyph: SharpGlyph) {
        self.glyph = glyph
    }

    var body: some View {
        Image(systemName: glyph.template)
            .hidden()
            .overlay {
                GlyphShape(glyph: glyph)
            }
            .accessibilityHidden(true)
    }
}

/// Play/Pause's glyph: pause while playing, play while not - crossfaded over 0.15 s as it turns (the symbols were
/// swapped at once; at once under Reduce Motion, as the EQ's are), in the room of the larger, so the button never
/// changes size.
struct PlayPauseGlyph: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SharpSymbol(.play)
                .opacity(playing ? 0 : 1)
            SharpSymbol(.pause)
                .opacity(playing ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: playing)
    }
}

private struct GlyphShape: Shape {
    let glyph: SharpGlyph

    func path(in rect: CGRect) -> Path {
        glyph.path(in: rect)
    }
}
