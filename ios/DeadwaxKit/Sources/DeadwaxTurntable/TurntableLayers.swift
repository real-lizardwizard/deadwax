// The turntable's drawing (notes/ios-specs/turntable.md 2.2-2.5, 5.1): the plinth, the platter, the record's face -
// vinyl, the label, the CD art, the grooves, the spindle - the sheen over it, the arm, its handle, and slice 4's fader
// and readout, as a Core Animation layer tree. QuartzCore and CoreGraphics only, no UIKit, so the same tree renders
// on ios.yml's macOS runner (`CALayer.render(in:)`, DeadwaxTurntableTests) and in the app, whose UIView hosts `root`.
// Each frame writes transforms and positions only (`set(_:)`), never a layout pass; everything that depends on the
// size is made in `lay(_:)`.
#if canImport(QuartzCore)
import CoreGraphics
import DeadwaxCore
import Foundation
import QuartzCore

/// A frame's state of the drawing: what turns, where the arm is, what is held.
public struct TurntableLook: Equatable {
    /// the face's turn, degrees clockwise (the deck's angle and the hand's turn together)
    public var angle = 0.0
    /// the arm's angle round its pivot, degrees clockwise (TurntableTrig.armAngle)
    public var arm = 0.0
    /// the needle, in stage units - where the handle is
    public var needle = StagePoint(x: 0, y: 0)
    /// the head lifted (2.5: from the press that takes the arm to its let-go) - grown, its shadow shown, on the bar
    public var lifted = false
    /// Reduce Motion: the head's lift a step, not eased
    public var still = false
    /// Increase Contrast: the handle's ring in Palette.text3
    public var contrast = false
    /// the fader and the readout (slice 4): the speed they show, nil to hide them
    public var speed: Double?
    /// the fader's knob taken (past the slop): the arm's lighter grey
    public var faderHeld = false
    public init() {}
}

public final class TurntableLayers {
    /// The plinth's drawing box, `layout.width` by `layout.height` points; its edge and the arm's counterweight reach
    /// past it (the room round it, 2.2).
    public let root = CALayer()
    public private(set) var layout: TurntableLayout
    /// The screen's scale: the grooves' image is made at it.
    public let scale: CGFloat

    let plinth = CALayer()
    let highlight = CALayer()
    let highlightLine = CAShapeLayer()
    let platter = CAShapeLayer()
    let face = CALayer()
    let labelBack = CAShapeLayer()
    let label = CALayer()
    let labelRing = CAShapeLayer()
    let disc = CALayer()
    let grooves = CALayer()
    let spindle = CAShapeLayer()
    let spindleRing = CAShapeLayer()
    let sheen = CAGradientLayer()
    let fader = CALayer()
    let faderSlot = CAShapeLayer()
    let faderMark = CAShapeLayer()
    let knob = CAShapeLayer()
    let grip = CAShapeLayer()
    /// The readout (TurntableReadout): drawn in the plinth's renders; the app hosts its own above the foot line
    /// (`drawsReadout` false).
    let readoutFace: TurntableReadout
    var readout: CALayer { readoutFace.root }
    public var drawsReadout = true
    let arm = CALayer()
    let weight = CAShapeLayer()
    let bar = CAShapeLayer()
    let head = CAShapeLayer()
    let pivot = CAShapeLayer()
    let handle = CAShapeLayer()

    private var look = TurntableLook()
    private var hasArt = false
    private var groovesMade: (size: Double, scale: CGFloat)?
    /// The head's lift as drawn: nil until the layers' first drawing (in init), which is never eased.
    private var headLifted: Bool?

    /// `flipped`: the layer tree's geometry made y-down - true on a Mac (its layers are y-up), false under a UIView
    /// (already y-down). Either way the drawing is the web's, top left at (0, 0).
    public init(layout: TurntableLayout, scale: CGFloat, flipped: Bool) {
        self.layout = layout
        self.scale = scale
        readoutFace = TurntableReadout(scale: scale)
        root.isGeometryFlipped = flipped
        root.masksToBounds = false
        for layer in [plinth, highlight, platter, face, sheen, fader, readoutFace.root, arm, pivot, handle] { root.addSublayer(layer) }
        highlight.addSublayer(highlightLine)
        for layer in [labelBack, label, labelRing, disc, grooves, spindle, spindleRing] as [CALayer] { face.addSublayer(layer) }
        for layer in [faderSlot, faderMark, knob, grip] { fader.addSublayer(layer) }
        for layer in [weight, bar, head] { arm.addSublayer(layer) }
        for layer in [root, plinth, highlight, highlightLine, platter, face, labelBack, label, labelRing, disc, grooves, spindle,
                      spindleRing, sheen, fader, faderSlot, faderMark, knob, grip, arm, weight, bar, head,
                      pivot, handle] as [CALayer] {
            layer.contentsScale = scale
            layer.actions = Self.noActions
        }
        style()
        lay(layout)
    }

    /// No implicit animation on anything: a frame's write is the frame (2.6). The head's lift is the one thing eased,
    /// with explicit animations of its own (`liftHead`, 2.5).
    static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(),
                                                 "contents": NSNull(), "hidden": NSNull(), "path": NSNull(),
                                                 "opacity": NSNull(), "strokeColor": NSNull(), "fillColor": NSNull(),
                                                 "backgroundColor": NSNull(), "borderColor": NSNull(), "string": NSNull(),
                                                 "foregroundColor": NSNull(), "frame": NSNull(), "sublayers": NSNull(),
                                                 "shadowOpacity": NSNull(), "shadowPath": NSNull(),
                                                 "shadowRadius": NSNull()]

    static func cg(_ colour: DeckRGBA) -> CGColor {
        CGColor(srgbRed: CGFloat(colour.red) / 255, green: CGFloat(colour.green) / 255, blue: CGFloat(colour.blue) / 255,
                alpha: CGFloat(colour.alpha))
    }

    /// `--dw-text-2`, the readout's words at 1x (not a turntable token: the theme's secondary text).
    static let text2 = DeckRGBA(0xA3, 0xA3, 0xB8)

    // MARK: the colours, once

    private func style() {
        let p = TurntablePalette.self
        plinth.backgroundColor = Self.cg(p.ttPlinth)
        plinth.borderColor = Self.cg(p.barEdge)
        plinth.borderWidth = TurntableFace.hairline
        highlight.masksToBounds = true
        highlightLine.fillColor = Self.cg(p.highlight)
        highlightLine.fillRule = .evenOdd
        platter.fillColor = Self.cg(p.ttPlatter)
        face.backgroundColor = Self.cg(p.ttVinyl)
        face.masksToBounds = true
        labelBack.fillColor = Self.cg(p.ttLabel)
        label.masksToBounds = true
        label.contentsGravity = .resizeAspectFill
        labelRing.fillColor = nil
        labelRing.strokeColor = Self.cg(p.ttLabelEdge)
        labelRing.lineWidth = TurntableFace.labelRing
        disc.masksToBounds = true
        disc.contentsGravity = .resizeAspectFill
        disc.isHidden = true
        spindle.fillColor = Self.cg(p.ttSpindle)
        spindleRing.fillColor = nil
        spindleRing.strokeColor = Self.cg(p.ttSpindleEdge)
        spindleRing.lineWidth = TurntableFace.spindleRing
        sheen.type = .conic
        sheen.masksToBounds = true
        // the web's stops (2.4): each colour white at the stop's alpha, each location its CSS angle over 360; the start
        // direction is 20 deg clockwise of the top, set in `lay` (the sheen's frame is the record's)
        sheen.colors = TurntableFace.sheenStops.map { (stop: (degrees: Double, alpha: Double)) -> CGColor in
            Self.cg(DeckRGBA(255, 255, 255, stop.alpha))
        }
        sheen.locations = TurntableFace.sheenStops.map { (stop: (degrees: Double, alpha: Double)) -> NSNumber in
            NSNumber(value: stop.degrees / 360)
        }
        faderSlot.fillColor = Self.cg(p.barTrack)
        faderSlot.strokeColor = Self.cg(p.barEdge)
        knob.strokeColor = Self.cg(p.ttPivotEdge)
        grip.fillColor = Self.cg(p.ttSpindle)
        weight.fillColor = Self.cg(p.ttArmWeight)
        bar.fillColor = Self.cg(p.ttArm)
        head.fillColor = Self.cg(p.ttArmHead)
        // the lift's shadow: round the head with no offset, so the arm's turn doesn't turn it; shown while held
        head.shadowColor = Self.cg(p.ttHeadShadow)
        head.shadowOffset = .zero
        head.shadowOpacity = 0
        pivot.fillColor = Self.cg(p.ttPivot)
        pivot.strokeColor = Self.cg(p.ttPivotEdge)
        handle.fillColor = nil
        handle.lineWidth = TurntableFace.handleEdge
        handle.lineDashPattern = [NSNumber(value: TurntableFace.handleDash), NSNumber(value: TurntableFace.handleDash)]
        fader.isHidden = true
        readout.isHidden = true
    }

    // MARK: the size

    /// Everything that depends on the plinth's size: frames, paths, the grooves' image. Then the frame's state again.
    public func lay(_ layout: TurntableLayout) {
        self.layout = layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let w = layout.width, h = layout.height
        let k = layout.across(1)
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        // the plinth's border is outside its drawing box, so the drawing keeps the stage's exact shape - the web's is
        // border-box (player.css), inside its box, so this plinth is 1 pt wider each side than the web's in the same
        // room (the label's and the spindle's rings are inside theirs, as the web's: TurntableFaceParts)
        plinth.frame = CGRect(x: -TurntableFace.hairline, y: -TurntableFace.hairline, width: w + 2 * TurntableFace.hairline,
                              height: h + 2 * TurntableFace.hairline)
        plinth.cornerRadius = TurntableFace.plinthRadius
        // the top highlight: 1 pt inside the top edge, following the corners (box-shadow: inset 0 1px 0)
        highlight.frame = root.bounds
        highlight.cornerRadius = TurntableFace.plinthRadius - TurntableFace.hairline
        let inner = CGMutablePath()
        let r = TurntableFace.plinthRadius - TurntableFace.hairline
        inner.addRoundedRect(in: root.bounds, cornerWidth: r, cornerHeight: r)
        inner.addRoundedRect(in: root.bounds.offsetBy(dx: 0, dy: TurntableFace.highlight), cornerWidth: r, cornerHeight: r)
        highlightLine.frame = root.bounds
        highlightLine.path = inner

        platter.frame = root.bounds
        platter.path = CGPath(ellipseIn: rect(layout.platter), transform: nil)

        let record = rect(layout.record)
        let d = record.width
        face.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        face.position = CGPoint(x: record.midX, y: record.midY)
        face.cornerRadius = d / 2
        let parts = TurntableFaceParts(layout)
        let centre = CGPoint(x: d / 2, y: d / 2)
        labelBack.frame = face.bounds
        labelBack.path = circle(centre, parts.labelOuter)
        label.frame = CGRect(x: centre.x - parts.label, y: centre.y - parts.label, width: 2 * parts.label, height: 2 * parts.label)
        label.cornerRadius = parts.label
        labelRing.frame = face.bounds
        labelRing.path = circle(centre, parts.label + TurntableFace.labelRing / 2)
        disc.frame = face.bounds
        disc.cornerRadius = d / 2
        grooves.frame = face.bounds
        if groovesMade?.size != Double(d) || groovesMade?.scale != scale {
            grooves.contents = Self.grooves(diameter: d, scale: scale)
            groovesMade = (size: Double(d), scale: scale)   // spelled out: Xcode 26.6's Swift won't convert inside a tuple
        }
        spindle.frame = face.bounds
        spindle.path = circle(centre, parts.spindleOuter)
        spindleRing.frame = face.bounds
        spindleRing.path = circle(centre, parts.spindle + TurntableFace.spindleRing / 2)

        sheen.frame = record
        sheen.cornerRadius = d / 2
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        let start = (TurntableFace.sheenFrom - 90) * .pi / 180
        sheen.endPoint = CGPoint(x: 0.5 + 0.5 * cos(start), y: 0.5 + 0.5 * sin(start))

        // the fader and the readout, in the stage's units (SpeedFader.tsx)
        fader.frame = root.bounds
        let f = PlaySpeed.fader, knobSize = PlaySpeed.knob, mark = PlaySpeed.mark
        let spanTop = f.top - knobSize.height / 2, span = f.bottom - f.top + knobSize.height
        faderSlot.frame = root.bounds
        faderSlot.path = rounded(CGRect(x: (f.x - f.slot / 2) * k, y: spanTop * k, width: f.slot * k, height: span * k), f.slotRadius * k)
        faderSlot.lineWidth = k
        faderMark.frame = root.bounds
        knob.frame = root.bounds
        knob.lineWidth = k
        grip.frame = root.bounds
        _ = mark

        // the arm, in its own frame: the pivot at the origin, the bar along +x (Turntable.tsx's rects)
        let a = TurntableGeometry.self
        arm.bounds = .zero
        arm.position = point(layout.pivot)
        weight.path = rounded(CGRect(x: a.armWeight.from * k, y: -a.armWeight.thick / 2 * k, width: a.armWeight.length * k,
                                     height: a.armWeight.thick * k), a.armWeight.radius * k)
        bar.path = rounded(CGRect(x: 0, y: -a.armBar.thick / 2 * k, width: a.arm.reach * k, height: a.armBar.thick * k), a.armBar.radius * k)
        // the head is a layer of its own size, its middle on the bar, so the lift grows it about that middle
        let headBox = CGRect(x: 0, y: 0, width: a.armHead.length * k, height: a.armHead.thick * k)
        head.bounds = headBox
        head.position = CGPoint(x: (a.armHead.from + a.armHead.length / 2) * k, y: 0)
        head.path = rounded(headBox, a.armHead.radius * k)
        head.shadowPath = head.path
        head.shadowRadius = a.headLift.shadow * k
        pivot.frame = root.bounds
        pivot.path = circle(point(layout.pivot), (a.armBase - a.armBaseEdge / 2) * k)
        pivot.lineWidth = a.armBaseEdge * k
        let size = layout.handleSize
        handle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        handle.path = circle(CGPoint(x: size / 2, y: size / 2), size / 2 - TurntableFace.handleEdge / 2)
        apply(look)
    }

    // MARK: each frame

    /// A frame: the face's turn, the arm's angle and lift, the handle at the needle, the fader's knob - transforms and
    /// positions, no implicit animation.
    public func set(_ next: TurntableLook) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(next)
        CATransaction.commit()
    }

    private func apply(_ next: TurntableLook) {
        look = next
        let k = layout.across(1)
        face.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(next.angle * .pi / 180)))
        arm.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(next.arm * .pi / 180)))
        if headLifted != next.lifted {
            liftHead(next.lifted, eased: headLifted != nil && !next.still)
            headLifted = next.lifted
        }
        handle.position = point(layout.point(next.needle))
        handle.strokeColor = Self.cg(next.contrast ? TurntablePalette.textTertiary : TurntablePalette.ttHandleEdge)
        if let speed = next.speed {
            fader.isHidden = false
            readout.isHidden = !drawsReadout
            drawFader(speed, held: next.faderHeld, k: k)
        } else {
            fader.isHidden = true
            readout.isHidden = true
        }
    }

    /// The head lifted or set down (2.5): grown about its own middle and its shadow shown, or back - eased each way from
    /// where it is on screen, so a tap that sets it down mid-lift turns back rather than jumping; `eased` false (the
    /// layers' first drawing, Reduce Motion) is the step alone.
    private func liftHead(_ lifted: Bool, eased: Bool) {
        let lift = TurntableGeometry.headLift
        let grown = CGFloat(lift.scale)
        let transform = lifted ? CATransform3DMakeScale(grown, grown, 1) : CATransform3DIdentity
        let shadow: Float = lifted ? 1 : 0
        if eased {
            let shown = head.presentation()
            // --dw-ease, the web's curve for the same lift
            let ease = TurntableGeometry.headLiftEase
            let timing = CAMediaTimingFunction(controlPoints: Float(ease.x1), Float(ease.y1), Float(ease.x2), Float(ease.y2))
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: shown?.transform ?? head.transform)
            grow.toValue = NSValue(caTransform3D: transform)
            let fade = CABasicAnimation(keyPath: "shadowOpacity")
            fade.fromValue = NSNumber(value: shown?.shadowOpacity ?? head.shadowOpacity)
            fade.toValue = NSNumber(value: shadow)
            for animation in [grow, fade] {
                animation.duration = lift.seconds
                animation.timingFunction = timing
            }
            head.add(grow, forKey: "lift")
            head.add(fade, forKey: "liftShadow")
        } else {
            head.removeAnimation(forKey: "lift")
            head.removeAnimation(forKey: "liftShadow")
        }
        head.transform = transform
        head.shadowOpacity = shadow
    }

    private func drawFader(_ speed: Double, held: Bool, k: Double) {
        let p = TurntablePalette.self
        let f = PlaySpeed.fader, size = PlaySpeed.knob, mark = PlaySpeed.mark
        let scale = PlaySpeedScale(PlatformMaths())
        func y(_ s: Double) -> Double { f.bottom - scale.faderShare(s) * (f.bottom - f.top) }
        let normal = speed == PlaySpeed.normal
        faderMark.path = CGPath(rect: CGRect(x: (f.x - size.width / 2 - mark.overhang) * k, y: (y(PlaySpeed.normal) - mark.thick / 2) * k,
                                             width: (size.width + 2 * mark.overhang) * k, height: mark.thick * k), transform: nil)
        faderMark.fillColor = Self.cg(normal ? p.greenIcon : p.textTertiary)
        let knobY = y(speed)
        knob.path = rounded(CGRect(x: (f.x - size.width / 2) * k, y: (knobY - size.height / 2) * k, width: size.width * k,
                                   height: size.height * k), size.radius * k)
        knob.fillColor = Self.cg(held ? p.ttArm : p.ttArmWeight)
        grip.path = CGPath(rect: CGRect(x: (f.x - size.width / 2 + size.gripInset) * k, y: (knobY - size.grip / 2) * k,
                                        width: (size.width - 2 * size.gripInset) * k, height: size.grip * k), transform: nil)
        // the readout: its words a label's size, smaller with the plinth
        guard drawsReadout else { return }
        readoutFace.set(speed, points: TurntableReadout.points(layout))
        readout.position = point(layout.readout)
    }

    // MARK: the pictures

    /// The label's cover (the album's), nil for none: the label's own #141414.
    public func setCover(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.contents = image
        CATransaction.commit()
    }

    /// The CD art over the whole face, nil for none - the label shown again (2.3).
    public func setArt(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.contents = image
        hasArt = image != nil
        disc.isHidden = !hasArt
        label.isHidden = hasArt
        labelBack.isHidden = hasArt
        labelRing.isHidden = hasArt
        CATransaction.commit()
    }

    /// The grooves (2.4): `--dw-tt-grooves`, a repeating radial gradient of black - clear to 2 pt, 0.2 at 3, clear at
    /// 4 - from the face's centre, in points; one image for the face's size and the screen's scale, made once. Each
    /// pixel's alpha is the gradient's at its centre's distance, as a browser computes a gradient per pixel.
    static func grooves(diameter: Double, scale: CGFloat) -> CGImage? {
        let pixels = Int((diameter * Double(scale)).rounded(.up))
        guard pixels > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: pixels * pixels * 4)
        let centre = diameter / 2, s = Double(scale)
        for row in 0..<pixels {
            let dy = (Double(row) + 0.5) / s - centre
            for column in 0..<pixels {
                let dx = (Double(column) + 0.5) / s - centre
                let r = (dx * dx + dy * dy).squareRoot()
                guard r <= centre + 1 else { continue }
                let alpha = grooveAlpha(r)
                if alpha > 0 { data[(row * pixels + column) * 4 + 3] = UInt8((alpha * 255).rounded()) }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The grooves' black at a distance from the centre, points: TurntableFace.grooveStops, repeating.
    static func grooveAlpha(_ r: Double) -> Double {
        let period = TurntableFace.groovePeriod
        let m = r - (r / period).rounded(.down) * period
        let stops = TurntableFace.grooveStops
        for i in 1..<stops.count where m <= stops[i].at {
            let a = stops[i - 1], b = stops[i]
            let t = b.at > a.at ? (m - a.at) / (b.at - a.at) : 0
            return a.alpha + (b.alpha - a.alpha) * t
        }
        return stops.last?.alpha ?? 0
    }

    // MARK: helpers

    func rect(_ box: StageBox) -> CGRect { CGRect(x: box.left, y: box.top, width: box.width, height: box.height) }
    func point(_ p: StagePoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    func circle(_ centre: CGPoint, _ r: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    func rounded(_ r: CGRect, _ radius: Double) -> CGPath {
        let corner = Swift.min(radius, Double(Swift.min(r.width, r.height)) / 2)
        return CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    /// A translucent colour laid over an opaque one (the readout's well over the plinth, app.css's gradient over it).
    static func over(_ top: DeckRGBA, _ under: DeckRGBA) -> DeckRGBA {
        func mix(_ a: Int, _ b: Int) -> Int { Int((Double(a) * top.alpha + Double(b) * (1 - top.alpha)).rounded()) }
        return DeckRGBA(mix(top.red, under.red), mix(top.green, under.green), mix(top.blue, under.blue))
    }
}
#endif
