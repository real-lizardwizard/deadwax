// The turntable's drawing, rendered on a Mac (notes/ios-specs/turntable.md 7.3): each state of 2.8 that changes the
// drawing, at the iPhone 16's plinth (321 pt) and the SE's (284 pt), at 3x, written as PNGs to $TURNTABLE_RENDERS
// (ios.yml uploads them as the job's artifact) - and the checks that don't need an eye: the sheen's brightest band at
// 48 deg clockwise of the top, the label's ring where the web's is, the grooves' period 4 pt, the readout's colours
// the Palette's, the head 5 units up when lifted.
#if canImport(QuartzCore) && canImport(ImageIO)
import CoreGraphics
@testable import DeadwaxCore
@testable import DeadwaxTurntable
import Foundation
import ImageIO
import QuartzCore
import Testing

/// A render: the room round the plinth (24 pt above, 12 round it) at 3x, its pixels readable by the plinth's points.
struct Render {
    static let scale = 3.0
    let layers: TurntableLayers
    let width: Int, height: Int
    let pixels: [UInt8]
    let image: CGImage

    init(_ layers: TurntableLayers) {
        self.layers = layers
        let layout = layers.layout
        let roomW = layout.width + 2 * TurntableFace.pad, roomH = layout.height + TurntableFace.clear + TurntableFace.pad
        width = Int((roomW * Self.scale).rounded(.up))
        height = Int((roomH * Self.scale).rounded(.up))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Now Playing's backdrop under it: the app's dark ground
        context.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // y-down: the room's top left at (0, 0), the plinth at (12, 24)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(Self.scale), y: -CGFloat(Self.scale))
        context.translateBy(x: TurntableFace.pad, y: TurntableFace.clear)
        // render(in:) draws the root in the context's own geometry (its isGeometryFlipped is for a superlayer), so the
        // y-down context is what makes it the web's way up; the flag keeps its contents and words upright in it
        layers.root.layoutIfNeeded()
        layers.root.render(in: context)
        image = context.makeImage()!
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        pixels = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
    }

    /// The pixel at a plinth point (points from the plinth's top left), RGB 0-255.
    func at(_ x: Double, _ y: Double) -> (r: Double, g: Double, b: Double) {
        let column = Int(((x + TurntableFace.pad) * Self.scale).rounded(.down))
        let row = Int(((y + TurntableFace.clear) * Self.scale).rounded(.down))
        guard column >= 0, column < width, row >= 0, row < height else { return (0, 0, 0) }
        let i = (row * width + column) * 4
        return (Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
    }

    /// The pixel `r` points from the record's centre, `degrees` clockwise of the top.
    func onRecord(_ r: Double, _ degrees: Double) -> (r: Double, g: Double, b: Double) {
        let record = layers.layout.record
        let cx = record.left + record.width / 2, cy = record.top + record.height / 2
        let a = degrees * .pi / 180
        return at(cx + r * sin(a), cy - r * cos(a))
    }

    static func luminance(_ p: (r: Double, g: Double, b: Double)) -> Double { 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }

    func write(_ name: String) {
        let folder = Render.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).png")
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, nil)
        CGImageDestinationFinalize(out)
    }

    static var folder: URL {
        if let given = ProcessInfo.processInfo.environment["TURNTABLE_RENDERS"], !given.isEmpty {
            return URL(fileURLWithPath: given, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-turntable-renders", isDirectory: true)
    }
}

enum Pictures {
    /// A cover that shows which way up it is: red, with a white bar along its top and a blue square at its top left.
    static func cover(_ size: Int = 300) -> CGImage {
        picture(size) { (context: CGContext, s: CGFloat) -> Void in
            context.setFillColor(CGColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: s, height: s))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: s * 0.8, width: s, height: s * 0.2))
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: s * 0.6, width: s * 0.4, height: s * 0.4))
        }
    }

    /// CD art: a printed disc - a teal field, an orange band, and a black wedge at 12 o'clock, so a turn shows.
    static func disc(_ size: Int = 600) -> CGImage {
        picture(size) { (context: CGContext, s: CGFloat) -> Void in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.55, blue: 0.55, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: s, height: s))
            context.setStrokeColor(CGColor(srgbRed: 0.95, green: 0.55, blue: 0.1, alpha: 1))
            context.setLineWidth(s * 0.06)
            context.strokeEllipse(in: CGRect(x: s * 0.2, y: s * 0.2, width: s * 0.6, height: s * 0.6))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.move(to: CGPoint(x: s / 2, y: s / 2))
            context.addLine(to: CGPoint(x: s * 0.42, y: s))
            context.addLine(to: CGPoint(x: s * 0.58, y: s))
            context.fillPath()
        }
    }

    static func picture(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context, CGFloat(size))
        return context.makeImage()!
    }
}

@Suite(.serialized) struct TurntableRenderTests {
    /// The iPhone 16's plinth (2.2: 393 less Now Playing's 24 a side and the plinth's 12) and the SE's, held by its
    /// height (2.1: the scrubber's row kept, 284).
    static let sizes: [(name: String, width: Double)] = [("iphone16", 321), ("se", 284)]
    static let trig = TurntableTrig(PlatformMaths())

    static func layers(_ width: Double, cover: Bool = true) -> TurntableLayers {
        let layers = TurntableLayers(layout: TurntableLayout(width: width), scale: CGFloat(Render.scale), flipped: true)
        if cover { layers.setCover(Pictures.cover()) }
        return layers
    }

    /// At rest at the song's top, 1:12 into a 4:00 song.
    static func look(at time: Double = 72, length: Double = 240) -> TurntableLook {
        var look = TurntableLook()
        look.arm = trig.armAngle(time, length)
        look.needle = trig.needleAt(time, length)
        return look
    }

    /// Every state 7.3 names, at both sizes, written out - and each render looked at by the checks below.
    @Test func everyStateIsRenderedAtBothSizes() {
        for size in Self.sizes {
            func render(_ state: String, _ setUp: (TurntableLayers, inout TurntableLook) -> Void) {
                let layers = Self.layers(size.width)
                var look = Self.look()
                setUp(layers, &look)
                layers.set(look)
                let render = Render(layers)
                render.write("\(size.name)-\(state)")
                #expect(render.width > 0)
            }
            render("at-rest") { (_: TurntableLayers, _: inout TurntableLook) -> Void in }
            render("turned-90") { (_: TurntableLayers, look: inout TurntableLook) -> Void in look.angle = 90 }
            render("arm-lifted") { (_: TurntableLayers, look: inout TurntableLook) -> Void in look.lifted = true }
            render("cd-art") { (layers: TurntableLayers, _: inout TurntableLook) -> Void in layers.setArt(Pictures.disc()) }
            render("cd-art-turned-90") { (layers: TurntableLayers, look: inout TurntableLook) -> Void in
                layers.setArt(Pictures.disc())
                look.angle = 90
            }
            render("no-art-no-cover") { (layers: TurntableLayers, _: inout TurntableLook) -> Void in layers.setCover(nil) }
            render("readout-1x") { (_: TurntableLayers, look: inout TurntableLook) -> Void in look.speed = 1 }
            render("readout-1.25x") { (_: TurntableLayers, look: inout TurntableLook) -> Void in look.speed = 1.25 }
            render("fader-held") { (_: TurntableLayers, look: inout TurntableLook) -> Void in
                look.speed = 1.25
                look.faderHeld = true
            }
            render("contrast") { (_: TurntableLayers, look: inout TurntableLook) -> Void in look.contrast = true }
        }
        print("Turntable renders: \(Render.folder.path)")
    }

    /// 2.4: the sheen doesn't turn, and its brightest band lies 48 deg (its 20 deg start and its 28 deg stop) clockwise
    /// of the top, within 2 deg - read round a band of the vinyl, the arm and the label out of the way.
    @Test func theSheenIsBrightestAt48Degrees() {
        for size in Self.sizes {
            for angle in [0.0, 90] {
                let layers = Self.layers(size.width)
                layers.arm.isHidden = true
                layers.handle.isHidden = true
                var look = Self.look()
                look.angle = angle
                layers.set(look)
                let render = Render(layers)
                let r = layers.layout.record.width / 2
                var best = (degrees: 0.0, light: -1.0)
                var degrees = 0.0
                while degrees < 360 {
                    var light = 0.0
                    for share in stride(from: 0.55, through: 0.9, by: 0.05) { light += Render.luminance(render.onRecord(r * share, degrees)) }
                    if light > best.light { best = (degrees, light) }
                    degrees += 0.5
                }
                #expect(abs(best.degrees - TurntableFace.sheenBrightest) <= 2,
                        "\(size.name), turned \(angle): brightest at \(best.degrees) deg")
                // the second, fainter band: 208 deg on from 20
                let low = render.onRecord(r * 0.7, 228), dark = render.onRecord(r * 0.7, 120)
                #expect(Render.luminance(low) > Render.luminance(dark), "\(size.name): the second band at 228 deg")
            }
        }
    }

    /// 2.4: the label's 2 pt ring lies inside a label 38.75% of the face across (player.css makes app.css's label
    /// border-box) - the cover's red inside it, the ring's grey on it, the vinyl outside the 38.75% - read at four angles.
    @Test func theLabelsRingIsWhereTheWebsIs() {
        for size in Self.sizes {
            let layers = Self.layers(size.width)
            layers.arm.isHidden = true
            layers.handle.isHidden = true
            layers.set(Self.look())
            let render = Render(layers)
            let parts = TurntableFaceParts(layers.layout)
            #expect(abs(parts.labelOuter - layers.layout.record.width * 0.3875 / 2) < 1e-9)
            #expect(abs(parts.label - (parts.labelOuter - 2)) < 1e-9)
            // where the test cover is red (its white bar is along its top, its blue square at its top left)
            for degrees in [100.0, 160, 200, 250] {
                let inside = render.onRecord(parts.label - 1.5, degrees)
                let ring = render.onRecord(parts.label + 1, degrees)
                let outside = render.onRecord(parts.labelOuter + 1.5, degrees)
                #expect(inside.r > 150 && inside.g < 80, "\(size.name) \(degrees): the cover inside (\(inside))")
                #expect(abs(ring.r - ring.g) < 12 && abs(ring.g - ring.b) < 12 && ring.r > 55, "\(size.name) \(degrees): the ring's grey (\(ring))")
                #expect(Render.luminance(outside) < 40, "\(size.name) \(degrees): the vinyl outside (\(outside))")
            }
        }
    }

    /// 2.4: the spindle's 3 pt ring lies inside its 6.25% of the face, as the label's does (border-box) - its own dark
    /// inside the ring, the ring's grey, and the cover's red just past the 6.25% - read at four angles.
    @Test func theSpindlesRingIsInsideItsShare() {
        for size in Self.sizes {
            let layers = Self.layers(size.width)
            layers.arm.isHidden = true
            layers.handle.isHidden = true
            layers.set(Self.look())
            let render = Render(layers)
            let parts = TurntableFaceParts(layers.layout)
            #expect(abs(parts.spindleOuter - layers.layout.record.width * 0.0625 / 2) < 1e-9)
            #expect(abs(parts.spindle - (parts.spindleOuter - 3)) < 1e-9)
            for degrees in [100.0, 160, 200, 250] {
                let inside = render.onRecord(parts.spindle - 1.5, degrees)
                let ring = render.onRecord(parts.spindleOuter - 1.5, degrees)
                let outside = render.onRecord(parts.spindleOuter + 1.5, degrees)
                #expect(Render.luminance(inside) < 30, "\(size.name) \(degrees): the spindle inside its ring (\(inside))")
                #expect(abs(ring.r - ring.g) < 12 && abs(ring.g - ring.b) < 12 && ring.r > 55,
                        "\(size.name) \(degrees): the ring's grey (\(ring))")
                #expect(outside.r > 150 && outside.g < 80, "\(size.name) \(degrees): the cover past it (\(outside))")
            }
        }
    }

    /// 2.4: the grooves are a ring every 4 pt, in points whatever the plinth - their darkest every 4 pt along a radius.
    /// Read over a plain light CD art (the grooves are over the art too), where their 0.2 of black is many levels of
    /// grey rather than the vinyl's two or three.
    @Test func theGroovesPeriodIs4Points() {
        for size in Self.sizes {
            let layers = Self.layers(size.width)
            layers.arm.isHidden = true
            layers.handle.isHidden = true
            layers.setArt(Pictures.picture(600) { (context: CGContext, s: CGFloat) -> Void in
                context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: s, height: s))
            })
            layers.set(Self.look())
            let render = Render(layers)
            let r = layers.layout.record.width / 2
            // along a radius where the sheen is clear (56-180 deg), a sample every third of a point
            var samples: [(at: Double, light: Double)] = []
            var at = r * 0.45
            while at < r * 0.95 {
                samples.append((at, Render.luminance(render.onRecord(at, 120))))
                at += 1 / Render.scale
            }
            var minima: [Double] = []
            for i in 1..<(samples.count - 1) where samples[i].light < samples[i - 1].light && samples[i].light <= samples[i + 1].light {
                if let last = minima.last, samples[i].at - last < 2 { continue }
                minima.append(samples[i].at)
            }
            #expect(minima.count > 10, "\(size.name): \(minima.count) grooves found")
            let gaps = zip(minima.dropFirst(), minima).map { $0 - $1 }
            let mean = gaps.reduce(0, +) / Double(max(gaps.count, 1))
            #expect(abs(mean - TurntableFace.groovePeriod) < 0.1, "\(size.name): grooves every \(mean) pt")
            #expect(gaps.allSatisfy { abs($0 - 4) < 0.7 }, "\(size.name): \(gaps)")
        }
    }

    /// 5.1: the readout at 1x is --dw-text-2 in a plain well; at any other speed purple - --dw-accent-text in the
    /// toggled well. Read as the brightest pixel of its words and its edge's colour.
    @Test func theReadoutsColoursAreThePalettes() {
        for size in Self.sizes {
            for speed in [1.0, 1.25] {
                let layers = Self.layers(size.width)
                var look = Self.look()
                look.speed = speed
                layers.set(look)
                let render = Render(layers)
                let box = layers.readout.frame
                var brightest = (r: 0.0, g: 0.0, b: 0.0)
                var y = Double(box.minY) + 1
                while y < Double(box.maxY) - 1 {
                    var x = Double(box.minX) + 1
                    while x < Double(box.maxX) - 1 {
                        let p = render.at(x, y)
                        if Render.luminance(p) > Render.luminance(brightest) { brightest = p }
                        x += 1 / Render.scale
                    }
                    y += 1 / Render.scale
                }
                let want = speed == 1 ? TurntableLayers.text2 : TurntablePalette.accentText
                #expect(abs(brightest.r - Double(want.red)) < 14 && abs(brightest.g - Double(want.green)) < 14
                        && abs(brightest.b - Double(want.blue)) < 14, "\(size.name) \(speed)x: its words \(brightest), not \(want)")
                let edge = render.at(Double(box.midX), Double(box.minY) + 0.5)
                let edgeWant = TurntableLayers.over(speed == 1 ? DeckRGBA(0, 0, 0, 0) : TurntablePalette.toggledEdge,
                                                    speed == 1 ? TurntablePalette.barEdge : TurntableLayers.over(TurntablePalette.toggledFill, TurntablePalette.ttPlinth))
                #expect(abs(edge.r - Double(edgeWant.red)) < 16 && abs(edge.b - Double(edgeWant.blue)) < 16,
                        "\(size.name) \(speed)x: its edge \(edge), not \(edgeWant)")
            }
        }
    }

    /// 2.5: lifted, the head is drawn 5 units up in the arm's own frame - its middle moved by 5 units turned by the
    /// arm's angle; nothing else of the arm moves.
    @Test func theHeadIsFiveUnitsUpWhenLifted() {
        for size in Self.sizes {
            func headMiddle(_ lifted: Bool) -> (x: Double, y: Double, count: Int) {
                let layers = Self.layers(size.width)
                layers.handle.isHidden = true
                var look = Self.look()
                look.lifted = lifted
                layers.set(look)
                let render = Render(layers)
                let colour = TurntablePalette.ttArmHead
                var sum = (x: 0.0, y: 0.0, count: 0)
                let step = 1 / Render.scale
                var y = 0.0
                while y < layers.layout.height {
                    var x = 0.0
                    while x < layers.layout.width {
                        let p = render.at(x, y)
                        if abs(p.r - Double(colour.red)) < 2 && abs(p.g - Double(colour.green)) < 2 && abs(p.b - Double(colour.blue)) < 2 {
                            sum = (sum.x + x, sum.y + y, sum.count + 1)
                        }
                        x += step
                    }
                    y += step
                }
                return (sum.x / Double(max(sum.count, 1)), sum.y / Double(max(sum.count, 1)), sum.count)
            }
            let down = headMiddle(false), up = headMiddle(true)
            #expect(down.count > 100 && abs(Double(up.count - down.count)) < Double(down.count) * 0.05)
            let k = TurntableLayout(width: size.width).across(1)
            let a = Self.look().arm * .pi / 180
            // (0, -5) in the arm's frame, turned clockwise by its angle in y-down
            let want = (x: 5 * k * sin(a), y: -5 * k * cos(a))
            #expect(abs((up.x - down.x) - want.x) < 0.35 && abs((up.y - down.y) - want.y) < 0.35,
                    "\(size.name): moved (\(up.x - down.x), \(up.y - down.y)), not \(want)")
        }
    }

    /// 2.4: the face turns and the label's cover turns with it - its white top bar is at the right after 90 deg - and
    /// the CD art hides the label.
    @Test func theFaceTurnsAndTheArtCoversTheLabel() {
        let layers = Self.layers(321)
        layers.arm.isHidden = true
        layers.handle.isHidden = true
        var look = Self.look()
        layers.set(look)
        let parts = TurntableFaceParts(layers.layout)
        var render = Render(layers)
        let top = render.onRecord(parts.label * 0.85, 0)
        #expect(top.r > 200 && top.g > 200 && top.b > 200, "unturned, the cover's white bar at its top: \(top)")
        look.angle = 90
        layers.set(look)
        render = Render(layers)
        let right = render.onRecord(parts.label * 0.85, 90)
        #expect(right.r > 200 && right.g > 200 && right.b > 200, "turned 90, the white bar at the right: \(right)")
        layers.setArt(Pictures.disc())
        look.angle = 0
        layers.set(look)
        render = Render(layers)
        let middle = render.onRecord(parts.label * 0.5, 200)
        #expect(middle.g > middle.r, "the CD art's teal over the label: \(middle)")
    }

    /// 2.5: Increase Contrast draws the handle's ring in --dw-text-3 instead of white at 0.18.
    @Test func increaseContrastBrightensTheHandle() {
        func ring(_ contrast: Bool) -> Double {
            let layers = Self.layers(321)
            // the arm crosses its own handle's ring: out of the way
            layers.arm.isHidden = true
            var look = Self.look()
            look.contrast = contrast
            layers.set(look)
            let render = Render(layers)
            let at = layers.layout.point(look.needle), half = layers.layout.handleSize / 2
            var light = 0.0
            for degrees in stride(from: 0.0, to: 360, by: 3) {
                let a = degrees * .pi / 180
                light = max(light, Render.luminance(render.at(at.x + (half - 0.5) * sin(a), at.y - (half - 0.5) * cos(a))))
            }
            return light
        }
        let on = ring(true), off = ring(false)
        #expect(on > off + 30, "the ring: \(on) with Increase Contrast, \(off) without")
    }

    /// The grooves' alpha is the web's gradient: clear to 2 pt, 0.2 at 3, clear at 4, repeating.
    @Test func theGroovesAlphaIsTheGradient() {
        #expect(TurntableLayers.grooveAlpha(0) == 0 && TurntableLayers.grooveAlpha(1.9) == 0)
        #expect(abs(TurntableLayers.grooveAlpha(3) - 0.2) < 1e-12 && abs(TurntableLayers.grooveAlpha(2.5) - 0.1) < 1e-12)
        #expect(abs(TurntableLayers.grooveAlpha(7) - 0.2) < 1e-12 && abs(TurntableLayers.grooveAlpha(3.5) - 0.1) < 1e-12)
        #expect(TurntableLayers.grooveAlpha(4) == 0 && TurntableLayers.grooveAlpha(102) == 0)
    }
}
#endif
