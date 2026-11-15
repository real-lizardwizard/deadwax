"""
The iPhone app's cover, full screen (notes/ios.md "The cover, full screen"; James: "maybe when you tap the album art in
the play screen it should become full screen so you can zoom in and look at it").

Read from the Swift source, as the other ios tests read theirs: only a tap on Now Playing's cover opens the viewer -
never the lyrics' or the turntable's place, and the drag that closes Now Playing stays the cover's parent's; the viewer
is presented with no slide, on the page's black (theme.css's --dw-bg), the status bar hidden, closed by the button, a
drag down at rest and VoiceOver's escape; the zoom is a UIScrollView that stops at the image's edges, double-taps, and
is one adjustable VoiceOver element; the full size is asked with no size, and the route passes none to Navidrome; and
nothing in the viewer touches the player. Core's rules (CoverZoom, CoverViewerWords, DeadwaxClient.fullCover) are held
by CoverViewerTests.swift.
"""

import asyncio
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402

from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from test_navidrome import JPEG, ok, streamed  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
CORE = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
NOW_PLAYING = APP / "Player" / "NowPlayingView.swift"
VIEWER = APP / "Player" / "CoverViewer.swift"
ZOOM = APP / "Player" / "CoverZoomView.swift"
THEME_CSS = REPO / "interface" / "styles" / "theme.css"


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise AssertionError("unbalanced braces")


def func(text: str, name: str) -> str:
    found = list(re.finditer(r"\bfunc\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"func {name} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def test_only_a_tap_on_now_playings_cover_opens_it():
    source = code(NOW_PLAYING)
    # once, and on the cover itself: the lyrics' and the turntable's places come before it and have none
    assert source.count(".opensCoverFullScreen(track)") == 1
    lyrics = source.index("lyricsFace(track)\n")
    turntable = source.index("TurntableView()")
    cover = source.index("CoverImage(id: track.coverArt, size: 360)")
    opens = source.index(".opensCoverFullScreen(track)")
    room = source.index(".gesture(grip)", cover)
    assert lyrics < turntable < cover < opens < room
    # on the cover's own shape (after its clip), not the room around it, which stays the grip's
    assert source.index(".clipShape(Corners.artShape)", cover) < opens
    # the drag that closes Now Playing is untouched: the top row's and the cover's room, begun past dragStartDistance
    assert source.count(".gesture(grip)") == 2
    grip = source[source.index("private var grip: some Gesture"):]
    assert "DragGesture(minimumDistance: PlayerWords.dragStartDistance, coordinateSpace: .global)" in grip
    # a tap, never a drag of the viewer's own on the cover; a song with no cover opens nothing
    viewer = code(VIEWER)
    opening = viewer[viewer.index("private struct CoverOpens"):viewer.index("struct CoverViewer: View")]
    assert ".onTapGesture { open() }" in opening
    assert "DragGesture" not in viewer
    assert "guard let id = track.coverArt, !id.isEmpty, viewing == nil else { return }" in opening
    # VoiceOver: the cover is a button named for the album, hidden for a song with no cover
    assert ".accessibilityLabel(CoverViewerWords.open(album: track.album))" in opening
    assert ".accessibilityAddTraits(.isButton)" in opening and ".accessibilityAction { open() }" in opening
    assert ".accessibilityHidden(track.coverArt == nil)" in opening


def test_the_viewer_opens_and_closes_with_no_slide_and_fades():
    viewer = code(VIEWER)
    opening = viewer[viewer.index("private struct CoverOpens"):viewer.index("struct CoverViewer: View")]
    # the cover tapped is the one shown: an item, not a flag reading the song playing
    assert ".fullScreenCover(item: $viewing)" in opening
    put = func(opening, "put")
    assert "instant.disablesAnimations = true" in put and "withTransaction(instant) { viewing = cover }" in put
    body = viewer[viewer.index("struct CoverViewer: View"):viewer.index("final class FullCovers")]
    # its own fade in and out, then gone
    assert "withAnimation(Self.fade) { shown = true }" in body
    close = func(body, "close")
    assert "withAnimation(Self.fade) {" in close and "completion: {" in close and "done()" in close


def test_the_viewer_is_the_pages_black_with_the_status_bar_hidden():
    viewer = code(VIEWER)
    body = viewer[viewer.index("struct CoverViewer: View"):viewer.index("final class FullCovers")]
    assert "Palette.page" in body and ".ignoresSafeArea()" in body
    assert ".statusBarHidden(true)" in body
    assert ".presentationBackground(.clear)" in body
    # the ground fades with a drag down, by Core's rule
    assert "CoverZoom.groundOpacity(dragged:" in body
    # Palette.page is the web's page on a phone, #000
    palette = (APP / "DeadwaxApp.swift").read_text(encoding="utf-8")
    assert "static let page = Color(red: 0x00 / 255, green: 0x00 / 255, blue: 0x00 / 255)\n" in palette
    found = re.search(r"--dw-bg:\s*([^;]+);", THEME_CSS.read_text(encoding="utf-8"))
    assert found and found.group(1).strip().lower() in ("#000", "#000000")


def test_it_closes_by_the_button_a_drag_down_and_voiceovers_escape():
    viewer = code(VIEWER)
    body = viewer[viewer.index("struct CoverViewer: View"):viewer.index("final class FullCovers")]
    assert "Button(action: close)" in body and ".accessibilityLabel(CoverViewerWords.close)" in body
    assert "Corners.controlShape" in body
    assert ".accessibilityAction(.escape) { close() }" in body
    assert ".accessibilityAddTraits(.isModal)" in body
    zoom = code(ZOOM)
    # the drag down: only at rest, more down than across, one finger; the scroll view's own pan waits on it
    rule = zoom[zoom.index("private final class DismissPanRule"):]
    assert "CoverZoom.atRest(Double(scroll.zoomScale))" in rule and "down.y > 0 && abs(down.y) > abs(down.x)" in rule
    assert "dismissPan.maximumNumberOfTouches = 1" in zoom
    assert "scroll.panGestureRecognizer.require(toFail: dismissPan)" in zoom
    panned = func(zoom, "panned")
    assert "CoverZoom.closes(dragged: Double(moved.y), speed: Double(pan.velocity(in: self).y))" in panned
    assert "onClose?()" in panned and "settle()" in panned
    # and the escape on the image itself
    escape = zoom[zoom.index("override func accessibilityPerformEscape()"):]
    assert "host?.escape()" in escape[:200]


def test_the_zoom_stops_at_the_edges_and_double_taps():
    zoom = code(ZOOM)
    assert re.search(r"final class CoverScrollView: UIScrollView\b", zoom)
    assert "struct CoverZoomer: UIViewRepresentable" in zoom
    # never past the image's edges: no bounce on the pan (the pinch alone springs back), and the room around a cover
    # smaller than the screen is insets, centred
    assert "scroll.bounces = false" in zoom and "scroll.bouncesZoom = true" in zoom
    assert "scroll.minimumZoomScale = 1" in zoom
    centre = func(zoom, "centre")
    assert "scroll.contentInset = UIEdgeInsets(top: down, left: across, bottom: down, right: across)" in centre
    # the most it zooms from the cover's own pixels, by Core's rule
    assert "CoverZoom.maximum(pixels: pixels, fitted: max(fitted.width, fitted.height)" in zoom
    assert "scroll.maximumZoomScale = CGFloat(most)" in zoom
    # a double-tap in about the point tapped and back out
    assert "doubleTap.numberOfTapsRequired = 2" in zoom
    tapped = func(zoom, "doubleTapped")
    assert "CoverZoom.doubleTapped(zoom" in tapped and "tap.location(in: imageView)" in tapped
    assert "scroll.zoom(to: CGRect(" in func(zoom, "zoom")
    # a new image (the full size) keeps the zoom and the place looked at
    assert "fit(keepingPlace: had)" in func(zoom, "show")


def test_for_voiceover_the_image_is_named_and_zoomable():
    zoom = code(ZOOM)
    scroll = zoom[zoom.index("final class CoverScrollView"):zoom.index("private final class DismissPanRule")]
    assert "isAccessibilityElement = true" in scroll
    assert "accessibilityTraits = [.image, .adjustable]" in scroll
    assert "CoverViewerWords.zoom(Double(zoomScale))" in scroll
    for override in ("accessibilityIncrement()", "accessibilityDecrement()", "accessibilityScroll(_ direction",
                     "accessibilityPerformEscape()"):
        assert f"override func {override}" in scroll, override
    assert "CoverZoom.stepped(zoom, zoomIn: zoomIn" in func(zoom, "step")
    assert "host.scroll.accessibilityLabel = label" in zoom
    viewer = code(VIEWER)
    assert "CoverViewerWords.image(album: cover.album, artist: cover.artist)" in viewer
    # the image inside is no element of its own
    assert "imageView.isAccessibilityElement = false" in zoom


def test_it_shows_the_cover_drawn_then_the_full_size():
    viewer = code(VIEWER)
    drawn = func(viewer, "drawnCover")
    # the largest the cover cache holds, Now Playing's 1024 first
    assert "for size in CoverSize.steps.reversed()" in drawn
    assert "CoverCache.shared.cached(client: client, id: cover.coverID, size: size)" in drawn
    load = func(viewer, "load")
    assert "KeptCovers.shared.url(for: cover.coverID)" in load
    # deadwax asked only while it can be reached, with no size
    assert "guard reachability.online, let client = server.client else { return }" in load
    assert "try? await client.fullCover(coverID: cover.coverID)" in load
    # decoded off the main thread, no larger than Core's cap
    assert "Task.detached(priority: .userInitiated) { FullCovers.decode(bytes) }" in load
    decode = func(viewer, "decode")
    assert "kCGImageSourceThumbnailMaxPixelSize: CoverZoom.decodeSize(longest: max(width, height))" in decode
    assert "kCGImageSourceCreateThumbnailWithTransform: true" in decode
    # the bytes of the last one kept, one at a time, let go on a memory warning
    assert "UIApplication.didReceiveMemoryWarningNotification" in viewer
    core = (CORE / "DeadwaxClient.swift").read_text(encoding="utf-8")
    request = func(re.sub(r"//[^\n]*", "", core), "fullCoverRequest")
    assert 'request(Routes.cover, path: ["cover_id": coverID])' in request and "query" not in request


def test_nothing_in_the_viewer_touches_the_player():
    # the audio must not be touched: no engine, no player, no deck from either file
    for path in (VIEWER, ZOOM):
        source = code(path)
        for word in ("PlayerModel", "player.", "DeadwaxAudio", "DeckController", "deck.", "AVAudio"):
            assert word not in source, f"{path.name} names {word}"


# ---------------------------------------------------------------- the route: no size is none sent on

@pytest.fixture
def upstream(monkeypatch):
    """Navidrome, answering every cover with a JPEG; each request it saw is kept."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    seen: list[httpx.Request] = []

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path.endswith("/getCoverArt"):
            return streamed(200, JPEG, {"content-type": "image/jpeg"})
        return httpx.Response(200, json=ok())

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield seen
    asyncio.run(navidrome.close_client())


def test_the_full_cover_asks_navidrome_for_no_size(upstream):
    client = TestClient(start())
    answer = client.get("/deadwax/navidrome/cover/al-1_0")
    assert answer.status_code == 200 and answer.content == JPEG
    asked = parse_qs(urlparse(str(upstream[-1].url)).query)
    assert upstream[-1].url.path.endswith("/getCoverArt")
    # Navidrome sends the picture unresized when it is given no size
    assert asked["id"] == ["al-1_0"] and "size" not in asked
    # the sized covers the app asks for still are
    client.get("/deadwax/navidrome/cover/al-1_0", params={"size": 1024})
    assert parse_qs(urlparse(str(upstream[-1].url)).query)["size"] == ["1024"]
