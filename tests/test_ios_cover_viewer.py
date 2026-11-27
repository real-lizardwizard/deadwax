"""
The iPhone app's cover, full screen (notes/ios.md "The cover, full screen"; James: "maybe when you tap the album art in
the play screen it should become full screen so you can zoom in and look at it").

Read from the Swift source, as the other ios tests read theirs: only a tap on Now Playing's cover opens the viewer -
never the lyrics' or the turntable's place, and only a cover shown - and the drag that closes Now Playing is the
cover's room's at a high priority, so it wins from its first points; the viewer is Now Playing's, presented from its
root (so Lyrics taking the cover's place never closes it), with no slide, on the page's black (theme.css's --dw-bg),
the status bar hidden, closed by the button, a drag down at rest and VoiceOver's escape, and a shared EQ file waits for
it; the zoom is a UIScrollView that stops at the image's edges, double-taps, and is one adjustable VoiceOver element;
the full size is asked with no size, the route passes none to Navidrome, it is read no further than 30 MB and kept
after closing up to 10; and nothing in the viewer touches the player. Core's rules (CoverZoom, CoverViewerWords,
DeadwaxClient.fullCover) are held by CoverViewerTests.swift.
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


def body_of(source: str) -> str:
    """Now Playing's `var body`, the root its presentations hang from."""
    return block(source, source.index("{", source.index("var body: some View {")))


def test_only_a_tap_on_now_playings_cover_opens_it():
    source = code(NOW_PLAYING)
    # once, and on the cover itself: the lyrics' and the turntable's places come before it and have none
    assert source.count(".opensCoverFullScreen(track, into: $viewing)") == 1
    lyrics = source.index("lyricsFace(track)\n")
    turntable = source.index("TurntableView()")
    cover = source.index("CoverImage(id: track.coverArt, size: 360)")
    opens = source.index(".opensCoverFullScreen(track, into: $viewing)")
    room = source.index(".highPriorityGesture(grip)", cover)
    assert lyrics < turntable < cover < opens < room
    # on the cover's own shape (after its clip), not the room around it, which is the grip's
    assert source.index(".clipShape(Corners.artShape)", cover) < opens
    # a tap, never a drag of the viewer's own on the cover
    viewer = code(VIEWER)
    opening = viewer[viewer.index("private struct CoverOpens"):viewer.index("struct CoverViewer: View")]
    assert ".onTapGesture { open(saying: false) }" in opening
    assert "DragGesture" not in viewer
    # only a cover shown opens - drawn by Now Playing, or kept - by Core's rule; never twice over
    open = func(opening, "open")
    assert "guard viewing == nil else { return }" in open
    assert "CoverViewer.drawn(client: $0, coverID: id) != nil" in open
    assert "KeptCovers.shared.url(for: id) != nil" in open
    assert "guard CoverZoom.opens(coverID: id, drawn: drawn, kept: kept) else {" in open
    # VoiceOver: the cover is a button named for the album, hidden for a song with no cover id; a double-tap on one
    # not drawn says so rather than doing nothing silently
    assert ".accessibilityLabel(CoverViewerWords.open(album: track.album))" in opening
    assert ".accessibilityAddTraits(.isButton)" in opening and ".accessibilityAction { open(saying: true) }" in opening
    assert ".accessibilityHidden(track.coverArt?.isEmpty ?? true)" in opening
    assert "UIAccessibility.post(notification: .announcement, argument: CoverViewerWords.notYet)" in open


def test_the_grip_beats_the_covers_tap_from_its_first_points():
    source = code(NOW_PLAYING)
    # the cover's room: the grip at a high priority over the cover's tap, so a drag is the grip's from its first
    # dragStartDistance and the tap fires at lift only when none began (review: a child's tap under a plain
    # .gesture took precedence, and the drag began only once it failed, at the tap's own slop)
    content = func(source, "content")
    ladder = content[content.index("if lyricsShown {"):]
    room = ladder[ladder.index("} else {", ladder.index("TurntableView()")):]
    assert ".highPriorityGesture(grip)" in room and ".gesture(grip)" not in room
    # the rest is as it was: the top row's grip a plain one (its chevron and look button are buttons), the lyrics and
    # the turntable outside the grip
    assert source.count(".highPriorityGesture(grip)") == 1
    assert source.count(".gesture(grip)") == 1
    top = content[content.index("topRow"):content.index("ZStack {")]
    assert ".gesture(grip)" in top
    for place in ("lyricsFace(track)\n", "TurntableView()"):
        start = ladder.index(place)
        assert "grip" not in ladder[start:ladder.index("}", start)], place
    grip = source[source.index("private var grip: some Gesture"):]
    assert "DragGesture(minimumDistance: PlayerWords.dragStartDistance, coordinateSpace: .global)" in grip


def test_the_viewer_is_presented_from_now_playings_root():
    source = code(NOW_PLAYING)
    # the state and the presentation are Now Playing's, on its root beside its sheets - never on the cover, which
    # Lyrics replaces as the next song comes (review: a viewer on the cover went with it, mid-zoom)
    assert "@State private var viewing: ViewedCover?" in source
    body = body_of(source)
    root = body[body.index(".offset(y: dragY)"):]
    assert ".coverViewer($viewing, onDismiss: eqAfterSheet)" in root
    #? (R3) beside its one sheet - the Queue, Info and the EQ's
    assert root.index(".appSheet(isPresented: $sheetUp") < root.index(".coverViewer($viewing")
    # once, and nowhere inside the content the cover lives in
    assert source.count(".coverViewer(") == 1 and ".appCover(" not in source and "fullScreenCover(" not in source
    assert ".coverViewer(" not in func(source, "content")
    viewer = code(VIEWER)
    opening = viewer[viewer.index("private struct CoverOpens"):viewer.index("struct CoverViewer: View")]
    # the cover's modifier holds no state and presents nothing: the tap and VoiceOver's button
    assert "@State" not in opening and "fullScreenCover" not in opening
    assert "@Binding var viewing: ViewedCover?" in opening
    presents = func(viewer, "coverViewer")
    assert "appCover(item: viewing, onDismiss: onDismiss)" in presents
    assert viewer.count("appCover(") == 1


def test_a_shared_eq_file_waits_for_the_viewer_too():
    shared = func(code(NOW_PLAYING), "shared")
    #? (R3) the sheet up moves to EQ in place; the cover full screen closes first, and the sheet opens once it has gone
    #? (NowPlayingTabs.shared - NowPlayingTabsTests)
    assert "switch NowPlayingTabs.shared(sheet: sheetUp ? sheetTab : nil, coverUp: viewing != nil) {" in shared
    assert "case .show(let tab):\n            open(tab)" in shared
    assert "eqWaits = true" in shared and "CoverViewing.put(nil, into: $viewing)" in shared
    # its going opens the EQ the file waited for
    assert ".coverViewer($viewing, onDismiss: eqAfterSheet)" in code(NOW_PLAYING)


def test_the_viewer_opens_and_closes_with_no_slide_and_fades():
    viewer = code(VIEWER)
    # the cover tapped is the one shown: an item, not a flag reading the song playing; up and down with no slide
    put = func(viewer, "put")
    assert "instant.disablesAnimations = true" in put
    assert "withTransaction(instant) { viewing.wrappedValue = cover }" in put
    assert "CoverViewer(cover: cover) { CoverViewing.put(nil, into: viewing) }" in viewer
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


def test_the_close_button_grows_with_the_text_and_stops_at_the_first_accessibility_size():
    viewer = code(VIEWER)
    button = viewer[viewer.index("private struct CoverCloseButton"):viewer.index("final class FullCovers")]
    # the square scaled with the text as the glyph is, from 36 points; a 44-point target
    assert "@ScaledMetric(relativeTo: .body) private var side: CGFloat = 36" in button
    assert ".frame(width: side, height: side)" in button and ".frame(minWidth: 44, minHeight: 44)" in button
    # both held at the first accessibility size, where the viewer draws it
    assert "CoverCloseButton(action: close)\n                .dynamicTypeSize(...DynamicTypeSize.accessibility1)" in viewer


def test_the_placeholder_fades_with_the_cover_and_takes_no_touch():
    viewer = code(VIEWER)
    body = viewer[viewer.index("struct CoverViewer: View"):viewer.index("private struct CoverCloseButton")]
    drawn = body[body.index("if image == nil {"):]
    # under the same fade as the image, following a drag down, every touch passed to the zoom beneath
    assert "placeholder\n                    .opacity(shown ? 1 : 0)" in drawn
    assert ".offset(y: dragged)" in drawn[:200] and ".allowsHitTesting(false)" in drawn[:200]
    # the empty square is no second element named for the cover: the zoom beneath is that already
    placeholder = body[body.index("private var placeholder: some View {"):]
    square = placeholder[placeholder.index("Corners.artShape"):placeholder.index("} else {")]
    assert ".accessibilityHidden(true)" in square and "accessibilityLabel" not in square
    assert ".accessibilityLabel(LibraryWords.loading)" in placeholder


def test_the_full_size_is_read_no_further_than_thirty_megabytes_and_kept_up_to_ten():
    core = re.sub(r"//[^\n]*", "", (CORE / "DeadwaxClient.swift").read_text(encoding="utf-8"))
    assert "built.mostBytes = CoverZoom.fullMostBytes" in func(core, "fullCoverRequest")
    assert "guard CoverZoom.reads(bytes: body.count) else { throw HTTPTooLarge(most: CoverZoom.fullMostBytes) }" in (
        func(core, "fullCover"))
    rules = (CORE / "CoverViewer.swift").read_text(encoding="utf-8")
    assert "public static let fullMostBytes = 30 * 1024 * 1024" in rules
    assert "public static let keptMostBytes = 10 * 1024 * 1024" in rules
    # the app's transport reads such a request as it comes and calls it off past its most - at once when the
    # Content-Length says so - and says it as deadwax answering, never as no answer
    transport = code(APP / "URLSessionTransport.swift")
    send = func(transport, "send")
    assert "if let most = request.mostBytes {" in send and "CappedRead.read(sent, most: most," in send
    assert "catch let error as HTTPTooLarge {" in send and "heard(true)" in send
    capped = transport[transport.index("private final class CappedRead"):]
    assert "response.expectedContentLength > Int64(most)" in capped and "completionHandler(past ? .cancel : .allow)" in capped
    assert "guard body.count > most else { return false }" in capped and "dataTask.cancel()" in capped
    assert "result = .failure(HTTPTooLarge(most: most))" in capped
    # a task cancelled calls the read off, and a read ended before anything waited is never lost
    assert "} onCancel: {\n            task.cancel()" in capped
    assert "if let ended = reader.ended { return ended }" in capped and "if continuation == nil { ended = result }" in capped
    # what's kept once the viewer closes: up to 10 MB, by Core's rule
    viewer = code(VIEWER)
    assert "last = CoverZoom.keeps(bytes: bytes.count) ? (key, bytes) : nil" in func(viewer, "keep")


def test_it_closes_by_the_button_a_drag_down_and_voiceovers_escape():
    viewer = code(VIEWER)
    body = viewer[viewer.index("struct CoverViewer: View"):viewer.index("final class FullCovers")]
    assert "Button(action: action)" in body and ".accessibilityLabel(CoverViewerWords.close)" in body
    assert "CoverCloseButton(action: close)" in body
    # (R18) its key the bare glyph on the phone, the Mac's round key there (tests/test_ios_sheets_look.py)
    assert ".buttonStyle(CoverCloseKey())" in body
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
    drawn = func(viewer, "drawn")
    # the largest the cover cache holds, Now Playing's 1024 first
    assert "for size in CoverSize.steps.reversed()" in drawn
    assert "CoverCache.shared.cached(client: client, id: coverID, size: size)" in drawn
    assert "Self.drawn(client: client, coverID: cover.coverID)" in func(viewer, "drawnCover")
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
