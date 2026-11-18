import Foundation
import Testing
@testable import DeadwaxCore

// The cover, full screen (notes/ios.md "The cover, full screen"): its zoom's rules, its close, the size it is asked
// and decoded at, and its words - the phone's own, with no web code to hold them to.
@Suite struct CoverViewerTests {
    @Test func theMostItZoomsFollowsTheCoversPixels() {
        // a 1024-pixel cover fitted 402 pt wide on a 3x phone is under its own pixels already: the least maximum
        #expect(CoverZoom.maximum(pixels: 1024, fitted: 402, scale: 3) == CoverZoom.leastMaximum)
        // a 3000-pixel one: twice the zoom at which a pixel is a pixel (3000 / 1206 = 2.49)
        let large = CoverZoom.maximum(pixels: 3000, fitted: 402, scale: 3)
        #expect(abs(large - 2 * 3000 / 1206.0) < 0.0001)
        // a huge one stops at the most
        #expect(CoverZoom.maximum(pixels: 20000, fitted: 402, scale: 3) == CoverZoom.mostMaximum)
        // nothing known: the least
        #expect(CoverZoom.maximum(pixels: 0, fitted: 402, scale: 3) == CoverZoom.leastMaximum)
        #expect(CoverZoom.maximum(pixels: 1024, fitted: 0, scale: 3) == CoverZoom.leastMaximum)
    }

    @Test func aDoubleTapZoomsInAtRestAndOutOtherwise() {
        #expect(CoverZoom.doubleTapped(1, maximum: 3) == CoverZoom.doubleTap)
        // a pinch let go springs back through a few hundredths: still at rest
        #expect(CoverZoom.doubleTapped(1.005, maximum: 3) == CoverZoom.doubleTap)
        #expect(CoverZoom.doubleTapped(1.5, maximum: 3) == 1)
        #expect(CoverZoom.doubleTapped(2.5, maximum: 3) == 1)
        // never past the maximum
        #expect(CoverZoom.doubleTapped(1, maximum: 2) == 2)
    }

    @Test func aDoubleTapZoomsAboutThePointTapped() {
        let shown = CoverZoom.zoomRect(x: 300, y: 100, zoom: 2.5, width: 400, height: 800)
        #expect(shown.width == 160 && shown.height == 320)
        // centred on the point: UIScrollView keeps it inside the cover
        #expect(shown.x == 220 && shown.y == -60)
        // a zoom under 1 is read as 1
        #expect(CoverZoom.zoomRect(x: 0, y: 0, zoom: 0.5, width: 400, height: 800).width == 400)
    }

    @Test func voiceOversSwipesZoomByTwiceAndHalf() {
        #expect(CoverZoom.stepped(1, zoomIn: true, maximum: 5) == 2)
        #expect(CoverZoom.stepped(2, zoomIn: true, maximum: 5) == 4)
        #expect(CoverZoom.stepped(4, zoomIn: true, maximum: 5) == 5)
        #expect(CoverZoom.stepped(5, zoomIn: true, maximum: 5) == 5)
        #expect(CoverZoom.stepped(5, zoomIn: false, maximum: 5) == 2.5)
        #expect(CoverZoom.stepped(2.5, zoomIn: false, maximum: 5) == 1)
        #expect(CoverZoom.stepped(2, zoomIn: false, maximum: 5) == 1)
        #expect(CoverZoom.stepped(1, zoomIn: false, maximum: 5) == 1)
        // a pinch's zoom between the steps comes back down to rest too
        #expect(CoverZoom.stepped(3.2, zoomIn: false, maximum: 5) == 1.6)
        #expect(CoverZoom.stepped(1.6, zoomIn: false, maximum: 5) == 1)
    }

    @Test func aDragDownClosesPastItsDistanceOrFlicked() {
        #expect(CoverZoom.closes(dragged: 100, speed: 0))
        #expect(!CoverZoom.closes(dragged: 99, speed: 200))
        #expect(CoverZoom.closes(dragged: 20, speed: 900))
        // a flick up after a drag down, or no drag at all, is no close
        #expect(!CoverZoom.closes(dragged: 60, speed: -1200))
        #expect(!CoverZoom.closes(dragged: 0, speed: 2000))
    }

    @Test func theGroundFadesAsTheCoverGoesDown() {
        #expect(CoverZoom.groundOpacity(dragged: 0) == 1)
        #expect(CoverZoom.groundOpacity(dragged: -40) == 1)
        #expect(abs(CoverZoom.groundOpacity(dragged: 150) - (1 - 0.5 * (1 - CoverZoom.leastGround))) < 0.0001)
        #expect(CoverZoom.groundOpacity(dragged: 300) == CoverZoom.leastGround)
        #expect(CoverZoom.groundOpacity(dragged: 900) == CoverZoom.leastGround)
    }

    @Test func theFullCoverIsDecodedNoLargerThanFourThousandPixels() {
        #expect(CoverZoom.decodeSize(longest: 1200) == 1200)
        #expect(CoverZoom.decodeSize(longest: 4096) == 4096)
        #expect(CoverZoom.decodeSize(longest: 7000) == 4096)
        #expect(CoverZoom.decodeSize(longest: 0) == 1)
    }

    @Test func theCoverIsFittedWithItsShapeKept() {
        let square = CoverZoom.fitted(width: 3000, height: 3000, inWidth: 402, inHeight: 874)
        #expect(square.width == 402 && square.height == 402)
        let wide = CoverZoom.fitted(width: 1200, height: 600, inWidth: 400, inHeight: 800)
        #expect(wide.width == 400 && wide.height == 200)
        let tall = CoverZoom.fitted(width: 500, height: 2000, inWidth: 400, inHeight: 800)
        #expect(tall.width == 200 && tall.height == 800)
        #expect(CoverZoom.fitted(width: 0, height: 10, inWidth: 400, inHeight: 800) == (0, 0))
    }

    @Test func theFullCoverReplacesTheOneDrawnUnlessItIsSmaller() {
        #expect(CoverZoom.showsFull(drawnPixels: 1024 * 1024, fullPixels: 3000 * 3000))
        #expect(CoverZoom.showsFull(drawnPixels: 600 * 600, fullPixels: 600 * 600))
        #expect(!CoverZoom.showsFull(drawnPixels: 1024 * 1024, fullPixels: 500 * 500))
        #expect(!CoverZoom.showsFull(drawnPixels: 0, fullPixels: 0))
    }

    @Test func theWordsNameTheAlbum() {
        #expect(CoverViewerWords.open(album: "Dummy") == "Cover of Dummy - show full screen")
        #expect(CoverViewerWords.open(album: "  ") == "Cover of the album - show full screen")
        #expect(CoverViewerWords.image(album: "Dummy", artist: "Portishead") == "Cover of Dummy, by Portishead")
        #expect(CoverViewerWords.image(album: "Dummy", artist: "") == "Cover of Dummy")
        #expect(CoverViewerWords.zoom(1) == "Not zoomed")
        #expect(CoverViewerWords.zoom(1.004) == "Not zoomed")
        #expect(CoverViewerWords.zoom(2) == "Zoomed 2 times")
        #expect(CoverViewerWords.zoom(2.5) == "Zoomed 2.5 times")
        #expect(CoverViewerWords.zoom(4.96) == "Zoomed 5 times")
        #expect(CoverViewerWords.close == "Close")
    }

    @Test func aThreeFingerScrollSaysWhereItHasGone() {
        #expect(CoverViewerWords.showing(across: 0.1, down: 0.1) == "Showing the top left of the cover")
        #expect(CoverViewerWords.showing(across: 0.5, down: 0.5) == "Showing the middle of the cover")
        #expect(CoverViewerWords.showing(across: 0.5, down: 0.9) == "Showing the bottom of the cover")
        #expect(CoverViewerWords.showing(across: 0.9, down: 0.5) == "Showing the right side of the cover")
        #expect(CoverViewerWords.showing(across: 0.9, down: 0.8) == "Showing the bottom right of the cover")
    }

    @Test func theFullCoverIsAskedWithNoSize() async throws {
        let (deadwax, transport) = client()
        transport.handle("/deadwax/navidrome/cover/al-1_0") { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "image/jpeg"], body: Data([0xFF, 0xD8, 0xFF]))
        }
        #expect(try await deadwax.fullCover(coverID: "al-1_0") == Data([0xFF, 0xD8, 0xFF]))
        #expect(transport.last?.method == "GET")
        #expect(transport.last?.url.absoluteString == "http://192.168.3.20:8090/deadwax/navidrome/cover/al-1_0")
        #expect(transport.last?.url.query == nil)
        #expect(transport.last?.headers["Accept"] == "image/*")
        // read no further than 30 MB; the sized one is unchanged, with no limit
        #expect(transport.last?.mostBytes == 30 * 1024 * 1024)
        #expect(deadwax.coverRequest(coverID: "al-1_0", size: CoverSize.hero).url.query == "size=1024")
        #expect(deadwax.coverRequest(coverID: "al-1_0", size: CoverSize.hero).mostBytes == nil)
    }

    @Test func aFullCoverPastThirtyMegabytesIsRefused() async throws {
        let (deadwax, transport) = client()
        let most = CoverZoom.fullMostBytes
        transport.handle("/deadwax/navidrome/cover/al-2_0") { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "image/png"], body: Data(count: most + 1))
        }
        transport.handle("/deadwax/navidrome/cover/al-3_0") { _ in
            HTTPResponse(status: 200, headers: ["Content-Type": "image/png"], body: Data(count: most))
        }
        // a transport that read it all: refused here, as the app's transport refuses it as it reads
        await #expect(throws: HTTPTooLarge(most: most)) { try await deadwax.fullCover(coverID: "al-2_0") }
        #expect(try await deadwax.fullCover(coverID: "al-3_0").count == most)
        #expect(CoverZoom.reads(bytes: most) && !CoverZoom.reads(bytes: most + 1))
    }

    @Test func aTransportsTooLargeIsSaidAsItself() async throws {
        // the app's transport calls the read off past the request's most, and throws HTTPTooLarge: never "no answer"
        let server = try ServerAddress.parse("192.168.3.20:8090").get()
        let deadwax = DeadwaxClient(server: server, session: nil, transport: CalledOff(), device: .iPhone)
        await #expect(throws: HTTPTooLarge(most: CoverZoom.fullMostBytes)) {
            try await deadwax.fullCover(coverID: "al-4_0")
        }
    }

    @Test func onlyAFullCoverUpToTenMegabytesIsKeptOnceClosed() {
        #expect(CoverZoom.keptMostBytes == 10 * 1024 * 1024)
        #expect(CoverZoom.keeps(bytes: 3 * 1024 * 1024))
        #expect(CoverZoom.keeps(bytes: CoverZoom.keptMostBytes))
        #expect(!CoverZoom.keeps(bytes: CoverZoom.keptMostBytes + 1))
        #expect(!CoverZoom.keeps(bytes: 0))
    }

    @Test func aCoverOpensOnlyWithAPictureOfItShown() {
        // drawn by Now Playing, or kept with a downloaded album
        #expect(CoverZoom.opens(coverID: "al-1_0", drawn: true, kept: false))
        #expect(CoverZoom.opens(coverID: "al-1_0", drawn: false, kept: true))
        // the grey square - loading, or failed - opens nothing
        #expect(!CoverZoom.opens(coverID: "al-1_0", drawn: false, kept: false))
        // no cover id, none
        #expect(!CoverZoom.opens(coverID: nil, drawn: true, kept: true))
        #expect(!CoverZoom.opens(coverID: " ", drawn: true, kept: true))
        #expect(CoverViewerWords.notYet == "The cover hasn't loaded.")
    }
}

/// A transport that calls every read off past its request's most, as the app's does with a cover past 30 MB.
private struct CalledOff: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw HTTPTooLarge(most: request.mostBytes ?? 0)
    }
}
