"""
The app's stylesheets at /player/ (2.0.0-player.9), read as rules: what a review found drawn wrong,
each held to the fix.

- app.css is tokens only, as its header says: a raw length, time, line height, opacity or filter
  in a rule is a value nobody can restyle from the token layer. The pressed looks player.css
  gained with the restyle are tokens too.
- A focus ring on a row inside a grouped list (a card that clips) is drawn INSIDE the row; drawn
  outside, the card clipped it away entirely. The shelf keeps room over its tiles for theirs.
- Keyboard focus scrolls clear of the fixed chrome: the tab bar and the mini player at the bottom,
  the album page's bar at the top.
- A phone on its side gets the compact tab bar.
- Play and pause stay round (STYLE.md).
- Home's headings sit the board's 12px above their shelf; a tile's two lines sit together.
"""

import re
from pathlib import Path

PLAYER = Path(__file__).resolve().parent.parent / "interface" / "player"
THEME = Path(__file__).resolve().parent.parent / "interface" / "styles" / "theme.css"


def rules(css: str) -> list[tuple[str, str, dict[str, str]]]:
    """Every rule as (the @-rule it sits in, or '', its selector, its declarations)."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    found: list[tuple[str, str, dict[str, str]]] = []

    def walk(text: str, context: str) -> None:
        at = 0
        while True:
            opening = text.find("{", at)
            if opening == -1:
                return
            #? a statement before the block (`@import url(...);`) isn't part of its selector
            selector = text[at:opening].rsplit(";", 1)[-1].strip()
            depth, index = 1, opening + 1
            while depth:
                depth += {"{": 1, "}": -1}.get(text[index], 0)
                index += 1
            body = text[opening + 1:index - 1]
            if selector.startswith("@"):
                walk(body, selector)
            else:
                declarations = {}
                for part in body.split(";"):
                    if ":" in part:
                        name, value = part.split(":", 1)
                        declarations[name.strip()] = " ".join(value.split())
                found.append((context, selector, declarations))
            at = index

    walk(css, "")
    return found


def declarations(css: str, selector: str, context: str = "") -> dict[str, str]:
    merged: dict[str, str] = {}
    for where, found, values in rules(css):
        if where == context and selector in [part.strip() for part in found.split(",")]:
            merged.update(values)
    return merged


def tokens(css: str) -> dict[str, str]:
    """Every custom property defined on :root, outside any @-rule."""
    merged: dict[str, str] = {}
    for where, selector, values in rules(css):
        if where == "" and selector == ":root":
            merged.update({name: value for name, value in values.items() if name.startswith("--")})
    return merged


APP = (PLAYER / "app.css").read_text()
PLAYER_CSS = (PLAYER / "player.css").read_text()
THEME_CSS = THEME.read_text()
ALL_TOKENS = {**tokens(THEME_CSS), **tokens(PLAYER_CSS), **tokens(APP)}

#? a number with a unit - anything but 0 - is a raw size or time
RAW_LENGTH = re.compile(r"(?<![\w-])(?!0(?:px|em|rem|ms|s)?\b)\d*\.?\d+(px|em|rem|ms|s|vh|vw|dvh|pt)\b")
#? these take a bare number or a function, which is a value to restyle, never structure
LOOK_PROPERTIES = ("line-height", "opacity", "filter", "z-index", "font-size", "font-weight", "letter-spacing")


def test_the_apps_stylesheet_draws_only_from_tokens():
    raw = []
    for context, selector, values in rules(APP):
        if selector == ":root":
            continue  # the token layer itself
        for name, value in values.items():
            if name.startswith("--"):
                raw.append((selector, name, "a token defined outside :root"))
            elif RAW_LENGTH.search(value):
                raw.append((selector, name, value))
            elif name in LOOK_PROPERTIES and not value.startswith("var(") and value not in ("inherit", "normal"):
                raw.append((selector, name, value))
    assert raw == []


def test_the_pressed_looks_the_restyle_added_are_tokens():
    assert declarations(PLAYER_CSS, ".pl-pill.is-primary:active:not(:disabled)")["filter"] == "var(--pl-primary-pressed)"
    assert declarations(PLAYER_CSS, ".pl-album:active .pl-album-cover")["opacity"] == "var(--pl-pressed-cover)"
    assert declarations(APP, ".app-tile:active .app-tile-cover")["opacity"] == "var(--dw-pressed-cover)"
    #? one look for both covers under a finger, and the value the player always had
    assert ALL_TOKENS["--pl-pressed-cover"] == "var(--dw-pressed-cover)"
    assert ALL_TOKENS["--dw-pressed-cover"] == "0.7"
    assert ALL_TOKENS["--dw-primary-pressed"] == "brightness(0.92)"


def test_a_focus_ring_inside_a_card_that_clips_is_drawn_inside():
    assert declarations(APP, ".app-group")["overflow"] == "hidden"
    #? what sits in a grouped list, or in the tab bar's own box
    for selector in (".app-link-row:focus-visible", ".app-radio:focus-visible", ".app-tab:focus-visible"):
        assert declarations(APP, selector)["outline-offset"] == "var(--app-ring-inset)", selector
    assert ALL_TOKENS["--app-ring-inset"] == "calc(-1 * var(--app-ring))"


def test_the_shelf_keeps_room_over_its_tiles_for_their_ring():
    assert declarations(APP, ".app-tile:focus-visible")["outline-offset"] == "var(--app-ring)"
    shelf = declarations(APP, ".app-shelf")
    assert shelf["overflow-y"] == "hidden"
    top, _right, bottom, _left = shelf["padding"].split(" ")
    assert top == bottom == "var(--app-ring-room)"
    #? room for the ring's width and its gap
    assert ALL_TOKENS["--app-ring-room"] == "calc(2 * var(--app-ring))"


def test_keyboard_focus_scrolls_clear_of_the_fixed_chrome():
    page = declarations(APP, "html")
    assert page["scroll-padding-bottom"] == "var(--app-chrome-bottom)"
    assert page["scroll-padding-top"] == "var(--app-nav-clear)"
    assert declarations(APP, "html:has(.app-shell.has-mini)")["scroll-padding-bottom"] == "var(--app-chrome-bottom-mini)"
    #? the same room the page's own padding keeps, so the two can't drift apart
    assert declarations(APP, ".app-shell")["padding-bottom"] == "var(--app-chrome-bottom)"
    assert declarations(APP, ".app-shell.has-mini")["padding-bottom"] == "var(--app-chrome-bottom-mini)"
    assert "var(--app-tabbar-height)" in ALL_TOKENS["--app-chrome-bottom"]
    assert "var(--pl-mini-height)" in ALL_TOKENS["--app-chrome-bottom-mini"]
    #? the album page's sticky bar: the status bar, 4px, a tap target, 4px - as player.css draws it
    assert declarations(PLAYER_CSS, ".pl-nav-bar")["position"] == "sticky"
    assert declarations(PLAYER_CSS, ".pl-back")["min-height"] == "var(--pl-hit)"
    assert ALL_TOKENS["--app-nav-clear"] == "calc(var(--pl-safe-top) + var(--pl-gap-xs) + var(--pl-hit) + var(--pl-gap-xs))"


def test_a_phone_on_its_side_gets_the_compact_tab_bar():
    short = "@media (max-height: 500px)"
    assert declarations(APP, ":root", short)["--app-tab-item"] == "var(--dw-tab-item-compact)"
    assert declarations(APP, ".app-tab", short)["flex-direction"] == "row"
    #? everything that clears the tab bar reads the same height, so it all follows
    assert "var(--app-tab-item)" in ALL_TOKENS["--app-tabbar-height"]
    assert declarations(APP, ".app-tab")["height"] == "var(--app-tab-item)"
    assert ALL_TOKENS["--dw-tab-item-compact"] == "32px"


def test_play_and_pause_stay_round():
    assert declarations(PLAYER_CSS, ".pl-transport-button")["border-radius"] == "var(--pl-radius-round)"
    assert ALL_TOKENS["--pl-radius-round"] == "var(--dw-radius-round)"
    assert ALL_TOKENS["--dw-radius-round"] == "50%"


def test_home_sits_as_the_board_has_it():
    #? 12px from a heading to the covers: its margin plus the shelf's room over them
    assert declarations(APP, ".app-shelf-title")["margin-bottom"] == "calc(var(--app-shelf-heading-gap) - var(--app-ring-room))"
    assert ALL_TOKENS["--app-shelf-heading-gap"] == "12px"
    #? a tile's two lines are one block, with nothing between them
    text = declarations(APP, ".app-tile-text")
    assert text["display"] == "flex" and "gap" not in text
    home = (Path(__file__).resolve().parent.parent / "ui" / "src" / "app" / "Home.tsx").read_text()
    assert re.search(r'<span class="app-tile-text">\s*<span class="app-tile-title">.*?</span>\s*'
                     r'<span class="app-tile-artist">.*?</span>\s*</span>', home, re.S)


def test_the_reader_reads_rules_as_the_browser_would():
    css = "@import url('a.css'); /* a { b: c } */ .x, .y { color: red; margin: 0 } @media (max-height: 500px) { :root { --t: 1px } }"
    assert rules(css) == [("", ".x, .y", {"color": "red", "margin": "0"}),
                          ("@media (max-height: 500px)", ":root", {"--t": "1px"})]
    assert RAW_LENGTH.search("calc(100% - 4px)") and not RAW_LENGTH.search("0 var(--a)")
    assert not RAW_LENGTH.search("var(--dw-tab-item-2px)")
