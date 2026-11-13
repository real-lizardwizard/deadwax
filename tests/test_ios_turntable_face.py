"""The iPhone turntable's sizes are the web's (notes/ios-specs/turntable.md 2.1-2.5, 7.3).

TurntableFace (ios/DeadwaxKit/Sources/DeadwaxCore/TurntableScreen.swift) holds every size the phone's turntable is
drawn with that isn't in the STAGE's units: the plinth's room (--app-tt-max, --app-tt-pad, --app-tt-clear), the
label's and the spindle's share of the record and their rings, the grooves' and the sheen's gradients, the handle's
cap and edge, the look button's face and glyph. The colours are held by the deck's exported tokens.json (7.0); these
are the numbers app.css, theme.css and the web's icons say, read here so that a change on either side fails.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SWIFT = REPO / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore" / "TurntableScreen.swift"
APP_CSS = REPO / "interface" / "player" / "app.css"
PLAYER_CSS = REPO / "interface" / "player" / "player.css"
THEME_CSS = REPO / "interface" / "styles" / "theme.css"
ICONS = REPO / "ui" / "src" / "player" / "icons.tsx"


def face() -> str:
    text = SWIFT.read_text()
    start = text.index("public enum TurntableFace")
    return text[start:text.index("\n}\n", start) + 1]


def number(name: str) -> float:
    found = re.search(rf"public static let {name} = ([0-9.]+)\n", face())
    assert found, f"TurntableFace has no {name}"
    return float(found.group(1))


def pair(name: str) -> tuple[float, float]:
    found = re.search(rf"public static let {name} = \([a-z]+: ([0-9.]+), [a-z]+: ([0-9.]+)\)", face())
    assert found, f"TurntableFace has no {name}"
    return float(found.group(1)), float(found.group(2))


def stops(name: str) -> list[tuple[float, float]]:
    found = re.search(rf"public static let {name}: \[[^\]]+\] = \[(.*)\]\n", face())
    assert found, f"TurntableFace has no {name}"
    return [(float(a), float(b)) for a, b in re.findall(r"\(([0-9.]+), ([0-9.]+)\)", found.group(1))]


def token(css: Path, name: str) -> str:
    found = re.search(rf"--{name}:\s*([^;]+);", css.read_text())
    assert found, f"{css.name} has no --{name}"
    return found.group(1).strip()


def px(css: Path, name: str) -> float:
    value = token(css, name)
    assert value.endswith("px"), f"--{name} is {value}"
    return float(value[:-2])


def rule(selector: str) -> str:
    text = APP_CSS.read_text()
    found = re.search(rf"\n{re.escape(selector)} \{{([^}}]*)\}}", text)
    assert found, f"app.css has no {selector}"
    return found.group(1)


def percent(selector: str, prop: str) -> float:
    found = re.search(rf"\n\s*{prop}: ([0-9.]+)%;", rule(selector))
    assert found, f"{selector} has no {prop} in %"
    return float(found.group(1)) / 100


def test_the_plinths_room_is_the_webs():
    assert number("plinthMax") == px(APP_CSS, "app-tt-max")
    assert number("pad") == px(APP_CSS, "app-tt-pad")
    assert number("clear") == px(APP_CSS, "app-tt-clear")
    assert number("plinthRadius") == px(THEME_CSS, "dw-radius-card")
    assert number("hairline") == px(THEME_CSS, "dw-hairline")


def test_the_label_and_the_spindle_are_the_webs_share_of_the_record():
    label = percent(".app-tt-label", "width")
    assert number("labelShare") == label == percent(".app-tt-label", "height")
    # the web places the label's box from its top left: its centre is the record's
    assert abs(percent(".app-tt-label", "top") + label / 2 - 0.5) < 1e-12
    assert number("labelRing") == px(APP_CSS, "app-tt-label-ring")
    spindle = percent(".app-tt-spindle", "width")
    assert number("spindleShare") == spindle == percent(".app-tt-spindle", "height")
    assert abs(percent(".app-tt-spindle", "top") + spindle / 2 - 0.5) < 1e-12
    assert number("spindleRing") == px(APP_CSS, "app-tt-spindle-ring")


def test_the_rings_are_inside_the_label_and_the_spindle():
    """TurntableFaceParts draws each ring inside its share of the face, the cover (or the spindle's dark) inside the
    ring - because the web's boxes are border-box: player.css sets it on every box, the app's page links player.css
    before app.css, and neither the label nor the spindle sets it back. A content-box label would have its 2 px ring
    outside the 38.75% (and be 2 px off centre, placed from its top left)."""
    assert re.search(r"\n\*, \*::before, \*::after \{ box-sizing: border-box; \}", PLAYER_CSS.read_text())
    page = (REPO / "interface" / "player" / "index.html").read_text()
    assert page.index('href="/player/player.css"') < page.index('href="/player/app.css"')
    for selector in (".app-tt-label", ".app-tt-spindle"):
        assert "box-sizing" not in rule(selector)
    swift = SWIFT.read_text()
    parts = swift[swift.index("public struct TurntableFaceParts"):]
    parts = parts[:parts.index("\n}\n")]
    assert "labelOuter = face * TurntableFace.labelShare / 2" in parts
    assert "labelOuter - TurntableFace.labelRing" in parts
    assert "spindleOuter = face * TurntableFace.spindleShare / 2" in parts
    assert "spindleOuter - TurntableFace.spindleRing" in parts


def test_the_grooves_are_the_webs_gradient():
    css = token(THEME_CSS, "dw-tt-grooves")
    assert css.startswith("repeating-radial-gradient(circle at 50% 50%")
    web = [(float(px_), float(a)) for a, px_ in re.findall(r"rgba\(0, 0, 0, ([0-9.]+)\) ([0-9.]+)px", css)]
    assert stops("grooveStops") == web
    assert number("groovePeriod") == web[-1][0]


def test_the_sheen_is_the_webs_conic_gradient():
    css = token(THEME_CSS, "dw-tt-sheen")
    start = re.match(r"conic-gradient\(from ([0-9.]+)deg", css)
    assert start and number("sheenFrom") == float(start.group(1))
    web = [(float(d), float(a)) for a, d in re.findall(r"rgba\(255, 255, 255, ([0-9.]+)\) ([0-9.]+)deg", css)]
    assert stops("sheenStops") == web


def test_the_handle_is_the_webs():
    assert number("hit") == px(PLAYER_CSS, "pl-hit")
    assert number("handleEdge") == px(APP_CSS, "app-tt-handle-edge")
    assert token(APP_CSS, "app-tt-handle-cap") == f"{round(number('handleCap') * 100)}%"
    assert "dashed" in rule(".app-tt-handle")


def test_the_look_button_is_the_webs():
    assert number("lookFace") == px(APP_CSS, "app-look-face")
    assert number("lookIcon") == px(APP_CSS, "app-look-icon")
    assert number("lookRadius") == px(THEME_CSS, "dw-radius-control")
    assert number("timeGap") == px(APP_CSS, "app-tt-time-gap")
    icons = ICONS.read_text()
    thin = re.search(r"const thin = .*?stroke-width=\"([0-9.]+)\"", icons, re.S)
    assert thin
    # the web's 24-unit grid drawn at the glyph's size
    assert abs(number("iconStroke") - float(thin.group(1)) * number("lookIcon") / 24) < 1e-9
    record = re.search(r"RecordIcon = thin\(\s*<>\s*<circle [^>]*r=\"([0-9.]+)\" />\s*<circle [^>]*r=\"([0-9.]+)\" />", icons)
    assert record and pair("recordIconRings") == (float(record.group(1)), float(record.group(2)))
    square = re.search(r"SquareIcon = thin\(<rect [^>]*width=\"([0-9.]+)\" [^>]*rx=\"([0-9.]+)\" />", icons)
    assert square and pair("squareIcon") == (float(square.group(1)), float(square.group(2)))


APP = REPO / "ios" / "App"


def braced(text: str, start: str) -> str:
    """The text from `start` to the brace closing the first one opened after it."""
    at = text.index(start)
    opened = text.index("{", at)
    depth = 0
    for i in range(opened, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[at:i + 1]
    raise AssertionError(f"{start!r} is never closed")


def test_the_scrubbers_row_never_asks_for_height():
    """The time line takes the scrubber's place in the scrubber's own row, so the turntable's swap moves no row (2.1).

    A view in that row that asks for the most height (`maxHeight: .infinity`) makes the row as flexible as the cover's
    room above it, and the column then splits its leftover height between the two: a Mac probe of the same column
    measured the room at 445 pt and the row at 66 on the cover, and both at 255.5 on the turntable - a plinth of about
    222 pt on an iPhone 16 instead of 321, and the titles jumping about 190 pt at every swap. The row's height is the
    hidden scrubber's; nothing in it may ask for more.
    """
    view = (APP / "Player" / "NowPlayingView.swift").read_text()
    row = braced(view, "ZStack {\n                ScrubberView()")
    assert "TurntableTimeLine()" in row
    assert "maxHeight" not in row
    line = braced((APP / "Player" / "Turntable" / "TurntableView.swift").read_text(), "struct TurntableTimeLine: View")
    body = line[line.index("var body"):]
    assert "maxHeight" not in body and ".infinity" in body, "wide, never tall"
