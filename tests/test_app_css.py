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

And for what opens over Now Playing (2.0.0-player.10):

- Each sheet - Now Playing, its ••• menu, Info - has its own scroll lock on <html>.
- Info's scroller says its touches pan: Now Playing, and the layer Info sits in, take every touch.
- Info's top edge is where its board puts it, or just under the status bar where that is lower.
- The menu and Info stack over Now Playing, and are placed clear of a notch, never padded by it.
- Now Playing lost its readouts and its switch; its icon row is one fixed height, so AirPlay coming
  and going moves nothing above it.
- A control drawn smaller than a tap target (the album line, a segmented control's half) reaches
  past its own box to 44px - without reaching the scrubber's own target.
- Gapless is a checkbox: a square box, not a pill.
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


def px(token: str) -> float:
    """A token that is a plain px length, as a number."""
    value = ALL_TOKENS[token]
    assert value.endswith("px"), (token, value)
    return float(value[:-2])


def test_each_sheet_has_its_own_scroll_lock():
    assert declarations(PLAYER_CSS, "html.pl-sheet-open")["overflow"] == "hidden"
    for lock in ("html.app-menu-open", "html.app-info-open"):
        assert declarations(APP, lock)["overflow"] == "hidden", lock
    #? the classes the sheets put on <html> are exactly these three
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    sheets = {"player/NowPlaying.tsx": "pl-sheet-open", "app/ActionMenu.tsx": "app-menu-open", "app/InfoSheet.tsx": "app-info-open"}
    for file, lock in sheets.items():
        assert f"lockClass: '{lock}'" in (ui / file).read_text(), file


def test_infos_scroller_opts_out_of_now_playings_touch_action():
    assert declarations(PLAYER_CSS, ".pl-sheet")["touch-action"] == "none"
    #? the layer Info and the menu sit in takes every touch too, so none pans the page behind...
    assert declarations(APP, ".app-layer")["touch-action"] == "none"
    #? ...and the one scroller in it opts out: a scroller starts its own count
    scroller = declarations(APP, ".app-info-scroll")
    assert scroller["touch-action"] == "pan-y"
    assert scroller["overflow-y"] == "auto" and scroller["overflow-x"] == "hidden"
    assert scroller["overscroll-behavior"] == "contain"
    assert scroller["min-height"] == "0"  # a flex child that can shrink below its content, so it scrolls


def test_info_starts_where_its_board_does_or_under_the_status_bar():
    assert declarations(APP, ".app-info")["top"] == "max(var(--app-info-top), calc(var(--pl-safe-top) + var(--app-info-pad)))"
    assert ALL_TOKENS["--app-info-top"] == "52px"  # from the top of the screen, as NowPlayingInfo's board draws it


def test_the_menu_and_info_are_placed_clear_of_the_notch_not_padded_by_it():
    #? capped and centred, a phone on its side has them well clear of the notch already: the
    #? insets place them (as the mini player is placed), and their padding is the board's alone
    for sheet in (".app-menu", ".app-info"):
        found = declarations(APP, sheet)
        assert (found["left"], found["right"]) == ("var(--pl-safe-left)", "var(--pl-safe-right)"), sheet
        assert found["max-width"] == "var(--pl-content-max)" and found["margin"] == "0 auto", sheet
        assert not re.search(r"--pl-safe-(left|right)|--app-edge-grouped", found["padding"]), (sheet, found["padding"])
    assert declarations(APP, ".app-info")["padding"] == "var(--app-info-pad) var(--dw-gutter-grouped) 0"
    assert declarations(APP, ".app-menu")["padding"].startswith("var(--app-info-pad) var(--app-info-pad) ")


def test_the_menu_and_info_stack_over_now_playing():
    assert declarations(APP, ".app-layer")["z-index"] == "var(--app-z-over)"
    assert int(ALL_TOKENS["--app-z-over"]) > int(declarations(PLAYER_CSS, ".pl-sheet")["z-index"])
    #? hidden while closed, and until the slide down has finished
    assert declarations(APP, ".app-layer")["visibility"] == "hidden"
    assert declarations(APP, ".app-layer.is-open")["visibility"] == "visible"


def test_now_playing_has_no_readouts_or_switch_and_a_fixed_icon_row():
    selectors = {selector for _, found, _ in rules(PLAYER_CSS) for selector in found.split(",")}
    assert not [selector for selector in selectors if re.search(r"pl-readouts|pl-gapless|pl-switch", selector)]
    assert not [token for token in ALL_TOKENS if token.startswith("--pl-switch")]
    footer = declarations(PLAYER_CSS, ".pl-sheet-footer")
    assert footer["height"] == "var(--pl-hit)" and "min-height" not in footer
    assert footer["justify-content"] == "flex-end"  # ••• at the right end, AirPlay beside it


def test_a_small_control_reaches_a_full_tap_target_without_reaching_the_scrubber():
    hit = px("--pl-hit")
    #? the album line: its reach up and down, and its own line (17px at the token's leading)
    line = px("--dw-text-body") * float(ALL_TOKENS["--pl-byline-leading"])
    assert px("--pl-byline-reach-up") + line + px("--pl-byline-reach-down") >= hit
    assert px("--pl-byline-reach-down") < px("--pl-scrub-gap")
    reach = declarations(PLAYER_CSS, ".pl-sheet-artist.is-link::before")
    assert reach["top"] == "calc(-1 * var(--pl-byline-reach-up))" and reach["bottom"] == "calc(-1 * var(--pl-byline-reach-down))"
    #? the ellipsis is on the span inside, so clipping can't cut the reach away
    assert "overflow" not in declarations(PLAYER_CSS, ".pl-sheet-artist")
    assert declarations(PLAYER_CSS, ".pl-sheet-byline")["overflow"] == "hidden"
    #? a segmented control's half: 32px drawn, 44 to a finger, with room above it for the reach.
    #? The reach is placed against the HALF'S padding box (every box is border-box), which sits
    #? the well's border and padding and the half's own border inside the well's outside
    well, half = declarations(APP, ".app-segmented"), declarations(APP, ".app-segment")
    hairline = px("--dw-hairline")
    assert well["padding"] == "var(--dw-hairline)" and well["border"].startswith("var(--dw-hairline) ")
    assert half["border"].startswith("var(--dw-hairline) ")
    assert "*, *::before, *::after" in PLAYER_CSS and "box-sizing: border-box" in PLAYER_CSS
    padding_box = px("--dw-segmented") - 2 * (hairline + hairline) - 2 * hairline
    assert ALL_TOKENS["--app-segment-edge"] == "calc(3 * var(--dw-hairline))"
    edge = 3 * hairline
    assert padding_box + 2 * edge == px("--dw-segmented")  # the edge is exactly the well's inset
    reach = declarations(APP, ".app-segment::before")
    out = "calc(-1 * (var(--app-segment-reach) + var(--app-segment-edge)))"
    assert reach["top"] == out and reach["bottom"] == out
    assert padding_box + 2 * (px("--app-segment-reach") + edge) >= hit
    #? ...and past the well by the reach alone, which the margin above it leaves room for
    assert well["margin-top"] == "var(--app-segment-reach)"


def test_gapless_is_a_checkbox_not_a_switch():
    box = declarations(APP, ".app-checkbox")
    assert box["border-radius"] == "var(--dw-radius-tag)"
    assert box["width"] == box["height"] == "var(--dw-checkbox)"
    assert declarations(APP, ".app-check-row")["min-height"] == "var(--dw-row)"

