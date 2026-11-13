// The speed's readout (notes/ios-specs/turntable.md 5.1, 2.11, 2.14): "1.00x" in a well at the plinth's bottom right
// corner, purple in the toggled face while the speed isn't 1x - app.css's .app-tt-readout-face. Its own small layer
// tree, so the plinth's renders draw it (TurntableLayers) and the app hosts the same drawing in a control of its own,
// laid over the plinth ABOVE the line a failure lays across the plinth's foot, as the web's z-index puts it.
#if canImport(QuartzCore)
import CoreGraphics
import DeadwaxCore
import Foundation
import QuartzCore

public final class TurntableReadout {
    /// The face: its fill over the plinth's colour (opaque, so a line under it is hidden, not read through), its
    /// hairline edge, its corners. Its bounds are the face's size; the host sets its position.
    public let root = CALayer()
    /// `--dw-well-inset` (inset 0 1px 1px black at 0.5) at 1x: a 1 pt band inside the top edge, following the corners.
    /// Its 1 px blur isn't drawn.
    let inset = CAShapeLayer()
    let text = CATextLayer()
    /// The words' face at a size, points: nil draws Menlo (a Mac's render); the app gives the system's monospaced font.
    public var font: ((Double) -> CFTypeRef)?

    /// `--dw-leading-label`, and `--app-tt-readout-pad`: 0.15em by 0.4em.
    static let leading = 1.3
    static let pad = (down: 0.15, across: 0.4)
    /// A monospaced face's advance, of its size: Menlo's and SF Mono's are both 0.6 em.
    static let advance = 0.6

    public init(scale: CGFloat) {
        for layer in [root, inset, text] as [CALayer] {
            layer.contentsScale = scale
            layer.actions = TurntableLayers.noActions
        }
        root.addSublayer(inset)
        root.addSublayer(text)
        root.borderWidth = TurntableFace.hairline
        root.cornerRadius = TurntableFace.lookRadius
        root.masksToBounds = true
        inset.fillColor = TurntableLayers.cg(TurntablePalette.wellInset)
        inset.fillRule = .evenOdd
        text.alignmentMode = .center
        text.font = "Menlo-Regular" as CFString
    }

    /// The words' size, points, for a plinth: a label's (12 pt, grown with Dynamic Type by the app: `scaled`), but never
    /// more than 3.2% of the room the plinth is drawn in either way - app.css's min(--dw-text-label, 3.2cqw, 3.2cqh) -
    /// so on a small plinth it never spills over the record.
    public static func points(_ layout: TurntableLayout, scaled: Double = 12) -> Double {
        Swift.min(scaled, 0.032 * (layout.width + 2 * TurntableFace.pad),
                  0.032 * (layout.height + TurntableFace.clear + TurntableFace.pad))
    }

    /// The face's size for a speed's words at `points`: the words, the padding and the edge.
    public static func size(_ speed: Double, points: Double) -> CGSize {
        let words = Double(TurntableWords.speedLabel(speed).count)
        let width = words * points * advance + 2 * pad.across * points + 2 * TurntableFace.hairline
        let height = points * leading + 2 * pad.down * points + 2 * TurntableFace.hairline
        return CGSize(width: width, height: height)
    }

    /// Draws the face for `speed` at `points`, its fill laid on the plinth's colour.
    public func set(_ speed: Double, points: Double) {
        let p = TurntablePalette.self
        let normal = speed == PlaySpeed.normal
        let size = Self.size(speed, points: points)
        root.bounds = CGRect(origin: .zero, size: size)
        root.borderColor = TurntableLayers.cg(normal ? p.barEdge : p.toggledEdge)
        root.backgroundColor = TurntableLayers.cg(TurntableLayers.over(normal ? p.ttWell : p.toggledFill, p.ttPlinth))
        // the inset band inside the edge: the inner box less itself moved down a point
        let edge = TurntableFace.hairline
        let inner = root.bounds.insetBy(dx: edge, dy: edge)
        let r = Swift.max(0, TurntableFace.lookRadius - edge)
        let band = CGMutablePath()
        band.addRoundedRect(in: inner, cornerWidth: r, cornerHeight: r)
        band.addRoundedRect(in: inner.offsetBy(dx: 0, dy: 1), cornerWidth: r, cornerHeight: r)
        inset.frame = root.bounds
        inset.path = band
        inset.isHidden = !normal
        text.fontSize = points
        if let font { text.font = font(points) }
        text.string = TurntableWords.speedLabel(speed)
        text.foregroundColor = TurntableLayers.cg(normal ? TurntableLayers.text2 : p.accentText)
        text.frame = CGRect(x: 0, y: (Double(size.height) - points * 1.2) / 2, width: Double(size.width), height: points * 1.2)
    }
}
#endif
