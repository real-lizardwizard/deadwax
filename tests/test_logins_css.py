"""
The sign-in screen's stylesheet (2.0.0-player.48, interface/player/signin.css), read as rules - held to
app.css's own rule, and to what the screen has to be:

- tokens only: no raw length, time, line height, opacity, filter or z-index in a rule, and every token
  a rule reads defined somewhere the page loads;
- the fields' text never under 16px, or iOS zooms the page into a field as it is tapped;
- over everything the app draws - the desktop's visualizer and the pin notice included;
- the page behind held still while it is up, its own box scrolling;
- clear of the notch and the home bar (the home-screen app), and a card centred by its margins, so a
  card taller than a short screen still scrolls to its top;
- linked by the app's page only with logins on (the page is otherwise exactly what it was), after
  app.css, whose classes (the avatar, the error, a row) it builds on.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_app_css import APP, LOOK_PROPERTIES, PLAYER, PLAYER_CSS, RAW_LENGTH, THEME_CSS, declarations, rules, tokens  # noqa: E402

SIGNIN = (PLAYER / "signin.css").read_text()
DESK = (PLAYER / "app-desktop.css").read_text()
TOKENS = {**tokens(THEME_CSS), **tokens(PLAYER_CSS), **tokens(APP), **tokens(SIGNIN)}


def resolved(value: str) -> str:
    while (found := re.fullmatch(r"var\((--[\w-]+)\)", value.strip())):
        value = TOKENS[found.group(1)]
    return value


def test_the_sign_in_stylesheet_draws_only_from_tokens():
    raw = []
    for _context, selector, values in rules(SIGNIN):
        if selector == ":root":
            continue
        for name, value in values.items():
            if name.startswith("--"):
                raw.append((selector, name, "a token defined outside :root"))
            elif RAW_LENGTH.search(value):
                raw.append((selector, name, value))
            elif name in LOOK_PROPERTIES and not value.startswith("var(") and value not in ("inherit", "normal"):
                raw.append((selector, name, value))
    assert raw == []


def test_every_token_it_reads_is_defined():
    read = {name for _c, _s, values in rules(SIGNIN) for value in values.values() for name in re.findall(r"var\((--[\w-]+)\)", value)}
    assert sorted(read - set(TOKENS)) == []


def test_the_fields_text_is_never_small_enough_for_ios_to_zoom():
    size = resolved(declarations(SIGNIN, ".app-signin-field")["font-size"])
    assert size.endswith("px") and float(size[:-2]) >= 16


def test_the_screen_is_over_everything_the_app_draws():
    mine = int(resolved(declarations(SIGNIN, ".app-signin")["z-index"]))
    others = {name: value for css in (APP, DESK) for _c, _s, values in rules(css)
              for name, value in values.items() if name.startswith("--app-z-")}
    assert others and all(mine > int(value) for value in others.values()), others


def test_the_page_behind_holds_still_and_the_screen_scrolls_itself():
    assert declarations(SIGNIN, "html.has-signin")["overflow"] == "hidden"
    screen = declarations(SIGNIN, ".app-signin")
    assert screen["position"] == "fixed" and screen["inset"] == "0"
    assert screen["overflow-y"] == "auto" and screen["overscroll-behavior"] == "contain"


def test_it_keeps_clear_of_the_notch_and_centres_by_its_margins():
    padding = declarations(SIGNIN, ".app-signin")["padding"]
    for side in ("top", "right", "bottom", "left"):
        assert f"var(--pl-safe-{side})" in padding, side
    card = declarations(SIGNIN, ".app-signin-card")
    assert card["margin"] == "auto" and card["width"] == "100%"
    assert "align-items" not in declarations(SIGNIN, ".app-signin")


def test_the_app_page_links_it_only_with_logins_on_after_app_css(monkeypatch):
    """With logins off the app's page is exactly what it was; on, the sign-in's sheet comes after app.css."""
    from fastapi.testclient import TestClient

    from src.api.app import SIGNIN_SHEET, start
    from src.config import Config

    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    assert "signin.css" not in TestClient(start()).get("/player/").text
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    client = TestClient(start())
    page = client.get("/player/").text
    assert page.index('href="/player/app.css') < page.index('href="/player/signin.css?v=')
    #? the test bench doesn't draw the sign-in screen, so doesn't load its sheet (`/` is the app since 2.0.0-player.66)
    assert "signin.css" not in client.get("/player/lab/").text
    assert SIGNIN_SHEET == '<link rel="stylesheet" href="/player/signin.css">'
