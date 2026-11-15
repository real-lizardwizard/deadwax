import Foundation

/// The cover, full screen (notes/ios.md "The cover, full screen"; James: "maybe when you tap the album art in the play
/// screen it should become full screen so you can zoom in and look at it"): its rules, with no view in them. It is the
/// phone's own - the web's Now Playing has no such view - so nothing here is held to web code.
///
/// - A tap on Now Playing's cover opens it; a drag there is still Now Playing's own, closing it.
/// - The cover is fitted to the screen, zoomed from 1 (fitted) to `maximum`: twice the zoom at which one of the
///   cover's pixels is one of the screen's, never under `leastMaximum` nor over `mostMaximum`.
/// - A double-tap at rest zooms to `doubleTap` about the point tapped; zoomed, it goes back to 1.
/// - VoiceOver's swipe up and down zoom by `step` (twice, or half), between 1 and the maximum.
/// - At rest, a drag down that is let go past `closePast`, or flicked down faster than `flickClose`, closes it; the
///   ground fades as it goes (`groundOpacity`). Zoomed, a drag pans.
/// - The full-size cover is decoded no larger than `decodeLongest` pixels along its longer side: a 64 MB image at
///   most, however large the file Navidrome holds.
///
/// Distances are points, speeds points a second, downward positive (UIKit's).
public enum CoverZoom {
    /// The most the cover zooms, at least - a 1024-pixel cover on a 3x phone still zooms this far.
    public static let leastMaximum: Double = 3
    /// The most the cover zooms, at most.
    public static let mostMaximum: Double = 8
    /// Where a double-tap at rest zooms to.
    public static let doubleTap: Double = 2.5
    /// What one of VoiceOver's swipes multiplies (up) or divides (down) the zoom by.
    public static let step: Double = 2
    /// A zoom this close to 1 is at rest (a pinch let go springs back to 1 through a few hundredths).
    public static let restTolerance: Double = 0.01
    /// A drag down at rest let go this far closes the viewer.
    public static let closePast: Double = 100
    /// A drag down at rest let go moving down this fast closes the viewer, however short it was.
    public static let flickClose: Double = 900
    /// The ground is gone by this far down.
    public static let fadeOver: Double = 300
    /// The ground's opacity it never fades under while a finger holds the cover.
    public static let leastGround: Double = 0.25
    /// The full-size cover's longer side, decoded, at most (pixels).
    public static let decodeLongest = 4096

    /// The most the cover zooms: twice the zoom at which its pixels are the screen's (`pixels` the cover's longer side,
    /// `fitted` that side drawn at 1 in points, `scale` the screen's pixels to a point), within the two bounds.
    public static func maximum(pixels: Double, fitted: Double, scale: Double) -> Double {
        guard pixels > 0, fitted > 0, scale > 0 else { return leastMaximum }
        let native = pixels / (fitted * scale)
        return min(mostMaximum, max(leastMaximum, native * 2))
    }

    /// At rest: fitted, unzoomed.
    public static func atRest(_ zoom: Double) -> Bool {
        zoom <= 1 + restTolerance
    }

    /// A double-tap's zoom: from rest to `doubleTap` (or the maximum, if that is less); from anywhere else back to 1.
    public static func doubleTapped(_ zoom: Double, maximum: Double) -> Double {
        atRest(zoom) ? min(doubleTap, max(maximum, 1)) : 1
    }

    /// The part of the cover a zoom about a point shows (in the cover's own points at 1, as UIScrollView's zoom(to:)
    /// takes it): the screen's size over the zoom, centred on the point. UIScrollView keeps it inside the cover.
    public static func zoomRect(x: Double, y: Double, zoom: Double, width: Double, height: Double)
        -> (x: Double, y: Double, width: Double, height: Double) {
        let scale = max(zoom, 1)
        let shownWidth = width / scale
        let shownHeight = height / scale
        return (x - shownWidth / 2, y - shownHeight / 2, shownWidth, shownHeight)
    }

    /// VoiceOver's swipe up (`zoomIn`) or down: twice or half the zoom, between 1 and the maximum - a half that comes
    /// within a step of 1 is 1, so a few swipes down always reach rest.
    public static func stepped(_ zoom: Double, zoomIn: Bool, maximum: Double) -> Double {
        let top = max(maximum, 1)
        if zoomIn { return min(top, max(zoom, 1) * step) }
        let down = zoom / step
        return down < 1 + (step - 1) / 2 ? 1 : min(top, down)
    }

    /// A drag at rest let go `dragged` points down, moving `speed` points a second down: whether it closes the viewer.
    public static func closes(dragged: Double, speed: Double) -> Bool {
        dragged >= closePast || (dragged > 0 && speed >= flickClose)
    }

    /// The ground's opacity under a cover held `dragged` points down: 1 at rest, fading to `leastGround` by
    /// `fadeOver`.
    public static func groundOpacity(dragged: Double) -> Double {
        let gone = min(max(dragged, 0) / fadeOver, 1)
        return 1 - gone * (1 - leastGround)
    }

    /// The pixels to decode a cover `longest` pixels along its longer side at: all of them, up to `decodeLongest`.
    public static func decodeSize(longest: Int) -> Int {
        min(max(longest, 1), decodeLongest)
    }

    /// The cover's size fitted inside a screen (`width` by `height`), its shape kept: what zoom 1 draws.
    public static func fitted(width: Double, height: Double, inWidth: Double, inHeight: Double)
        -> (width: Double, height: Double) {
        guard width > 0, height > 0, inWidth > 0, inHeight > 0 else { return (0, 0) }
        let scale = min(inWidth / width, inHeight / height)
        return (width * scale, height * scale)
    }

    /// The image to show of two: the full-size one once it is in, unless it has fewer pixels than the one drawn already
    /// (a cover smaller than Now Playing's size is the same picture either way).
    public static func showsFull(drawnPixels: Double, fullPixels: Double) -> Bool {
        fullPixels > 0 && fullPixels >= drawnPixels
    }
}

/// What the cover viewer says (VoiceOver's words and the close button's).
public enum CoverViewerWords {
    /// The close button.
    public static let close = "Close"

    /// The album's name, or "the album" for a song that names none.
    private static func album(_ album: String) -> String {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "the album" : trimmed
    }

    /// Now Playing's cover, as a button: "Cover of Dummy - show full screen".
    public static func open(album: String) -> String {
        "Cover of \(Self.album(album)) - show full screen"
    }

    /// The cover in the viewer, an image named for its album: "Cover of Dummy, by Portishead".
    public static func image(album: String, artist: String) -> String {
        let by = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Cover of \(Self.album(album))" + (by.isEmpty ? "" : ", by \(by)")
    }

    /// The zoom, as VoiceOver reads its value: "Not zoomed", "Zoomed 2.5 times".
    public static func zoom(_ zoom: Double) -> String {
        if CoverZoom.atRest(zoom) { return "Not zoomed" }
        let tenths = (zoom * 10).rounded() / 10
        let number = tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
        return "Zoomed \(number) times"
    }

    /// Zoomed in, what the three-finger scroll does.
    public static let panHint = "Scroll with three fingers to look around it."

    /// Where a three-finger scroll has gone, by the point of the cover at the screen's centre (`across` and `down` as
    /// parts of its width and height): "Showing the top left of the cover", "Showing the middle of the cover",
    /// "Showing the right side of the cover".
    public static func showing(across: Double, down: Double) -> String {
        let row = down < 1.0 / 3 ? "top" : (down > 2.0 / 3 ? "bottom" : nil)
        let column = across < 1.0 / 3 ? "left" : (across > 2.0 / 3 ? "right" : nil)
        let place: String
        switch (row, column) {
        case (let row?, let column?): place = "\(row) \(column)"
        case (let row?, nil): place = row
        case (nil, let column?): place = "\(column) side"
        case (nil, nil): place = "middle"
        }
        return "Showing the \(place) of the cover"
    }
}
