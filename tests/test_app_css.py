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

And for the Requests tab and Home's Arriving (2.0.0-player.12):

- Every control is a tap target to a finger, drawn at the board's size inside it: the ✕ (a 32px
  box in 44px), Next peer and Ask again (36px, reaching 44 - which nothing may clip), Clear done.
- Next peer and Ask again stack where a pair wouldn't hold their words whole (a 320px phone).
- The bar is STYLE.md's thin sunken track with the purple fill.
- The tab's count is opaque over the icon it sits on - and beside it on a phone on its side,
  where the label is beside the icon too.
- A retry button waiting on its retry stays legible; it is aria-disabled, not disabled.
- A row being cancelled fades its cover, title and bar, never the words saying "cancelling…".
- An Arriving card's state word gives way before the album's name.

And for the Search tab and the album you don't have (2.0.0-player.13):

- The search field's text is never under 16px, or iOS zooms the page as it is tapped.
- The pressing list scrolls inside itself, over the tracklist and under the album page's bar, and
  `hidden` still hides it; it is never taller than the band between the page's bars (with the mini
  player up too), so brought into view it is all in view.
- The "N more" fold is drawn as a control (the accent), legible on the popover.
- Every pressing, the button and the "N more" fold are a tap target; so is a result's row, and its
  words give way with an ellipsis.
- A track that differs is tinted past the column without moving its number or length - green for a
  Bonus track, amber for another version or a rename.
- "Asking MusicBrainz…" stops moving for reduced motion.
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



# ---------------------------------------------------------------- the turntable (2.0.0-player.11)

def test_the_record_turns_at_33_and_a_third_and_only_when_told():
    face = declarations(APP, ".app-tt-face")
    #? one turn in --dw-record-turn, forever - but paused, where it is, until the page says spin
    assert face["animation"] == "app-tt-spin var(--dw-record-turn) linear infinite"
    assert face["animation-play-state"] == "paused"
    assert declarations(APP, ".app-tt-face.is-spinning")["animation-play-state"] == "running"
    assert declarations(APP, "to", "@keyframes app-tt-spin")["transform"] == "rotate(360deg)"
    #? stopped for good under reduced motion
    assert declarations(APP, ".app-tt-face", "@media (prefers-reduced-motion: reduce)")["animation"] == "none"
    #? its own value, never a duration reduced motion collapses to 1ms - that would spin it 1800
    #? times faster instead of stopping it
    assert ALL_TOKENS["--dw-record-turn"] == "1.8s"
    collapsed = declarations(THEME_CSS, ":root", "@media (prefers-reduced-motion: reduce)")
    assert "--dw-record-turn" not in collapsed and "--duration" not in ALL_TOKENS["--dw-record-turn"]


def test_the_record_and_the_arm_take_every_touch_and_the_grip_only_the_top_row():
    for selector in (".app-tt-record", ".app-tt-handle"):
        found = declarations(APP, selector)
        assert found["touch-action"] == "none", selector
        assert found["-webkit-touch-callout"] == "none" and found["user-select"] == "none", selector
    #? on the turntable the grip is the top row alone; the turntable takes the cover's room
    assert declarations(APP, ".pl-sheet-grip.app-grip-top")["flex"] == "none"
    assert declarations(APP, ".app-tt")["flex"] == "1 1 auto" and declarations(APP, ".app-tt")["min-height"] == "0"
    #? the drawing's layers take no touch, so a press lands on the record or the arm's handle
    assert declarations(APP, ".app-tt-layer")["pointer-events"] == "none"
    assert declarations(APP, ".app-tt-sheen")["pointer-events"] == "none"
    #? the arm's handle is a tap target at the least - but never more than a share of the plinth:
    #? on a phone on its side the plinth can be 45px, and a 44px ring covered most of the record,
    #? its middle included, so a tap or a turn there took the arm
    assert declarations(APP, ".app-tt-handle")["min-width"] == "min(var(--pl-hit), var(--app-tt-handle-cap))"
    assert ALL_TOKENS["--app-tt-handle-cap"] == "30%"
    assert ALL_TOKENS["--pl-hit"] == "44px"  # the cap bites only on a plinth under about 147px


def test_a_failure_line_on_the_turntable_moves_nothing_a_finger_goes_to():
    """A failure comes and goes (the skipped-song note clears itself), and on the turntable the
    room above the song's name is the record and the arm: taking its line from there resized and
    moved them under a finger. So there it is laid over the plinth's foot, out of the flow."""
    error = declarations(APP, ".app-is-turntable .pl-sheet-error")
    assert error["position"] == "absolute" and error["bottom"] == "100%"
    assert error["left"] == error["right"] == "0"
    assert declarations(APP, ".app-is-turntable .pl-sheet-titles")["position"] == "relative"
    #? two lines at most, and a press through it reaches what is under it
    assert error["-webkit-line-clamp"] == "2" and error["overflow"] == "hidden"
    assert error["pointer-events"] == "none"


def test_the_look_button_is_a_tap_target_and_the_time_line_one_line():
    button = declarations(APP, ".app-look-button")
    assert button["width"] == button["height"] == "var(--pl-hit)"
    assert ALL_TOKENS["--app-look-face"] == "36px"  # the boards' drawn box, inside the 44px target
    time = declarations(APP, ".app-tt-time")
    assert time["white-space"] == "nowrap" and time["overflow"] == "hidden"
    assert time["font-family"] == "var(--dw-font-mono)"


# ------------------------------------------------- the Requests tab and Arriving (2.0.0-player.12)

def test_the_requests_tabs_controls_are_a_tap_target_to_a_finger():
    cancel = declarations(APP, ".app-job-cancel")
    assert cancel["width"] == cancel["height"] == "var(--pl-hit)"
    #? the board's 32px box inside it, the target reaching into the card's padding
    assert declarations(APP, ".app-job-cancel-face")["width"] == "var(--app-job-cancel-face)"
    assert ALL_TOKENS["--app-job-cancel-face"] == "32px"
    assert cancel["margin-right"] == "var(--app-job-cancel-bleed)"
    assert ALL_TOKENS["--app-job-cancel-bleed"] == "calc((var(--app-job-cancel-face) - var(--pl-hit)) / 2)"
    #? Next peer and Ask again are drawn 36px, as the board has them, and reach 44 above and below:
    #? the ::before sits against the button's padding box, inside its border, so the reach is half
    #? the difference plus that border
    action = declarations(APP, ".app-job-action")
    assert action["height"] == "var(--app-job-action)" and action["position"] == "relative"
    reach = declarations(APP, ".app-job-action::before")
    assert reach["top"] == reach["bottom"] == "calc(-1 * var(--app-job-action-reach))"
    assert ALL_TOKENS["--app-job-action-reach"] == "calc((var(--pl-hit) - var(--app-job-action)) / 2 + var(--dw-hairline))"
    assert action["border"].startswith("var(--dw-hairline) ")
    assert ALL_TOKENS["--app-job-action"] == "36px"
    #? ...and nothing clips that reach: the button is its ::before's containing block, so an
    #? overflow of its own cut the 44px back to 36. The ellipsis is on the label inside it.
    assert "overflow" not in action and "text-overflow" not in action
    label = declarations(APP, ".app-job-action-label")
    assert (label["overflow"], label["text-overflow"], label["white-space"]) == ("hidden", "ellipsis", "nowrap")
    #? Clear done and See all are text buttons a target tall, with no padding pushing them in
    assert declarations(APP, ".app-text-button")["min-height"] == "var(--dw-row)"
    assert declarations(APP, ".app-clear-done")["padding"] == declarations(APP, ".app-see-all")["padding"] == "0"
    assert declarations(APP, ".app-arriving-card")["width"] == "100%"


def test_the_bar_is_styles_thin_sunken_track_with_the_purple_fill():
    bar = declarations(APP, ".app-bar")
    assert bar["height"] == "var(--dw-bar)" and ALL_TOKENS["--dw-bar"] == "6px"
    assert (bar["background"], bar["box-shadow"], bar["border-radius"]) == (
        "var(--dw-track)", "var(--dw-track-inset)", "var(--dw-radius-track)")
    fill = declarations(APP, ".app-bar-fill")
    assert (fill["background"], fill["border-radius"]) == ("var(--dw-bar-purple)", "var(--dw-radius-fill)")


def test_the_tabs_count_is_opaque_over_its_icon():
    badge = declarations(APP, ".app-tab-badge")
    assert badge["position"] == "absolute" and declarations(APP, ".app-tab-art")["position"] == "relative"
    #? STYLE.md's translucent purple badge, laid over the tab bar's own colour
    assert badge["background"] == "linear-gradient(var(--dw-badge-purple-bg), var(--dw-badge-purple-bg)), var(--dw-tab-bar)"
    assert badge["border-radius"] == "var(--dw-radius-control)"


def test_a_retry_button_waiting_on_its_retry_stays_legible():
    #? its words say what it is doing, so it fades less than player.css's 0.4 for a disabled button -
    #? and it is aria-disabled, not disabled (a disabled button drops the focus on it), so its rule
    #? can't hang off :disabled
    assert declarations(PLAYER_CSS, "button:disabled")["opacity"] == "0.4"
    assert declarations(APP, ".app-job-action.is-busy")["opacity"] == "var(--app-job-busy)"
    assert declarations(APP, ".app-job-action.is-busy:disabled") == {}
    assert float(ALL_TOKENS["--app-job-busy"]) > 0.4
    #? a pressed look only while the button takes taps
    assert "filter" in declarations(APP, ".app-job-action.is-primary:active:not([aria-disabled='true'])")
    #? and the screen's one solid purple button is the primary class alone
    assert declarations(APP, ".app-job-action.is-primary")["background"] == "var(--dw-primary-bg)"
    assert declarations(APP, ".app-job-action.is-tinted")["background"] == "var(--dw-toggled-bg)"


def test_next_peer_and_ask_again_stack_where_a_pair_wouldnt_hold_their_words():
    #? at 320px a column was 105px of text, and "Next peer · 2 left" (121px of 15px Noto Sans 600)
    #? lost its count to the ellipsis; a column narrower than "Next peer · 10 left" whole stacks
    actions = declarations(APP, ".app-job-actions")
    assert actions["grid-template-columns"] == "repeat(auto-fit, minmax(min(var(--app-job-action-min), 100%), 1fr))"
    assert ALL_TOKENS["--app-job-action-min"] == "150px"
    #? stacked, the two reaches don't overlap
    assert actions["gap"] == "var(--app-job-actions-row-gap) var(--app-job-gap)"
    assert ALL_TOKENS["--app-job-actions-row-gap"] == "calc(2 * var(--app-job-action-reach))"


def test_a_row_being_cancelled_keeps_its_words_legible():
    #? the whole card at 0.55 put "cancelling…" (--dw-text-2 on the card) at 2.7:1
    assert "opacity" not in declarations(APP, ".app-job.is-dimmed")
    faded = [selector for _context, selector, values in rules(APP) if "is-dimmed" in selector and "opacity" in values]
    parts = {part.strip() for selector in faded for part in selector.split(",")}
    assert parts == {".app-job.is-dimmed .app-job-cover", ".app-job.is-dimmed .app-job-title",
                     ".app-job.is-dimmed .app-bar", ".app-job.is-downloading.is-dimmed .app-job-line"}
    #? a Waiting card's line, and a Downloading card's data, are where "cancelling…" is said


def test_the_tabs_count_goes_beside_the_icon_on_a_phone_on_its_side():
    #? the label is beside the icon there, and a count over the icon's corner ran over its first letters
    short = "@media (max-height: 500px)"
    assert declarations(APP, ".app-tab-badge", short)["position"] == "static"
    assert declarations(APP, ".app-tab-art", short)["display"] == "flex"
    assert declarations(APP, ".app-tab-art", short)["gap"] == "var(--app-tab-badge-gap)"


def test_an_arriving_cards_state_word_gives_way_before_the_albums_name():
    brief = declarations(APP, ".app-job-brief")
    assert brief["flex"] == "0 1 auto" and brief["min-width"] == "0" and brief["text-overflow"] == "ellipsis"
    assert declarations(APP, ".app-arriving-card .app-job-body")["min-width"] == "var(--app-arriving-body-min)"


def test_the_requests_tabs_live_region_is_read_and_not_drawn():
    hidden = declarations(APP, ".app-visually-hidden")
    assert (hidden["position"], hidden["overflow"], hidden["clip-path"]) == ("absolute", "hidden", "inset(50%)")


# ---------------------------------------------------------------- Search and the album you don't have

def test_the_search_field_is_never_small_enough_for_ios_to_zoom():
    field = declarations(APP, ".app-search-input")
    assert field["font-size"] == "var(--dw-text-body)" and px("--dw-text-body") >= 16
    #? the well is STYLE.md's; nothing native is drawn over it
    assert field["appearance"] == "none"


def test_the_pressing_list_scrolls_inside_itself_over_the_tracklist():
    popover = declarations(APP, ".app-picker-popover")
    assert (popover["position"], popover["overflow-y"], popover["overflow-x"], popover["overscroll-behavior"]) == (
        "absolute", "auto", "hidden", "contain")
    assert popover["max-height"] == "max(var(--app-picker), min(var(--app-picker-max), var(--app-picker-band)))"
    #? over the tracklist, under the album page's sticky bar
    assert int(ALL_TOKENS["--app-z-popover"]) < int(declarations(PLAYER_CSS, ".pl-nav-bar")["z-index"])
    #? `hidden` must still hide it: nothing gives it a display of its own
    assert "display" not in popover


def test_the_pressing_list_fits_between_the_pages_bars():
    """It opens downward; brought into view (scrollIntoView, which keeps the page's scroll-padding
    clear) it must fit the band that padding leaves, or part of it stays under the mini player."""
    page = declarations(APP, "html")
    assert (page["scroll-padding-top"], page["scroll-padding-bottom"]) == ("var(--app-nav-clear)", "var(--app-chrome-bottom)")
    assert ALL_TOKENS["--app-picker-band"] == "calc(100dvh - var(--app-nav-clear) - var(--app-chrome-bottom))"
    assert declarations(APP, "html:has(.app-shell.has-mini)")["scroll-padding-bottom"] == "var(--app-chrome-bottom-mini)"
    assert ALL_TOKENS["--app-picker-band-mini"] == "calc(100dvh - var(--app-nav-clear) - var(--app-chrome-bottom-mini))"
    assert declarations(APP, ".app-shell.has-mini .app-picker-popover")["max-height"] == (
        "max(var(--app-picker), min(var(--app-picker-max), var(--app-picker-band-mini)))")


def test_the_fold_is_drawn_as_a_control_and_legible():
    assert declarations(APP, ".app-picker-more")["color"] == "var(--dw-accent)"
    #? the app's text buttons are the accent too
    assert declarations(APP, ".app-text-button")["color"] == "var(--dw-accent)"


def test_every_pressing_and_the_fold_are_a_tap_target():
    assert px("--app-picker") >= px("--pl-hit")
    assert declarations(APP, ".app-picker-option")["min-height"] == "var(--app-picker)"
    assert declarations(APP, ".app-picker-button")["min-height"] == "var(--app-picker)"
    assert declarations(APP, ".app-picker-more")["min-height"] == "var(--pl-hit)"


def test_a_row_of_search_results_is_a_tap_target_and_its_words_give_way():
    assert px("--app-result") >= px("--pl-hit") and px("--app-rg-row") >= px("--pl-hit")
    assert declarations(APP, ".app-result")["min-height"] == "var(--app-result)"
    assert declarations(APP, ".app-result-text")["min-width"] == "0"
    for selector in (".app-result-title", ".app-result-line", ".app-rg-title", ".app-picker-value"):
        found = declarations(APP, selector)
        assert found["text-overflow"] == "ellipsis" and found["white-space"] == "nowrap", selector


def test_a_marked_tracks_tint_reaches_past_the_column_without_moving_it():
    marked = declarations(APP, ".app-rg-track.is-marked")
    assert marked["margin"] == "0 calc(-1 * var(--app-rg-mark-bleed))"
    assert marked["padding"] == "var(--app-rg-mark-pad) var(--app-rg-mark-bleed)"
    #? green for a Bonus track, amber for another version or a rename - STYLE.md's badges
    assert declarations(APP, ".app-rg-track.is-bonus")["background"] == "var(--dw-tint-green)"
    assert declarations(APP, ".app-rg-track.is-version")["background"] == "var(--dw-tint-amber)"
    assert declarations(APP, ".app-rg-track.is-renamed")["background"] == "var(--dw-tint-amber)"
    assert declarations(APP, ".app-rg-track.is-bonus .app-rg-chip")["color"] == "var(--dw-badge-green-text)"
    assert declarations(APP, ".app-rg-chip")["color"] == "var(--dw-amber-text)"
    assert declarations(APP, ".app-rg-number")["text-align"] == "right"


def test_asking_musicbrainz_stops_moving_for_reduced_motion():
    assert "app-sweep" in declarations(APP, ".app-sweep::before")["animation"]
    assert declarations(APP, ".app-sweep::before", "@media (prefers-reduced-motion: reduce)")["animation"] == "none"
    assert declarations(APP, ".app-sweep")["overflow"] == "hidden"
